import '../../../foundation/logging/sdk_logger.dart';
import 'memory_service.dart';
import 'allocation_manager.dart';

/// Handles memory pressure by evicting models
class PressureHandler {
  final SDKLogger logger = SDKLogger(category: 'PressureHandler');

  /// Handle memory pressure
  Future<void> handlePressure({
    required MemoryPressureLevel level,
    required List<String> modelsToEvict,
    required AllocationManager allocationManager,
  }) async {
    logger.info('Handling memory pressure: $level, evicting ${modelsToEvict.length} models');

    for (final modelId in modelsToEvict) {
      final allocation = allocationManager.getAllocations()[modelId];
      if (allocation != null) {
        try {
          // Cleanup service
          await allocation.service.cleanup();
          // Unregister model
          allocationManager.unregisterModel(modelId);
          logger.info('Evicted model: $modelId');
        } catch (e) {
          logger.error('Failed to evict model $modelId: $e');
        }
      }
    }
  }
}

