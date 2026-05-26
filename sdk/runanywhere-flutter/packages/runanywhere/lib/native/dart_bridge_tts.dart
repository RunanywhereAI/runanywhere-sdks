/// DartBridge+TTS
///
/// TTS component bridge - manages C++ TTS component lifecycle.
/// Mirrors Swift's CppBridge+TTS.swift pattern.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/tts_options.pb.dart'
    show
        TTSOptions,
        TTSOutput,
        TTSServiceState,
        TTSStreamEvent,
        TTSSynthesisRequest,
        TTSVoiceInfo;
import 'package:runanywhere/generated/tts_options.pbenum.dart'
    show TTSStreamEventKind;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/native_functions.dart';
import 'package:runanywhere/native/types/basic_types.dart';

/// TTS component bridge for C++ interop.
///
/// Provides thread-safe access to the C++ TTS component.
/// Handles voice loading, synthesis, and streaming.
class DartBridgeTTS {
  // MARK: - Singleton

  /// Shared instance
  static final DartBridgeTTS shared = DartBridgeTTS._();

  DartBridgeTTS._();

  // MARK: - State

  RacHandle? _handle;
  String? _loadedVoiceId;
  final _logger = SDKLogger('DartBridge.TTS');
  static TTSOutput Function(TTSSynthesisRequest)?
      _synthesizeLifecycleProtoForTesting;

  static void setSynthesizeLifecycleProtoForTesting(
    TTSOutput Function(TTSSynthesisRequest)? override,
  ) {
    _synthesizeLifecycleProtoForTesting = override;
  }

  // Streaming test seam (pass2-syn-023). Symmetric to
  // `setSynthesizeLifecycleProtoForTesting` but for the streaming path —
  // tests use this to drive `synthesizeStreamLifecycleProto` without a real
  // FFI binding. The override receives the same `dispatch` closure the
  // production NativeCallable would invoke, so the real wrapper's drain loop
  // + `controller.onCancel -> stopLifecycleProto()` path stays in-circuit.
  static TTSStreamFakeFFI? _synthesizeStreamLifecycleProtoForTesting;
  // Type matches production `stopLifecycleProto()` return type
  // (`TTSServiceState`) so the seam contract is identical to the real call.
  // The override's return value is discarded at the call site today, but
  // aligning the type eliminates refactor friction when commons-side stop
  // state is propagated. (pass3-syn-163)
  static TTSServiceState Function()? _stopLifecycleProtoForTesting;

  /// Inject a fake native-stream driver. Pass `null` to clear.
  static void setSynthesizeStreamLifecycleProtoForTesting(
    TTSStreamFakeFFI? override,
  ) {
    _synthesizeStreamLifecycleProtoForTesting = override;
  }

  /// Inject a fake `stopLifecycleProto` invocation that
  /// `synthesizeStreamLifecycleProto.onCancel` should call instead of the
  /// real FFI binding. Pass `null` to clear.
  static void setStopLifecycleProtoForTesting(
    TTSServiceState Function()? override,
  ) {
    _stopLifecycleProtoForTesting = override;
  }

  // MARK: - Handle Management

  /// Get or create the TTS component handle.
  RacHandle getHandle() {
    if (_handle != null) {
      return _handle!;
    }

    try {
      final handlePtr = calloc<RacHandle>();
      try {
        final result = NativeFunctions.ttsCreate(handlePtr);

        if (result != RAC_SUCCESS) {
          throw StateError(
            'Failed to create TTS component: ${RacResultCode.getMessage(result)}',
          );
        }

        _handle = handlePtr.value;
        _logger.debug('TTS component created');
        return _handle!;
      } finally {
        calloc.free(handlePtr);
      }
    } catch (e) {
      _logger.error('Failed to create TTS handle: $e');
      rethrow;
    }
  }

  // MARK: - State Queries

  /// Check if a voice is loaded.
  bool get isLoaded {
    if (_handle == null) return false;

    try {
      return NativeFunctions.ttsIsLoaded(_handle!) == RAC_TRUE;
    } catch (e) {
      _logger.debug('isLoaded check failed: $e');
      return false;
    }
  }

  /// Get the currently loaded voice ID.
  String? get currentVoiceId => _loadedVoiceId;

  /// Stop ongoing synthesis.
  void stop() {
    if (_handle == null) return;

    try {
      NativeFunctions.ttsStop(_handle!);
      _logger.debug('TTS synthesis stopped');
    } catch (e) {
      _logger.error('Failed to stop TTS: $e');
    }
  }

  // MARK: - Synthesis

  /// Synthesize speech through the lifecycle-owned generated-proto TTS ABI.
  TTSOutput synthesizeLifecycleProto(TTSSynthesisRequest request) {
    _validateLifecycleRequest(request);

    final override = _synthesizeLifecycleProtoForTesting;
    if (override != null) {
      return override(request);
    }

    final fn = RacNative.bindings.rac_tts_synthesize_lifecycle_proto;
    if (fn == null) {
      throw UnsupportedError(
        'rac_tts_synthesize_lifecycle_proto is unavailable',
      );
    }

    return DartBridgeProtoUtils.callRequest<TTSOutput>(
      request: request,
      invoke: fn,
      decode: TTSOutput.fromBuffer,
      symbol: 'rac_tts_synthesize_lifecycle_proto',
    );
  }

  /// Stream TTSStreamEvent chunks via the lifecycle-owned generated-proto ABI.
  ///
  /// Mirrors STT's `transcribeStreamLifecycleProto`. Requires commons to have
  /// the TTS model loaded through model lifecycle.
  Stream<TTSStreamEvent> synthesizeStreamLifecycleProto(
    TTSSynthesisRequest request,
  ) {
    _validateLifecycleRequest(request);

    final streamOverride = _synthesizeStreamLifecycleProtoForTesting;
    // Defer the FFI lookup when a test seam is installed — accessing
    // `RacNative.bindings` triggers a `dlopen` of librac_commons, which fails
    // in the unit-test harness where no native library is staged. The test
    // group `DartBridgeTTS.synthesizeStreamLifecycleProto — real wrapper, fake
    // FFI` (pass2-syn-023) covers the production wrapper without the FFI.
    final fn = streamOverride == null
        ? RacNative.bindings.rac_tts_synthesize_stream_lifecycle_proto
        : null;
    if (streamOverride == null && fn == null) {
      return Stream<TTSStreamEvent>.error(
        UnsupportedError(
          'rac_tts_synthesize_stream_lifecycle_proto is unavailable',
        ),
      );
    }

    final controller = StreamController<TTSStreamEvent>(sync: false);
    NativeCallable<RacTtsStreamEventCallbackNative>? callback;
    var sawTerminalEvent = false;

    // Shared dispatch closure — used by both the real NativeCallable.listener
    // and the test-injected fake FFI. Centralizing this guarantees the test
    // path exercises the same listener-body behavior (closed-controller
    // guard, terminal-kind tracking) as production. (pass2-syn-023)
    void dispatchEvent(TTSStreamEvent event) {
      if (controller.isClosed) return;
      sawTerminalEvent = sawTerminalEvent ||
          event.kind == TTSStreamEventKind.TTS_STREAM_EVENT_KIND_COMPLETED ||
          event.kind == TTSStreamEventKind.TTS_STREAM_EVENT_KIND_ERROR;
      controller.add(event);
    }

    Future<void> run() async {
      // Test seam: skip FFI entirely; let the fake drive `dispatchEvent`
      // synchronously then return an rc. Same drain + close semantics as
      // the real path.
      if (streamOverride != null) {
        try {
          final rc = await streamOverride(
            request,
            dispatchEvent,
            () => sawTerminalEvent,
          );
          await drainPendingStreamCallbacks(() => sawTerminalEvent);
          if (rc != RAC_SUCCESS && !controller.isClosed) {
            controller.addError(StateError(
              'rac_tts_synthesize_stream_lifecycle_proto (test fake) failed: '
              '${RacResultCode.getMessage(rc)}',
            ));
          }
          if (!controller.isClosed) {
            await controller.close();
          }
        } catch (e, st) {
          if (!controller.isClosed) {
            controller.addError(e, st);
            await controller.close();
          }
        }
        return;
      }

      final bytes = request.writeToBuffer();
      final requestPtr = DartBridgeProtoUtils.copyBytes(bytes);

      try {
        callback = NativeCallable<RacTtsStreamEventCallbackNative>.listener((
          Pointer<Uint8> bytesPtr,
          int bytesLen,
          Pointer<Void> _,
        ) {
          if (bytesPtr == nullptr || bytesLen <= 0) return;
          try {
            final copy = Uint8List.fromList(bytesPtr.asTypedList(bytesLen));
            dispatchEvent(TTSStreamEvent.fromBuffer(copy));
          } catch (e, st) {
            controller.addError(e, st);
            unawaited(controller.close());
          }
        });
        final rc = fn!(
          requestPtr,
          bytes.length,
          callback!.nativeFunction,
          nullptr,
        );
        // FLUTTER-IOS-001 fix (mirrors RunAnywhereLLM._generateStreamProto):
        // `rac_tts_synthesize_stream_lifecycle_proto` is a blocking
        // synchronous FFI call. While it runs the main isolate's event loop
        // is frozen, so NativeCallable.listener invocations queue up but do
        // not execute. The terminal COMPLETED/ERROR event therefore arrives
        // ASYNCHRONOUSLY after `fn()` returns. Yield via the shared
        // [drainPendingStreamCallbacks] helper so queued callbacks can drain
        // before deciding whether to force-close the controller; otherwise
        // subscribers receive an empty stream even though native emitted
        // started/audio/final. See [kStreamDrainMaxMicrotasks].
        await drainPendingStreamCallbacks(() => sawTerminalEvent);
        if (rc != RAC_SUCCESS && !controller.isClosed) {
          controller.addError(StateError(
            'rac_tts_synthesize_stream_lifecycle_proto failed: '
            '${RacResultCode.getMessage(rc)}',
          ));
        }
        if (!controller.isClosed) {
          await controller.close();
        }
      } finally {
        calloc.free(requestPtr);
        // CONSOLIDATE-D fix: drain in-flight TTS chunk dispatches before
        // closing the NativeCallable. `rac_tts_synthesize_stream_lifecycle_proto`
        // may post the terminal COMPLETED/ERROR callback from a worker
        // thread that copies the user_data slot under commons' internal
        // mutex and releases it BEFORE invoking the callback (see
        // `rac/features/tts/rac_tts_stream.h` warning). Without
        // `rac_tts_proto_quiesce()` the C side can invoke the trampoline
        // backed by NativeCallable user_data after `callback.close()` —
        // UAF on the proto scratch buffer.
        RacNative.bindings.rac_tts_proto_quiesce?.call();
        callback?.close();
        callback = null;
      }
    }

    controller.onCancel = () {
      // Best-effort: ask commons to stop lifecycle synthesis so native CPU
      // isn't burned for a Dart subscriber that has already gone away.
      // RunAnywhereTTS.stopSynthesis() routes through the same ABI; mirror
      // its semantics here so cancelling the public stream subscription
      // also stops the underlying lifecycle work. Errors are swallowed so
      // cancellation remains best-effort.
      try {
        final stopOverride = _stopLifecycleProtoForTesting;
        if (stopOverride != null) {
          stopOverride();
        } else {
          stopLifecycleProto();
        }
      } catch (e) {
        _logger.debug('stopLifecycleProto on stream cancel failed: $e');
      }
      // Same CONSOLIDATE-D ordering as the run() teardown — quiesce first.
      RacNative.bindings.rac_tts_proto_quiesce?.call();
      callback?.close();
      callback = null;
    };

    unawaited(run());
    return controller.stream;
  }

  /// Stop the lifecycle-loaded TTS synthesis. Returns post-stop service state.
  TTSServiceState stopLifecycleProto() {
    final fn = RacNative.bindings.rac_tts_stop_lifecycle_proto;
    if (fn == null) {
      throw UnsupportedError('rac_tts_stop_lifecycle_proto is unavailable');
    }
    return DartBridgeProtoUtils.callOut<TTSServiceState>(
      invoke: fn,
      decode: TTSServiceState.fromBuffer,
      symbol: 'rac_tts_stop_lifecycle_proto',
    );
  }

  /// Enumerate voices via the generated-proto ABI.
  Future<List<TTSVoiceInfo>> listVoicesProto() async {
    final handle = getHandle();
    final fn = RacNative.bindings.rac_tts_component_list_voices_proto;
    if (fn == null) {
      throw UnsupportedError(
          'rac_tts_component_list_voices_proto is unavailable');
    }

    final voices = <TTSVoiceInfo>[];
    NativeCallable<RacTtsProtoVoiceCallbackNative>? callback;

    try {
      callback = NativeCallable<RacTtsProtoVoiceCallbackNative>.listener((
        Pointer<Uint8> bytesPtr,
        int bytesLen,
        Pointer<Void> _,
      ) {
        if (bytesPtr == nullptr || bytesLen <= 0) return;
        final copy = Uint8List.fromList(bytesPtr.asTypedList(bytesLen));
        voices.add(TTSVoiceInfo.fromBuffer(copy));
      });
      final rc = fn(handle, callback.nativeFunction, nullptr);
      if (rc != RAC_SUCCESS) {
        throw StateError(
          'rac_tts_component_list_voices_proto failed: '
          '${RacResultCode.getMessage(rc)}',
        );
      }
      return voices;
    } finally {
      callback?.close();
    }
  }

  /// Synthesize speech with serialized runanywhere.v1.TTSOptions.
  Future<TTSOutput> synthesizeProto(String text, TTSOptions options) async {
    final handle = getHandle();
    if (!isLoaded) {
      throw UnsupportedError(
        'No TTS component handle is loaded. Public TTS uses '
        'synthesizeLifecycleProto instead of Dart-held component handles.',
      );
    }

    final fn = RacNative.bindings.rac_tts_component_synthesize_proto;
    if (fn == null) {
      throw UnsupportedError(
          'rac_tts_component_synthesize_proto is unavailable');
    }

    final textPtr = text.toNativeUtf8();
    final optionBytes = options.writeToBuffer();
    final optionPtr = DartBridgeProtoUtils.copyBytes(optionBytes);
    final out = calloc<RacProtoBuffer>();
    final bindings = RacNative.bindings;

    try {
      bindings.rac_proto_buffer_init(out);
      final code = fn(handle, textPtr, optionPtr, optionBytes.length, out);
      DartBridgeProtoUtils.ensureSuccess(
        out,
        code,
        'rac_tts_component_synthesize_proto',
      );
      return DartBridgeProtoUtils.decodeBuffer(out, TTSOutput.fromBuffer);
    } finally {
      bindings.rac_proto_buffer_free(out);
      calloc.free(textPtr);
      calloc.free(optionPtr);
      calloc.free(out);
    }
  }

  /// Stream synthesized speech chunks through serialized TTSOutput messages.
  Stream<TTSOutput> synthesizeStreamProto(String text, TTSOptions options) {
    if (!isLoaded) {
      return Stream<TTSOutput>.error(
        UnsupportedError(
          'No TTS component handle is loaded. Public TTS streaming remains '
          'unavailable until a lifecycle-owned stream ABI exists.',
        ),
      );
    }
    final fn = RacNative.bindings.rac_tts_component_synthesize_stream_proto;
    if (fn == null) {
      return Stream<TTSOutput>.error(
        UnsupportedError(
            'rac_tts_component_synthesize_stream_proto is unavailable'),
      );
    }

    final controller = StreamController<TTSOutput>(sync: false);
    NativeCallable<RacTtsProtoChunkCallbackNative>? callback;

    Future<void> run() async {
      final textPtr = text.toNativeUtf8();
      final optionBytes = options.writeToBuffer();
      final optionPtr = DartBridgeProtoUtils.copyBytes(optionBytes);

      try {
        callback = NativeCallable<RacTtsProtoChunkCallbackNative>.listener((
          Pointer<Uint8> bytesPtr,
          int bytesLen,
          Pointer<Void> _,
        ) {
          if (controller.isClosed || bytesPtr == nullptr || bytesLen <= 0) {
            return;
          }
          try {
            final copy = Uint8List.fromList(bytesPtr.asTypedList(bytesLen));
            controller.add(TTSOutput.fromBuffer(copy));
          } catch (e, st) {
            controller.addError(e, st);
            unawaited(controller.close());
          }
        });
        final rc = fn(
          getHandle(),
          textPtr,
          optionPtr,
          optionBytes.length,
          callback!.nativeFunction,
          nullptr,
        );
        if (rc != RAC_SUCCESS && !controller.isClosed) {
          controller.addError(StateError(
            'rac_tts_component_synthesize_stream_proto failed: '
            '${RacResultCode.getMessage(rc)}',
          ));
        }
        if (!controller.isClosed) {
          await controller.close();
        }
      } finally {
        calloc.free(textPtr);
        calloc.free(optionPtr);
        // CONSOLIDATE-D: same quiesce-before-close ordering as the
        // lifecycle-owned stream wrapper above. See
        // `synthesizeStreamLifecycleProto`.
        RacNative.bindings.rac_tts_proto_quiesce?.call();
        callback?.close();
        callback = null;
      }
    }

    controller.onCancel = () {
      RacNative.bindings.rac_tts_proto_quiesce?.call();
      callback?.close();
      callback = null;
    };

    unawaited(run());
    return controller.stream;
  }

  // MARK: - Cleanup

  /// Destroy the component and release resources.
  void destroy() {
    if (_handle != null) {
      try {
        NativeFunctions.ttsDestroy(_handle!);
        _handle = null;
        _loadedVoiceId = null;
        _logger.debug('TTS component destroyed');
      } catch (e) {
        _logger.error('Failed to destroy TTS component: $e');
      }
    }
  }

  void _validateLifecycleRequest(TTSSynthesisRequest request) {
    if (request.text.isEmpty && (!request.hasSsml() || request.ssml.isEmpty)) {
      throw ArgumentError(
        'TTSSynthesisRequest.text or ssml is required for lifecycle TTS',
      );
    }
  }
}

/// Test seam type for [DartBridgeTTS.synthesizeStreamLifecycleProto]
/// (pass2-syn-023). The override receives:
///   - [request]: the TTSSynthesisRequest the production code received.
///   - [dispatch]: the same closure the production NativeCallable invokes —
///     pass a `TTSStreamEvent` to deliver it through the real wrapper's
///     listener body (drain loop + closed-controller guard intact).
///   - [terminalObserved]: closure the fake can check to short-circuit.
/// Returning a non-zero result code drives the wrapper's error branch.
typedef TTSStreamFakeFFI = Future<int> Function(
  TTSSynthesisRequest request,
  void Function(TTSStreamEvent) dispatch,
  bool Function() terminalObserved,
);
