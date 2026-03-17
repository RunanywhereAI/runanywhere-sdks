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
  static late final _lib = PlatformLoader.loadCommons();

  // ---------------------------------------------------------------------------
  // LLM Component
  // ---------------------------------------------------------------------------

  static late final int Function(Pointer<RacHandle>) llmCreate =
      _lib.lookupFunction<
          Int32 Function(Pointer<RacHandle>),
          int Function(Pointer<RacHandle>)>('rac_llm_component_create');

  static late final int Function(RacHandle) llmIsLoaded =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_llm_component_is_loaded');

  static late final int Function(RacHandle) llmSupportsStreaming =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_llm_component_supports_streaming');

  static late final int Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>,
          Pointer<Utf8>) llmLoadModel =
      _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_llm_component_load_model');

  static late final int Function(RacHandle) llmCleanup =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_llm_component_cleanup');

  static late final int Function(RacHandle) llmCancel =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_llm_component_cancel');

  static late final int Function(
    RacHandle,
    Pointer<Utf8>,
    Pointer<RacLlmOptionsStruct>,
    Pointer<RacLlmResultStruct>,
  ) llmGenerate = _lib.lookupFunction<
      Int32 Function(RacHandle, Pointer<Utf8>, Pointer<RacLlmOptionsStruct>,
          Pointer<RacLlmResultStruct>),
      int Function(RacHandle, Pointer<Utf8>, Pointer<RacLlmOptionsStruct>,
          Pointer<RacLlmResultStruct>)>('rac_llm_component_generate');

  static late final int Function(
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

  static late final void Function(RacHandle) llmDestroy =
      _lib.lookupFunction<
          Void Function(RacHandle),
          void Function(RacHandle)>('rac_llm_component_destroy');


  // ---------------------------------------------------------------------------
  // STT Component
  // ---------------------------------------------------------------------------

  static late final int Function(Pointer<RacHandle>) sttCreate =
      _lib.lookupFunction<
          Int32 Function(Pointer<RacHandle>),
          int Function(Pointer<RacHandle>)>('rac_stt_component_create');

  static late final int Function(RacHandle) sttIsLoaded =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_stt_component_is_loaded');

  static late final int Function(RacHandle) sttSupportsStreaming =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_stt_component_supports_streaming');

  static late final int Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>,
          Pointer<Utf8>) sttLoadModel =
      _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_stt_component_load_model');

  static late final int Function(RacHandle) sttCleanup =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_stt_component_cleanup');

  static late final int Function(
    RacHandle,
    Pointer<Void>,
    int,
    Pointer<Void>,
    Pointer<Void>,
  ) sttTranscribe = _lib.lookupFunction<
      Int32 Function(
        RacHandle,
        Pointer<Void>,
        IntPtr,
        Pointer<Void>,
        Pointer<Void>,
      ),
      int Function(
        RacHandle,
        Pointer<Void>,
        int,
        Pointer<Void>,
        Pointer<Void>,
      )>('rac_stt_component_transcribe');

  static late final void Function(Pointer<Void>) sttResultFree =
      _lib.lookupFunction<Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>('rac_stt_result_free');

  static late final void Function(RacHandle) sttDestroy =
      _lib.lookupFunction<
          Void Function(RacHandle),
          void Function(RacHandle)>('rac_stt_component_destroy');


  // ---------------------------------------------------------------------------
  // TTS Component
  // ---------------------------------------------------------------------------

  static late final int Function(Pointer<RacHandle>) ttsCreate =
      _lib.lookupFunction<
          Int32 Function(Pointer<RacHandle>),
          int Function(Pointer<RacHandle>)>('rac_tts_component_create');

  static late final int Function(RacHandle) ttsIsLoaded =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_tts_component_is_loaded');

  static late final int Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>,
          Pointer<Utf8>) ttsLoadVoice =
      _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_tts_component_load_voice');

  static late final int Function(RacHandle) ttsCleanup =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_tts_component_cleanup');

  static late final int Function(RacHandle) ttsStop =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_tts_component_stop');

  static late final int Function(
    RacHandle,
    Pointer<Utf8>,
    Pointer<Void>,
    Pointer<Void>,
  ) ttsSynthesize = _lib.lookupFunction<
      Int32 Function(
        RacHandle,
        Pointer<Utf8>,
        Pointer<Void>,
        Pointer<Void>,
      ),
      int Function(
        RacHandle,
        Pointer<Utf8>,
        Pointer<Void>,
        Pointer<Void>,
      )>('rac_tts_component_synthesize');

  static late final void Function(RacHandle) ttsDestroy =
      _lib.lookupFunction<
          Void Function(RacHandle),
          void Function(RacHandle)>('rac_tts_component_destroy');


  // ---------------------------------------------------------------------------
  // VAD Component
  // ---------------------------------------------------------------------------

  static late final int Function(Pointer<RacHandle>) vadCreate =
      _lib.lookupFunction<
          Int32 Function(Pointer<RacHandle>),
          int Function(Pointer<RacHandle>)>('rac_vad_component_create');

  static late final int Function(RacHandle) vadIsInitialized =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_vad_component_is_initialized');

  static late final int Function(RacHandle) vadIsSpeechActive =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_vad_component_is_speech_active');

  static late final double Function(RacHandle) vadGetEnergyThreshold =
      _lib.lookupFunction<
          Float Function(RacHandle),
          double Function(RacHandle)>('rac_vad_component_get_energy_threshold');

  static late final int Function(RacHandle, double) vadSetEnergyThreshold =
      _lib.lookupFunction<
          Int32 Function(RacHandle, Float),
          int Function(RacHandle, double)>('rac_vad_component_set_energy_threshold');

  static late final int Function(RacHandle) vadInitialize =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_vad_component_initialize');

  static late final int Function(RacHandle) vadStart =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_vad_component_start');

  static late final int Function(RacHandle) vadStop =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_vad_component_stop');

  static late final int Function(RacHandle) vadReset =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_vad_component_reset');

  static late final int Function(RacHandle) vadCleanup =
      _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_vad_component_cleanup');

  static late final int Function(RacHandle, Pointer<Float>, int, Pointer<Void>)
      vadProcess =
      _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Float>, IntPtr, Pointer<Void>),
          int Function(
              RacHandle, Pointer<Float>, int, Pointer<Void>)>('rac_vad_component_process');

  static late final void Function(RacHandle) vadDestroy =
      _lib.lookupFunction<
          Void Function(RacHandle),
          void Function(RacHandle)>('rac_vad_component_destroy');

  // ---------------------------------------------------------------------------
  // VoiceAgent Component
  // ---------------------------------------------------------------------------

  static late final int Function(
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

  static late final int Function(RacHandle, Pointer<Int32>) voiceAgentIsReady =
      _lib.lookupFunction<Int32 Function(RacHandle, Pointer<Int32>),
          int Function(RacHandle, Pointer<Int32>)>('rac_voice_agent_is_ready');

  static late final int Function(RacHandle, Pointer<Int32>) voiceAgentIsSTTLoaded =
      _lib.lookupFunction<Int32 Function(RacHandle, Pointer<Int32>),
          int Function(RacHandle, Pointer<Int32>)>('rac_voice_agent_is_stt_loaded');

  static late final int Function(RacHandle, Pointer<Int32>) voiceAgentIsLLMLoaded =
      _lib.lookupFunction<Int32 Function(RacHandle, Pointer<Int32>),
          int Function(RacHandle, Pointer<Int32>)>('rac_voice_agent_is_llm_loaded');

  static late final int Function(RacHandle, Pointer<Int32>) voiceAgentIsTTSLoaded =
      _lib.lookupFunction<Int32 Function(RacHandle, Pointer<Int32>),
          int Function(RacHandle, Pointer<Int32>)>('rac_voice_agent_is_tts_loaded');

  static late final int Function(
          RacHandle, Pointer<Utf8>, Pointer<Utf8>)
      voiceAgentLoadSTTModel = _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_voice_agent_load_stt_model');

  static late final int Function(
          RacHandle, Pointer<Utf8>, Pointer<Utf8>)
      voiceAgentLoadLLMModel = _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_voice_agent_load_llm_model');

  static late final int Function(
          RacHandle, Pointer<Utf8>, Pointer<Utf8>)
      voiceAgentLoadTTSVoice = _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_voice_agent_load_tts_voice');

  static late final int Function(RacHandle)
      voiceAgentInitializeWithLoadedModels = _lib.lookupFunction<
          Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_voice_agent_initialize_with_loaded_models');

  static late final int Function(RacHandle, Pointer<Void>, int, Pointer<Void>)
      voiceAgentProcessVoiceTurn =
      _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Void>, IntPtr, Pointer<Void>),
          int Function(
              RacHandle, Pointer<Void>, int, Pointer<Void>)>('rac_voice_agent_process_voice_turn');

  static late final void Function(Pointer<Void>) voiceAgentResultFree =
      _lib.lookupFunction<Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>('rac_voice_agent_result_free');

  static late final int Function(RacHandle, Pointer<Void>, int,
          Pointer<Pointer<Utf8>>) voiceAgentTranscribe =
      _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Void>, IntPtr,
              Pointer<Pointer<Utf8>>),
          int Function(RacHandle, Pointer<Void>, int,
              Pointer<Pointer<Utf8>>)>('rac_voice_agent_transcribe');

  static late final int Function(
          RacHandle, Pointer<Utf8>, Pointer<Pointer<Utf8>>)
      voiceAgentGenerateResponse = _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>,
              Pointer<Pointer<Utf8>>),
          int Function(RacHandle, Pointer<Utf8>,
              Pointer<Pointer<Utf8>>)>('rac_voice_agent_generate_response');

  static late final int Function(RacHandle, Pointer<Utf8>,
          Pointer<Pointer<Void>>, Pointer<IntPtr>) voiceAgentSynthesizeSpeech =
      _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>,
              Pointer<Pointer<Void>>, Pointer<IntPtr>),
          int Function(RacHandle, Pointer<Utf8>,
              Pointer<Pointer<Void>>, Pointer<IntPtr>)>('rac_voice_agent_synthesize_speech');

  static late final int Function(RacHandle) voiceAgentCleanup =
      _lib.lookupFunction<Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_voice_agent_cleanup');

  static late final void Function(RacHandle) voiceAgentDestroy =
      _lib.lookupFunction<Void Function(RacHandle),
          void Function(RacHandle)>('rac_voice_agent_destroy');

  static late final void Function(Pointer<Void>) racFree =
      _lib.lookupFunction<Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>('rac_free');
}
