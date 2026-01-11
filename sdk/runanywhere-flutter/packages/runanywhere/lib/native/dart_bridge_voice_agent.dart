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

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_llm.dart';
import 'package:runanywhere/native/dart_bridge_stt.dart';
import 'package:runanywhere/native/dart_bridge_tts.dart';
import 'package:runanywhere/native/dart_bridge_vad.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// Voice agent handle type (opaque pointer to rac_voice_agent struct).
typedef RacVoiceAgentHandle = Pointer<Void>;

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

  RacVoiceAgentHandle? _handle;
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
  Future<RacVoiceAgentHandle> getHandle() async {
    if (_handle != null) {
      return _handle!;
    }

    try {
      final lib = PlatformLoader.loadCommons();

      // Use shared component handles (matches Swift approach)
      // This allows the voice agent to use already-loaded models from the
      // individual component bridges (STT, LLM, TTS, VAD)
      final llmHandle = DartBridgeLLM.shared.getHandle();
      final sttHandle = DartBridgeSTT.shared.getHandle();
      final ttsHandle = DartBridgeTTS.shared.getHandle();
      final vadHandle = DartBridgeVAD.shared.getHandle();

      _logger.debug(
          'Creating voice agent with shared handles: LLM=$llmHandle, STT=$sttHandle, TTS=$ttsHandle, VAD=$vadHandle');

      final create = lib.lookupFunction<
          Int32 Function(RacHandle, RacHandle, RacHandle, RacHandle,
              Pointer<RacVoiceAgentHandle>),
          int Function(RacHandle, RacHandle, RacHandle, RacHandle,
              Pointer<RacVoiceAgentHandle>)>('rac_voice_agent_create');

      final handlePtr = calloc<RacVoiceAgentHandle>();
      try {
        final result =
            create(llmHandle, sttHandle, ttsHandle, vadHandle, handlePtr);

        if (result != RAC_SUCCESS) {
          throw StateError(
            'Failed to create voice agent: ${RacResultCode.getMessage(result)}',
          );
        }

        _handle = handlePtr.value;
        _logger.info('Voice agent created with shared component handles');
        return _handle!;
      } finally {
        calloc.free(handlePtr);
      }
    } catch (e) {
      _logger.error('Failed to create voice agent handle: $e');
      rethrow;
    }
  }

  // MARK: - State Queries

  /// Check if voice agent is ready.
  bool get isReady {
    if (_handle == null) return false;

    try {
      final lib = PlatformLoader.loadCommons();
      final isReadyFn = lib.lookupFunction<
          Int32 Function(RacVoiceAgentHandle, Pointer<Int32>),
          int Function(
              RacVoiceAgentHandle, Pointer<Int32>)>('rac_voice_agent_is_ready');

      final readyPtr = calloc<Int32>();
      try {
        final result = isReadyFn(_handle!, readyPtr);
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
      final lib = PlatformLoader.loadCommons();
      final isLoadedFn = lib.lookupFunction<
          Int32 Function(RacVoiceAgentHandle, Pointer<Int32>),
          int Function(RacVoiceAgentHandle,
              Pointer<Int32>)>('rac_voice_agent_is_stt_loaded');

      final loadedPtr = calloc<Int32>();
      try {
        final result = isLoadedFn(_handle!, loadedPtr);
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
      final lib = PlatformLoader.loadCommons();
      final isLoadedFn = lib.lookupFunction<
          Int32 Function(RacVoiceAgentHandle, Pointer<Int32>),
          int Function(RacVoiceAgentHandle,
              Pointer<Int32>)>('rac_voice_agent_is_llm_loaded');

      final loadedPtr = calloc<Int32>();
      try {
        final result = isLoadedFn(_handle!, loadedPtr);
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
      final lib = PlatformLoader.loadCommons();
      final isLoadedFn = lib.lookupFunction<
          Int32 Function(RacVoiceAgentHandle, Pointer<Int32>),
          int Function(RacVoiceAgentHandle,
              Pointer<Int32>)>('rac_voice_agent_is_tts_loaded');

      final loadedPtr = calloc<Int32>();
      try {
        final result = isLoadedFn(_handle!, loadedPtr);
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
      final lib = PlatformLoader.loadCommons();
      final loadFn = lib.lookupFunction<
          Int32 Function(RacVoiceAgentHandle, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacVoiceAgentHandle, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_voice_agent_load_stt_model');

      final result = loadFn(handle, pathPtr, idPtr);

      if (result != RAC_SUCCESS) {
        throw StateError(
          'Failed to load STT model: ${RacResultCode.getMessage(result)}',
        );
      }

      _logger.info('Voice agent STT model loaded: $modelId');
      _eventController.add(const VoiceAgentModelLoadedEvent(component: 'stt'));
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
      final lib = PlatformLoader.loadCommons();
      final loadFn = lib.lookupFunction<
          Int32 Function(RacVoiceAgentHandle, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacVoiceAgentHandle, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_voice_agent_load_llm_model');

      final result = loadFn(handle, pathPtr, idPtr);

      if (result != RAC_SUCCESS) {
        throw StateError(
          'Failed to load LLM model: ${RacResultCode.getMessage(result)}',
        );
      }

      _logger.info('Voice agent LLM model loaded: $modelId');
      _eventController.add(const VoiceAgentModelLoadedEvent(component: 'llm'));
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
      final lib = PlatformLoader.loadCommons();
      final loadFn = lib.lookupFunction<
          Int32 Function(RacVoiceAgentHandle, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacVoiceAgentHandle, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_voice_agent_load_tts_voice');

      final result = loadFn(handle, pathPtr, idPtr);

      if (result != RAC_SUCCESS) {
        throw StateError(
          'Failed to load TTS voice: ${RacResultCode.getMessage(result)}',
        );
      }

      _logger.info('Voice agent TTS voice loaded: $voiceId');
      _eventController.add(const VoiceAgentModelLoadedEvent(component: 'tts'));
    } finally {
      calloc.free(pathPtr);
      calloc.free(idPtr);
    }
  }

  // MARK: - Initialization

  /// Initialize voice agent with loaded models.
  ///
  /// Call after loading all required models (STT, LLM, TTS).
  Future<void> initializeWithLoadedModels() async {
    final handle = await getHandle();

    try {
      final lib = PlatformLoader.loadCommons();
      final initFn = lib.lookupFunction<Int32 Function(RacVoiceAgentHandle),
              int Function(RacVoiceAgentHandle)>(
          'rac_voice_agent_initialize_with_loaded_models');

      final result = initFn(handle);

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

    // Run the heavy C++ processing in a background isolate
    return await Isolate.run(
        () => _processVoiceTurnInIsolate(handle, audioData));
  }

  /// Static helper for processing voice turn in an isolate.
  /// The C++ API expects raw audio bytes (PCM16), not float samples.
  static Future<VoiceTurnResult> _processVoiceTurnInIsolate(
    RacVoiceAgentHandle handle,
    Uint8List audioData,
  ) async {
    // Allocate native memory for audio data (raw PCM16 bytes)
    final audioPtr = calloc<Uint8>(audioData.length);
    final resultPtr = calloc<RacVoiceAgentResultStruct>();

    try {
      // Copy audio bytes
      for (var i = 0; i < audioData.length; i++) {
        audioPtr[i] = audioData[i];
      }

      final lib = PlatformLoader.loadCommons();
      final processFn = lib.lookupFunction<
              Int32 Function(RacVoiceAgentHandle, Pointer<Void>, IntPtr,
                  Pointer<RacVoiceAgentResultStruct>),
              int Function(RacVoiceAgentHandle, Pointer<Void>, int,
                  Pointer<RacVoiceAgentResultStruct>)>(
          'rac_voice_agent_process_voice_turn');

      final status =
          processFn(handle, audioPtr.cast<Void>(), audioData.length, resultPtr);

      if (status != RAC_SUCCESS) {
        throw StateError(
          'Voice turn processing failed: ${RacResultCode.getMessage(status)}',
        );
      }

      // Parse result while still in isolate (before freeing memory)
      return _parseVoiceTurnResultStatic(resultPtr.ref, lib);
    } finally {
      // Free audio data
      calloc.free(audioPtr);

      // Free result struct - the C++ side allocates strings/audio that need freeing
      final lib = PlatformLoader.loadCommons();
      try {
        final freeFn = lib.lookupFunction<
            Void Function(Pointer<RacVoiceAgentResultStruct>),
            void Function(Pointer<RacVoiceAgentResultStruct>)>(
          'rac_voice_agent_result_free',
        );
        freeFn(resultPtr);
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
    DynamicLibrary lib,
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
        result.synthesizedAudio.cast<Uint8>().asTypedList(result.synthesizedAudioSize),
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
      for (var i = 0; i < audioData.length; i++) {
        audioPtr[i] = audioData[i];
      }

      final lib = PlatformLoader.loadCommons();
      final transcribeFn = lib.lookupFunction<
          Int32 Function(RacVoiceAgentHandle, Pointer<Void>, IntPtr,
              Pointer<Pointer<Utf8>>),
          int Function(RacVoiceAgentHandle, Pointer<Void>, int,
              Pointer<Pointer<Utf8>>)>('rac_voice_agent_transcribe');

      final status = transcribeFn(
          handle, audioPtr.cast<Void>(), audioData.length, resultPtr);

      if (status != RAC_SUCCESS) {
        throw StateError(
            'Transcription failed: ${RacResultCode.getMessage(status)}');
      }

      return resultPtr.value != nullptr ? resultPtr.value.toDartString() : '';
    } finally {
      calloc.free(audioPtr);
      calloc.free(resultPtr);
    }
  }

  /// Generate LLM response using voice agent.
  Future<String> generateResponse(String prompt) async {
    final handle = await getHandle();

    final promptPtr = prompt.toNativeUtf8();
    final resultPtr = calloc<Pointer<Utf8>>();

    try {
      final lib = PlatformLoader.loadCommons();
      final generateFn = lib.lookupFunction<
          Int32 Function(
              RacVoiceAgentHandle, Pointer<Utf8>, Pointer<Pointer<Utf8>>),
          int Function(RacVoiceAgentHandle, Pointer<Utf8>,
              Pointer<Pointer<Utf8>>)>('rac_voice_agent_generate_response');

      final status = generateFn(handle, promptPtr, resultPtr);

      if (status != RAC_SUCCESS) {
        throw StateError(
            'Response generation failed: ${RacResultCode.getMessage(status)}');
      }

      return resultPtr.value != nullptr ? resultPtr.value.toDartString() : '';
    } finally {
      calloc.free(promptPtr);
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
      final lib = PlatformLoader.loadCommons();
      final synthesizeFn = lib.lookupFunction<
          Int32 Function(RacVoiceAgentHandle, Pointer<Utf8>,
              Pointer<Pointer<Void>>, Pointer<IntPtr>),
          int Function(
              RacVoiceAgentHandle,
              Pointer<Utf8>,
              Pointer<Pointer<Void>>,
              Pointer<IntPtr>)>('rac_voice_agent_synthesize_speech');

      final status = synthesizeFn(handle, textPtr, audioPtr, audioSizePtr);

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
      if (audioPtr.value != nullptr) {
        final lib = PlatformLoader.loadCommons();
        try {
          final freeFn = lib.lookupFunction<Void Function(Pointer<Void>),
              void Function(Pointer<Void>)>('rac_free');
          freeFn(audioPtr.value);
        } catch (_) {
          // rac_free may not exist
        }
      }
      calloc.free(audioPtr);
      calloc.free(audioSizePtr);
    }
  }

  // MARK: - Cleanup

  /// Cleanup voice agent.
  void cleanup() {
    if (_handle == null) return;

    try {
      final lib = PlatformLoader.loadCommons();
      final cleanupFn = lib.lookupFunction<Int32 Function(RacVoiceAgentHandle),
          int Function(RacVoiceAgentHandle)>('rac_voice_agent_cleanup');

      cleanupFn(_handle!);
      _logger.info('Voice agent cleaned up');
    } catch (e) {
      _logger.error('Failed to cleanup voice agent: $e');
    }
  }

  /// Destroy voice agent.
  void destroy() {
    if (_handle != null) {
      try {
        final lib = PlatformLoader.loadCommons();
        final destroyFn = lib.lookupFunction<Void Function(RacVoiceAgentHandle),
            void Function(RacVoiceAgentHandle)>('rac_voice_agent_destroy');

        destroyFn(_handle!);
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
    _eventController.close();
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

/// Voice agent model loaded.
class VoiceAgentModelLoadedEvent extends VoiceAgentEvent {
  final String component; // 'stt', 'llm', or 'tts'
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
