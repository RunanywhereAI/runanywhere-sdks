import 'dart:async';
import '../../foundation/logging/sdk_logger.dart';
import 'models/memory_models.dart';

/// Manages memory allocation and model registration
/// Matches iOS AllocationManager
class AllocationManager {
  final SDKLogger _logger = SDKLogger(category: 'AllocationManager');
  final Map<String, MemoryLoadedModelInfo> _loadedModels = {};
  void Function()? _pressureCallback;

  void setPressureCallback(void Function() callback) {
    _pressureCallback = callback;
  }

  // MARK: - Model Registration

  /// Register a model with memory tracking
  void registerModel(
    MemoryLoadedModel model, {
    required int size,
    required dynamic service,
    MemoryPriority priority = MemoryPriority.normal,
  }) {
    final modelInfo = MemoryLoadedModelInfo(
      model: model,
      size: size,
      service: service,
      priority: priority,
    );

    _loadedModels[model.id] = modelInfo;

    final sizeString = _formatBytes(size);
    _logger.info("Registered model '${model.name}' with $sizeString");

    // Trigger pressure callback outside of registration to prevent deadlock
    _pressureCallback?.call();
  }

  /// Unregister a model
  void unregisterModel(String modelId) {
    final modelInfo = _loadedModels.remove(modelId);
    if (modelInfo != null) {
      _logger.info("Unregistered model '${modelInfo.model.name}'");
    }
  }

  /// Update last used time for a model
  void touchModel(String modelId) {
    final modelInfo = _loadedModels[modelId];
    if (modelInfo != null) {
      modelInfo.lastUsed = DateTime.now();
    }
  }

  // MARK: - Memory Requests

  /// Request memory allocation
  Future<bool> requestMemory({
    required int size,
    MemoryPriority priority = MemoryPriority.normal,
  }) async {
    final availableMemory = _getCurrentAvailableMemory();

    if (availableMemory >= size) {
      _logger.debug('Memory request granted: ${_formatBytes(size)}');
      return true;
    }

    _logger.info('Insufficient memory, attempting to free space for ${_formatBytes(size)}');

    // Try to free memory based on priority
    final needed = size - availableMemory;
    final freed = await _freeMemory(needed: needed, requesterPriority: priority);

    final newAvailable = _getCurrentAvailableMemory();
    final success = newAvailable >= size;

    if (success) {
      _logger.info('Memory request successful after freeing ${_formatBytes(freed)}');
    } else {
      _logger.warning('Memory request failed, insufficient memory available');
    }

    return success;
  }

  /// Release memory
  Future<void> releaseMemory(int size) async {
    // Memory is automatically released when models are unloaded
    // This tracks explicit memory releases for accounting
    _logger.debug('Released ${_formatBytes(size)}');
  }

  // MARK: - Memory Information

  /// Get total memory used by all models
  int getTotalModelMemory() {
    return _loadedModels.values.fold<int>(0, (sum, info) => sum + info.size);
  }

  /// Get count of loaded models
  int getLoadedModelCount() {
    return _loadedModels.length;
  }

  /// Get list of loaded models
  List<MemoryLoadedModel> getLoadedModels() {
    return _loadedModels.values.map((info) => info.model).toList();
  }

  /// Get list of loaded model infos (for cache eviction)
  List<MemoryLoadedModelInfo> getLoadedModelInfos() {
    return _loadedModels.values.toList();
  }

  /// Check if a model is loaded
  bool isModelLoaded(String modelId) {
    return _loadedModels.containsKey(modelId);
  }

  /// Get memory usage for a specific model
  int? getModelMemoryUsage(String modelId) {
    return _loadedModels[modelId]?.size;
  }

  /// Get models for eviction consideration
  List<MemoryLoadedModelInfo> getModelsForEviction() {
    return _loadedModels.values.toList();
  }

  // MARK: - Model Unloading

  /// Unload a single model and return freed memory
  Future<int> unloadModel(String modelId) async {
    final modelInfo = _loadedModels.remove(modelId);
    if (modelInfo == null) {
      return 0;
    }

    final size = modelInfo.size;
    final sizeString = _formatBytes(size);
    _logger.info("Unloading model '${modelInfo.model.name}' to free $sizeString");

    // Notify service to cleanup
    try {
      await modelInfo.service?.cleanup();
    } catch (e) {
      _logger.error('Error cleaning up model service: $e');
    }

    return size;
  }

  /// Unload multiple models and return total freed memory
  Future<int> unloadModels(List<String> modelIds) async {
    int totalFreed = 0;

    for (final modelId in modelIds) {
      totalFreed += await unloadModel(modelId);
    }

    return totalFreed;
  }

  // MARK: - Private Implementation

  int _getCurrentAvailableMemory() {
    // Placeholder - in production, use platform channels to get actual memory
    // For now, return a conservative estimate based on total physical memory
    const int totalMemory = 4 * 1024 * 1024 * 1024; // 4GB default
    final usedByModels = getTotalModelMemory();
    const systemOverhead = totalMemory ~/ 2; // Assume 50% used by system
    return totalMemory - systemOverhead - usedByModels;
  }

  Future<int> _freeMemory({
    required int needed,
    required MemoryPriority requesterPriority,
  }) async {
    final models = _loadedModels.values.toList();

    // Sort models by eviction priority
    models.sort((a, b) {
      // Higher priority models are less likely to be evicted
      if (a.priority != b.priority) {
        return a.priority.value.compareTo(b.priority.value);
      }
      // If same priority, evict least recently used first
      return a.lastUsed.compareTo(b.lastUsed);
    });

    int freedMemory = 0;
    final modelsToUnload = <String>[];

    for (final model in models) {
      // Don't evict models with higher or equal priority unless absolutely necessary
      if (model.priority.value >= requesterPriority.value && freedMemory > 0) {
        continue;
      }

      modelsToUnload.add(model.model.id);
      freedMemory += model.size;

      if (freedMemory >= needed) {
        break;
      }
    }

    // Unload selected models
    final actualFreed = await unloadModels(modelsToUnload);
    return actualFreed;
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
