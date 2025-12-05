import 'dart:async';

import 'analytics_event.dart';
import 'analytics_metrics.dart';
import 'session_metadata.dart';

/// Base protocol for all analytics services in the SDK
///
/// Corresponds to iOS SDK's AnalyticsService protocol in UnifiedAnalytics.swift
///
/// Note: In Dart, we use abstract classes instead of Swift protocols with
/// associated types. Implementations can use generics if needed for type safety.
abstract class AnalyticsService<TEvent extends AnalyticsEvent,
    TMetrics extends AnalyticsMetrics> {
  // Event tracking

  /// Track a single event
  Future<void> track(TEvent event);

  /// Track multiple events in a batch
  Future<void> trackBatch(List<TEvent> events);

  // Metrics

  /// Get current metrics
  Future<TMetrics> getMetrics();

  /// Clear metrics older than the specified date
  Future<void> clearMetrics({required DateTime olderThan});

  // Session management

  /// Start a new session with the given metadata
  /// Returns the session ID
  Future<String> startSession(SessionMetadata metadata);

  /// End a session by its ID
  Future<void> endSession(String sessionId);

  // Health

  /// Check if the analytics service is healthy
  Future<bool> isHealthy();
}

/// Mock implementation of AnalyticsService for testing and development
///
/// TODO: Replace with actual implementation when analytics backend is ready
class MockAnalyticsService
    implements AnalyticsService<AnalyticsEvent, AnalyticsMetrics> {
  final List<AnalyticsEvent> _events = [];
  SimpleAnalyticsMetrics _metrics = SimpleAnalyticsMetrics.initial();
  final Map<String, SessionMetadata> _sessions = {};

  @override
  Future<void> track(AnalyticsEvent event) async {
    _events.add(event);
    _metrics = _metrics.copyWith(
      totalEvents: _metrics.totalEvents + 1,
      lastEventTime: DateTime.now(),
    );
  }

  @override
  Future<void> trackBatch(List<AnalyticsEvent> events) async {
    _events.addAll(events);
    _metrics = _metrics.copyWith(
      totalEvents: _metrics.totalEvents + events.length,
      lastEventTime: DateTime.now(),
    );
  }

  @override
  Future<AnalyticsMetrics> getMetrics() async => _metrics;

  @override
  Future<void> clearMetrics({required DateTime olderThan}) async {
    _events.removeWhere((event) => event.timestamp.isBefore(olderThan));
    _metrics = SimpleAnalyticsMetrics(
      totalEvents: _events.length,
      startTime: _metrics.startTime,
      lastEventTime: _events.isNotEmpty ? _events.last.timestamp : null,
    );
  }

  @override
  Future<String> startSession(SessionMetadata metadata) async {
    _sessions[metadata.id] = metadata;
    return metadata.id;
  }

  @override
  Future<void> endSession(String sessionId) async {
    _sessions.remove(sessionId);
  }

  @override
  Future<bool> isHealthy() async => true;

  /// Get all tracked events (for testing)
  List<AnalyticsEvent> get events => List.unmodifiable(_events);

  /// Get all active sessions (for testing)
  Map<String, SessionMetadata> get sessions => Map.unmodifiable(_sessions);
}
