import 'dart:async';
import '../../foundation/logging/sdk_logger.dart';
import 'models/memory_models.dart';
import 'cache_eviction.dart';
import 'allocation_manager.dart';

/// Handles memory pressure situations and coordinates response actions
/// Matches iOS PressureHandler
class PressureHandler {
  final SDKLogger _logger = SDKLogger(category: 'PressureHandler');

  CacheEviction? _evictionHandler;
  AllocationManager? _allocationManager;
  int _memoryThreshold = 500 * 1024 * 1024; // 500MB

  // Stream controller for pressure notifications
  final StreamController<MemoryPressureNotificationInfo>
      _pressureNotifications =
      StreamController<MemoryPressureNotificationInfo>.broadcast();

  /// Stream of pressure handling notifications
  Stream<MemoryPressureNotificationInfo> get pressureNotifications =>
      _pressureNotifications.stream;

  PressureHandler();

  void configure({required int memoryThreshold}) {
    _memoryThreshold = memoryThreshold;
  }

  void setEvictionHandler(CacheEviction handler) {
    _evictionHandler = handler;
  }

  void setAllocationManager(AllocationManager manager) {
    _allocationManager = manager;
  }

  // MARK: - Pressure Handling

  /// Handle memory pressure at a given level
  Future<MemoryPressureResponse> handlePressure({
    required MemoryPressureLevel level,
    List<String> modelsToEvict = const [],
  }) async {
    _logger.info('Handling memory pressure at level: $level');

    final startTime = DateTime.now();
    int totalFreed = 0;
    final evictedModels = <String>[];

    switch (level) {
      case MemoryPressureLevel.low:
      case MemoryPressureLevel.medium:
        // No action needed for low/medium pressure
        totalFreed = 0;
        break;
      case MemoryPressureLevel.high:
        // Light cleanup for high pressure
        final result =
            await _handleWarningPressure(modelsToEvict: modelsToEvict);
        totalFreed = result.$1;
        evictedModels.addAll(result.$2);
        break;
      case MemoryPressureLevel.warning:
        final result =
            await _handleWarningPressure(modelsToEvict: modelsToEvict);
        totalFreed = result.$1;
        evictedModels.addAll(result.$2);
        break;
      case MemoryPressureLevel.critical:
        final result =
            await _handleCriticalPressure(modelsToEvict: modelsToEvict);
        totalFreed = result.$1;
        evictedModels.addAll(result.$2);
        break;
    }

    final duration = DateTime.now().difference(startTime);
    final freedString = _formatBytes(totalFreed);

    _logger.info(
        'Memory pressure handling completed in ${duration.inMilliseconds}ms, freed $freedString');

    // Post pressure handling notification
    _postPressureHandlingNotification(
      level: level,
      freedMemory: totalFreed,
      duration: duration,
    );

    return MemoryPressureResponse(
      level: level,
      freedMemory: totalFreed,
      duration: duration,
      modelsEvicted: evictedModels,
      success: totalFreed > 0 || modelsToEvict.isEmpty,
    );
  }

  /// Handle system memory warning
  Future<void> handleSystemMemoryWarning() async {
    _logger.warning('System memory warning received');
    await handlePressure(level: MemoryPressureLevel.critical);
  }

  // MARK: - Pressure Response Strategies

  Future<(int, List<String>)> _handleWarningPressure({
    required List<String> modelsToEvict,
  }) async {
    int totalFreed = 0;
    final evictedModels = <String>[];

    // First, try evicting suggested models
    if (modelsToEvict.isNotEmpty) {
      final result = await _evictModels(modelsToEvict);
      totalFreed += result.$1;
      evictedModels.addAll(result.$2);
    }

    // If that's not enough, use eviction handler to find more candidates
    if (totalFreed < _calculateTargetFreedMemory(MemoryPressureLevel.warning)) {
      final evictionHandler = _evictionHandler;
      if (evictionHandler == null) {
        _logger.error('No eviction handler available for additional cleanup');
        return (totalFreed, evictedModels);
      }

      final additionalTarget =
          _calculateTargetFreedMemory(MemoryPressureLevel.warning) - totalFreed;
      final additionalModels =
          evictionHandler.selectModelsToEvict(targetMemory: additionalTarget);
      final result = await _evictModels(additionalModels);
      totalFreed += result.$1;
      evictedModels.addAll(result.$2);
    }

    return (totalFreed, evictedModels);
  }

  Future<(int, List<String>)> _handleCriticalPressure({
    required List<String> modelsToEvict,
  }) async {
    int totalFreed = 0;
    final evictedModels = <String>[];

    // In critical situations, be more aggressive
    if (modelsToEvict.isNotEmpty) {
      final result = await _evictModels(modelsToEvict);
      totalFreed += result.$1;
      evictedModels.addAll(result.$2);
    }

    // Force additional cleanup if needed
    if (totalFreed <
        _calculateTargetFreedMemory(MemoryPressureLevel.critical)) {
      final evictionHandler = _evictionHandler;
      if (evictionHandler == null) {
        _logger.error('No eviction handler available for critical cleanup');
        return (totalFreed, evictedModels);
      }

      // Use more aggressive eviction strategy
      final additionalTarget =
          _calculateTargetFreedMemory(MemoryPressureLevel.critical) -
              totalFreed;
      final additionalModels = evictionHandler.selectModelsForCriticalEviction(
          targetMemory: additionalTarget);
      final result = await _evictModels(additionalModels);
      totalFreed += result.$1;
      evictedModels.addAll(result.$2);
    }

    return (totalFreed, evictedModels);
  }

  // MARK: - Memory Eviction

  Future<(int, List<String>)> _evictModels(List<String> modelIds) async {
    if (modelIds.isEmpty) return (0, <String>[]);

    _logger.info('Evicting ${modelIds.length} models due to memory pressure');

    int totalFreed = 0;
    final evictedModels = <String>[];

    for (final modelId in modelIds) {
      final freed = await _evictModel(modelId);
      totalFreed += freed;
      if (freed > 0) {
        evictedModels.add(modelId);
      }
    }

    return (totalFreed, evictedModels);
  }

  Future<int> _evictModel(String modelId) async {
    _logger.debug('Evicting model: $modelId');

    final allocationManager = _allocationManager;
    if (allocationManager == null) {
      return 0;
    }

    return await allocationManager.unloadModel(modelId);
  }

  // MARK: - Memory Calculations

  int _calculateTargetFreedMemory(MemoryPressureLevel level) {
    switch (level) {
      case MemoryPressureLevel.low:
      case MemoryPressureLevel.medium:
        return 0;
      case MemoryPressureLevel.high:
        return _memoryThreshold ~/ 2;
      case MemoryPressureLevel.warning:
        return _memoryThreshold;
      case MemoryPressureLevel.critical:
        return _memoryThreshold * 2;
    }
  }

  // MARK: - Notifications

  void _postPressureHandlingNotification({
    required MemoryPressureLevel level,
    required int freedMemory,
    required Duration duration,
  }) {
    final response = MemoryPressureNotificationInfo(
      level: level,
      freedMemory: freedMemory,
      duration: duration,
    );

    _pressureNotifications.add(response);
  }

  // MARK: - Cleanup

  void dispose() {
    _pressureNotifications.close();
  }

  // MARK: - Helper

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
