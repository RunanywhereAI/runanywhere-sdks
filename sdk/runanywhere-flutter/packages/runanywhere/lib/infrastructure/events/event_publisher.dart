/// Event Publisher
///
/// Routes events to public EventBus and/or C++ telemetry based on destination.
/// Mirrors iOS SDK's event routing pattern where C++ handles telemetry.
library event_publisher;

import 'dart:async';

import 'package:runanywhere/native/dart_bridge_telemetry.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';

/// Routes SDK events to appropriate destinations.
///
/// Mirrors iOS pattern where:
/// - Public events go to EventBus (Dart streams)
/// - Analytics events go to C++ telemetry via DartBridge FFI
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
  ///
  /// - all: To both EventBus and C++ telemetry (default)
  /// - publicOnly: Only to EventBus (app developers can subscribe)
  /// - analyticsOnly: Only to C++ telemetry (backend)
  void track(SDKEvent event) {
    final destination = event.destination;

    // Route to EventBus (public) - app developers subscribe here
    if (destination == EventDestination.all ||
        destination == EventDestination.publicOnly) {
      _eventBus.publish(event);
    }

    // Route to C++ telemetry via DartBridge FFI
    if (destination == EventDestination.all ||
        destination == EventDestination.analyticsOnly) {
      _trackToTelemetry(event);
    }
  }

  /// Track an event asynchronously (for use in async contexts).
  Future<void> trackAsync(SDKEvent event) async {
    track(event);
  }

  // MARK: - Internal

  /// Route event to C++ telemetry system via DartBridge.
  /// C++ handles JSON serialization, batching, and HTTP transport.
  void _trackToTelemetry(SDKEvent event) {
    // Map event to C++ telemetry call
    // The DartBridgeTelemetry provides typed emit methods matching iOS pattern
    switch (event.category) {
      case EventCategory.model:
        _trackModelEvent(event);
        break;
      case EventCategory.llm:
        _trackLLMEvent(event);
        break;
      case EventCategory.stt:
        _trackSTTEvent(event);
        break;
      case EventCategory.tts:
        _trackTTSEvent(event);
        break;
      case EventCategory.sdk:
        _trackSDKEvent(event);
        break;
      case EventCategory.storage:
        _trackStorageEvent(event);
        break;
      case EventCategory.device:
        _trackDeviceEvent(event);
        break;
      case EventCategory.voice:
        _trackVoiceEvent(event);
        break;
      case EventCategory.vad:
        _trackVADEvent(event);
        break;
      case EventCategory.network:
      case EventCategory.error:
        // These are logged but not sent to telemetry
        break;
    }
  }

  void _trackModelEvent(SDKEvent event) {
    final props = event.properties;
    final modelId = props['modelId'] ?? '';
    final modelName = props['modelName'] ?? '';
    final framework = props['framework'] ?? '';

    switch (event.type) {
      case 'model.download.started':
        unawaited(DartBridgeTelemetry.instance.emitDownloadStarted(
          modelId: modelId,
          modelName: modelName,
          modelSize: int.tryParse(props['modelSize'] ?? '0') ?? 0,
          framework: framework,
        ));
        break;
      case 'model.download.completed':
        unawaited(DartBridgeTelemetry.instance.emitDownloadCompleted(
          modelId: modelId,
          modelName: modelName,
          modelSize: int.tryParse(props['modelSize'] ?? '0') ?? 0,
          framework: framework,
          durationMs: int.tryParse(props['durationMs'] ?? '0') ?? 0,
        ));
        break;
      case 'model.download.failed':
        unawaited(DartBridgeTelemetry.instance.emitDownloadFailed(
          modelId: modelId,
          modelName: modelName,
          error: props['error'] ?? 'Unknown error',
          framework: framework,
        ));
        break;
      case 'model.extraction.started':
        unawaited(DartBridgeTelemetry.instance.emitExtractionStarted(
          modelId: modelId,
          modelName: modelName,
          framework: framework,
        ));
        break;
      case 'model.extraction.completed':
        unawaited(DartBridgeTelemetry.instance.emitExtractionCompleted(
          modelId: modelId,
          modelName: modelName,
          framework: framework,
          durationMs: int.tryParse(props['durationMs'] ?? '0') ?? 0,
        ));
        break;
      case 'model.loaded':
        unawaited(DartBridgeTelemetry.instance.emitModelLoaded(
          modelId: modelId,
          modelName: modelName,
          framework: framework,
          durationMs: int.tryParse(props['durationMs'] ?? '0') ?? 0,
        ));
        break;
    }
  }

  void _trackLLMEvent(SDKEvent event) {
    final props = event.properties;
    final modelId = props['modelId'] ?? '';
    final modelName = props['modelName'] ?? '';

    switch (event.type) {
      case 'llm.generation.completed':
        unawaited(DartBridgeTelemetry.instance.emitInferenceCompleted(
          modelId: modelId,
          modelName: modelName,
          modality: 'llm',
          durationMs: int.tryParse(props['durationMs'] ?? '0') ?? 0,
          tokensGenerated: int.tryParse(props['tokensGenerated'] ?? ''),
          tokensPerSecond: double.tryParse(props['tokensPerSecond'] ?? ''),
        ));
        break;
    }
  }

  void _trackSTTEvent(SDKEvent event) {
    final props = event.properties;
    final modelId = props['modelId'] ?? '';
    final modelName = props['modelName'] ?? '';

    switch (event.type) {
      case 'stt.transcription.completed':
        unawaited(DartBridgeTelemetry.instance.emitInferenceCompleted(
          modelId: modelId,
          modelName: modelName,
          modality: 'stt',
          durationMs: int.tryParse(props['durationMs'] ?? '0') ?? 0,
        ));
        break;
    }
  }

  void _trackTTSEvent(SDKEvent event) {
    final props = event.properties;
    final modelId = props['modelId'] ?? '';
    final modelName = props['modelName'] ?? '';

    switch (event.type) {
      case 'tts.synthesis.completed':
        unawaited(DartBridgeTelemetry.instance.emitInferenceCompleted(
          modelId: modelId,
          modelName: modelName,
          modality: 'tts',
          durationMs: int.tryParse(props['durationMs'] ?? '0') ?? 0,
        ));
        break;
    }
  }

  void _trackSDKEvent(SDKEvent event) {
    final props = event.properties;

    switch (event.type) {
      case 'sdk.initialized':
        unawaited(DartBridgeTelemetry.instance.emitSDKInitialized(
          durationMs: int.tryParse(props['durationMs'] ?? '0') ?? 0,
          environment: props['environment'] ?? 'production',
        ));
        break;
    }
  }

  void _trackStorageEvent(SDKEvent event) {
    final props = event.properties;

    switch (event.type) {
      case 'storage.cache.cleared':
        unawaited(DartBridgeTelemetry.instance.emitStorageCacheCleared(
          freedBytes: int.tryParse(props['freedBytes'] ?? '0') ?? 0,
        ));
        break;
      case 'storage.cache.clear_failed':
        unawaited(DartBridgeTelemetry.instance.emitStorageCacheClearFailed(
          error: props['error'] ?? 'Unknown error',
        ));
        break;
      case 'storage.temp.cleaned':
        unawaited(DartBridgeTelemetry.instance.emitStorageTempCleaned(
          freedBytes: int.tryParse(props['freedBytes'] ?? '0') ?? 0,
        ));
        break;
    }
  }

  void _trackDeviceEvent(SDKEvent event) {
    final props = event.properties;

    switch (event.type) {
      case 'device.registered':
        unawaited(DartBridgeTelemetry.instance.emitDeviceRegistered(
          deviceId: props['deviceId'] ?? '',
        ));
        break;
      case 'device.registration_failed':
        unawaited(DartBridgeTelemetry.instance.emitDeviceRegistrationFailed(
          error: props['error'] ?? 'Unknown error',
        ));
        break;
    }
  }

  void _trackVoiceEvent(SDKEvent event) {
    final props = event.properties;

    switch (event.type) {
      case 'voice.turn.started':
        unawaited(DartBridgeTelemetry.instance.emitVoiceAgentTurnStarted());
        break;
      case 'voice.turn.completed':
        unawaited(DartBridgeTelemetry.instance.emitVoiceAgentTurnCompleted(
          durationMs: int.tryParse(props['durationMs'] ?? '0') ?? 0,
        ));
        break;
      case 'voice.turn.failed':
        unawaited(DartBridgeTelemetry.instance.emitVoiceAgentTurnFailed(
          error: props['error'] ?? 'Unknown error',
        ));
        break;
      case 'voice.stt.state_changed':
        unawaited(DartBridgeTelemetry.instance.emitVoiceAgentSttStateChanged(
          state: props['state'] ?? 'unknown',
        ));
        break;
      case 'voice.llm.state_changed':
        unawaited(DartBridgeTelemetry.instance.emitVoiceAgentLlmStateChanged(
          state: props['state'] ?? 'unknown',
        ));
        break;
      case 'voice.tts.state_changed':
        unawaited(DartBridgeTelemetry.instance.emitVoiceAgentTtsStateChanged(
          state: props['state'] ?? 'unknown',
        ));
        break;
      case 'voice.all_ready':
        unawaited(DartBridgeTelemetry.instance.emitVoiceAgentAllReady());
        break;
    }
  }

  void _trackVADEvent(SDKEvent event) {
    // VAD events are part of voice pipeline, tracked as voice events
    // Individual VAD detections are typically not telemetered (too frequent)
    // Only aggregate stats would be tracked if needed
    switch (event.type) {
      case 'vad.speech_started':
      case 'vad.speech_ended':
        // These are high-frequency events, logged locally but not sent to telemetry
        // to avoid overwhelming the backend
        break;
    }
  }
}
