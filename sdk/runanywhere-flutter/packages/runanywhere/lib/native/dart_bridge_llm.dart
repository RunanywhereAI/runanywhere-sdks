/// DartBridge+LLM
///
/// LLM component bridge - manages C++ LLM component lifecycle.
/// Mirrors Swift's CppBridge+LLM.swift pattern exactly.
///
/// This is a thin wrapper around C++ LLM component functions.
/// All business logic is in C++ - Dart only manages the handle.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/llm_options.pb.dart'
    show LLMGenerationResult;
import 'package:runanywhere/generated/llm_service.pb.dart'
    show LLMGenerateRequest, LLMStreamEvent;
import 'package:runanywhere/generated/sdk_events.pb.dart' as sdk_events_pb;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/native_functions.dart';
import 'package:runanywhere/native/types/basic_types.dart';

/// LLM component bridge for C++ interop.
///
/// Provides access to the C++ LLM component.
/// Handles model loading, generation, and lifecycle.
///
/// Matches Swift's CppBridge.LLM actor pattern.
class DartBridgeLLM {
  // MARK: - Singleton

  /// Shared instance
  static final DartBridgeLLM shared = DartBridgeLLM._();

  DartBridgeLLM._();

  // MARK: - State (matches Swift CppBridge.LLM exactly)

  RacHandle? _handle;
  String? _loadedModelId;
  final _logger = SDKLogger('DartBridge.LLM');

  // MARK: - Handle Management

  /// Get or create the LLM component handle.
  ///
  /// Lazily creates the C++ LLM component on first access.
  /// Throws if creation fails.
  RacHandle getHandle() {
    if (_handle != null) {
      return _handle!;
    }

    try {
      final handlePtr = calloc<RacHandle>();
      try {
        final result = NativeFunctions.llmCreate(handlePtr);

        if (result != RAC_SUCCESS) {
          throw StateError(
            'Failed to create LLM component: ${RacResultCode.getMessage(result)}',
          );
        }

        _handle = handlePtr.value;
        _logger.debug('LLM component created');
        return _handle!;
      } finally {
        calloc.free(handlePtr);
      }
    } catch (e) {
      _logger.error('Failed to create LLM handle: $e');
      rethrow;
    }
  }

  // MARK: - State Queries

  /// Check if a model is loaded.
  bool get isLoaded {
    if (_handle == null) return false;

    try {
      return NativeFunctions.llmIsLoaded(_handle!) == RAC_TRUE;
    } catch (e) {
      _logger.debug('isLoaded check failed: $e');
      return false;
    }
  }

  /// Get the currently loaded model ID.
  String? get currentModelId => _loadedModelId;

  /// Check if streaming is supported.
  bool get supportsStreaming {
    if (_handle == null) return false;

    try {
      return NativeFunctions.llmSupportsStreaming(_handle!) == RAC_TRUE;
    } catch (e) {
      return false;
    }
  }

  // MARK: - Model Lifecycle

  /// Unload the current model.
  void unload() {
    if (_handle == null) return;

    try {
      NativeFunctions.llmCleanup(_handle!);
      _loadedModelId = null;
      _logger.info('LLM model unloaded');
    } catch (e) {
      _logger.error('Failed to unload LLM model: $e');
    }
  }

  /// Cancel ongoing generation.
  void cancel() {
    if (_handle == null) return;

    try {
      NativeFunctions.llmCancel(_handle!);
      _logger.debug('LLM generation cancelled');
    } catch (e) {
      _logger.error('Failed to cancel generation: $e');
    }
  }

  // MARK: - Generation

  /// Generate text using the lifecycle-owned generated-proto LLM ABI.
  ///
  /// The blocking C call runs in a short-lived worker isolate
  /// (`Isolate.run`) so the calling isolate — usually the Flutter UI
  /// isolate — stays responsive for the whole generation. Mirrors Swift's
  /// background `Task` and Kotlin's `Dispatchers.IO` placement of the same
  /// single-call ABI.
  ///
  /// No `isLoaded` gate: the generated-proto ABI resolves the engine from the
  /// commons model lifecycle (acquire_lifecycle_llm), NOT from this bridge's
  /// own `_handle` (which the lifecycle load path never populates). Gating on
  /// `_handle`/isLoaded here is a phantom check that spuriously throws even
  /// when a model IS loaded via the lifecycle, diverging from Kotlin/Swift
  /// (which have no such gate). Commons returns a clear error if truly unloaded.
  Future<LLMGenerationResult> generateProto(LLMGenerateRequest request) async {
    if (RacNative.bindings.rac_llm_generate_proto == null) {
      throw UnsupportedError('rac_llm_generate_proto is unavailable');
    }

    final requestBytes = request.writeToBuffer();
    final resultBytes =
        await Isolate.run(() => _llmGenerateWorker(requestBytes));
    return LLMGenerationResult.fromBuffer(resultBytes);
  }

  /// Stream text generation using the lifecycle-owned generated-proto LLM ABI,
  /// with TRUE incremental token delivery (FLUTTER-IOS-006 resolved).
  ///
  /// Threading model: the blocking `rac_llm_generate_stream_proto` call runs
  /// inside a short-lived worker isolate (`Isolate.run`), where a
  /// worker-owned `NativeCallable.isolateLocal` fires synchronously per
  /// token. The callback copies the proto bytes eagerly (commons serializes
  /// into a `thread_local` scratch buffer that is reused on the next
  /// emission — see FLUTTER-AND-PROTO-002 for why a deferred `.listener`
  /// read corrupts) and sends the copy over a `SendPort`. The main isolate
  /// decodes and emits each event as it arrives, so the calling isolate is
  /// never blocked and tokens stream live instead of bursting after the
  /// generation finishes. This is the Dart equivalent of Swift's
  /// `Task.detached` + `AsyncStream` and Kotlin's `Dispatchers.IO` +
  /// `callbackFlow` placement of the same single-call ABI.
  ///
  /// Cancellation: `onCancel` → `rac_llm_cancel_proto` sets the lifecycle
  /// cancel flag checked per token; the engine aborts, the worker's blocking
  /// call returns, and the trailing rc sentinel tears down the port. (With
  /// the old main-isolate placement, cancel could not even run until the
  /// generation finished — the isolate was blocked inside the FFI call.)
  ///
  /// No `isLoaded` gate (see generateProto): generation resolves via the
  /// commons model lifecycle, not this bridge's `_handle`.
  Stream<LLMStreamEvent> generateStreamProto(LLMGenerateRequest request) {
    if (RacNative.bindings.rac_llm_generate_stream_proto == null) {
      return Stream<LLMStreamEvent>.error(
        UnsupportedError('rac_llm_generate_stream_proto is unavailable'),
      );
    }

    final controller = StreamController<LLMStreamEvent>(sync: false);
    final receivePort = ReceivePort();
    var sawTerminalEvent = false;
    var tornDown = false;

    void teardown() {
      if (tornDown) return;
      tornDown = true;
      receivePort.close();
    }

    receivePort.listen((Object? message) {
      if (message is Uint8List) {
        // One serialized LLMStreamEvent, already copied in the worker's
        // synchronous callback, delivered over the port in emission order.
        if (controller.isClosed) return;
        try {
          final event = LLMStreamEvent.fromBuffer(message);
          sawTerminalEvent = sawTerminalEvent || event.isFinal;
          controller.add(event);
          if (event.isFinal) {
            unawaited(controller.close());
          }
        } catch (e, st) {
          controller.addError(e, st);
          unawaited(controller.close());
        }
      } else if (message is int) {
        // rc sentinel — always the LAST message (same port as the tokens, so
        // FIFO ordering is guaranteed; the Isolate.run future has no such
        // ordering relative to port messages). Early-return rcs (parse /
        // no-model errors) produce no terminal event, so surface them.
        if (message != RAC_SUCCESS &&
            !sawTerminalEvent &&
            !controller.isClosed) {
          controller.addError(
            StateError(
              'rac_llm_generate_stream_proto failed: '
              '${RacResultCode.getMessage(message)}',
            ),
          );
        }
        if (!controller.isClosed) {
          unawaited(controller.close());
        }
        teardown();
      }
    });

    final requestBytes = request.writeToBuffer();
    final sendPort = receivePort.sendPort;
    unawaited(
      _runLlmStreamWorker(requestBytes, sendPort)
          .catchError((Object e, StackTrace st) {
        // Worker isolate crashed (RemoteError) before the rc sentinel.
        if (!controller.isClosed) {
          controller.addError(e, st);
          unawaited(controller.close());
        }
        teardown();
        return RAC_SUCCESS;
      }),
    );

    // Cancel sets the per-token lifecycle cancel flag; the worker's blocking
    // call returns shortly after, emits a terminal "cancelled" event
    // (dropped — the controller is closing) and the rc sentinel closes the
    // port.
    controller.onCancel = cancelProto;

    return controller.stream;
  }

  /// Cancel lifecycle-owned LLM generation.
  sdk_events_pb.SDKEvent? cancelProto() {
    final fn = RacNative.bindings.rac_llm_cancel_proto;
    if (fn == null) {
      cancel();
      return null;
    }

    try {
      return DartBridgeProtoUtils.callOut<sdk_events_pb.SDKEvent>(
        invoke: fn,
        decode: sdk_events_pb.SDKEvent.fromBuffer,
        symbol: 'rac_llm_cancel_proto',
      );
    } catch (e) {
      _logger.error('Failed to cancel lifecycle-owned generation: $e');
      return null;
    }
  }

  // MARK: - Cleanup

  /// Destroy the component and release resources.
  void destroy() {
    if (_handle != null) {
      try {
        NativeFunctions.llmDestroy(_handle!);
        _handle = null;
        _loadedModelId = null;
        _logger.debug('LLM component destroyed');
      } catch (e) {
        _logger.error('Failed to destroy LLM component: $e');
      }
    }
  }
}

// MARK: - Worker-isolate entry points
//
// Top-level so `Isolate.run` closures capture only sendable values
// (Uint8List / SendPort). `RacNative.bindings` is a per-isolate static —
// the worker re-resolves the dylib symbols on first access (idempotent
// `PlatformLoader.loadCommons()`; same per-isolate-lookup convention as the
// HTTP adapter's `_sendBlocking`).
//
// Worker-isolate safety: the generation path's only Dart-bound callbacks are
// SDK events and logging, both registered as `NativeCallable.listener`
// (cross-isolate safe). The `Pointer.fromFunction` platform-adapter
// trampolines (file/secure/memory) that SIGABRTed the earlier model-LOAD
// `Isolate.run` wrap (see dart_bridge_model_lifecycle.dart) are never invoked
// during generation. If a future commons change adds one to this path, fix
// that callback to `.listener` — do not move the blocking call back onto the
// main isolate.

/// Runs [_llmStreamWorker] in a worker isolate. Hoisted to top level so the
/// `Isolate.run` closure captures ONLY its two sendable parameters
/// (`Uint8List` + `SendPort`). Inlined in [DartBridgeLLM.generateStreamProto],
/// the closure captured that method's whole local context — including the
/// unsendable `ReceivePort`/`StreamController` — which fails the isolate spawn
/// with "object is unsendable".
Future<int> _runLlmStreamWorker(Uint8List requestBytes, SendPort port) =>
    Isolate.run(() => _llmStreamWorker(requestBytes, port));

/// Blocking body of [DartBridgeLLM.generateStreamProto]. Runs the single-call
/// streaming ABI on the worker isolate; the worker-owned `isolateLocal`
/// callback fires synchronously per token (commons requires a synchronous
/// same-thread callback because it passes a pointer into a `thread_local`
/// scratch buffer), copies the bytes eagerly, and forwards the copy to the
/// main isolate. The rc is sent LAST on the same port so it is FIFO-ordered
/// after every token.
int _llmStreamWorker(Uint8List requestBytes, SendPort port) {
  final bindings = RacNative.bindings;
  final fn = bindings.rac_llm_generate_stream_proto;
  if (fn == null) {
    throw UnsupportedError('rac_llm_generate_stream_proto is unavailable');
  }

  final requestPtr = DartBridgeProtoUtils.copyBytes(requestBytes);
  NativeCallable<RacLlmStreamProtoCallbackNative>? callback;
  try {
    callback = NativeCallable<RacLlmStreamProtoCallbackNative>.isolateLocal(
      (Pointer<Uint8> bytesPtr, int bytesLen, Pointer<Void> _) {
        if (bytesPtr == nullptr || bytesLen <= 0) return;
        // Copy INSIDE the synchronous callback — commons reuses the scratch
        // buffer the moment we return. The copy is what crosses isolates.
        port.send(Uint8List.fromList(bytesPtr.asTypedList(bytesLen)));
      },
    );

    final rc = fn(
      requestPtr,
      requestBytes.length,
      callback.nativeFunction,
      nullptr,
    );
    port.send(rc);
    return rc;
  } finally {
    // Defensive quiesce (no-op for the single-call ABI today), then close the
    // callable on its owning isolate AFTER the blocking call has returned —
    // no emission can occur past this point.
    bindings.rac_llm_proto_quiesce?.call();
    callback?.close();
    calloc.free(requestPtr);
  }
}

/// Blocking body of [DartBridgeLLM.generateProto]: plain request→response
/// proto call, no callbacks. Returns the serialized LLMGenerationResult so
/// the main isolate owns the decode.
Uint8List _llmGenerateWorker(Uint8List requestBytes) {
  final bindings = RacNative.bindings;
  final fn = bindings.rac_llm_generate_proto;
  if (fn == null) {
    throw UnsupportedError('rac_llm_generate_proto is unavailable');
  }

  final requestPtr = DartBridgeProtoUtils.copyBytes(requestBytes);
  final out = calloc<RacProtoBuffer>();
  try {
    bindings.rac_proto_buffer_init(out);
    final code = fn(requestPtr, requestBytes.length, out);
    DartBridgeProtoUtils.ensureSuccess(out, code, 'rac_llm_generate_proto');
    if (out.ref.data == nullptr || out.ref.size == 0) {
      return Uint8List(0);
    }
    return Uint8List.fromList(out.ref.data.asTypedList(out.ref.size));
  } finally {
    bindings.rac_proto_buffer_free(out);
    calloc.free(out);
    calloc.free(requestPtr);
  }
}
