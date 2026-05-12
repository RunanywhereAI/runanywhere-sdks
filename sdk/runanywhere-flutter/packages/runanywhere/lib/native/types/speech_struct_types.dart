// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:ffi';


/// STT ONNX config struct matching rac_stt_onnx_config_t
base class RacSttOnnxConfigStruct extends Struct {
  @Int32()
  external int modelType;

  @Int32()
  external int numThreads;

  @Int32()
  external int useCoreml;
}

/// TTS ONNX config struct matching rac_tts_onnx_config_t
base class RacTtsOnnxConfigStruct extends Struct {
  @Int32()
  external int numThreads;

  @Int32()
  external int useCoreml;

  @Int32()
  external int sampleRate;
}

/// VAD ONNX config struct matching rac_vad_onnx_config_t.
///
/// Field order MUST match the C declaration in
/// `include/rac/backends/rac_vad_onnx.h`:
///   int32_t sample_rate;
///   float   energy_threshold;
///   float   frame_length;
///   int32_t num_threads;
base class RacVadOnnxConfigStruct extends Struct {
  @Int32()
  external int sampleRate;

  @Float()
  external double energyThreshold;

  @Float()
  external double frameLength;

  @Int32()
  external int numThreads;
}

