/**
 * @runanywhere/qhexrt - QHexRT (Qualcomm Hexagon NPU) Backend for RunAnywhere RN
 *
 * This package registers the QHexRT native provider and exposes its pre-flight
 * capability probe. Public model registration, lifecycle, generation, VLM,
 * STT, and TTS APIs live in @runanywhere/core.
 *
 * QHexRT is Qualcomm-only (Snapdragon Hexagon NPU): Android arm64 exclusively.
 *
 * ## Usage
 *
 * ```typescript
 * import { RunAnywhere } from '@runanywhere/core';
 * import { InferenceFramework } from '@runanywhere/proto-ts/model_types';
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
 * // Register the exact dedicated model URL through the core SDK.
 * await RunAnywhere.registerModel({
 *   id: 'my-qhexrt-model',
 *   name: 'My QHexRT Model',
 *   url: 'https://huggingface.co/organization/dedicated-qhexrt-model/resolve/main/model.json',
 *   framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
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
