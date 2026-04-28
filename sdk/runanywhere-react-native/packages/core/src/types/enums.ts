/**
 * RunAnywhere React Native SDK — Enums.
 *
 * These enums match the iOS Swift SDK exactly for consistency.
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/
 *
 * GAP 01 Phase 5: each IDL-backed enum below ships a `toProto<X>()` /
 * `fromProto<X>()` helper that bridges to the ts-proto-generated numeric
 * enum under `@runanywhere/proto-ts/dist/model_types`. Adding a case on either side
 * forces the mapping to cover it; the CI drift-check
 * (.github/workflows/idl-drift-check.yml) catches any gap.
 */
import * as proto from '@runanywhere/proto-ts/dist/model_types';

/**
 * SDK environment for configuration and behavior
 */
export enum SDKEnvironment {
  Development = 'development',
  Staging = 'staging',
  Production = 'production',
}

/**
 * Execution target for generation requests
 */
export enum ExecutionTarget {
  OnDevice = 'onDevice',
  Cloud = 'cloud',
  Hybrid = 'hybrid',
}

/**
 * Supported LLM frameworks
 * Reference: LLMFramework.swift
 */
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
  Genie = 'Genie',
}

/**
 * Human-readable display names for frameworks
 */
export const LLMFrameworkDisplayNames: Record<LLMFramework, string> = {
  [LLMFramework.CoreML]: 'Core ML',
  [LLMFramework.TensorFlowLite]: 'TensorFlow Lite',
  [LLMFramework.MLX]: 'MLX',
  [LLMFramework.SwiftTransformers]: 'Swift Transformers',
  [LLMFramework.ONNX]: 'ONNX Runtime',
  [LLMFramework.ExecuTorch]: 'ExecuTorch',
  [LLMFramework.LlamaCpp]: 'llama.cpp',
  [LLMFramework.FoundationModels]: 'Foundation Models',
  [LLMFramework.PicoLLM]: 'Pico LLM',
  [LLMFramework.MLC]: 'MLC',
  [LLMFramework.MediaPipe]: 'MediaPipe',
  [LLMFramework.WhisperKit]: 'WhisperKit',
  [LLMFramework.OpenAIWhisper]: 'OpenAI Whisper',
  [LLMFramework.SystemTTS]: 'System TTS',
  [LLMFramework.PiperTTS]: 'Piper TTS',
  [LLMFramework.Genie]: 'Qualcomm Genie',
};

/**
 * Model categories based on input/output modality
 * Reference: ModelCategory.swift
 */
export enum ModelCategory {
  Language = 'language',
  SpeechRecognition = 'speech-recognition',
  SpeechSynthesis = 'speech-synthesis',
  Vision = 'vision',
  ImageGeneration = 'image-generation',
  Multimodal = 'multimodal',
  Audio = 'audio',
  Embedding = 'embedding',
}

/**
 * Human-readable display names for model categories
 */
export const ModelCategoryDisplayNames: Record<ModelCategory, string> = {
  [ModelCategory.Language]: 'Language Model',
  [ModelCategory.SpeechRecognition]: 'Speech Recognition',
  [ModelCategory.SpeechSynthesis]: 'Text-to-Speech',
  [ModelCategory.Vision]: 'Vision Model',
  [ModelCategory.ImageGeneration]: 'Image Generation',
  [ModelCategory.Multimodal]: 'Multimodal',
  [ModelCategory.Audio]: 'Audio Processing',
  [ModelCategory.Embedding]: 'Embedding Model',
};

/**
 * Model artifact type for model packaging
 * Reference: ModelArtifactType.swift
 */
export enum ModelArtifactType {
  SingleFile = 'singleFile',
  TarGzArchive = 'tarGzArchive',
  TarBz2Archive = 'tarBz2Archive',
  ZipArchive = 'zipArchive',
}

/**
 * Model file formats
 * Reference: ModelFormat.swift
 */
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
  Proprietary = 'proprietary', // Built-in system models
  Unknown = 'unknown',
}

/**
 * Framework modality (input/output types)
 * Reference: FrameworkModality.swift
 */
export enum FrameworkModality {
  TextToText = 'textToText',
  VoiceToText = 'voiceToText',
  TextToVoice = 'textToVoice',
  ImageToText = 'imageToText',
  TextToImage = 'textToImage',
  Multimodal = 'multimodal',
}

/**
 * Component state for lifecycle management
 */
export enum ComponentState {
  NotInitialized = 'notInitialized',
  Initializing = 'initializing',
  Ready = 'ready',
  Error = 'error',
  CleaningUp = 'cleaningUp',
}

/**
 * SDK component identifiers
 * Note: Values match iOS SDK rawValue
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Types/ComponentTypes.swift
 */
export enum SDKComponent {
  LLM = 'llm',
  STT = 'stt',
  TTS = 'tts',
  VAD = 'vad',
  Embedding = 'embedding',
  SpeakerDiarization = 'speakerDiarization',
  VoiceAgent = 'voice',
}

/**
 * Routing policy for execution decisions
 */
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

/**
 * Privacy mode for data handling
 */
export enum PrivacyMode {
  Public = 'public',
  Private = 'private',
  Restricted = 'restricted',
}

/**
 * Hardware acceleration types
 */
export enum HardwareAcceleration {
  CPU = 'cpu',
  GPU = 'gpu',
  NeuralEngine = 'neuralEngine',
  NPU = 'npu',
}

/**
 * Audio format for STT/TTS
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Types/AudioTypes.swift
 */
export enum AudioFormat {
  PCM = 'pcm',
  WAV = 'wav',
  MP3 = 'mp3',
  M4A = 'm4a',
  FLAC = 'flac',
  OPUS = 'opus',
  AAC = 'aac',
}

/**
 * Get MIME type for audio format
 * @param format Audio format
 * @returns MIME type string
 */
export function getAudioFormatMimeType(format: AudioFormat): string {
  switch (format) {
    case AudioFormat.PCM:
      return 'audio/pcm';
    case AudioFormat.WAV:
      return 'audio/wav';
    case AudioFormat.MP3:
      return 'audio/mpeg';
    case AudioFormat.OPUS:
      return 'audio/opus';
    case AudioFormat.AAC:
      return 'audio/aac';
    case AudioFormat.FLAC:
      return 'audio/flac';
    case AudioFormat.M4A:
      return 'audio/mp4';
  }
}

/**
 * Get file extension for audio format
 * @param format Audio format
 * @returns File extension string (matches enum value)
 */
export function getAudioFormatFileExtension(format: AudioFormat): string {
  return format;
}

/**
 * Configuration source
 */
export enum ConfigurationSource {
  Remote = 'remote',
  Local = 'local',
  Builtin = 'builtin',
}

/**
 * Event types for categorization
 */
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

export function audioFormatToProto(a: AudioFormat): proto.AudioFormat {
  switch (a) {
    case AudioFormat.PCM:  return proto.AudioFormat.AUDIO_FORMAT_PCM;
    case AudioFormat.WAV:  return proto.AudioFormat.AUDIO_FORMAT_WAV;
    case AudioFormat.MP3:  return proto.AudioFormat.AUDIO_FORMAT_MP3;
    case AudioFormat.M4A:  return proto.AudioFormat.AUDIO_FORMAT_M4A;
    case AudioFormat.FLAC: return proto.AudioFormat.AUDIO_FORMAT_FLAC;
    case AudioFormat.OPUS: return proto.AudioFormat.AUDIO_FORMAT_OPUS;
    case AudioFormat.AAC:  return proto.AudioFormat.AUDIO_FORMAT_AAC;
  }
}

export function audioFormatFromProto(p: proto.AudioFormat): AudioFormat | undefined {
  switch (p) {
    case proto.AudioFormat.AUDIO_FORMAT_PCM:  return AudioFormat.PCM;
    case proto.AudioFormat.AUDIO_FORMAT_WAV:  return AudioFormat.WAV;
    case proto.AudioFormat.AUDIO_FORMAT_MP3:  return AudioFormat.MP3;
    case proto.AudioFormat.AUDIO_FORMAT_M4A:  return AudioFormat.M4A;
    case proto.AudioFormat.AUDIO_FORMAT_FLAC: return AudioFormat.FLAC;
    case proto.AudioFormat.AUDIO_FORMAT_OPUS: return AudioFormat.OPUS;
    case proto.AudioFormat.AUDIO_FORMAT_AAC:  return AudioFormat.AAC;
    default:                                   return undefined; // PCM_S16LE / OGG / UNSPEC / UNRECOGNIZED
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
    case ModelCategory.Embedding:          return proto.ModelCategory.MODEL_CATEGORY_EMBEDDING;
  }
}

export function modelCategoryFromProto(p: proto.ModelCategory): ModelCategory {
  switch (p) {
    case proto.ModelCategory.MODEL_CATEGORY_LANGUAGE:                 return ModelCategory.Language;
    case proto.ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION:       return ModelCategory.SpeechRecognition;
    case proto.ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS:         return ModelCategory.SpeechSynthesis;
    case proto.ModelCategory.MODEL_CATEGORY_VISION:                   return ModelCategory.Vision;
    case proto.ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION:         return ModelCategory.ImageGeneration;
    case proto.ModelCategory.MODEL_CATEGORY_MULTIMODAL:               return ModelCategory.Multimodal;
    case proto.ModelCategory.MODEL_CATEGORY_EMBEDDING:                return ModelCategory.Embedding;
    // AUDIO + VOICE_ACTIVITY_DETECTION both collapse to Audio (TS has no VAD category)
    default:                                                          return ModelCategory.Audio;
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
    case LLMFramework.Genie:              return proto.InferenceFramework.INFERENCE_FRAMEWORK_GENIE;
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
    case proto.InferenceFramework.INFERENCE_FRAMEWORK_GENIE:               return LLMFramework.Genie;
    default:                                                                return undefined;
  }
}
