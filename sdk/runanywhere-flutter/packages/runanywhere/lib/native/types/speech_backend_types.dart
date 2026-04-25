// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/native/types/basic_types.dart';

// =============================================================================
// STT ONNX API Function Signatures (from rac_stt_onnx.h)
// =============================================================================

/// rac_result_t rac_stt_onnx_create(const char* model_path, const rac_stt_onnx_config_t* config, rac_handle_t* out_handle)
typedef RacSttOnnxCreateNative = Int32 Function(
  Pointer<Utf8> modelPath,
  Pointer<Void> config,
  Pointer<RacHandle> outHandle,
);
typedef RacSttOnnxCreateDart = int Function(
  Pointer<Utf8> modelPath,
  Pointer<Void> config,
  Pointer<RacHandle> outHandle,
);

/// rac_result_t rac_stt_onnx_transcribe(rac_handle_t handle, const float* audio_samples, size_t num_samples, const rac_stt_options_t* options, rac_stt_result_t* out_result)
typedef RacSttOnnxTranscribeNative = Int32 Function(
  RacHandle handle,
  Pointer<Float> audioSamples,
  IntPtr numSamples,
  Pointer<Void> options,
  Pointer<Void> outResult,
);
typedef RacSttOnnxTranscribeDart = int Function(
  RacHandle handle,
  Pointer<Float> audioSamples,
  int numSamples,
  Pointer<Void> options,
  Pointer<Void> outResult,
);

/// rac_bool_t rac_stt_onnx_supports_streaming(rac_handle_t handle)
typedef RacSttOnnxSupportsStreamingNative = Int32 Function(RacHandle handle);
typedef RacSttOnnxSupportsStreamingDart = int Function(RacHandle handle);

/// rac_result_t rac_stt_onnx_create_stream(rac_handle_t handle, rac_handle_t* out_stream)
typedef RacSttOnnxCreateStreamNative = Int32 Function(
  RacHandle handle,
  Pointer<RacHandle> outStream,
);
typedef RacSttOnnxCreateStreamDart = int Function(
  RacHandle handle,
  Pointer<RacHandle> outStream,
);

/// rac_result_t rac_stt_onnx_feed_audio(rac_handle_t handle, rac_handle_t stream, const float* audio_samples, size_t num_samples)
typedef RacSttOnnxFeedAudioNative = Int32 Function(
  RacHandle handle,
  RacHandle stream,
  Pointer<Float> audioSamples,
  IntPtr numSamples,
);
typedef RacSttOnnxFeedAudioDart = int Function(
  RacHandle handle,
  RacHandle stream,
  Pointer<Float> audioSamples,
  int numSamples,
);

/// rac_bool_t rac_stt_onnx_stream_is_ready(rac_handle_t handle, rac_handle_t stream)
typedef RacSttOnnxStreamIsReadyNative = Int32 Function(
  RacHandle handle,
  RacHandle stream,
);
typedef RacSttOnnxStreamIsReadyDart = int Function(
  RacHandle handle,
  RacHandle stream,
);

/// rac_result_t rac_stt_onnx_decode_stream(rac_handle_t handle, rac_handle_t stream, char** out_text)
typedef RacSttOnnxDecodeStreamNative = Int32 Function(
  RacHandle handle,
  RacHandle stream,
  Pointer<Pointer<Utf8>> outText,
);
typedef RacSttOnnxDecodeStreamDart = int Function(
  RacHandle handle,
  RacHandle stream,
  Pointer<Pointer<Utf8>> outText,
);

/// void rac_stt_onnx_input_finished(rac_handle_t handle, rac_handle_t stream)
typedef RacSttOnnxInputFinishedNative = Void Function(
  RacHandle handle,
  RacHandle stream,
);
typedef RacSttOnnxInputFinishedDart = void Function(
  RacHandle handle,
  RacHandle stream,
);

/// rac_bool_t rac_stt_onnx_is_endpoint(rac_handle_t handle, rac_handle_t stream)
typedef RacSttOnnxIsEndpointNative = Int32 Function(
  RacHandle handle,
  RacHandle stream,
);
typedef RacSttOnnxIsEndpointDart = int Function(
  RacHandle handle,
  RacHandle stream,
);

/// void rac_stt_onnx_destroy_stream(rac_handle_t handle, rac_handle_t stream)
typedef RacSttOnnxDestroyStreamNative = Void Function(
  RacHandle handle,
  RacHandle stream,
);
typedef RacSttOnnxDestroyStreamDart = void Function(
  RacHandle handle,
  RacHandle stream,
);

/// void rac_stt_onnx_destroy(rac_handle_t handle)
typedef RacSttOnnxDestroyNative = Void Function(RacHandle handle);
typedef RacSttOnnxDestroyDart = void Function(RacHandle handle);

// =============================================================================
// TTS ONNX API Function Signatures (from rac_tts_onnx.h)
// =============================================================================

/// rac_result_t rac_tts_onnx_create(const char* model_path, const rac_tts_onnx_config_t* config, rac_handle_t* out_handle)
typedef RacTtsOnnxCreateNative = Int32 Function(
  Pointer<Utf8> modelPath,
  Pointer<Void> config,
  Pointer<RacHandle> outHandle,
);
typedef RacTtsOnnxCreateDart = int Function(
  Pointer<Utf8> modelPath,
  Pointer<Void> config,
  Pointer<RacHandle> outHandle,
);

/// rac_result_t rac_tts_onnx_synthesize(rac_handle_t handle, const char* text, const rac_tts_options_t* options, rac_tts_result_t* out_result)
typedef RacTtsOnnxSynthesizeNative = Int32 Function(
  RacHandle handle,
  Pointer<Utf8> text,
  Pointer<Void> options,
  Pointer<Void> outResult,
);
typedef RacTtsOnnxSynthesizeDart = int Function(
  RacHandle handle,
  Pointer<Utf8> text,
  Pointer<Void> options,
  Pointer<Void> outResult,
);

/// rac_result_t rac_tts_onnx_get_voices(rac_handle_t handle, char*** out_voices, size_t* out_count)
typedef RacTtsOnnxGetVoicesNative = Int32 Function(
  RacHandle handle,
  Pointer<Pointer<Pointer<Utf8>>> outVoices,
  Pointer<IntPtr> outCount,
);
typedef RacTtsOnnxGetVoicesDart = int Function(
  RacHandle handle,
  Pointer<Pointer<Pointer<Utf8>>> outVoices,
  Pointer<IntPtr> outCount,
);

/// void rac_tts_onnx_stop(rac_handle_t handle)
typedef RacTtsOnnxStopNative = Void Function(RacHandle handle);
typedef RacTtsOnnxStopDart = void Function(RacHandle handle);

/// void rac_tts_onnx_destroy(rac_handle_t handle)
typedef RacTtsOnnxDestroyNative = Void Function(RacHandle handle);
typedef RacTtsOnnxDestroyDart = void Function(RacHandle handle);

// =============================================================================
// VAD ONNX Functions (from rac_vad_onnx.h)
// =============================================================================

/// rac_result_t rac_vad_onnx_create(const char* model_path, const rac_vad_onnx_config_t* config, rac_handle_t* out_handle)
typedef RacVadOnnxCreateNative = Int32 Function(
  Pointer<Utf8> modelPath,
  Pointer<Void> config,
  Pointer<RacHandle> outHandle,
);
typedef RacVadOnnxCreateDart = int Function(
  Pointer<Utf8> modelPath,
  Pointer<Void> config,
  Pointer<RacHandle> outHandle,
);

/// rac_result_t rac_vad_onnx_process(rac_handle_t handle, const float* samples, size_t num_samples, rac_vad_result_t* out_result)
typedef RacVadOnnxProcessNative = Int32 Function(
  RacHandle handle,
  Pointer<Float> samples,
  IntPtr numSamples,
  Pointer<Void> outResult,
);
typedef RacVadOnnxProcessDart = int Function(
  RacHandle handle,
  Pointer<Float> samples,
  int numSamples,
  Pointer<Void> outResult,
);

/// void rac_vad_onnx_destroy(rac_handle_t handle)
typedef RacVadOnnxDestroyNative = Void Function(RacHandle handle);
typedef RacVadOnnxDestroyDart = void Function(RacHandle handle);
