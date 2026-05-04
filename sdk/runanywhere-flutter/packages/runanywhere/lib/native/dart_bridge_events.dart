// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/sdk_events.pb.dart' as event_pb;
import 'package:runanywhere/native/ffi_types.dart';

/// Native bridge for the stable SDKEvent proto-byte stream.
class DartBridgeEvents {
  DartBridgeEvents._();

  static final _logger = SDKLogger('DartBridge.Events');
  static final DartBridgeEvents instance = DartBridgeEvents._();

  static final _eventController =
      StreamController<event_pb.SDKEvent>.broadcast();

  static bool _isRegistered = false;
  static int _subscriptionId = 0;

  static Stream<event_pb.SDKEvent> get eventStream => _eventController.stream;

  /// Subscribe to the commons process-wide SDKEvent stream.
  static void register() {
    if (_isRegistered) return;

    try {
      final subscribe = RacNative.bindings.rac_sdk_event_subscribe;
      if (subscribe == null) {
        _logger.warning('SDKEvent proto subscription ABI is unavailable');
        _isRegistered = true;
        return;
      }

      final callback = Pointer.fromFunction<RacSdkEventCallbackNative>(
        _sdkEventCallback,
      );
      _subscriptionId = subscribe(callback, nullptr);
      _isRegistered = true;
      _logger.debug('SDKEvent proto callback registered');
    } catch (e) {
      _logger.warning('SDKEvent proto registration failed: $e');
      _isRegistered = true;
    }
  }

  static void unregister() {
    if (!_isRegistered) return;

    try {
      final unsubscribe = RacNative.bindings.rac_sdk_event_unsubscribe;
      if (unsubscribe != null && _subscriptionId != 0) {
        unsubscribe(_subscriptionId);
      }
    } catch (e) {
      _logger.debug('SDKEvent proto unregistration failed: $e');
    } finally {
      _subscriptionId = 0;
      _isRegistered = false;
    }
  }

  StreamSubscription<event_pb.SDKEvent> subscribe(
    void Function(event_pb.SDKEvent event) onEvent, {
    bool Function(event_pb.SDKEvent event)? where,
  }) {
    final stream = where == null ? eventStream : eventStream.where(where);
    return stream.listen(onEvent);
  }

  void emit(event_pb.SDKEvent event) {
    _eventController.add(event);
  }

  Future<bool> publish(event_pb.SDKEvent event) async {
    final publish = RacNative.bindings.rac_sdk_event_publish_proto;
    if (publish == null) return false;
    return _withProtoBytes(event, (bytes, size) {
      return publish(bytes, size) == RacResultCode.success;
    });
  }

  Future<event_pb.SDKEvent?> poll() async {
    final poll = RacNative.bindings.rac_sdk_event_poll;
    if (poll == null) return null;

    final out = calloc<RacProtoBuffer>();
    final bindings = RacNative.bindings;
    try {
      bindings.rac_proto_buffer_init(out);
      final code = poll(out);
      if (code != RacResultCode.success || out.ref.data == nullptr) {
        return null;
      }
      final bytes =
          out.ref.data.asTypedList(out.ref.size).toList(growable: false);
      return event_pb.SDKEvent.fromBuffer(bytes);
    } catch (e) {
      _logger.debug('rac_sdk_event_poll error: $e');
      return null;
    } finally {
      bindings.rac_proto_buffer_free(out);
      calloc.free(out);
    }
  }

  Future<bool> publishFailure({
    required int errorCode,
    required String message,
    required String component,
    required String operation,
    bool recoverable = false,
  }) async {
    final publishFailure = RacNative.bindings.rac_sdk_event_publish_failure;
    if (publishFailure == null) return false;

    final messagePtr = message.toNativeUtf8();
    final componentPtr = component.toNativeUtf8();
    final operationPtr = operation.toNativeUtf8();
    try {
      return publishFailure(
            errorCode,
            messagePtr,
            componentPtr,
            operationPtr,
            recoverable ? 1 : 0,
          ) ==
          RacResultCode.success;
    } finally {
      calloc.free(messagePtr);
      calloc.free(componentPtr);
      calloc.free(operationPtr);
    }
  }

  bool _withProtoBytes(
    event_pb.SDKEvent event,
    bool Function(Pointer<Uint8> bytes, int size) body,
  ) {
    final bytes = event.writeToBuffer();
    final ptr = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    try {
      if (bytes.isNotEmpty) {
        ptr.asTypedList(bytes.length).setAll(0, bytes);
      }
      return body(ptr, bytes.length);
    } finally {
      calloc.free(ptr);
    }
  }
}

void _sdkEventCallback(
  Pointer<Uint8> protoBytes,
  int protoSize,
  Pointer<Void> userData,
) {
  if (protoBytes == nullptr) return;

  try {
    final bytes = protoBytes.asTypedList(protoSize).toList(growable: false);
    DartBridgeEvents.instance.emit(event_pb.SDKEvent.fromBuffer(bytes));
  } catch (e) {
    SDKLogger('DartBridge.Events').warning('Failed to decode SDKEvent: $e');
  }
}
