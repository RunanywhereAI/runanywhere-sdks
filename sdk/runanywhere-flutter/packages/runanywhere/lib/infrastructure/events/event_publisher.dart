/// Event Publisher
///
/// Simple event router. Call track(event) and it handles the rest.
/// Corresponds to iOS SDK's EventPublisher.swift
library event_publisher;

import 'dart:async';

import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';

/// Event destination options
enum EventDestination {
  /// Send to public EventBus only
  publicOnly,

  /// Send to analytics/telemetry only
  analyticsOnly,

  /// Send to both public EventBus and analytics
  both,
}

/// Simple event router for the SDK.
///
/// Mirrors iOS `EventPublisher` from RunAnywhere SDK.
/// Just call `track(event)` - the router decides where to send it.
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

  // MARK: - Track

  /// Track an event. Routes automatically based on event.destination.
  void track(SDKEvent event) {
    final destination = event.destination;

    // Route to EventBus (public)
    if (destination != EventDestination.analyticsOnly) {
      _eventBus.publish(event);
    }

    // Route to Analytics (telemetry) - handled via FFI/DartBridge
    if (destination != EventDestination.publicOnly) {
      // TODO: Route to DartBridge.Telemetry
    }
  }

  /// Track an event asynchronously (for use in async contexts).
  Future<void> trackAsync(SDKEvent event) async {
    track(event);
  }
}
