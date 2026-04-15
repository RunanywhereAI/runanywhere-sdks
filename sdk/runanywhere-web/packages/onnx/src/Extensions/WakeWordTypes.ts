/**
 * WakeWordTypes
 * -----------------------------------------------------------------------------
 * Configuration types for wake-word detection.
 *
 * Mirrors the native C struct layout in
 * `sdk/runanywhere-commons/include/rac/backends/rac_wakeword_onnx.h` so the
 * same .onnx model files work on web and native without model-side changes.
 *
 * The implementation (`RunAnywhere+WakeWord.ts`) runs the openWakeWord 3-stage
 * pipeline using `onnxruntime-web` via ORTRuntimeBridge.
 */

export interface WakeWordSharedModelConfig {
  /** Path / URL / ArrayBuffer for melspectrogram.onnx (Stage 1). */
  melspectrogramModel: string | ArrayBuffer | Uint8Array;
  /** Path / URL / ArrayBuffer for embedding_model.onnx (Stage 2). */
  embeddingModel: string | ArrayBuffer | Uint8Array;
}

export interface WakeWordClassifierConfig {
  /** Unique identifier for this wake word (e.g. `"hey_jarvis"`). */
  modelId: string;
  /** Display name for the phrase (e.g. `"Hey Jarvis"`). */
  wakeWord: string;
  /** Path / URL / ArrayBuffer for the classifier .onnx. */
  classifierModel: string | ArrayBuffer | Uint8Array;
  /**
   * Score in [0, 1] above which we emit a detection event. Default: 0.5.
   * Per-classifier threshold overrides `WakeWordConfig.globalThreshold`.
   */
  threshold?: number;
}

export interface WakeWordConfig {
  /** Shared Stage 1 + Stage 2 models (melspec + embeddings). */
  shared: WakeWordSharedModelConfig;
  /** One entry per wake word to detect concurrently. */
  classifiers: WakeWordClassifierConfig[];
  /** Fallback threshold if a classifier doesn't specify one. Default: 0.5. */
  globalThreshold?: number;
  /**
   * If > 1, require `cooldownFrames` frames between successive detections
   * of the same wake word. Default: 0 (emit every frame above threshold).
   */
  cooldownFrames?: number;
}

export interface WakeWordDetection {
  /** Classifier modelId that fired. */
  modelId: string;
  /** Display phrase. */
  wakeWord: string;
  /** Confidence score in [0, 1]. */
  score: number;
  /** Frame index (80 ms / 1280 sample @16 kHz) at which detection was emitted. */
  frameIndex: number;
}

export type WakeWordCallback = (detection: WakeWordDetection) => void;
