import '../../foundation/logging/sdk_logger.dart';
import 'allocation_manager.dart';
import 'models/memory_models.dart';

/// Manages cache eviction strategies and model selection for memory cleanup
/// Matches iOS CacheEviction
class CacheEviction {
  final SDKLogger _logger = SDKLogger(category: 'CacheEviction');
  AllocationManager? _allocationManager;

  void setAllocationManager(AllocationManager manager) {
    _allocationManager = manager;
  }

  // MARK: - Model Selection for Eviction

  /// Select models to evict to meet target memory
  List<String> selectModelsToEvict({required int targetMemory}) {
    final models = _getCurrentModels();
    return _selectModelsUsingStrategy(
      models: models,
      targetMemory: targetMemory,
      aggressive: false,
    );
  }

  /// Select models for critical eviction (more aggressive)
  List<String> selectModelsForCriticalEviction({required int targetMemory}) {
    final models = _getCurrentModels();
    return _selectModelsUsingStrategy(
      models: models,
      targetMemory: targetMemory,
      aggressive: true,
    );
  }

  /// Select a specific count of models to evict
  List<String> selectModelsToEvictByCount({required int count}) {
    final models = _getCurrentModels();
    final sortedModels =
        _sortModelsByEvictionPriority(models, aggressive: false);
    return sortedModels.take(count).map((m) => m.model.id).toList();
  }

  /// Select least important models
  List<String> selectLeastImportantModels({required int maxCount}) {
    final models = _getCurrentModels();
    final sortedModels = _sortModelsByImportance(models);
    return sortedModels.take(maxCount).map((m) => m.model.id).toList();
  }

  // MARK: - Eviction Strategies

  List<String> _selectModelsUsingStrategy({
    required List<MemoryLoadedModelInfo> models,
    required int targetMemory,
    required bool aggressive,
  }) {
    // Default to least recently used strategy
    return _selectByLeastRecentlyUsed(
      models: models,
      targetMemory: targetMemory,
      aggressive: aggressive,
    );
  }

  List<String> _selectByLeastRecentlyUsed({
    required List<MemoryLoadedModelInfo> models,
    required int targetMemory,
    required bool aggressive,
  }) {
    final sortedModels = models.toList()
      ..sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
    return _selectModelsToTarget(
      sortedModels: sortedModels,
      targetMemory: targetMemory,
      aggressive: aggressive,
    );
  }

  // ignore: unused_element - Reserved for future use (matches iOS eviction strategies)
  List<String> _selectByLargestFirst({
    required List<MemoryLoadedModelInfo> models,
    required int targetMemory,
    required bool aggressive,
  }) {
    final sortedModels = models.toList()
      ..sort((a, b) => b.size.compareTo(a.size));
    return _selectModelsToTarget(
      sortedModels: sortedModels,
      targetMemory: targetMemory,
      aggressive: aggressive,
    );
  }

  // ignore: unused_element - Reserved for future use (matches iOS eviction strategies)
  List<String> _selectByOldestFirst({
    required List<MemoryLoadedModelInfo> models,
    required int targetMemory,
    required bool aggressive,
  }) {
    final sortedModels = models.toList()
      ..sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
    return _selectModelsToTarget(
      sortedModels: sortedModels,
      targetMemory: targetMemory,
      aggressive: aggressive,
    );
  }

  // ignore: unused_element - Reserved for future use (matches iOS eviction strategies)
  List<String> _selectByPriority({
    required List<MemoryLoadedModelInfo> models,
    required int targetMemory,
    required bool aggressive,
  }) {
    final sortedModels = models.toList()
      ..sort((a, b) {
        // Lower priority models are evicted first
        if (a.priority != b.priority) {
          return a.priority.value.compareTo(b.priority.value);
        }
        // If same priority, evict least recently used first
        return a.lastUsed.compareTo(b.lastUsed);
      });
    return _selectModelsToTarget(
      sortedModels: sortedModels,
      targetMemory: targetMemory,
      aggressive: aggressive,
    );
  }

  List<String> _selectModelsToTarget({
    required List<MemoryLoadedModelInfo> sortedModels,
    required int targetMemory,
    required bool aggressive,
  }) {
    final modelsToEvict = <String>[];
    int freedMemory = 0;

    for (final model in sortedModels) {
      // In non-aggressive mode, skip critical priority models unless absolutely necessary
      if (!aggressive &&
          model.priority == MemoryPriority.critical &&
          freedMemory > 0) {
        continue;
      }

      modelsToEvict.add(model.model.id);
      freedMemory += model.size;

      final sizeString = _formatBytes(model.size);
      _logger.debug(
          "Selected model '${model.model.name}' for eviction (size: $sizeString)");

      if (freedMemory >= targetMemory) {
        break;
      }
    }

    final targetMemoryString = _formatBytes(targetMemory);
    _logger.info(
        'Selected ${modelsToEvict.length} models for eviction, target memory: $targetMemoryString');

    return modelsToEvict;
  }

  // MARK: - Model Sorting

  List<MemoryLoadedModelInfo> _sortModelsByEvictionPriority(
    List<MemoryLoadedModelInfo> models, {
    required bool aggressive,
  }) {
    return models.toList()
      ..sort((a, b) {
        // In aggressive mode, ignore critical priority
        if (!aggressive) {
          if (a.priority != b.priority) {
            return a.priority.value.compareTo(b.priority.value);
          }
        }

        // Consider both recency and size
        final aScore = _calculateEvictionScore(a);
        final bScore = _calculateEvictionScore(b);

        return aScore
            .compareTo(bScore); // Lower score = higher eviction priority
      });
  }

  List<MemoryLoadedModelInfo> _sortModelsByImportance(
      List<MemoryLoadedModelInfo> models) {
    return models.toList()
      ..sort((a, b) {
        // Higher priority = more important (lower eviction priority)
        if (a.priority != b.priority) {
          return a.priority.value.compareTo(b.priority.value);
        }

        // More recently used = more important
        return a.lastUsed.compareTo(b.lastUsed);
      });
  }

  double _calculateEvictionScore(MemoryLoadedModelInfo model) {
    final timeSinceUse = DateTime.now().difference(model.lastUsed).inSeconds;
    final priorityWeight =
        model.priority.value * 1000; // Higher priority = higher score
    final recencyScore = timeSinceUse / 3600; // Hours since last use

    // Lower score = higher eviction priority
    return priorityWeight - recencyScore;
  }

  // MARK: - Model Information

  /// Get eviction candidates with minimum memory size
  List<MemoryLoadedModelInfo> getEvictionCandidates({required int minMemory}) {
    final models = _getCurrentModels();
    return models.where((m) => m.size >= minMemory).toList();
  }

  /// Get models by priority
  List<MemoryLoadedModelInfo> getModelsByPriority(MemoryPriority priority) {
    final models = _getCurrentModels();
    return models.where((m) => m.priority == priority).toList();
  }

  /// Get models older than interval
  List<MemoryLoadedModelInfo> getModelsByUsageAge(
      {required Duration olderThan}) {
    final models = _getCurrentModels();
    final cutoffDate = DateTime.now().subtract(olderThan);
    return models.where((m) => m.lastUsed.isBefore(cutoffDate)).toList();
  }

  // MARK: - Statistics

  /// Get eviction statistics
  EvictionStatistics getEvictionStatistics() {
    final models = _getCurrentModels();

    final totalMemory = models.fold<int>(0, (sum, m) => sum + m.size);
    final modelsByPriority = <MemoryPriority, int>{};
    for (final model in models) {
      modelsByPriority[model.priority] =
          (modelsByPriority[model.priority] ?? 0) + 1;
    }

    final avgLastUsed = models.isEmpty
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(
            (models
                        .map((m) => m.lastUsed.millisecondsSinceEpoch)
                        .reduce((a, b) => a + b) /
                    models.length)
                .round(),
          );

    final oldestModel = models.isEmpty
        ? DateTime.now()
        : models
            .reduce((a, b) => a.lastUsed.isBefore(b.lastUsed) ? a : b)
            .lastUsed;

    final largestModel = models.isEmpty
        ? 0
        : models.reduce((a, b) => a.size > b.size ? a : b).size;

    return EvictionStatistics(
      totalModels: models.length,
      totalMemory: totalMemory,
      modelsByPriority: modelsByPriority,
      averageLastUsed: avgLastUsed,
      oldestModel: oldestModel,
      largestModel: largestModel,
    );
  }

  // MARK: - Private Implementation

  List<MemoryLoadedModelInfo> _getCurrentModels() {
    // Get models from allocation manager
    return _allocationManager?.getLoadedModelInfos() ?? [];
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
