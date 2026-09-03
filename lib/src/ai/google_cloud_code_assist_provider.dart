import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../core/cancellation.dart';
import 'ai_provider.dart';
import 'oauth/google_antigravity_oauth.dart';
import 'provider_diagnostics.dart';

class GoogleCloudCodeAssistProvider extends AIProvider {
  GoogleCloudCodeAssistProvider({
    required String baseUrl,
    http.Client? client,
    String providerName = GoogleAntigravityOAuthFlow.providerName,
  }) : _baseUri = _parseBaseUri(baseUrl),
       _client = client ?? http.Client(),
       _providerName = providerName;

  final Uri _baseUri;
  final http.Client _client;
  final String _providerName;

  Uri get resolvedStreamUri => _baseUri.replace(
    path: _joinPath(_baseUri.path, '/v1internal:streamGenerateContent'),
    queryParameters: const {'alt': 'sse'},
  );

  @override
  Stream<AIStreamEvent> streamChat(
    AIChatRequest request, {
    required String apiKey,
    CancellationToken? cancellationToken,
  }) async* {
    final credential = _parseCredential(apiKey);
    if (credential['token'] == null || credential['projectId'] == null) {
      throw AIProviderException(
        'Missing token or projectId in Google Antigravity credentials',
        kind: 'oauth_error',
        details: _details(
          request,
          'oauth_error',
          exceptionMessage: 'Missing token or projectId in OAuth credential',
        ),
      );
    }
    final url = resolvedStreamUri;
    final wireModel = _wireModelId(request.model);
    final requestBody = _requestBody(
      request,
      credential['projectId']!,
      wireModel,
    );
    final structuralTrace = _geminiStructuralTrace(requestBody);
    final validationError = _validateGeminiContents(requestBody);
    if (validationError != null) {
      throw AIProviderException(
        validationError,
        kind: 'malformed_request',
        details: _details(
          request,
          'malformed_request',
          exceptionMessage: validationError,
          finalResponse: structuralTrace,
        ),
      );
    }
    final body = jsonEncode(requestBody);
    var streamStarted = false;
    var chunksReceived = 0;
    final toolCalls = <AIToolCall>[];
    String? finishReason;
    final nativeModelParts = <Map<String, Object?>>[];
    final nativeModelPartKeys = <String>{};
    final toolCallKeys = <String>{};
    try {
      final httpRequest = http.Request('POST', url)
        ..headers.addAll({
          'Authorization': 'Bearer ${credential['token']}',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
          'User-Agent': GoogleAntigravityOAuthFlow.antigravityUserAgent,
        })
        ..body = body;
      final response = await _client
          .send(httpRequest)
          .timeout(request.timeout ?? const Duration(seconds: 90));
      cancellationToken?.throwIfCancelled();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final responseBody = await response.stream.bytesToString();
        throw AIProviderException(
          _extractMessage(responseBody),
          statusCode: response.statusCode,
          kind: _kindForStatus(response.statusCode),
          details: _details(
            request,
            _kindForStatus(response.statusCode),
            httpStatus: response.statusCode,
            responseBody: responseBody,
            streamStarted: streamStarted,
            chunksReceived: chunksReceived,
            finalResponse: structuralTrace,
          ),
        );
      }
      streamStarted = true;
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
        chunksReceived++;
        final decoded = jsonDecode(data);
        if (decoded is! Map<String, Object?>) continue;
        final error = decoded['error'];
        if (error is Map) {
          final message =
              error['message']?.toString() ??
              error['status']?.toString() ??
              'Cloud Code Assist stream error';
          throw AIProviderException(
            message,
            statusCode: error['code'] is int ? error['code'] as int : null,
            kind: 'provider_error',
            details: _details(
              request,
              'provider_error',
              httpStatus: error['code'] is int ? error['code'] as int : null,
              responseBody: data,
              streamStarted: streamStarted,
              chunksReceived: chunksReceived,
            ),
          );
        }
        final responseData = decoded['response'];
        if (responseData is! Map) continue;
        final candidates = responseData['candidates'];
        if (candidates is! List || candidates.isEmpty) continue;
        final candidate = candidates.first;
        if (candidate is! Map) continue;
        finishReason = candidate['finishReason']?.toString() ?? finishReason;
        final content = candidate['content'];
        if (content is! Map) continue;
        final parts = content['parts'];
        if (parts is! List) continue;
        for (final part in parts) {
          if (part is! Map) continue;
          final nativePart = _cloneJsonMap(part.cast<String, Object?>());
          final nativePartKey = jsonEncode(nativePart);
          if (nativeModelPartKeys.add(nativePartKey)) {
            nativeModelParts.add(nativePart);
          }
          final text = part['text'];
          final isThinking = part['thought'] == true;
          if (text is String && text.isNotEmpty && !isThinking) {
            yield AIStreamEvent.text(
              text,
              networkChunkAt: eventAt,
              providerEventAt: eventAt,
            );
          }
          final functionCall = part['functionCall'];
          if (functionCall is Map) {
            final name = functionCall['name']?.toString() ?? '';
            if (name.isEmpty) continue;
            final args = functionCall['args'];
            final providerId = functionCall['id']?.toString();
            final callKey = '${providerId ?? ''}|$name|${_stableJson(args)}';
            if (!toolCallKeys.add(callKey)) continue;
            final internalId = providerId?.isNotEmpty == true
                ? providerId!
                : 'gemini_call_${toolCalls.length}_${callKey.hashCode.abs()}';
            toolCalls.add(
              AIToolCall(
                id: internalId,
                name: name,
                argumentsJson: args is String
                    ? args
                    : jsonEncode(args ?? <String, Object?>{}),
                providerMetadata: {
                  ..._providerMetadataFromPart(part),
                  'geminiFunctionName': name,
                  'geminiFunctionCallId': internalId,
                  if (providerId != null && providerId.isNotEmpty)
                    'providerFunctionCallId': providerId,
                },
              ),
            );
          }
        }
      }
      if (finishReason == null) {
        throw AIProviderException(
          'Cloud Code Assist stream ended before completion marker',
          kind: 'incomplete_stream',
          details: _details(
            request,
            'incomplete_stream',
            streamStarted: streamStarted,
            chunksReceived: chunksReceived,
          ),
        );
      }
      yield AIStreamEvent.done(
        toolCalls: toolCalls,
        finishReason: finishReason,
        providerMetadata: _geminiProviderMetadata(nativeModelParts, toolCalls),
      );
    } on TimeoutException catch (error) {
      throw AIProviderException(
        'Cloud Code Assist did not respond in time',
        kind: 'timeout',
        details: _details(
          request,
          'timeout',
          exceptionMessage: error.toString(),
          streamStarted: streamStarted,
          chunksReceived: chunksReceived,
        ),
      );
    } on AIProviderException {
      rethrow;
    } catch (error) {
      if (cancellationToken?.isCancelled ?? false) {
        throw const OperationCancelledException();
      }
      throw AIProviderException(
        'Cloud Code Assist request failed',
        kind: 'provider_error',
        details: _details(
          request,
          'provider_error',
          exceptionMessage: error.toString(),
          streamStarted: streamStarted,
          chunksReceived: chunksReceived,
        ),
      );
    }
  }

  Map<String, Object?> _requestBody(
    AIChatRequest request,
    String projectId,
    String wireModel,
  ) {
    final systemParts = <Map<String, String>>[];
    final contents = <Map<String, Object?>>[];
    final toolNamesById = <String, String>{};
    final pendingFunctionResponses = <Map<String, Object?>>[];

    void flushFunctionResponses() {
      if (pendingFunctionResponses.isEmpty) return;
      contents.add({
        'role': 'user',
        'parts': List.of(pendingFunctionResponses),
      });
      pendingFunctionResponses.clear();
    }

    for (final message in request.messages) {
      if (message.role != 'tool') flushFunctionResponses();
      if (message.role == 'system') {
        if (message.content.trim().isNotEmpty) {
          systemParts.add({'text': message.content});
        }
        continue;
      }
      if (message.role == 'assistant') {
        for (final call in message.toolCalls ?? const <AIToolCall>[]) {
          toolNamesById[call.id] = call.name;
        }
        final nativeParts = _geminiNativeParts(message.providerMetadata);
        final parts = nativeParts ?? <Map<String, Object?>>[];
        if (nativeParts == null) {
          if (message.content.trim().isNotEmpty) {
            parts.add({'text': message.content});
          }
          for (final call in message.toolCalls ?? const <AIToolCall>[]) {
            parts.add(_functionCallPart(call));
          }
        }
        for (final part in parts) {
          final functionCall = part['functionCall'];
          if (functionCall is Map) {
            final id = functionCall['id']?.toString();
            final name = functionCall['name']?.toString();
            if (id != null &&
                id.isNotEmpty &&
                name != null &&
                name.isNotEmpty) {
              toolNamesById[id] = name;
            }
          }
        }
        if (parts.isNotEmpty) contents.add({'role': 'model', 'parts': parts});
        continue;
      }
      if (message.role == 'tool') {
        final name = toolNamesById[message.toolCallId] ?? 'tool';
        pendingFunctionResponses.add({
          'functionResponse': {
            'name': name,
            'response': _toolResponseObject(message.content),
          },
        });
        continue;
      }
      if (message.content.trim().isNotEmpty) {
        contents.add({
          'role': 'user',
          'parts': [
            {'text': message.content},
          ],
        });
      }
    }
    flushFunctionResponses();
    final trace = _geminiStructuralTrace({
      'request': {'contents': contents},
    });
    final validationError = _validateGeminiContents({
      'request': {'contents': contents},
    });
    if (validationError != null) {
      throw AIProviderException(
        validationError,
        kind: 'malformed_request',
        details: _details(
          request,
          'malformed_request',
          exceptionMessage: validationError,
          finalResponse: trace,
        ),
      );
    }
    final generationConfig = <String, Object?>{
      'maxOutputTokens': _maxOutputTokens(wireModel),
      if (request.temperature != null) 'temperature': request.temperature,
    };
    final labels = <String, String>{
      'last_step_index': '1',
      'trajectory_id': _randomHex(16),
      'used_claude': wireModel.startsWith('claude-').toString(),
      'used_claude_conservative': wireModel.startsWith('claude-').toString(),
      if (_modelEnum(wireModel) != null) 'model_enum': _modelEnum(wireModel)!,
    };
    return {
      'project': projectId,
      'model': wireModel,
      'userAgent': 'antigravity',
      'requestType': 'agent',
      'requestId':
          'agent/${_randomHex(12)}/${DateTime.now().millisecondsSinceEpoch}/${_randomHex(12)}/2',
      'request': {
        'contents': contents,
        if (systemParts.isNotEmpty)
          'systemInstruction': {'role': 'user', 'parts': systemParts},
        if (request.tools.isNotEmpty)
          'tools': [
            {
              'functionDeclarations': request.tools
                  .map(_toolDeclaration)
                  .toList(),
            },
          ],
        if (request.tools.isNotEmpty)
          'toolConfig': {
            'functionCallingConfig': {'mode': 'VALIDATED'},
          },
        'generationConfig': generationConfig,
        'sessionId': _randomSignedSessionId(),
        'labels': labels,
      },
    };
  }

  Map<String, Object?> _toolDeclaration(Map<String, Object?> spec) {
    final function = spec['function'];
    if (function is Map) {
      return {
        'name': function['name']?.toString() ?? 'tool',
        if (function['description'] != null)
          'description': function['description'],
        'parameters': _normalizeCloudCodeSchema(
          function['parameters'] ?? <String, Object?>{},
        ),
      };
    }
    return spec;
  }

  static Map<String, Object?> _functionCallPart(AIToolCall call) {
    Object? args;
    try {
      args = jsonDecode(call.argumentsJson);
    } catch (_) {
      args = <String, Object?>{'raw': call.argumentsJson};
    }
    final functionCallPart = <String, Object?>{
      'functionCall': {'name': call.name, 'args': args},
    };
    final thoughtSignature = call.providerMetadata['thoughtSignature'];
    if (thoughtSignature is String && thoughtSignature.isNotEmpty) {
      final key =
          call.providerMetadata['thoughtSignatureKey']?.toString() ??
          'thoughtSignature';
      functionCallPart[key] = thoughtSignature;
    }
    return functionCallPart;
  }

  static List<Map<String, Object?>>? _geminiNativeParts(
    Map<String, Object?> metadata,
  ) {
    final gemini = metadata['gemini'];
    if (gemini is! Map) return null;
    final parts = gemini['parts'];
    if (parts is! List) return null;
    final nativeParts = <Map<String, Object?>>[];
    for (final part in parts) {
      if (part is Map) nativeParts.add(part.cast<String, Object?>());
    }
    return nativeParts.isEmpty ? null : nativeParts;
  }

  static Map<String, Object?> _toolResponseObject(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map) return decoded.cast<String, Object?>();
      return {'output': decoded};
    } catch (_) {
      return {'output': content};
    }
  }

  static Map<String, Object?> _geminiProviderMetadata(
    List<Map<String, Object?>> parts,
    List<AIToolCall> toolCalls,
  ) {
    final signatureCount = toolCalls
        .where((call) => call.providerMetadata['thoughtSignature'] is String)
        .length;
    return {
      'gemini': {
        'parts': parts,
        'diagnostics': {
          'assistantPartCount': parts.length,
          'functionCallCount': toolCalls.length,
          'thoughtSignaturesReceived': signatureCount,
          'providerNativeMetadataPresent': parts.isNotEmpty,
        },
      },
    };
  }

  static String _stableJson(Object? value) {
    if (value is Map) {
      final sorted = Map.fromEntries(
        value.entries.toList()
          ..sort((a, b) => a.key.toString().compareTo(b.key.toString())),
      );
      return jsonEncode(sorted);
    }
    return jsonEncode(value);
  }

  static Map<String, Object?> _cloneJsonMap(Map<String, Object?> value) =>
      (jsonDecode(jsonEncode(value)) as Map).cast<String, Object?>();
  static Map<String, Object?> _providerMetadataFromPart(Map part) {
    for (final source in [part, part['functionCall']]) {
      if (source is! Map) continue;
      for (final key in const [
        'thoughtSignature',
        'thought_signature',
        'thoughtSignatureBytes',
      ]) {
        final value = source[key];
        if (value is String && value.isNotEmpty) {
          return {
            'thoughtSignature': value,
            'thoughtSignatureKey': key,
            'thoughtSignatureReceived': true,
          };
        }
      }
    }
    return const <String, Object?>{};
  }

  static String _geminiStructuralTrace(Map<String, Object?> requestBody) {
    final request = requestBody['request'];
    final contents = request is Map ? request['contents'] : null;
    if (contents is! List) return 'contents: unavailable';
    final lines = <String>[];
    for (var i = 0; i < contents.length; i++) {
      final content = contents[i];
      if (content is! Map) continue;
      lines.add('contents[$i]');
      lines.add('role=${content['role']}');
      final parts = content['parts'];
      if (parts is! List) {
        lines.add('parts=[]');
        continue;
      }
      final labels = <String>[];
      for (final part in parts) {
        if (part is! Map) continue;
        if (part['text'] != null) labels.add('text');
        final functionCall = part['functionCall'];
        if (functionCall is Map) {
          labels.add(
            'functionCall:${functionCall['name'] ?? 'tool'}:thoughtSignature=${_hasThoughtSignature(part) ? 'yes' : 'no'}',
          );
        }
        final functionResponse = part['functionResponse'];
        if (functionResponse is Map) {
          labels.add('functionResponse:${functionResponse['name'] ?? 'tool'}');
        }
      }
      lines.add('parts=[${labels.join(', ')}]');
    }
    return lines.join('\n');
  }

  static String? _validateGeminiContents(Map<String, Object?> requestBody) {
    final request = requestBody['request'];
    final contents = request is Map ? request['contents'] : null;
    if (contents is! List) return 'Gemini history invalid: contents missing';
    var pendingFunctionCallCount = 0;
    for (var i = 0; i < contents.length; i++) {
      final content = contents[i];
      if (content is! Map) continue;
      final parts = content['parts'];
      if (parts is! List) continue;
      final functionCallCount = parts
          .where((part) => part is Map && part['functionCall'] is Map)
          .length;
      final functionResponseCount = parts
          .where((part) => part is Map && part['functionResponse'] is Map)
          .length;
      if (functionResponseCount > 0) {
        if (pendingFunctionCallCount == 0) {
          return 'Gemini history invalid: contents[$i] contains functionResponse without a preceding functionCall turn.\n${_geminiStructuralTrace(requestBody)}';
        }
        if (functionResponseCount != pendingFunctionCallCount) {
          return 'Gemini history invalid: contents[$i] has $functionResponseCount functionResponse part(s), expected $pendingFunctionCallCount for the previous functionCall turn.\n${_geminiStructuralTrace(requestBody)}';
        }
        pendingFunctionCallCount = 0;
      }
      if (functionCallCount == 0) continue;
      if (pendingFunctionCallCount > 0) {
        return 'Gemini history invalid: contents[$i] contains functionCall before prior function responses were complete.\n${_geminiStructuralTrace(requestBody)}';
      }
      if (i == 0) {
        return 'Gemini history invalid: contents[$i] contains functionCall but has no previous user/functionResponse turn.\n${_geminiStructuralTrace(requestBody)}';
      }
      final previous = contents[i - 1];
      if (previous is! Map || previous['role'] != 'user') {
        return 'Gemini history invalid: contents[$i] contains functionCall; previous turn contents[${i - 1}] is role=${previous is Map ? previous['role'] : 'unknown'}.\n${_geminiStructuralTrace(requestBody)}';
      }
      pendingFunctionCallCount = functionCallCount;
    }
    if (pendingFunctionCallCount > 0) {
      return 'Gemini history invalid: final functionCall turn has no functionResponse turn.\n${_geminiStructuralTrace(requestBody)}';
    }
    return null;
  }

  static bool _hasThoughtSignature(Map part) {
    for (final key in const [
      'thoughtSignature',
      'thought_signature',
      'thoughtSignatureBytes',
    ]) {
      final value = part[key];
      if (value is String && value.isNotEmpty) return true;
    }
    return false;
  }

  ProviderErrorDetails _details(
    AIChatRequest request,
    String kind, {
    int? httpStatus,
    String? responseBody,
    String? exceptionMessage,
    bool streamStarted = false,
    int chunksReceived = 0,
    String? finalResponse,
  }) => ProviderErrorDetails(
    providerName: _providerName,
    modelId: request.model,
    requestUrl: resolvedStreamUri.toString(),
    method: 'POST',
    httpStatus: httpStatus,
    errorType: kind,
    responseBody: responseBody,
    exceptionMessage: exceptionMessage,
    headers: const {
      'Authorization': 'Bearer [redacted]',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      'User-Agent': GoogleAntigravityOAuthFlow.antigravityUserAgent,
    },
    streamStarted: streamStarted,
    chunksReceived: chunksReceived,
    finalResponse: finalResponse,
  );

  static Map<String, String?> _parseCredential(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return {
          'token': decoded['token']?.toString(),
          'projectId': (decoded['projectId'] ?? decoded['project_id'])
              ?.toString(),
        };
      }
    } catch (_) {}
    return const {'token': null, 'projectId': null};
  }

  static Uri _parseBaseUri(String baseUrl) {
    final normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const AIProviderException(
        'Cloud Code Assist endpoint must be a valid http:// or https:// URL with a host',
        kind: 'malformed_endpoint',
      );
    }
    return uri;
  }

  static String _wireModelId(String modelId) => switch (modelId) {
    'gemini-3.1-pro' => 'gemini-3.1-pro-low',
    'gemini-3.5-flash' => 'gemini-3.5-flash-extra-low',
    _ => modelId,
  };

  static int _maxOutputTokens(String modelId) => switch (modelId) {
    'claude-sonnet-4-6' || 'claude-opus-4-6-thinking' => 64000,
    _ => 65535,
  };

  static String? _modelEnum(String modelId) => switch (modelId) {
    'gemini-3.5-flash-extra-low' => 'MODEL_PLACEHOLDER_M187',
    'gemini-3.5-flash-low' => 'MODEL_PLACEHOLDER_M20',
    'gemini-3-flash-agent' => 'MODEL_PLACEHOLDER_M132',
    'gemini-3.1-pro-low' => 'MODEL_PLACEHOLDER_M36',
    'gemini-pro-agent' => 'MODEL_PLACEHOLDER_M16',
    _ => null,
  };

  static String _kindForStatus(int status) => switch (status) {
    401 || 403 => 'auth_error',
    408 => 'timeout',
    429 => 'rate_limited',
    >= 500 => 'server_error',
    _ => 'http_error',
  };

  static String _extractMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        return (decoded['error'] as Map)['message']?.toString() ?? body;
      }
    } catch (_) {}
    return body;
  }

  static String _joinPath(String base, String suffix) {
    final cleanBase = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    final cleanSuffix = suffix.startsWith('/') ? suffix : '/$suffix';
    return '$cleanBase$cleanSuffix';
  }

  static String _randomHex(int length) {
    final random = Random.secure();
    const chars = '0123456789abcdef';
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  static String _randomSignedSessionId() {
    final value = Random.secure().nextInt(0x7fffffff) + 1;
    return Random.secure().nextBool() ? '$value' : '-$value';
  }
}

const _cloudCodeUnsupportedSchemaFields = <String>{
  r'$schema',
  r'$ref',
  r'$defs',
  r'$dynamicRef',
  r'$dynamicAnchor',
  'examples',
  'prefixItems',
  'unevaluatedProperties',
  'unevaluatedItems',
  'patternProperties',
  'additionalProperties',
  'propertyNames',
  'minItems',
  'maxItems',
  'minLength',
  'maxLength',
  'minimum',
  'maximum',
  'exclusiveMinimum',
  'exclusiveMaximum',
  'multipleOf',
  'pattern',
  'format',
  'dependencies',
  'dependentSchemas',
  'dependentRequired',
  'deprecated',
  'readOnly',
  'writeOnly',
  r'$comment',
};

Object? _normalizeCloudCodeSchema(Object? value) {
  if (value is bool) return <String, Object?>{};
  if (value is List) {
    return value.map(_normalizeCloudCodeSchema).toList(growable: false);
  }
  if (value is! Map) return value;
  final result = <String, Object?>{};
  value.forEach((key, raw) {
    final name = key.toString();
    if (_cloudCodeUnsupportedSchemaFields.contains(name)) return;
    result[name] = _normalizeCloudCodeSchema(raw);
  });
  return result;
}
