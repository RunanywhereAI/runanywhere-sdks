// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// Events bridge for C++ event routing.
/// Matches Swift's `CppBridge+Events.swift`.
class DartBridgeEvents {
  DartBridgeEvents._();

  static final _logger = SDKLogger('DartBridge.Events');
  static final DartBridgeEvents instance = DartBridgeEvents._();

  static bool _isRegistered = false;

  /// Event stream controller for SDK events
  static final _eventController = StreamController<SDKEvent>.broadcast();

  /// Stream of SDK events from C++
  static Stream<SDKEvent> get eventStream => _eventController.stream;

  /// Register events callback with C++
  static void register() {
    if (_isRegistered) return;

    try {
      final lib = PlatformLoader.load();

      // Look up event registration function
      final registerCallback = lib.lookupFunction<
          Int32 Function(Pointer<NativeFunction<Void Function(Pointer<Utf8>, Pointer<Void>)>>),
          int Function(Pointer<NativeFunction<Void Function(Pointer<Utf8>, Pointer<Void>)>>)>(
        'rac_events_register_callback',
      );

      // Register the callback
      final callbackPtr = Pointer.fromFunction<Void Function(Pointer<Utf8>, Pointer<Void>)>(
        _eventsCallback,
      );

      final result = registerCallback(callbackPtr);
      if (result != RacResultCode.success) {
        _logger.warning('Failed to register events callback', metadata: {'code': result});
      }

      _isRegistered = true;
      _logger.debug('Events callback registered');
    } catch (e) {
      _logger.debug('Events registration not available: $e');
      _isRegistered = true; // Mark as registered to avoid retry
    }
  }

  /// Unregister events callback
  static void unregister() {
    if (!_isRegistered) return;

    try {
      final lib = PlatformLoader.load();
      final unregisterCallback = lib.lookupFunction<
          Void Function(),
          void Function()>('rac_events_unregister_callback');

      unregisterCallback();
      _isRegistered = false;
      _logger.debug('Events callback unregistered');
    } catch (e) {
      _logger.debug('Events unregistration not available: $e');
    }
  }

  /// Emit an event to subscribers
  void emit(SDKEvent event) {
    _eventController.add(event);
  }

  /// Subscribe to events of a specific type
  StreamSubscription<SDKEvent> subscribe(
    void Function(SDKEvent event) onEvent, {
    String? eventType,
  }) {
    if (eventType != null) {
      return eventStream
          .where((e) => e.type == eventType)
          .listen(onEvent);
    }
    return eventStream.listen(onEvent);
  }
}

/// Events callback from C++
void _eventsCallback(Pointer<Utf8> eventJson, Pointer<Void> userData) {
  if (eventJson == nullptr) return;

  try {
    final jsonString = eventJson.toDartString();
    final data = jsonDecode(jsonString) as Map<String, dynamic>;

    final event = SDKEvent(
      type: data['type'] as String? ?? 'unknown',
      data: data['data'] as Map<String, dynamic>? ?? {},
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        data['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );

    DartBridgeEvents.instance.emit(event);
  } catch (e) {
    SDKLogger('DartBridge.Events').warning('Failed to parse event: $e');
  }
}

/// SDK event from C++ or Dart
class SDKEvent {
  final String type;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  SDKEvent({
    required this.type,
    required this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'type': type,
        'data': data,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };

  @override
  String toString() => 'SDKEvent($type, $data)';
}
