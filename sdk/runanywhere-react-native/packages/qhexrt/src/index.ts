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
 * import { QHexRT, HexagonArch } from '@runanywhere/qhexrt';
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
 *     id: 'my-npu-llm',
 *     name: 'My NPU LLM',
 *     url: 'https://huggingface.co/your-org/your-model_HNPU/model.json',
 *     framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
 *   }),
 *   [HexagonArch.HEXAGON_ARCH_V79, HexagonArch.HEXAGON_ARCH_V81]
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

// =============================================================================
// Nitrogen Spec Types
// =============================================================================

export type { RunAnywhereQHexRT } from './specs/RunAnywhereQHexRT.nitro';
