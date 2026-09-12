// Direct DeepSeek Chat Completions policy, verified against OMP e24466515d.
import 'ai_provider.dart';

String deepSeekEffort(AIReasoningEffort? effort) => switch (effort) {
  AIReasoningEffort.minimal || AIReasoningEffort.low => 'low',
  AIReasoningEffort.max => 'max',
  _ => 'high',
};

void validateDeepSeekReasoningReplay(AIChatRequest request) {
  if (!request.includeThinking || request.tools.isEmpty) return;
  for (final message in request.messages) {
    if (message.role != 'assistant') continue;
    final metadata = message.providerMetadata;
    if (metadata['provider'] != 'deepseek' ||
        metadata['reasoning_content'] is! String) {
      throw const AIProviderException(
        'This chat predates DeepSeek reasoning replay. Start a new chat before using DeepSeek tools.',
        kind: 'context_limit',
      );
    }
  }
}

Map<String, Object?> deepSeekMessage(AIChatMessage message) {
  final wire = message.toJson()..remove('provider_metadata');
  final metadata = message.providerMetadata;
  if (message.role == 'assistant' && metadata['provider'] == 'deepseek') {
    if (metadata['reasoning_contentTruncated'] == true) {
      throw const AIProviderException(
        'Stored DeepSeek reasoning is truncated. Start a new chat to preserve tool continuity.',
        kind: 'context_limit',
      );
    }
    final reasoning = metadata['reasoning_content'];
    if (reasoning is String) wire['reasoning_content'] = reasoning;
  }
  return wire;
}
