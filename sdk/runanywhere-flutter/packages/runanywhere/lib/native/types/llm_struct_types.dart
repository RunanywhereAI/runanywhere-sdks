// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:ffi';

import 'package:ffi/ffi.dart';


/// LlamaCPP config struct matching rac_llm_llamacpp_config_t
base class RacLlmLlamacppConfigStruct extends Struct {
  @Int32()
  external int contextSize;

  @Int32()
  external int numThreads;

  @Int32()
  external int gpuLayers;

  @Int32()
  external int batchSize;
}

/// LLM options struct matching rac_llm_options_t
base class RacLlmOptionsStruct extends Struct {
  @Int32()
  external int maxTokens;

  @Float()
  external double temperature;

  @Float()
  external double topP;

  external Pointer<Pointer<Utf8>> stopSequences;

  @IntPtr()
  external int numStopSequences;

  @Int32()
  external int streamingEnabled;

  external Pointer<Utf8> systemPrompt;
}

/// LLM result struct matching rac_llm_result_t
base class RacLlmResultStruct extends Struct {
  external Pointer<Utf8> text;

  @Int32()
  external int promptTokens;

  @Int32()
  external int completionTokens;

  @Int32()
  external int totalTokens;

  @Int64()
  external int timeToFirstTokenMs;

  @Int64()
  external int totalTimeMs;

  @Float()
  external double tokensPerSecond;
}
