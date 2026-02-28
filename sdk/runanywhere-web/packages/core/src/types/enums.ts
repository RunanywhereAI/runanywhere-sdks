/**
 * RunAnywhere Web SDK - Enums
 *
 * These enums match the iOS Swift SDK exactly for consistency.
 * Mirrored from: sdk/runanywhere-react-native/packages/core/src/types/enums.ts
 * Source of truth: sdk/runanywhere-swift/Sources/RunAnywhere/Core/
 */

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
