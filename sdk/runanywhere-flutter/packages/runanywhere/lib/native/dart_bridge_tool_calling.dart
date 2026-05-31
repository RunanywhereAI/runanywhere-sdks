// SPDX-License-Identifier: Apache-2.0
//
// dart_bridge_tool_calling.dart — thin proto-byte bridge over the commons
// tool-calling C ABI. All parsing, validation, prompt formatting, and
// session orchestration live in C++ (`rac_tool_call_*_proto` +
// `rac_tool_calling_session_*_proto`). This file only carries bytes.
//
// Mirrors Swift's `CppBridge+ToolCalling.swift`.
library;

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/tool_calling.pb.dart'
    show
        ToolCallValidationRequest,
        ToolCallValidationResult,
        ToolCallingSessionCreateRequest,
        ToolCallingSessionEvent,
        ToolCallingSessionStepWithResultRequest,
        ToolParseRequest,
        ToolParseResult,
        ToolPromptFormatRequest,
        ToolPromptFormatResult,
        ToolValue,
        ToolValueJSON;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';

/// Thin C ABI bridge for tool-calling parse / format / validate and the
/// session state machine.
class DartBridgeToolCalling {
  DartBridgeToolCalling._();

  static final DartBridgeToolCalling shared = DartBridgeToolCalling._();

  final _logger = SDKLogger('DartBridge.ToolCalling');

  /// Parse LLM output bytes via commons.
  ToolParseResult parse(ToolParseRequest request) {
    final fn = RacNative.bindings.rac_tool_call_parse_proto;
    if (fn == null) {
      throw UnsupportedError('rac_tool_call_parse_proto is unavailable');
    }
    return DartBridgeProtoUtils.callRequest<ToolParseResult>(
      request: request,
      invoke: fn,
      decode: ToolParseResult.fromBuffer,
      symbol: 'rac_tool_call_parse_proto',
    );
  }

  /// Format a tools-aware prompt via commons.
  ToolPromptFormatResult formatPrompt(ToolPromptFormatRequest request) {
    final fn = RacNative.bindings.rac_tool_call_format_prompt_proto;
    if (fn == null) {
      throw UnsupportedError(
          'rac_tool_call_format_prompt_proto is unavailable');
    }
    return DartBridgeProtoUtils.callRequest<ToolPromptFormatResult>(
      request: request,
      invoke: fn,
      decode: ToolPromptFormatResult.fromBuffer,
      symbol: 'rac_tool_call_format_prompt_proto',
    );
  }

  /// Validate a parsed tool call via commons.
  ToolCallValidationResult validate(ToolCallValidationRequest request) {
    final fn = RacNative.bindings.rac_tool_call_validate_proto;
    if (fn == null) {
      throw UnsupportedError('rac_tool_call_validate_proto is unavailable');
    }
    return DartBridgeProtoUtils.callRequest<ToolCallValidationResult>(
      request: request,
      invoke: fn,
      decode: ToolCallValidationResult.fromBuffer,
      symbol: 'rac_tool_call_validate_proto',
    );
  }

  /// Serialize a [ToolValue] to its canonical JSON string. Recursive walk
  /// lives in commons (`rac_tool_value_to_json_proto`); Dart only marshals
  /// bytes.
  String toolValueToJson(ToolValue value) {
    final fn = RacNative.bindings.rac_tool_value_to_json_proto;
    if (fn == null) {
      throw UnsupportedError('rac_tool_value_to_json_proto is unavailable');
    }
    final wrapper = DartBridgeProtoUtils.callRequest<ToolValueJSON>(
      request: value,
      invoke: fn,
      decode: ToolValueJSON.fromBuffer,
      symbol: 'rac_tool_value_to_json_proto',
    );
    return wrapper.json;
  }

  /// Parse a JSON string back into a [ToolValue]. Recursive walk lives in
  /// commons (`rac_tool_value_from_json_proto`); Dart only marshals bytes.
  ToolValue toolValueFromJson(String json) {
    final fn = RacNative.bindings.rac_tool_value_from_json_proto;
    if (fn == null) {
      throw UnsupportedError('rac_tool_value_from_json_proto is unavailable');
    }
    final wrapper = ToolValueJSON(json: json);
    return DartBridgeProtoUtils.callRequest<ToolValue>(
      request: wrapper,
      invoke: fn,
      decode: ToolValue.fromBuffer,
      symbol: 'rac_tool_value_from_json_proto',
    );
  }

  /// Create a native tool-calling session + install a callback that decodes
  /// [ToolCallingSessionEvent] bytes onto the returned broadcast stream.
  /// The returned [ToolCallingSessionHandle] wraps the session handle + the
  /// live NativeCallable so callers can destroy both together.
  ToolCallingSessionHandle createSession(
    ToolCallingSessionCreateRequest request,
  ) {
    final createFn = RacNative.bindings.rac_tool_calling_session_create_proto;
    final destroyFn = RacNative.bindings.rac_tool_calling_session_destroy_proto;
    if (createFn == null || destroyFn == null) {
      throw UnsupportedError(
        'rac_tool_calling_session_* proto APIs are unavailable',
      );
    }

    final controller = StreamController<ToolCallingSessionEvent>.broadcast();
    final nativeCb =
        ffi.NativeCallable<RacToolCallingSessionEventCallbackNative>.listener((
      ffi.Pointer<ffi.Uint8> bytesPtr,
      int bytesLen,
      ffi.Pointer<ffi.Void> _,
    ) {
      if (bytesLen <= 0 || bytesPtr == ffi.nullptr) return;
      final copy = Uint8List.fromList(bytesPtr.asTypedList(bytesLen));
      try {
        controller.add(ToolCallingSessionEvent.fromBuffer(copy));
      } catch (e, st) {
        controller.addError(e, st);
      }
    });

    final bytes = request.writeToBuffer();
    final reqPtr = DartBridgeProtoUtils.copyBytes(bytes);
    final handleOut = calloc<ffi.Uint64>();

    try {
      final code = createFn(
        reqPtr,
        bytes.length,
        nativeCb.nativeFunction,
        ffi.nullptr,
        handleOut,
      );
      if (code != 0) {
        nativeCb.close();
        unawaited(controller.close());
        throw StateError(
          'rac_tool_calling_session_create_proto failed: code=$code',
        );
      }
      final sessionHandle = handleOut.value;
      _logger.debug('Tool calling session created: handle=$sessionHandle');
      return ToolCallingSessionHandle._(
        sessionHandle: sessionHandle,
        events: controller,
        nativeCb: nativeCb,
      );
    } finally {
      calloc.free(reqPtr);
      calloc.free(handleOut);
    }
  }

  /// Forward a tool-result into an in-flight session so commons can continue
  /// the orchestration loop.
  void sessionStepWithResult(
    ToolCallingSessionStepWithResultRequest request,
  ) {
    final fn =
        RacNative.bindings.rac_tool_calling_session_step_with_result_proto;
    if (fn == null) {
      throw UnsupportedError(
        'rac_tool_calling_session_step_with_result_proto is unavailable',
      );
    }
    final bytes = request.writeToBuffer();
    final ptr = DartBridgeProtoUtils.copyBytes(bytes);
    try {
      final code = fn(ptr, bytes.length);
      if (code != 0) {
        throw StateError(
          'rac_tool_calling_session_step_with_result_proto failed: code=$code',
        );
      }
    } finally {
      calloc.free(ptr);
    }
  }

  /// Teardown a session created via [createSession].
  void destroySession(int sessionHandle) {
    final fn = RacNative.bindings.rac_tool_calling_session_destroy_proto;
    if (fn == null) return;
    try {
      fn(sessionHandle);
    } catch (e) {
      _logger.warning('session destroy failed: $e');
    }
  }

  /// Cancel an in-flight session. Safe to call from any
  /// isolate; the native side latches the cancel and asks the in-flight
  /// LifecycleLlmRef to abort. Idempotent for unknown handles. Returns
  /// false when the cancel ABI is not exported by the loaded libcommons.
  bool cancelSession(int sessionHandle) {
    final fn = RacNative.bindings.rac_tool_calling_session_cancel_proto;
    if (fn == null) {
      _logger.warning(
        'rac_tool_calling_session_cancel_proto is unavailable; falling back to destroy-only',
      );
      return false;
    }
    try {
      fn(sessionHandle);
      return true;
    } catch (e) {
      _logger.warning('session cancel failed: $e');
      return false;
    }
  }
}

/// Owned handle for a tool-calling session — combines the C side session id,
/// the Dart broadcast stream of decoded events, and the native callable that
/// must be closed when the session ends.
class ToolCallingSessionHandle {
  ToolCallingSessionHandle._({
    required this.sessionHandle,
    required StreamController<ToolCallingSessionEvent> events,
    required ffi.NativeCallable<RacToolCallingSessionEventCallbackNative>
        nativeCb,
  })  : _events = events,
        _nativeCb = nativeCb;

  /// C-side session handle (also carried on `ToolCallingSessionCreateResult`).
  final int sessionHandle;
  final StreamController<ToolCallingSessionEvent> _events;
  final ffi.NativeCallable<RacToolCallingSessionEventCallbackNative> _nativeCb;
  bool _closed = false;

  /// Stream of `ToolCallingSessionEvent`s emitted by commons.
  Stream<ToolCallingSessionEvent> get events => _events.stream;

  /// Destroy the native session, close the callback, and complete the stream.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    DartBridgeToolCalling.shared.destroySession(sessionHandle);
    // Teardown ordering: (1) destroy the session above so commons stops
    // accepting new dispatches into this NativeCallable, (2) quiesce so the
    // dispatcher returns from any in-flight callback whose `user_data` slot
    // was snapshotted under the commons mutex before the destroy landed
    // (see `rac_tool_calling.h:642` + `tool_calling_session.cpp:841`),
    // (3) close the NativeCallable backing that `user_data`. Skipping the
    // quiesce step lets the dispatcher invoke the trampoline after Dart frees
    // the user_data pointer (UAF). Mirrors the same ordering used by every
    // other Flutter stream wrapper (LLM/STT/TTS/VLM/voice-agent) and Swift's
    // `HandleStreamAdapter.tearDown()`.
    RacNative.bindings.rac_tool_calling_session_proto_quiesce?.call();
    _nativeCb.close();
    await _events.close();
  }

  /// Cancel the in-flight native loop. Distinct from [close]:
  /// cancel interrupts the underlying LLM generate from another isolate,
  /// while [close] tears the session down. The recommended pattern is to
  /// wire this into a `StreamSubscription.onCancel`, fanning consumer-side
  /// cancellation into the native loop.
  bool cancel() {
    if (_closed) return false;
    return DartBridgeToolCalling.shared.cancelSession(sessionHandle);
  }
}
