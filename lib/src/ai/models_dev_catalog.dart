import 'dart:convert';

import 'package:flutter/services.dart';

class ModelMetadata {
  const ModelMetadata({
    required this.id,
    required this.name,
    required this.providerId,
    this.contextWindow,
    this.inputLimit,
    this.outputLimit,
    this.reasoning = false,
    this.toolCall = false,
    this.temperature = false,
    this.modalities = const <String>[],
  });

  final String id;
  final String name;
  final String providerId;
  final int? contextWindow;
  final int? inputLimit;
  final int? outputLimit;
  final bool reasoning;
  final bool toolCall;
  final bool temperature;
  final List<String> modalities;

  bool get supportsImages => modalities.contains('image');

  factory ModelMetadata.fromJson({
    required String providerId,
    required String id,
    required Map<String, Object?> json,
  }) {
    final limit = json['limit'];
    final modalities = json['modalities'];
    final inputModalities = modalities is Map
        ? modalities['input']
        : const <Object?>[];
    return ModelMetadata(
      id: id,
      name: json['name']?.toString() ?? id,
      providerId: providerId,
      contextWindow: _positiveInt(limit is Map ? limit['context'] : null),
      inputLimit: _positiveInt(limit is Map ? limit['input'] : null),
      outputLimit: _positiveInt(limit is Map ? limit['output'] : null),
      reasoning: json['reasoning'] == true,
      toolCall: json['tool_call'] == true,
      temperature: json['temperature'] == true,
      modalities: inputModalities is List
          ? inputModalities.map((value) => value.toString()).toList()
          : const <String>[],
    );
  }

  static int? _positiveInt(Object? value) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return parsed != null && parsed > 0 ? parsed : null;
  }
}

class ModelsDevCatalog {
  const ModelsDevCatalog._(this._models);

  const ModelsDevCatalog.empty() : _models = const <String, ModelMetadata>{};

  final Map<String, ModelMetadata> _models;

  static const assetPath = 'assets/models/models.dev.api.json';

  static Future<ModelsDevCatalog> load() async {
    final source = await rootBundle.loadString(assetPath);
    return ModelsDevCatalog.fromJson(source);
  }

  factory ModelsDevCatalog.fromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) return const ModelsDevCatalog.empty();
    final models = <String, ModelMetadata>{};
    for (final providerEntry in decoded.entries) {
      final providerId = providerEntry.key.toString();
      final provider = providerEntry.value;
      if (provider is! Map) continue;
      final rawModels = provider['models'];
      if (rawModels is! Map) continue;
      for (final modelEntry in rawModels.entries) {
        final id = modelEntry.key.toString();
        final rawModel = modelEntry.value;
        if (rawModel is! Map) continue;
        final metadata = ModelMetadata.fromJson(
          providerId: providerId,
          id: id,
          json: rawModel.cast<String, Object?>(),
        );
        models[_key(providerId, id)] = metadata;
        models.putIfAbsent(_key('', id), () => metadata);
      }
    }
    return ModelsDevCatalog._(models);
  }

  List<String> modelIdsForProvider(String providerId) => _models.values
      .where((model) => model.providerId == providerId)
      .map((model) => model.id)
      .toSet()
      .toList(growable: false);
  ModelMetadata? lookup({
    required String providerKey,
    required String modelId,
  }) {
    return _models[_key(providerKey, modelId)] ??
        _models[_key('', modelId)] ??
        _models.values.where((model) => model.id == modelId).firstOrNull;
  }

  int? contextWindowFor({
    required String providerKey,
    required String modelId,
  }) => lookup(providerKey: providerKey, modelId: modelId)?.contextWindow;

  int? maxOutputTokensFor({
    required String providerKey,
    required String modelId,
  }) => lookup(providerKey: providerKey, modelId: modelId)?.outputLimit;

  static String _key(String providerId, String modelId) =>
      '${providerId.toLowerCase()}::$modelId';
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
