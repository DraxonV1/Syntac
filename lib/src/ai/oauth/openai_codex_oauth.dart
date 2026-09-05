import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../ai_provider.dart';
import 'google_antigravity_oauth.dart';
import 'oauth_credential.dart';

class OpenAICodexOAuthFlow {
  OpenAICodexOAuthFlow({http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _now = now ?? DateTime.now;

  static const providerId = 'openai-codex';
  static const providerName = 'ChatGPT (Codex)';
  static const defaultBaseUrl = 'https://chatgpt.com/backend-api';
  static const callbackPort = 1455;
  static const callbackPath = '/auth/callback';
  static const clientId = 'app_EMoamEEZ73f0CkXaXp7hrann';
  static const authUrl = 'https://auth.openai.com/oauth/authorize';
  static const tokenUrl = 'https://auth.openai.com/oauth/token';
  static const scope =
      'openid profile email offline_access api.connectors.read api.connectors.invoke';
  static const originator = 'codex_cli_rs';

  final http.Client _client;
  final DateTime Function() _now;

  Future<OAuthCredential> login({
    required void Function(OAuthAuthRequest request) onAuthRequest,
    void Function(String message)? onProgress,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      callbackPort,
      shared: false,
    );
    try {
      final state = _randomToken(24);
      final verifier = _randomToken(48);
      final redirectUri = 'http://localhost:$callbackPort$callbackPath';
      onAuthRequest(
        OAuthAuthRequest(
          url: buildAuthorizationUrl(
            state: state,
            redirectUri: redirectUri,
            codeChallenge: _codeChallenge(verifier),
          ),
          redirectUri: redirectUri,
          instructions:
              'Open the URL, sign in with ChatGPT, then return to Syntac.',
        ),
      );
      onProgress?.call('Waiting for ChatGPT authorization...');
      final code = await _waitForCode(
        server,
        expectedState: state,
        timeout: timeout,
      );
      onProgress?.call('Exchanging ChatGPT authorization code...');
      return await exchangeAuthorizationCode(
        code: code,
        verifier: verifier,
        redirectUri: redirectUri,
      );
    } finally {
      await server.close(force: true);
    }
  }

  String buildAuthorizationUrl({
    required String state,
    required String redirectUri,
    required String codeChallenge,
  }) {
    final query = Uri(
      queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'scope': scope,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'state': state,
        'id_token_add_organizations': 'true',
        'codex_cli_simplified_flow': 'true',
        'originator': originator,
      },
    ).query;
    return '$authUrl?$query';
  }

  Future<OAuthCredential> exchangeAuthorizationCode({
    required String code,
    required String verifier,
    required String redirectUri,
  }) async {
    final response = await _client
        .post(
          Uri.parse(tokenUrl),
          headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'grant_type': 'authorization_code',
            'client_id': clientId,
            'code': code,
            'code_verifier': verifier,
            'redirect_uri': redirectUri,
          },
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AIProviderException(
        'ChatGPT token exchange failed: ${response.statusCode}',
        statusCode: response.statusCode,
        kind: 'oauth_error',
      );
    }
    final decoded = _decodeObject(response.body, 'ChatGPT token response');
    final accessToken = decoded['access_token'];
    final refreshToken = decoded['refresh_token'];
    if (accessToken is! String ||
        accessToken.isEmpty ||
        refreshToken is! String ||
        refreshToken.isEmpty) {
      throw const AIProviderException(
        'ChatGPT token response was missing required fields',
        kind: 'malformed_response',
      );
    }
    return _credentialFromTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresIn: _expiresIn(decoded),
      idToken: decoded['id_token'] as String?,
    );
  }

  Future<OAuthCredential> refreshToken(OAuthCredential credential) async {
    final response = await _client
        .post(
          Uri.parse(tokenUrl),
          headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'grant_type': 'refresh_token',
            'client_id': clientId,
            'refresh_token': credential.refreshToken,
          },
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AIProviderException(
        'ChatGPT token refresh failed: ${response.statusCode}',
        statusCode: response.statusCode,
        kind: 'oauth_error',
      );
    }
    final decoded = _decodeObject(response.body, 'ChatGPT refresh response');
    final accessToken = decoded['access_token'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw const AIProviderException(
        'ChatGPT refresh response was malformed',
        kind: 'malformed_response',
      );
    }
    final profile = _tokenProfile(accessToken, decoded['id_token'] as String?);
    return credential.copyWith(
      accessToken: accessToken,
      refreshToken: decoded['refresh_token'] is String
          ? decoded['refresh_token'] as String
          : credential.refreshToken,
      expiresAt: _now().add(Duration(seconds: _expiresIn(decoded))),
      accountId: profile.accountId ?? credential.accountId,
      email: profile.email ?? credential.email,
    );
  }

  Future<String> _waitForCode(
    HttpServer server, {
    required String expectedState,
    required Duration timeout,
  }) async {
    try {
      await for (final request in server.timeout(timeout)) {
        if (request.uri.path != callbackPath) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          continue;
        }
        final error = request.uri.queryParameters['error'];
        final state = request.uri.queryParameters['state'];
        final code = request.uri.queryParameters['code'];
        if (error != null) {
          await _writeCallback(
            request,
            'ChatGPT sign-in failed. Return to Syntac.',
          );
          throw AIProviderException(
            'OAuth callback error: $error',
            kind: 'oauth_error',
          );
        }
        if (state != expectedState || code == null || code.isEmpty) {
          await _writeCallback(
            request,
            'Invalid OAuth callback. Return to Syntac.',
          );
          throw const AIProviderException(
            'Invalid OAuth callback',
            kind: 'oauth_error',
          );
        }
        await _writeCallback(
          request,
          'ChatGPT sign-in complete. Return to Syntac.',
        );
        return code;
      }
    } on TimeoutException {
      throw const AIProviderException(
        'Timed out waiting for ChatGPT sign-in',
        kind: 'timeout',
      );
    }
    throw const AIProviderException(
      'Timed out waiting for ChatGPT sign-in',
      kind: 'timeout',
    );
  }

  Future<void> _writeCallback(HttpRequest request, String message) async {
    request.response.headers.contentType = ContentType.html;
    request.response.write(
      '<!doctype html><title>Syntac</title><p>$message</p>',
    );
    await request.response.close();
  }

  OAuthCredential _credentialFromTokens({
    required String accessToken,
    required String refreshToken,
    required int expiresIn,
    String? idToken,
  }) {
    final profile = _tokenProfile(accessToken, idToken);
    if (profile.accountId == null) {
      throw const AIProviderException(
        'ChatGPT token did not contain an account id',
        kind: 'oauth_error',
      );
    }
    return OAuthCredential(
      provider: OAuthProviderId.openAICodex,
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: _now().add(Duration(seconds: expiresIn)),
      accountId: profile.accountId,
      email: profile.email,
      authorizedAt: _now(),
    );
  }
}

class _TokenProfile {
  const _TokenProfile({this.accountId, this.email});
  final String? accountId;
  final String? email;
}

_TokenProfile _tokenProfile(String accessToken, String? idToken) {
  final access = _decodeJwt(accessToken);
  final id = idToken == null ? null : _decodeJwt(idToken);
  final accessAuth = access?['https://api.openai.com/auth'];
  final idAuth = id?['https://api.openai.com/auth'];
  final accessProfile = access?['https://api.openai.com/profile'];
  final idProfile = id?['https://api.openai.com/profile'];
  final accountId = _firstClaim(accessAuth, idAuth, 'chatgpt_account_id');
  final email = _firstClaim(accessProfile, idProfile, 'email');
  return _TokenProfile(
    accountId: accountId is String && accountId.isNotEmpty ? accountId : null,
    email: email is String && email.isNotEmpty ? email.toLowerCase() : null,
  );
}

Object? _firstClaim(Object? first, Object? second, String key) {
  if (first is Map && first[key] != null) return first[key];
  if (second is Map && second[key] != null) return second[key];
  return null;
}

Map<String, Object?>? _decodeJwt(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    final decoded = jsonDecode(payload);
    return decoded is Map ? decoded.cast<String, Object?>() : null;
  } catch (_) {
    return null;
  }
}

Map<String, Object?> _decodeObject(String body, String label) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) return decoded.cast<String, Object?>();
  } catch (_) {}
  throw AIProviderException('$label was malformed', kind: 'malformed_response');
}

int _expiresIn(Map<String, Object?> body) => body['expires_in'] is num
    ? (body['expires_in'] as num).toInt()
    : int.tryParse(body['expires_in']?.toString() ?? '') ?? 3600;

String _randomToken(int length) {
  final random = Random.secure();
  final bytes = List<int>.generate(length, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

String _codeChallenge(String verifier) => base64UrlEncode(
  sha256.convert(ascii.encode(verifier)).bytes,
).replaceAll('=', '');
