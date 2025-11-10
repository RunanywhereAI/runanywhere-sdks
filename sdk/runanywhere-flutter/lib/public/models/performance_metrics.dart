/// Performance Metrics
/// Similar to Swift SDK's PerformanceMetrics
class PerformanceMetrics {
  final double tokensPerSecond;
  final int timeToFirstTokenMs;
  final int inferenceTimeMs;
  final int? peakMemoryUsage;

  PerformanceMetrics({
    required this.tokensPerSecond,
    required this.timeToFirstTokenMs,
    required this.inferenceTimeMs,
    this.peakMemoryUsage,
  });
}

