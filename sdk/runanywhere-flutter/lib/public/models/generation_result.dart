import 'performance_metrics.dart';

/// Generation Result
/// Similar to Swift SDK's GenerationResult
class GenerationResult {
  final String text;
  final int tokensUsed;
  final int latencyMs;
  final PerformanceMetrics performanceMetrics;
  final double savedAmount;
  final String? modelId;
  final String? executionTarget;

  GenerationResult({
    required this.text,
    required this.tokensUsed,
    required this.latencyMs,
    required this.performanceMetrics,
    this.savedAmount = 0.0,
    this.modelId,
    this.executionTarget,
  });
}

