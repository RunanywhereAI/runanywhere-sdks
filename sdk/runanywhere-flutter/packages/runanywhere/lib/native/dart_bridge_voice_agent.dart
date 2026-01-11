/// DartBridge+VoiceAgent
///
/// VoiceAgent component bridge - manages C++ VoiceAgent lifecycle.
/// Mirrors Swift's CppBridge+VoiceAgent.swift pattern.
library dart_bridge_voice_agent;

import 'dart:async';
import 'dart:ffi';
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
  Future<RacVoiceAgentHandle> getHandle() async {
    if (_handle != null) {
      return _handle!;
    }

    try {
      final lib = PlatformLoader.loadCommons();

      // Try standalone creation first (preferred)
      try {
        final createStandalone = lib.lookupFunction<
                Int32 Function(Pointer<RacVoiceAgentHandle>),
                int Function(Pointer<RacVoiceAgentHandle>)>(
            'rac_voice_agent_create_standalone');

        final handlePtr = calloc<RacVoiceAgentHandle>();
        try {
          final result = createStandalone(handlePtr);

          if (result == RAC_SUCCESS) {
            _handle = handlePtr.value;
            _logger.info('Voice agent created (standalone)');
            return _handle!;
          }
        } finally {
          calloc.free(handlePtr);
        }
      } catch (e) {
        _logger
            .debug('Standalone creation not available, trying component-based');
      }

      // Fallback: Create with component handles
      final llmHandle = DartBridgeLLM.shared.getHandle();
      final sttHandle = DartBridgeSTT.shared.getHandle();
      final ttsHandle = DartBridgeTTS.shared.getHandle();
      final vadHandle = DartBridgeVAD.shared.getHandle();

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
        _logger.info('Voice agent created');
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
  /// [audioData] - Complete audio data for the user's utterance.
  ///
  /// Returns the voice turn result with transcription, response, and audio.
  Future<VoiceTurnResult> processVoiceTurn(Uint8List audioData) async {
    final handle = await getHandle();

    if (!isReady) {
      throw StateError(
          'Voice agent not ready. Load models and initialize first.');
    }

    // Convert to float samples (assuming PCM16)
    final floatSamples = _pcm16ToFloat32(audioData);
    final samplesPtr = calloc<Float>(floatSamples.length);
    final resultPtr = calloc<RacVoiceAgentResultStruct>();

    try {
      // Copy samples
      for (var i = 0; i < floatSamples.length; i++) {
        samplesPtr[i] = floatSamples[i];
      }

      final lib = PlatformLoader.loadCommons();
      final processFn = lib.lookupFunction<
              Int32 Function(RacVoiceAgentHandle, Pointer<Float>, IntPtr,
                  Pointer<RacVoiceAgentResultStruct>),
              int Function(RacVoiceAgentHandle, Pointer<Float>, int,
                  Pointer<RacVoiceAgentResultStruct>)>(
          'rac_voice_agent_process_voice_turn');

      final status =
          processFn(handle, samplesPtr, floatSamples.length, resultPtr);

      if (status != RAC_SUCCESS) {
        throw StateError(
          'Voice turn processing failed: ${RacResultCode.getMessage(status)}',
        );
      }

      return _parseVoiceTurnResult(resultPtr.ref);
    } finally {
      calloc.free(samplesPtr);
      calloc.free(resultPtr);
    }
  }

  /// Transcribe audio using voice agent.
  Future<String> transcribe(Uint8List audioData) async {
    final handle = await getHandle();

    final floatSamples = _pcm16ToFloat32(audioData);
    final samplesPtr = calloc<Float>(floatSamples.length);
    final resultPtr = calloc<Pointer<Utf8>>();

    try {
      for (var i = 0; i < floatSamples.length; i++) {
        samplesPtr[i] = floatSamples[i];
      }

      final lib = PlatformLoader.loadCommons();
      final transcribeFn = lib.lookupFunction<
          Int32 Function(RacVoiceAgentHandle, Pointer<Float>, IntPtr,
              Pointer<Pointer<Utf8>>),
          int Function(RacVoiceAgentHandle, Pointer<Float>, int,
              Pointer<Pointer<Utf8>>)>('rac_voice_agent_transcribe');

      final status =
          transcribeFn(handle, samplesPtr, floatSamples.length, resultPtr);

      if (status != RAC_SUCCESS) {
        throw StateError(
            'Transcription failed: ${RacResultCode.getMessage(status)}');
      }

      return resultPtr.value != nullptr ? resultPtr.value.toDartString() : '';
    } finally {
      calloc.free(samplesPtr);
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
  Future<Float32List> synthesizeSpeech(String text) async {
    final handle = await getHandle();

    final textPtr = text.toNativeUtf8();
    final samplesPtr = calloc<Pointer<Float>>();
    final numSamplesPtr = calloc<IntPtr>();

    try {
      final lib = PlatformLoader.loadCommons();
      final synthesizeFn = lib.lookupFunction<
          Int32 Function(RacVoiceAgentHandle, Pointer<Utf8>,
              Pointer<Pointer<Float>>, Pointer<IntPtr>),
          int Function(
              RacVoiceAgentHandle,
              Pointer<Utf8>,
              Pointer<Pointer<Float>>,
              Pointer<IntPtr>)>('rac_voice_agent_synthesize_speech');

      final status = synthesizeFn(handle, textPtr, samplesPtr, numSamplesPtr);

      if (status != RAC_SUCCESS) {
        throw StateError(
            'Speech synthesis failed: ${RacResultCode.getMessage(status)}');
      }

      final numSamples = numSamplesPtr.value;
      if (numSamples > 0 && samplesPtr.value != nullptr) {
        final samples = samplesPtr.value.asTypedList(numSamples);
        return Float32List.fromList(samples);
      }
      return Float32List(0);
    } finally {
      calloc.free(textPtr);
      calloc.free(samplesPtr);
      calloc.free(numSamplesPtr);
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

  /// Convert PCM16 audio to Float32 samples.
  Float32List _pcm16ToFloat32(Uint8List pcm16) {
    final numSamples = pcm16.length ~/ 2;
    final samples = Float32List(numSamples);

    for (var i = 0; i < numSamples; i++) {
      final low = pcm16[i * 2];
      final high = pcm16[i * 2 + 1];
      final sample = (high << 8) | low;
      // Convert to signed
      final signed = sample > 32767 ? sample - 65536 : sample;
      samples[i] = signed / 32768.0;
    }

    return samples;
  }

  /// Parse voice turn result from FFI struct.
  VoiceTurnResult _parseVoiceTurnResult(RacVoiceAgentResultStruct result) {
    return VoiceTurnResult(
      transcription: result.transcription != nullptr
          ? result.transcription.toDartString()
          : '',
      response:
          result.response != nullptr ? result.response.toDartString() : '',
      audioSamples: result.audioSamples != nullptr && result.numAudioSamples > 0
          ? Float32List.fromList(
              result.audioSamples.asTypedList(result.numAudioSamples))
          : Float32List(0),
      sttDurationMs: result.sttDurationMs,
      llmDurationMs: result.llmDurationMs,
      ttsDurationMs: result.ttsDurationMs,
    );
  }
}

// MARK: - Result Types

/// Result from a complete voice turn.
class VoiceTurnResult {
  final String transcription;
  final String response;
  final Float32List audioSamples;
  final int sttDurationMs;
  final int llmDurationMs;
  final int ttsDurationMs;

  const VoiceTurnResult({
    required this.transcription,
    required this.response,
    required this.audioSamples,
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
final class RacVoiceAgentResultStruct extends Struct {
  external Pointer<Utf8> transcription;
  external Pointer<Utf8> response;
  external Pointer<Float> audioSamples;

  @IntPtr()
  external int numAudioSamples;

  @Int32()
  external int sttDurationMs;

  @Int32()
  external int llmDurationMs;

  @Int32()
  external int ttsDurationMs;
}
