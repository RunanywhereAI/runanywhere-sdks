/**
 * formatFramework.ts
 *
 * Pure-JS proxy for the canonical `rac_framework_display_name` C ABI
 * mapping in runanywhere-commons (`model_types.cpp:261`).
 *
 * The C string table is not exposed through the proto bridge — it
 * would cost a JS<->native bridge call for a static label. Mirror the
 * exact same table in TypeScript so consumers (UI banners, status
 * labels) can resolve a human-readable display name synchronously.
 *
 * The mapping is the source-of-truth pair with Swift's
 * `RAInferenceFramework.displayName` (ModelTypes.swift:186) and
 * React Native's `formatFramework` (Helpers/formatFramework.ts) —
 * keep in lock-step when commons adds a new framework.
 */
import { InferenceFramework } from '@runanywhere/proto-ts/model_types';

const FRAMEWORK_DISPLAY_TABLE: Partial<Record<InferenceFramework, string>> = {
  [InferenceFramework.INFERENCE_FRAMEWORK_ONNX]: 'ONNX Runtime',
  [InferenceFramework.INFERENCE_FRAMEWORK_SHERPA]: 'Sherpa-ONNX',
  [InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP]: 'llama.cpp',
  [InferenceFramework.INFERENCE_FRAMEWORK_COREML]: 'Core ML',
  [InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS]:
    'Foundation Models',
  [InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS]: 'System TTS',
  [InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO]: 'FluidAudio',
  [InferenceFramework.INFERENCE_FRAMEWORK_MLX]: 'MLX',
  [InferenceFramework.INFERENCE_FRAMEWORK_GENIE]: 'Qualcomm Genie',
  [InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN]: 'Built-in',
  [InferenceFramework.INFERENCE_FRAMEWORK_NONE]: 'None',
};

/**
 * Return the canonical human-readable display name for an
 * `InferenceFramework`. Mirrors `rac_framework_display_name` from
 * commons (model_types.cpp:261) so cross-platform UIs render the same
 * label without each example app maintaining its own switch table.
 *
 * Unknown / unspecified values resolve to `"Unknown"` to match the C
 * default branch.
 */
export function formatFramework(
  framework?: InferenceFramework | null
): string {
  if (
    framework == null ||
    framework === InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED ||
    framework === InferenceFramework.UNRECOGNIZED
  ) {
    return 'Unknown';
  }
  return FRAMEWORK_DISPLAY_TABLE[framework] ?? 'Unknown';
}
