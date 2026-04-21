/**
 * RunAnywhere Web SDK — Enums.
 *
 * These enums match the iOS Swift SDK exactly for consistency.
 * Mirrored from: sdk/runanywhere-react-native/packages/core/src/types/enums.ts
 * Source of truth: sdk/runanywhere-swift/Sources/RunAnywhere/Core/
 *
 * GAP 01 Phase 5: each IDL-backed enum below ships a `<name>ToProto()` /
 * `<name>FromProto()` helper that bridges to the ts-proto-generated numeric
 * enum under `./generated/model_types`. Adding a case on either side forces
 * the mapping to cover it; the CI drift-check enforces freshness.
 */
import * as proto from '../generated/model_types';

export enum SDKEnvironment {
  Development = 'development',
  Staging = 'staging',
  Production = 'production',
}

export enum ExecutionTarget {
  OnDevice = 'onDevice',
  Cloud = 'cloud',
  Hybrid = 'hybrid',
}

export enum LLMFramework {
  CoreML = 'CoreML',
  TensorFlowLite = 'TFLite',
  MLX = 'MLX',
  SwiftTransformers = 'SwiftTransformers',
  ONNX = 'ONNX',
  ExecuTorch = 'ExecuTorch',
  LlamaCpp = 'LlamaCpp',
  FoundationModels = 'FoundationModels',
  PicoLLM = 'PicoLLM',
  MLC = 'MLC',
  MediaPipe = 'MediaPipe',
  WhisperKit = 'WhisperKit',
  OpenAIWhisper = 'OpenAIWhisper',
  SystemTTS = 'SystemTTS',
  PiperTTS = 'PiperTTS',
}

export enum ModelCategory {
  /** Large Language Models (LLM) for text generation. */
  Language = 'language',
  /** Speech-to-Text (STT) transcription models (~105 MB+). */
  SpeechRecognition = 'speech-recognition',
  /** Text-to-Speech (TTS) synthesis models. */
  SpeechSynthesis = 'speech-synthesis',
  /** Vision-Language Models (VLM) for image understanding. */
  Vision = 'vision',
  /** Diffusion / image generation models. */
  ImageGeneration = 'image-generation',
  /** Models combining multiple modalities. */
  Multimodal = 'multimodal',
  /** Voice Activity Detection (VAD) — detects speech boundaries (~5 MB). Not transcription — use SpeechRecognition for STT. */
  Audio = 'audio',
}

export enum ModelFormat {
  GGUF = 'gguf',
  GGML = 'ggml',
  ONNX = 'onnx',
  MLModel = 'mlmodel',
  MLPackage = 'mlpackage',
  TFLite = 'tflite',
  SafeTensors = 'safetensors',
  Bin = 'bin',
  Zip = 'zip',
  Folder = 'folder',
  Proprietary = 'proprietary',
  Unknown = 'unknown',
}

export enum FrameworkModality {
  TextToText = 'textToText',
  VoiceToText = 'voiceToText',
  TextToVoice = 'textToVoice',
  ImageToText = 'imageToText',
  TextToImage = 'textToImage',
  Multimodal = 'multimodal',
}

export enum ComponentState {
  NotInitialized = 'notInitialized',
  Initializing = 'initializing',
  Ready = 'ready',
  Error = 'error',
  CleaningUp = 'cleaningUp',
}

export enum SDKComponent {
  LLM = 'llm',
  STT = 'stt',
  TTS = 'tts',
  VAD = 'vad',
  VLM = 'vlm',
  Embedding = 'embedding',
  Diffusion = 'diffusion',
  SpeakerDiarization = 'speakerDiarization',
  VoiceAgent = 'voice',
}

export enum RoutingPolicy {
  OnDevicePreferred = 'onDevicePreferred',
  CloudPreferred = 'cloudPreferred',
  OnDeviceOnly = 'onDeviceOnly',
  CloudOnly = 'cloudOnly',
  Hybrid = 'hybrid',
  CostOptimized = 'costOptimized',
  LatencyOptimized = 'latencyOptimized',
  PrivacyOptimized = 'privacyOptimized',
}

export enum HardwareAcceleration {
  CPU = 'cpu',
  GPU = 'gpu',
  NeuralEngine = 'neuralEngine',
  NPU = 'npu',
  /** WebGPU acceleration (browser-specific) */
  WebGPU = 'webgpu',
  /** WebAssembly SIMD (browser-specific) */
  WASM = 'wasm',
}

export enum ConfigurationSource {
  Remote = 'remote',
  Local = 'local',
  Builtin = 'builtin',
}

export enum ModelStatus {
  Registered = 'registered',
  Downloading = 'downloading',
  Downloaded = 'downloaded',
  Loading = 'loading',
  Loaded = 'loaded',
  Error = 'error',
}

export enum DownloadStage {
  Downloading = 'downloading',
  Validating = 'validating',
  Completed = 'completed',
}

export enum SDKEventType {
  Initialization = 'initialization',
  Configuration = 'configuration',
  Generation = 'generation',
  Model = 'model',
  Voice = 'voice',
  Storage = 'storage',
  Framework = 'framework',
  Device = 'device',
  Error = 'error',
  Performance = 'performance',
  Network = 'network',
}

/** Hardware acceleration preference for SDK initialization. */
export enum AccelerationPreference {
  /** Detect WebGPU and use it when available, fall back to CPU. */
  Auto = 'auto',
  /** Force WebGPU (fails gracefully to CPU if unavailable). */
  WebGPU = 'webgpu',
  /** Always use CPU-only WASM (skip WebGPU detection entirely). */
  CPU = 'cpu',
}

// ────────────────────────────────────────────────────────────────────────────
// Proto ↔ TS bridges (GAP 01 Phase 5 — drift prevention)
// ────────────────────────────────────────────────────────────────────────────

export function sdkEnvironmentToProto(e: SDKEnvironment): proto.SDKEnvironment {
  switch (e) {
    case SDKEnvironment.Development: return proto.SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
    case SDKEnvironment.Staging:     return proto.SDKEnvironment.SDK_ENVIRONMENT_STAGING;
    case SDKEnvironment.Production:  return proto.SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION;
  }
}

export function sdkEnvironmentFromProto(p: proto.SDKEnvironment): SDKEnvironment {
  switch (p) {
    case proto.SDKEnvironment.SDK_ENVIRONMENT_STAGING:    return SDKEnvironment.Staging;
    case proto.SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION: return SDKEnvironment.Production;
    default:                                              return SDKEnvironment.Development;
  }
}

export function modelFormatToProto(f: ModelFormat): proto.ModelFormat {
  switch (f) {
    case ModelFormat.GGUF:        return proto.ModelFormat.MODEL_FORMAT_GGUF;
    case ModelFormat.GGML:        return proto.ModelFormat.MODEL_FORMAT_GGML;
    case ModelFormat.ONNX:        return proto.ModelFormat.MODEL_FORMAT_ONNX;
    case ModelFormat.MLModel:     return proto.ModelFormat.MODEL_FORMAT_MLMODEL;
    case ModelFormat.MLPackage:   return proto.ModelFormat.MODEL_FORMAT_MLPACKAGE;
    case ModelFormat.TFLite:      return proto.ModelFormat.MODEL_FORMAT_TFLITE;
    case ModelFormat.SafeTensors: return proto.ModelFormat.MODEL_FORMAT_SAFETENSORS;
    case ModelFormat.Bin:         return proto.ModelFormat.MODEL_FORMAT_BIN;
    case ModelFormat.Zip:         return proto.ModelFormat.MODEL_FORMAT_ZIP;
    case ModelFormat.Folder:      return proto.ModelFormat.MODEL_FORMAT_FOLDER;
    case ModelFormat.Proprietary: return proto.ModelFormat.MODEL_FORMAT_PROPRIETARY;
    case ModelFormat.Unknown:     return proto.ModelFormat.MODEL_FORMAT_UNKNOWN;
  }
}

export function modelFormatFromProto(p: proto.ModelFormat): ModelFormat {
  switch (p) {
    case proto.ModelFormat.MODEL_FORMAT_GGUF:        return ModelFormat.GGUF;
    case proto.ModelFormat.MODEL_FORMAT_GGML:        return ModelFormat.GGML;
    case proto.ModelFormat.MODEL_FORMAT_ONNX:        return ModelFormat.ONNX;
    case proto.ModelFormat.MODEL_FORMAT_MLMODEL:     return ModelFormat.MLModel;
    case proto.ModelFormat.MODEL_FORMAT_MLPACKAGE:   return ModelFormat.MLPackage;
    case proto.ModelFormat.MODEL_FORMAT_TFLITE:      return ModelFormat.TFLite;
    case proto.ModelFormat.MODEL_FORMAT_SAFETENSORS: return ModelFormat.SafeTensors;
    case proto.ModelFormat.MODEL_FORMAT_BIN:         return ModelFormat.Bin;
    case proto.ModelFormat.MODEL_FORMAT_ZIP:         return ModelFormat.Zip;
    case proto.ModelFormat.MODEL_FORMAT_FOLDER:      return ModelFormat.Folder;
    case proto.ModelFormat.MODEL_FORMAT_PROPRIETARY: return ModelFormat.Proprietary;
    default:                                         return ModelFormat.Unknown;
  }
}

export function modelCategoryToProto(c: ModelCategory): proto.ModelCategory {
  switch (c) {
    case ModelCategory.Language:           return proto.ModelCategory.MODEL_CATEGORY_LANGUAGE;
    case ModelCategory.SpeechRecognition:  return proto.ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION;
    case ModelCategory.SpeechSynthesis:    return proto.ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS;
    case ModelCategory.Vision:             return proto.ModelCategory.MODEL_CATEGORY_VISION;
    case ModelCategory.ImageGeneration:    return proto.ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION;
    case ModelCategory.Multimodal:         return proto.ModelCategory.MODEL_CATEGORY_MULTIMODAL;
    case ModelCategory.Audio:              return proto.ModelCategory.MODEL_CATEGORY_AUDIO;
  }
}

export function modelCategoryFromProto(p: proto.ModelCategory): ModelCategory {
  switch (p) {
    case proto.ModelCategory.MODEL_CATEGORY_LANGUAGE:           return ModelCategory.Language;
    case proto.ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION: return ModelCategory.SpeechRecognition;
    case proto.ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS:   return ModelCategory.SpeechSynthesis;
    case proto.ModelCategory.MODEL_CATEGORY_VISION:             return ModelCategory.Vision;
    case proto.ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION:   return ModelCategory.ImageGeneration;
    case proto.ModelCategory.MODEL_CATEGORY_MULTIMODAL:         return ModelCategory.Multimodal;
    default:                                                    return ModelCategory.Audio;
  }
}

export function llmFrameworkToProto(f: LLMFramework): proto.InferenceFramework {
  switch (f) {
    case LLMFramework.CoreML:             return proto.InferenceFramework.INFERENCE_FRAMEWORK_COREML;
    case LLMFramework.TensorFlowLite:     return proto.InferenceFramework.INFERENCE_FRAMEWORK_TFLITE;
    case LLMFramework.MLX:                return proto.InferenceFramework.INFERENCE_FRAMEWORK_MLX;
    case LLMFramework.SwiftTransformers:  return proto.InferenceFramework.INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS;
    case LLMFramework.ONNX:               return proto.InferenceFramework.INFERENCE_FRAMEWORK_ONNX;
    case LLMFramework.ExecuTorch:         return proto.InferenceFramework.INFERENCE_FRAMEWORK_EXECUTORCH;
    case LLMFramework.LlamaCpp:           return proto.InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP;
    case LLMFramework.FoundationModels:   return proto.InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS;
    case LLMFramework.PicoLLM:            return proto.InferenceFramework.INFERENCE_FRAMEWORK_PICO_LLM;
    case LLMFramework.MLC:                return proto.InferenceFramework.INFERENCE_FRAMEWORK_MLC;
    case LLMFramework.MediaPipe:          return proto.InferenceFramework.INFERENCE_FRAMEWORK_MEDIAPIPE;
    case LLMFramework.WhisperKit:         return proto.InferenceFramework.INFERENCE_FRAMEWORK_WHISPERKIT;
    case LLMFramework.OpenAIWhisper:      return proto.InferenceFramework.INFERENCE_FRAMEWORK_OPENAI_WHISPER;
    case LLMFramework.SystemTTS:          return proto.InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS;
    case LLMFramework.PiperTTS:           return proto.InferenceFramework.INFERENCE_FRAMEWORK_PIPER_TTS;
  }
}

export function llmFrameworkFromProto(p: proto.InferenceFramework): LLMFramework | undefined {
  switch (p) {
    case proto.InferenceFramework.INFERENCE_FRAMEWORK_COREML:              return LLMFramework.CoreML;
    case proto.InferenceFramework.INFERENCE_FRAMEWORK_TFLITE:              return LLMFramework.TensorFlowLite;
    case proto.InferenceFramework.INFERENCE_FRAMEWORK_MLX:                 return LLMFramework.MLX;
    case proto.InferenceFramework.INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS:  return LLMFramework.SwiftTransformers;
    case proto.InferenceFramework.INFERENCE_FRAMEWORK_ONNX:                return LLMFramework.ONNX;
    case proto.InferenceFramework.INFERENCE_FRAMEWORK_EXECUTORCH:          return LLMFramework.ExecuTorch;
    case proto.InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP:           return LLMFramework.LlamaCpp;
    case proto.InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS:   return LLMFramework.FoundationModels;
    case proto.InferenceFramework.INFERENCE_FRAMEWORK_PICO_LLM:            return LLMFramework.PicoLLM;
    case proto.InferenceFramework.INFERENCE_FRAMEWORK_MLC:                 return LLMFramework.MLC;
    case proto.InferenceFramework.INFERENCE_FRAMEWORK_MEDIAPIPE:           return LLMFramework.MediaPipe;
    case proto.InferenceFramework.INFERENCE_FRAMEWORK_WHISPERKIT:          return LLMFramework.WhisperKit;
    case proto.InferenceFramework.INFERENCE_FRAMEWORK_OPENAI_WHISPER:      return LLMFramework.OpenAIWhisper;
    case proto.InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS:          return LLMFramework.SystemTTS;
    case proto.InferenceFramework.INFERENCE_FRAMEWORK_PIPER_TTS:           return LLMFramework.PiperTTS;
    default:                                                                return undefined;
  }
}
