// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:ffi';

import 'package:ffi/ffi.dart';


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

/// STT ONNX result struct matching rac_stt_onnx_result_t
base class RacSttOnnxResultStruct extends Struct {
  external Pointer<Utf8> text;

  @Float()
  external double confidence;

  external Pointer<Utf8> language;

  @Int32()
  external int durationMs;
}

/// TTS ONNX result struct matching rac_tts_onnx_result_t
base class RacTtsOnnxResultStruct extends Struct {
  external Pointer<Float> audioSamples;

  @Int32()
  external int numSamples;

  @Int32()
  external int sampleRate;

  @Int32()
  external int durationMs;
}

/// VAD ONNX config struct matching rac_vad_onnx_config_t
base class RacVadOnnxConfigStruct extends Struct {
  @Int32()
  external int numThreads;

  @Int32()
  external int sampleRate;

  @Int32()
  external int windowSizeMs;

  @Float()
  external double threshold;
}

/// VAD ONNX result struct matching rac_vad_onnx_result_t
base class RacVadOnnxResultStruct extends Struct {
  @Int32()
  external int isSpeech;

  @Float()
  external double probability;
}

/// VAD result struct matching rac_vad_result_t
base class RacVadResultStruct extends Struct {
  @Int32()
  external int isSpeech;

  @Float()
  external double energy;

  @Float()
  external double speechProbability;
}
