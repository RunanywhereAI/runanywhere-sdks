/// Base protocol for analytics metrics
///
/// Corresponds to iOS SDK's AnalyticsMetrics protocol in UnifiedAnalytics.swift
abstract class AnalyticsMetrics {
  /// Total number of events tracked
  int get totalEvents;

  /// When tracking started
  DateTime get startTime;

  /// When the last event was tracked (if any)
  DateTime? get lastEventTime;
}

/// Simple concrete implementation of AnalyticsMetrics
class SimpleAnalyticsMetrics implements AnalyticsMetrics {
  @override
  final int totalEvents;

  @override
  final DateTime startTime;

  @override
  final DateTime? lastEventTime;

  const SimpleAnalyticsMetrics({
    required this.totalEvents,
    required this.startTime,
    this.lastEventTime,
  });

  /// Create initial empty metrics
  factory SimpleAnalyticsMetrics.initial() => SimpleAnalyticsMetrics(
        totalEvents: 0,
        startTime: DateTime.now(),
        lastEventTime: null,
      );

  /// Create a copy with updated values
  SimpleAnalyticsMetrics copyWith({
    int? totalEvents,
    DateTime? startTime,
    DateTime? lastEventTime,
  }) {
    return SimpleAnalyticsMetrics(
      totalEvents: totalEvents ?? this.totalEvents,
      startTime: startTime ?? this.startTime,
      lastEventTime: lastEventTime ?? this.lastEventTime,
    );
  }
}
