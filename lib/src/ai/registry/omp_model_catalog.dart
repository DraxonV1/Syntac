/// Model IDs copied from OMP v18.1.6 catalog snapshot.
///
/// Runtime refresh still treats provider `/models` or Cloud Code Assist discovery
/// as authoritative. These lists only seed a new provider before first refresh.
class OmpModelCatalog {
  const OmpModelCatalog._();

  static const googleAntigravity = <String>[
    'gemini-3.1-pro',
    'claude-opus-4-5',
    'claude-opus-4-6',
    'claude-sonnet-4-5',
    'claude-sonnet-4-6',
    'gemini-2.5-flash',
    'gemini-2.5-flash-lite',
    'gemini-2.5-pro',
    'gemini-3-flash',
    'gemini-3-pro',
    'gemini-3.1-flash-image',
    'gemini-3.1-flash-lite',
    'gemini-3.5-flash',
    'gemini-3.6-flash',
    'gemini-3.7-flash',
    'gemini-3.8-flash',
    'gpt-oss-120b',
    'tab_flash_lite_preview',
    'tab_jump_flash_lite_preview',
  ];

  static const xai = <String>[
    'grok-4.6',
    'grok-2',
    'grok-2-1212',
    'grok-2-latest',
    'grok-2-vision',
    'grok-2-vision-1212',
    'grok-2-vision-latest',
    'grok-3',
    'grok-3-fast',
    'grok-3-fast-latest',
    'grok-3-latest',
    'grok-3-mini',
    'grok-3-mini-fast',
    'grok-3-mini-fast-latest',
    'grok-3-mini-latest',
    'grok-4',
    'grok-4-1-fast',
    'grok-4-1-fast-non-reasoning',
    'grok-4-fast',
    'grok-4-fast-non-reasoning',
    'grok-4.20-0309-non-reasoning',
    'grok-4.20-0309-reasoning',
    'grok-4.20-beta-latest-non-reasoning',
    'grok-4.20-beta-latest-reasoning',
    'grok-4.20-multi-agent-beta-latest',
    'grok-4.3',
    'grok-4.5',
    'grok-beta',
    'grok-build-0.1',
    'grok-code-fast-1',
    'grok-vision-beta',
  ];

  static const xaiOAuth = <String>[
    'grok-4.6',
    'grok-build',
    'grok-build-0.1',
    'grok-4.3',
    'grok-4.5',
    'grok-4.20-multi-agent-0309',
    'grok-4.20-0309-reasoning',
    'grok-4.20-0309-non-reasoning',
    'grok-composer-2.5-fast',
  ];

  static const openAICodex = <String>[
    'gpt-5.5',
    'gpt-5.3-codex-spark',
    'gpt-5.4',
    'gpt-5.4-mini',
    'gpt-5.6-luna',
    'gpt-5.6-sol',
    'gpt-5.6-terra',
    'gpt-daybreak-blue-latest',
  ];
}
