import 'dart:convert';

enum OAuthProviderId { googleAntigravity }

class OAuthException implements Exception {
  const OAuthException(this.message);
  final String message;

  @override
  String toString() => 'OAuthException: $message';
}

class OAuthCredential {
  const OAuthCredential({
    required this.provider,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.projectId,
    this.email,
    this.accountId,
    this.apiEndpoint,
    this.authorizedAt,
  });

  factory OAuthCredential.fromJson(Map<String, Object?> json) =>
      OAuthCredential(
        provider: _providerFromJson(json['provider']),
        accessToken: json['accessToken']! as String,
        refreshToken: json['refreshToken']! as String,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          json['expiresAt']! as int,
        ),
        projectId: json['projectId'] as String?,
        email: json['email'] as String?,
        accountId: json['accountId'] as String?,
        apiEndpoint: json['apiEndpoint'] as String?,
        authorizedAt: json['authorizedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['authorizedAt']! as int),
      );

  final OAuthProviderId provider;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String? projectId;
  final String? email;
  final String? accountId;
  final String? apiEndpoint;
  final DateTime? authorizedAt;

  bool expiresWithin(Duration skew, {DateTime? now}) =>
      (now ?? DateTime.now()).add(skew).isAfter(expiresAt);

  OAuthCredential copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
    String? projectId,
    String? email,
    String? accountId,
    String? apiEndpoint,
    DateTime? authorizedAt,
  }) => OAuthCredential(
    provider: provider,
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
    expiresAt: expiresAt ?? this.expiresAt,
    projectId: projectId ?? this.projectId,
    email: email ?? this.email,
    accountId: accountId ?? this.accountId,
    apiEndpoint: apiEndpoint ?? this.apiEndpoint,
    authorizedAt: authorizedAt ?? this.authorizedAt,
  );

  Map<String, Object?> toJson() => {
    'provider': provider.name,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.millisecondsSinceEpoch,
    if (projectId != null) 'projectId': projectId,
    if (email != null) 'email': email,
    if (accountId != null) 'accountId': accountId,
    if (apiEndpoint != null) 'apiEndpoint': apiEndpoint,
    if (authorizedAt != null)
      'authorizedAt': authorizedAt!.millisecondsSinceEpoch,
  };

  String toStructuredApiKey() => jsonEncode({
    'token': accessToken,
    'projectId': projectId,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.millisecondsSinceEpoch,
    if (email != null) 'email': email,
    if (accountId != null) 'accountId': accountId,
    if (apiEndpoint != null) 'apiEndpoint': apiEndpoint,
  });
}

OAuthProviderId _providerFromJson(Object? raw) =>
    OAuthProviderId.googleAntigravity;
