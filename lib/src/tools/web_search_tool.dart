// Web search tool using default free provider (DuckDuckGo).

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/cancellation.dart';
import 'tool_context.dart';

mixin WebSearchTool on ToolContext {
  Future<Map<String, Object?>> searchWeb(
    String query, {
    String? recency,
    int? limit,
    CancellationToken? cancellationToken,
  }) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      throw ToolFailure('Search query is required');
    }

    final maxResults = (limit ?? 10).clamp(1, 20);
    cancellationToken?.throwIfCancelled();

    final bodyFields = <String, String>{
      'q': trimmedQuery,
      'b': '',
      'kl': 'us-en',
    };
    if (recency != null) {
      final df = switch (recency.toLowerCase()) {
        'day' => 'd',
        'week' => 'w',
        'month' => 'm',
        'year' => 'y',
        _ => null,
      };
      if (df != null) bodyFields['df'] = df;
    }

    final http.Response response;
    try {
      response = await httpClient
          .post(
            Uri.parse('https://html.duckduckgo.com/html/'),
            headers: const {
              'Content-Type': 'application/x-www-form-urlencoded',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Referer': 'https://html.duckduckgo.com/',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            },
            body: bodyFields,
          )
          .timeout(const Duration(seconds: 30));
    } on SocketException catch (e) {
      throw ToolFailure('Failed to connect to search provider: ${e.message}');
    } on TimeoutException {
      throw ToolFailure('Web search timed out after 30 seconds');
    } catch (e) {
      throw ToolFailure('Web search request failed: $e');
    }

    cancellationToken?.throwIfCancelled();

    if (response.statusCode != 200) {
      throw ToolFailure('Web search failed: HTTP ${response.statusCode}');
    }

    final html = response.body;
    if (html.contains('anomaly-modal') || html.contains('anomaly.js')) {
      throw ToolFailure(
        'DuckDuckGo search rate limit reached or challenge detected.',
      );
    }

    final sources = _parseDuckDuckGoResults(html, maxResults: maxResults);
    final formattedResults = _formatSearchSourcesForLLM(sources);

    return {
      'query': trimmedQuery,
      'provider': 'duckduckgo',
      'totalResults': sources.length,
      'sources': sources,
      'results': formattedResults,
    };
  }

  List<Map<String, String>> _parseDuckDuckGoResults(
    String html, {
    required int maxResults,
  }) {
    final results = <Map<String, String>>[];
    final seenUrls = <String>{};

    final blockRegex = RegExp(
      r'<div\b[^>]*\bclass="[^"]*\bresult(?:__body)?\b[^"]*"[^>]*>([\s\S]*?)(?=<div\b[^>]*\bclass="[^"]*\bresult(?:__body)?\b|<div\b[^>]*\bclass="[^"]*\bnav-link\b|$)',
      caseSensitive: false,
    );
    final titleRegex = RegExp(
      r'<a\b[^>]*\bclass="[^"]*\bresult__a\b[^"]*"[^>]*\bhref="([^"]+)"[^>]*>([\s\S]*?)<\/a>',
      caseSensitive: false,
    );
    final snippetRegex = RegExp(
      r'<(?:a|div|span)\b[^>]*\bclass="[^"]*\bresult__snippet\b[^"]*"[^>]*>([\s\S]*?)<\/(?:a|div|span)>',
      caseSensitive: false,
    );

    for (final match in blockRegex.allMatches(html)) {
      if (results.length >= maxResults) break;
      final block = match.group(1)!;

      final titleMatch = titleRegex.firstMatch(block);
      if (titleMatch == null) continue;

      final rawHref = titleMatch.group(1)!;
      final rawTitle = titleMatch.group(2)!;
      final url = _unwrapDuckDuckGoUrl(rawHref);
      if (url == null || seenUrls.contains(url)) continue;

      final title = _decodeHtml(rawTitle);
      if (title.isEmpty) continue;

      final snippetMatch = snippetRegex.firstMatch(block);
      final snippet = snippetMatch != null
          ? _decodeHtml(snippetMatch.group(1)!)
          : '';

      seenUrls.add(url);
      results.add({
        'title': title,
        'url': url,
        if (snippet.isNotEmpty) 'snippet': snippet,
      });
    }

    return results;
  }

  String? _unwrapDuckDuckGoUrl(String href) {
    var raw = href.replaceAll('&amp;', '&');
    final uddgMatch = RegExp(r'[?&]uddg=([^&]+)').firstMatch(raw);
    if (uddgMatch != null) {
      try {
        return Uri.decodeComponent(uddgMatch.group(1)!);
      } catch (_) {}
    }
    if (raw.startsWith('//')) return 'https:$raw';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return null;
  }

  String _decodeHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&hellip;', '…')
        .replaceAllMapped(
          RegExp(r'&#(\d+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!)),
        )
        .replaceAllMapped(
          RegExp(r'&#x([0-9a-fA-F]+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _formatSearchSourcesForLLM(List<Map<String, String>> sources) {
    if (sources.isEmpty) return 'No search results found.';
    final buffer = StringBuffer('## Sources\n');
    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      buffer.writeln('[${i + 1}] ${source['title']}');
      buffer.writeln('    ${source['url']}');
      if (source['snippet'] != null && source['snippet']!.isNotEmpty) {
        buffer.writeln('    ${source['snippet']}');
      }
    }
    return buffer.toString().trim();
  }
}
