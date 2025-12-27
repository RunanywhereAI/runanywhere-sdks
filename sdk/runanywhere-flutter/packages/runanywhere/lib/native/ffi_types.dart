// ignore_for_file: non_constant_identifier_names

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// =============================================================================
/// RunAnywhere FFI Type Definitions
///
/// Dart FFI types matching the C API defined in runanywhere_bridge.h
/// =============================================================================

// =============================================================================
// Result Codes (enum ra_result_code)
// =============================================================================

abstract class RaResultCode {
  static const int success = 0;
  static const int errorInitFailed = -1;
  static const int errorModelLoadFailed = -2;
  static const int errorInferenceFailed = -3;
  static const int errorInvalidHandle = -4;
  static const int errorInvalidParams = -5;
  static const int errorOutOfMemory = -6;
  static const int errorNotImplemented = -7;
  static const int errorCancelled = -8;
  static const int errorTimeout = -9;
  static const int errorIO = -10;
  static const int errorUnknown = -99;

  static String getMessage(int code) {
    switch (code) {
      case success:
        return 'Success';
      case errorInitFailed:
        return 'Initialization failed';
      case errorModelLoadFailed:
        return 'Model load failed';
      case errorInferenceFailed:
        return 'Inference failed';
      case errorInvalidHandle:
        return 'Invalid handle';
      case errorInvalidParams:
        return 'Invalid parameters';
      case errorOutOfMemory:
        return 'Out of memory';
      case errorNotImplemented:
        return 'Not implemented';
      case errorCancelled:
        return 'Cancelled';
      case errorTimeout:
        return 'Timeout';
      case errorIO:
        return 'I/O error';
      default:
        return 'Unknown error (code: $code)';
    }
  }
}

// =============================================================================
// Device Types (enum ra_device_type)
// =============================================================================

abstract class RaDeviceType {
  static const int cpu = 0;
  static const int gpu = 1;
  static const int neuralEngine = 2;
  static const int metal = 3;
  static const int cuda = 4;
  static const int nnapi = 5;
  static const int coreml = 6;
  static const int vulkan = 7;
  static const int unknown = 99;

  static String getName(int type) {
    switch (type) {
      case cpu:
        return 'CPU';
      case gpu:
        return 'GPU';
      case neuralEngine:
        return 'Neural Engine';
      case metal:
        return 'Metal';
      case cuda:
        return 'CUDA';
      case nnapi:
        return 'NNAPI';
      case coreml:
        return 'CoreML';
      case vulkan:
        return 'Vulkan';
      default:
        return 'Unknown';
    }
  }
}

// =============================================================================
// Capability Types (enum ra_capability_type)
// =============================================================================

abstract class RaCapabilityType {
  static const int textGeneration = 0;
  static const int embeddings = 1;
  static const int stt = 2;
  static const int tts = 3;
  static const int vad = 4;
  static const int diarization = 5;

  static String getName(int type) {
    switch (type) {
      case textGeneration:
        return 'Text Generation';
      case embeddings:
        return 'Embeddings';
      case stt:
        return 'Speech-to-Text';
      case tts:
        return 'Text-to-Speech';
      case vad:
        return 'Voice Activity Detection';
      case diarization:
        return 'Speaker Diarization';
      default:
        return 'Unknown';
    }
  }
}

// =============================================================================
// Audio Format (enum ra_audio_format)
// =============================================================================

abstract class RaAudioFormat {
  static const int pcmF32 = 0;
  static const int pcmS16 = 1;
  static const int pcmS32 = 2;
  static const int wav = 10;
  static const int mp3 = 11;
  static const int flac = 12;
  static const int aac = 13;
  static const int opus = 14;
}

// =============================================================================
// Opaque Handle Types
// =============================================================================

/// Opaque handle to a backend instance
typedef RaBackendHandle = Pointer<Void>;

/// Opaque handle to a streaming session
typedef RaStreamHandle = Pointer<Void>;

// =============================================================================
// Callback Function Types (Native signatures)
// =============================================================================

/// Text generation streaming callback
/// bool (*ra_text_stream_callback)(const char* token, void* user_data);
typedef RaTextStreamCallbackNative = Bool Function(
  Pointer<Utf8> token,
  Pointer<Void> userData,
);

/// STT streaming callback
/// bool (*ra_stt_stream_callback)(const char* text, bool is_final, void* user_data);
typedef RaSttStreamCallbackNative = Bool Function(
  Pointer<Utf8> text,
  Bool isFinal,
  Pointer<Void> userData,
);

/// TTS streaming callback
/// bool (*ra_tts_stream_callback)(const float*, size_t, bool, void*);
typedef RaTtsStreamCallbackNative = Bool Function(
  Pointer<Float> samples,
  IntPtr numSamples,
  Bool isFinal,
  Pointer<Void> userData,
);

/// VAD streaming callback
/// void (*ra_vad_stream_callback)(bool, float, double, void*);
typedef RaVadStreamCallbackNative = Void Function(
  Bool isSpeech,
  Float probability,
  Double timestampMs,
  Pointer<Void> userData,
);

// =============================================================================
// FFI Function Signatures - Backend Lifecycle
// =============================================================================

/// const char** ra_get_available_backends(int* count);
typedef RaGetAvailableBackendsNative = Pointer<Pointer<Utf8>> Function(
  Pointer<Int32> count,
);
typedef RaGetAvailableBackendsDart = Pointer<Pointer<Utf8>> Function(
  Pointer<Int32> count,
);

/// ra_backend_handle ra_create_backend(const char* backend_name);
typedef RaCreateBackendNative = RaBackendHandle Function(Pointer<Utf8> name);
typedef RaCreateBackendDart = RaBackendHandle Function(Pointer<Utf8> name);

/// ra_result_code ra_initialize(ra_backend_handle, const char* config_json);
typedef RaInitializeNative = Int32 Function(
  RaBackendHandle handle,
  Pointer<Utf8> configJson,
);
typedef RaInitializeDart = int Function(
  RaBackendHandle handle,
  Pointer<Utf8> configJson,
);

/// bool ra_is_initialized(ra_backend_handle);
typedef RaIsInitializedNative = Bool Function(RaBackendHandle handle);
typedef RaIsInitializedDart = bool Function(RaBackendHandle handle);

/// void ra_destroy(ra_backend_handle);
typedef RaDestroyNative = Void Function(RaBackendHandle handle);
typedef RaDestroyDart = void Function(RaBackendHandle handle);

/// char* ra_get_backend_info(ra_backend_handle);
typedef RaGetBackendInfoNative = Pointer<Utf8> Function(RaBackendHandle handle);
typedef RaGetBackendInfoDart = Pointer<Utf8> Function(RaBackendHandle handle);

/// bool ra_supports_capability(ra_backend_handle, ra_capability_type);
typedef RaSupportsCapabilityNative = Bool Function(
  RaBackendHandle handle,
  Int32 capability,
);
typedef RaSupportsCapabilityDart = bool Function(
  RaBackendHandle handle,
  int capability,
);

/// ra_device_type ra_get_device(ra_backend_handle);
typedef RaGetDeviceNative = Int32 Function(RaBackendHandle handle);
typedef RaGetDeviceDart = int Function(RaBackendHandle handle);

/// size_t ra_get_memory_usage(ra_backend_handle);
typedef RaGetMemoryUsageNative = IntPtr Function(RaBackendHandle handle);
typedef RaGetMemoryUsageDart = int Function(RaBackendHandle handle);

// =============================================================================
// FFI Function Signatures - STT (Speech-to-Text)
// =============================================================================

/// ra_result_code ra_stt_load_model(handle, model_path, model_type, config_json);
typedef RaSttLoadModelNative = Int32 Function(
  RaBackendHandle handle,
  Pointer<Utf8> modelPath,
  Pointer<Utf8> modelType,
  Pointer<Utf8> configJson,
);
typedef RaSttLoadModelDart = int Function(
  RaBackendHandle handle,
  Pointer<Utf8> modelPath,
  Pointer<Utf8> modelType,
  Pointer<Utf8> configJson,
);

/// bool ra_stt_is_model_loaded(ra_backend_handle);
typedef RaSttIsModelLoadedNative = Bool Function(RaBackendHandle handle);
typedef RaSttIsModelLoadedDart = bool Function(RaBackendHandle handle);

/// ra_result_code ra_stt_unload_model(ra_backend_handle);
typedef RaSttUnloadModelNative = Int32 Function(RaBackendHandle handle);
typedef RaSttUnloadModelDart = int Function(RaBackendHandle handle);

/// ra_result_code ra_stt_transcribe(handle, samples, num_samples, sample_rate, language, result_json);
typedef RaSttTranscribeNative = Int32 Function(
  RaBackendHandle handle,
  Pointer<Float> samples,
  IntPtr numSamples,
  Int32 sampleRate,
  Pointer<Utf8> language,
  Pointer<Pointer<Utf8>> resultJson,
);
typedef RaSttTranscribeDart = int Function(
  RaBackendHandle handle,
  Pointer<Float> samples,
  int numSamples,
  int sampleRate,
  Pointer<Utf8> language,
  Pointer<Pointer<Utf8>> resultJson,
);

/// bool ra_stt_supports_streaming(ra_backend_handle);
typedef RaSttSupportsStreamingNative = Bool Function(RaBackendHandle handle);
typedef RaSttSupportsStreamingDart = bool Function(RaBackendHandle handle);

/// ra_stream_handle ra_stt_create_stream(handle, config_json);
typedef RaSttCreateStreamNative = RaStreamHandle Function(
  RaBackendHandle handle,
  Pointer<Utf8> configJson,
);
typedef RaSttCreateStreamDart = RaStreamHandle Function(
  RaBackendHandle handle,
  Pointer<Utf8> configJson,
);

/// ra_result_code ra_stt_feed_audio(backend, stream, samples, num_samples, sample_rate);
typedef RaSttFeedAudioNative = Int32 Function(
  RaBackendHandle backend,
  RaStreamHandle stream,
  Pointer<Float> samples,
  IntPtr numSamples,
  Int32 sampleRate,
);
typedef RaSttFeedAudioDart = int Function(
  RaBackendHandle backend,
  RaStreamHandle stream,
  Pointer<Float> samples,
  int numSamples,
  int sampleRate,
);

/// bool ra_stt_is_ready(backend, stream);
typedef RaSttIsReadyNative = Bool Function(
  RaBackendHandle backend,
  RaStreamHandle stream,
);
typedef RaSttIsReadyDart = bool Function(
  RaBackendHandle backend,
  RaStreamHandle stream,
);

/// ra_result_code ra_stt_decode(backend, stream, result_json);
typedef RaSttDecodeNative = Int32 Function(
  RaBackendHandle backend,
  RaStreamHandle stream,
  Pointer<Pointer<Utf8>> resultJson,
);
typedef RaSttDecodeDart = int Function(
  RaBackendHandle backend,
  RaStreamHandle stream,
  Pointer<Pointer<Utf8>> resultJson,
);

/// bool ra_stt_is_endpoint(backend, stream);
typedef RaSttIsEndpointNative = Bool Function(
  RaBackendHandle backend,
  RaStreamHandle stream,
);
typedef RaSttIsEndpointDart = bool Function(
  RaBackendHandle backend,
  RaStreamHandle stream,
);

/// void ra_stt_input_finished(backend, stream);
typedef RaSttInputFinishedNative = Void Function(
  RaBackendHandle backend,
  RaStreamHandle stream,
);
typedef RaSttInputFinishedDart = void Function(
  RaBackendHandle backend,
  RaStreamHandle stream,
);

/// void ra_stt_reset_stream(backend, stream);
typedef RaSttResetStreamNative = Void Function(
  RaBackendHandle backend,
  RaStreamHandle stream,
);
typedef RaSttResetStreamDart = void Function(
  RaBackendHandle backend,
  RaStreamHandle stream,
);

/// void ra_stt_destroy_stream(backend, stream);
typedef RaSttDestroyStreamNative = Void Function(
  RaBackendHandle backend,
  RaStreamHandle stream,
);
typedef RaSttDestroyStreamDart = void Function(
  RaBackendHandle backend,
  RaStreamHandle stream,
);

/// void ra_stt_cancel(handle);
typedef RaSttCancelNative = Void Function(RaBackendHandle handle);
typedef RaSttCancelDart = void Function(RaBackendHandle handle);

// =============================================================================
// FFI Function Signatures - TTS (Text-to-Speech)
// =============================================================================

/// ra_result_code ra_tts_load_model(handle, model_path, model_type, config_json);
typedef RaTtsLoadModelNative = Int32 Function(
  RaBackendHandle handle,
  Pointer<Utf8> modelPath,
  Pointer<Utf8> modelType,
  Pointer<Utf8> configJson,
);
typedef RaTtsLoadModelDart = int Function(
  RaBackendHandle handle,
  Pointer<Utf8> modelPath,
  Pointer<Utf8> modelType,
  Pointer<Utf8> configJson,
);

/// bool ra_tts_is_model_loaded(ra_backend_handle);
typedef RaTtsIsModelLoadedNative = Bool Function(RaBackendHandle handle);
typedef RaTtsIsModelLoadedDart = bool Function(RaBackendHandle handle);

/// ra_result_code ra_tts_unload_model(ra_backend_handle);
typedef RaTtsUnloadModelNative = Int32 Function(RaBackendHandle handle);
typedef RaTtsUnloadModelDart = int Function(RaBackendHandle handle);

/// ra_result_code ra_tts_synthesize(handle, text, voice_id, speed, pitch, samples, num_samples, sample_rate);
typedef RaTtsSynthesizeNative = Int32 Function(
  RaBackendHandle handle,
  Pointer<Utf8> text,
  Pointer<Utf8> voiceId,
  Float speed,
  Float pitch,
  Pointer<Pointer<Float>> audioSamples,
  Pointer<IntPtr> numSamples,
  Pointer<Int32> sampleRate,
);
typedef RaTtsSynthesizeDart = int Function(
  RaBackendHandle handle,
  Pointer<Utf8> text,
  Pointer<Utf8> voiceId,
  double speed,
  double pitch,
  Pointer<Pointer<Float>> audioSamples,
  Pointer<IntPtr> numSamples,
  Pointer<Int32> sampleRate,
);

/// bool ra_tts_supports_streaming(ra_backend_handle);
typedef RaTtsSupportsStreamingNative = Bool Function(RaBackendHandle handle);
typedef RaTtsSupportsStreamingDart = bool Function(RaBackendHandle handle);

/// char* ra_tts_get_voices(ra_backend_handle);
typedef RaTtsGetVoicesNative = Pointer<Utf8> Function(RaBackendHandle handle);
typedef RaTtsGetVoicesDart = Pointer<Utf8> Function(RaBackendHandle handle);

/// void ra_tts_cancel(handle);
typedef RaTtsCancelNative = Void Function(RaBackendHandle handle);
typedef RaTtsCancelDart = void Function(RaBackendHandle handle);

// =============================================================================
// FFI Function Signatures - LLM (Text Generation)
// =============================================================================

/// ra_result_code ra_text_load_model(handle, model_path, config_json);
typedef RaTextLoadModelNative = Int32 Function(
  RaBackendHandle handle,
  Pointer<Utf8> modelPath,
  Pointer<Utf8> configJson,
);
typedef RaTextLoadModelDart = int Function(
  RaBackendHandle handle,
  Pointer<Utf8> modelPath,
  Pointer<Utf8> configJson,
);

/// bool ra_text_is_model_loaded(ra_backend_handle);
typedef RaTextIsModelLoadedNative = Bool Function(RaBackendHandle handle);
typedef RaTextIsModelLoadedDart = bool Function(RaBackendHandle handle);

/// ra_result_code ra_text_unload_model(ra_backend_handle);
typedef RaTextUnloadModelNative = Int32 Function(RaBackendHandle handle);
typedef RaTextUnloadModelDart = int Function(RaBackendHandle handle);

/// ra_result_code ra_text_generate(handle, prompt, system_prompt, max_tokens, temperature, result_json);
typedef RaTextGenerateNative = Int32 Function(
  RaBackendHandle handle,
  Pointer<Utf8> prompt,
  Pointer<Utf8> systemPrompt,
  Int32 maxTokens,
  Float temperature,
  Pointer<Pointer<Utf8>> resultJson,
);
typedef RaTextGenerateDart = int Function(
  RaBackendHandle handle,
  Pointer<Utf8> prompt,
  Pointer<Utf8> systemPrompt,
  int maxTokens,
  double temperature,
  Pointer<Pointer<Utf8>> resultJson,
);

/// ra_result_code ra_text_generate_stream(handle, prompt, system_prompt, max_tokens, temperature, callback, user_data);
typedef RaTextGenerateStreamNative = Int32 Function(
  RaBackendHandle handle,
  Pointer<Utf8> prompt,
  Pointer<Utf8> systemPrompt,
  Int32 maxTokens,
  Float temperature,
  Pointer<NativeFunction<RaTextStreamCallbackNative>> callback,
  Pointer<Void> userData,
);
typedef RaTextGenerateStreamDart = int Function(
  RaBackendHandle handle,
  Pointer<Utf8> prompt,
  Pointer<Utf8> systemPrompt,
  int maxTokens,
  double temperature,
  Pointer<NativeFunction<RaTextStreamCallbackNative>> callback,
  Pointer<Void> userData,
);

/// void ra_text_cancel(handle);
typedef RaTextCancelNative = Void Function(RaBackendHandle handle);
typedef RaTextCancelDart = void Function(RaBackendHandle handle);

// =============================================================================
// FFI Function Signatures - VAD (Voice Activity Detection)
// =============================================================================

/// ra_result_code ra_vad_load_model(handle, model_path, config_json);
typedef RaVadLoadModelNative = Int32 Function(
  RaBackendHandle handle,
  Pointer<Utf8> modelPath,
  Pointer<Utf8> configJson,
);
typedef RaVadLoadModelDart = int Function(
  RaBackendHandle handle,
  Pointer<Utf8> modelPath,
  Pointer<Utf8> configJson,
);

/// bool ra_vad_is_model_loaded(ra_backend_handle);
typedef RaVadIsModelLoadedNative = Bool Function(RaBackendHandle handle);
typedef RaVadIsModelLoadedDart = bool Function(RaBackendHandle handle);

/// ra_result_code ra_vad_unload_model(ra_backend_handle);
typedef RaVadUnloadModelNative = Int32 Function(RaBackendHandle handle);
typedef RaVadUnloadModelDart = int Function(RaBackendHandle handle);

/// ra_result_code ra_vad_process(handle, samples, num_samples, sample_rate, is_speech, probability);
typedef RaVadProcessNative = Int32 Function(
  RaBackendHandle handle,
  Pointer<Float> samples,
  IntPtr numSamples,
  Int32 sampleRate,
  Pointer<Bool> isSpeech,
  Pointer<Float> probability,
);
typedef RaVadProcessDart = int Function(
  RaBackendHandle handle,
  Pointer<Float> samples,
  int numSamples,
  int sampleRate,
  Pointer<Bool> isSpeech,
  Pointer<Float> probability,
);

/// ra_stream_handle ra_vad_create_stream(handle, config_json);
typedef RaVadCreateStreamNative = RaStreamHandle Function(
  RaBackendHandle handle,
  Pointer<Utf8> configJson,
);
typedef RaVadCreateStreamDart = RaStreamHandle Function(
  RaBackendHandle handle,
  Pointer<Utf8> configJson,
);

/// void ra_vad_destroy_stream(backend, stream);
typedef RaVadDestroyStreamNative = Void Function(
  RaBackendHandle backend,
  RaStreamHandle stream,
);
typedef RaVadDestroyStreamDart = void Function(
  RaBackendHandle backend,
  RaStreamHandle stream,
);

/// void ra_vad_reset(handle);
typedef RaVadResetNative = Void Function(RaBackendHandle handle);
typedef RaVadResetDart = void Function(RaBackendHandle handle);

// =============================================================================
// FFI Function Signatures - Embeddings
// =============================================================================

/// ra_result_code ra_embed_load_model(handle, model_path, config_json);
typedef RaEmbedLoadModelNative = Int32 Function(
  RaBackendHandle handle,
  Pointer<Utf8> modelPath,
  Pointer<Utf8> configJson,
);
typedef RaEmbedLoadModelDart = int Function(
  RaBackendHandle handle,
  Pointer<Utf8> modelPath,
  Pointer<Utf8> configJson,
);

/// bool ra_embed_is_model_loaded(ra_backend_handle);
typedef RaEmbedIsModelLoadedNative = Bool Function(RaBackendHandle handle);
typedef RaEmbedIsModelLoadedDart = bool Function(RaBackendHandle handle);

/// ra_result_code ra_embed_text(handle, text, embedding, dimensions);
typedef RaEmbedTextNative = Int32 Function(
  RaBackendHandle handle,
  Pointer<Utf8> text,
  Pointer<Pointer<Float>> embedding,
  Pointer<Int32> dimensions,
);
typedef RaEmbedTextDart = int Function(
  RaBackendHandle handle,
  Pointer<Utf8> text,
  Pointer<Pointer<Float>> embedding,
  Pointer<Int32> dimensions,
);

/// int ra_embed_get_dimensions(ra_backend_handle);
typedef RaEmbedGetDimensionsNative = Int32 Function(RaBackendHandle handle);
typedef RaEmbedGetDimensionsDart = int Function(RaBackendHandle handle);

// =============================================================================
// FFI Function Signatures - Memory Management
// =============================================================================

/// void ra_free_string(char* str);
typedef RaFreeStringNative = Void Function(Pointer<Utf8> str);
typedef RaFreeStringDart = void Function(Pointer<Utf8> str);

/// void ra_free_audio(float* audio_samples);
typedef RaFreeAudioNative = Void Function(Pointer<Float> samples);
typedef RaFreeAudioDart = void Function(Pointer<Float> samples);

/// void ra_free_embedding(float* embedding);
typedef RaFreeEmbeddingNative = Void Function(Pointer<Float> embedding);
typedef RaFreeEmbeddingDart = void Function(Pointer<Float> embedding);

// =============================================================================
// FFI Function Signatures - Utility
// =============================================================================

/// const char* ra_get_last_error(void);
typedef RaGetLastErrorNative = Pointer<Utf8> Function();
typedef RaGetLastErrorDart = Pointer<Utf8> Function();

/// const char* ra_get_version(void);
typedef RaGetVersionNative = Pointer<Utf8> Function();
typedef RaGetVersionDart = Pointer<Utf8> Function();

/// ra_result_code ra_extract_archive(const char* archive_path, const char* dest_dir);
typedef RaExtractArchiveNative = Int32 Function(
  Pointer<Utf8> archivePath,
  Pointer<Utf8> destDir,
);
typedef RaExtractArchiveDart = int Function(
  Pointer<Utf8> archivePath,
  Pointer<Utf8> destDir,
);
