/**
 * RunAnywhere Web SDK - enum bridge.
 *
 * Generated proto-ts enums are the source of truth for public data contracts.
 * This file keeps short Web-facing member names as aliases to generated enum
 * values for existing internal call sites, without defining a second enum
 * value system.
 */

// ---------------------------------------------------------------------------
// Proto-canonical re-exports (wire transport). Use these when talking
// to the commons C ABI or serialising to the wire.
// ---------------------------------------------------------------------------
import {
  ModelFormat as ProtoModelFormat,
  ModelCategory as ProtoModelCategory,
  InferenceFramework as ProtoInferenceFramework,
  AccelerationPreference as ProtoAccelerationPreference,
  RoutingPolicy as ProtoRoutingPolicy,
  SDKEnvironment as ProtoSDKEnvironment,
  AudioFormat as ProtoAudioFormat,
} from '@runanywhere/proto-ts/model_types';
import { SDKComponent as ProtoSDKComponent } from '@runanywhere/proto-ts/sdk_events';

export {
  ProtoAccelerationPreference,
  ProtoAudioFormat,
  ProtoInferenceFramework,
  ProtoModelCategory,
  ProtoModelFormat,
  ProtoRoutingPolicy,
  ProtoSDKEnvironment,
};
export { ProtoSDKComponent };
export { DownloadStage as ProtoDownloadStage } from '@runanywhere/proto-ts/download_service';

// ---------------------------------------------------------------------------
// Generated enum aliases with short Web member names.
// ---------------------------------------------------------------------------

export const SDKEnvironment = {
  Development: ProtoSDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
  Staging: ProtoSDKEnvironment.SDK_ENVIRONMENT_STAGING,
  Production: ProtoSDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
} as const;
export type SDKEnvironment = ProtoSDKEnvironment;

export const LLMFramework = {
  CoreML: ProtoInferenceFramework.INFERENCE_FRAMEWORK_COREML,
  TensorFlowLite: ProtoInferenceFramework.INFERENCE_FRAMEWORK_TFLITE,
  MLX: ProtoInferenceFramework.INFERENCE_FRAMEWORK_MLX,
  SwiftTransformers: ProtoInferenceFramework.INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS,
  ONNX: ProtoInferenceFramework.INFERENCE_FRAMEWORK_ONNX,
  Sherpa: ProtoInferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
  ExecuTorch: ProtoInferenceFramework.INFERENCE_FRAMEWORK_EXECUTORCH,
  LlamaCpp: ProtoInferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
  FoundationModels: ProtoInferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS,
  PicoLLM: ProtoInferenceFramework.INFERENCE_FRAMEWORK_PICO_LLM,
  MLC: ProtoInferenceFramework.INFERENCE_FRAMEWORK_MLC,
  MediaPipe: ProtoInferenceFramework.INFERENCE_FRAMEWORK_MEDIAPIPE,
  WhisperKit: ProtoInferenceFramework.INFERENCE_FRAMEWORK_WHISPERKIT,
  OpenAIWhisper: ProtoInferenceFramework.INFERENCE_FRAMEWORK_OPENAI_WHISPER,
  SystemTTS: ProtoInferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS,
  PiperTTS: ProtoInferenceFramework.INFERENCE_FRAMEWORK_PIPER_TTS,
} as const;
export type LLMFramework = ProtoInferenceFramework;
export { ProtoInferenceFramework as InferenceFramework };

export const ModelCategory = {
  Language: ProtoModelCategory.MODEL_CATEGORY_LANGUAGE,
  SpeechRecognition: ProtoModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
  SpeechSynthesis: ProtoModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
  Vision: ProtoModelCategory.MODEL_CATEGORY_VISION,
  ImageGeneration: ProtoModelCategory.MODEL_CATEGORY_IMAGE_GENERATION,
  Multimodal: ProtoModelCategory.MODEL_CATEGORY_MULTIMODAL,
  Audio: ProtoModelCategory.MODEL_CATEGORY_AUDIO,
  Embedding: ProtoModelCategory.MODEL_CATEGORY_EMBEDDING,
  VoiceActivityDetection: ProtoModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
} as const;
export type ModelCategory = ProtoModelCategory;

export const ModelFormat = {
  GGUF: ProtoModelFormat.MODEL_FORMAT_GGUF,
  GGML: ProtoModelFormat.MODEL_FORMAT_GGML,
  ONNX: ProtoModelFormat.MODEL_FORMAT_ONNX,
  ORT: ProtoModelFormat.MODEL_FORMAT_ORT,
  CoreML: ProtoModelFormat.MODEL_FORMAT_COREML,
  MLModel: ProtoModelFormat.MODEL_FORMAT_MLMODEL,
  MLPackage: ProtoModelFormat.MODEL_FORMAT_MLPACKAGE,
  TFLite: ProtoModelFormat.MODEL_FORMAT_TFLITE,
  SafeTensors: ProtoModelFormat.MODEL_FORMAT_SAFETENSORS,
  QNNContext: ProtoModelFormat.MODEL_FORMAT_QNN_CONTEXT,
  Bin: ProtoModelFormat.MODEL_FORMAT_BIN,
  Zip: ProtoModelFormat.MODEL_FORMAT_ZIP,
  Folder: ProtoModelFormat.MODEL_FORMAT_FOLDER,
  Proprietary: ProtoModelFormat.MODEL_FORMAT_PROPRIETARY,
  Unknown: ProtoModelFormat.MODEL_FORMAT_UNKNOWN,
} as const;
export type ModelFormat = ProtoModelFormat;

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

export const SDKComponent = {
  LLM: ProtoSDKComponent.SDK_COMPONENT_LLM,
  STT: ProtoSDKComponent.SDK_COMPONENT_STT,
  TTS: ProtoSDKComponent.SDK_COMPONENT_TTS,
  VAD: ProtoSDKComponent.SDK_COMPONENT_VAD,
  VLM: ProtoSDKComponent.SDK_COMPONENT_VLM,
  Embedding: ProtoSDKComponent.SDK_COMPONENT_EMBEDDINGS,
  Diffusion: ProtoSDKComponent.SDK_COMPONENT_DIFFUSION,
  RAG: ProtoSDKComponent.SDK_COMPONENT_RAG,
  SpeakerDiarization: ProtoSDKComponent.SDK_COMPONENT_SPEAKER_DIARIZATION,
  VoiceAgent: ProtoSDKComponent.SDK_COMPONENT_VOICE_AGENT,
  WakeWord: ProtoSDKComponent.SDK_COMPONENT_WAKEWORD,
} as const;
export type SDKComponent = ProtoSDKComponent;

export const RoutingPolicy = {
  OnDevicePreferred: ProtoRoutingPolicy.ROUTING_POLICY_PREFER_LOCAL,
  CloudPreferred: ProtoRoutingPolicy.ROUTING_POLICY_PREFER_CLOUD,
  OnDeviceOnly: ProtoRoutingPolicy.ROUTING_POLICY_PREFER_LOCAL,
  CloudOnly: ProtoRoutingPolicy.ROUTING_POLICY_PREFER_CLOUD,
  Hybrid: ProtoRoutingPolicy.ROUTING_POLICY_MANUAL,
  CostOptimized: ProtoRoutingPolicy.ROUTING_POLICY_COST_OPTIMIZED,
  LatencyOptimized: ProtoRoutingPolicy.ROUTING_POLICY_LATENCY_OPTIMIZED,
  PrivacyOptimized: ProtoRoutingPolicy.ROUTING_POLICY_PREFER_LOCAL,
} as const;
export type RoutingPolicy = ProtoRoutingPolicy;

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

/**
 * Canonical `DownloadStage` is proto-generated (integer enum, 5 values).
 * The Web-local string enum previously defined here has been deleted —
 * per-SDK type unification (Task M8). Consumers that need a string form
 * should derive it from the proto enum value.
 */
export { DownloadStage, DownloadState } from '@runanywhere/proto-ts/download_service';

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

export const AccelerationPreference = {
  Auto: ProtoAccelerationPreference.ACCELERATION_PREFERENCE_AUTO,
  WebGPU: ProtoAccelerationPreference.ACCELERATION_PREFERENCE_WEBGPU,
  CPU: ProtoAccelerationPreference.ACCELERATION_PREFERENCE_CPU,
  GPU: ProtoAccelerationPreference.ACCELERATION_PREFERENCE_GPU,
  NPU: ProtoAccelerationPreference.ACCELERATION_PREFERENCE_NPU,
  Metal: ProtoAccelerationPreference.ACCELERATION_PREFERENCE_METAL,
  Vulkan: ProtoAccelerationPreference.ACCELERATION_PREFERENCE_VULKAN,
} as const;
export type AccelerationPreference = ProtoAccelerationPreference;
