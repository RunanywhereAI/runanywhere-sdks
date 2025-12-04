import 'dart:async';
import '../../foundation/logging/sdk_logger.dart';
import '../../core/models/common.dart';
import '../model_loading/models/loaded_model.dart';
import 'allocation_manager.dart';
import 'pressure_handler.dart';
import 'cache_eviction.dart';
import 'memory_monitor.dart';

/// Central memory management service
class MemoryService {
  final AllocationManager allocationManager;
  final PressureHandler pressureHandler;
  final CacheEviction cacheEviction;
  final MemoryMonitor memoryMonitor;
  final SDKLogger logger = SDKLogger(category: 'MemoryService');

  // Memory thresholds
  int _memoryThreshold = 500 * 1024 * 1024; // 500MB
  final int _criticalThreshold = 200 * 1024 * 1024; // 200MB

  MemoryService({
    AllocationManager? allocationManager,
    PressureHandler? pressureHandler,
    CacheEviction? cacheEviction,
    MemoryMonitor? memoryMonitor,
  })  : allocationManager = allocationManager ?? AllocationManager(),
        pressureHandler = pressureHandler ?? PressureHandler(),
        cacheEviction = cacheEviction ?? CacheEviction(),
        memoryMonitor = memoryMonitor ?? MemoryMonitor() {
    _setupIntegration();
  }

  void _setupIntegration() {
    // Setup memory pressure monitoring
    memoryMonitor.onMemoryPressure = (level) {
      unawaited(handleMemoryPressure(level: level));
    };
  }

  /// Register a loaded model
  Future<void> registerLoadedModel(
    LoadedModel model,
    int size,
    dynamic service, {
    MemoryPriority priority = MemoryPriority.normal,
  }) async {
    // Use preferredFramework or first compatible framework, or default to foundationModels
    final framework = model.model.preferredFramework ??
        model.model.compatibleFrameworks.firstOrNull ??
        LLMFramework.foundationModels;

    allocationManager.registerModel(
      MemoryLoadedModel(
        id: model.model.id,
        name: model.model.name,
        size: size,
        framework: framework,
      ),
      size: size,
      service: service,
      priority: priority,
    );

    // Check for memory pressure after registration
    await checkMemoryConditions();
  }

  /// Unregister a model
  void unregisterModel(String modelId) {
    allocationManager.unregisterModel(modelId);
  }

  /// Touch a model (update last access time)
  void touchModel(String modelId) {
    allocationManager.touchModel(modelId);
  }

  /// Handle memory pressure
  Future<void> handleMemoryPressure({MemoryPressureLevel level = MemoryPressureLevel.warning}) async {
    logger.info('Handling memory pressure at level: $level');

    final targetMemory = _calculateTargetMemory(level);
    final modelsToEvict = cacheEviction.selectModelsToEvict(
      targetMemory: targetMemory,
      allocationManager: allocationManager,
    );

    await pressureHandler.handlePressure(
      level: level,
      modelsToEvict: modelsToEvict,
      allocationManager: allocationManager,
    );
  }

  /// Calculate target memory to free up
  int _calculateTargetMemory(MemoryPressureLevel level) {
    final available = getAvailableMemory();

    switch (level) {
      case MemoryPressureLevel.warning:
        final target = _memoryThreshold - available;
        return target > 0 ? target : 0;
      case MemoryPressureLevel.critical:
        final target = _criticalThreshold - available;
        return target > 0 ? target : 0;
    }
  }

  /// Request memory allocation
  Future<bool> requestMemory({
    required int size,
    MemoryPriority priority = MemoryPriority.normal,
  }) async {
    return await allocationManager.requestMemory(size: size, priority: priority);
  }

  /// Release memory
  Future<void> releaseMemory(int size) async {
    await allocationManager.releaseMemory(size);
  }

  /// Check if memory can be allocated
  Future<bool> canAllocate(int size) async {
    return await requestMemory(size: size);
  }

  /// Get current memory usage
  int getCurrentMemoryUsage() {
    return allocationManager.getTotalModelMemory();
  }

  /// Get available memory
  int getAvailableMemory() {
    return memoryMonitor.getAvailableMemory();
  }

  /// Get loaded model count
  int getLoadedModelCount() {
    return allocationManager.getLoadedModelCount();
  }

  /// Check if memory is available
  bool hasAvailableMemory(int size) {
    return getAvailableMemory() >= size;
  }

  /// Get memory statistics
  MemoryStatistics getMemoryStatistics() {
    final totalMemory = memoryMonitor.getTotalMemory();
    final availableMemory = memoryMonitor.getAvailableMemory();
    final modelMemory = allocationManager.getTotalModelMemory();
    final loadedModelCount = allocationManager.getLoadedModelCount();
    final memoryPressure = availableMemory < _memoryThreshold;

    return MemoryStatistics(
      totalMemory: totalMemory,
      availableMemory: availableMemory,
      modelMemory: modelMemory,
      loadedModelCount: loadedModelCount,
      memoryPressure: memoryPressure,
    );
  }

  /// Set memory threshold
  void setMemoryThreshold(int threshold) {
    _memoryThreshold = threshold;
  }

  /// Check memory conditions and handle pressure if needed
  Future<void> checkMemoryConditions() async {
    final available = getAvailableMemory();
    if (available < _criticalThreshold) {
      await handleMemoryPressure(level: MemoryPressureLevel.critical);
    } else if (available < _memoryThreshold) {
      await handleMemoryPressure(level: MemoryPressureLevel.warning);
    }
  }
}

/// Memory priority levels
enum MemoryPriority {
  low,
  normal,
  high,
  critical,
}

/// Memory pressure levels
enum MemoryPressureLevel {
  warning,
  critical,
}

/// Memory statistics
class MemoryStatistics {
  final int totalMemory;
  final int availableMemory;
  final int modelMemory;
  final int loadedModelCount;
  final bool memoryPressure;

  MemoryStatistics({
    required this.totalMemory,
    required this.availableMemory,
    required this.modelMemory,
    required this.loadedModelCount,
    required this.memoryPressure,
  });
}

/// Memory loaded model representation
class MemoryLoadedModel {
  final String id;
  final String name;
  final int size;
  final LLMFramework framework;

  MemoryLoadedModel({
    required this.id,
    required this.name,
    required this.size,
    required this.framework,
  });
}
