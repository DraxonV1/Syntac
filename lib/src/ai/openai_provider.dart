import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/cancellation.dart';
import 'ai_provider.dart';
import 'provider_diagnostics.dart';

class OpenAICompatibleProvider extends AIProvider {
  OpenAICompatibleProvider({
    required String baseUrl,
    http.Client? client,
    String providerName = 'provider',
  }) : _baseUri = _parseBaseUri(baseUrl),
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _providerName = providerName;

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;
  final String _providerName;

  Uri get resolvedChatCompletionsUri => _chatCompletionsUri;
  Uri get resolvedModelsUri => _modelsUri;

  Uri get _chatCompletionsUri =>
      _baseUri.replace(path: _openAIPath(_baseUri.path, 'chat/completions'));
  Uri get _modelsUri =>
      _baseUri.replace(path: _openAIPath(_baseUri.path, 'models'));

  Future<void> testConnection({required String apiKey}) async {
    try {
      final response = await _client
          .get(_modelsUri, headers: _headers(apiKey))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _errorFromResponse(
          response.statusCode,
          response.body,
          _modelsUri,
          'GET',
          '',
        );
      }
    } on TimeoutException {
      throw const AIProviderException(
        'Provider request timed out',
        kind: 'timeout',
      );
    } on AIProviderException {
      rethrow;
    } catch (error) {
      throw _transportException(error, _modelsUri);
    }
  }

  Future<List<String>> discoverModels({required String apiKey}) async {
    try {
      final response = await _client
          .get(_modelsUri, headers: _headers(apiKey))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _errorFromResponse(
          response.statusCode,
          response.body,
          _modelsUri,
          'GET',
          '',
        );
      }
      final decoded = jsonDecode(response.body);
      final List<String> models = [];
      if (decoded is Map && decoded['data'] is List) {
        for (final item in decoded['data'] as List) {
          if (item is Map && item['id'] is String) {
            models.add(item['id'] as String);
          } else if (item is String) {
            models.add(item);
          }
        }
      } else if (decoded is List) {
        for (final item in decoded) {
          if (item is Map && item['id'] is String) {
            models.add(item['id'] as String);
          } else if (item is String) {
            models.add(item);
          }
        }
      }
      return models;
    } on TimeoutException {
      throw const AIProviderException(
        'Provider request timed out',
        kind: 'timeout',
      );
    } on AIProviderException {
      rethrow;
    } catch (error) {
      throw _transportException(error, _modelsUri);
    }
  }

  @override
  Stream<AIStreamEvent> streamChat(
    AIChatRequest request, {
    required String apiKey,
    CancellationToken? cancellationToken,
  }) async* {
    StreamSubscription<void>? cancellationSub;
    if (cancellationToken != null && _ownsClient) {
      cancellationSub = cancellationToken.whenCancelled.asStream().listen((_) {
        _client.close();
      });
    }

    try {
      cancellationToken?.throwIfCancelled();
      final httpRequest = http.Request('POST', _chatCompletionsUri)
        ..headers.addAll(_headers(apiKey))
        ..body = jsonEncode({
          'model': request.model,
          'messages': request.messages
              .map((message) => message.toJson())
              .toList(),
          if (request.tools.isNotEmpty) 'tools': request.tools,
          if (request.tools.isNotEmpty) 'tool_choice': 'auto',
          if (request.temperature != null) 'temperature': request.temperature,
          if (request.maxOutputTokens != null)
            'max_tokens': request.maxOutputTokens,
          'stream': true,
        });

      final response = await _client
          .send(httpRequest)
          .timeout(request.timeout ?? const Duration(seconds: 60));
      cancellationToken?.throwIfCancelled();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.stream.bytesToString();
        throw _errorFromResponse(
          response.statusCode,
          body,
          _chatCompletionsUri,
          'POST',
          request.model,
        );
      }

      final toolAccumulators = <int, _ToolAccumulator>{};
      String? finishReason;
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        cancellationToken?.throwIfCancelled();
        final trimmed = line.trim();
        if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;
        final eventAt = DateTime.now();
        final data = trimmed.substring(5).trim();
        if (data == '[DONE]') break;
        final Object? decoded;
        try {
          decoded = jsonDecode(data);
        } catch (_) {
          throw const AIProviderException(
            'Malformed streaming response',
            kind: 'malformed_response',
          );
        }
        if (decoded is! Map<String, Object?>) {
          throw const AIProviderException(
            'Malformed streaming response',
            kind: 'malformed_response',
          );
        }
        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final choice = choices.first;
        if (choice is! Map) continue;
        finishReason = choice['finish_reason']?.toString() ?? finishReason;
        final delta = choice['delta'];
        if (delta is! Map) continue;
        final content = delta['content'];
        if (content is String && content.isNotEmpty) {
          yield AIStreamEvent.text(
            content,
            networkChunkAt: eventAt,
            providerEventAt: eventAt,
          );
        }
        final toolCalls = delta['tool_calls'];
        if (toolCalls is List) {
          for (final rawCall in toolCalls) {
            if (rawCall is! Map) continue;
            final index = rawCall['index'] is int
                ? rawCall['index'] as int
                : int.tryParse(rawCall['index']?.toString() ?? '') ?? 0;
            final accumulator = toolAccumulators.putIfAbsent(
              index,
              () => _ToolAccumulator(),
            );
            final id = rawCall['id'];
            if (id is String && id.isNotEmpty) accumulator.id = id;
            final function = rawCall['function'];
            if (function is Map) {
              final name = function['name'];
              if (name is String && name.isNotEmpty) accumulator.name = name;
              final arguments = function['arguments'];
              if (arguments is String) accumulator.arguments.write(arguments);
            }
          }
        }
      }
      if (finishReason == null) {
        throw const AIProviderException(
          'Provider stream ended before completion marker',
          kind: 'incomplete_stream',
        );
      }
      final calls = toolAccumulators.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      yield AIStreamEvent.done(
        toolCalls: calls
            .where((entry) => entry.value.name.isNotEmpty)
            .map(
              (entry) => AIToolCall(
                id: entry.value.id.isEmpty
                    ? 'tool_${entry.key}'
                    : entry.value.id,
                name: entry.value.name,
                argumentsJson: entry.value.arguments.toString(),
              ),
            )
            .toList(),
        finishReason: finishReason,
      );
    } on TimeoutException {
      throw const AIProviderException(
        'Provider request timed out',
        kind: 'timeout',
      );
    } on AIProviderException {
      rethrow;
    } catch (error) {
      if (cancellationToken?.isCancelled ?? false) {
        throw const OperationCancelledException();
      }
      throw _transportException(
        error,
        _chatCompletionsUri,
        modelId: request.model,
      );
    } finally {
      await cancellationSub?.cancel();
    }
  }

  Map<String, String> _headers(String apiKey) => {
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
  };

  AIProviderException _errorFromResponse(
    int statusCode,
    String body,
    Uri uri,
    String method,
    String modelId,
  ) {
    var message = body;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        message = (decoded['error'] as Map)['message']?.toString() ?? body;
      }
    } catch (_) {}
    final kind = switch (statusCode) {
      400 =>
        message.toLowerCase().contains('context')
            ? 'context_length'
            : 'bad_request',
      401 || 403 => 'auth_error',
      408 => 'timeout',
      429 => 'rate_limited',
      >= 500 => 'server_error',
      _ => 'http_error',
    };
    return AIProviderException(
      message,
      statusCode: statusCode,
      kind: kind,
      details: ProviderErrorDetails(
        providerName: _providerName,
        modelId: modelId,
        requestUrl: uri.toString(),
        method: method,
        httpStatus: statusCode,
        errorType: kind,
        responseBody: body,
      ),
    );
  }

  static Uri _parseBaseUri(String baseUrl) {
    final normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const AIProviderException(
        'Provider endpoint must be a valid http:// or https:// URL with a host',
        kind: 'malformed_endpoint',
      );
    }
    return uri;
  }

  AIProviderException _transportException(
    Object error,
    Uri uri, {
    String modelId = '',
  }) {
    final details = error.toString();
    final host = uri.host.isEmpty ? 'provider host' : uri.host;
    AIProviderException build(String message, String kind) =>
        AIProviderException(
          message,
          kind: kind,
          details: ProviderErrorDetails(
            providerName: _providerName,
            modelId: modelId,
            requestUrl: uri.toString(),
            method: 'POST',
            errorType: kind,
            exceptionMessage: details,
          ),
        );
    if (error is FormatException ||
        details.contains('Invalid argument') ||
        details.contains('Invalid URI')) {
      return build('Provider endpoint is malformed', 'malformed_endpoint');
    }
    if (error is HandshakeException || details.contains('HandshakeException')) {
      return build('TLS handshake failed for $host', 'tls_failure');
    }
    if (error is SocketException || details.contains('SocketException')) {
      final lower = details.toLowerCase();
      if (lower.contains('failed host lookup') ||
          lower.contains('nodename nor servname') ||
          lower.contains('no address associated with hostname') ||
          lower.contains('name or service not known')) {
        return build('DNS lookup failed for $host', 'dns_failure');
      }
      if (lower.contains('network is unreachable') ||
          lower.contains('no route to host') ||
          lower.contains('connection failed')) {
        return build('No network route to $host', 'no_network');
      }
      return build('Network request failed for $host', 'network_error');
    }
    if (error is http.ClientException) {
      final lower = details.toLowerCase();
      if (lower.contains('failed host lookup') ||
          lower.contains('no address associated with hostname')) {
        return build('DNS lookup failed for $host', 'dns_failure');
      }
      return build('Network request failed for $host', 'network_error');
    }
    return build('Provider request failed for $host', 'provider_error');
  }

  static String _openAIPath(String base, String resource) {
    final cleanBase = base.replaceFirst(RegExp(r'/+$'), '');
    final prefix = cleanBase.endsWith('/v1') ? cleanBase : '$cleanBase/v1';
    return '$prefix/$resource';
  }
}

class _ToolAccumulator {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();
}
