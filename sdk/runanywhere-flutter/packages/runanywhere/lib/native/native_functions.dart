/// NativeFunctions
///
/// Cached FFI function lookup registry.
///
/// All [DynamicLibrary.lookupFunction] calls are performed once at first access
/// via lazy static fields. Subsequent calls return the cached function pointer,
/// avoiding repeated symbol-table searches (dlsym) on every invocation.
library native_functions;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// Cached native function pointers for the RACommons library.
///
/// Usage:
/// ```dart
/// final result = NativeFunctions.llmIsLoaded(_handle!);
/// ```
abstract class NativeFunctions {
  static final _lib = PlatformLoader.loadCommons();

  // ---------------------------------------------------------------------------
  // LLM Component
  // ---------------------------------------------------------------------------

  static final int Function(Pointer<RacHandle>) llmCreate =
      _lib.lookupFunction<
          Int32 Function(Pointer<RacHandle>),
          int Function(Pointer<RacHandle>)>('rac_llm_component_create');

  static final int Function(RacHandle) llmIsLoaded =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_llm_component_is_loaded');

  static final int Function(RacHandle) llmSupportsStreaming =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_llm_component_supports_streaming');

  static final int Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>,
          Pointer<Utf8>) llmLoadModel =
      _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_llm_component_load_model');

  static final int Function(RacHandle) llmCleanup =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_llm_component_cleanup');

  static final int Function(RacHandle) llmCancel =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_llm_component_cancel');

  static final int Function(
    RacHandle,
    Pointer<Utf8>,
    Pointer<RacLlmOptionsStruct>,
    Pointer<RacLlmResultStruct>,
  ) llmGenerate = _lib.lookupFunction<
      Int32 Function(RacHandle, Pointer<Utf8>, Pointer<RacLlmOptionsStruct>,
          Pointer<RacLlmResultStruct>),
      int Function(RacHandle, Pointer<Utf8>, Pointer<RacLlmOptionsStruct>,
          Pointer<RacLlmResultStruct>)>('rac_llm_component_generate');

  static final int Function(
    RacHandle,
    Pointer<Utf8>,
    Pointer<RacLlmOptionsStruct>,
    Pointer<NativeFunction<Int32 Function(Pointer<Utf8>, Pointer<Void>)>>,
    Pointer<NativeFunction<Void Function(Pointer<RacLlmResultStruct>, Pointer<Void>)>>,
    Pointer<NativeFunction<Void Function(Int32, Pointer<Utf8>, Pointer<Void>)>>,
    Pointer<Void>,
  ) llmGenerateStream = _lib.lookupFunction<
      Int32 Function(
        RacHandle,
        Pointer<Utf8>,
        Pointer<RacLlmOptionsStruct>,
        Pointer<NativeFunction<Int32 Function(Pointer<Utf8>, Pointer<Void>)>>,
        Pointer<NativeFunction<Void Function(Pointer<RacLlmResultStruct>, Pointer<Void>)>>,
        Pointer<NativeFunction<Void Function(Int32, Pointer<Utf8>, Pointer<Void>)>>,
        Pointer<Void>,
      ),
      int Function(
        RacHandle,
        Pointer<Utf8>,
        Pointer<RacLlmOptionsStruct>,
        Pointer<NativeFunction<Int32 Function(Pointer<Utf8>, Pointer<Void>)>>,
        Pointer<NativeFunction<Void Function(Pointer<RacLlmResultStruct>, Pointer<Void>)>>,
        Pointer<NativeFunction<Void Function(Int32, Pointer<Utf8>, Pointer<Void>)>>,
        Pointer<Void>,
      )>('rac_llm_component_generate_stream');

  static final void Function(RacHandle) llmDestroy =
      _lib.lookupFunction<
          Void Function(RacHandle),
          void Function(RacHandle)>('rac_llm_component_destroy');


  // ---------------------------------------------------------------------------
  // STT Component
  // ---------------------------------------------------------------------------

  static final int Function(Pointer<RacHandle>) sttCreate =
      _lib.lookupFunction<
          Int32 Function(Pointer<RacHandle>),
          int Function(Pointer<RacHandle>)>('rac_stt_component_create');

  static final int Function(RacHandle) sttIsLoaded =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_stt_component_is_loaded');

  static final int Function(RacHandle) sttSupportsStreaming =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_stt_component_supports_streaming');

  static final int Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>,
          Pointer<Utf8>) sttLoadModel =
      _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_stt_component_load_model');

  static final int Function(RacHandle) sttCleanup =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_stt_component_cleanup');

  static final int Function(
    RacHandle,
    Pointer<Void>,
    int,
    Pointer<RacSttOptionsStruct>,
    Pointer<RacSttResultStruct>,
  ) sttTranscribe = _lib.lookupFunction<
      Int32 Function(
        RacHandle,
        Pointer<Void>,
        IntPtr,
        Pointer<RacSttOptionsStruct>,
        Pointer<RacSttResultStruct>,
      ),
      int Function(
        RacHandle,
        Pointer<Void>,
        int,
        Pointer<RacSttOptionsStruct>,
        Pointer<RacSttResultStruct>,
      )>('rac_stt_component_transcribe');

  static final void Function(Pointer<RacSttResultStruct>) sttResultFree =
      _lib.lookupFunction<Void Function(Pointer<RacSttResultStruct>),
          void Function(Pointer<RacSttResultStruct>)>('rac_stt_result_free');

  static final void Function(RacHandle) sttDestroy =
      _lib.lookupFunction<
          Void Function(RacHandle),
          void Function(RacHandle)>('rac_stt_component_destroy');


  // ---------------------------------------------------------------------------
  // TTS Component
  // ---------------------------------------------------------------------------

  static final int Function(Pointer<RacHandle>) ttsCreate =
      _lib.lookupFunction<
          Int32 Function(Pointer<RacHandle>),
          int Function(Pointer<RacHandle>)>('rac_tts_component_create');

  static final int Function(RacHandle) ttsIsLoaded =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_tts_component_is_loaded');

  static final int Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>,
          Pointer<Utf8>) ttsLoadVoice =
      _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_tts_component_load_voice');

  static final int Function(RacHandle) ttsCleanup =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_tts_component_cleanup');

  static final int Function(RacHandle) ttsStop =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_tts_component_stop');

  static final int Function(
    RacHandle,
    Pointer<Utf8>,
    Pointer<RacTtsOptionsStruct>,
    Pointer<RacTtsResultStruct>,
  ) ttsSynthesize = _lib.lookupFunction<
      Int32 Function(
        RacHandle,
        Pointer<Utf8>,
        Pointer<RacTtsOptionsStruct>,
        Pointer<RacTtsResultStruct>,
      ),
      int Function(
        RacHandle,
        Pointer<Utf8>,
        Pointer<RacTtsOptionsStruct>,
        Pointer<RacTtsResultStruct>,
      )>('rac_tts_component_synthesize');

  static final void Function(RacHandle) ttsDestroy =
      _lib.lookupFunction<
          Void Function(RacHandle),
          void Function(RacHandle)>('rac_tts_component_destroy');


  // ---------------------------------------------------------------------------
  // VAD Component
  // ---------------------------------------------------------------------------

  static final int Function(Pointer<RacHandle>) vadCreate =
      _lib.lookupFunction<
          Int32 Function(Pointer<RacHandle>),
          int Function(Pointer<RacHandle>)>('rac_vad_component_create');

  static final int Function(RacHandle) vadIsInitialized =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_vad_component_is_initialized');

  static final int Function(RacHandle) vadIsSpeechActive =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_vad_component_is_speech_active');

  static final double Function(RacHandle) vadGetEnergyThreshold =
      _lib.lookupFunction<
          Float Function(RacHandle),
          double Function(RacHandle)>('rac_vad_component_get_energy_threshold');

  static final int Function(RacHandle, double) vadSetEnergyThreshold =
      _lib.lookupFunction<
          Int32 Function(RacHandle, Float),
          int Function(RacHandle, double)>('rac_vad_component_set_energy_threshold');

  static final int Function(RacHandle) vadInitialize =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_vad_component_initialize');

  static final int Function(RacHandle) vadStart =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_vad_component_start');

  static final int Function(RacHandle) vadStop =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_vad_component_stop');

  static final int Function(RacHandle) vadReset =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_vad_component_reset');

  static final int Function(RacHandle) vadCleanup =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_vad_component_cleanup');

  static final int Function(RacHandle, Pointer<Float>, int, Pointer<Void>)
      vadProcess =
      _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Float>, IntPtr, Pointer<Void>),
          int Function(
              RacHandle, Pointer<Float>, int, Pointer<Void>)>('rac_vad_component_process');

  static final void Function(RacHandle) vadDestroy =
      _lib.lookupFunction<
          Void Function(RacHandle),
          void Function(RacHandle)>('rac_vad_component_destroy');

  // ---------------------------------------------------------------------------
  // VoiceAgent Component
  // ---------------------------------------------------------------------------

  static final int Function(
    RacHandle,
    RacHandle,
    RacHandle,
    RacHandle,
    Pointer<RacHandle>,
  ) voiceAgentCreate =
      _lib.lookupFunction<
          Int32 Function(
            RacHandle,
            RacHandle,
            RacHandle,
            RacHandle,
            Pointer<RacHandle>,
          ),
          int Function(
            RacHandle,
            RacHandle,
            RacHandle,
            RacHandle,
            Pointer<RacHandle>,
          )>('rac_voice_agent_create');

  static final int Function(RacHandle, Pointer<Int32>) voiceAgentIsReady =
      _lib.lookupFunction<Int32 Function(RacHandle, Pointer<Int32>),
          int Function(RacHandle, Pointer<Int32>)>('rac_voice_agent_is_ready');

  static final int Function(RacHandle, Pointer<Int32>) voiceAgentIsSTTLoaded =
      _lib.lookupFunction<Int32 Function(RacHandle, Pointer<Int32>),
          int Function(RacHandle, Pointer<Int32>)>('rac_voice_agent_is_stt_loaded');

  static final int Function(RacHandle, Pointer<Int32>) voiceAgentIsLLMLoaded =
      _lib.lookupFunction<Int32 Function(RacHandle, Pointer<Int32>),
          int Function(RacHandle, Pointer<Int32>)>('rac_voice_agent_is_llm_loaded');

  static final int Function(RacHandle, Pointer<Int32>) voiceAgentIsTTSLoaded =
      _lib.lookupFunction<Int32 Function(RacHandle, Pointer<Int32>),
          int Function(RacHandle, Pointer<Int32>)>('rac_voice_agent_is_tts_loaded');

  static final int Function(
          RacHandle, Pointer<Utf8>, Pointer<Utf8>)
      voiceAgentLoadSTTModel = _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_voice_agent_load_stt_model');

  static final int Function(
          RacHandle, Pointer<Utf8>, Pointer<Utf8>)
      voiceAgentLoadLLMModel = _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_voice_agent_load_llm_model');

  static final int Function(
          RacHandle, Pointer<Utf8>, Pointer<Utf8>)
      voiceAgentLoadTTSVoice = _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_voice_agent_load_tts_voice');

  static final int Function(RacHandle)
      voiceAgentInitializeWithLoadedModels = _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_voice_agent_initialize_with_loaded_models');

  static final int Function(RacHandle, Pointer<Void>, int, Pointer<Void>)
      voiceAgentProcessVoiceTurn =
      _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Void>, IntPtr, Pointer<Void>),
          int Function(
              RacHandle, Pointer<Void>, int, Pointer<Void>)>('rac_voice_agent_process_voice_turn');

  static final void Function(Pointer<Void>) voiceAgentResultFree =
      _lib.lookupFunction<Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>('rac_voice_agent_result_free');

  static final int Function(RacHandle, Pointer<Void>, int,
          Pointer<Pointer<Utf8>>) voiceAgentTranscribe =
      _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Void>, IntPtr,
              Pointer<Pointer<Utf8>>),
          int Function(RacHandle, Pointer<Void>, int,
              Pointer<Pointer<Utf8>>)>('rac_voice_agent_transcribe');

  static final int Function(
          RacHandle, Pointer<Utf8>, Pointer<Pointer<Utf8>>)
      voiceAgentGenerateResponse = _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>,
              Pointer<Pointer<Utf8>>),
          int Function(RacHandle, Pointer<Utf8>,
              Pointer<Pointer<Utf8>>)>('rac_voice_agent_generate_response');

  static final int Function(RacHandle, Pointer<Utf8>,
          Pointer<Pointer<Void>>, Pointer<IntPtr>) voiceAgentSynthesizeSpeech =
      _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>,
              Pointer<Pointer<Void>>, Pointer<IntPtr>),
          int Function(RacHandle, Pointer<Utf8>,
              Pointer<Pointer<Void>>, Pointer<IntPtr>)>('rac_voice_agent_synthesize_speech');

  static final int Function(RacHandle) voiceAgentCleanup =
      _lib.lookupFunction<Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_voice_agent_cleanup');

  static final void Function(RacHandle) voiceAgentDestroy =
      _lib.lookupFunction<Void Function(RacHandle),
          void Function(RacHandle)>('rac_voice_agent_destroy');

  static final void Function(Pointer<Void>) racFree =
      _lib.lookupFunction<Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>('rac_free');
}

// =============================================================================
// FFI Structs
// =============================================================================
//
// These are the native struct layouts used by a subset of component functions.
// They are defined here (instead of `ffi_types.dart`) so that `NativeFunctions`
// exposes correctly typed pointers without requiring other library imports.

/// FFI struct for STT options (matches `rac_stt_options_t`).
final class RacSttOptionsStruct extends Struct {
  /// Language code (e.g., "en")
  external Pointer<Utf8> language;

  /// Whether to auto-detect language
  @Int32()
  external int detectLanguage;

  /// Whether to add punctuation
  @Int32()
  external int enablePunctuation;

  /// Whether to enable speaker diarization
  @Int32()
  external int enableDiarization;

  /// Maximum number of speakers for diarization
  @Int32()
  external int maxSpeakers;

  /// Whether to include word timestamps
  @Int32()
  external int enableTimestamps;

  /// Audio format of input data (`rac_audio_format_enum_t`)
  @Int32()
  external int audioFormat;

  /// Sample rate of input audio in Hz
  @Int32()
  external int sampleRate;
}

/// FFI struct for STT result (matches `rac_stt_result_t`).
final class RacSttResultStruct extends Struct {
  external Pointer<Utf8> text;

  @Double()
  external double confidence;

  @Int32()
  external int durationMs;

  external Pointer<Utf8> language;
}

/// FFI struct for TTS options (matches `rac_tts_options_t`).
final class RacTtsOptionsStruct extends Struct {
  /// Voice to use for synthesis (can be NULL for default)
  external Pointer<Utf8> voice;

  /// Language for synthesis (BCP-47 format, e.g., "en-US")
  external Pointer<Utf8> language;

  /// Speech rate (0.0 to 2.0, 1.0 is normal)
  @Float()
  external double rate;

  /// Speech pitch (0.0 to 2.0, 1.0 is normal)
  @Float()
  external double pitch;

  /// Speech volume (0.0 to 1.0)
  @Float()
  external double volume;

  /// Audio format for output (`rac_audio_format_enum_t`)
  @Int32()
  external int audioFormat;

  /// Sample rate for output audio in Hz
  @Int32()
  external int sampleRate;

  /// Whether to use SSML markup (`rac_bool_t`)
  @Int32()
  external int useSsml;
}

/// FFI struct for TTS result (matches `rac_tts_result_t`).
final class RacTtsResultStruct extends Struct {
  /// Audio data (PCM float samples)
  external Pointer<Void> audioData;

  /// Size of audio data in bytes (size_t)
  @IntPtr()
  external int audioSize;

  /// Audio format (`rac_audio_format_enum_t`)
  @Int32()
  external int audioFormat;

  /// Sample rate in Hz
  @Int32()
  external int sampleRate;

  /// Duration in milliseconds
  @Int64()
  external int durationMs;

  /// Processing time in milliseconds
  @Int64()
  external int processingTimeMs;
}
