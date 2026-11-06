import fs from 'node:fs';
import path from 'node:path';

export interface ProviderInfo {
  id: string;
  name: string;
  badge: string;
  authType: string;
  transport: string;
  defaultBaseUrl: string;
  models: string[];
  capabilities: {
    streaming: boolean;
    tools: boolean;
    reasoning: boolean;
    images: boolean;
  };
  description: string;
  setupGuide: string;
}

export interface ToolInfo {
  name: string;
  category: 'Filesystem' | 'Search' | 'Execution';
  signature: string;
  description: string;
  params: { name: string; type: string; required: boolean; description: string }[];
  example: string;
  resultExample: string;
}

export interface ReleaseInfo {
  version: string;
  versionCode: number;
  channel: 'beta' | 'stable' | 'nightly';
  apkUrl: string;
  sha256: string;
  sizeBytes: number;
  sizeFormatted: string;
  releaseDate: string;
  mandatory: boolean;
  highlights: string[];
}

// Dynamically load update manifests from repository
function loadManifest(channel: 'beta' | 'stable' | 'nightly'): ReleaseInfo {
  const possiblePaths = [
    path.resolve(process.cwd(), `../update/${channel}.json`),
    path.resolve(process.cwd(), `update/${channel}.json`),
    path.resolve(import.meta.dirname || '', `../../../update/${channel}.json`),
  ];

  let raw = '';
  for (const p of possiblePaths) {
    if (fs.existsSync(p)) {
      raw = fs.readFileSync(p, 'utf-8');
      break;
    }
  }

  if (raw) {
    try {
      const data = JSON.parse(raw);
      const sizeMb = (data.size / (1024 * 1024)).toFixed(1);
      return {
        version: data.version,
        versionCode: data.versionCode,
        channel: channel,
        apkUrl: data.apkUrl,
        sha256: data.sha256,
        sizeBytes: data.size,
        sizeFormatted: `${sizeMb} MB`,
        releaseDate: 'Latest',
        mandatory: !!data.mandatory,
        highlights: data.notes || ['On-device project and chat storage', 'Direct model connectivity', 'Surgical file editing tools']
      };
    } catch {
      // Fallback
    }
  }

  // Fallback defaults if manifest cannot be read
  return {
    version: 'Latest',
    versionCode: 1,
    channel: channel,
    apkUrl: 'https://github.com/DraxonV1/Syntac/releases/latest',
    sha256: '',
    sizeBytes: 0,
    sizeFormatted: 'APK',
    releaseDate: 'Latest',
    mandatory: false,
    highlights: ['Autonomous coding agent', 'On-device execution']
  };
}

const betaManifest = loadManifest('beta');
const stableManifest = loadManifest('stable');
const nightlyManifest = loadManifest('nightly');

export const RELEASES: ReleaseInfo[] = [
  betaManifest,
  stableManifest,
  nightlyManifest
];

export const APP_CONFIG = {
  name: 'Syntac',
  displayName: 'Syntac',
  slug: 'syntac',
  tagline: 'Autonomous mobile coding environment',
  subtitle: 'A local-first coding agent built for code work away from a laptop. Review projects, prompt frontier AI models, inspect surgical edits, and build software on-device.',
  developer: 'DraxonV1',
  repoUrl: 'https://github.com/DraxonV1/Syntac',
  releasesUrl: 'https://github.com/DraxonV1/Syntac/releases',
  issuesUrl: 'https://github.com/DraxonV1/Syntac/issues',
  packageId: 'com.syntac',
  currentVersion: stableManifest.version || '0.1.2',
  currentVersionCode: stableManifest.versionCode || 20,
  currentChannel: 'stable',
  domain: 'https://syntac.com',
  metaDescription: 'Syntac is an autonomous, local-first coding agent by DraxonV1. Connect Gemini 3, Claude, and GPT-OSS models to review, edit, and build software on your device.',
  keywords: [
    'Syntac',
    'Syntac Coding Agent',
    'autonomous coding agent',
    'mobile code editor',
    'Gemini 3',
    'Claude',
    'GPT-OSS',
    'local-first coding agent',
    'DraxonV1'
  ],
};

export const PROVIDERS: ProviderInfo[] = [
  {
    id: 'google-antigravity',
    name: 'Google Antigravity',
    badge: 'OAuth Native',
    authType: 'Google OAuth 2.0 (PKCE)',
    transport: 'Google Cloud Code Assist',
    defaultBaseUrl: 'https://daily-cloudcode-pa.googleapis.com',
    models: ['Gemini 3', 'Gemini 3 Flash'],
    capabilities: {
      streaming: true,
      tools: true,
      reasoning: true,
      images: true,
    },
    description: 'Direct deep-linked Google Cloud Code Assist authentication with Gemini 3 models, native reasoning, vision, and tool execution without manual API key copying.',
    setupGuide: 'Tap "Connect with Google", authorize via your browser, and the app captures the OAuth token via syntac:// deep link automatically.'
  },
  {
    id: 'custom-openai-compatible',
    name: 'OpenAI-Compatible & Custom Endpoints',
    badge: 'Universal / Local',
    authType: 'API Key / Bearer',
    transport: 'OpenAI Chat Completions',
    defaultBaseUrl: 'https://api.openai.com/v1',
    models: ['Claude', 'GPT-OSS', 'Custom Models'],
    capabilities: {
      streaming: true,
      tools: true,
      reasoning: true,
      images: true,
    },
    description: 'Connect any OpenAI-compatible inference server or gateway: Claude, GPT-OSS, Ollama, vLLM, LM Studio, Groq, or private self-hosted endpoints.',
    setupGuide: 'Enter your endpoint base URL and your bearer API key in Provider Settings.'
  }
];

export const TOOLS: ToolInfo[] = [
  {
    name: 'read',
    category: 'Filesystem',
    signature: 'read(path, offset?, limit?, startLine?, endLine?, unit?, raw?)',
    description: 'Reads bounded file content or fetches web pages (http/https) with HTML-to-Markdown conversion and line paging.',
    params: [
      { name: 'path', type: 'string', required: true, description: 'Relative file path inside project root' },
      { name: 'startLine', type: 'integer', required: false, description: '1-indexed starting line number' },
      { name: 'endLine', type: 'integer', required: false, description: '1-indexed ending line number' },
      { name: 'limit', type: 'integer', required: false, description: 'Maximum lines or bytes to retrieve' },
    ],
    example: 'read({ path: "src/server/auth.ts", startLine: 1, endLine: 60 })',
    resultExample: 'Lines 1-60 returned with line numbers'
  },
  {
    name: 'edit',
    category: 'Filesystem',
    signature: 'edit(path, target, replacement, requireUnique?, replaceAll?)',
    description: 'Surgically replaces targeted text blocks without re-writing entire files.',
    params: [
      { name: 'path', type: 'string', required: true, description: 'Relative target file path' },
      { name: 'target', type: 'string', required: true, description: 'Exact verbatim source snippet to replace' },
      { name: 'replacement', type: 'string', required: true, description: 'New code snippet to inject' },
    ],
    example: 'edit({\n  path: "src/config.ts",\n  target: "const PORT = 3000;",\n  replacement: "const PORT = process.env.PORT || 8080;"\n})',
    resultExample: 'Replaced 1 match in src/config.ts'
  },
  {
    name: 'write',
    category: 'Filesystem',
    signature: 'write(path, content)',
    description: 'Creates new files or overwrites existing files atomically.',
    params: [
      { name: 'path', type: 'string', required: true, description: 'Relative file path' },
      { name: 'content', type: 'string', required: true, description: 'Full file content payload' },
    ],
    example: 'write({ path: "scripts/deploy.sh", content: "#!/bin/bash\\necho Deploying..." })',
    resultExample: 'Wrote 1,840 bytes to scripts/deploy.sh'
  },
  {
    name: 'search',
    category: 'Search',
    signature: 'search(query, path?, maxResults?, regex?, caseSensitive?, include?, exclude?)',
    description: 'High-speed search across files and filenames with glob filtering and pagination.',
    params: [
      { name: 'query', type: 'string', required: true, description: 'Text or regex search pattern' },
      { name: 'path', type: 'string', required: false, description: 'Subdirectory root to limit search scope' },
    ],
    example: 'search({ query: "ProviderRegistry", include: ["lib/**/*.dart"] })',
    resultExample: 'Found 4 matches in 2 files'
  },
  {
    name: 'web_search',
    category: 'Search',
    signature: 'web_search(query, recency?, limit?)',
    description: 'Searches the web using default DuckDuckGo provider for ranked sources, snippets, and technical information.',
    params: [
      { name: 'query', type: 'string', required: true, description: 'Search query text' },
      { name: 'recency', type: 'string', required: false, description: 'Filter by recency: day, week, month, year' },
      { name: 'limit', type: 'integer', required: false, description: 'Maximum number of results (default: 10, max: 20)' },
    ],
    example: 'web_search({ query: "flutter agent harness", recency: "month" })',
    resultExample: 'Ranked sources with titles, snippets, and URLs'
  },
  {
    name: 'list',
    category: 'Filesystem',
    signature: 'list(path, depth?)',
    description: 'Inspects project directories recursively up to a specified depth.',
    params: [
      { name: 'path', type: 'string', required: true, description: 'Relative directory path' },
    ],
    example: 'list({ path: "lib/src", depth: 2 })',
    resultExample: 'Listed 18 entries across 4 subdirectories'
  },
  {
    name: 'delete',
    category: 'Filesystem',
    signature: 'delete(path, recursive?)',
    description: 'Deletes unwanted files or directories safely.',
    params: [
      { name: 'path', type: 'string', required: true, description: 'Path to target file or directory' },
    ],
    example: 'delete({ path: "temp_build.log" })',
    resultExample: 'Deleted temp_build.log successfully'
  },
  {
    name: 'bash',
    category: 'Execution',
    signature: 'bash(command, timeout_seconds?)',
    description: 'Executes shell commands on-device with output capture and timeout safeguards.',
    params: [
      { name: 'command', type: 'string', required: true, description: 'Shell command line to execute' },
    ],
    example: 'bash({ command: "git status && npm test" })',
    resultExample: 'Exit code: 0\nstdout: 12 tests passed (4.2s)'
  }
];

export const FAQS = [
  {
    q: 'How does Syntac keep project code private?',
    a: 'Syntac is 100% local-first. Your source files, chat history, and API keys stay on your physical device. Model inference calls go directly from your phone to Google, Anthropic, or your custom endpoint over encrypted TLS with zero intermediary servers.'
  },
  {
    q: 'How does Google Antigravity OAuth work?',
    a: 'Syntac uses a standard PKCE OAuth flow. Tapping Connect with Google opens your browser, and upon authorization redirects back into Syntac via the syntac:// deep link to store the token in secure storage.'
  },
  {
    q: 'What models can I use?',
    a: 'Syntac supports Gemini 3 models via Google Cloud Code Assist, as well as Claude, GPT-OSS, and custom models through any OpenAI-compatible endpoint.'
  },
  {
    q: 'What devices and architectures are supported?',
    a: 'Syntac is optimized for 64-bit ARM (ARM64-v8a) devices running Android 8.0 through Android 15+.'
  }
];
