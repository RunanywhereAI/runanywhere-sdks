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

  static final int Function(Pointer<RacHandle>) llmCreate = _lib.lookupFunction<
      Int32 Function(Pointer<RacHandle>),
      int Function(Pointer<RacHandle>)>('rac_llm_component_create');

  static final int Function(RacHandle) llmIsLoaded =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_llm_component_is_loaded');

  static final int Function(RacHandle) llmSupportsStreaming =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_llm_component_supports_streaming');

  static final int Function(
          RacHandle, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>) llmLoadModel =
      _lib.lookupFunction<
          Int32 Function(
              RacHandle, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_llm_component_load_model');

  static final int Function(RacHandle) llmCleanup =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_llm_component_cleanup');

  static final int Function(RacHandle) llmCancel =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_llm_component_cancel');

  static final void Function(RacHandle) llmDestroy =
      _lib.lookupFunction<Void Function(RacHandle), void Function(RacHandle)>(
          'rac_llm_component_destroy');

  // ---------------------------------------------------------------------------
  // STT Component
  // ---------------------------------------------------------------------------

  static final int Function(Pointer<RacHandle>) sttCreate = _lib.lookupFunction<
      Int32 Function(Pointer<RacHandle>),
      int Function(Pointer<RacHandle>)>('rac_stt_component_create');

  static final int Function(RacHandle) sttIsLoaded =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_stt_component_is_loaded');

  static final int Function(RacHandle) sttSupportsStreaming =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_stt_component_supports_streaming');

  static final int Function(
          RacHandle, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>) sttLoadModel =
      _lib.lookupFunction<
          Int32 Function(
              RacHandle, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_stt_component_load_model');

  static final int Function(RacHandle) sttCleanup =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_stt_component_cleanup');

  // Note: rac_stt_result_free is intentionally NOT cached here. The STT
  // transcription path runs inside Isolate.run(...), which cannot access
  // main-isolate static state — `_transcribeInIsolate` in dart_bridge_stt.dart
  // performs its own inline lookup so each spawned isolate resolves the
  // symbol once. A main-isolate cache entry would be dead code.

  static final void Function(RacHandle) sttDestroy =
      _lib.lookupFunction<Void Function(RacHandle), void Function(RacHandle)>(
          'rac_stt_component_destroy');

  // ---------------------------------------------------------------------------
  // TTS Component
  // ---------------------------------------------------------------------------

  static final int Function(Pointer<RacHandle>) ttsCreate = _lib.lookupFunction<
      Int32 Function(Pointer<RacHandle>),
      int Function(Pointer<RacHandle>)>('rac_tts_component_create');

  static final int Function(RacHandle) ttsIsLoaded =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_tts_component_is_loaded');

  static final int Function(
          RacHandle, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>) ttsLoadVoice =
      _lib.lookupFunction<
          Int32 Function(
              RacHandle, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_tts_component_load_voice');

  static final int Function(RacHandle) ttsCleanup =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_tts_component_cleanup');

  static final int Function(RacHandle) ttsStop =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_tts_component_stop');

  static final void Function(RacHandle) ttsDestroy =
      _lib.lookupFunction<Void Function(RacHandle), void Function(RacHandle)>(
          'rac_tts_component_destroy');

  // ---------------------------------------------------------------------------
  // VAD Component
  // ---------------------------------------------------------------------------

  static final int Function(Pointer<RacHandle>) vadCreate = _lib.lookupFunction<
      Int32 Function(Pointer<RacHandle>),
      int Function(Pointer<RacHandle>)>('rac_vad_component_create');

  static final int Function(RacHandle) vadIsInitialized =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_vad_component_is_initialized');

  static final int Function(RacHandle) vadIsSpeechActive =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_vad_component_is_speech_active');

  static final double Function(RacHandle) vadGetEnergyThreshold = _lib
      .lookupFunction<Float Function(RacHandle), double Function(RacHandle)>(
          'rac_vad_component_get_energy_threshold');

  static final int Function(RacHandle, double) vadSetEnergyThreshold =
      _lib.lookupFunction<
          Int32 Function(RacHandle, Float),
          int Function(
              RacHandle, double)>('rac_vad_component_set_energy_threshold');

  static final int Function(RacHandle) vadInitialize =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_vad_component_initialize');

  static final int Function(RacHandle) vadStart =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_vad_component_start');

  static final int Function(RacHandle) vadStop =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_vad_component_stop');

  static final int Function(RacHandle) vadReset =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_vad_component_reset');

  static final int Function(RacHandle) vadCleanup =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_vad_component_cleanup');

  static final int Function(
    RacHandle,
    Pointer<Float>,
    int,
    Pointer<RacVadResultStruct>,
  ) vadProcess = _lib.lookupFunction<
      Int32 Function(
        RacHandle,
        Pointer<Float>,
        IntPtr,
        Pointer<RacVadResultStruct>,
      ),
      int Function(
        RacHandle,
        Pointer<Float>,
        int,
        Pointer<RacVadResultStruct>,
      )>('rac_vad_component_process');

  static final void Function(RacHandle) vadDestroy =
      _lib.lookupFunction<Void Function(RacHandle), void Function(RacHandle)>(
          'rac_vad_component_destroy');

  // ---------------------------------------------------------------------------
  // VoiceAgent Component
  // ---------------------------------------------------------------------------

  static final int Function(
    RacHandle,
    RacHandle,
    RacHandle,
    RacHandle,
    Pointer<RacHandle>,
  ) voiceAgentCreate = _lib.lookupFunction<
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
      _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Int32>),
          int Function(
              RacHandle, Pointer<Int32>)>('rac_voice_agent_is_stt_loaded');

  static final int Function(RacHandle, Pointer<Int32>) voiceAgentIsLLMLoaded =
      _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Int32>),
          int Function(
              RacHandle, Pointer<Int32>)>('rac_voice_agent_is_llm_loaded');

  static final int Function(RacHandle, Pointer<Int32>) voiceAgentIsTTSLoaded =
      _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Int32>),
          int Function(
              RacHandle, Pointer<Int32>)>('rac_voice_agent_is_tts_loaded');

  static final int Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>)
      voiceAgentLoadSTTModel = _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_voice_agent_load_stt_model');

  static final int Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>)
      voiceAgentLoadLLMModel = _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_voice_agent_load_llm_model');

  static final int Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>)
      voiceAgentLoadTTSVoice = _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_voice_agent_load_tts_voice');

  static final int Function(RacHandle) voiceAgentInitializeWithLoadedModels =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_voice_agent_initialize_with_loaded_models');

  static final int Function(
          RacHandle, Pointer<Void>, int, Pointer<Pointer<Utf8>>)
      voiceAgentTranscribe = _lib.lookupFunction<
          Int32 Function(
              RacHandle, Pointer<Void>, IntPtr, Pointer<Pointer<Utf8>>),
          int Function(RacHandle, Pointer<Void>, int,
              Pointer<Pointer<Utf8>>)>('rac_voice_agent_transcribe');

  static final int Function(RacHandle, Pointer<Utf8>, Pointer<Pointer<Utf8>>)
      voiceAgentGenerateResponse = _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>, Pointer<Pointer<Utf8>>),
          int Function(RacHandle, Pointer<Utf8>,
              Pointer<Pointer<Utf8>>)>('rac_voice_agent_generate_response');

  static final int Function(
          RacHandle, Pointer<Utf8>, Pointer<Pointer<Void>>, Pointer<IntPtr>)
      voiceAgentSynthesizeSpeech = _lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>, Pointer<Pointer<Void>>,
              Pointer<IntPtr>),
          int Function(RacHandle, Pointer<Utf8>, Pointer<Pointer<Void>>,
              Pointer<IntPtr>)>('rac_voice_agent_synthesize_speech');

  static final int Function(RacHandle) voiceAgentCleanup =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_voice_agent_cleanup');

  static final void Function(RacHandle) voiceAgentDestroy =
      _lib.lookupFunction<Void Function(RacHandle), void Function(RacHandle)>(
          'rac_voice_agent_destroy');

  // ---------------------------------------------------------------------------
  // Voice Agent Proto-Byte Callback ABI (v3-readiness Phase A2 / GAP 09 #6)
  //
  // `rac_voice_agent_set_proto_callback` is the canonical streaming entry
  // point for VoiceEvent. The typed instance-method-style facade lives in
  // `lib/core/native/rac_native.dart`; this `Function` alias is exposed
  // here for callers that use the `NativeFunctions.voiceAgentSetProtoCallback`
  // pattern consistent with the rest of this file.
  // ---------------------------------------------------------------------------

  static final int Function(
    RacHandle,
    Pointer<NativeFunction<Void Function(Pointer<Uint8>, Size, Pointer<Void>)>>,
    Pointer<Void>,
  ) voiceAgentSetProtoCallback = _lib.lookupFunction<
      Int32 Function(
        RacHandle,
        Pointer<NativeFunction<Void Function(Pointer<Uint8>, Size, Pointer<Void>)>>,
        Pointer<Void>,
      ),
      int Function(
        RacHandle,
        Pointer<NativeFunction<Void Function(Pointer<Uint8>, Size, Pointer<Void>)>>,
        Pointer<Void>,
      )>('rac_voice_agent_set_proto_callback');

  static final void Function(Pointer<Void>)? racFree = (() {
    try {
      return _lib.lookupFunction<Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>('rac_free');
    } catch (_) {
      return null;
    }
  })();

  // ---------------------------------------------------------------------------
  // Solutions runtime (rac/solutions/rac_solution.h) — T4.7/T4.8.
  //
  // Proto-byte / YAML driven L5 solution runtime. `solutionCreateFromProto`
  // and `solutionCreateFromYaml` allocate a `rac_solution_handle_t` via
  // their out-pointer; the lifecycle verbs (start/stop/cancel/feed/
  // closeInput/destroy) take that handle directly. Every entry point is
  // wrapped by the higher-level `RunAnywhereSolutions` capability.
  // ---------------------------------------------------------------------------

  static final int Function(Pointer<Void>, int, Pointer<RacHandle>)
      solutionCreateFromProto = _lib.lookupFunction<
              Int32 Function(Pointer<Void>, IntPtr, Pointer<RacHandle>),
              int Function(Pointer<Void>, int, Pointer<RacHandle>)>(
          'rac_solution_create_from_proto');

  static final int Function(Pointer<Utf8>, Pointer<RacHandle>)
      solutionCreateFromYaml = _lib.lookupFunction<
              Int32 Function(Pointer<Utf8>, Pointer<RacHandle>),
              int Function(Pointer<Utf8>, Pointer<RacHandle>)>(
          'rac_solution_create_from_yaml');

  static final int Function(RacHandle) solutionStart =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_solution_start');

  static final int Function(RacHandle) solutionStop =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_solution_stop');

  static final int Function(RacHandle) solutionCancel =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_solution_cancel');

  static final int Function(RacHandle, Pointer<Utf8>) solutionFeed =
      _lib.lookupFunction<Int32 Function(RacHandle, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>)>('rac_solution_feed');

  static final int Function(RacHandle) solutionCloseInput =
      _lib.lookupFunction<Int32 Function(RacHandle), int Function(RacHandle)>(
          'rac_solution_close_input');

  static final void Function(RacHandle) solutionDestroy =
      _lib.lookupFunction<Void Function(RacHandle), void Function(RacHandle)>(
          'rac_solution_destroy');
}
