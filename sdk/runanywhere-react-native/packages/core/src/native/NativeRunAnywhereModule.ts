/**
 * NativeRunAnywhereModule.ts
 *
 * Full native module type that includes all methods from core.
 * All methods call backend-agnostic C++ APIs (rac_*_component_*).
 *
 * LLM, STT, TTS, VAD methods are backend-agnostic:
 * - They call the C++ rac_*_component_* APIs
 * - The actual backend is registered by importing backend packages:
 *   - @runanywhere/llamacpp registers the LLM backend
 *   - @runanywhere/onnx registers the STT/TTS/VAD backends
 */

import type { RunAnywhereCore } from '../specs/RunAnywhereCore.nitro';

/**
 * Native module type - directly matches RunAnywhereCore spec
 *
 * All methods are backend-agnostic. If no backend is registered for a
 * capability, the methods will throw appropriate errors.
 */
export type NativeRunAnywhereModule = RunAnywhereCore;

/**
 * Type guard to check if a method is available on the native module
 */
export function hasNativeMethod<K extends keyof NativeRunAnywhereModule>(
  native: NativeRunAnywhereModule,
  method: K
): boolean {
  return typeof native[method] === 'function';
}
