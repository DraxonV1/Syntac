import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_identity.dart';

enum UpdateChannel {
  stable,
  beta,
  nightly;

  static UpdateChannel fromName(String value) {
    for (final channel in values) {
      if (channel.name == value) return channel;
    }
    return UpdateChannel.beta;
  }
}

class UpdateManifest {
  const UpdateManifest({
    required this.version,
    required this.versionCode,
    required this.apkUrl,
    required this.sha256,
    required this.size,
    required this.mandatory,
    required this.minSupportedVersionCode,
    required this.notes,
    required this.channel,
  });

  final String version;
  final int versionCode;
  final String apkUrl;
  final String sha256;
  final int size;
  final bool mandatory;
  final int minSupportedVersionCode;
  final List<String> notes;
  final UpdateChannel channel;

  bool isNewerThan(int currentVersionCode) => versionCode > currentVersionCode;

  bool requiresUpgradeFrom(int currentVersionCode) =>
      mandatory || currentVersionCode < minSupportedVersionCode;

  String get downloadUrl => apkUrl;

  factory UpdateManifest.fromJson(
    Map<String, Object?> json, {
    required UpdateChannel channel,
  }) {
    return UpdateManifest(
      version: (json['version'] ?? '').toString(),
      versionCode: (json['versionCode'] as num?)?.toInt() ?? 0,
      apkUrl: (json['apkUrl'] ?? '').toString(),
      sha256: (json['sha256'] ?? '').toString(),
      size: (json['size'] as num?)?.toInt() ?? 0,
      mandatory: json['mandatory'] == true,
      minSupportedVersionCode:
          (json['minSupportedVersionCode'] as num?)?.toInt() ?? 0,
      notes: (json['notes'] as List? ?? const <Object?>[])
          .map((note) => note.toString())
          .where((note) => note.trim().isNotEmpty)
          .toList(growable: false),
      channel: channel,
    );
  }
}

class UpdateService {
  UpdateService({
    http.Client? client,
    this.timeout = const Duration(seconds: 5),
    List<Uri>? endpoints,
  }) : _client = client ?? http.Client(),
       _endpoints = endpoints;

  final http.Client _client;
  final Duration timeout;
  final List<Uri>? _endpoints;

  static List<Uri> defaultEndpoints(UpdateChannel channel) => <Uri>[
    Uri.parse('https://syntac.com/download/${channel.name}.json'),
    Uri.parse(
      'https://raw.githubusercontent.com/DraxonV1/Syntac/master/update/${channel.name}.json',
    ),
  ];

  static final _sha256 = RegExp(r'^[a-fA-F0-9]{64}$');
  static final _version = RegExp(r'^\d+\.\d+\.\d+(?:-(?:beta|nightly)\.\d+)?$');

  static bool _validManifest(UpdateManifest manifest) {
    final uri = Uri.tryParse(manifest.apkUrl);
    if (!_version.hasMatch(manifest.version) ||
        manifest.versionCode <= 0 ||
        uri?.scheme != 'https' ||
        uri!.host.isEmpty ||
        !_sha256.hasMatch(manifest.sha256) ||
        manifest.size <= 0 ||
        manifest.minSupportedVersionCode < 0) {
      return false;
    }
    final qualifier = manifest.version
        .split('-')
        .skip(1)
        .join('-')
        .toLowerCase();
    return switch (manifest.channel) {
      UpdateChannel.stable => qualifier.isEmpty,
      UpdateChannel.beta => qualifier.isEmpty || qualifier.startsWith('beta.'),
      UpdateChannel.nightly => qualifier.startsWith('nightly.'),
    };
  }

  Future<UpdateManifest?> check({
    required UpdateChannel channel,
    required int currentVersionCode,
  }) async {
    for (final endpoint in _endpoints ?? defaultEndpoints(channel)) {
      try {
        final response = await _client.get(endpoint).timeout(timeout);
        if (response.statusCode < 200 || response.statusCode >= 300) continue;
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, Object?>) continue;
        final manifest = UpdateManifest.fromJson(decoded, channel: channel);
        if (!_validManifest(manifest)) continue;
        if (manifest.isNewerThan(currentVersionCode) ||
            manifest.requiresUpgradeFrom(currentVersionCode)) {
          return manifest;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}

UpdateChannel get defaultUpdateChannel =>
    UpdateChannel.fromName(AppIdentity.instance.updateChannel);
