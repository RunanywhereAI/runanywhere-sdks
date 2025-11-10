/// Memory Manager Protocol
/// Similar to Swift SDK's MemoryManager
abstract class MemoryManager {
  /// Get current memory usage
  Future<int> getCurrentMemoryUsage();

  /// Get available memory
  Future<int> getAvailableMemory();

  /// Check if memory can be allocated
  Future<bool> canAllocate(int size);

  /// Register memory usage for a model
  Future<void> registerMemory(String modelId, int size);

  /// Unregister memory usage for a model
  Future<void> unregisterMemory(String modelId);

  /// Get memory pressure level
  MemoryPressureLevel getMemoryPressureLevel();
}

/// Memory Pressure Level enum
enum MemoryPressureLevel {
  normal,
  warning,
  critical,
}

