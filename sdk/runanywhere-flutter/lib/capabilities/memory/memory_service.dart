import 'dart:async';
import '../../foundation/logging/sdk_logger.dart';
import '../../core/models/framework/llm_framework.dart';
import '../model_loading/models/loaded_model.dart';
import 'models/memory_models.dart';
import 'allocation_manager.dart';
import 'pressure_handler.dart';
import 'cache_eviction.dart';
import 'memory_monitor.dart';
import 'monitors/threshold_watcher.dart';

// Re-export memory models for convenience
export 'models/memory_models.dart';

/// Central memory management service
/// Matches iOS MemoryService
class MemoryService {
  final AllocationManager allocationManager;
  final PressureHandler pressureHandler;
  final CacheEviction cacheEviction;
  final MemoryMonitor memoryMonitor;
  final ThresholdWatcher thresholdWatcher;
  final SDKLogger _logger = SDKLogger(category: 'MemoryService');

  // Memory thresholds
  int _memoryThreshold = 500 * 1024 * 1024; // 500MB
  int _criticalThreshold = 200 * 1024 * 1024; // 200MB

  MemoryService({
    AllocationManager? allocationManager,
    PressureHandler? pressureHandler,
    CacheEviction? cacheEviction,
    MemoryMonitor? memoryMonitor,
    ThresholdWatcher? thresholdWatcher,
  })  : allocationManager = allocationManager ?? AllocationManager(),
        pressureHandler = pressureHandler ?? PressureHandler(),
        cacheEviction = cacheEviction ?? CacheEviction(),
        memoryMonitor = memoryMonitor ?? MemoryMonitor(),
        thresholdWatcher = thresholdWatcher ?? ThresholdWatcher() {
    _setupIntegration();
  }

  void _setupIntegration() {
    // Connect cache eviction with allocation manager
    cacheEviction.setAllocationManager(allocationManager);

    // Connect pressure handler with cache eviction and allocation manager
    pressureHandler.setEvictionHandler(cacheEviction);
    pressureHandler.setAllocationManager(allocationManager);

    // Connect threshold watcher with memory monitor
    thresholdWatcher.setMemoryMonitor(memoryMonitor);

    // Connect allocation manager with pressure monitoring
    allocationManager.setPressureCallback(() {
      unawaited(checkMemoryConditions());
    });
  }

  // MARK: - Model Memory Management

  /// Register a model with memory tracking
  void registerModel(
    MemoryLoadedModel model, {
    required int size,
    required dynamic service,
    MemoryPriority priority = MemoryPriority.normal,
  }) {
    allocationManager.registerModel(
      model,
      size: size,
      service: service,
      priority: priority,
    );

    // Check for memory pressure after registration
    unawaited(checkMemoryConditions());
  }

  /// Register a loaded model (convenience method)
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

    registerModel(
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
  }

  /// Unregister a model
  void unregisterModel(String modelId) {
    allocationManager.unregisterModel(modelId);
  }

  /// Touch a model (update last access time)
  void touchModel(String modelId) {
    allocationManager.touchModel(modelId);
  }

  // MARK: - Memory Pressure Management

  /// Handle memory pressure at a given level
  Future<void> handleMemoryPressure({MemoryPressureLevel level = MemoryPressureLevel.warning}) async {
    _logger.info('Handling memory pressure at level: $level');

    final targetMemory = _calculateTargetMemory(level);
    final modelsToEvict = cacheEviction.selectModelsToEvict(targetMemory: targetMemory);

    await pressureHandler.handlePressure(
      level: level,
      modelsToEvict: modelsToEvict,
    );
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

  // MARK: - Memory Information

  /// Get current memory usage by models
  int getCurrentMemoryUsage() {
    return allocationManager.getTotalModelMemory();
  }

  /// Get available memory
  int getAvailableMemory() {
    return memoryMonitor.getAvailableMemory();
  }

  /// Check if memory is available for allocation
  bool hasAvailableMemory(int size) {
    return getAvailableMemory() >= size;
  }

  /// Check if memory can be allocated
  Future<bool> canAllocate(int size) async {
    return await requestMemory(size: size);
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

  /// Check if a model is loaded
  bool isModelLoaded(String modelId) {
    return allocationManager.isModelLoaded(modelId);
  }

  /// Get memory usage for a specific model
  int? getModelMemoryUsage(String modelId) {
    return allocationManager.getModelMemoryUsage(modelId);
  }

  /// Get loaded model infos
  List<MemoryLoadedModelInfo> getLoadedModels() {
    return allocationManager.getLoadedModelInfos();
  }

  /// Get loaded model count
  int getLoadedModelCount() {
    return allocationManager.getLoadedModelCount();
  }

  /// Check health status
  bool isHealthy() {
    // Basic health check - ensure all components are available
    return memoryMonitor.getAvailableMemory() > 0;
  }

  // MARK: - Configuration

  /// Set memory threshold
  void setMemoryThreshold(int threshold) {
    _memoryThreshold = threshold;
    memoryMonitor.configure(
      memoryThreshold: _memoryThreshold,
      criticalThreshold: _criticalThreshold,
    );
    thresholdWatcher.configure(
      memoryThreshold: _memoryThreshold,
      criticalThreshold: _criticalThreshold,
    );
  }

  /// Set critical threshold
  void setCriticalThreshold(int threshold) {
    _criticalThreshold = threshold;
    memoryMonitor.configure(
      memoryThreshold: _memoryThreshold,
      criticalThreshold: _criticalThreshold,
    );
    thresholdWatcher.configure(
      memoryThreshold: _memoryThreshold,
      criticalThreshold: _criticalThreshold,
    );
  }

  // MARK: - Threshold Watching

  /// Start watching memory thresholds
  void startThresholdWatching() {
    thresholdWatcher.startWatching();
  }

  /// Stop watching memory thresholds
  void stopThresholdWatching() {
    thresholdWatcher.stopWatching();
  }

  /// Get threshold statistics
  ThresholdStatistics getThresholdStatistics() {
    return thresholdWatcher.getThresholdStatistics();
  }

  // MARK: - Private Implementation

  /// Check memory conditions and handle pressure if needed
  Future<void> checkMemoryConditions() async {
    final available = getAvailableMemory();
    final stats = memoryMonitor.getCurrentStats();

    // Check thresholds
    thresholdWatcher.checkThresholds(stats);

    if (available < _criticalThreshold) {
      await handleMemoryPressure(level: MemoryPressureLevel.critical);
    } else if (available < _memoryThreshold) {
      await handleMemoryPressure(level: MemoryPressureLevel.warning);
    }
  }

  int _calculateTargetMemory(MemoryPressureLevel level) {
    switch (level) {
      case MemoryPressureLevel.low:
      case MemoryPressureLevel.medium:
        return _memoryThreshold;
      case MemoryPressureLevel.high:
        return (_memoryThreshold * 1.5).round();
      case MemoryPressureLevel.warning:
        return _memoryThreshold * 2;
      case MemoryPressureLevel.critical:
        return _memoryThreshold * 3;
    }
  }
}
