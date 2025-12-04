import '../../models/storage/storage_info.dart';

/// Protocol for storage monitoring operations.
/// Matches iOS StorageMonitoring from Core/Protocols/Storage/StorageMonitoring.swift
abstract interface class StorageMonitoring {
  /// Start monitoring storage changes
  void startMonitoring();

  /// Stop monitoring storage changes
  void stopMonitoring();

  /// Get current storage information
  Future<StorageInfo> getStorageInfo();

  /// Check if monitoring is currently active
  bool get isMonitoring;
}

/// Default mock implementation of StorageMonitoring.
/// TODO: Implement platform-specific storage monitoring when FFI bridge is ready.
class MockStorageMonitoring implements StorageMonitoring {
  bool _isMonitoring = false;

  @override
  void startMonitoring() {
    _isMonitoring = true;
  }

  @override
  void stopMonitoring() {
    _isMonitoring = false;
  }

  @override
  Future<StorageInfo> getStorageInfo() async {
    return StorageInfo.empty;
  }

  @override
  bool get isMonitoring => _isMonitoring;
}
