// SPDX-License-Identifier: Apache-2.0
//
// dart_bridge_voice_agent.dart — VoiceAgent component bridge.
//
// Wave E cleanup: local DTO classes (VoiceTurnResult, sealed VoiceAgentEvent
// hierarchy, VoiceAgentComponent enum) have been deleted. All public events
// flow through the canonical `VoiceEvent` proto from
// `generated/voice_events.pb.dart`. Per-helper transcribe/synthesize calls
// route through `rac_voice_agent_transcribe_proto` /
// `rac_voice_agent_synthesize_speech_proto` (Wave D-7) instead of the old
// cstring native entrypoints. Composite handle lifecycle uses
// `rac_voice_agent_component_create_proto` /
// `rac_voice_agent_component_destroy_proto` so Dart no longer pins
// individual LLM/STT/TTS/VAD handles.
library;

import 'dart:async';
import 'dart:ffi';
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
  Future<RacHandle> getHandle(
      [voice_agent_pb.VoiceAgentComposeConfig? config]) async {
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

  bool get isSTTLoaded =>
      _checkComponentLoaded(NativeFunctions.voiceAgentIsSTTLoaded);
  bool get isLLMLoaded =>
      _checkComponentLoaded(NativeFunctions.voiceAgentIsLLMLoaded);
  bool get isTTSLoaded =>
      _checkComponentLoaded(NativeFunctions.voiceAgentIsTTSLoaded);

  bool _checkComponentLoaded(int Function(RacHandle, Pointer<Int32>) fn) {
    if (_handle == null) return false;
    try {
      final loadedPtr = calloc<Int32>();
      try {
        final result = fn(_handle!, loadedPtr);
        return result == RAC_SUCCESS && loadedPtr.value == RAC_TRUE;
      } finally {
        calloc.free(loadedPtr);
      }
    } catch (_) {
      return false;
    }
  }

  // MARK: - Model Loading (delegates to commons voice-agent C ABI)

  Future<void> loadSTTModel(String modelPath, String modelId) async {
    final handle = await getHandle();
    final pathPtr = modelPath.toNativeUtf8();
    final idPtr = modelId.toNativeUtf8();
    try {
      final result =
          NativeFunctions.voiceAgentLoadSTTModel(handle, pathPtr, idPtr);
      if (result != RAC_SUCCESS) {
        throw StateError(
          'Failed to load STT model: ${RacResultCode.getMessage(result)}',
        );
      }
      _logger.info('Voice agent STT model loaded: $modelId');
    } finally {
      calloc.free(pathPtr);
      calloc.free(idPtr);
    }
  }

  Future<void> loadLLMModel(String modelPath, String modelId) async {
    final handle = await getHandle();
    final pathPtr = modelPath.toNativeUtf8();
    final idPtr = modelId.toNativeUtf8();
    try {
      final result =
          NativeFunctions.voiceAgentLoadLLMModel(handle, pathPtr, idPtr);
      if (result != RAC_SUCCESS) {
        throw StateError(
          'Failed to load LLM model: ${RacResultCode.getMessage(result)}',
        );
      }
      _logger.info('Voice agent LLM model loaded: $modelId');
    } finally {
      calloc.free(pathPtr);
      calloc.free(idPtr);
    }
  }

  Future<void> loadTTSVoice(String voicePath, String voiceId) async {
    final handle = await getHandle();
    final pathPtr = voicePath.toNativeUtf8();
    final idPtr = voiceId.toNativeUtf8();
    try {
      final result =
          NativeFunctions.voiceAgentLoadTTSVoice(handle, pathPtr, idPtr);
      if (result != RAC_SUCCESS) {
        throw StateError(
          'Failed to load TTS voice: ${RacResultCode.getMessage(result)}',
        );
      }
      _logger.info('Voice agent TTS voice loaded: $voiceId');
    } finally {
      calloc.free(pathPtr);
      calloc.free(idPtr);
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
        voice_events_pb.VoiceAgentComponentStates>(
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
          'Voice agent not ready. Load models and initialize first.');
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

  /// Streaming turn processing — Wave D-7. Invokes
  /// `rac_voice_agent_process_turn_proto` and pipes decoded `VoiceEvent`
  /// bytes onto the returned broadcast stream.
  Stream<voice_events_pb.VoiceEvent> processTurnStream(
    voice_agent_pb.VoiceAgentTurnRequest request,
  ) {
    final controller = StreamController<voice_events_pb.VoiceEvent>();
    NativeCallable<RacVoiceAgentProtoEventCallbackNative>? nativeCb;

    controller
      ..onListen = () async {
        try {
          final handle = await getHandle();
          final fn = RacNative.bindings.rac_voice_agent_process_turn_proto;
          if (fn == null) {
            controller.addError(UnsupportedError(
                'rac_voice_agent_process_turn_proto is unavailable'));
            unawaited(controller.close());
            return;
          }
          // flutter-core-001 fix: use `isolateLocal` (not `.listener`) so the
          // callback fires SYNCHRONOUSLY on the same Dart isolate that
          // invokes `rac_voice_agent_process_turn_proto`. The commons
          // implementation in `voice_agent_d7_abi.cpp` runs the entire turn
          // (STT → LLM → TTS) on the calling thread under `handle->mutex`
          // and invokes `event_callback` for each VoiceEvent inline. With
          // `.listener` mode the callbacks are queued onto the isolate's
          // event loop and the `finally` below closes the controller before
          // any of them drain — every event is silently dropped at
          // `controller.add(...)` on a closed controller. `isolateLocal`
          // ensures every emission lands on the still-open controller
          // before `fn(...)` returns. This mirrors the canonical pattern in
          // `dart_bridge_llm.dart` (`_generateStreamProto`).
          nativeCb = NativeCallable<
              RacVoiceAgentProtoEventCallbackNative>.isolateLocal((
            Pointer<Uint8> bytesPtr,
            int bytesLen,
            Pointer<Void> _,
          ) {
            if (controller.isClosed || bytesLen <= 0 || bytesPtr == nullptr) {
              return;
            }
            final copy = Uint8List.fromList(bytesPtr.asTypedList(bytesLen));
            try {
              controller.add(voice_events_pb.VoiceEvent.fromBuffer(copy));
            } catch (e, st) {
              controller.addError(e, st);
            }
          });
          final bytes = request.writeToBuffer();
          final reqPtr = DartBridgeProtoUtils.copyBytes(bytes);
          try {
            final code = fn(
              handle,
              reqPtr,
              bytes.length,
              nativeCb!.nativeFunction,
              nullptr,
            );
            if (code != 0) {
              controller.addError(
                StateError(
                  'rac_voice_agent_process_turn_proto failed: code=$code',
                ),
              );
            }
          } finally {
            calloc.free(reqPtr);
          }
        } catch (e, st) {
          controller.addError(e, st);
        } finally {
          // CONSOLIDATE-D / flutter-core-001 teardown: with `isolateLocal`
          // all events have already drained by the time `fn` returns, but
          // `rac_voice_agent_proto_quiesce()` is still invoked as a defensive
          // barrier in case a future commons revision posts late events from
          // a worker thread.
          RacNative.bindings.rac_voice_agent_proto_quiesce?.call();
          nativeCb?.close();
          nativeCb = null;
          unawaited(controller.close());
        }
      }
      ..onCancel = () {
        // Same CONSOLIDATE-D ordering as the run() teardown above.
        RacNative.bindings.rac_voice_agent_proto_quiesce?.call();
        nativeCb?.close();
        nativeCb = null;
      };

    return controller.stream;
  }

  /// Transcribe via the voice agent using the Wave D-7 proto helper.
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
          handle, promptPtr, resultPtr);
      if (status != RAC_SUCCESS) {
        throw StateError(
            'Response generation failed: ${RacResultCode.getMessage(status)}');
      }
      return resultPtr.value != nullptr ? resultPtr.value.toDartString() : '';
    } finally {
      calloc.free(promptPtr);
      _safeRacFree(resultPtr.value.cast<Void>());
      calloc.free(resultPtr);
    }
  }

  /// Synthesize speech via the Wave D-7 proto helper. Returns Float32 samples
  /// carved out of the VoiceAgentResult.synthesized_audio WAV payload.
  Future<Float32List> synthesizeSpeech(String text) async {
    final handle = await getHandle();
    final fn = RacNative.bindings.rac_voice_agent_synthesize_speech_proto;
    if (fn == null) {
      throw UnsupportedError(
          'rac_voice_agent_synthesize_speech_proto is unavailable');
    }
    final request =
        voice_agent_pb.VoiceAgentSynthesizeSpeechProtoRequest(text: text);
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

  /// Destroy the voice agent via the Wave D-7 lifecycle-owned destroy proto.
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
