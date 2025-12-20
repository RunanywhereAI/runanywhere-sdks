/**
 * RunAnywhere React Native SDK - Enums
 *
 * These enums match the iOS Swift SDK exactly for consistency.
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/
 */

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
};

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
 */
export enum AudioFormat {
  PCM = 'pcm',
  WAV = 'wav',
  MP3 = 'mp3',
  M4A = 'm4a',
  FLAC = 'flac',
  OPUS = 'opus',
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
