import '../../models/common/lifecycle_stage.dart';
import '../../models/common/memory_priority.dart';
import '../../models/framework/llm_framework.dart';

// Forward reference - LoadedModel is in capabilities/model_loading
// We use dynamic here to avoid circular dependency
// Implementations should cast appropriately

/// Protocol for memory management
/// Matches iOS MemoryManager from Core/Protocols/Memory/MemoryManager.swift
abstract class MemoryManager {
  /// Register a loaded model
  void registerLoadedModel(dynamic model, int size, dynamic service);

  /// Unregister a model
  void unregisterModel(String modelId);

  /// Get current memory usage in bytes
  int getCurrentMemoryUsage();

  /// Get available memory in bytes
  int getAvailableMemory();

  /// Check if enough memory is available
  bool hasAvailableMemory(int size);

  /// Check if memory can be allocated for a specific size
  Future<bool> canAllocate(int size);

  /// Handle memory pressure
  Future<void> handleMemoryPressure();

  /// Set memory threshold in bytes
  void setMemoryThreshold(int threshold);

  /// Get loaded models
  List<dynamic> getLoadedModels();

  /// Request memory for a model
  Future<bool> requestMemory({required int size, required MemoryPriority priority});

  /// Check if the memory manager is healthy and operational
  bool isHealthy();
}

/// Memory-tracked model information
/// Matches iOS MemoryLoadedModel from Core/Protocols/Memory/MemoryManager.swift
class MemoryLoadedModel {
  final String id;
  final String name;
  final int size;
  final LLMFramework framework;
  final DateTime loadedAt;
  DateTime lastUsed;
  final MemoryPriority priority;

  MemoryLoadedModel({
    required this.id,
    required this.name,
    required this.size,
    required this.framework,
    DateTime? loadedAt,
    DateTime? lastUsed,
    this.priority = MemoryPriority.normal,
  })  : loadedAt = loadedAt ?? DateTime.now(),
        lastUsed = lastUsed ?? DateTime.now();

  /// Mark as recently used
  void markUsed() {
    lastUsed = DateTime.now();
  }

  /// JSON serialization
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'size': size,
        'framework': framework.rawValue,
        'loadedAt': loadedAt.toIso8601String(),
        'lastUsed': lastUsed.toIso8601String(),
        'priority': priority.value,
      };

  factory MemoryLoadedModel.fromJson(Map<String, dynamic> json) {
    return MemoryLoadedModel(
      id: json['id'] as String,
      name: json['name'] as String,
      size: json['size'] as int,
      framework: LLMFramework.fromRawValue(json['framework'] as String) ??
          LLMFramework.llamaCpp,
      loadedAt: DateTime.parse(json['loadedAt'] as String),
      lastUsed: DateTime.parse(json['lastUsed'] as String),
      priority: MemoryPriority.values[json['priority'] as int],
    );
  }
}

/// Progress observer protocol
/// Matches iOS ProgressObserver from Core/Protocols/Memory/MemoryManager.swift
abstract class ProgressObserver {
  /// Called when progress is updated
  void progressDidUpdate(OverallProgress progress);

  /// Called when a stage completes
  void stageDidComplete(LifecycleStage stage);

  /// Called when a stage fails
  void stageDidFail(LifecycleStage stage, Object error);
}
