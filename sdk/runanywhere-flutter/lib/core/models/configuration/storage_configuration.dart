import 'cache_eviction_policy.dart';

/// Configuration for storage behavior.
/// Matches iOS StorageConfiguration from Configuration/StorageConfiguration.swift
class StorageConfiguration {
  /// Maximum cache size in bytes
  final int maxCacheSize;

  /// Cache eviction policy
  final CacheEvictionPolicy evictionPolicy;

  /// Storage directory name
  final String directoryName;

  /// Whether to enable automatic cleanup
  final bool enableAutoCleanup;

  /// Auto cleanup interval
  final Duration autoCleanupInterval;

  /// Minimum free space to maintain (in bytes)
  final int minimumFreeSpace;

  /// Whether to compress stored models
  final bool enableCompression;

  const StorageConfiguration({
    this.maxCacheSize = 1073741824, // 1GB
    this.evictionPolicy = CacheEvictionPolicy.leastRecentlyUsed,
    this.directoryName = 'RunAnywhere',
    this.enableAutoCleanup = true,
    this.autoCleanupInterval = const Duration(hours: 24),
    this.minimumFreeSpace = 500000000, // 500MB
    this.enableCompression = false,
  });

  /// Create from JSON map
  factory StorageConfiguration.fromJson(Map<String, dynamic> json) {
    return StorageConfiguration(
      maxCacheSize: (json['maxCacheSize'] as num?)?.toInt() ?? 1073741824,
      evictionPolicy: CacheEvictionPolicy.fromRawValue(
              json['evictionPolicy'] as String? ?? 'lru') ??
          CacheEvictionPolicy.leastRecentlyUsed,
      directoryName: json['directoryName'] as String? ?? 'RunAnywhere',
      enableAutoCleanup: json['enableAutoCleanup'] as bool? ?? true,
      autoCleanupInterval: Duration(
        seconds: (json['autoCleanupInterval'] as num?)?.toInt() ?? 86400,
      ),
      minimumFreeSpace:
          (json['minimumFreeSpace'] as num?)?.toInt() ?? 500000000,
      enableCompression: json['enableCompression'] as bool? ?? false,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'maxCacheSize': maxCacheSize,
      'evictionPolicy': evictionPolicy.rawValue,
      'directoryName': directoryName,
      'enableAutoCleanup': enableAutoCleanup,
      'autoCleanupInterval': autoCleanupInterval.inSeconds,
      'minimumFreeSpace': minimumFreeSpace,
      'enableCompression': enableCompression,
    };
  }

  /// Create a copy with updated fields
  StorageConfiguration copyWith({
    int? maxCacheSize,
    CacheEvictionPolicy? evictionPolicy,
    String? directoryName,
    bool? enableAutoCleanup,
    Duration? autoCleanupInterval,
    int? minimumFreeSpace,
    bool? enableCompression,
  }) {
    return StorageConfiguration(
      maxCacheSize: maxCacheSize ?? this.maxCacheSize,
      evictionPolicy: evictionPolicy ?? this.evictionPolicy,
      directoryName: directoryName ?? this.directoryName,
      enableAutoCleanup: enableAutoCleanup ?? this.enableAutoCleanup,
      autoCleanupInterval: autoCleanupInterval ?? this.autoCleanupInterval,
      minimumFreeSpace: minimumFreeSpace ?? this.minimumFreeSpace,
      enableCompression: enableCompression ?? this.enableCompression,
    );
  }

  /// Get human-readable max cache size
  String get formattedMaxCacheSize {
    if (maxCacheSize >= 1073741824) {
      return '${(maxCacheSize / 1073741824).toStringAsFixed(1)} GB';
    } else if (maxCacheSize >= 1048576) {
      return '${(maxCacheSize / 1048576).toStringAsFixed(1)} MB';
    } else if (maxCacheSize >= 1024) {
      return '${(maxCacheSize / 1024).toStringAsFixed(1)} KB';
    }
    return '$maxCacheSize bytes';
  }
}
