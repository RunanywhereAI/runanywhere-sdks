import 'dart:async';
import 'sdk_event.dart';

/// Central event bus for SDK-wide event communication
/// Similar to Swift SDK's EventBus
class EventBus {
  static final EventBus shared = EventBus._();
  EventBus._();

  final _eventController = StreamController<SDKEvent>.broadcast();

  /// Stream of all SDK events
  Stream<SDKEvent> get stream => _eventController.stream;

  /// Publish an event to all subscribers
  void publish(SDKEvent event) {
    _eventController.add(event);
  }

  /// Subscribe to a specific event type
  Stream<T> subscribe<T extends SDKEvent>() {
    return stream.where((event) => event is T).cast<T>();
  }

  /// Subscribe to all events
  StreamSubscription<SDKEvent> listen(
    void Function(SDKEvent event) onEvent, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return stream.listen(
      onEvent,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  /// Dispose the event bus
  void dispose() {
    _eventController.close();
  }
}

