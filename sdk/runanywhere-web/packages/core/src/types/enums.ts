/**
 * RunAnywhere Web SDK — Enums.
 *
 * Wave 4.5 cleanup (CANONICAL_API.md §15): the proto-canonical wire
 * representation of every enum below lives in `@runanywhere/proto-ts/*`
 * and is re-exported from this file under `Proto*` aliases. The Web SDK
 * preserves a parallel set of *string-valued ergonomic enums* because
 *
 *   1. The Web public API surface has historically exposed
 *      PascalCase/kebab-case string values (e.g. `ModelCategory.Language
 *      === 'language'`) that appear verbatim in persisted model catalog
 *      metadata, `localStorage` entries and URL query params.
 *   2. The generated proto-ts enums are numeric with
 *      `SCREAMING_SNAKE_CASE` keys (proto3 convention). They are not
 *      drop-in replacements for the string surface.
 *
 * For wire transport / proto round-tripping, import the `Proto*` alias
 * below (or go directly to `@runanywhere/proto-ts/*`). For day-to-day
 * in-process Web usage, use the ergonomic enum.
 *
 * ExecutionTarget has been DELETED from this file (CANONICAL §15) — the
 * proto-ts variant is re-exported from `types/index.ts` directly and is
 * the single source of truth.
 *
 * Source of truth (wire shape): idl/*.proto → @runanywhere/proto-ts.
 */

// ---------------------------------------------------------------------------
// Proto-canonical re-exports (wire transport). Use these when talking
// to the commons C ABI or serialising to the wire.
// ---------------------------------------------------------------------------
export {
  ModelFormat as ProtoModelFormat,
  ModelCategory as ProtoModelCategory,
  InferenceFramework as ProtoInferenceFramework,
  AccelerationPreference as ProtoAccelerationPreference,
  RoutingPolicy as ProtoRoutingPolicy,
  SDKEnvironment as ProtoSDKEnvironment,
  AudioFormat as ProtoAudioFormat,
} from '@runanywhere/proto-ts/model_types';
export { SDKComponent as ProtoSDKComponent } from '@runanywhere/proto-ts/sdk_events';
export { DownloadStage as ProtoDownloadStage } from '@runanywhere/proto-ts/download_service';

// ---------------------------------------------------------------------------
// Web-ergonomic string enums. Each comments its proto counterpart.
// ---------------------------------------------------------------------------

/** Proto counterpart: `SDKEnvironment` / `ProtoSDKEnvironment`. */
export enum SDKEnvironment {
  Development = 'development',
  Staging = 'staging',
  Production = 'production',
}

/**
 * Proto counterpart: `InferenceFramework` / `ProtoInferenceFramework`.
 * Web names this `LLMFramework` for RN/Swift/Flutter label parity.
 */
export enum LLMFramework {
  CoreML = 'CoreML',
  TensorFlowLite = 'TFLite',
  MLX = 'MLX',
  SwiftTransformers = 'SwiftTransformers',
  ONNX = 'ONNX',
  Sherpa = 'Sherpa', // Sherpa-ONNX speech engine (STT/TTS/VAD/wakeword)
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

/** Proto counterpart: `ModelCategory` / `ProtoModelCategory`. */
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

/** Proto counterpart: `ModelFormat` / `ProtoModelFormat`. */
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

/**
 * Framework modality (I/O types). No direct proto counterpart — used by
 * Web-local model-registry helpers.
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
 * In-process JS state machine for a capability handle. No direct proto
 * counterpart — `ComponentLoadState` in `voice_events.proto` covers a
 * different axis (per-voice-component preload state).
 */
export enum ComponentState {
  NotInitialized = 'notInitialized',
  Initializing = 'initializing',
  Ready = 'ready',
  Error = 'error',
  CleaningUp = 'cleaningUp',
}

/**
 * Proto counterpart: `SDKComponent` / `ProtoSDKComponent`
 * (sdk_events.proto). Web uses a tighter ergonomic string surface.
 */
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

/** Proto counterpart: `RoutingPolicy` / `ProtoRoutingPolicy`. */
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
 * Hardware acceleration targets. No proto counterpart yet (G-B1 adds
 * `hardware_profile.proto`; once that lands, merge with `AcceleratorPreference`
 * in `@runanywhere/proto-ts/hardware_profile`). WebGPU / WASM are
 * browser-specific extensions not present on mobile SDKs.
 */
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

/**
 * Origin of a configuration value. No proto counterpart — describes
 * where a config was loaded from (Web-local metadata).
 */
export enum ConfigurationSource {
  Remote = 'remote',
  Local = 'local',
  Builtin = 'builtin',
}

/**
 * Per-model lifecycle state. No proto counterpart — describes the
 * in-process UI state of a model entry (downloading / downloaded /
 * loaded / error).
 */
export enum ModelStatus {
  Registered = 'registered',
  Downloading = 'downloading',
  Downloaded = 'downloaded',
  Loading = 'loading',
  Loaded = 'loaded',
  Error = 'error',
}

/** Proto counterpart: `DownloadStage` / `ProtoDownloadStage`. */
export enum DownloadStage {
  Downloading = 'downloading',
  Validating = 'validating',
  Completed = 'completed',
}

/**
 * JS `EventBus` topic category. Maps loosely onto the `category` field
 * of proto `SDKEvent` but the proto categories are a larger set — this
 * is the Web-local subset actually emitted by `EventBus`.
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

/**
 * Hardware acceleration preference passed to SDK initialization. The
 * proto counterpart (`AccelerationPreference` / `ProtoAccelerationPreference`)
 * covers the mobile/desktop modes; Web adds a browser-specific
 * WebGPU-or-CPU three-way.
 */
export enum AccelerationPreference {
  /** Detect WebGPU and use it when available, fall back to CPU. */
  Auto = 'auto',
  /** Force WebGPU (fails gracefully to CPU if unavailable). */
  WebGPU = 'webgpu',
  /** Always use CPU-only WASM (skip WebGPU detection entirely). */
  CPU = 'cpu',
}
