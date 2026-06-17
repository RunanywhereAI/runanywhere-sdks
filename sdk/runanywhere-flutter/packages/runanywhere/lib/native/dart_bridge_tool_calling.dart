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
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:fixnum/fixnum.dart' show Int64;

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

  /// Create a tool-calling session that runs entirely in a dedicated worker
  /// isolate, so the inline llama.cpp generation loop (create + every step)
  /// never blocks the calling isolate. Events are copied SYNCHRONOUSLY inside a
  /// worker-owned `NativeCallable.isolateLocal` (commons' dispatcher hands out a
  /// stack-local buffer valid only for the call — see tool_calling_session.cpp
  /// `dispatch_pending`) and forwarded to this isolate over a port, where they
  /// are decoded onto the returned broadcast stream. Tool results are sent back
  /// to the worker via [ToolCallingSessionHandle.stepWithResult]; cancellation
  /// uses the thread-safe `rac_tool_calling_session_cancel_proto` directly.
  ToolCallingSessionHandle createSession(
    ToolCallingSessionCreateRequest request,
  ) {
    if (RacNative.bindings.rac_tool_calling_session_create_proto == null ||
        RacNative.bindings.rac_tool_calling_session_step_with_result_proto ==
            null ||
        RacNative.bindings.rac_tool_calling_session_destroy_proto == null) {
      throw UnsupportedError(
        'rac_tool_calling_session_* proto APIs are unavailable',
      );
    }

    final controller = StreamController<ToolCallingSessionEvent>.broadcast();
    final fromWorker = ReceivePort();
    final idCompleter = Completer<int>();
    final handle = ToolCallingSessionHandle._(
      sessionId: idCompleter.future,
      events: controller,
      fromWorker: fromWorker,
    );

    fromWorker.listen((Object? message) {
      if (message is SendPort) {
        handle._toWorker = message;
      } else if (message is Uint8List) {
        if (controller.isClosed) return;
        try {
          controller.add(ToolCallingSessionEvent.fromBuffer(message));
        } catch (e, st) {
          controller.addError(e, st);
        }
      } else if (message is int) {
        _logger.debug('Tool calling session created: handle=$message');
        if (!idCompleter.isCompleted) idCompleter.complete(message);
      } else if (message is List && message.isNotEmpty && message[0] == 'err') {
        final err = StateError(
          message.length > 1 ? '${message[1]}' : 'tool-calling worker error',
        );
        if (!controller.isClosed) controller.addError(err);
        if (!idCompleter.isCompleted) idCompleter.completeError(err);
      }
    });

    final bytes = request.writeToBuffer();
    unawaited(() async {
      try {
        final iso = await Isolate.spawn(
          _toolSessionWorkerEntry,
          <dynamic>[fromWorker.sendPort, bytes],
        );
        handle._isolate = iso;
        if (handle._closed) iso.kill(priority: Isolate.immediate);
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
        if (!idCompleter.isCompleted) idCompleter.completeError(e, st);
      }
    }());

    return handle;
  }

  /// Teardown a session handle (called by the session worker, not directly).
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
    required Future<int> sessionId,
    required StreamController<ToolCallingSessionEvent> events,
    required ReceivePort fromWorker,
  })  : _sessionId = sessionId,
        _events = events,
        _fromWorker = fromWorker {
    // Cache the resolved id for synchronous cancel. Errors are swallowed here —
    // a failed create surfaces through the events stream and to [sessionId].
    _sessionId.then((id) => _resolvedId = id).catchError((Object _) => 0);
  }

  final Future<int> _sessionId;
  int _resolvedId = 0;
  final StreamController<ToolCallingSessionEvent> _events;
  final ReceivePort _fromWorker;
  SendPort? _toWorker;
  Isolate? _isolate;
  bool _closed = false;

  /// Future of the C-side session id, resolved when the worker reports it back
  /// (a turn after the first event). Only needed for [cancel].
  Future<int> get sessionId => _sessionId;

  /// Resolved C-side session id, or 0 if the worker has not reported it yet.
  int get resolvedSessionId => _resolvedId;

  /// Stream of `ToolCallingSessionEvent`s emitted by commons (forwarded from
  /// the session worker over a port).
  Stream<ToolCallingSessionEvent> get events => _events.stream;

  /// Forward a tool result so commons continues the loop. Runs the next
  /// generation turn IN THE SESSION WORKER — never blocks the calling isolate.
  /// The worker fills in its own session id, so callers need not await it.
  void stepWithResult({
    required String toolCallId,
    required String resultJson,
    required String error,
  }) {
    _toWorker?.send(<dynamic>['step', toolCallId, resultJson, error]);
  }

  /// Tear the session down: ask the worker to destroy the native session,
  /// quiesce, and close its callback (the worker owns the teardown ordering so
  /// commons never invokes a freed trampoline), then drop our port. When the
  /// worker is idle (the usual case — close runs after the final event) it
  /// processes this immediately and exits on its own.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final worker = _toWorker;
    if (worker != null) {
      worker.send('close');
    } else {
      // Worker not live yet — kill it once it spawns so it cannot leak.
      _isolate?.kill(priority: Isolate.immediate);
    }
    _toWorker = null;
    _fromWorker.close();
    await _events.close();
  }

  /// Cancel the in-flight native loop. `rac_tool_calling_session_cancel_proto`
  /// is thread-safe and idempotent, so it is invoked directly from this isolate
  /// (it latches a cancel the worker's in-flight generate checks) rather than
  /// queued behind the worker's blocking turn.
  bool cancel() {
    if (_closed || _resolvedId == 0) return false;
    return DartBridgeToolCalling.shared.cancelSession(_resolvedId);
  }
}

// MARK: - Session worker isolate
//
// `Isolate.spawn` entry (top-level; the spawn message is a sendable
// `[SendPort, Uint8List]` list — no closure capture). The whole session lives
// here: create + every step run the blocking llama.cpp generation loop inline
// without touching the UI isolate, and the event callback is a WORKER-owned
// `NativeCallable.isolateLocal` that fires SYNCHRONOUSLY on this worker thread
// during create/step. That synchronous timing is mandatory: commons'
// `dispatch_pending` hands the callback a pointer into a stack-local buffer
// that is freed the moment the call returns (tool_calling_session.cpp), so the
// bytes must be copied here-and-now — a deferred `.listener` read on another
// isolate is a use-after-free. The copy is what crosses back to the main
// isolate over `mainPort`. `RacNative.bindings` re-resolves the dylib symbols
// on first access (idempotent `PlatformLoader.loadCommons()`).
//
// Protocol — worker → main: the control `SendPort` (first), then serialized
// `ToolCallingSessionEvent` bytes per emission, then the `int` session id once
// create returns; `['err', msg]` on a hard create/step failure. main → worker:
// `['step', toolCallId, resultJson, error]` to continue the loop; `'close'` to
// destroy + quiesce + close the callback and exit. Cancellation is NOT routed
// here — the thread-safe cancel ABI is called directly from the main isolate.
void _toolSessionWorkerEntry(List<dynamic> args) {
  final mainPort = args[0] as SendPort;
  final createRequestBytes = args[1] as Uint8List;

  final bindings = RacNative.bindings;
  final createFn = bindings.rac_tool_calling_session_create_proto;
  final stepFn = bindings.rac_tool_calling_session_step_with_result_proto;
  final destroyFn = bindings.rac_tool_calling_session_destroy_proto;
  if (createFn == null || stepFn == null || destroyFn == null) {
    mainPort.send(<dynamic>['err', 'tool-calling session ABI unavailable']);
    return;
  }

  final control = ReceivePort();
  var sessionId = 0;
  var closed = false;

  final nativeCb =
      ffi.NativeCallable<RacToolCallingSessionEventCallbackNative>.isolateLocal(
          (ffi.Pointer<ffi.Uint8> bytesPtr, int bytesLen,
              ffi.Pointer<ffi.Void> _) {
    if (bytesLen <= 0 || bytesPtr == ffi.nullptr) return;
    // Copy synchronously — commons frees this buffer when the call returns.
    mainPort.send(Uint8List.fromList(bytesPtr.asTypedList(bytesLen)));
  });

  void cleanup() {
    if (closed) return;
    closed = true;
    if (sessionId != 0) destroyFn(sessionId);
    bindings.rac_tool_calling_session_proto_quiesce?.call();
    nativeCb.close();
    control.close();
  }

  // Hand the control port back before generating so main can send steps/close.
  mainPort.send(control.sendPort);

  control.listen((Object? message) {
    if (closed) return;
    if (message is List && message.isNotEmpty && message[0] == 'step') {
      final req = ToolCallingSessionStepWithResultRequest(
        sessionHandle: Int64(sessionId),
        toolCallId: message[1] as String,
        resultJson: message[2] as String,
        error: message[3] as String,
      );
      final bytes = req.writeToBuffer();
      final ptr = DartBridgeProtoUtils.copyBytes(bytes);
      try {
        final code = stepFn(ptr, bytes.length);
        if (code != 0) {
          mainPort.send(<dynamic>['err', 'step failed: code=$code']);
        }
      } finally {
        calloc.free(ptr);
      }
    } else if (message == 'close') {
      cleanup();
    }
  });

  // First turn — blocks here; events fire via nativeCb → mainPort. Commons
  // returns once it needs a tool result (or on the final answer).
  final reqPtr = DartBridgeProtoUtils.copyBytes(createRequestBytes);
  final handleOut = calloc<ffi.Uint64>();
  try {
    final code = createFn(
      reqPtr,
      createRequestBytes.length,
      nativeCb.nativeFunction,
      ffi.nullptr,
      handleOut,
    );
    if (code != 0) {
      mainPort.send(<dynamic>['err', 'create failed: code=$code']);
      cleanup();
      return;
    }
    sessionId = handleOut.value;
    mainPort.send(sessionId);
  } finally {
    calloc.free(reqPtr);
    calloc.free(handleOut);
  }
}
