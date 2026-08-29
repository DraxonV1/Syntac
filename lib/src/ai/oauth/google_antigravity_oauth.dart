import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../ai_provider.dart';
import 'oauth_credential.dart';

class OAuthAuthRequest {
  const OAuthAuthRequest({
    required this.url,
    required this.redirectUri,
    this.launchUrl,
    this.instructions =
        'Open your browser to sign in. The authorization will return to the app automatically.',
  });

  final String url;
  final String redirectUri;
  final String? launchUrl;
  final String instructions;
}

class GoogleAntigravityOAuthFlow {
  GoogleAntigravityOAuthFlow({
    http.Client? client,
    DateTime Function()? now,
    String? clientId,
    String? clientSecret,
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now,
       _clientId = clientId ?? _defaultClientId,
       _clientSecret = clientSecret ?? _defaultClientSecret;

  static const providerId = 'google-antigravity';
  static const providerName = 'Google Antigravity';
  static const defaultBaseUrl = 'https://daily-cloudcode-pa.googleapis.com';
  static const callbackPort = 51121;
  static const callbackPath = '/oauth-callback';
  static const authUrl = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const tokenUrl = 'https://oauth2.googleapis.com/token';
  static const dailyCloudCodeEndpoint =
      'https://daily-cloudcode-pa.googleapis.com';
  static const cloudCodeEndpoint = 'https://cloudcode-pa.googleapis.com';
  static const antigravityUserAgent =
      'antigravity/hub/2.8.0 (aidev_client; os_type=darwin; arch=arm64; cl=963137146)';

  static const _defaultClientId = String.fromEnvironment(
    'SYNTAC_GOOGLE_OAUTH_CLIENT_ID',
  );
  static const _defaultClientSecret = String.fromEnvironment(
    'SYNTAC_GOOGLE_OAUTH_CLIENT_SECRET',
  );
  static const _nodeApiClientUserAgent = 'google-api-nodejs-client/10.3.0';
  static const _googApiClientHeader = 'gl-node/22.21.1';
  static const _freeTier = 'free-tier';

  static const scopes = <String>[
    'https://www.googleapis.com/auth/cloud-platform',
    'https://www.googleapis.com/auth/userinfo.email',
    'https://www.googleapis.com/auth/userinfo.profile',
    'https://www.googleapis.com/auth/cclog',
    'https://www.googleapis.com/auth/experimentsandconfigs',
  ];

  final http.Client _client;
  final DateTime Function() _now;
  final String _clientId;
  final String _clientSecret;

  Future<OAuthCredential> login({
    required void Function(OAuthAuthRequest request) onAuthRequest,
    void Function(String message)? onProgress,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      callbackPort,
      shared: true,
    );
    try {
      final state = _randomState();
      final redirectUri = 'http://127.0.0.1:${server.port}$callbackPath';
      onAuthRequest(
        OAuthAuthRequest(
          url: buildAuthorizationUrl(state: state, redirectUri: redirectUri),
          redirectUri: redirectUri,
        ),
      );
      onProgress?.call('Waiting for Google authorization...');
      final code = await _waitForAuthorizationCode(
        server,
        expectedState: state,
        timeout: timeout,
      );
      onProgress?.call('Exchanging authorization code...');
      final token = await exchangeAuthorizationCode(
        code: code,
        redirectUri: redirectUri,
      );
      onProgress?.call('Getting Google account info...');
      final email = await fetchUserEmail(token.accessToken);
      onProgress?.call('Discovering Antigravity project...');
      final projectId = await discoverProject(
        token.accessToken,
        onProgress: onProgress,
      );
      return token.copyWith(
        projectId: projectId,
        email: email,
        authorizedAt: _now(),
      );
    } finally {
      await server.close(force: true);
    }
  }

  String buildAuthorizationUrl({
    required String state,
    required String redirectUri,
  }) {
    _requireClientCredentials();
    _validateCallbackRedirectUri(redirectUri);
    final params = Uri(
      queryParameters: {
        'client_id': _clientId,
        'response_type': 'code',
        'redirect_uri': redirectUri,
        'scope': scopes.join(' '),
        'state': state,
        'access_type': 'offline',
        'prompt': 'consent',
      },
    ).query;
    return '$authUrl?$params';
  }

  Future<OAuthCredential> exchangeAuthorizationCode({
    required String code,
    required String redirectUri,
  }) async {
    _requireClientCredentials();
    _validateCallbackRedirectUri(redirectUri);
    final response = await _client
        .post(
          Uri.parse(tokenUrl),
          headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'client_id': _clientId,
            'client_secret': _clientSecret,
            'code': code,
            'grant_type': 'authorization_code',
            'redirect_uri': redirectUri,
          },
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AIProviderException(
        'Token exchange failed: ${response.body}',
        statusCode: response.statusCode,
        kind: 'oauth_error',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['access_token'] is! String) {
      throw const AIProviderException(
        'Google token response was malformed',
        kind: 'malformed_response',
      );
    }
    final refreshToken = decoded['refresh_token'];
    if (refreshToken is! String || refreshToken.isEmpty) {
      throw const AIProviderException(
        'No refresh token received. Sign in again and approve offline access.',
        kind: 'oauth_error',
      );
    }
    final expiresIn = decoded['expires_in'] is num
        ? (decoded['expires_in'] as num).toInt()
        : int.tryParse(decoded['expires_in']?.toString() ?? '') ?? 3600;
    return OAuthCredential(
      provider: OAuthProviderId.googleAntigravity,
      accessToken: decoded['access_token'] as String,
      refreshToken: refreshToken,
      expiresAt: _now()
          .add(Duration(seconds: expiresIn))
          .subtract(const Duration(minutes: 5)),
    );
  }

  Future<OAuthCredential> refreshToken(OAuthCredential credential) async {
    _requireClientCredentials();
    final response = await _client
        .post(
          Uri.parse(tokenUrl),
          headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'client_id': _clientId,
            'client_secret': _clientSecret,
            'refresh_token': credential.refreshToken,
            'grant_type': 'refresh_token',
          },
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AIProviderException(
        'Antigravity token refresh failed: ${response.body}',
        statusCode: response.statusCode,
        kind: 'oauth_error',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['access_token'] is! String) {
      throw const AIProviderException(
        'Google refresh response was malformed',
        kind: 'malformed_response',
      );
    }
    final expiresIn = decoded['expires_in'] is num
        ? (decoded['expires_in'] as num).toInt()
        : int.tryParse(decoded['expires_in']?.toString() ?? '') ?? 3600;
    return credential.copyWith(
      accessToken: decoded['access_token'] as String,
      refreshToken: decoded['refresh_token'] is String
          ? decoded['refresh_token'] as String
          : credential.refreshToken,
      expiresAt: _now()
          .add(Duration(seconds: expiresIn))
          .subtract(const Duration(minutes: 5)),
    );
  }

  Future<String?> fetchUserEmail(String accessToken) async {
    try {
      final response = await _client
          .get(
            Uri.parse('https://www.googleapis.com/oauth2/v1/userinfo?alt=json'),
            headers: {'Authorization': 'Bearer $accessToken'},
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      return decoded is Map ? decoded['email'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  Future<String> discoverProject(
    String accessToken, {
    void Function(String message)? onProgress,
  }) async {
    final headers = {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
      'User-Agent': antigravityUserAgent,
    };
    var fallbackTier = _freeTier;
    var loadedSuccessfully = false;
    int? lastStatus;
    String? lastBody;
    for (final endpoint in [dailyCloudCodeEndpoint, cloudCodeEndpoint]) {
      final response = await _client
          .post(
            Uri.parse('$endpoint/v1internal:loadCodeAssist'),
            headers: headers,
            body: jsonEncode({
              'metadata': {'ideType': 'ANTIGRAVITY'},
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        lastStatus = response.statusCode;
        lastBody = response.body;
        continue;
      }
      loadedSuccessfully = true;
      final decoded = jsonDecode(response.body);
      final project = _extractProjectId(decoded);
      if (project != null) return project;
      fallbackTier = _defaultTierId(decoded) ?? fallbackTier;
    }
    if (!loadedSuccessfully && lastStatus != null) {
      throw AIProviderException(
        'loadCodeAssist failed: $lastStatus: ${lastBody ?? 'unknown error'}',
        statusCode: lastStatus,
        kind: 'oauth_error',
      );
    }
    onProgress?.call('Provisioning Antigravity project...');
    return _onboardProject(accessToken, fallbackTier);
  }

  Future<List<String>> discoverModels(String accessToken) async {
    final headers = {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
      'User-Agent': antigravityUserAgent,
    };
    final models = <String>{};
    for (final endpoint in [dailyCloudCodeEndpoint, cloudCodeEndpoint]) {
      try {
        final response = await _client
            .post(
              Uri.parse('$endpoint/v1internal:loadCodeAssist'),
              headers: headers,
              body: jsonEncode({
                'metadata': {'ideType': 'ANTIGRAVITY'},
              }),
            )
            .timeout(const Duration(seconds: 30));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }
        _collectGeminiModels(jsonDecode(response.body), models);
      } catch (_) {
        continue;
      }
    }
    return models.toList(growable: false);
  }

  Future<String> _onboardProject(String accessToken, String tierId) async {
    final headers = {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
      'User-Agent': '$antigravityUserAgent $_nodeApiClientUserAgent',
      'X-Goog-Api-Client': _googApiClientHeader,
    };
    for (var attempt = 0; attempt < 5; attempt++) {
      final response = await _client
          .post(
            Uri.parse('$dailyCloudCodeEndpoint/v1internal:onboardUser'),
            headers: headers,
            body: jsonEncode({
              'tier_id': tierId,
              'metadata': {
                'ide_type': 'ANTIGRAVITY',
                'ide_version': '2.8.0',
                'ide_name': 'antigravity',
              },
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AIProviderException(
          'onboardUser failed: ${response.statusCode}: ${response.body}',
          statusCode: response.statusCode,
          kind: 'oauth_error',
        );
      }
      final decoded = jsonDecode(response.body);
      final project = _extractProjectId(decoded);
      if (project != null) return project;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    throw const AIProviderException(
      'onboardUser did not return a provisioned project id',
      kind: 'oauth_error',
    );
  }

  Future<String> _waitForAuthorizationCode(
    HttpServer server, {
    required String expectedState,
    required Duration timeout,
  }) async {
    try {
      await for (final request in server.timeout(timeout)) {
        final uri = request.uri;
        if (uri.path != callbackPath) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          continue;
        }
        final state = uri.queryParameters['state'];
        final code = uri.queryParameters['code'];
        final error = uri.queryParameters['error'];
        if (error != null) {
          await _writeCallbackResponse(
            request,
            'Google sign-in failed. Return to the app.',
          );
          throw AIProviderException(
            'OAuth callback error: $error',
            kind: 'oauth_error',
          );
        }
        if (state != expectedState || code == null || code.isEmpty) {
          await _writeCallbackResponse(
            request,
            'Invalid OAuth callback. Return to the app and retry.',
          );
          throw const AIProviderException(
            'Invalid OAuth callback',
            kind: 'oauth_error',
          );
        }
        await _writeCallbackResponse(
          request,
          'Google sign-in complete. Return to Syntac.',
        );
        return code;
      }
    } on TimeoutException {
      throw const AIProviderException(
        'Timed out waiting for Google sign-in',
        kind: 'timeout',
      );
    }
    throw const AIProviderException(
      'Timed out waiting for Google sign-in',
      kind: 'timeout',
    );
  }

  Future<void> _writeCallbackResponse(
    HttpRequest request,
    String message,
  ) async {
    request.response.headers.contentType = ContentType.html;
    final escaped = _escapeHtml(message);
    request.response.write(
      '<!doctype html><title>Syntac</title><p>$escaped</p>',
    );
    await request.response.close();
  }

  void _requireClientCredentials() {
    if (_clientId.isEmpty || _clientSecret.isEmpty) {
      throw const AIProviderException(
        'Google Antigravity OAuth client credentials are not configured',
        kind: 'oauth_error',
      );
    }
  }

  String _randomState() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

String? _extractProjectId(Object? value) {
  if (value is! Map) return null;
  for (final key in const ['cloudaicompanionProject', 'projectId', 'project']) {
    final project = value[key];
    if (project is String && project.isNotEmpty) return project;
    if (project is Map && project['id'] is String) {
      return project['id'] as String;
    }
  }
  final response = value['response'];
  if (response is Map) return _extractProjectId(response);
  final metadata = value['metadata'];
  if (metadata is Map) return _extractProjectId(metadata);
  return null;
}

String? _defaultTierId(Object? value) {
  if (value is! Map) return null;
  final tiers = value['allowedTiers'];
  if (tiers is List) {
    for (final tier in tiers) {
      if (tier is Map && tier['isDefault'] == true && tier['id'] is String) {
        return tier['id'] as String;
      }
    }
    for (final tier in tiers) {
      if (tier is Map && tier['id'] is String) return tier['id'] as String;
    }
  }
  final current = value['currentTier'];
  if (current is Map && current['id'] is String) return current['id'] as String;
  return null;
}

void _collectGeminiModels(Object? value, Set<String> models) {
  if (value is List) {
    for (final child in value) {
      _collectGeminiModels(child, models);
    }
    return;
  }
  if (value is! Map) return;
  for (final key in const ['model', 'modelId', 'id', 'name']) {
    final model = value[key];
    if (model is String && _isSupportedModelName(model)) {
      models.add(model);
    }
  }
  for (final child in value.values) {
    _collectGeminiModels(child, models);
  }
}

bool _isSupportedModelName(String value) {
  final clean = value.trim();
  if (clean.isEmpty || clean.contains(RegExp(r'\s'))) return false;
  if (clean.contains('MODEL_PLACEHOLDER')) return false;
  if (clean.length > 120) return false;
  return RegExp(r'^(gemini|models/gemini)-[A-Za-z0-9_.-]+$').hasMatch(clean);
}

void _validateCallbackRedirectUri(String redirectUri) {
  final uri = Uri.tryParse(redirectUri);
  final host = uri?.host.toLowerCase();
  final validHost = host == '127.0.0.1' || host == 'localhost';
  if (uri == null ||
      uri.scheme != 'http' ||
      !validHost ||
      uri.port != GoogleAntigravityOAuthFlow.callbackPort ||
      uri.path != GoogleAntigravityOAuthFlow.callbackPath) {
    throw const AIProviderException(
      'Invalid OAuth callback redirect URI',
      kind: 'oauth_error',
    );
  }
}

String _escapeHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
