import 'dart:convert';

import '../ai/ai_provider.dart';
import '../models.dart';
import 'system_prompt.dart';

class ContextBuilder {
  const ContextBuilder({required this.maxCharacters});

  final int maxCharacters;

  List<AIChatMessage> build({
    required List<ChatMessage> history,
    String? customSystemPrompt,
    Map<String, List<AIImagePart>> imagePartsByMessageId =
        const <String, List<AIImagePart>>{},
  }) {
    final effectiveSystemPrompt =
        customSystemPrompt != null && customSystemPrompt.trim().isNotEmpty
        ? customSystemPrompt.trim()
        : codingAgentSystemPrompt;
    final messages = <AIChatMessage>[
      AIChatMessage(role: 'system', content: effectiveSystemPrompt),
    ];
    var used = effectiveSystemPrompt.length;
    for (final message in history.reversed) {
      final converted = _convert(
        message,
        images:
            imagePartsByMessageId[message.id] ?? _imagesFromContent(message),
      );
      final imageCost = converted.images.fold<int>(
        0,
        (total, image) => total + image.base64Data.length,
      );
      final cost =
          converted.content.length +
          imageCost +
          (message.metadataJson?.length ?? 0) +
          32;
      if (maxCharacters > 0 &&
          used + cost > maxCharacters &&
          messages.length > 1) {
        break;
      }
      messages.insert(1, converted);
      used += cost;
    }
    _dropUnsafeLeadingMessages(messages);
    _dropIncompleteToolExchanges(messages);
    return messages;
  }

  void _dropUnsafeLeadingMessages(List<AIChatMessage> messages) {
    while (messages.length > 1 && messages[1].role != 'user') {
      messages.removeAt(1);
    }
  }

  void _dropIncompleteToolExchanges(List<AIChatMessage> messages) {
    var index = 1;
    while (index < messages.length) {
      final message = messages[index];
      final toolCallIds = message.role == 'assistant'
          ? (message.toolCalls ?? const <AIToolCall>[])
                .map((call) => call.id)
                .toSet()
          : const <String>{};
      if (toolCallIds.isEmpty) {
        index++;
        continue;
      }
      var cursor = index + 1;
      final responseIds = <String>{};
      while (cursor < messages.length && messages[cursor].role == 'tool') {
        final toolCallId = messages[cursor].toolCallId;
        if (toolCallId != null) responseIds.add(toolCallId);
        cursor++;
      }
      if (responseIds.containsAll(toolCallIds) &&
          toolCallIds.containsAll(responseIds)) {
        index = cursor;
        continue;
      }
      messages.removeRange(index, cursor);
    }
  }

  AIChatMessage _convert(
    ChatMessage message, {
    List<AIImagePart> images = const <AIImagePart>[],
  }) {
    final userRun = _isUserRunResult(message);
    final role = userRun
        ? 'user'
        : switch (message.role) {
            MessageRole.system => 'system',
            MessageRole.user => 'user',
            MessageRole.assistant => 'assistant',
            MessageRole.tool => 'tool',
            MessageRole.internal => 'system',
          };
    return AIChatMessage(
      role: role,
      content: userRun
          ? '[User-run bash result]\\n${message.content}'
          : _contentForModel(message),
      images: userRun ? const <AIImagePart>[] : images,
      toolCallId: userRun ? null : message.toolCallId,
      toolCalls: !userRun && message.role == MessageRole.assistant
          ? _toolCallsFromMetadata(message.metadataJson)
          : null,
      providerMetadata: !userRun && message.role == MessageRole.assistant
          ? _providerMetadataFromMessage(message.metadataJson)
          : const <String, Object?>{},
    );
  }

  bool _isUserRunResult(ChatMessage message) {
    if (message.role != MessageRole.tool) return false;
    final metadata = message.metadataJson;
    if (metadata == null || metadata.isEmpty) return false;
    try {
      final decoded = jsonDecode(metadata);
      return decoded is Map && decoded['source'] == 'user';
    } catch (_) {
      return false;
    }
  }

  List<AIImagePart> _imagesFromContent(ChatMessage message) {
    if (message.role != MessageRole.tool) return const <AIImagePart>[];
    try {
      final decoded = jsonDecode(message.content);
      final result = decoded is Map ? decoded['result'] : null;
      final uri = result is Map ? result['imageDataUri']?.toString() : null;
      if (uri == null || !uri.startsWith('data:image/')) {
        return const <AIImagePart>[];
      }
      final separator = uri.indexOf(';base64,');
      if (separator < 0) return const <AIImagePart>[];
      final mimeType = uri.substring(5, separator);
      final base64Data = uri.substring(separator + 8);
      if (base64Data.isEmpty || base64Data.length > 4_200_000) {
        return const <AIImagePart>[];
      }
      return [AIImagePart(mimeType: mimeType, base64Data: base64Data)];
    } catch (_) {
      return const <AIImagePart>[];
    }
  }

  List<AIToolCall>? _toolCallsFromMetadata(String? metadataJson) {
    if (metadataJson == null || metadataJson.isEmpty) return null;
    try {
      final decoded = jsonDecode(metadataJson);
      if (decoded is! Map<String, Object?>) return null;
      final rawCalls = decoded['toolCalls'];
      if (rawCalls is! List) return null;
      final calls = <AIToolCall>[];
      for (final rawCall in rawCalls) {
        if (rawCall is! Map) continue;
        final function = rawCall['function'];
        final id = rawCall['id']?.toString() ?? '';
        final name =
            rawCall['name']?.toString() ??
            (function is Map ? function['name']?.toString() : null) ??
            '';
        final argumentsJson =
            rawCall['argumentsJson']?.toString() ??
            rawCall['arguments']?.toString() ??
            (function is Map ? function['arguments']?.toString() : null) ??
            '';
        if (id.isEmpty || name.isEmpty) continue;
        final providerMetadata = rawCall['providerMetadata'];
        calls.add(
          AIToolCall(
            id: id,
            name: name,
            argumentsJson: argumentsJson,
            providerMetadata: providerMetadata is Map
                ? providerMetadata.cast<String, Object?>()
                : const <String, Object?>{},
          ),
        );
      }
      return calls.isEmpty ? null : calls;
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> _providerMetadataFromMessage(String? metadataJson) {
    if (metadataJson == null || metadataJson.isEmpty) {
      return const <String, Object?>{};
    }
    try {
      final decoded = jsonDecode(metadataJson);
      if (decoded is! Map<String, Object?>) {
        return const <String, Object?>{};
      }
      final providerNativeData = decoded['providerNativeData'];
      return providerNativeData is Map
          ? providerNativeData.cast<String, Object?>()
          : const <String, Object?>{};
    } catch (_) {
      return const <String, Object?>{};
    }
  }

  String _contentForModel(ChatMessage message) {
    if (message.role != MessageRole.user || message.metadataJson == null) {
      return message.content;
    }
    try {
      final decoded = jsonDecode(message.metadataJson!);
      if (decoded is! List || decoded.isEmpty) return message.content;
      final uris = <String>[];
      for (var index = 0; index < decoded.length; index++) {
        if (decoded[index] is Map) {
          uris.add('local://attachment-${index + 1}');
        }
      }
      if (uris.isEmpty) return message.content;
      return '${message.content}\n\nAttached files available: ${uris.join(', ')}';
    } catch (_) {
      return message.content;
    }
  }
}
