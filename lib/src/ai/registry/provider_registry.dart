enum ProviderTransport { openAIChatCompletions, googleCloudCodeAssist }

enum ProviderAuthType { apiKey, googleAntigravityOAuth }

class ProviderCapabilities {
  const ProviderCapabilities({
    required this.supportsStreaming,
    required this.supportsTools,
    this.supportsReasoning = false,
    this.supportsImages = false,
    this.supportsNativeWebSearch = false,
  });

  final bool supportsStreaming;
  final bool supportsTools;
  final bool supportsReasoning;
  final bool supportsImages;
  final bool supportsNativeWebSearch;
}

class ProviderDefinition {
  const ProviderDefinition({
    required this.id,
    required this.name,
    required this.transport,
    required this.authType,
    required this.defaultBaseUrl,
    required this.defaultModels,
    required this.capabilities,
  });

  final String id;
  final String name;
  final ProviderTransport transport;
  final ProviderAuthType authType;
  final String defaultBaseUrl;
  final List<String> defaultModels;
  final ProviderCapabilities capabilities;
}

class ProviderRegistry {
  const ProviderRegistry();

  static const customOpenAICompatible = ProviderDefinition(
    id: 'custom-openai-compatible',
    name: 'Custom OpenAI-compatible',
    transport: ProviderTransport.openAIChatCompletions,
    authType: ProviderAuthType.apiKey,
    defaultBaseUrl: 'https://example.com/v1',
    defaultModels: <String>[],
    capabilities: ProviderCapabilities(
      supportsStreaming: true,
      supportsTools: true,
    ),
  );

  static const openRouter = ProviderDefinition(
    id: 'openrouter',
    name: 'OpenRouter',
    transport: ProviderTransport.openAIChatCompletions,
    authType: ProviderAuthType.apiKey,
    defaultBaseUrl: 'https://openrouter.ai/api/v1',
    defaultModels: <String>['openai/gpt-4o-mini'],
    capabilities: ProviderCapabilities(
      supportsStreaming: true,
      supportsTools: true,
    ),
  );

  static const deepSeek = ProviderDefinition(
    id: 'deepseek',
    name: 'DeepSeek',
    transport: ProviderTransport.openAIChatCompletions,
    authType: ProviderAuthType.apiKey,
    defaultBaseUrl: 'https://api.deepseek.com',
    defaultModels: <String>['deepseek-chat', 'deepseek-reasoner'],
    capabilities: ProviderCapabilities(
      supportsStreaming: true,
      supportsTools: true,
      supportsReasoning: true,
    ),
  );

  static const googleAntigravity = ProviderDefinition(
    id: 'google-antigravity',
    name: 'Google Antigravity',
    transport: ProviderTransport.googleCloudCodeAssist,
    authType: ProviderAuthType.googleAntigravityOAuth,
    defaultBaseUrl: 'https://daily-cloudcode-pa.googleapis.com',
    defaultModels: <String>['gemini-3.1-pro', 'gemini-3.5-flash'],
    capabilities: ProviderCapabilities(
      supportsStreaming: true,
      supportsTools: true,
      supportsReasoning: true,
      supportsImages: true,
    ),
  );

  static const builtIns = <ProviderDefinition>[
    googleAntigravity,
    openRouter,
    deepSeek,
    customOpenAICompatible,
  ];

  static bool isVisibleForBeta(String providerKey) =>
      providerKey != 'custom-anthropic-compatible';

  ProviderDefinition byId(String id) {
    for (final definition in builtIns) {
      if (definition.id == id) return definition;
    }
    return customOpenAICompatible;
  }
}
