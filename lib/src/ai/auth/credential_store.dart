import '../oauth/oauth_credential.dart';
import '../registry/provider_registry.dart';
import '../../models.dart';

sealed class ProviderCredential {
  const ProviderCredential();
}

class ApiKeyProviderCredential extends ProviderCredential {
  const ApiKeyProviderCredential(this.apiKey);
  final String apiKey;
}

class OAuthProviderCredential extends ProviderCredential {
  const OAuthProviderCredential(this.credential);
  final OAuthCredential credential;
}

abstract class CredentialStore {
  Future<void> saveApiKey(String providerId, String apiKey);
  Future<String?> readApiKey(String providerId);
  Future<void> saveOAuthCredential(
    String providerId,
    OAuthCredential credential,
  );
  Future<OAuthCredential?> readOAuthCredential(String providerId);
  Future<void> deleteProviderCredentials(String providerId);
  Future<ProviderCredential?> resolveProviderCredential(
    ProviderConfig provider,
  );
}

ProviderAuthType authTypeForProvider(ProviderConfig provider) {
  for (final value in ProviderAuthType.values) {
    if (value.name == provider.authType) return value;
  }
  return ProviderAuthType.apiKey;
}
