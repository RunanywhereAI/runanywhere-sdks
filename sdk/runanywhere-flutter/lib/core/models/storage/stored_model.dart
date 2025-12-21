import 'package:runanywhere/core/models/framework/llm_framework.dart';
import 'package:runanywhere/core/models/framework/model_format.dart';
import 'package:runanywhere/core/models/model/model_info_metadata.dart';

/// Stored model information.
/// Matches iOS StoredModel from Data/Models/Storage/StoredModel.swift
class StoredModel {
  /// Model ID used for operations like deletion
  final String id;

  /// Model display name
  final String name;

  /// Path to the model file/directory
  final String path;

  /// Size in bytes
  final int size;

  /// Model format
  final ModelFormat format;

  /// Framework used (optional)
  final LLMFramework? framework;

  /// Date the model was created/downloaded
  final DateTime createdDate;

  /// Date the model was last used (optional)
  final DateTime? lastUsed;

  /// Model metadata (optional)
  final ModelInfoMetadata? metadata;

  /// Context length (optional)
  final int? contextLength;

  /// Checksum for verification (optional)
  final String? checksum;

  const StoredModel({
    required this.id,
    required this.name,
    required this.path,
    required this.size,
    required this.format,
    this.framework,
    required this.createdDate,
    this.lastUsed,
    this.metadata,
    this.contextLength,
    this.checksum,
  });

  /// Create from JSON map
  factory StoredModel.fromJson(Map<String, dynamic> json) {
    return StoredModel(
      id: json['id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
      size: (json['size'] as num).toInt(),
      format: ModelFormat.fromRawValue(json['format'] as String? ?? 'unknown'),
      framework: json['framework'] != null
          ? LLMFramework.fromRawValue(json['framework'] as String)
          : null,
      createdDate: DateTime.parse(json['createdDate'] as String),
      lastUsed: json['lastUsed'] != null
          ? DateTime.parse(json['lastUsed'] as String)
          : null,
      metadata: json['metadata'] != null
          ? ModelInfoMetadata.fromJson(json['metadata'] as Map<String, dynamic>)
          : null,
      contextLength: (json['contextLength'] as num?)?.toInt(),
      checksum: json['checksum'] as String?,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'size': size,
      'format': format.rawValue,
      if (framework != null) 'framework': framework!.rawValue,
      'createdDate': createdDate.toIso8601String(),
      if (lastUsed != null) 'lastUsed': lastUsed!.toIso8601String(),
      if (metadata != null) 'metadata': metadata!.toJson(),
      if (contextLength != null) 'contextLength': contextLength,
      if (checksum != null) 'checksum': checksum,
    };
  }
}
