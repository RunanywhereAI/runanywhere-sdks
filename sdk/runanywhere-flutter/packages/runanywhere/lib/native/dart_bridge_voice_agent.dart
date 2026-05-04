/// DartBridge+VoiceAgent
///
/// VoiceAgent component bridge - manages C++ VoiceAgent lifecycle.
/// Mirrors Swift's CppBridge+VoiceAgent.swift pattern.
library dart_bridge_voice_agent;

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
import 'package:runanywhere/native/dart_bridge_llm.dart';
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/dart_bridge_stt.dart';
import 'package:runanywhere/native/dart_bridge_tts.dart';
import 'package:runanywhere/native/dart_bridge_vad.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/native_functions.dart';
import 'package:runanywhere/native/platform_loader.dart';

void _safeRacFree(Pointer<Void> ptr) {
  if (ptr == nullptr) return;

  try {
    NativeFunctions.racFree?.call(ptr);
  } catch (_) {
    // rac_free may not exist in some native builds
  }
}

/// VoiceAgent component bridge for C++ interop.
///
/// Orchestrates LLM, STT, TTS, and VAD components for voice conversations.
/// Provides a unified interface for voice agent operations.
///
/// Usage:
/// ```dart
/// final voiceAgent = DartBridgeVoiceAgent.shared;
/// await voiceAgent.initialize();
/// final session = await voiceAgent.startSession();
/// await session.processAudio(audioData);
/// ```
class DartBridgeVoiceAgent {
  // MARK: - Singleton

  /// Shared instance
  static final DartBridgeVoiceAgent shared = DartBridgeVoiceAgent._();

  DartBridgeVoiceAgent._();

  // MARK: - State

  RacHandle? _handle;
  Future<RacHandle>? _initFuture;
  final _logger = SDKLogger('DartBridge.VoiceAgent');

  /// Event stream controller
  final _eventController = StreamController<VoiceAgentEvent>.broadcast();

  /// Stream of voice agent events
  Stream<VoiceAgentEvent> get events => _eventController.stream;

  // MARK: - Handle Management

  /// Get or create the VoiceAgent handle.
  ///
  /// Requires LLM, STT, TTS, and VAD components to be available.
  /// Uses shared component handles (matches Swift CppBridge+VoiceAgent.swift).
  Future<RacHandle> getHandle() async {
    if (_handle != null) {
      return _handle!;
    }

    if (_initFuture != null) {
      return _initFuture!;
    }

    final completer = Completer<RacHandle>();
    _initFuture = completer.future;

    try {
      // Use shared component handles (matches Swift approach)
      // This allows the voice agent to use already-loaded models from the
      // individual component bridges (STT, LLM, TTS, VAD)
      final llmHandle = DartBridgeLLM.shared.getHandle();
      final sttHandle = DartBridgeSTT.shared.getHandle();
      final ttsHandle = DartBridgeTTS.shared.getHandle();
      final vadHandle = DartBridgeVAD.shared.getHandle();

      _logger.debug(
          'Creating voice agent with shared handles: LLM=$llmHandle, STT=$sttHandle, TTS=$ttsHandle, VAD=$vadHandle');

      final handlePtr = calloc<RacHandle>();
      try {
        final result = NativeFunctions.voiceAgentCreate(
            llmHandle, sttHandle, ttsHandle, vadHandle, handlePtr);

        if (result != RAC_SUCCESS) {
          throw StateError(
            'Failed to create voice agent: ${RacResultCode.getMessage(result)}',
          );
        }

        _handle = handlePtr.value;
        _logger.info('Voice agent created with shared component handles');
        completer.complete(_handle!);
        // Clear _initFuture after completing the completer so that concurrent
        // callers that already hold a reference to completer.future receive the
        // value normally. New callers arriving after this line hit the
        // `_handle != null` fast path.
        _initFuture = null;
        return _handle!;
      } finally {
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

  /// Check if voice agent is ready.
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
    } catch (e) {
      return false;
    }
  }

  /// Check if STT model is loaded.
  bool get isSTTLoaded {
    if (_handle == null) return false;

    try {
      final loadedPtr = calloc<Int32>();
      try {
        final result =
            NativeFunctions.voiceAgentIsSTTLoaded(_handle!, loadedPtr);
        return result == RAC_SUCCESS && loadedPtr.value == RAC_TRUE;
      } finally {
        calloc.free(loadedPtr);
      }
    } catch (e) {
      return false;
    }
  }

  /// Check if LLM model is loaded.
  bool get isLLMLoaded {
    if (_handle == null) return false;

    try {
      final loadedPtr = calloc<Int32>();
      try {
        final result =
            NativeFunctions.voiceAgentIsLLMLoaded(_handle!, loadedPtr);
        return result == RAC_SUCCESS && loadedPtr.value == RAC_TRUE;
      } finally {
        calloc.free(loadedPtr);
      }
    } catch (e) {
      return false;
    }
  }

  /// Check if TTS voice is loaded.
  bool get isTTSLoaded {
    if (_handle == null) return false;

    try {
      final loadedPtr = calloc<Int32>();
      try {
        final result =
            NativeFunctions.voiceAgentIsTTSLoaded(_handle!, loadedPtr);
        return result == RAC_SUCCESS && loadedPtr.value == RAC_TRUE;
      } finally {
        calloc.free(loadedPtr);
      }
    } catch (e) {
      return false;
    }
  }

  // MARK: - Model Loading

  /// Load STT model for voice agent.
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
      _eventController.add(
          const VoiceAgentModelLoadedEvent(component: VoiceAgentComponent.stt));
    } finally {
      calloc.free(pathPtr);
      calloc.free(idPtr);
    }
  }

  /// Load LLM model for voice agent.
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
      _eventController.add(
          const VoiceAgentModelLoadedEvent(component: VoiceAgentComponent.llm));
    } finally {
      calloc.free(pathPtr);
      calloc.free(idPtr);
    }
  }

  /// Load TTS voice for voice agent.
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
      _eventController.add(
          const VoiceAgentModelLoadedEvent(component: VoiceAgentComponent.tts));
    } finally {
      calloc.free(pathPtr);
      calloc.free(idPtr);
    }
  }

  // MARK: - Initialization

  Future<voice_events_pb.VoiceAgentComponentStates> initializeProto(
    voice_agent_pb.VoiceAgentComposeConfig config,
  ) async {
    final handle = await getHandle();
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
      _eventController.add(const VoiceAgentInitializedEvent());
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

  /// Initialize voice agent with loaded models.
  ///
  /// Call after loading all required models (STT, LLM, TTS).
  Future<void> initializeWithLoadedModels() async {
    final handle = await getHandle();

    try {
      final result =
          NativeFunctions.voiceAgentInitializeWithLoadedModels(handle);

      if (result != RAC_SUCCESS) {
        throw StateError(
          'Failed to initialize voice agent: ${RacResultCode.getMessage(result)}',
        );
      }

      _logger.info('Voice agent initialized with loaded models');
      _eventController.add(const VoiceAgentInitializedEvent());
    } catch (e) {
      _logger.error('Failed to initialize voice agent: $e');
      rethrow;
    }
  }

  // MARK: - Voice Turn Processing

  /// Process a complete voice turn.
  ///
  /// [audioData] - Complete audio data for the user's utterance (PCM16 bytes).
  ///
  /// Returns the voice turn result with transcription, response, and audio.
  /// NOTE: This runs the entire STT -> LLM -> TTS pipeline, so it should be
  /// called from a background isolate to avoid blocking the UI.
  Future<VoiceTurnResult> processVoiceTurn(Uint8List audioData) async {
    final handle = await getHandle();

    if (!isReady) {
      throw StateError(
          'Voice agent not ready. Load models and initialize first.');
    }

    // Capture handle address before entering isolate — passing the raw Pointer
    // across an isolate boundary is unsafe; pass the address and reconstruct it.
    final handleAddress = handle.address;
    return Isolate.run(
        () => _processVoiceTurnInIsolate(handleAddress, audioData));
  }

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

  /// Static helper for processing voice turn in an isolate.
  /// The C++ API expects raw audio bytes (PCM16), not float samples.
  /// Must be static/top-level for Isolate.run().
  static Future<VoiceTurnResult> _processVoiceTurnInIsolate(
    int handleAddress,
    Uint8List audioData,
  ) async {
    final handle = RacHandle.fromAddress(handleAddress);

    // Allocate native memory for audio data (raw PCM16 bytes)
    final audioPtr = calloc<Uint8>(audioData.length);
    final resultPtr = calloc<RacVoiceAgentResultStruct>();

    try {
      // Efficient bulk copy of audio bytes
      audioPtr.asTypedList(audioData.length).setAll(0, audioData);

      final status = _processVoiceTurnFn(
          handle, audioPtr.cast<Void>(), audioData.length, resultPtr);

      if (status != RAC_SUCCESS) {
        throw StateError(
          'Voice turn processing failed: ${RacResultCode.getMessage(status)}',
        );
      }

      // Parse result while still in isolate (before freeing memory)
      return _parseVoiceTurnResultStatic(resultPtr.ref);
    } finally {
      // Free audio data
      calloc.free(audioPtr);

      // Free result struct - the C++ side allocates strings/audio that need freeing
      try {
        _voiceAgentResultFreeFn?.call(resultPtr);
      } catch (e) {
        // Function may not exist, just free the struct
      }
      calloc.free(resultPtr);
    }
  }

  /// Static helper to parse voice turn result (can be called from isolate).
  /// The C++ voice agent already converts TTS output to WAV format internally
  /// using rac_audio_float32_to_wav, so synthesized_audio is WAV data.
  static VoiceTurnResult _parseVoiceTurnResultStatic(
    RacVoiceAgentResultStruct result,
  ) {
    final transcription = result.transcription != nullptr
        ? result.transcription.toDartString()
        : '';
    final response =
        result.response != nullptr ? result.response.toDartString() : '';

    // The synthesized audio is WAV format (C++ voice agent converts Float32 to WAV)
    // Just copy the raw bytes - no conversion needed
    Uint8List audioWavData;
    if (result.synthesizedAudioSize > 0 && result.synthesizedAudio != nullptr) {
      audioWavData = Uint8List.fromList(
        result.synthesizedAudio
            .cast<Uint8>()
            .asTypedList(result.synthesizedAudioSize),
      );
    } else {
      audioWavData = Uint8List(0);
    }

    return VoiceTurnResult(
      transcription: transcription,
      response: response,
      audioWavData: audioWavData,
      // Duration fields not available in C++ struct - use 0
      sttDurationMs: 0,
      llmDurationMs: 0,
      ttsDurationMs: 0,
    );
  }

  /// Transcribe audio using voice agent.
  /// Audio data should be raw PCM16 bytes.
  Future<String> transcribe(Uint8List audioData) async {
    final handle = await getHandle();

    // Pass raw audio bytes - C++ handles conversion
    final audioPtr = calloc<Uint8>(audioData.length);
    final resultPtr = calloc<Pointer<Utf8>>();

    try {
      // Efficient bulk copy of audio bytes
      audioPtr.asTypedList(audioData.length).setAll(0, audioData);

      final status = NativeFunctions.voiceAgentTranscribe(
          handle, audioPtr.cast<Void>(), audioData.length, resultPtr);

      if (status != RAC_SUCCESS) {
        throw StateError(
            'Transcription failed: ${RacResultCode.getMessage(status)}');
      }

      return resultPtr.value != nullptr ? resultPtr.value.toDartString() : '';
    } finally {
      calloc.free(audioPtr);
      _safeRacFree(resultPtr.value.cast<Void>());
      calloc.free(resultPtr);
    }
  }

  /// Generate LLM response using voice agent.
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

  /// Synthesize speech using voice agent.
  /// Returns Float32 audio samples.
  Future<Float32List> synthesizeSpeech(String text) async {
    final handle = await getHandle();

    final textPtr = text.toNativeUtf8();
    final audioPtr = calloc<Pointer<Void>>();
    final audioSizePtr = calloc<IntPtr>();

    try {
      final status = NativeFunctions.voiceAgentSynthesizeSpeech(
          handle, textPtr, audioPtr, audioSizePtr);

      if (status != RAC_SUCCESS) {
        throw StateError(
            'Speech synthesis failed: ${RacResultCode.getMessage(status)}');
      }

      // Audio data is float32 samples (4 bytes per sample)
      final audioSize = audioSizePtr.value;
      final numSamples = audioSize ~/ 4;
      if (numSamples > 0 && audioPtr.value != nullptr) {
        final samples = audioPtr.value.cast<Float>().asTypedList(numSamples);
        return Float32List.fromList(samples);
      }
      return Float32List(0);
    } finally {
      calloc.free(textPtr);
      // Free the audio data allocated by C++
      _safeRacFree(audioPtr.value);
      calloc.free(audioPtr);
      calloc.free(audioSizePtr);
    }
  }

  // MARK: - Cleanup

  /// Cleanup voice agent.
  void cleanup() {
    if (_handle == null) return;

    try {
      NativeFunctions.voiceAgentCleanup(_handle!);
      _logger.info('Voice agent cleaned up');
    } catch (e) {
      _logger.error('Failed to cleanup voice agent: $e');
    }
  }

  /// Destroy voice agent.
  void destroy() {
    if (_handle != null) {
      try {
        NativeFunctions.voiceAgentDestroy(_handle!);
        _handle = null;
        _logger.debug('Voice agent destroyed');
      } catch (e) {
        _logger.error('Failed to destroy voice agent: $e');
      }
    }
  }

  /// Dispose resources.
  void dispose() {
    destroy();
    unawaited(_eventController.close());
  }

  // MARK: - Helpers
}

// MARK: - Result Types

/// Result from a complete voice turn.
/// Audio is in WAV format (C++ voice agent converts Float32 TTS output to WAV).
class VoiceTurnResult {
  final String transcription;
  final String response;

  /// WAV-formatted audio data ready for playback
  final Uint8List audioWavData;
  final int sttDurationMs;
  final int llmDurationMs;
  final int ttsDurationMs;

  const VoiceTurnResult({
    required this.transcription,
    required this.response,
    required this.audioWavData,
    required this.sttDurationMs,
    required this.llmDurationMs,
    required this.ttsDurationMs,
  });

  int get totalDurationMs => sttDurationMs + llmDurationMs + ttsDurationMs;
}

// MARK: - Events

/// Voice agent event base.
sealed class VoiceAgentEvent {
  const VoiceAgentEvent();
}

/// Voice agent initialized.
class VoiceAgentInitializedEvent extends VoiceAgentEvent {
  const VoiceAgentInitializedEvent();
}

/// Component types that can emit a model-loaded event on the voice agent.
enum VoiceAgentComponent { stt, llm, tts }

/// Voice agent model loaded.
class VoiceAgentModelLoadedEvent extends VoiceAgentEvent {
  final VoiceAgentComponent component;
  const VoiceAgentModelLoadedEvent({required this.component});
}

/// Voice agent turn started.
class VoiceAgentTurnStartedEvent extends VoiceAgentEvent {
  const VoiceAgentTurnStartedEvent();
}

/// Voice agent turn completed.
class VoiceAgentTurnCompletedEvent extends VoiceAgentEvent {
  final VoiceTurnResult result;
  const VoiceAgentTurnCompletedEvent({required this.result});
}

/// Voice agent error.
class VoiceAgentErrorEvent extends VoiceAgentEvent {
  final String error;
  const VoiceAgentErrorEvent({required this.error});
}

// MARK: - FFI Structs

/// FFI struct for voice agent result (matches rac_voice_agent_result_t).
/// MUST match exact layout of C struct:
/// typedef struct rac_voice_agent_result {
///     rac_bool_t speech_detected;
///     char* transcription;
///     char* response;
///     void* synthesized_audio;
///     size_t synthesized_audio_size;
/// } rac_voice_agent_result_t;
final class RacVoiceAgentResultStruct extends Struct {
  @Int32()
  external int speechDetected; // rac_bool_t

  external Pointer<Utf8> transcription; // char*

  external Pointer<Utf8> response; // char*

  external Pointer<Void> synthesizedAudio; // void* (raw audio bytes)

  @IntPtr()
  external int synthesizedAudioSize; // size_t (size in bytes)
}

// MARK: - Isolate-scoped FFI caches

// These are intentionally top-level statics so each isolate initializes them
// once on first use. This keeps symbol lookups out of hot paths while preserving
// the existing isolate execution model.
final DynamicLibrary _voiceAgentLib = PlatformLoader.loadCommons();

final int Function(
  RacHandle,
  Pointer<Void>,
  int,
  Pointer<RacVoiceAgentResultStruct>,
) _processVoiceTurnFn = _voiceAgentLib.lookupFunction<
        Int32 Function(RacHandle, Pointer<Void>, IntPtr,
            Pointer<RacVoiceAgentResultStruct>),
        int Function(
            RacHandle, Pointer<Void>, int, Pointer<RacVoiceAgentResultStruct>)>(
    'rac_voice_agent_process_voice_turn');

final void Function(Pointer<RacVoiceAgentResultStruct>)?
    _voiceAgentResultFreeFn = (() {
  try {
    return _voiceAgentLib.lookupFunction<
        Void Function(Pointer<RacVoiceAgentResultStruct>),
        void Function(Pointer<RacVoiceAgentResultStruct>)>(
      'rac_voice_agent_result_free',
    );
  } catch (_) {
    return null;
  }
})();
