/**
 * RunAnywhere React Native SDK — Enums.
 *
 * G-B2 Round 1 cleanup: every enum that has a proto-canonical
 * counterpart (`@runanywhere/proto-ts/*`) is RE-EXPORTED from there.
 * The few survivors live here only because no proto equivalent exists
 * and each has a clear `// no proto equivalent` doc-comment justifying
 * its survival.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/
 */

// ============================================================================
// Re-exported from @runanywhere/proto-ts — single source of truth.
// ============================================================================

export {
  // sdk_events.proto
  SDKComponent,
  EventSeverity,
  EventDestination,
} from '@runanywhere/proto-ts/sdk_events';

export {
  // llm_options.proto
  ExecutionTarget,
} from '@runanywhere/proto-ts/llm_options';

export {
  // model_types.proto — the canonical option/format/category enums.
  AccelerationPreference,
  AudioFormat,
  InferenceFramework,
  ModelArtifactType,
  ModelCategory,
  ModelFormat,
  RoutingPolicy,
  SDKEnvironment,
} from '@runanywhere/proto-ts/model_types';

// ============================================================================
// RN-only survivors (no proto equivalent — see audit `02_PARITY.md` §"Type-
// coverage gaps (no proto exists)").
// ============================================================================

/**
 * Component lifecycle states. RN-local — describes the in-process JS
 * state machine for a capability handle. No proto counterpart;
 * `ComponentLoadState` from `voice_events.proto` covers a different axis.
 */
export enum ComponentState {
  NotInitialized = 'notInitialized',
  Initializing = 'initializing',
  Ready = 'ready',
  Error = 'error',
  CleaningUp = 'cleaningUp',
}

/**
 * Framework modality (input/output types). RN-local — used by
 * model-registry helpers that have no proto counterpart.
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
 * Configuration source. RN-local — describes where a configuration
 * value originated; no proto carries this metadata today.
 */
export enum ConfigurationSource {
  Remote = 'remote',
  Local = 'local',
  Builtin = 'builtin',
}

/**
 * @deprecated Legacy RN registry bridge labels. New public APIs must use
 * `InferenceFramework` from `@runanywhere/proto-ts/model_types` directly.
 * This survives only until the RN model registry/native JSON bridge returns
 * generated `ModelInfo` proto messages.
 */
export enum LLMFramework {
  CoreML = 'CoreML',
  TensorFlowLite = 'TFLite',
  MLX = 'MLX',
  SwiftTransformers = 'SwiftTransformers',
  ONNX = 'ONNX',
  Sherpa = 'Sherpa',
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
 * Human-readable display names for frameworks. RN-local helper; no
 * proto counterpart.
 */
export const LLMFrameworkDisplayNames: Record<LLMFramework, string> = {
  [LLMFramework.CoreML]: 'Core ML',
  [LLMFramework.TensorFlowLite]: 'TensorFlow Lite',
  [LLMFramework.MLX]: 'MLX',
  [LLMFramework.SwiftTransformers]: 'Swift Transformers',
  [LLMFramework.ONNX]: 'ONNX Runtime',
  [LLMFramework.Sherpa]: 'Sherpa-ONNX',
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
 * Human-readable display names for model categories. RN-local helper;
 * proto exposes labels via numeric → string conversion only. Keyed by
 * the proto enum values via `ModelCategory[i]` after the re-export.
 */
import type { ModelCategory as ModelCategoryProto } from '@runanywhere/proto-ts/model_types';
export const ModelCategoryDisplayNames: Partial<Record<ModelCategoryProto, string>> = {};

/**
 * @deprecated Legacy RN display labels. Public hardware data is generated
 * `HardwareProfileResult` / `AcceleratorPreference` from
 * `@runanywhere/proto-ts/hardware_profile`.
 */
export enum HardwareAcceleration {
  CPU = 'cpu',
  GPU = 'gpu',
  NeuralEngine = 'neuralEngine',
  NPU = 'npu',
}

/**
 * Privacy mode for data handling. RN-local — describes how the SDK
 * routes telemetry, not part of the proto API surface.
 */
export enum PrivacyMode {
  Public = 'public',
  Private = 'private',
  Restricted = 'restricted',
}

/**
 * @deprecated Legacy JS EventBus topics. Public event streams should use the
 * generated `SDKEvent` envelope from `@runanywhere/proto-ts/sdk_events`.
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
