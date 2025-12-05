import 'app_storage_info.dart';
import 'device_storage_info.dart';
import 'model_storage_info.dart';
import 'stored_model.dart';

/// Complete storage information.
/// Matches iOS StorageInfo from Data/Models/Storage/StorageInfo.swift
class StorageInfo {
  /// App storage breakdown
  final AppStorageInfo appStorage;

  /// Device storage information
  final DeviceStorageInfo deviceStorage;

  /// Model storage information
  final ModelStorageInfo modelStorage;

  /// Cache size in bytes
  final int cacheSize;

  /// List of stored models
  final List<StoredModel> storedModels;

  /// Last updated timestamp
  final DateTime lastUpdated;

  const StorageInfo({
    required this.appStorage,
    required this.deviceStorage,
    required this.modelStorage,
    required this.cacheSize,
    this.storedModels = const [],
    required this.lastUpdated,
  });

  /// Empty storage info for initialization
  static final empty = StorageInfo(
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
    modelStorage: const ModelStorageInfo(
      totalSize: 0,
      modelCount: 0,
      modelsByFramework: {},
      largestModel: null,
    ),
    cacheSize: 0,
    storedModels: [],
    lastUpdated: DateTime.fromMillisecondsSinceEpoch(0),
  );

  /// Create from JSON map
  factory StorageInfo.fromJson(Map<String, dynamic> json) {
    return StorageInfo(
      appStorage:
          AppStorageInfo.fromJson(json['appStorage'] as Map<String, dynamic>),
      deviceStorage: DeviceStorageInfo.fromJson(
          json['deviceStorage'] as Map<String, dynamic>),
      modelStorage: ModelStorageInfo.fromJson(
          json['modelStorage'] as Map<String, dynamic>),
      cacheSize: (json['cacheSize'] as num?)?.toInt() ?? 0,
      storedModels: (json['storedModels'] as List<dynamic>?)
              ?.map((e) => StoredModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'appStorage': appStorage.toJson(),
      'deviceStorage': deviceStorage.toJson(),
      'modelStorage': modelStorage.toJson(),
      'cacheSize': cacheSize,
      'storedModels': storedModels.map((m) => m.toJson()).toList(),
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }
}
