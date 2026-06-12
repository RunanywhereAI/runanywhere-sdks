import 'dart:async';

import 'package:runanywhere/generated/component_types.pbenum.dart';
import 'package:runanywhere/generated/sdk_events.pb.dart';

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

  Stream<SDKEvent> get voiceEvents =>
      _where(EventCategory.EVENT_CATEGORY_VOICE_AGENT);

  Stream<SDKEvent> get storageEvents =>
      _where(EventCategory.EVENT_CATEGORY_STORAGE);

  Stream<SDKEvent> get deviceEvents =>
      _where(EventCategory.EVENT_CATEGORY_DEVICE);

  Stream<SDKEvent> get ragEvents => _where(EventCategory.EVENT_CATEGORY_RAG);

  Stream<SDKEvent> get allEvents => _allEventsController.stream;

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
