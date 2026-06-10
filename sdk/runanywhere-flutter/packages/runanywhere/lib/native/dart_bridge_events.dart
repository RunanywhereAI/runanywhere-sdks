// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/sdk_events.pb.dart' as event_pb;
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/types/basic_types.dart';
import 'package:runanywhere/public/events/event_bus.dart';

/// Native bridge for the stable SDKEvent proto-byte stream.
class DartBridgeEvents {
  DartBridgeEvents._();

  static final _logger = SDKLogger('DartBridge.Events');
  static final DartBridgeEvents instance = DartBridgeEvents._();

  static bool _isRegistered = false;
  static int _subscriptionId = 0;
  static NativeCallable<RacSdkEventCallbackNative>? _eventCallback;

  /// Thin alias for [EventBus.shared.allEvents] — single canonical bus.
  static Stream<event_pb.SDKEvent> get eventStream => EventBus.shared.allEvents;

  /// Subscribe to the commons process-wide SDKEvent stream.
  ///
  /// Also wires the native publish hook into [EventBus] so that
  /// [EventBus.publish] routes through [rac_sdk_event_publish_proto] first,
  /// mirroring Swift's `CppBridge.Events.publishSDKEvent`.
  static void register() {
    if (_isRegistered) return;

    EventBus.shared.setNativePublish(instance.publish);

    NativeCallable<RacSdkEventCallbackNative>? callback;
    try {
      final subscribe = RacNative.bindings.rac_sdk_event_subscribe;
      if (subscribe == null) {
        _logger.warning('SDKEvent proto subscription ABI is unavailable');
        _isRegistered = true;
        return;
      }

      callback = NativeCallable<RacSdkEventCallbackNative>.listener(
        _sdkEventCallback,
      );
      final subscriptionId = subscribe(callback.nativeFunction, nullptr);
      if (subscriptionId == 0) {
        callback.close();
        _logger.warning('SDKEvent proto subscription returned no handle');
        _isRegistered = true;
        return;
      }

      _eventCallback = callback;
      callback = null;
      _subscriptionId = subscriptionId;
      _isRegistered = true;
      _logger.debug('SDKEvent proto callback registered');
    } catch (e) {
      callback?.close();
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
      // Commons dispatches subscriber callbacks after releasing its mutex, so
      // unsubscribe alone does not guarantee no publisher thread is mid-call
      // into our NativeCallable. Drain in-flight callbacks per the documented
      // rac_sdk_event_stream.h teardown contract (unsubscribe -> quiesce ->
      // close) before closing the callable, mirroring the Swift/Kotlin/RN
      // event bridges and avoiding a use-after-free onto the closing isolate.
      RacNative.bindings.rac_sdk_event_quiesce?.call();
    } catch (e) {
      _logger.debug('SDKEvent proto unregistration failed: $e');
    } finally {
      _eventCallback?.close();
      _eventCallback = null;
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
    EventBus.shared.addFromNative(event);
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

  /// Clear all queued SDK events without affecting active subscriptions.
  ///
  /// Mirrors Swift `CppBridge.SDKEvents.clearQueue()`. Returns `true` when the
  /// commons symbol `rac_sdk_event_clear_queue` was located and invoked.
  bool clearQueue() {
    try {
      final lib = PlatformLoader.loadCommons();
      final fn = lib.lookupFunction<Void Function(), void Function()>(
        'rac_sdk_event_clear_queue',
      );
      fn();
      return true;
    } catch (e) {
      _logger.debug('rac_sdk_event_clear_queue unavailable: $e');
      return false;
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

/// The native callback is used as a
/// wake-up signal only. The bytes pointed to by [protoBytes] are NOT safe to
/// dereference from this listener because Dart `NativeCallable.listener`
/// dispatches to the Dart isolate asynchronously — by the time this callback
/// runs in the isolate, the commons producer (event_publisher.cpp) may have
/// rotated its ring buffer slot to a newer serialization, leaving the pointer
/// pointing at stale or partially overwritten bytes. This is precisely what
/// the 64-slot ring tried to mitigate, but the contract in
/// `rac_sdk_event_stream.h:6-7` ("Callback memory is owned by commons and is
/// valid only for the duration of the callback") cannot be honored when the
/// listener runs after the native call returns.
///
/// Instead we drain the canonical SDKEvent queue (`rac_sdk_event_poll`) which
/// returns an owned `rac_proto_buffer_t` populated from
/// `g_sdk_event_queue.front()` (event_publisher.cpp:539-547). That queue
/// holds copies (not pointers into the ring), so the decoded bytes are
/// race-free.
// ignore_for_file: prefer_function_declarations_over_variables

void _sdkEventCallback(
  Pointer<Uint8> protoBytes,
  int protoSize,
  Pointer<Void> userData,
) {
  // The pointer args are intentionally unused (see doc comment above): they
  // reference a ring slot that may have been overwritten by a newer
  // emission before this listener fires on the Dart isolate. The queue,
  // by contrast, holds owned copies popped one at a time via
  // rac_sdk_event_poll.
  // Keep params bound to keep the typedef-compatible signature.
  if (protoBytes == nullptr && protoSize < 0 && userData == nullptr) {
    return; // Unreachable; satisfies analyzer.
  }
  final pollFn = RacNative.bindings.rac_sdk_event_poll;
  if (pollFn == null) return;

  final bindings = RacNative.bindings;
  // Drain in a bounded loop so a single callback fires that fell behind
  // can catch up without unbounded queue growth. The loop terminates as
  // soon as the queue is empty (poll returns ERROR_NOT_FOUND).
  for (var i = 0; i < 1024; i++) {
    final out = calloc<RacProtoBuffer>();
    try {
      bindings.rac_proto_buffer_init(out);
      final code = pollFn(out);
      if (code != RacResultCode.success || out.ref.data == nullptr) {
        return;
      }
      try {
        final bytes =
            out.ref.data.asTypedList(out.ref.size).toList(growable: false);
        DartBridgeEvents.instance.emit(event_pb.SDKEvent.fromBuffer(bytes));
      } catch (e) {
        SDKLogger('DartBridge.Events').warning('Failed to decode SDKEvent: $e');
      }
    } finally {
      bindings.rac_proto_buffer_free(out);
      calloc.free(out);
    }
  }
}
