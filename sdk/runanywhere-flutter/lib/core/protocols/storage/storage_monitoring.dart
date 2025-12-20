import 'dart:async';

import '../../models/storage/storage_info.dart';
import 'storage_analyzer.dart';

/// Storage event types for monitoring
sealed class StorageEvent {
  const StorageEvent();
}

/// Event when storage space changes
class StorageSpaceChanged extends StorageEvent {
  final int previousFreeSpace;
  final int currentFreeSpace;

  const StorageSpaceChanged({
    required this.previousFreeSpace,
    required this.currentFreeSpace,
  });
}

/// Event when storage is running low
class LowStorageWarning extends StorageEvent {
  final int freeSpace;
  final int threshold;

  const LowStorageWarning({
    required this.freeSpace,
    required this.threshold,
  });
}

/// Protocol for storage monitoring operations.
/// Matches iOS storage monitoring patterns from Infrastructure/FileManagement/
abstract interface class StorageMonitoring {
  /// Start monitoring storage changes
  void startMonitoring({Duration interval = const Duration(seconds: 30)});

  /// Stop monitoring storage changes
  void stopMonitoring();

  /// Get current storage information
  Future<StorageInfo> getStorageInfo();

  /// Check if monitoring is currently active
  bool get isMonitoring;

  /// Stream of storage events
  Stream<StorageEvent> get storageEvents;
}

/// Default implementation of StorageMonitoring.
/// Matches iOS storage monitoring patterns from Infrastructure/FileManagement/
class DefaultStorageMonitoring implements StorageMonitoring {
  final StorageAnalyzer _storageAnalyzer;

  Timer? _monitorTimer;
  int _lastFreeSpace = 0;
  bool _isMonitoring = false;

  final StreamController<StorageEvent> _storageController =
      StreamController<StorageEvent>.broadcast();

  /// Low storage threshold: 500 MB (matches iOS)
  static const int _lowStorageThreshold = 500 * 1024 * 1024;

  /// Create a new storage monitoring instance
  DefaultStorageMonitoring({StorageAnalyzer? storageAnalyzer})
      : _storageAnalyzer = storageAnalyzer ?? DefaultStorageAnalyzer();

  @override
  Stream<StorageEvent> get storageEvents => _storageController.stream;

  @override
  bool get isMonitoring => _isMonitoring;

  @override
  void startMonitoring({Duration interval = const Duration(seconds: 30)}) {
    if (_isMonitoring) return;

    _isMonitoring = true;
    _monitorTimer?.cancel();

    // Get initial storage state (fire-and-forget, errors handled internally)
    unawaited(_updateStorageState());

    // Start periodic monitoring
    _monitorTimer =
        Timer.periodic(interval, (_) => unawaited(_updateStorageState()));
  }

  @override
  void stopMonitoring() {
    _isMonitoring = false;
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  @override
  Future<StorageInfo> getStorageInfo() async {
    return await _storageAnalyzer.analyzeStorage();
  }

  Future<void> _updateStorageState() async {
    try {
      final storageInfo = await _storageAnalyzer.analyzeStorage();
      final currentFreeSpace = storageInfo.deviceStorage.freeSpace;

      // Check for space changes
      if (_lastFreeSpace != 0 && currentFreeSpace != _lastFreeSpace) {
        _storageController.add(StorageSpaceChanged(
          previousFreeSpace: _lastFreeSpace,
          currentFreeSpace: currentFreeSpace,
        ));
      }

      // Check for low storage warning
      if (currentFreeSpace < _lowStorageThreshold) {
        _storageController.add(LowStorageWarning(
          freeSpace: currentFreeSpace,
          threshold: _lowStorageThreshold,
        ));
      }

      _lastFreeSpace = currentFreeSpace;
    } catch (_) {
      // Silently handle errors - monitoring should not crash the app
    }
  }

  /// Dispose resources
  void dispose() {
    stopMonitoring();
    unawaited(_storageController.close());
  }
}
