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
  LLMGenerationResult generateProto(LLMGenerateRequest request) {
    // No `isLoaded` gate: the generated-proto ABI resolves the engine from the
    // commons model lifecycle (acquire_lifecycle_llm), NOT from this bridge's
    // own `_handle` (which the lifecycle load path never populates). Gating on
    // `_handle`/isLoaded here is a phantom check that spuriously throws even
    // when a model IS loaded via the lifecycle, diverging from Kotlin/Swift
    // (which have no such gate). Commons returns a clear error if truly unloaded.
    final fn = RacNative.bindings.rac_llm_generate_proto;
    if (fn == null) {
      throw UnsupportedError('rac_llm_generate_proto is unavailable');
    }

    return DartBridgeProtoUtils.callRequest<LLMGenerationResult>(
      request: request,
      invoke: fn,
      decode: LLMGenerationResult.fromBuffer,
      symbol: 'rac_llm_generate_proto',
    );
  }

  /// Stream text generation using the lifecycle-owned generated-proto LLM ABI.
  Stream<LLMStreamEvent> generateStreamProto(LLMGenerateRequest request) {
    // No `isLoaded` gate (see generateProto): generation resolves via the
    // commons model lifecycle, not this bridge's `_handle`. The phantom gate
    // here was the root cause of Flutter-only "No LLM model loaded" stream
    // errors offline (the spurious throw then triggered a downstream cancel).
    final fn = RacNative.bindings.rac_llm_generate_stream_proto;
    if (fn == null) {
      return Stream<LLMStreamEvent>.error(
        UnsupportedError('rac_llm_generate_stream_proto is unavailable'),
      );
    }

    final controller = StreamController<LLMStreamEvent>(sync: false);
    NativeCallable<RacLlmStreamProtoCallbackNative>? callback;
    var sawTerminalEvent = false;

    Future<void> run() async {
      final bytes = request.writeToBuffer();
      final requestPtr = DartBridgeProtoUtils.copyBytes(bytes);

      try {
        // FLUTTER-IOS-006 / FLUTTER-AND-PROTO-002: use `isolateLocal` (not
        // `.listener`) so the callback runs synchronously on the same
        // thread that invoked `rac_llm_generate_stream_proto`. The commons
        // producer (`dispatch_stream_event` in rac_llm_proto_service.cpp:353)
        // serializes into a `thread_local std::vector<uint8_t> scratch` slot
        // and immediately calls the callback with `scratch.data()`. With
        // `.listener` mode the callback is queued onto the Dart isolate's
        // event loop and runs ASYNCHRONOUSLY — by then a subsequent token
        // emission has already resized/overwritten the `scratch` slot,
        // leaving the captured pointer pointing at partially-overwritten
        // bytes. The decode then fails with `Protocol message end-group tag
        // did not match expected tag` (FLUTTER-IOS-006) or
        // `InvalidProtocolBufferException: invalid tag (zero)`
        // (FLUTTER-AND-PROTO-002).
        //
        // `isolateLocal` is safe here because:
        //   1. `rac_llm_generate_stream_proto` runs synchronously on the
        //      caller's thread (the Dart isolate).
        //   2. The engine vtable's `generate_stream` (llamacpp, onnx, etc.)
        //      iterates tokens on that same thread, invoking the proto
        //      callback synchronously per token.
        //   3. Therefore the callback always fires on the Dart isolate that
        //      created it — the exact precondition `isolateLocal` requires.
        callback = NativeCallable<RacLlmStreamProtoCallbackNative>.isolateLocal(
          (Pointer<Uint8> bytesPtr, int bytesLen, Pointer<Void> _) {
            if (controller.isClosed || bytesPtr == nullptr || bytesLen <= 0) {
              return;
            }

            try {
              final copy = Uint8List.fromList(bytesPtr.asTypedList(bytesLen));
              final event = LLMStreamEvent.fromBuffer(copy);
              sawTerminalEvent = sawTerminalEvent || event.isFinal;
              controller.add(event);
              if (event.isFinal) {
                unawaited(controller.close());
              }
            } catch (e, st) {
              controller.addError(e, st);
              unawaited(controller.close());
            }
          },
        );

        final rc = fn(
          requestPtr,
          bytes.length,
          callback!.nativeFunction,
          nullptr,
        );
        if (rc != RAC_SUCCESS && !controller.isClosed) {
          controller.addError(
            StateError(
              'rac_llm_generate_stream_proto failed: '
              '${RacResultCode.getMessage(rc)}',
            ),
          );
          await controller.close();
        } else if (!sawTerminalEvent && !controller.isClosed) {
          await controller.close();
        }
      } catch (e, st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
          await controller.close();
        }
      } finally {
        calloc.free(requestPtr);
        // commons-127: safety here relies on Dart isolate single-threading
        // plus the synchronous nature of `rac_llm_generate_stream_proto`
        // (the single-call ABI used by this bridge). `fn(...)` only returns
        // after the engine vtable's `generate_stream` has finished iterating
        // tokens on this same isolate thread, so by the time we reach this
        // `finally` the NativeCallable can no longer be invoked. The
        // `rac_llm_proto_quiesce` call below is a NO-OP for this path
        // (commons only increments the in-flight counter inside
        // `dispatch_llm_stream_event`, which is the REGISTRY path used by
        // `rac_llm_set_stream_proto_callback` — never invoked by Flutter)
        // but we still issue it defensively so that if commons ever fans
        // out a post-return emission on a worker through the single-call
        // ABI, this teardown sequence does the right thing without further
        // changes here. Pattern mirrors the voice-agent / STT / TTS / VAD /
        // VLM streaming bridges.
        RacNative.bindings.rac_llm_proto_quiesce?.call();
        callback?.close();
        callback = null;
      }
    }

    controller.onCancel = () {
      // commons-127: cancel → quiesce → close. `rac_llm_cancel_proto`
      // signals the engine to abort. Because the producing
      // `rac_llm_generate_stream_proto` call runs synchronously on this
      // Dart isolate thread, the NativeCallable cannot be re-entered once
      // `run()` has returned — Dart isolate single-threading is what
      // actually prevents the UAF here. `rac_llm_proto_quiesce` only spin-
      // waits on commons' REGISTRY-path in-flight counter
      // (`rac_llm_set_stream_proto_callback`), which Flutter never uses, so
      // it is a NO-OP today. We still call it (best-effort, ignored if the
      // symbol is absent) to future-proof this teardown the moment commons
      // adds an async tail-emit on the single-call path.
      cancelProto();
      RacNative.bindings.rac_llm_proto_quiesce?.call();
      callback?.close();
      callback = null;
    };

    unawaited(run());
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
