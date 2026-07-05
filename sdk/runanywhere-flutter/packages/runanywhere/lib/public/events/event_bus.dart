import 'dart:async';

import 'package:runanywhere/generated/component_types.pbenum.dart';
import 'package:runanywhere/generated/sdk_events.pb.dart';
import 'package:runanywhere/generated/voice_events.pb.dart' show VoiceEvent;

/// Central event bus for generated SDKEvent proto distribution.
class EventBus {
  /// Shared instance - thread-safe singleton
  static final EventBus shared = EventBus._();

  EventBus._();

  final _allEventsController = StreamController<SDKEvent>.broadcast();

  /// Native publish hook injected by [DartBridgeEvents] during SDK init.
  ///
  /// When set, [publish] delegates to this callback first and falls back to
  /// the local stream only when it returns false. Avoids a circular import
  /// between event_bus.dart and dart_bridge_events.dart.
  Future<bool> Function(SDKEvent)? _nativePublish;

  /// Inject the native publish callback. Called once by [DartBridgeEvents]
  /// after the C++ commons bridge is available.
  void setNativePublish(Future<bool> Function(SDKEvent) fn) {
    _nativePublish = fn;
  }

  /// Public streams for subscribing to generated proto events.
  Stream<SDKEvent> get initializationEvents =>
      _where(EventCategory.EVENT_CATEGORY_INITIALIZATION);

  Stream<SDKEvent> get generationEvents =>
      _where(EventCategory.EVENT_CATEGORY_LLM);

  Stream<SDKEvent> get modelEvents =>
      _where(EventCategory.EVENT_CATEGORY_MODEL);

  Stream<SDKEvent> get ragEvents => _where(EventCategory.EVENT_CATEGORY_RAG);

  /// LLM events. Mirrors Swift `EventBus.llmEvents`. Alias of
  /// [generationEvents] under the canonical Swift name.
  Stream<SDKEvent> get llmEvents => _where(EventCategory.EVENT_CATEGORY_LLM);

  /// STT events. Mirrors Swift `EventBus.sttEvents`.
  Stream<SDKEvent> get sttEvents => _where(EventCategory.EVENT_CATEGORY_STT);

  /// TTS events. Mirrors Swift `EventBus.ttsEvents`.
  Stream<SDKEvent> get ttsEvents => _where(EventCategory.EVENT_CATEGORY_TTS);

  /// Error events. Mirrors Swift `EventBus.errorEvents`.
  Stream<SDKEvent> get errorEvents =>
      _where(EventCategory.EVENT_CATEGORY_ERROR);

  /// SDK lifecycle events. Mirrors Swift `EventBus.sdkEvents`
  /// (category SDK — distinct from [initializationEvents]).
  Stream<SDKEvent> get sdkEvents => _where(EventCategory.EVENT_CATEGORY_SDK);

  Stream<SDKEvent> get allEvents => _allEventsController.stream;

  // Typed payload streams (Swift EventBus.swift:106-136)

  /// `VoiceEvent` payloads (voice-agent pipeline events).
  Stream<VoiceEvent> get voiceEventPayloads => allEvents
      .where((e) => e.hasVoicePipeline())
      .map((e) => e.voicePipeline);

  /// `DownloadEvent` payloads (model download progress / lifecycle).
  Stream<DownloadEvent> get downloadEventPayloads =>
      allEvents.where((e) => e.hasDownload()).map((e) => e.download);

  /// `ComponentLifecycleEvent` payloads.
  Stream<ComponentLifecycleEvent> get componentLifecycleEventPayloads =>
      allEvents
          .where((e) => e.hasComponentLifecycle())
          .map((e) => e.componentLifecycle);

  /// `ModelRegistryEvent` payloads.
  Stream<ModelRegistryEvent> get modelRegistryEventPayloads =>
      allEvents.where((e) => e.hasModelRegistry()).map((e) => e.modelRegistry);

  // --- Unified model-lifecycle stream (Swift EventBus+ModelLifecycle.swift) -

  /// Unified model load/unload stream across all native signal channels
  /// (component-lifecycle, model events, LLM generation events). Mirrors
  /// Swift `EventBus.modelLifecycle`.
  Stream<ModelLifecycleChange> get modelLifecycle => allEvents
      .map(modelLifecycleChange)
      .where((change) => change != null)
      .cast<ModelLifecycleChange>();

  /// [modelLifecycle] filtered to load completions.
  Stream<ModelLifecycleChange> get modelLoaded =>
      modelLifecycle.where((c) => c.kind == ModelLifecycleChangeKind.loaded);

  /// [modelLifecycle] filtered to unloads.
  Stream<ModelLifecycleChange> get modelUnloaded =>
      modelLifecycle.where((c) => c.kind == ModelLifecycleChangeKind.unloaded);

  /// Subscribe to events filtered by [category]. Mirrors Swift's
  /// `EventBus.events(for:)` API surface — useful when callers want
  /// dynamic category selection instead of using a named getter.
  Stream<SDKEvent> onCategory(EventCategory category) => _where(category);

  /// Publish [event] through the C++ commons event pipeline first; fall back
  /// to the local broadcast stream only when native publish is unavailable.
  ///
  /// Mirrors Swift's `if !CppBridge.Events.publishSDKEvent(event) { subject.send(event) }`.
  Future<void> publish(SDKEvent event) async {
    if (_allEventsController.isClosed) return;
    final nativePublish = _nativePublish;
    if (nativePublish != null) {
      final published = await nativePublish(event);
      if (published) return;
    }
    _allEventsController.add(event);
  }

  /// Fan-out an event that has already been delivered by the native layer.
  ///
  /// Used exclusively by [DartBridgeEvents.emit] so that events received from
  /// C++ commons are broadcast to Dart subscribers without triggering a
  /// redundant [rac_sdk_event_publish_proto] round-trip back to native.
  void addFromNative(SDKEvent event) {
    if (_allEventsController.isClosed) return;
    _allEventsController.add(event);
  }

  /// Dispose all controllers
  Future<void> dispose() async {
    await _allEventsController.close();
  }

  Stream<SDKEvent> _where(EventCategory category) =>
      _allEventsController.stream.where((event) => event.category == category);
}

/// Whether the model finished loading or was unloaded.
enum ModelLifecycleChangeKind { loaded, unloaded }

/// One model load/unload transition, decoded from the raw event bus.
/// Mirrors Swift `RAModelLifecycleChange` (EventBus+ModelLifecycle.swift).
class ModelLifecycleChange {
  const ModelLifecycleChange({
    required this.kind,
    required this.modelId,
    required this.component,
    required this.event,
  });

  final ModelLifecycleChangeKind kind;

  /// Registry id of the affected model. May be empty when the native channel
  /// did not carry one (rare; treat as "current model").
  final String modelId;

  /// SDK component slot the change applies to (.llm, .stt, .tts, ...).
  final SDKComponent component;

  /// The underlying raw event, for consumers that need extra payload fields.
  final SDKEvent event;
}

/// Decode a raw SDK event into a lifecycle change, or null when the event is
/// not a load/unload transition. Mirrors Swift
/// `EventBus.modelLifecycleChange(from:)`.
ModelLifecycleChange? modelLifecycleChange(SDKEvent event) {
  // Channel 1: component-lifecycle (the canonical loadModel path).
  if (event.category == EventCategory.EVENT_CATEGORY_COMPONENT &&
      event.hasComponentLifecycle()) {
    final lifecycle = event.componentLifecycle;
    switch (lifecycle.currentState) {
      case ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY:
        return ModelLifecycleChange(
          kind: ModelLifecycleChangeKind.loaded,
          modelId: lifecycle.modelId,
          component: lifecycle.component,
          event: event,
        );
      case ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_NOT_LOADED:
      case ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_UNLOADING:
      case ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_SHUTDOWN:
      case ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_DELETING:
        return ModelLifecycleChange(
          kind: ModelLifecycleChangeKind.unloaded,
          modelId: lifecycle.modelId,
          component: lifecycle.component,
          event: event,
        );
      default:
        return null;
    }
  }

  // Channels 2 + 3: model events and LLM generation events.
  final modelId = event.model.modelId.isNotEmpty
      ? event.model.modelId
      : event.generation.modelId;

  final loaded = event.model.kind ==
          ModelEventKind.MODEL_EVENT_KIND_LOAD_COMPLETED ||
      event.generation.kind ==
          GenerationEventKind.GENERATION_EVENT_KIND_MODEL_LOADED;
  if (loaded) {
    return ModelLifecycleChange(
      kind: ModelLifecycleChangeKind.loaded,
      modelId: modelId,
      component: event.component,
      event: event,
    );
  }
  final unloaded = event.model.kind ==
          ModelEventKind.MODEL_EVENT_KIND_UNLOAD_COMPLETED ||
      event.generation.kind ==
          GenerationEventKind.GENERATION_EVENT_KIND_MODEL_UNLOADED;
  if (unloaded) {
    return ModelLifecycleChange(
      kind: ModelLifecycleChangeKind.unloaded,
      modelId: modelId,
      component: event.component,
      event: event,
    );
  }
  return null;
}
