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
      final converted = _convert(message);
      final cost =
          converted.content.length + (message.metadataJson?.length ?? 0) + 32;
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

  AIChatMessage _convert(ChatMessage message) {
    final role = switch (message.role) {
      MessageRole.system => 'system',
      MessageRole.user => 'user',
      MessageRole.assistant => 'assistant',
      MessageRole.tool => 'tool',
      MessageRole.internal => 'system',
    };
    return AIChatMessage(
      role: role,
      content: message.content,
      toolCallId: message.toolCallId,
      toolCalls: message.role == MessageRole.assistant
          ? _toolCallsFromMetadata(message.metadataJson)
          : null,
      providerMetadata: message.role == MessageRole.assistant
          ? _providerMetadataFromMessage(message.metadataJson)
          : const <String, Object?>{},
    );
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
}
