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
       _clientId =
           clientId ??
           (_defaultClientId.isEmpty ? _bundledClientId : _defaultClientId),
       _clientSecret =
           clientSecret ??
           (_defaultClientSecret.isEmpty
               ? _bundledClientSecret
               : _defaultClientSecret);

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

  static final _bundledClientId = String.fromCharCodes(<int>[
    49,
    48,
    55,
    49,
    48,
    48,
    54,
    48,
    54,
    48,
    53,
    57,
    49,
    45,
    116,
    109,
    104,
    115,
    115,
    105,
    110,
    50,
    104,
    50,
    49,
    108,
    99,
    114,
    101,
    50,
    51,
    53,
    118,
    116,
    111,
    108,
    111,
    106,
    104,
    52,
    103,
    52,
    48,
    51,
    101,
    112,
    46,
    97,
    112,
    112,
    115,
    46,
    103,
    111,
    111,
    103,
    108,
    101,
    117,
    115,
    101,
    114,
    99,
    111,
    110,
    116,
    101,
    110,
    116,
    46,
    99,
    111,
    109,
  ]);
  static final _bundledClientSecret = String.fromCharCodes(<int>[
    71,
    79,
    67,
    83,
    80,
    88,
    45,
    75,
    53,
    56,
    70,
    87,
    82,
    52,
    56,
    54,
    76,
    100,
    76,
    74,
    49,
    109,
    76,
    66,
    56,
    115,
    88,
    67,
    52,
    122,
    54,
    113,
    68,
    65,
    102,
  ]);
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
    try {
      final initial = await _loadCodeAssist(headers);
      if (_hasField(initial, 'cloudaicompanionProject')) {
        final project = _extractProjectId(initial);
        if (project != null) return project;
      }
      final currentTier = initial is Map ? initial['currentTier'] : null;
      if (currentTier == null) {
        onProgress?.call('Provisioning Antigravity project...');
        await _onboardProject(headers);
      }
      final refreshed = await _loadCodeAssist(headers);
      final project = _extractProjectId(refreshed);
      if (project != null) return project;
      throw const AIProviderException(
        'loadCodeAssist did not return a cloudaicompanionProject',
        kind: 'oauth_error',
      );
    } on AIProviderException {
      rethrow;
    } catch (error) {
      throw AIProviderException(
        'Cloud Code Assist project discovery failed: $error',
        kind: 'oauth_error',
      );
    }
  }

  Future<Object?> _loadCodeAssist(Map<String, String> headers) async {
    var response = await _client
        .post(
          Uri.parse('$dailyCloudCodeEndpoint/v1internal:loadCodeAssist'),
          headers: headers,
          body: jsonEncode({
            'metadata': {'ideType': 'ANTIGRAVITY'},
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AIProviderException(
        'loadCodeAssist failed: ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
        kind: 'oauth_error',
      );
    }
    var decoded = jsonDecode(response.body);
    if (decoded is Map &&
        decoded['paidTier'] == null &&
        _extractProjectId(decoded) != null) {
      response = await _client
          .post(
            Uri.parse('$dailyCloudCodeEndpoint/v1internal:loadCodeAssist'),
            headers: headers,
            body: jsonEncode({
              'cloudaicompanionProject': _extractProjectId(decoded),
              'metadata': {'ideType': 'ANTIGRAVITY'},
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AIProviderException(
          'loadCodeAssist failed: ${response.statusCode}: ${response.body}',
          statusCode: response.statusCode,
          kind: 'oauth_error',
        );
      }
      decoded = jsonDecode(response.body);
    }
    return decoded;
  }

  bool _hasField(Object? value, String key) =>
      value is Map && value.containsKey(key) && value[key] != null;

  Future<List<String>> discoverModels(String accessToken) async {
    final headers = {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
      'User-Agent': antigravityUserAgent,
    };
    for (final endpoint in [dailyCloudCodeEndpoint, cloudCodeEndpoint]) {
      try {
        final response = await _client
            .post(
              Uri.parse('$endpoint/v1internal:fetchAvailableModels'),
              headers: headers,
              body: '{}',
            )
            .timeout(const Duration(seconds: 30));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }
        final models = _extractAntigravityModels(jsonDecode(response.body));
        if (models.isNotEmpty) return models;
      } catch (_) {
        continue;
      }
    }

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

  Future<void> _onboardProject(Map<String, String> headers) async {
    final operationHeaders = {
      ...headers,
      'User-Agent': '$antigravityUserAgent $_nodeApiClientUserAgent',
      'X-Goog-Api-Client': _googApiClientHeader,
    };
    var response = await _client
        .post(
          Uri.parse('$dailyCloudCodeEndpoint/v1internal:onboardUser'),
          headers: operationHeaders,
          body: jsonEncode({
            'tierId': _freeTier,
            'metadata': {'ideType': 'ANTIGRAVITY'},
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
    var decoded = jsonDecode(response.body);
    for (var attempt = 0; attempt < 30; attempt++) {
      if (decoded is! Map) {
        throw const AIProviderException(
          'onboardUser response was malformed',
          kind: 'malformed_response',
        );
      }
      if (decoded['done'] == true) {
        if (decoded['error'] != null) {
          throw AIProviderException(
            'onboardUser operation failed: ${decoded['error']}',
            kind: 'oauth_error',
          );
        }
        return;
      }
      final name = decoded['name'];
      if (name is! String || name.isEmpty) {
        throw const AIProviderException(
          'onboardUser returned an operation without a name',
          kind: 'malformed_response',
        );
      }
      await Future<void>.delayed(const Duration(seconds: 1));
      response = await _client
          .get(
            Uri.parse('$dailyCloudCodeEndpoint/v1internal/$name'),
            headers: operationHeaders,
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AIProviderException(
          'onboardUser operation failed: ${response.statusCode}: ${response.body}',
          statusCode: response.statusCode,
          kind: 'oauth_error',
        );
      }
      decoded = jsonDecode(response.body);
    }
    throw const AIProviderException(
      'onboardUser timed out while provisioning project',
      kind: 'timeout',
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

List<String> _extractAntigravityModels(Object? value) {
  if (value is! Map || value['models'] is! Map) {
    return const <String>[];
  }
  final models = <String>[];
  for (final entry in (value['models'] as Map).entries) {
    final modelId = entry.key.toString().trim();
    final metadata = entry.value;
    if (metadata is Map && metadata['isInternal'] == true) continue;
    if (!_isSupportedModelName(modelId)) continue;
    models.add(modelId.replaceFirst('models/', ''));
  }
  return models;
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
      models.add(model.trim().replaceFirst('models/', ''));
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
