import 'dart:io';

import '../common/configuration_source.dart';
import '../common/thinking_tag_pattern.dart';
import '../framework/llm_framework.dart';
import '../framework/model_format.dart';
import 'model_category.dart';
import 'model_info_metadata.dart';

/// Information about a model
/// Matches iOS ModelInfo from Core/Models/Model/ModelInfo.swift
class ModelInfo {
  // Essential identifiers
  final String id;
  final String name;
  final ModelCategory category;

  // Format and location
  final ModelFormat format;
  final Uri? downloadURL;
  Uri? localPath;

  // Size information (in bytes)
  final int? downloadSize;
  final int? memoryRequired;

  // Framework compatibility
  final List<LLMFramework> compatibleFrameworks;
  final LLMFramework? preferredFramework;

  // Model-specific capabilities
  final int? contextLength;
  final bool supportsThinking;
  final ThinkingTagPattern? thinkingPattern;

  // Optional metadata
  final ModelInfoMetadata? metadata;

  // Tracking fields
  final ConfigurationSource source;
  final DateTime createdAt;
  DateTime updatedAt;
  bool syncPending;

  // Usage tracking
  DateTime? lastUsed;
  int usageCount;

  // Non-Codable runtime properties
  Map<String, String> additionalProperties;

  ModelInfo({
    required this.id,
    required this.name,
    required this.category,
    required this.format,
    this.downloadURL,
    this.localPath,
    this.downloadSize,
    this.memoryRequired,
    List<LLMFramework>? compatibleFrameworks,
    LLMFramework? preferredFramework,
    int? contextLength,
    bool supportsThinking = false,
    ThinkingTagPattern? thinkingPattern,
    this.metadata,
    ConfigurationSource? source,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncPending = false,
    this.lastUsed,
    this.usageCount = 0,
    Map<String, String>? additionalProperties,
  })  : compatibleFrameworks = compatibleFrameworks ?? [],
        preferredFramework =
            preferredFramework ?? compatibleFrameworks?.firstOrNull,
        contextLength = category.requiresContextLength
            ? (contextLength ?? 2048)
            : contextLength,
        supportsThinking = category.supportsThinking ? supportsThinking : false,
        thinkingPattern = (category.supportsThinking && supportsThinking)
            ? (thinkingPattern ?? ThinkingTagPattern.defaultPattern)
            : null,
        source = source ?? ConfigurationSource.remote,
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        additionalProperties = additionalProperties ?? {};

  /// Whether this model is downloaded and available locally
  bool get isDownloaded {
    final path = localPath;
    if (path == null) return false;

    // Built-in models (e.g., Apple Foundation Models) are always available
    if (path.scheme == 'builtin') {
      return true;
    }

    // Check if the file or directory actually exists on disk
    final localFile = File(path.toFilePath());
    final localDir = Directory(path.toFilePath());

    if (localFile.existsSync()) {
      return true;
    }

    if (localDir.existsSync()) {
      // For directories, verify they contain files (not empty)
      final contents = localDir.listSync();
      return contents.isNotEmpty;
    }

    return false;
  }

  /// Whether this model is available for use (downloaded and locally accessible)
  bool get isAvailable => isDownloaded;

  /// JSON serialization
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category.rawValue,
        'format': format.rawValue,
        if (downloadURL != null) 'downloadURL': downloadURL.toString(),
        if (localPath != null) 'localPath': localPath.toString(),
        if (downloadSize != null) 'downloadSize': downloadSize,
        if (memoryRequired != null) 'memoryRequired': memoryRequired,
        'compatibleFrameworks':
            compatibleFrameworks.map((f) => f.rawValue).toList(),
        if (preferredFramework != null)
          'preferredFramework': preferredFramework!.rawValue,
        if (contextLength != null) 'contextLength': contextLength,
        'supportsThinking': supportsThinking,
        if (thinkingPattern != null)
          'thinkingPattern': thinkingPattern!.toJson(),
        if (metadata != null) 'metadata': metadata!.toJson(),
        'source': source.rawValue,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'syncPending': syncPending,
        if (lastUsed != null) 'lastUsed': lastUsed!.toIso8601String(),
        'usageCount': usageCount,
      };

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      category: ModelCategory.fromRawValue(json['category'] as String) ??
          ModelCategory.language,
      format: ModelFormat.fromRawValue(json['format'] as String),
      downloadURL: json['downloadURL'] != null
          ? Uri.parse(json['downloadURL'] as String)
          : null,
      localPath: json['localPath'] != null
          ? Uri.parse(json['localPath'] as String)
          : null,
      downloadSize: json['downloadSize'] as int?,
      memoryRequired: json['memoryRequired'] as int?,
      compatibleFrameworks: (json['compatibleFrameworks'] as List<dynamic>?)
              ?.map((f) => LLMFramework.fromRawValue(f as String))
              .whereType<LLMFramework>()
              .toList() ??
          [],
      preferredFramework: json['preferredFramework'] != null
          ? LLMFramework.fromRawValue(json['preferredFramework'] as String)
          : null,
      contextLength: json['contextLength'] as int?,
      supportsThinking: json['supportsThinking'] as bool? ?? false,
      thinkingPattern: json['thinkingPattern'] != null
          ? ThinkingTagPattern.fromJson(
              json['thinkingPattern'] as Map<String, dynamic>)
          : null,
      metadata: json['metadata'] != null
          ? ModelInfoMetadata.fromJson(json['metadata'] as Map<String, dynamic>)
          : null,
      source: ConfigurationSource.fromRawValue(
          json['source'] as String? ?? 'remote'),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      syncPending: json['syncPending'] as bool? ?? false,
      lastUsed: json['lastUsed'] != null
          ? DateTime.parse(json['lastUsed'] as String)
          : null,
      usageCount: json['usageCount'] as int? ?? 0,
    );
  }

  /// Copy with modifications
  ModelInfo copyWith({
    String? id,
    String? name,
    ModelCategory? category,
    ModelFormat? format,
    Uri? downloadURL,
    Uri? localPath,
    int? downloadSize,
    int? memoryRequired,
    List<LLMFramework>? compatibleFrameworks,
    LLMFramework? preferredFramework,
    int? contextLength,
    bool? supportsThinking,
    ThinkingTagPattern? thinkingPattern,
    ModelInfoMetadata? metadata,
    ConfigurationSource? source,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? syncPending,
    DateTime? lastUsed,
    int? usageCount,
    Map<String, String>? additionalProperties,
  }) {
    return ModelInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      format: format ?? this.format,
      downloadURL: downloadURL ?? this.downloadURL,
      localPath: localPath ?? this.localPath,
      downloadSize: downloadSize ?? this.downloadSize,
      memoryRequired: memoryRequired ?? this.memoryRequired,
      compatibleFrameworks: compatibleFrameworks ?? this.compatibleFrameworks,
      preferredFramework: preferredFramework ?? this.preferredFramework,
      contextLength: contextLength ?? this.contextLength,
      supportsThinking: supportsThinking ?? this.supportsThinking,
      thinkingPattern: thinkingPattern ?? this.thinkingPattern,
      metadata: metadata ?? this.metadata,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncPending: syncPending ?? this.syncPending,
      lastUsed: lastUsed ?? this.lastUsed,
      usageCount: usageCount ?? this.usageCount,
      additionalProperties: additionalProperties ?? this.additionalProperties,
    );
  }

  /// Mark model as used
  void markAsUsed() {
    lastUsed = DateTime.now();
    usageCount++;
    updatedAt = DateTime.now();
    syncPending = true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModelInfo && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ModelInfo(id: $id, name: $name, category: $category)';
}
