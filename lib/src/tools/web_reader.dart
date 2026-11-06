// Web reader with anti-bot user-agent rotation, specialized scrapers, and reader fallback.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'pdf_parser.dart';

class WebReadResult {
  const WebReadResult({
    required this.url,
    required this.finalUrl,
    required this.contentType,
    required this.content,
    this.rawBytes,
    this.isImage = false,
    this.isPdf = false,
    this.notes = const [],
  });

  final String url;
  final String finalUrl;
  final String contentType;
  final String content;
  final List<int>? rawBytes;
  final bool isImage;
  final bool isPdf;
  final List<String> notes;
}

class ParsedUrlTarget {
  const ParsedUrlTarget({
    required this.url,
    this.startLine,
    this.endLine,
    this.tailLines,
    this.raw = false,
  });

  final String url;
  final int? startLine;
  final int? endLine;
  final int? tailLines;
  final bool raw;
}

class WebReader {
  const WebReader._();

  static const List<String> userAgents = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (compatible; TextBot/1.0)',
    'curl/8.0',
  ];

  static bool isWebUrl(String input) {
    final lower = input.trim().toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  static ParsedUrlTarget parseUrlTarget(String input) {
    var rawUrl = input.trim();
    var raw = false;
    int? startLine;
    int? endLine;
    int? tailLines;

    // Check for trailing :raw or :N-M selector
    final selectorRegex = RegExp(
      r':(raw|\d+(?:-\d+)?|-\d+)$',
      caseSensitive: false,
    );
    final match = selectorRegex.firstMatch(rawUrl);
    if (match != null) {
      final token = match.group(1)!.toLowerCase();
      rawUrl = rawUrl.substring(0, match.start);
      if (token == 'raw') {
        raw = true;
      } else if (token.startsWith('-')) {
        tailLines = int.tryParse(token.substring(1));
      } else if (token.contains('-')) {
        final parts = token.split('-');
        startLine = int.tryParse(parts[0]);
        endLine = int.tryParse(parts[1]);
      } else {
        startLine = int.tryParse(token);
        endLine = startLine;
      }
    }

    return ParsedUrlTarget(
      url: rawUrl,
      startLine: startLine,
      endLine: endLine,
      tailLines: tailLines,
      raw: raw,
    );
  }

  static Future<WebReadResult> fetchUrl(
    String targetUrl, {
    bool raw = false,
    http.Client? client,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final uri = Uri.tryParse(targetUrl);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      throw FormatException('Invalid web URL: $targetUrl');
    }

    final httpClient = client ?? http.Client();
    final notes = <String>[];

    // Step 1: Specialized site scrapers (unless raw mode)
    if (!raw) {
      final specialResult = await _handleSpecialSites(
        uri,
        httpClient,
        timeout,
        notes,
      );
      if (specialResult != null) return specialResult;
    }

    // Step 2: Fetch page with user agent rotation
    http.Response? response;
    String? lastError;

    for (final ua in userAgents) {
      try {
        final resp = await httpClient
            .get(
              uri,
              headers: {
                'User-Agent': ua,
                'Accept':
                    'text/html,application/xhtml+xml,application/xml;q=0.9,text/plain,*/*;q=0.8',
              },
            )
            .timeout(timeout);

        if (resp.statusCode == 200) {
          response = resp;
          break;
        } else if (resp.statusCode == 403 ||
            resp.statusCode == 429 ||
            resp.statusCode == 503) {
          lastError = 'HTTP ${resp.statusCode} with $ua';
          continue; // try next user agent
        } else {
          throw HttpException('HTTP ${resp.statusCode}', uri: uri);
        }
      } on HttpException {
        rethrow;
      } catch (e) {
        lastError = e.toString();
      }
    }

    if (response == null) {
      // Step 3: Remote reader fallback via Jina reader API on blocked or JS-heavy URLs
      if (!raw) {
        final jinaResult = await _tryJinaReader(
          targetUrl,
          httpClient,
          timeout,
          notes,
        );
        if (jinaResult != null) return jinaResult;
      }
      throw HttpException(
        'Failed to fetch $targetUrl: ${lastError ?? 'Connection failed'}',
        uri: uri,
      );
    }

    final contentType = response.headers['content-type'] ?? '';
    final mime = contentType.split(';').first.trim().toLowerCase();
    final bytes = response.bodyBytes;

    // Check if image
    if (mime.startsWith('image/')) {
      return WebReadResult(
        url: targetUrl,
        finalUrl: response.request?.url.toString() ?? targetUrl,
        contentType: mime,
        content: '[Image data: $mime, ${bytes.length} bytes]',
        rawBytes: bytes,
        isImage: true,
        notes: notes,
      );
    }

    // Check if PDF
    if (mime == 'application/pdf' ||
        targetUrl.toLowerCase().endsWith('.pdf') ||
        PdfParser.isPdfBytes(bytes)) {
      final pdfLines = PdfParser.extractTextLines(bytes);
      return WebReadResult(
        url: targetUrl,
        finalUrl: response.request?.url.toString() ?? targetUrl,
        contentType: 'application/pdf',
        content: pdfLines.join('\n'),
        rawBytes: bytes,
        isPdf: true,
        notes: notes,
      );
    }

    // Raw mode
    if (raw) {
      return WebReadResult(
        url: targetUrl,
        finalUrl: response.request?.url.toString() ?? targetUrl,
        contentType: mime,
        content: response.body,
        notes: notes,
      );
    }

    // JSON format
    if (mime.contains('json')) {
      try {
        final decoded = jsonDecode(response.body);
        final pretty = const JsonEncoder.withIndent('  ').convert(decoded);
        return WebReadResult(
          url: targetUrl,
          finalUrl: response.request?.url.toString() ?? targetUrl,
          contentType: mime,
          content: pretty,
          notes: notes,
        );
      } catch (_) {
        return WebReadResult(
          url: targetUrl,
          finalUrl: response.request?.url.toString() ?? targetUrl,
          contentType: mime,
          content: response.body,
          notes: notes,
        );
      }
    }

    // HTML format
    if (mime.contains('html') || looksLikeHtml(response.body)) {
      final markdown = convertHtmlToMarkdown(response.body, baseUrl: uri);

      // If page is an SPA shell with virtually no readable text, try Jina reader fallback
      if (markdown.trim().length < 150) {
        final jinaResult = await _tryJinaReader(
          targetUrl,
          httpClient,
          timeout,
          notes,
        );
        if (jinaResult != null &&
            jinaResult.content.trim().length > markdown.trim().length) {
          return jinaResult;
        }
      }

      return WebReadResult(
        url: targetUrl,
        finalUrl: response.request?.url.toString() ?? targetUrl,
        contentType: 'text/markdown',
        content: markdown,
        notes: notes,
      );
    }

    // Plain text or other format
    return WebReadResult(
      url: targetUrl,
      finalUrl: response.request?.url.toString() ?? targetUrl,
      contentType: mime.isNotEmpty ? mime : 'text/plain',
      content: response.body,
      notes: notes,
    );
  }

  static Future<WebReadResult?> _handleSpecialSites(
    Uri uri,
    http.Client client,
    Duration timeout,
    List<String> notes,
  ) async {
    final host = uri.host.toLowerCase();
    final path = uri.path;

    // 1. GitHub
    if (host == 'github.com') {
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.length >= 2) {
        final owner = segments[0];
        final repo = segments[1];

        // GitHub Blob -> raw content
        if (segments.length >= 5 && segments[2] == 'blob') {
          final ref = segments[3];
          final filePath = segments.sublist(4).join('/');
          final rawUrl =
              'https://raw.githubusercontent.com/$owner/$repo/$ref/$filePath';
          try {
            final resp = await client
                .get(Uri.parse(rawUrl), headers: {'User-Agent': userAgents[0]})
                .timeout(timeout);
            if (resp.statusCode == 200) {
              notes.add('Fetched raw file directly from GitHub');
              return WebReadResult(
                url: uri.toString(),
                finalUrl: rawUrl,
                contentType: resp.headers['content-type'] ?? 'text/plain',
                content: resp.body,
                notes: notes,
              );
            }
          } catch (_) {}
        }

        // GitHub Repo root -> fetch README.md
        if (segments.length == 2) {
          for (final branch in ['main', 'master']) {
            for (final readme in ['README.md', 'readme.md', 'README']) {
              final rawUrl =
                  'https://raw.githubusercontent.com/$owner/$repo/$branch/$readme';
              try {
                final resp = await client
                    .get(
                      Uri.parse(rawUrl),
                      headers: {'User-Agent': userAgents[0]},
                    )
                    .timeout(const Duration(seconds: 5));
                if (resp.statusCode == 200) {
                  notes.add('Fetched repository README directly');
                  return WebReadResult(
                    url: uri.toString(),
                    finalUrl: rawUrl,
                    contentType: 'text/markdown',
                    content: '# $owner/$repo\n\n${resp.body}',
                    notes: notes,
                  );
                }
              } catch (_) {}
            }
          }
        }
      }
    }

    // 2. pub.dev
    if (host == 'pub.dev' || host == 'www.pub.dev') {
      final match = RegExp(r'^/packages/([^/]+)').firstMatch(path);
      if (match != null) {
        final pkg = match.group(1)!;
        final apiUrl = 'https://pub.dev/api/packages/$pkg';
        try {
          final resp = await client
              .get(Uri.parse(apiUrl), headers: {'User-Agent': userAgents[0]})
              .timeout(timeout);
          if (resp.statusCode == 200) {
            final data = jsonDecode(resp.body) as Map<String, dynamic>;
            final name = data['name'];
            final latest = data['latest'] as Map<String, dynamic>? ?? {};
            final version = latest['version'];
            final pubspec = latest['pubspec'] as Map<String, dynamic>? ?? {};
            final desc = pubspec['description'] ?? '';

            final buffer = StringBuffer('# $name\n\n');
            if (desc.toString().isNotEmpty) {
              buffer.writeln('$desc\n');
            }
            buffer.writeln('**Latest Version:** $version');
            if (pubspec['homepage'] != null) {
              buffer.writeln('**Homepage:** ${pubspec['homepage']}');
            }
            if (pubspec['repository'] != null) {
              buffer.writeln('**Repository:** ${pubspec['repository']}');
            }
            notes.add('Fetched package metadata via pub.dev API');
            return WebReadResult(
              url: uri.toString(),
              finalUrl: apiUrl,
              contentType: 'text/markdown',
              content: buffer.toString().trim(),
              notes: notes,
            );
          }
        } catch (_) {}
      }
    }

    // 3. Wikipedia
    if (host.endsWith('.wikipedia.org')) {
      final lang = host.split('.').first;
      final match = RegExp(r'^/wiki/(.+)').firstMatch(path);
      if (match != null) {
        final title = match.group(1)!;
        final apiUrl =
            'https://$lang.wikipedia.org/api/rest_v1/page/summary/$title';
        try {
          final resp = await client
              .get(Uri.parse(apiUrl), headers: {'User-Agent': userAgents[0]})
              .timeout(timeout);
          if (resp.statusCode == 200) {
            final data = jsonDecode(resp.body) as Map<String, dynamic>;
            final pageTitle = data['title'] ?? title;
            final desc = data['description'] ?? '';
            final extract = data['extract'] ?? '';

            final buffer = StringBuffer('# $pageTitle\n\n');
            if (desc.toString().isNotEmpty) buffer.writeln('*$desc*\n');
            buffer.writeln(extract);
            notes.add('Extracted Wikipedia article summary via REST API');
            return WebReadResult(
              url: uri.toString(),
              finalUrl: apiUrl,
              contentType: 'text/markdown',
              content: buffer.toString().trim(),
              notes: notes,
            );
          }
        } catch (_) {}
      }
    }

    // 4. arXiv
    if (host == 'arxiv.org') {
      final match = RegExp(
        r'^/(?:abs|pdf)/([0-9\.]+)(?:\.pdf)?',
      ).firstMatch(path);
      if (match != null) {
        final paperId = match.group(1)!;
        final apiUrl = 'https://export.arxiv.org/api/query?id_list=$paperId';
        try {
          final resp = await client
              .get(Uri.parse(apiUrl), headers: {'User-Agent': userAgents[0]})
              .timeout(timeout);
          if (resp.statusCode == 200) {
            final xml = resp.body;
            final titleMatch = RegExp(
              r'<title\b[^>]*>([\s\S]*?)</title>',
            ).allMatches(xml);
            final summaryMatch = RegExp(
              r'<summary\b[^>]*>([\s\S]*?)</summary>',
            ).firstMatch(xml);
            final authorMatches = RegExp(
              r'<author>\s*<name>([\s\S]*?)</name>',
            ).allMatches(xml);

            final paperTitle = titleMatch.length > 1
                ? titleMatch
                      .elementAt(1)
                      .group(1)!
                      .trim()
                      .replaceAll(RegExp(r'\s+'), ' ')
                : 'arXiv Paper';
            final summary =
                summaryMatch
                    ?.group(1)
                    ?.trim()
                    .replaceAll(RegExp(r'\s+'), ' ') ??
                '';
            final authors = authorMatches
                .map((m) => m.group(1)!.trim())
                .toList();

            final buffer = StringBuffer('# $paperTitle\n\n');
            if (authors.isNotEmpty) {
              buffer.writeln('**Authors:** ${authors.join(', ')}\n');
            }
            buffer.writeln('**Paper ID:** $paperId\n');
            buffer.writeln(
              '**PDF Download:** https://arxiv.org/pdf/$paperId.pdf\n\n',
            );
            buffer.writeln('## Abstract\n$summary');

            notes.add('Extracted paper details via arXiv API');
            return WebReadResult(
              url: uri.toString(),
              finalUrl: apiUrl,
              contentType: 'text/markdown',
              content: buffer.toString().trim(),
              notes: notes,
            );
          }
        } catch (_) {}
      }
    }

    return null;
  }

  static Future<WebReadResult?> _tryJinaReader(
    String targetUrl,
    http.Client client,
    Duration timeout,
    List<String> notes,
  ) async {
    try {
      final jinaUri = Uri.parse('https://r.jina.ai/$targetUrl');
      final resp = await client
          .get(
            jinaUri,
            headers: {
              'User-Agent': userAgents[0],
              'Accept': 'text/markdown',
              'X-No-Cache': 'true',
            },
          )
          .timeout(timeout);

      if (resp.statusCode == 200 && resp.body.trim().isNotEmpty) {
        notes.add('Rendered through Jina reader service');
        return WebReadResult(
          url: targetUrl,
          finalUrl: jinaUri.toString(),
          contentType: 'text/markdown',
          content: resp.body.trim(),
          notes: notes,
        );
      }
    } catch (_) {}
    return null;
  }

  static bool looksLikeHtml(String text) {
    final prefix = text.trimLeft().toLowerCase();
    return prefix.startsWith('<!doctype') ||
        prefix.startsWith('<html') ||
        prefix.startsWith('<head') ||
        prefix.startsWith('<body');
  }

  static String convertHtmlToMarkdown(String html, {Uri? baseUrl}) {
    var text = html
        .replaceAll(
          RegExp(r'<script\b[^>]*>[\s\S]*?<\/script>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'<style\b[^>]*>[\s\S]*?<\/style>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(
            r'<noscript\b[^>]*>[\s\S]*?<\/noscript>',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(r'<svg\b[^>]*>[\s\S]*?<\/svg>', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

    String? title;
    final titleMatch = RegExp(
      r'<title\b[^>]*>([\s\S]*?)<\/title>',
      caseSensitive: false,
    ).firstMatch(text);
    if (titleMatch != null) {
      title = decodeHtmlEntities(titleMatch.group(1)!.trim());
    }

    for (var i = 1; i <= 6; i++) {
      final prefix = '#' * i;
      text = text.replaceAllMapped(
        RegExp('<h$i\\b[^>]*>([\\s\\S]*?)<\\/h$i>', caseSensitive: false),
        (m) =>
            '\n\n$prefix ${decodeHtmlEntities(_stripTags(m.group(1)!)).trim()}\n\n',
      );
    }

    text = text.replaceAllMapped(
      RegExp(
        r'''<a\b[^>]*\bhref\s*=\s*(?:["']([^"']*)["'])[^>]*>([\s\S]*?)<\/a>''',
        caseSensitive: false,
      ),
      (m) {
        var href = (m.group(1) ?? '').trim();
        final linkText = decodeHtmlEntities(_stripTags(m.group(2)!)).trim();
        if (linkText.isEmpty) return '';
        if (href.startsWith('/') && baseUrl != null) {
          href = baseUrl.resolve(href).toString();
        }
        if (href.startsWith('http://') || href.startsWith('https://')) {
          return '[$linkText]($href)';
        }
        return linkText;
      },
    );

    text = text.replaceAllMapped(
      RegExp(
        r'<pre\b[^>]*><code\b[^>]*>([\s\S]*?)<\/code><\/pre>',
        caseSensitive: false,
      ),
      (m) => '\n\n```\n${decodeHtmlEntities(m.group(1)!)}\n```\n\n',
    );
    text = text.replaceAllMapped(
      RegExp(r'<pre\b[^>]*>([\s\S]*?)<\/pre>', caseSensitive: false),
      (m) => '\n\n```\n${decodeHtmlEntities(m.group(1)!)}\n```\n\n',
    );
    text = text.replaceAllMapped(
      RegExp(r'<code\b[^>]*>([\s\S]*?)<\/code>', caseSensitive: false),
      (m) => '`${decodeHtmlEntities(m.group(1)!)}`',
    );

    text = text.replaceAllMapped(
      RegExp(
        r'<(?:strong|b)\b[^>]*>([\s\S]*?)<\/(?:strong|b)>',
        caseSensitive: false,
      ),
      (m) => '**${_stripTags(m.group(1)!)}**',
    );
    text = text.replaceAllMapped(
      RegExp(r'<(?:em|i)\b[^>]*>([\s\S]*?)<\/(?:em|i)>', caseSensitive: false),
      (m) => '*${_stripTags(m.group(1)!)}*',
    );

    text = text.replaceAllMapped(
      RegExp(r'<li\b[^>]*>([\s\S]*?)<\/li>', caseSensitive: false),
      (m) => '\n- ${_stripTags(m.group(1)!).trim()}',
    );

    text = text.replaceAll(RegExp(r'<br\s*\/?>', caseSensitive: false), '\n');
    text = text.replaceAllMapped(
      RegExp(r'<p\b[^>]*>([\s\S]*?)<\/p>', caseSensitive: false),
      (m) => '\n\n${m.group(1)!}\n\n',
    );
    text = text.replaceAllMapped(
      RegExp(
        r'<blockquote\b[^>]*>([\s\S]*?)<\/blockquote>',
        caseSensitive: false,
      ),
      (m) => '\n\n> ${_stripTags(m.group(1)!).trim()}\n\n',
    );
    text = text.replaceAll(
      RegExp(
        r'<\/?(?:div|section|article|nav|main|header|footer)\b[^>]*>',
        caseSensitive: false,
      ),
      '\n',
    );

    text = _stripTags(text);
    text = decodeHtmlEntities(text);

    text = text
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .join('\n');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

    if (title != null && title.isNotEmpty && !text.startsWith('# ')) {
      text = '# $title\n\n$text';
    }
    return text;
  }

  static String _stripTags(String html) =>
      html.replaceAll(RegExp(r'<[^>]*>'), '');

  static String decodeHtmlEntities(String text) {
    return text
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
        );
  }
}
