/**
 * @runanywhere/qhexrt - QHexRT (Qualcomm Hexagon NPU) Backend for RunAnywhere RN
 *
 * This package registers the QHexRT native provider and exposes its pre-flight
 * capability and device-aware catalog facade. Public model lifecycle,
 * generation, VLM, STT, and TTS APIs live in @runanywhere/core.
 *
 * QHexRT is Qualcomm-only (Snapdragon Hexagon NPU): Android arm64 exclusively.
 *
 * ## Usage
 *
 * ```typescript
 * import { RunAnywhere } from '@runanywhere/core';
 * import { InferenceFramework, RegisterModelFromUrlRequest } from '@runanywhere/proto-ts/model_types';
 * import { QHexRT } from '@runanywhere/qhexrt';
 *
 * await RunAnywhere.initialize({ apiKey: 'your-key' });
 *
 * // Warn unsupported devices up front (no QNN load).
 * const npu = await QHexRT.probeNpu();
 * if (!npu.qhexrtSupported) {
 *   console.warn(`Hexagon ${npu.archName} is outside V75/V79/V81`);
 * }
 *
 * // Register the QHexRT backend (covers LLM, VLM, STT, TTS).
 * await QHexRT.register();
 *
 * // URLs and display metadata stay app-owned; QHexRT selects the chip folder.
 * await QHexRT.registerModelForDevice(
 *   RegisterModelFromUrlRequest.fromPartial({
 *     id: 'qwen3_5_0_8b',
 *     name: 'Qwen3.5 0.8B (HNPU)',
 *     url: 'https://huggingface.co/runanywhere/qwen3_5_0_8b_HNPU/qwen3.5-0.8b-1024.json',
 *     framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
 *   })
 * );
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
export { seedNpuCatalog } from './NpuCatalog';

// =============================================================================
// Nitrogen Spec Types
// =============================================================================

export type { RunAnywhereQHexRT } from './specs/RunAnywhereQHexRT.nitro';
