/// Model Storage Manager Protocol
/// Similar to Swift SDK's ModelStorageManager
abstract class ModelStorageManager {
  /// Get storage path for a model
  Future<String> getStoragePath(String modelId);

  /// Check if model exists in storage
  Future<bool> modelExists(String modelId);

  /// Save model to storage
  Future<void> saveModel(String modelId, List<int> data);

  /// Load model from storage
  Future<List<int>> loadModel(String modelId);

  /// Delete model from storage
  Future<void> deleteModel(String modelId);

  /// Get storage info
  Future<StorageInfo> getStorageInfo();
}

/// Storage Info
class StorageInfo {
  final int totalSpace;
  final int usedSpace;
  final int availableSpace;

  StorageInfo({
    required this.totalSpace,
    required this.usedSpace,
    required this.availableSpace,
  });
}

