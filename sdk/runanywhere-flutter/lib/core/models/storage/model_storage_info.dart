import '../framework/llm_framework.dart';
import 'stored_model.dart';

/// Model storage information.
/// Matches iOS ModelStorageInfo from Data/Models/Storage/ModelStorageInfo.swift
class ModelStorageInfo {
  /// Total size of all stored models in bytes
  final int totalSize;

  /// Number of stored models
  final int modelCount;

  /// Models grouped by framework
  final Map<LLMFramework, List<StoredModel>> modelsByFramework;

  /// Largest stored model (optional)
  final StoredModel? largestModel;

  const ModelStorageInfo({
    required this.totalSize,
    required this.modelCount,
    this.modelsByFramework = const {},
    this.largestModel,
  });

  /// Create from JSON map
  factory ModelStorageInfo.fromJson(Map<String, dynamic> json) {
    final modelsByFramework = <LLMFramework, List<StoredModel>>{};
    final rawModelsByFramework =
        json['modelsByFramework'] as Map<String, dynamic>?;
    if (rawModelsByFramework != null) {
      for (final entry in rawModelsByFramework.entries) {
        final framework = LLMFramework.fromRawValue(entry.key);
        if (framework != null) {
          final models = (entry.value as List<dynamic>)
              .map((e) => StoredModel.fromJson(e as Map<String, dynamic>))
              .toList();
          modelsByFramework[framework] = models;
        }
      }
    }

    return ModelStorageInfo(
      totalSize: (json['totalSize'] as num?)?.toInt() ?? 0,
      modelCount: (json['modelCount'] as num?)?.toInt() ?? 0,
      modelsByFramework: modelsByFramework,
      largestModel: json['largestModel'] != null
          ? StoredModel.fromJson(json['largestModel'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'totalSize': totalSize,
      'modelCount': modelCount,
      'modelsByFramework': modelsByFramework.map(
        (k, v) => MapEntry(k.rawValue, v.map((m) => m.toJson()).toList()),
      ),
      if (largestModel != null) 'largestModel': largestModel!.toJson(),
    };
  }
}
