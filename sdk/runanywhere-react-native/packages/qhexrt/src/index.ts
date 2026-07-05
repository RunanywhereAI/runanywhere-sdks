/**
 * @runanywhere/qhexrt - QHexRT (Qualcomm Hexagon NPU) Backend for RunAnywhere RN
 *
 * This package registers the QHexRT native provider and exposes a pre-flight
 * NPU capability probe. Public model lifecycle, generation, VLM, STT, and TTS
 * APIs live in @runanywhere/core.
 *
 * QHexRT is Qualcomm-only (Snapdragon Hexagon NPU): Android arm64 exclusively.
 *
 * ## Usage
 *
 * ```typescript
 * import { RunAnywhere } from '@runanywhere/core';
 * import { InferenceFramework, ModelCategory, ModelLoadRequest } from '@runanywhere/proto-ts/model_types';
 * import { QHexRT } from '@runanywhere/qhexrt';
 *
 * await RunAnywhere.initialize({ apiKey: 'your-key' });
 *
 * // Warn unsupported devices up front (no QNN load).
 * const npu = await QHexRT.probeNpu();
 * if (!npu.qhexrtSupported) {
 *   console.warn(`Hexagon ${npu.archName} not supported (needs v75+)`);
 * }
 *
 * // Register the QHexRT backend (covers LLM, VLM, STT, TTS).
 * await QHexRT.register();
 *
 * // Register models via RunAnywhere (matching the LlamaCPP pattern).
 * await RunAnywhere.registerModel({
 *   id: 'my-npu-llm',
 *   name: 'My NPU LLM',
 *   url: 'https://huggingface.co/.../bundle.zip',
 *   framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
 *   memoryRequirement: 2_000_000_000
 * });
 * ```
 *
 * @packageDocumentation
 */

// =============================================================================
// Main API
// =============================================================================

// NpuCapability / HexagonArch are the generated proto wire types
// (@runanywhere/proto-ts/hardware_profile) — re-exported for consumers.
export { QHexRT, NpuCapability, HexagonArch } from './QHexRT';

// =============================================================================
// Nitrogen Spec Types
// =============================================================================

export type { RunAnywhereQHexRT } from './specs/RunAnywhereQHexRT.nitro';
