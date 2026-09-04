enum ProviderTransport {
  openAIChatCompletions,
  openAIResponses,
  openAICodexResponses,
  googleCloudCodeAssist,
}

enum ProviderAuthType {
  apiKey,
  googleAntigravityOAuth,
  openAICodexOAuth,
  xaiOAuth,
}

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
    required this.modelsDevProvider,
    required this.defaultModels,
    required this.capabilities,
  });

  final String id;
  final String name;
  final ProviderTransport transport;
  final ProviderAuthType authType;
  final String defaultBaseUrl;
  final String modelsDevProvider;
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
    defaultBaseUrl: '',
    modelsDevProvider: '',
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
    modelsDevProvider: 'openrouter',
    defaultModels: <String>[],
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
    modelsDevProvider: 'deepseek',
    defaultModels: <String>[],
    capabilities: ProviderCapabilities(
      supportsStreaming: true,
      supportsTools: true,
      supportsReasoning: true,
    ),
  );

  static const grok = ProviderDefinition(
    id: 'xai',
    name: 'Grok',
    transport: ProviderTransport.openAIResponses,
    authType: ProviderAuthType.apiKey,
    defaultBaseUrl: 'https://api.x.ai/v1',
    modelsDevProvider: 'xai',
    defaultModels: <String>[],
    capabilities: ProviderCapabilities(
      supportsStreaming: true,
      supportsTools: true,
      supportsReasoning: true,
      supportsImages: true,
    ),
  );

  static const grokOAuth = ProviderDefinition(
    id: 'xai-oauth',
    name: 'Grok OAuth',
    transport: ProviderTransport.openAIResponses,
    authType: ProviderAuthType.xaiOAuth,
    defaultBaseUrl: 'https://api.x.ai/v1',
    modelsDevProvider: 'xai',
    defaultModels: <String>[],
    capabilities: ProviderCapabilities(
      supportsStreaming: true,
      supportsTools: true,
      supportsReasoning: true,
      supportsImages: true,
    ),
  );

  static const openAICodex = ProviderDefinition(
    id: 'openai-codex',
    name: 'ChatGPT (Codex)',
    transport: ProviderTransport.openAICodexResponses,
    authType: ProviderAuthType.openAICodexOAuth,
    defaultBaseUrl: 'https://chatgpt.com/backend-api',
    modelsDevProvider: 'openai',
    defaultModels: <String>[],
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
    modelsDevProvider: 'google',
    defaultModels: <String>[],
    capabilities: ProviderCapabilities(
      supportsStreaming: true,
      supportsTools: true,
      supportsReasoning: true,
      supportsImages: true,
    ),
  );

  static const builtIns = <ProviderDefinition>[
    googleAntigravity,
    openAICodex,
    grokOAuth,
    grok,
    openRouter,
    deepSeek,
    customOpenAICompatible,
  ];

  static bool isVisibleForBeta(String providerKey) =>
      providerKey != 'custom-anthropic-compatible';

  static bool isBuiltin(String providerKey) =>
      builtIns.any((definition) => definition.id == providerKey);

  ProviderDefinition byId(String id) {
    for (final definition in builtIns) {
      if (definition.id == id) return definition;
    }
    return customOpenAICompatible;
  }
}
