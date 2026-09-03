import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/cancellation.dart';
import 'ai_provider.dart';
import 'oauth/oauth_credential.dart';
import 'provider_diagnostics.dart';

class OpenAICodexProvider extends AIProvider {
  OpenAICodexProvider({
    required String baseUrl,
    http.Client? client,
    String providerName = 'ChatGPT (Codex)',
  }) : _baseUri = _parseBaseUri(baseUrl),
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _providerName = providerName;

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;
  final String _providerName;

  Uri get resolvedResponsesUri {
    final path = _baseUri.path.replaceFirst(RegExp(r'/+$'), '');
    final responsePath = path.endsWith('/codex/responses')
        ? path
        : '$path/codex/responses';
    return _baseUri.replace(path: responsePath);
  }

  @override
  Stream<AIStreamEvent> streamChat(
    AIChatRequest request, {
    required String apiKey,
    CancellationToken? cancellationToken,
  }) async* {
    final credential = _credential(apiKey);
    StreamSubscription<void>? cancellationSub;
    if (cancellationToken != null && _ownsClient) {
      cancellationSub = cancellationToken.whenCancelled.asStream().listen((_) {
        _client.close();
      });
    }
    try {
      cancellationToken?.throwIfCancelled();
      final body = _requestBody(request);
      final response = await _client
          .send(
            http.Request('POST', resolvedResponsesUri)
              ..headers.addAll(_headers(credential))
              ..body = jsonEncode(body),
          )
          .timeout(request.timeout ?? const Duration(seconds: 90));
      cancellationToken?.throwIfCancelled();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final text = await response.stream.bytesToString();
        throw AIProviderException(
          '$_providerName request failed: ${response.statusCode}: ${_safeError(text)}',
          statusCode: response.statusCode,
          kind: response.statusCode == 401 || response.statusCode == 403
              ? 'unauthorized'
              : 'provider_error',
        );
      }

      final toolCalls = <String, _CodexToolCall>{};
      var completed = false;
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        cancellationToken?.throwIfCancelled();
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith(':')) continue;
        final data = trimmed.startsWith('data:')
            ? trimmed.substring(5).trim()
            : trimmed;
        if (data == '[DONE]') {
          completed = true;
          break;
        }
        final decoded = _decodeEvent(data);
        if (decoded == null) continue;
        final type = decoded['type']?.toString() ?? '';
        final eventAt = DateTime.now();
        if (type == 'response.output_text.delta' ||
            type == 'response.refusal.delta') {
          final delta = decoded['delta'];
          if (delta is String && delta.isNotEmpty) {
            yield AIStreamEvent.text(
              delta,
              networkChunkAt: eventAt,
              providerEventAt: eventAt,
            );
          }
        } else if (type == 'response.output_item.added') {
          final item = decoded['item'];
          if (item is Map && item['type'] == 'function_call') {
            final key = _toolKey(item);
            toolCalls[key] = _CodexToolCall(
              id: (item['call_id'] ?? item['id'] ?? key).toString(),
              name: (item['name'] ?? '').toString(),
            );
          }
        } else if (type == 'response.function_call_arguments.delta') {
          final key = (decoded['item_id'] ?? decoded['call_id'] ?? '')
              .toString();
          final call = toolCalls[key];
          final delta = decoded['delta'];
          if (call != null && delta is String) call.arguments += delta;
        } else if (type == 'response.function_call_arguments.done') {
          final key = (decoded['item_id'] ?? decoded['call_id'] ?? '')
              .toString();
          final call = toolCalls[key];
          final arguments = decoded['arguments'];
          if (call != null && arguments is String) {
            call.arguments = arguments;
          }
        } else if (type == 'response.output_item.done') {
          final item = decoded['item'];
          if (item is Map && item['type'] == 'function_call') {
            final key = _toolKey(item);
            final call = toolCalls.putIfAbsent(
              key,
              () => _CodexToolCall(
                id: (item['call_id'] ?? item['id'] ?? key).toString(),
                name: (item['name'] ?? '').toString(),
              ),
            );
            final arguments = item['arguments'];
            if (arguments is String) call.arguments = arguments;
          }
        } else if (type == 'response.completed' ||
            type == 'response.done' ||
            type == 'response.incomplete') {
          completed = true;
          final responseObject = decoded['response'];
          final status = responseObject is Map
              ? responseObject['status']?.toString()
              : null;
          yield AIStreamEvent.done(
            toolCalls: _finishToolCalls(toolCalls),
            finishReason: status ?? 'stop',
            networkChunkAt: eventAt,
            providerEventAt: eventAt,
          );
        } else if (type == 'response.failed') {
          final error = decoded['response'];
          throw AIProviderException(
            '$_providerName response failed: ${error is Map ? error['error'] ?? error : error}',
            kind: 'provider_error',
          );
        }
      }
      if (!completed) {
        throw const AIProviderException(
          'Provider stream ended before completion marker',
          kind: 'incomplete_stream',
        );
      }
      if (toolCalls.isNotEmpty && completed) {
        // Some Codex deployments emit response.completed without a separate
        // terminal event after tool calls. Emit no duplicate done event.
      }
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
        resolvedResponsesUri,
        modelId: request.model,
      );
    } finally {
      await cancellationSub?.cancel();
    }
  }

  Map<String, Object?> _requestBody(AIChatRequest request) {
    String? instructions;
    final input = <Object?>[];
    for (final message in request.messages) {
      if (message.role == 'system') {
        instructions = instructions == null
            ? message.content
            : '$instructions\n\n${message.content}';
        continue;
      }
      if (message.role == 'tool') {
        input.add({
          'type': 'function_call_output',
          'call_id': message.toolCallId ?? 'tool_call',
          'output': message.content,
        });
        continue;
      }
      if (message.toolCalls != null && message.toolCalls!.isNotEmpty) {
        for (final call in message.toolCalls!) {
          input.add({
            'type': 'function_call',
            'call_id': call.id,
            'name': call.name,
            'arguments': call.argumentsJson,
          });
        }
      }
      input.add({
        'type': 'message',
        'role': message.role == 'assistant' ? 'assistant' : 'user',
        'content': [
          {
            'type': message.role == 'assistant' ? 'output_text' : 'input_text',
            'text': message.content,
          },
        ],
      });
    }
    final body = <String, Object?>{
      'model': request.model,
      'input': input,
      'stream': true,
    };
    if (instructions != null && instructions.isNotEmpty) {
      body['instructions'] = instructions;
    }
    if (request.tools case final tools when tools.isNotEmpty) {
      body['tools'] = tools
          .map(
            (tool) => {
              'type': 'function',
              'name': tool['name'] ?? 'tool',
              if (tool['description'] != null)
                'description': tool['description'],
              'parameters': tool['parameters'] is Map
                  ? tool['parameters']
                  : <String, Object?>{},
            },
          )
          .toList();
    }
    return body;
  }

  Map<String, String> _headers(OAuthCredential credential) => {
    'Authorization': 'Bearer ${credential.accessToken}',
    if (credential.accountId != null)
      'chatgpt-account-id': credential.accountId!,
    'OpenAI-Beta': 'responses=experimental',
    'originator': 'pi',
    'version': '0.144.1',
    'Accept': 'text/event-stream',
    'Content-Type': 'application/json',
  };

  OAuthCredential _credential(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['token'] is String) {
        return OAuthCredential(
          provider: OAuthProviderId.openAICodex,
          accessToken: decoded['token'] as String,
          refreshToken: decoded['refreshToken'] as String? ?? '',
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            decoded['expiresAt'] is int ? decoded['expiresAt'] as int : 0,
          ),
          accountId: decoded['accountId'] as String?,
          email: decoded['email'] as String?,
        );
      }
    } catch (_) {}
    return OAuthCredential(
      provider: OAuthProviderId.openAICodex,
      accessToken: raw,
      refreshToken: '',
      expiresAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  AIProviderException _transportException(
    Object error,
    Uri uri, {
    required String modelId,
  }) => AIProviderException(
    '$_providerName request failed: ${error.toString()}',
    kind: 'network_error',
    details: ProviderErrorDetails(
      providerName: _providerName,
      modelId: modelId,
      requestUrl: uri.toString(),
      method: 'POST',
      errorType: 'network_error',
      exceptionMessage: error.toString(),
    ),
  );

  static Uri _parseBaseUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError.value(value, 'baseUrl', 'must be an absolute URL');
    }
    return uri;
  }

  static Map<String, Object?>? _decodeEvent(String data) {
    try {
      final value = jsonDecode(data);
      return value is Map ? value.cast<String, Object?>() : null;
    } catch (_) {
      throw const AIProviderException(
        'Malformed streaming response',
        kind: 'malformed_response',
      );
    }
  }

  static String _toolKey(Map item) =>
      (item['item_id'] ?? item['call_id'] ?? item['id'] ?? '').toString();

  static List<AIToolCall> _finishToolCalls(Map<String, _CodexToolCall> calls) =>
      calls.values
          .where((call) => call.name.isNotEmpty)
          .map(
            (call) => AIToolCall(
              id: call.id,
              name: call.name,
              argumentsJson: call.arguments,
            ),
          )
          .toList(growable: false);

  static String _safeError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return (decoded['detail'] ??
                decoded['error'] ??
                decoded['message'] ??
                body)
            .toString();
      }
    } catch (_) {}
    return body.trim().isEmpty ? 'empty response' : body.trim();
  }
}

class _CodexToolCall {
  _CodexToolCall({required this.id, required this.name});
  final String id;
  final String name;
  String arguments = '';
}
