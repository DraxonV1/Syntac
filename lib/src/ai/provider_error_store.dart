// Persists bounded-diagnostic provider failures inside project-local Syntac data.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'ai_provider.dart';
import 'provider_diagnostics.dart';

Future<void> persistProviderError({
  required String projectRoot,
  required String chatId,
  required Object error,
  AIChatRequest? request,
}) async {
  try {
    final providerError = error is AIProviderException ? error : null;
    final details = providerError?.details;
    final statusCode = details?.httpStatus ?? providerError?.statusCode;
    final requestPayload =
        details?.requestPayload ??
        (request == null ? null : jsonEncode(_requestFallback(request)));
    final responseBody = details?.responseBody;
    final statusDirectory = statusCode?.toString() ?? 'unknown';
    final safeChatId = chatId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (safeChatId.isEmpty) return;
    final directory = Directory(
      p.join(projectRoot, '.syntac', 'errors', statusDirectory),
    );
    await directory.create(recursive: true);
    final record = <String, Object?>{
      'timestamp': DateTime.now().toIso8601String(),
      'chatId': chatId,
      'statusCode': statusCode,
      'provider': details?.providerName,
      'model': details?.modelId ?? request?.model,
      'errorType': details?.errorType ?? providerError?.kind,
      'message': providerError?.message ?? error.toString(),
      if (requestPayload != null)
        'requestPayload': redactSecrets(requestPayload),
      if (responseBody != null) 'responseBody': redactSecrets(responseBody),
      if (details != null) 'diagnostics': details.toJson(),
    };
    await File(p.join(directory.path, '$safeChatId.jsonl')).writeAsString(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {
    // Never replace provider failure with diagnostics filesystem failure.
  }
}

Map<String, Object?> _requestFallback(AIChatRequest request) => {
  'model': request.model,
  'messages': request.messages.map((message) => message.toJson()).toList(),
  'tools': request.tools,
  if (request.temperature != null) 'temperature': request.temperature,
  if (request.maxOutputTokens != null)
    'maxOutputTokens': request.maxOutputTokens,
  'reasoningEffort': request.reasoningEffort?.wireValue,
  'includeThinking': request.includeThinking,
  'supportsReasoning': request.supportsReasoning,
};
