/// Central application identity and dynamic branding source.
/// All user-facing surfaces derive names, paths, schemes, and identifiers from here.
class AppIdentity {
  const AppIdentity({
    this.appName = 'Syntac',
    this.appDisplayName = 'Syntac',
    this.appSlug = 'syntac',
    this.appScheme = 'syntac',
    this.storageFolderName = '.syntac',
    this.tagline = 'Autonomous mobile coding environment',
    this.developerName = 'DraxonV1',
    this.repositoryUrl = 'https://github.com/DraxonV1/Syntac',
    this.version = '0.1.1-beta.2',
    this.versionCode = 12,
    this.updateChannel = 'beta',
  });

  final String appName;
  final String appDisplayName;
  final String appSlug;
  final String appScheme;
  final String storageFolderName;
  final String tagline;
  final String developerName;
  final String repositoryUrl;
  final String version;
  final int versionCode;
  final String updateChannel;

  /// Global singleton instance, modifiable for dynamic branding / custom configurations.
  static AppIdentity instance = const AppIdentity();

  /// Formatted welcome title: "Welcome to {appName}"
  String get welcomeTitle => 'Welcome to $appName';

  /// Runtime label: "ARCH Linux Runtime"
  String get runtimeLabel => 'ARCH Linux Runtime';

  /// Agent label: "{appName} Agent"
  String get agentLabel => '$appName Agent';

  /// Storage folder name, keeping explicit identity override support.
  String get storageFolder => storageFolderName;

  /// OAuth deep-link redirect URI
  String get oauthRedirectUri => '$appScheme://auth/callback';

  /// Android shared storage root path for projects / data
  String get defaultSharedStoragePath => '/storage/emulated/0/$appDisplayName';

  /// Compatibility alias for older project-path code.
  String get legacySharedStoragePath => defaultSharedStoragePath;

  AppIdentity copyWith({
    String? appName,
    String? appDisplayName,
    String? appSlug,
    String? appScheme,
    String? storageFolderName,
    String? tagline,
    String? developerName,
    String? repositoryUrl,
    String? version,
    int? versionCode,
    String? updateChannel,
  }) {
    return AppIdentity(
      appName: appName ?? this.appName,
      appDisplayName: appDisplayName ?? this.appDisplayName,
      appSlug: appSlug ?? this.appSlug,
      appScheme: appScheme ?? this.appScheme,
      storageFolderName: storageFolderName ?? this.storageFolderName,
      tagline: tagline ?? this.tagline,
      developerName: developerName ?? this.developerName,
      repositoryUrl: repositoryUrl ?? this.repositoryUrl,
      version: version ?? this.version,
      versionCode: versionCode ?? this.versionCode,
      updateChannel: updateChannel ?? this.updateChannel,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppIdentity &&
          runtimeType == other.runtimeType &&
          appName == other.appName &&
          appDisplayName == other.appDisplayName &&
          appSlug == other.appSlug &&
          appScheme == other.appScheme &&
          storageFolderName == other.storageFolderName &&
          tagline == other.tagline &&
          developerName == other.developerName &&
          repositoryUrl == other.repositoryUrl &&
          version == other.version &&
          versionCode == other.versionCode &&
          updateChannel == other.updateChannel;

  @override
  int get hashCode => Object.hash(
    appName,
    appDisplayName,
    appSlug,
    appScheme,
    storageFolderName,
    tagline,
    developerName,
    repositoryUrl,
    version,
    versionCode,
    updateChannel,
  );
}
