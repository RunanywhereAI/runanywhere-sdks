// SPDX-License-Identifier: Apache-2.0
//
// dart_bridge_voice_agent.dart — VoiceAgent component bridge.
//
// Local DTO classes (VoiceTurnResult, sealed VoiceAgentEvent
// hierarchy, VoiceAgentComponent enum) have been deleted. All public events
// flow through the canonical `VoiceEvent` proto from
// `generated/voice_events.pb.dart`. Per-helper transcribe/synthesize calls
// route through `rac_voice_agent_transcribe_proto` /
// `rac_voice_agent_synthesize_speech_proto` instead of the old
// cstring native entrypoints. Composite handle lifecycle uses
// `rac_voice_agent_component_create_proto` /
// `rac_voice_agent_component_destroy_proto` so Dart no longer pins
// individual LLM/STT/TTS/VAD handles.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/voice_agent_service.pb.dart'
    as voice_agent_pb;
import 'package:runanywhere/generated/voice_events.pb.dart' as voice_events_pb;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/native_functions.dart';
import 'package:runanywhere/native/types/basic_types.dart';

/// VoiceAgent component bridge for the commons C ABI.
///
/// The handle is created through
/// `rac_voice_agent_component_create_proto(VoiceAgentComposeConfig)` so
/// commons owns the lifecycle — Flutter does not pin LLM/STT/TTS/VAD
/// component handles manually.
class DartBridgeVoiceAgent {
  DartBridgeVoiceAgent._();

  static final DartBridgeVoiceAgent shared = DartBridgeVoiceAgent._();

  final _logger = SDKLogger('DartBridge.VoiceAgent');

  RacHandle? _handle;
  Future<RacHandle>? _initFuture;

  /// Default empty compose config is used if [getHandle] is invoked
  /// without an explicit [initializeProto] first — matches Swift's
  /// "compose on first access with defaults" behavior.
  ///
  /// No-yield invariant: the synchronous prefix below (read `_handle`,
  /// read `_initFuture`, assign `_initFuture`) executes within a single
  /// microtask — Dart's cooperative scheduler cannot interleave another
  /// microtask at a non-`await` point. Concurrent `getHandle()` calls
  /// therefore cannot both observe `_initFuture == null` and each create
  /// a separate `Completer`, so only one C ABI
  /// `rac_voice_agent_component_create_proto` call is issued per
  /// lifecycle. Mirrors the `.installing` state gate in Swift's
  /// `HandleFanOutAttachRole` / `HandleFanOut.attach`. Do NOT insert an
  /// `await` between the null-checks and the `_initFuture` assignment —
  /// that would open a real race window.
  Future<RacHandle> getHandle([
    voice_agent_pb.VoiceAgentComposeConfig? config,
  ]) async {
    if (_handle != null) return _handle!;
    if (_initFuture != null) return _initFuture!;

    final completer = Completer<RacHandle>();
    _initFuture = completer.future;

    try {
      final createFn =
          RacNative.bindings.rac_voice_agent_component_create_proto;
      if (createFn == null) {
        throw UnsupportedError(
          'rac_voice_agent_component_create_proto is unavailable',
        );
      }

      final cfg = config ?? voice_agent_pb.VoiceAgentComposeConfig();
      final bytes = cfg.writeToBuffer();
      final reqPtr = DartBridgeProtoUtils.copyBytes(bytes);
      final handlePtr = calloc<Pointer<Void>>();

      try {
        final code = createFn(reqPtr, bytes.length, handlePtr);
        if (code != 0 || handlePtr.value == nullptr) {
          throw StateError(
            'rac_voice_agent_component_create_proto failed: code=$code',
          );
        }
        _handle = handlePtr.value;
        _logger.info('Voice agent component created via proto lifecycle');
        completer.complete(_handle!);
        _initFuture = null;
        return _handle!;
      } finally {
        calloc.free(reqPtr);
        calloc.free(handlePtr);
      }
    } catch (e, st) {
      _logger.error('Failed to create voice agent handle: $e');
      if (!completer.isCompleted) {
        completer.completeError(e, st);
      }
      _initFuture = null;
      rethrow;
    }
  }

  // MARK: - State Queries

  bool get isReady {
    if (_handle == null) return false;
    try {
      final readyPtr = calloc<Int32>();
      try {
        final result = NativeFunctions.voiceAgentIsReady(_handle!, readyPtr);
        return result == RAC_SUCCESS && readyPtr.value == RAC_TRUE;
      } finally {
        calloc.free(readyPtr);
      }
    } catch (_) {
      return false;
    }
  }

  // MARK: - Initialization

  Future<voice_events_pb.VoiceAgentComponentStates> initializeProto(
    voice_agent_pb.VoiceAgentComposeConfig config,
  ) async {
    final handle = await getHandle(config);
    final fn = RacNative.bindings.rac_voice_agent_initialize_proto;
    if (fn == null) {
      throw UnsupportedError('rac_voice_agent_initialize_proto is unavailable');
    }

    final bytes = config.writeToBuffer();
    final ptr = DartBridgeProtoUtils.copyBytes(bytes);
    final out = calloc<RacProtoBuffer>();
    final bindings = RacNative.bindings;

    try {
      bindings.rac_proto_buffer_init(out);
      final code = fn(handle, ptr, bytes.length, out);
      DartBridgeProtoUtils.ensureSuccess(
        out,
        code,
        'rac_voice_agent_initialize_proto',
      );
      return DartBridgeProtoUtils.decodeBuffer(
        out,
        voice_events_pb.VoiceAgentComponentStates.fromBuffer,
      );
    } finally {
      bindings.rac_proto_buffer_free(out);
      calloc.free(ptr);
      calloc.free(out);
    }
  }

  Future<voice_events_pb.VoiceAgentComponentStates>
  componentStatesProto() async {
    final handle = await getHandle();
    final fn = RacNative.bindings.rac_voice_agent_component_states_proto;
    if (fn == null) {
      throw UnsupportedError(
        'rac_voice_agent_component_states_proto is unavailable',
      );
    }
    return DartBridgeProtoUtils.callOut<
      voice_events_pb.VoiceAgentComponentStates
    >(
      invoke: (out) => fn(handle, out),
      decode: voice_events_pb.VoiceAgentComponentStates.fromBuffer,
      symbol: 'rac_voice_agent_component_states_proto',
    );
  }

  Future<void> initializeWithLoadedModels() async {
    final handle = await getHandle();
    final result = NativeFunctions.voiceAgentInitializeWithLoadedModels(handle);
    if (result != RAC_SUCCESS) {
      throw StateError(
        'Failed to initialize voice agent: ${RacResultCode.getMessage(result)}',
      );
    }
    _logger.info('Voice agent initialized with loaded models');
  }

  // MARK: - Voice Turn Processing

  /// Synchronous one-shot voice turn → full `VoiceAgentResult` proto.
  Future<voice_agent_pb.VoiceAgentResult> processVoiceTurnProto(
    Uint8List audioData,
  ) async {
    final handle = await getHandle();
    if (!isReady) {
      throw StateError(
        'Voice agent not ready. Load models and initialize first.',
      );
    }

    final fn = RacNative.bindings.rac_voice_agent_process_voice_turn_proto;
    if (fn == null) {
      throw UnsupportedError(
        'rac_voice_agent_process_voice_turn_proto is unavailable',
      );
    }

    final audioPtr = calloc<Uint8>(audioData.isEmpty ? 1 : audioData.length);
    final out = calloc<RacProtoBuffer>();
    final bindings = RacNative.bindings;

    try {
      if (audioData.isNotEmpty) {
        audioPtr.asTypedList(audioData.length).setAll(0, audioData);
      }
      bindings.rac_proto_buffer_init(out);
      final code = fn(handle, audioPtr.cast<Void>(), audioData.length, out);
      DartBridgeProtoUtils.ensureSuccess(
        out,
        code,
        'rac_voice_agent_process_voice_turn_proto',
      );
      return DartBridgeProtoUtils.decodeBuffer(
        out,
        voice_agent_pb.VoiceAgentResult.fromBuffer,
      );
    } finally {
      bindings.rac_proto_buffer_free(out);
      calloc.free(audioPtr);
      calloc.free(out);
    }
  }

  /// Streaming turn processing. Invokes `rac_voice_agent_process_turn_proto`
  /// on a short-lived WORKER isolate and pipes each decoded `VoiceEvent` onto
  /// the returned stream as it is emitted.
  ///
  /// Why a worker isolate: commons runs the ENTIRE turn (STT → LLM → TTS)
  /// synchronously on the calling thread under `handle->mutex`, invoking the
  /// event callback inline per VoiceEvent. Run on the MAIN isolate that blocks
  /// the UI for the whole turn AND — because Dart can't pump the stream's
  /// listener until the blocking FFI call returns — every event (including the
  /// early `userSaid` transcript) is only delivered AFTER the LLM+TTS finish,
  /// so the transcript appears seconds late. Running on a worker isolate (the
  /// canonical pattern from `dart_bridge_llm.generateStreamProto`) lets the
  /// stream deliver incrementally. On iOS and Android, the Flutter plugin
  /// exports a native-port helper that copies event bytes inside the C callback
  /// and posts owned `Uint8List` messages here, which is safe if a composed
  /// backend invokes callbacks from native worker threads. Older or unsupported
  /// binaries fall back to the worker-owned `isolateLocal` path, valid only for
  /// same-thread callback delivery. Mirrors Kotlin's `Dispatchers.IO` placement
  /// of the same single-call ABI.
  Stream<voice_events_pb.VoiceEvent> processTurnStream(
    voice_agent_pb.VoiceAgentTurnRequest request,
  ) {
    final bindings = RacNative.bindings;
    final hasProcessTurn =
        bindings.rac_voice_agent_process_turn_proto != null ||
        bindings.ra_flutter_voice_agent_process_turn_proto_native_port != null;
    if (!hasProcessTurn) {
      return Stream<voice_events_pb.VoiceEvent>.error(
        UnsupportedError('rac_voice_agent_process_turn_proto is unavailable'),
      );
    }

    final controller = StreamController<voice_events_pb.VoiceEvent>(
      sync: false,
    );
    final receivePort = ReceivePort();
    var sawError = false;
    var tornDown = false;

    void teardown() {
      if (tornDown) return;
      tornDown = true;
      receivePort.close();
    }

    receivePort.listen((Object? message) {
      if (message is Uint8List) {
        // One serialized VoiceEvent, copied in the worker's synchronous
        // callback, delivered over the port in emission order.
        if (controller.isClosed) return;
        try {
          controller.add(voice_events_pb.VoiceEvent.fromBuffer(message));
        } catch (e, st) {
          sawError = true;
          controller.addError(e, st);
        }
      } else if (message is int) {
        // rc sentinel — always LAST (same port as events ⇒ FIFO).
        if (message != 0 && !sawError && !controller.isClosed) {
          controller.addError(
            StateError(
              'rac_voice_agent_process_turn_proto failed: code=$message',
            ),
          );
        }
        if (!controller.isClosed) {
          unawaited(controller.close());
        }
        teardown();
      }
    });

    controller
      ..onListen = () async {
        try {
          final handle = await getHandle();
          final requestBytes = request.writeToBuffer();
          final nativePortFn = RacNative
              .bindings
              .ra_flutter_voice_agent_process_turn_proto_native_port;
          final worker = nativePortFn != null
              ? _runVoiceTurnNativePortWorker(
                  handle.address,
                  requestBytes,
                  receivePort.sendPort.nativePort,
                )
              : _runVoiceTurnWorker(
                  handle.address,
                  requestBytes,
                  receivePort.sendPort,
                );
          unawaited(
            worker.catchError((Object e, StackTrace st) {
              // Worker isolate crashed before the rc sentinel.
              if (!controller.isClosed) {
                controller.addError(e, st);
                unawaited(controller.close());
              }
              teardown();
              return 0;
            }),
          );
        } catch (e, st) {
          if (!controller.isClosed) {
            controller.addError(e, st);
            unawaited(controller.close());
          }
          teardown();
        }
      }
      ..onCancel = teardown;

    return controller.stream;
  }

  /// Transcribe via the voice agent using the proto helper.
  Future<String> transcribe(Uint8List audioData) async {
    final handle = await getHandle();
    final fn = RacNative.bindings.rac_voice_agent_transcribe_proto;
    if (fn == null) {
      throw UnsupportedError('rac_voice_agent_transcribe_proto is unavailable');
    }
    final request = voice_agent_pb.VoiceAgentTranscribeProtoRequest(
      audioData: audioData,
    );
    final bytes = request.writeToBuffer();
    final reqPtr = DartBridgeProtoUtils.copyBytes(bytes);
    final out = calloc<RacProtoBuffer>();
    final bindings = RacNative.bindings;

    try {
      bindings.rac_proto_buffer_init(out);
      final code = fn(handle, reqPtr, bytes.length, out);
      DartBridgeProtoUtils.ensureSuccess(
        out,
        code,
        'rac_voice_agent_transcribe_proto',
      );
      // Commons returns a VoiceAgentResult proto carrying the transcription.
      final result = DartBridgeProtoUtils.decodeBuffer(
        out,
        voice_agent_pb.VoiceAgentResult.fromBuffer,
      );
      return result.transcription;
    } finally {
      bindings.rac_proto_buffer_free(out);
      calloc.free(reqPtr);
      calloc.free(out);
    }
  }

  /// Generate response via the voice agent. The LLM-only response remains a
  /// string — no proto envelope on the C side.
  Future<String> generateResponse(String prompt) async {
    final handle = await getHandle();
    final promptPtr = prompt.toNativeUtf8();
    final resultPtr = calloc<Pointer<Utf8>>();
    try {
      final status = NativeFunctions.voiceAgentGenerateResponse(
        handle,
        promptPtr,
        resultPtr,
      );
      if (status != RAC_SUCCESS) {
        throw StateError(
          'Response generation failed: ${RacResultCode.getMessage(status)}',
        );
      }
      return resultPtr.value != nullptr ? resultPtr.value.toDartString() : '';
    } finally {
      calloc.free(promptPtr);
      _safeRacFree(resultPtr.value.cast<Void>());
      calloc.free(resultPtr);
    }
  }

  /// Synthesize speech via the proto helper. Returns Float32 samples
  /// carved out of the VoiceAgentResult.synthesized_audio WAV payload.
  Future<Float32List> synthesizeSpeech(String text) async {
    final handle = await getHandle();
    final fn = RacNative.bindings.rac_voice_agent_synthesize_speech_proto;
    if (fn == null) {
      throw UnsupportedError(
        'rac_voice_agent_synthesize_speech_proto is unavailable',
      );
    }
    final request = voice_agent_pb.VoiceAgentSynthesizeSpeechProtoRequest(
      text: text,
    );
    final bytes = request.writeToBuffer();
    final reqPtr = DartBridgeProtoUtils.copyBytes(bytes);
    final out = calloc<RacProtoBuffer>();
    final bindings = RacNative.bindings;

    try {
      bindings.rac_proto_buffer_init(out);
      final code = fn(handle, reqPtr, bytes.length, out);
      DartBridgeProtoUtils.ensureSuccess(
        out,
        code,
        'rac_voice_agent_synthesize_speech_proto',
      );
      final result = DartBridgeProtoUtils.decodeBuffer(
        out,
        voice_agent_pb.VoiceAgentResult.fromBuffer,
      );
      if (result.synthesizedAudio.isEmpty) return Float32List(0);
      // Commons emits PCM float32 or WAV — assume WAV if header present.
      final audio = result.synthesizedAudio;
      if (audio.length >= 44 &&
          audio[0] == 0x52 &&
          audio[1] == 0x49 &&
          audio[2] == 0x46 &&
          audio[3] == 0x46) {
        // RIFF/WAV header — strip and interpret as float32 samples.
        final pcm = audio.sublist(44);
        final samples = Float32List(pcm.length ~/ 4);
        final bd = ByteData.sublistView(Uint8List.fromList(pcm));
        for (var i = 0; i < samples.length; i++) {
          samples[i] = bd.getFloat32(i * 4, Endian.little);
        }
        return samples;
      }
      // Assume raw float32 samples.
      final bd = ByteData.sublistView(Uint8List.fromList(audio));
      final samples = Float32List(audio.length ~/ 4);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = bd.getFloat32(i * 4, Endian.little);
      }
      return samples;
    } finally {
      bindings.rac_proto_buffer_free(out);
      calloc.free(reqPtr);
      calloc.free(out);
    }
  }

  // MARK: - Cleanup

  void cleanup() {
    if (_handle == null) return;
    try {
      NativeFunctions.voiceAgentCleanup(_handle!);
      _logger.info('Voice agent cleaned up');
    } catch (e) {
      _logger.error('Failed to cleanup voice agent: $e');
    }
  }

  /// Destroy the voice agent via the lifecycle-owned destroy proto.
  void destroy() {
    if (_handle == null) return;
    final fn = RacNative.bindings.rac_voice_agent_component_destroy_proto;
    try {
      if (fn != null) {
        fn(_handle!);
      } else {
        NativeFunctions.voiceAgentDestroy(_handle!);
      }
      _handle = null;
      _logger.debug('Voice agent destroyed');
    } catch (e) {
      _logger.error('Failed to destroy voice agent: $e');
    }
  }

  void dispose() {
    destroy();
  }
}

void _safeRacFree(Pointer<Void> ptr) {
  if (ptr == nullptr) return;
  try {
    NativeFunctions.racFree?.call(ptr);
  } catch (_) {
    // rac_free may not exist in some native builds
  }
}

// MARK: - Voice-turn worker isolate
//
// Top-level so the `Isolate.run` closure captures ONLY sendable values
// (int handle address + Uint8List + SendPort). Mirrors
// `dart_bridge_llm._runLlmStreamWorker` / `_llmStreamWorker`. The voice turn
// (STT → LLM → TTS) is inference over already-loaded models — the same class
// of work STT/VLM/RAG/embeddings already run on worker isolates here — and
// its only Dart-bound callbacks (SDK events, logging, telemetry HTTP wakeup)
// are `.listener` (cross-isolate safe). The `Pointer.fromFunction`
// platform-adapter trampolines that SIGABRT under `Isolate.run` (model LOAD)
// are not invoked during a turn; if a future commons change adds one to this
// path, fix it in the platform adapter/native bridge layer before moving the
// turn back to the main isolate.

/// Runs [_voiceTurnWorker] in a worker isolate. Hoisted to top level so the
/// closure captures only its three sendable parameters.
Future<int> _runVoiceTurnWorker(
  int handleAddress,
  Uint8List requestBytes,
  SendPort port,
) => Isolate.run(() => _voiceTurnWorker(handleAddress, requestBytes, port));

/// Runs the Flutter native-port stream helper in a worker isolate. The helper
/// itself posts copied voice-event bytes to [nativePort] and posts the return
/// code as the final sentinel.
Future<int> _runVoiceTurnNativePortWorker(
  int handleAddress,
  Uint8List requestBytes,
  int nativePort,
) => Isolate.run(
  () => _voiceTurnNativePortWorker(handleAddress, requestBytes, nativePort),
);

int _voiceTurnNativePortWorker(
  int handleAddress,
  Uint8List requestBytes,
  int nativePort,
) {
  final fn =
      RacNative.bindings.ra_flutter_voice_agent_process_turn_proto_native_port;
  if (fn == null) {
    throw UnsupportedError(
      'ra_flutter_voice_agent_process_turn_proto_native_port is unavailable',
    );
  }

  final handle = Pointer<Void>.fromAddress(handleAddress);
  final requestPtr = DartBridgeProtoUtils.copyBytes(requestBytes);
  try {
    return fn(
      handle,
      requestPtr,
      requestBytes.length,
      nativePort,
      NativeApi.postCObject,
    );
  } finally {
    calloc.free(requestPtr);
  }
}

/// Blocking body of [DartBridgeVoiceAgent.processTurnStream]. The worker-owned
/// `isolateLocal` callback fires synchronously per VoiceEvent (commons passes
/// a pointer into a reused scratch buffer, so the bytes are copied INSIDE the
/// callback before they cross the isolate). The rc is sent LAST on the same
/// port, FIFO-ordered after every event.
int _voiceTurnWorker(int handleAddress, Uint8List requestBytes, SendPort port) {
  final bindings = RacNative.bindings;
  final fn = bindings.rac_voice_agent_process_turn_proto;
  if (fn == null) {
    throw UnsupportedError('rac_voice_agent_process_turn_proto is unavailable');
  }

  final handle = Pointer<Void>.fromAddress(handleAddress);
  final requestPtr = DartBridgeProtoUtils.copyBytes(requestBytes);
  NativeCallable<RacVoiceAgentProtoEventCallbackNative>? callback;
  try {
    callback =
        NativeCallable<RacVoiceAgentProtoEventCallbackNative>.isolateLocal((
          Pointer<Uint8> bytesPtr,
          int bytesLen,
          Pointer<Void> _,
        ) {
          if (bytesPtr == nullptr || bytesLen <= 0) return;
          // Copy inside the synchronous callback — commons reuses the scratch
          // buffer the moment we return. The copy is what crosses isolates.
          port.send(Uint8List.fromList(bytesPtr.asTypedList(bytesLen)));
        });

    final rc = fn(
      handle,
      requestPtr,
      requestBytes.length,
      callback.nativeFunction,
      nullptr,
    );
    port.send(rc);
    return rc;
  } finally {
    bindings.rac_voice_agent_proto_quiesce?.call();
    callback?.close();
    calloc.free(requestPtr);
  }
}
