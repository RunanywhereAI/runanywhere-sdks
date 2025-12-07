/// Lifecycle stages for progress tracking
/// Matches iOS LifecycleStage from Core/Protocols/Memory/MemoryManager.swift
enum LifecycleStage implements Comparable<LifecycleStage> {
  discovery(0, 'Discovery', 'Discovering model...'),
  download(1, 'Download', 'Downloading model...'),
  extraction(2, 'Extraction', 'Extracting files...'),
  validation(3, 'Validation', 'Validating model...'),
  initialization(4, 'Initialization', 'Initializing model...'),
  loading(5, 'Loading', 'Loading model...'),
  ready(6, 'Ready', 'Model ready');

  final int sortOrder;
  final String displayName;
  final String defaultMessage;

  const LifecycleStage(this.sortOrder, this.displayName, this.defaultMessage);

  @override
  int compareTo(LifecycleStage other) => sortOrder.compareTo(other.sortOrder);

  bool operator <(LifecycleStage other) => sortOrder < other.sortOrder;
  bool operator <=(LifecycleStage other) => sortOrder <= other.sortOrder;
  bool operator >(LifecycleStage other) => sortOrder > other.sortOrder;
  bool operator >=(LifecycleStage other) => sortOrder >= other.sortOrder;
}

/// Overall progress information
/// Matches iOS OverallProgress from Core/Protocols/Memory/MemoryManager.swift
class OverallProgress {
  final double percentage;
  final LifecycleStage? currentStage;
  final double stageProgress;
  final String message;
  final Duration? estimatedTimeRemaining;

  const OverallProgress({
    required this.percentage,
    this.currentStage,
    this.stageProgress = 0,
    this.message = '',
    this.estimatedTimeRemaining,
  });

  /// Create progress at a specific stage
  factory OverallProgress.atStage(
    LifecycleStage stage, {
    double progress = 0,
    String? message,
    Duration? estimatedTimeRemaining,
  }) {
    // Calculate overall percentage based on stage position
    final stageCount = LifecycleStage.values.length;
    final basePercentage = (stage.sortOrder / stageCount) * 100;
    final stageContribution = (progress / stageCount);
    final overallPercentage = basePercentage + stageContribution;

    return OverallProgress(
      percentage: overallPercentage.clamp(0, 100),
      currentStage: stage,
      stageProgress: progress,
      message: message ?? stage.defaultMessage,
      estimatedTimeRemaining: estimatedTimeRemaining,
    );
  }

  @override
  String toString() =>
      'OverallProgress(${percentage.toStringAsFixed(1)}%, stage: $currentStage)';
}
