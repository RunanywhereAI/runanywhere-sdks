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
    if (!isLoaded) {
      throw StateError('No LLM model loaded. Call loadModel() first.');
    }

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
    if (!isLoaded) {
      return Stream<LLMStreamEvent>.error(
        StateError('No LLM model loaded. Call loadModel() first.'),
      );
    }

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
        // flutter-core-014: quiesce first so any tail emissions the engine
        // worker still has queued through this NativeCallable land BEFORE
        // we tear it down. Matches the CONSOLIDATE-D pattern used by the
        // voice-agent / STT / TTS / VAD / VLM streaming bridges.
        RacNative.bindings.rac_llm_proto_quiesce?.call();
        callback?.close();
        callback = null;
      }
    }

    controller.onCancel = () {
      // flutter-core-014: cancel → quiesce → close. `rac_llm_cancel_proto`
      // only signals the engine to abort; the inference loop may still be
      // mid-token and invoke this NativeCallable once more before noticing
      // the flag. Spin-wait via `rac_llm_proto_quiesce` (no-op if commons
      // does not export it) so the C side has fully drained any in-flight
      // dispatch through the trampoline before we close the
      // NativeCallable — without this the engine can call into a freed
      // callback (UAF) on the proto scratch buffer.
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
