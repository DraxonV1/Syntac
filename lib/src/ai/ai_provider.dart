import '../core/cancellation.dart';
import 'provider_diagnostics.dart';

class AIChatMessage {
  const AIChatMessage({
    required this.role,
    required this.content,
    this.name,
    this.toolCallId,
    this.toolCalls,
    this.providerMetadata = const <String, Object?>{},
  });

  final String role;
  final String content;
  final String? name;
  final String? toolCallId;
  final List<AIToolCall>? toolCalls;
  final Map<String, Object?> providerMetadata;

  Map<String, Object?> toJson() {
    final map = <String, Object?>{'role': role, 'content': content};
    if (name != null) map['name'] = name;
    if (toolCallId != null) map['tool_call_id'] = toolCallId;
    if (toolCalls != null && toolCalls!.isNotEmpty) {
      map['tool_calls'] = toolCalls!
          .map((call) => call.toOpenAIJson())
          .toList();
    }
    if (providerMetadata.isNotEmpty) {
      map['provider_metadata'] = providerMetadata;
    }
    return map;
  }
}

class AIToolCall {
  const AIToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
    this.providerMetadata = const <String, Object?>{},
  });

  final String id;
  final String name;
  final String argumentsJson;
  final Map<String, Object?> providerMetadata;

  Map<String, Object?> toOpenAIJson({bool includeProviderMetadata = false}) => {
    'id': id,
    'type': 'function',
    'function': {'name': name, 'arguments': argumentsJson},
    if (includeProviderMetadata && providerMetadata.isNotEmpty)
      'providerMetadata': providerMetadata,
  };
}

class AIChatRequest {
  const AIChatRequest({
    required this.model,
    required this.messages,
    required this.tools,
    this.temperature,
    this.timeout,
  });

  final String model;
  final List<AIChatMessage> messages;
  final List<Map<String, Object?>> tools;
  final double? temperature;
  final Duration? timeout;
}

class AIChatResponse {
  const AIChatResponse({
    required this.text,
    required this.toolCalls,
    required this.finishReason,
    this.providerMetadata = const <String, Object?>{},
  });

  final String text;
  final List<AIToolCall> toolCalls;
  final String? finishReason;
  final Map<String, Object?> providerMetadata;
}

class AIStreamEvent {
  AIStreamEvent.text(
    this.textDelta, {
    DateTime? networkChunkAt,
    DateTime? providerEventAt,
  }) : toolCalls = const <AIToolCall>[],
       finishReason = null,
       providerMetadata = const <String, Object?>{},
       done = false,
       networkChunkAt = networkChunkAt ?? DateTime.now(),
       providerEventAt = providerEventAt ?? networkChunkAt ?? DateTime.now();

  AIStreamEvent.done({
    required this.toolCalls,
    this.finishReason,
    this.providerMetadata = const <String, Object?>{},
    DateTime? networkChunkAt,
    DateTime? providerEventAt,
  }) : textDelta = '',
       done = true,
       networkChunkAt = networkChunkAt ?? DateTime.now(),
       providerEventAt = providerEventAt ?? networkChunkAt ?? DateTime.now();

  final String textDelta;
  final List<AIToolCall> toolCalls;
  final String? finishReason;
  final Map<String, Object?> providerMetadata;
  final bool done;
  final DateTime networkChunkAt;
  final DateTime providerEventAt;
}

abstract class AIProvider {
  Stream<AIStreamEvent> streamChat(
    AIChatRequest request, {
    required String apiKey,
    CancellationToken? cancellationToken,
  });

  Future<AIChatResponse> completeChat(
    AIChatRequest request, {
    required String apiKey,
    CancellationToken? cancellationToken,
  }) async {
    final buffer = StringBuffer();
    var calls = const <AIToolCall>[];
    String? finishReason;
    var providerMetadata = const <String, Object?>{};
    await for (final event in streamChat(
      request,
      apiKey: apiKey,
      cancellationToken: cancellationToken,
    )) {
      cancellationToken?.throwIfCancelled();
      if (event.done) {
        calls = event.toolCalls;
        finishReason = event.finishReason;
        providerMetadata = event.providerMetadata;
      } else {
        buffer.write(event.textDelta);
      }
    }
    return AIChatResponse(
      text: buffer.toString(),
      toolCalls: calls,
      finishReason: finishReason,
      providerMetadata: providerMetadata,
    );
  }
}

class AIProviderException implements Exception {
  const AIProviderException(
    this.message, {
    this.statusCode,
    this.kind = 'provider_error',
    this.details,
  });

  final String message;
  final int? statusCode;
  final String kind;
  final ProviderErrorDetails? details;
  @override
  String toString() => '$kind: $message';
}
