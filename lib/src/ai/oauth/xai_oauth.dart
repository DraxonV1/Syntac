import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/cancellation.dart';
import 'google_antigravity_oauth.dart';
import 'oauth_credential.dart';

class XAIOAuthFlow {
  XAIOAuthFlow({
    http.Client? client,
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _now = now ?? DateTime.now,
       _sleep = sleep ?? ((duration) => Future<void>.delayed(duration));

  static const providerId = 'xai-oauth';
  static const providerName = 'xAI Grok OAuth';
  static const defaultBaseUrl = 'https://api.x.ai/v1';
  static const clientId = 'b1a00492-073a-47ea-816f-4c329264a828';
  static const scope =
      'openid profile email offline_access grok-cli:access api:access';
  static const issuer = 'https://auth.x.ai';
  static const discoveryUrl = '$issuer/.well-known/openid-configuration';
  static const deviceCodeUrl = '$issuer/oauth2/device/code';
  static const userInfoUrl = '$issuer/oauth2/userinfo';

  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;

  Future<OAuthCredential> login({
    required void Function(OAuthAuthRequest request) onAuthRequest,
    void Function(String message)? onProgress,
    CancellationToken? cancellationToken,
  }) async {
    final device = await _requestDeviceCode(cancellationToken);
    onAuthRequest(
      OAuthAuthRequest(
        url: device.verificationUri,
        redirectUri: device.verificationUri,
        launchUrl: device.verificationUriComplete,
        instructions: 'Enter code: ${device.userCode}',
      ),
    );

    onProgress?.call('Waiting for device authorization...');
    try {
      final tokenEndpoint = await _tokenEndpoint(cancellationToken);
      final token = await _pollToken(tokenEndpoint, device, cancellationToken);
      return await _credentialFromToken(token, cancellationToken);
    } finally {
      if (_ownsClient) _client.close();
    }
  }

  Future<OAuthCredential> refreshToken(
    OAuthCredential credential, {
    CancellationToken? cancellationToken,
  }) async {
    if (credential.refreshToken.isEmpty) {
      throw const OAuthException('xAI refresh token missing');
    }
    try {
      final endpoint = await _tokenEndpoint(cancellationToken);
      final response = await _postForm(Uri.parse(endpoint), {
        'grant_type': 'refresh_token',
        'client_id': clientId,
        'refresh_token': credential.refreshToken,
      }, cancellationToken);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _oauthError(response, 'xAI token refresh failed');
      }
      final decoded = _decodeObject(response.body, 'xAI token refresh');
      final accessToken = _string(decoded['access_token']);
      if (accessToken == null || accessToken.isEmpty) {
        throw const OAuthException('xAI token response missing access token');
      }
      return _credentialFromTokenPayload(
        accessToken,
        _string(decoded['refresh_token']) ?? credential.refreshToken,
        _int(decoded['expires_in']) ?? 3600,
        credential,
        cancellationToken,
      );
    } finally {
      if (_ownsClient) _client.close();
    }
  }

  Future<_DeviceCode> _requestDeviceCode(
    CancellationToken? cancellationToken,
  ) async {
    final response = await _postForm(
      Uri.parse(deviceCodeUrl),
      {'client_id': clientId, 'scope': scope},
      cancellationToken,
      headers: const {'Accept': 'application/json'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _oauthError(response, 'xAI device authorization failed');
    }
    final body = _decodeObject(response.body, 'xAI device authorization');
    final deviceCode = _requiredString(body, 'device_code');
    final userCode = _requiredString(body, 'user_code');
    final verificationUri = _requiredString(body, 'verification_uri');
    final complete =
        _string(body['verification_uri_complete']) ?? verificationUri;
    return _DeviceCode(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUri: verificationUri,
      verificationUriComplete: complete,
      interval: (_int(body['interval']) ?? 5).clamp(1, 60),
      expiresIn: (_int(body['expires_in']) ?? 600).clamp(1, 3600),
    );
  }

  Future<String> _tokenEndpoint(CancellationToken? cancellationToken) async {
    final response = await _get(
      Uri.parse(discoveryUrl),
      cancellationToken,
      headers: const {'Accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw _oauthError(response, 'xAI OIDC discovery failed');
    }
    final body = _decodeObject(response.body, 'xAI OIDC discovery');
    final endpoint = _requiredString(body, 'token_endpoint');
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        uri.scheme != 'https' ||
        !(uri.host == 'x.ai' || uri.host.endsWith('.x.ai'))) {
      throw const OAuthException('Invalid xAI token endpoint');
    }
    return endpoint;
  }

  Future<Map<String, Object?>> _pollToken(
    String endpoint,
    _DeviceCode device,
    CancellationToken? cancellationToken,
  ) async {
    final deadline = _now().add(Duration(seconds: device.expiresIn));
    var interval = device.interval;
    while (_now().isBefore(deadline)) {
      cancellationToken?.throwIfCancelled();
      final response = await _postForm(
        Uri.parse(endpoint),
        {
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          'client_id': clientId,
          'device_code': device.deviceCode,
        },
        cancellationToken,
        headers: const {'Accept': 'application/json'},
      );
      final body = _decodeObject(response.body, 'xAI token response');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return body;
      }
      final error = _string(body['error']);
      if (error == 'authorization_pending') {
        await _sleep(Duration(seconds: interval));
        continue;
      }
      if (error == 'slow_down') {
        interval += 5;
        await _sleep(Duration(seconds: interval));
        continue;
      }
      throw OAuthException(
        'xAI device authorization failed: ${_string(body['error_description']) ?? error ?? 'unknown error'}',
      );
    }
    throw const OAuthException('xAI device flow timed out');
  }

  Future<OAuthCredential> _credentialFromToken(
    Map<String, Object?> token,
    CancellationToken? cancellationToken,
  ) async {
    final accessToken = _string(token['access_token']);
    if (accessToken == null || accessToken.isEmpty) {
      throw const OAuthException('xAI token response missing access token');
    }
    final refreshToken = _string(token['refresh_token']) ?? '';
    return _credentialFromTokenPayload(
      accessToken,
      refreshToken,
      _int(token['expires_in']) ?? 3600,
      null,
      cancellationToken,
    );
  }

  Future<OAuthCredential> _credentialFromTokenPayload(
    String accessToken,
    String refreshToken,
    int expiresIn,
    OAuthCredential? previous,
    CancellationToken? cancellationToken,
  ) async {
    final jwt = _jwtPayload(accessToken);
    var accountId = _string(jwt?['sub']);
    String? email;
    try {
      final response = await _get(
        Uri.parse(userInfoUrl),
        cancellationToken,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final profile = _decodeObject(response.body, 'xAI user info');
        accountId = _string(profile['sub']) ?? accountId;
        email = _string(profile['email'])?.toLowerCase();
      }
    } on OperationCancelledException {
      rethrow;
    } catch (_) {
      // JWT subject remains sufficient account binding when userinfo is down.
    }
    return OAuthCredential(
      provider: OAuthProviderId.xaiOAuth,
      accessToken: accessToken,
      refreshToken: refreshToken.isEmpty
          ? previous?.refreshToken ?? ''
          : refreshToken,
      expiresAt: _now().add(
        Duration(seconds: (expiresIn - 300).clamp(1, 86400)),
      ),
      accountId: accountId,
      email: email ?? previous?.email,
      authorizedAt: previous?.authorizedAt ?? _now(),
    );
  }

  Future<http.Response> _get(
    Uri uri,
    CancellationToken? cancellationToken, {
    Map<String, String>? headers,
  }) async {
    cancellationToken?.throwIfCancelled();
    try {
      return await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const OAuthException('xAI OAuth request timed out');
    } catch (error) {
      throw _transportError(error, uri, 'GET');
    }
  }

  Future<http.Response> _postForm(
    Uri uri,
    Map<String, String> form,
    CancellationToken? cancellationToken, {
    Map<String, String>? headers,
  }) async {
    cancellationToken?.throwIfCancelled();
    try {
      return await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              ...?headers,
            },
            body: form,
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const OAuthException('xAI OAuth request timed out');
    } catch (error) {
      throw _transportError(error, uri, 'POST');
    }
  }
}

class _DeviceCode {
  const _DeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.verificationUriComplete,
    required this.interval,
    required this.expiresIn,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final String verificationUriComplete;
  final int interval;
  final int expiresIn;
}

Map<String, Object?> _decodeObject(String body, String label) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) return decoded.cast<String, Object?>();
  } catch (_) {}
  throw OAuthException('$label returned invalid JSON');
}

String _requiredString(Map<String, Object?> value, String key) {
  final result = _string(value[key]);
  if (result == null || result.isEmpty) {
    throw OAuthException('xAI response missing $key');
  }
  return result;
}

String? _string(Object? value) => value is String ? value.trim() : null;
int? _int(Object? value) => value is int ? value : int.tryParse('$value');

Map<String, Object?>? _jwtPayload(String token) {
  try {
    final parts = token.split('.');
    if (parts.length < 2) return null;
    final decoded = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    final payload = jsonDecode(decoded);
    return payload is Map ? payload.cast<String, Object?>() : null;
  } catch (_) {
    return null;
  }
}

OAuthException _oauthError(http.Response response, String prefix) =>
    OAuthException(
      '$prefix: ${response.statusCode}: ${_safeOAuthError(response.body)}',
    );

OAuthException _transportError(Object error, Uri uri, String method) =>
    OAuthException('xAI OAuth $method ${uri.host} failed: ${error.toString()}');

String _safeOAuthError(String body) {
  try {
    final value = jsonDecode(body);
    if (value is Map) {
      return (value['error_description'] ??
              value['detail'] ??
              value['error'] ??
              value['message'] ??
              body)
          .toString();
    }
  } catch (_) {}
  return body.trim().isEmpty ? 'empty response' : body.trim();
}
