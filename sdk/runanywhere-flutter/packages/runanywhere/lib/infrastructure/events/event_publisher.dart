//
//  event_publisher.dart
//  RunAnywhere SDK
//
//  Simple event router. Call track(event) and it handles the rest.
//
//  Corresponds to iOS SDK's EventPublisher.swift
//

import 'dart:async';

import 'package:runanywhere/infrastructure/analytics/analytics_queue_manager.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';

/// Simple event router for the SDK.
///
/// Mirrors iOS `EventPublisher` from RunAnywhere SDK.
/// Just call `track(event)` - the router decides where to send it
/// based on the event's `destination` property.
///
/// Usage:
/// ```dart
/// EventPublisher.shared.track(LLMEvent.generationCompleted(...));
/// ```
class EventPublisher {
  // MARK: - Singleton

  /// Shared instance
  static final EventPublisher shared = EventPublisher._();

  EventPublisher._({EventBus? eventBus})
      : _eventBus = eventBus ?? EventBus.shared;

  // MARK: - Dependencies

  final EventBus _eventBus;

  /// Analytics queue manager (set during SDK initialization).
  /// When null, analytics events are silently dropped.
  AnalyticsQueueManager? _analyticsQueue;

  // MARK: - Initialization

  /// Initialize with analytics queue (call during SDK startup).
  void initialize({required AnalyticsQueueManager analyticsQueue}) {
    _analyticsQueue = analyticsQueue;
  }

  // MARK: - Track

  /// Track an event. Routes automatically based on event.destination.
  void track(SDKEvent event) {
    final destination = event.destination;

    // Route to EventBus (public)
    if (destination != EventDestination.analyticsOnly) {
      _eventBus.publish(event);
    }

    // Route to Analytics (telemetry)
    if (destination != EventDestination.publicOnly) {
      _analyticsQueue?.enqueue(event);
    }
  }

  /// Track an event asynchronously (for use in async contexts).
  Future<void> trackAsync(SDKEvent event) async {
    final destination = event.destination;

    // Route to EventBus (public)
    if (destination != EventDestination.analyticsOnly) {
      _eventBus.publish(event);
    }

    // Route to Analytics (telemetry)
    if (destination != EventDestination.publicOnly) {
      await _analyticsQueue?.enqueueAsync(event);
    }
  }
}
