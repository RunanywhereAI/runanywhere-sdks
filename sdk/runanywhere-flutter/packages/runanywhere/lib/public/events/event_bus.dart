import 'dart:async';

import 'package:runanywhere/generated/component_types.pbenum.dart';
import 'package:runanywhere/generated/sdk_events.pb.dart';

/// Central event bus for generated SDKEvent proto distribution.
class EventBus {
  /// Shared instance - thread-safe singleton
  static final EventBus shared = EventBus._();

  EventBus._();

  final _allEventsController = StreamController<SDKEvent>.broadcast();

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

  /// Generic event publisher - dispatches to appropriate stream
  void publish(SDKEvent event) {
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
