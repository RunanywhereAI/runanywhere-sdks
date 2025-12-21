import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import '../../models/storage/storage_info.dart';
import '../../models/storage/model_storage_info.dart';
import '../../models/storage/storage_recommendation.dart';
import '../../models/storage/app_storage_info.dart';
import '../../models/storage/device_storage_info.dart';

/// Represents storage availability status
class StorageAvailability {
  final bool isAvailable;
  final int requiredSpace;
  final int availableSpace;
  final bool hasWarning;
  final String? recommendation;

  const StorageAvailability({
    required this.isAvailable,
    required this.requiredSpace,
    required this.availableSpace,
    required this.hasWarning,
    this.recommendation,
  });
}

/// Protocol for storage analysis operations.
/// Matches iOS StorageAnalyzer from Infrastructure/FileManagement/Protocol/StorageAnalyzer.swift
abstract interface class StorageAnalyzer {
  /// Analyze overall storage situation
  Future<StorageInfo> analyzeStorage();

  /// Get model storage usage information
  Future<ModelStorageInfo> getModelStorageUsage();

  /// Check storage availability for a model
  /// [modelSize] - Required size in bytes
  /// [safetyMargin] - Safety margin as a percentage (e.g., 0.1 for 10%)
  StorageAvailability checkStorageAvailable({
    required int modelSize,
    double safetyMargin = 0.1,
  });

  /// Get storage recommendations based on current storage info
  List<StorageRecommendation> getRecommendations(StorageInfo storageInfo);

  /// Calculate size at a given path
  Future<int> calculateSize(String path);
}

/// Default implementation of StorageAnalyzer.
/// Matches iOS DefaultStorageAnalyzer from Infrastructure/FileManagement/Services/DefaultStorageAnalyzer.swift
class DefaultStorageAnalyzer implements StorageAnalyzer {
  // Cached values for performance
  int? _cachedAvailableSpace;
  DateTime? _lastCacheUpdate;
  static const _cacheDuration = Duration(seconds: 30);

  @override
  Future<StorageInfo> analyzeStorage() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = await getTemporaryDirectory();

    // Calculate directory sizes
    final documentsSize = await _calculateDirectorySize(appDir);
    final cacheSize = await _calculateDirectorySize(cacheDir);

    // Get device storage info
    final deviceStorage = await _getDeviceStorageInfo();

    // Get model storage info
    final modelStorage = await getModelStorageUsage();

    return StorageInfo(
      appStorage: AppStorageInfo(
        documentsSize: documentsSize,
        cacheSize: cacheSize,
        appSupportSize: 0, // Would need app support directory
        totalSize: documentsSize + cacheSize,
      ),
      deviceStorage: deviceStorage,
      modelStorage: modelStorage,
      cacheSize: cacheSize,
      storedModels: const [], // Would need to integrate with model registry
      lastUpdated: DateTime.now(),
    );
  }

  @override
  Future<ModelStorageInfo> getModelStorageUsage() async {
    // Get the models directory
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${appDir.path}/models');

    if (!await modelsDir.exists()) {
      return const ModelStorageInfo(
        totalSize: 0,
        modelCount: 0,
        modelsByFramework: {},
        largestModel: null,
      );
    }

    int totalSize = 0;
    int modelCount = 0;

    await for (final entity in modelsDir.list()) {
      if (entity is Directory) {
        final size = await _calculateDirectorySize(entity);
        totalSize += size;
        modelCount++;
      }
    }

    return ModelStorageInfo(
      totalSize: totalSize,
      modelCount: modelCount,
      modelsByFramework: const {},
      largestModel: null,
    );
  }

  @override
  StorageAvailability checkStorageAvailable({
    required int modelSize,
    double safetyMargin = 0.1,
  }) {
    final availableSpace = _cachedAvailableSpace ?? _getAvailableSpaceSync();
    final requiredSpace = (modelSize * (1 + safetyMargin)).round();

    final isAvailable = availableSpace > requiredSpace;
    final hasWarning = availableSpace < requiredSpace * 2;

    String? recommendation;
    if (!isAvailable) {
      final shortfall = requiredSpace - availableSpace;
      recommendation = 'Need ${_formatBytes(shortfall)} more space.';
    } else if (hasWarning) {
      recommendation = 'Storage space is getting low.';
    }

    return StorageAvailability(
      isAvailable: isAvailable,
      requiredSpace: requiredSpace,
      availableSpace: availableSpace,
      hasWarning: hasWarning,
      recommendation: recommendation,
    );
  }

  @override
  List<StorageRecommendation> getRecommendations(StorageInfo storageInfo) {
    final recommendations = <StorageRecommendation>[];

    final freeSpace = storageInfo.deviceStorage.freeSpace;
    final totalSpace = storageInfo.deviceStorage.totalSpace;

    if (totalSpace > 0) {
      final freePercentage = freeSpace / totalSpace;

      if (freePercentage < 0.1) {
        recommendations.add(const StorageRecommendation(
          type: RecommendationType.warning,
          message: 'Low storage space. Clear cache to free up space.',
          action: 'Clear Cache',
        ));
      }

      if (freePercentage < 0.05) {
        recommendations.add(const StorageRecommendation(
          type: RecommendationType.critical,
          message:
              'Critical storage shortage. Consider removing unused models.',
          action: 'Delete Models',
        ));
      }
    }

    if (storageInfo.storedModels.length > 5) {
      recommendations.add(const StorageRecommendation(
        type: RecommendationType.suggestion,
        message:
            'Multiple models stored. Consider removing models you don\'t use.',
        action: 'Review Models',
      ));
    }

    return recommendations;
  }

  @override
  Future<int> calculateSize(String path) async {
    final entity = FileSystemEntity.typeSync(path);

    if (entity == FileSystemEntityType.notFound) {
      return 0;
    }

    if (entity == FileSystemEntityType.file) {
      final file = File(path);
      return await file.length();
    }

    if (entity == FileSystemEntityType.directory) {
      return await _calculateDirectorySize(Directory(path));
    }

    return 0;
  }

  // MARK: - Private Methods

  Future<int> _calculateDirectorySize(Directory directory) async {
    if (!await directory.exists()) return 0;

    int totalSize = 0;

    try {
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          try {
            totalSize += await entity.length();
          } catch (_) {
            // Skip files we can't read
          }
        }
      }
    } catch (_) {
      // Handle directory access errors
    }

    return totalSize;
  }

  Future<DeviceStorageInfo> _getDeviceStorageInfo() async {
    // Get available space using path_provider directory
    final appDir = await getApplicationDocumentsDirectory();

    try {
      // On iOS/Android, we can get filesystem stats
      final stat = await Process.run('df', ['-k', appDir.path]);
      if (stat.exitCode == 0) {
        // Parse df output (second line, columns: filesystem, total, used, available, %, mount)
        final lines = (stat.stdout as String).split('\n');
        if (lines.length > 1) {
          final parts = lines[1].split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            // df reports in 1K blocks
            final total = (int.tryParse(parts[1]) ?? 0) * 1024;
            final used = (int.tryParse(parts[2]) ?? 0) * 1024;
            final available = (int.tryParse(parts[3]) ?? 0) * 1024;

            _cachedAvailableSpace = available;
            _lastCacheUpdate = DateTime.now();

            return DeviceStorageInfo(
              totalSpace: total,
              freeSpace: available,
              usedSpace: used,
            );
          }
        }
      }
    } catch (_) {
      // Fall through to default values
    }

    // Default fallback: estimate based on typical device storage
    const defaultTotal = 64 * 1024 * 1024 * 1024; // 64 GB
    const defaultFree = 10 * 1024 * 1024 * 1024; // 10 GB free

    _cachedAvailableSpace = defaultFree;
    _lastCacheUpdate = DateTime.now();

    return const DeviceStorageInfo(
      totalSpace: defaultTotal,
      freeSpace: defaultFree,
      usedSpace: defaultTotal - defaultFree,
    );
  }

  int _getAvailableSpaceSync() {
    // Check if cache is still valid
    if (_cachedAvailableSpace != null &&
        _lastCacheUpdate != null &&
        DateTime.now().difference(_lastCacheUpdate!) < _cacheDuration) {
      return _cachedAvailableSpace!;
    }

    // Return default if no cache
    return 10 * 1024 * 1024 * 1024; // 10 GB default
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
