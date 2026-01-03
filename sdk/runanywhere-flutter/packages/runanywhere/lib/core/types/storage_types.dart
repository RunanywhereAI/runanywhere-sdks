/// Storage Types
///
/// Consolidated storage-related types for public API.
/// Matches Swift StorageTypes.swift from Public/Extensions/Storage/
/// Includes: storage info, configuration, availability, and model storage metrics.
library storage_types;

import 'model_types.dart';

// MARK: - Device Storage

/// Device storage information
class DeviceStorageInfo {
  /// Total device storage space in bytes
  final int totalSpace;

  /// Free space available in bytes
  final int freeSpace;

  /// Used space in bytes
  final int usedSpace;

  const DeviceStorageInfo({
    required this.totalSpace,
    required this.freeSpace,
    required this.usedSpace,
  });

  /// Percentage of storage used (0-100)
  double get usagePercentage {
    if (totalSpace == 0) return 0;
    return (usedSpace / totalSpace) * 100;
  }

  Map<String, dynamic> toJson() => {
        'totalSpace': totalSpace,
        'freeSpace': freeSpace,
        'usedSpace': usedSpace,
      };

  factory DeviceStorageInfo.fromJson(Map<String, dynamic> json) {
    return DeviceStorageInfo(
      totalSpace: (json['totalSpace'] as num?)?.toInt() ?? 0,
      freeSpace: (json['freeSpace'] as num?)?.toInt() ?? 0,
      usedSpace: (json['usedSpace'] as num?)?.toInt() ?? 0,
    );
  }
}

// MARK: - App Storage

/// App storage breakdown by directory type
class AppStorageInfo {
  /// Documents directory size in bytes
  final int documentsSize;

  /// Cache directory size in bytes
  final int cacheSize;

  /// Application Support directory size in bytes
  final int appSupportSize;

  /// Total app storage in bytes
  final int totalSize;

  const AppStorageInfo({
    required this.documentsSize,
    required this.cacheSize,
    required this.appSupportSize,
    required this.totalSize,
  });

  Map<String, dynamic> toJson() => {
        'documentsSize': documentsSize,
        'cacheSize': cacheSize,
        'appSupportSize': appSupportSize,
        'totalSize': totalSize,
      };

  factory AppStorageInfo.fromJson(Map<String, dynamic> json) {
    return AppStorageInfo(
      documentsSize: (json['documentsSize'] as num?)?.toInt() ?? 0,
      cacheSize: (json['cacheSize'] as num?)?.toInt() ?? 0,
      appSupportSize: (json['appSupportSize'] as num?)?.toInt() ?? 0,
      totalSize: (json['totalSize'] as num?)?.toInt() ?? 0,
    );
  }
}

// MARK: - Model Storage Metrics

/// Storage metrics for a single model
/// All model metadata (id, name, framework, artifactType, etc.) is in ModelInfo
/// This class adds the on-disk storage size
class ModelStorageMetrics {
  /// The model info (contains id, framework, localPath, artifactType, etc.)
  final ModelInfo model;

  /// Actual size on disk in bytes (may differ from downloadSize after extraction)
  final int sizeOnDisk;

  const ModelStorageMetrics({
    required this.model,
    required this.sizeOnDisk,
  });
}

// MARK: - Stored Model (Backward Compatible)

/// Backward-compatible stored model view
/// Provides a simple view of a stored model with computed properties
class StoredModel {
  /// Underlying model info
  final ModelInfo modelInfo;

  /// Size on disk in bytes
  final int size;

  const StoredModel({
    required this.modelInfo,
    required this.size,
  });

  /// Model ID
  String get id => modelInfo.id;

  /// Model name
  String get name => modelInfo.name;

  /// Model format
  ModelFormat get format => modelInfo.format;

  /// Inference framework
  InferenceFramework get framework => modelInfo.framework;

  /// Model description
  String? get description => modelInfo.description;

  /// Path to the model on disk
  Uri get path => modelInfo.localPath ?? Uri.parse('file:///unknown');

  /// Created date (use current date as fallback)
  DateTime get createdDate => modelInfo.createdAt;

  /// Create from ModelStorageMetrics
  factory StoredModel.fromMetrics(ModelStorageMetrics metrics) {
    return StoredModel(
      modelInfo: metrics.model,
      size: metrics.sizeOnDisk,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path.toString(),
        'size': size,
        'format': format.rawValue,
        'framework': framework.rawValue,
        'createdDate': createdDate.toIso8601String(),
        if (description != null) 'description': description,
      };

  factory StoredModel.fromJson(Map<String, dynamic> json) {
    return StoredModel(
      modelInfo: ModelInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        category: ModelCategory.language,
        format: ModelFormat.fromRawValue(json['format'] as String? ?? 'unknown'),
        framework: InferenceFramework.fromRawValue(
            json['framework'] as String? ?? 'unknown'),
        localPath: json['path'] != null
            ? Uri.parse(json['path'] as String)
            : null,
        description: json['description'] as String?,
        createdAt: json['createdDate'] != null
            ? DateTime.parse(json['createdDate'] as String)
            : null,
      ),
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }
}

// MARK: - Storage Info (Aggregate)

/// Complete storage information including device, app, and model storage
class StorageInfo {
  /// App storage usage
  final AppStorageInfo appStorage;

  /// Device storage capacity
  final DeviceStorageInfo deviceStorage;

  /// Storage metrics for each downloaded model
  final List<ModelStorageMetrics> models;

  const StorageInfo({
    required this.appStorage,
    required this.deviceStorage,
    required this.models,
  });

  /// Total size of all models
  int get totalModelsSize {
    return models.fold(0, (sum, m) => sum + m.sizeOnDisk);
  }

  /// Number of stored models
  int get modelCount => models.length;

  /// Stored models array (backward compatible)
  List<StoredModel> get storedModels {
    return models.map((m) => StoredModel.fromMetrics(m)).toList();
  }

  /// Empty storage info
  static final StorageInfo empty = StorageInfo(
    appStorage: const AppStorageInfo(
      documentsSize: 0,
      cacheSize: 0,
      appSupportSize: 0,
      totalSize: 0,
    ),
    deviceStorage: const DeviceStorageInfo(
      totalSpace: 0,
      freeSpace: 0,
      usedSpace: 0,
    ),
    models: const [],
  );

  Map<String, dynamic> toJson() => {
        'appStorage': appStorage.toJson(),
        'deviceStorage': deviceStorage.toJson(),
        'models': storedModels.map((m) => m.toJson()).toList(),
      };

  factory StorageInfo.fromJson(Map<String, dynamic> json) {
    final storedModels = (json['models'] as List<dynamic>?)
            ?.map((m) => StoredModel.fromJson(m as Map<String, dynamic>))
            .toList() ??
        [];

    return StorageInfo(
      appStorage:
          AppStorageInfo.fromJson(json['appStorage'] as Map<String, dynamic>),
      deviceStorage: DeviceStorageInfo.fromJson(
          json['deviceStorage'] as Map<String, dynamic>),
      models: storedModels
          .map((s) => ModelStorageMetrics(model: s.modelInfo, sizeOnDisk: s.size))
          .toList(),
    );
  }
}

// MARK: - Storage Availability

/// Storage availability check result
class StorageAvailability {
  /// Whether storage is available for the requested operation
  final bool isAvailable;

  /// Required space in bytes
  final int requiredSpace;

  /// Available space in bytes
  final int availableSpace;

  /// Whether there's a warning (e.g., low space)
  final bool hasWarning;

  /// Recommendation message if any
  final String? recommendation;

  const StorageAvailability({
    required this.isAvailable,
    required this.requiredSpace,
    required this.availableSpace,
    required this.hasWarning,
    this.recommendation,
  });
}
