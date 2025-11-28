import 'dart:collection';
import '../../../foundation/logging/sdk_logger.dart';
import '../../../core/module_registry.dart';
import 'memory_service.dart';

/// Manages memory allocation for loaded models
class AllocationManager {
  final SDKLogger logger = SDKLogger(category: 'AllocationManager');
  final Map<String, _ModelAllocation> _allocations = {};
  int _totalAllocated = 0;

  /// Register a model allocation
  void registerModel(
    MemoryLoadedModel model, {
    required int size,
    required dynamic service,
    MemoryPriority priority = MemoryPriority.normal,
  }) {
    _allocations[model.id] = _ModelAllocation(
      model: model,
      size: size,
      service: service,
      priority: priority,
      lastAccess: DateTime.now(),
    );

    _totalAllocated += size;
    logger.info('Registered model ${model.id} with ${size / (1024 * 1024)}MB');
  }

  /// Unregister a model allocation
  void unregisterModel(String modelId) {
    final allocation = _allocations.remove(modelId);
    if (allocation != null) {
      _totalAllocated -= allocation.size;
      logger.info('Unregistered model $modelId');
    }
  }

  /// Touch a model (update last access time)
  void touchModel(String modelId) {
    final allocation = _allocations[modelId];
    if (allocation != null) {
      allocation.lastAccess = DateTime.now();
    }
  }

  /// Request memory allocation
  Future<bool> requestMemory({
    required int size,
    MemoryPriority priority = MemoryPriority.normal,
  }) async {
    // Check if we can allocate
    // In a real implementation, this would check system memory
    // For now, we'll use a simple threshold
    const maxMemory = 2 * 1024 * 1024 * 1024; // 2GB
    if (_totalAllocated + size > maxMemory) {
      // Try to evict low priority models
      final evictable = _getEvictableModels(size);
      if (evictable.isNotEmpty) {
        // Evict models
        for (final modelId in evictable) {
          unregisterModel(modelId);
        }
      } else {
        return false;
      }
    }

    return true;
  }

  /// Release memory
  Future<void> releaseMemory(int size) async {
    // Memory is released when models are unregistered
    // This is a placeholder for explicit memory release
  }

  /// Get total model memory
  int getTotalModelMemory() {
    return _totalAllocated;
  }

  /// Get loaded model count
  int getLoadedModelCount() {
    return _allocations.length;
  }

  /// Get loaded models
  List<MemoryLoadedModel> getLoadedModels() {
    return _allocations.values.map((a) => a.model).toList();
  }

  /// Get allocations (for cache eviction)
  Map<String, _ModelAllocation> getAllocations() {
    return Map.from(_allocations);
  }

  /// Get evictable models (low priority, least recently used)
  List<String> _getEvictableModels(int requiredSize) {
    final sorted = _allocations.entries.toList()
      ..sort((a, b) {
        // Sort by priority first, then by last access
        final priorityCompare = a.value.priority.index.compareTo(b.value.priority.index);
        if (priorityCompare != 0) return priorityCompare;
        return a.value.lastAccess.compareTo(b.value.lastAccess);
      });

    final evictable = <String>[];
    int freed = 0;

    for (final entry in sorted) {
      if (entry.value.priority == MemoryPriority.low) {
        evictable.add(entry.key);
        freed += entry.value.size;
        if (freed >= requiredSize) break;
      }
    }

    return evictable;
  }
}

/// Internal model allocation tracking
class _ModelAllocation {
  final MemoryLoadedModel model;
  final int size;
  final dynamic service;
  final MemoryPriority priority;
  DateTime lastAccess;

  _ModelAllocation({
    required this.model,
    required this.size,
    required this.service,
    required this.priority,
    required this.lastAccess,
  });
}

