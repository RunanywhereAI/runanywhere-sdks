/// DartBridge+TTS
///
/// TTS component bridge - manages C++ TTS component lifecycle.
/// Mirrors Swift's CppBridge+TTS.swift pattern.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
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

  // Streaming test seam. Symmetric to
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
  // state is propagated.
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

  /// Synthesize speech through the lifecycle-owned generated-proto TTS ABI,
  /// running the blocking native call in a short-lived worker isolate
  /// (`Isolate.run`) so the calling isolate — usually the Flutter UI isolate —
  /// stays responsive for the whole synthesis. Vocoder synthesis of a full
  /// utterance is a long synchronous block; on the UI isolate it freezes
  /// frames. Mirrors `dart_bridge_stt.dart`'s `transcribeLifecycleProtoAsync`
  /// and `dart_bridge_llm.dart`'s `generateProto`: this ABI is lifecycle-owned
  /// (no Dart-held handle), so the worker re-resolves the engine via the
  /// commons model lifecycle — nothing isolate-bound crosses.
  Future<TTSOutput> synthesizeLifecycleProtoAsync(
    TTSSynthesisRequest request,
  ) async {
    _validateLifecycleRequest(request);

    final override = _synthesizeLifecycleProtoForTesting;
    if (override != null) {
      return override(request);
    }

    if (RacNative.bindings.rac_tts_synthesize_lifecycle_proto == null) {
      throw UnsupportedError(
        'rac_tts_synthesize_lifecycle_proto is unavailable',
      );
    }

    final requestBytes = request.writeToBuffer();
    final resultBytes = await Isolate.run(
      () => _ttsSynthesizeWorker(requestBytes),
    );
    return TTSOutput.fromBuffer(resultBytes);
  }

  /// Stream TTSStreamEvent chunks via the lifecycle-owned generated-proto ABI.
  ///
  /// Mirrors STT's `transcribeStreamLifecycleProto`. Requires commons to have
  /// the TTS model loaded through model lifecycle.
  Stream<TTSStreamEvent> synthesizeStreamLifecycleProto(
    TTSSynthesisRequest request,
  ) {
    _validateLifecycleRequest(request);

    // Test seam: drive the wrapper without the FFI. Accessing
    // `RacNative.bindings` triggers a `dlopen` of librac_commons, which fails
    // in the unit-test harness where no native library is staged. The seam
    // path runs entirely on the calling isolate so the test group
    // `DartBridgeTTS.synthesizeStreamLifecycleProto — real wrapper, fake FFI`
    // exercises the production drain loop + dispatch closure without spawning
    // a worker.
    final streamOverride = _synthesizeStreamLifecycleProtoForTesting;
    if (streamOverride != null) {
      return _synthesizeStreamViaTestSeam(request, streamOverride);
    }

    final bindings = RacNative.bindings;
    final nativePortFn =
        bindings.ra_flutter_tts_synthesize_stream_lifecycle_proto_native_port;
    if (nativePortFn == null) {
      return Stream<TTSStreamEvent>.error(
        UnsupportedError(
          'ra_flutter_tts_synthesize_stream_lifecycle_proto_native_port '
          'is unavailable',
        ),
      );
    }

    // Production path: the blocking TTS stream call runs inside a short-lived
    // worker isolate (`Isolate.run`). On iOS and Android, the Flutter plugin
    // exports a native-port helper that copies event bytes inside the C
    // callback and posts owned `Uint8List` messages here, which is safe for
    // MLX/Swift async and native worker-thread callbacks. The calling isolate
    // stays responsive.
    final controller = StreamController<TTSStreamEvent>(sync: false);
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
        // One serialized TTSStreamEvent, already copied in the worker's
        // synchronous callback, delivered over the port in emission order.
        if (controller.isClosed) return;
        try {
          final event = TTSStreamEvent.fromBuffer(message);
          final isTerminal =
              event.kind ==
                  TTSStreamEventKind.TTS_STREAM_EVENT_KIND_COMPLETED ||
              event.kind == TTSStreamEventKind.TTS_STREAM_EVENT_KIND_ERROR;
          sawTerminalEvent = sawTerminalEvent || isTerminal;
          controller.add(event);
          if (isTerminal) {
            unawaited(controller.close());
          }
        } catch (e, st) {
          controller.addError(e, st);
          unawaited(controller.close());
        }
      } else if (message is int) {
        // rc sentinel — always the LAST message (same port as the chunks, so
        // FIFO ordering is guaranteed). Early-return rcs (parse / no-model
        // errors) produce no terminal event, so surface them.
        if (message != RAC_SUCCESS &&
            !sawTerminalEvent &&
            !controller.isClosed) {
          controller.addError(
            StateError(
              'rac_tts_synthesize_stream_lifecycle_proto failed: '
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
    final worker = _runTtsStreamNativePortWorker(
      requestBytes,
      receivePort.sendPort.nativePort,
    );
    unawaited(
      worker.catchError((Object e, StackTrace st) {
        // Worker isolate crashed (RemoteError) before the rc sentinel.
        if (!controller.isClosed) {
          controller.addError(e, st);
          unawaited(controller.close());
        }
        teardown();
        return RAC_SUCCESS;
      }),
    );

    controller.onCancel = () {
      // Best-effort: ask commons to stop lifecycle synthesis so native CPU
      // isn't burned for a Dart subscriber that has already gone away.
      // RunAnywhereTTS.stopSynthesis() routes through the same ABI; mirror its
      // semantics here. The worker's blocking call returns shortly after, emits
      // a terminal event (dropped — the controller is closing) and the rc
      // sentinel closes the port. Errors are swallowed so cancellation stays
      // best-effort.
      try {
        stopLifecycleProto();
      } catch (e) {
        _logger.debug('stopLifecycleProto on stream cancel failed: $e');
      }
      teardown();
    };

    return controller.stream;
  }

  /// Test-only streaming path: drives the production drain loop + dispatch
  /// closure with a Dart-side fake instead of the FFI. Runs entirely on the
  /// calling isolate (the unit-test harness has no native library to `dlopen`
  /// and no worker to spawn).
  Stream<TTSStreamEvent> _synthesizeStreamViaTestSeam(
    TTSSynthesisRequest request,
    TTSStreamFakeFFI streamOverride,
  ) {
    final controller = StreamController<TTSStreamEvent>(sync: false);
    var sawTerminalEvent = false;

    void dispatchEvent(TTSStreamEvent event) {
      if (controller.isClosed) return;
      sawTerminalEvent =
          sawTerminalEvent ||
          event.kind == TTSStreamEventKind.TTS_STREAM_EVENT_KIND_COMPLETED ||
          event.kind == TTSStreamEventKind.TTS_STREAM_EVENT_KIND_ERROR;
      controller.add(event);
    }

    Future<void> run() async {
      try {
        final rc = await streamOverride(
          request,
          dispatchEvent,
          () => sawTerminalEvent,
        );
        await drainPendingStreamCallbacks(() => sawTerminalEvent);
        if (rc != RAC_SUCCESS && !controller.isClosed) {
          controller.addError(
            StateError(
              'rac_tts_synthesize_stream_lifecycle_proto (test fake) failed: '
              '${RacResultCode.getMessage(rc)}',
            ),
          );
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
    }

    controller.onCancel = () {
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
        'rac_tts_component_list_voices_proto is unavailable',
      );
    }

    final voices = <TTSVoiceInfo>[];
    NativeCallable<RacTtsProtoVoiceCallbackNative>? callback;

    try {
      // `isolateLocal` (not `.listener`): `rac_tts_component_list_voices_proto`
      // is a single synchronous enumeration on the calling thread — it invokes
      // the callback inline once per voice (tts_component.cpp) and returns. With
      // `.listener` the callbacks queue onto the event loop and run on a future
      // microtask, so `return voices` below captures an empty list (and the
      // stack-local proto buffer is freed by then). `isolateLocal` fires inline
      // so voices accumulate synchronously before `fn(...)` returns.
      callback = NativeCallable<RacTtsProtoVoiceCallbackNative>.isolateLocal((
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
        'rac_tts_component_synthesize_proto is unavailable',
      );
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
          'rac_tts_component_synthesize_stream_proto is unavailable',
        ),
      );
    }

    final controller = StreamController<TTSOutput>(sync: false);
    NativeCallable<RacTtsProtoChunkCallbackNative>? callback;

    Future<void> run() async {
      final textPtr = text.toNativeUtf8();
      final optionBytes = options.writeToBuffer();
      final optionPtr = DartBridgeProtoUtils.copyBytes(optionBytes);

      try {
        // Same root cause as
        // synthesizeStreamLifecycleProto: `isolateLocal` so the callback runs
        // inline on the synchronous-FFI thread. `rac_tts_component_synthesize_
        // stream_proto`'s `bridge` (tts_component.cpp) serializes each chunk
        // into a stack-local buffer and invokes the callback inline; with
        // `.listener` the deferred callback reads that freed buffer (UAF).
        callback = NativeCallable<RacTtsProtoChunkCallbackNative>.isolateLocal((
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
          controller.addError(
            StateError(
              'rac_tts_component_synthesize_stream_proto failed: '
              '${RacResultCode.getMessage(rc)}',
            ),
          );
        }
        if (!controller.isClosed) {
          await controller.close();
        }
      } finally {
        calloc.free(textPtr);
        calloc.free(optionPtr);
        // Same quiesce-before-close ordering as the
        // lifecycle-owned stream wrapper above. See
        // `synthesizeStreamLifecycleProto`.
        _quiesce();
        callback?.close();
        callback = null;
      }
    }

    controller.onCancel = () {
      _quiesce();
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

  void _quiesce() {
    try {
      RacNative.bindings.rac_tts_proto_quiesce();
    } catch (e) {
      _logger.error('rac_tts_proto_quiesce failed: $e');
    }
  }
}

/// Test seam type for [DartBridgeTTS.synthesizeStreamLifecycleProto].
/// The override receives:
///   - [request]: the TTSSynthesisRequest the production code received.
///   - [dispatch]: the same closure the production NativeCallable invokes —
///     pass a `TTSStreamEvent` to deliver it through the real wrapper's
///     listener body (drain loop + closed-controller guard intact).
///   - [terminalObserved]: closure the fake can check to short-circuit.
/// Returning a non-zero result code drives the wrapper's error branch.
typedef TTSStreamFakeFFI =
    Future<int> Function(
      TTSSynthesisRequest request,
      void Function(TTSStreamEvent) dispatch,
      bool Function() terminalObserved,
    );

// MARK: - Worker-isolate entry points
//
// Top-level so `Isolate.run` closures capture only sendable values
// (Uint8List / SendPort). `RacNative.bindings` is a per-isolate static — the
// worker re-resolves the dylib symbols on first access (idempotent
// `PlatformLoader.loadCommons()`, same convention as the LLM/STT/VLM workers).

/// Blocking body of [DartBridgeTTS.synthesizeLifecycleProtoAsync]: a plain
/// request→response proto call with no callbacks. Returns the serialized
/// TTSOutput so the main isolate owns the decode.
Uint8List _ttsSynthesizeWorker(Uint8List requestBytes) {
  final bindings = RacNative.bindings;
  final fn = bindings.rac_tts_synthesize_lifecycle_proto;
  if (fn == null) {
    throw UnsupportedError('rac_tts_synthesize_lifecycle_proto is unavailable');
  }

  final requestPtr = DartBridgeProtoUtils.copyBytes(requestBytes);
  final out = calloc<RacProtoBuffer>();
  try {
    bindings.rac_proto_buffer_init(out);
    final code = fn(requestPtr, requestBytes.length, out);
    DartBridgeProtoUtils.ensureSuccess(
      out,
      code,
      'rac_tts_synthesize_lifecycle_proto',
    );
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

/// Runs the Flutter native-port stream helper in a worker isolate. The helper
/// itself posts copied stream bytes to [nativePort] and posts the return code
/// as the final sentinel.
Future<int> _runTtsStreamNativePortWorker(
  Uint8List requestBytes,
  int nativePort,
) => Isolate.run(() => _ttsStreamNativePortWorker(requestBytes, nativePort));

int _ttsStreamNativePortWorker(Uint8List requestBytes, int nativePort) {
  final fn = RacNative
      .bindings
      .ra_flutter_tts_synthesize_stream_lifecycle_proto_native_port;
  if (fn == null) {
    throw UnsupportedError(
      'ra_flutter_tts_synthesize_stream_lifecycle_proto_native_port is unavailable',
    );
  }

  final requestPtr = DartBridgeProtoUtils.copyBytes(requestBytes);
  try {
    return fn(
      requestPtr,
      requestBytes.length,
      nativePort,
      NativeApi.postCObject,
    );
  } finally {
    calloc.free(requestPtr);
  }
}
