import '../common/quantization_level.dart';

/// Model information metadata
/// Matches iOS ModelInfoMetadata from Core/Models/Model/ModelInfoMetadata.swift
class ModelInfoMetadata {
  final String? author;
  final String? license;
  final List<String> tags;
  final String? description;
  final String? trainingDataset;
  final String? baseModel;
  final QuantizationLevel? quantizationLevel;
  final String? version;
  final String? minOSVersion;
  final int? minMemory;

  const ModelInfoMetadata({
    this.author,
    this.license,
    this.tags = const [],
    this.description,
    this.trainingDataset,
    this.baseModel,
    this.quantizationLevel,
    this.version,
    this.minOSVersion,
    this.minMemory,
  });

  /// JSON serialization
  Map<String, dynamic> toJson() => {
        if (author != null) 'author': author,
        if (license != null) 'license': license,
        if (tags.isNotEmpty) 'tags': tags,
        if (description != null) 'description': description,
        if (trainingDataset != null) 'trainingDataset': trainingDataset,
        if (baseModel != null) 'baseModel': baseModel,
        if (quantizationLevel != null)
          'quantizationLevel': quantizationLevel!.rawValue,
        if (version != null) 'version': version,
        if (minOSVersion != null) 'minOSVersion': minOSVersion,
        if (minMemory != null) 'minMemory': minMemory,
      };

  factory ModelInfoMetadata.fromJson(Map<String, dynamic> json) {
    return ModelInfoMetadata(
      author: json['author'] as String?,
      license: json['license'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
      description: json['description'] as String?,
      trainingDataset: json['trainingDataset'] as String?,
      baseModel: json['baseModel'] as String?,
      quantizationLevel: json['quantizationLevel'] != null
          ? QuantizationLevel.fromRawValue(json['quantizationLevel'] as String)
          : null,
      version: json['version'] as String?,
      minOSVersion: json['minOSVersion'] as String?,
      minMemory: json['minMemory'] as int?,
    );
  }

  /// Copy with modifications
  ModelInfoMetadata copyWith({
    String? author,
    String? license,
    List<String>? tags,
    String? description,
    String? trainingDataset,
    String? baseModel,
    QuantizationLevel? quantizationLevel,
    String? version,
    String? minOSVersion,
    int? minMemory,
  }) {
    return ModelInfoMetadata(
      author: author ?? this.author,
      license: license ?? this.license,
      tags: tags ?? this.tags,
      description: description ?? this.description,
      trainingDataset: trainingDataset ?? this.trainingDataset,
      baseModel: baseModel ?? this.baseModel,
      quantizationLevel: quantizationLevel ?? this.quantizationLevel,
      version: version ?? this.version,
      minOSVersion: minOSVersion ?? this.minOSVersion,
      minMemory: minMemory ?? this.minMemory,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModelInfoMetadata &&
          runtimeType == other.runtimeType &&
          author == other.author &&
          license == other.license &&
          description == other.description &&
          version == other.version;

  @override
  int get hashCode =>
      author.hashCode ^
      license.hashCode ^
      description.hashCode ^
      version.hashCode;
}
