/**
 * Shared types for the VLM Web Worker protocol.
 *
 * Both the main-thread bridge (`VLMWorkerBridge`) and the worker-side
 * runtime (`VLMWorkerRuntime`) must stay in lockstep across postMessage
 * boundaries. Centralising the shape here removes the duplicated declaration
 * and turns any drift into a compile-time error.
 */

/**
 * Parameters required to load a VLM model in the worker.
 *
 * Either `modelPath` (when a previous bridge already wrote the model into
 * MEMFS) or raw `modelData` (transferred zero-copy via postMessage).
 */
export interface VLMLoadModelParams {
  /** Filename written into the worker's MEMFS, e.g. `'llava-7b.gguf'`. */
  modelFilename: string;
  /** Filename for the mmproj sidecar, e.g. `'mmproj-llava-7b.gguf'`. */
  mmprojFilename: string;
  /** Stable identifier (used for model-family detection — Qwen2-VL etc.). */
  modelId: string;
  /** Human-readable name (also checked for Qwen2-VL detection). */
  modelName: string;
  /** Raw model GGUF bytes — transferred zero-copy via postMessage. */
  modelData: ArrayBuffer;
  /** Raw mmproj GGUF bytes — transferred zero-copy via postMessage. */
  mmprojData: ArrayBuffer;
}
