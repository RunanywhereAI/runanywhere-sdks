import 'model_lifecycle_protocol.dart';

/// Extended observer protocol for progress updates
/// Matches iOS ModelLifecycleProgressObserver from Core/Protocols/Lifecycle/ModelLifecycleProgressObserver.swift
abstract class ModelLifecycleProgressObserver extends ModelLifecycleObserver {
  /// Called when model loading/unloading progress is updated
  void modelDidUpdateProgress(ModelLifecycleProgress progress);
}

/// Progress information for lifecycle operations
class ModelLifecycleProgress {
  final ModelLifecycleState currentState;
  final double percentage;
  final Duration? estimatedTimeRemaining;
  final String? message;

  ModelLifecycleProgress({
    required this.currentState,
    required double percentage,
    this.estimatedTimeRemaining,
    this.message,
  }) : percentage = percentage.clamp(0.0, 100.0);

  @override
  String toString() =>
      'ModelLifecycleProgress(state: $currentState, ${percentage.toStringAsFixed(1)}%)';
}
