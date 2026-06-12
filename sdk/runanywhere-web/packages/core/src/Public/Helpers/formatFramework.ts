/**
 * formatFramework.ts
 *
 * Display name for an `InferenceFramework`, routed through the canonical
 * `rac_framework_display_name` C ABI table in runanywhere-commons via the
 * `_rac_framework_display_name_proto` WASM wrapper (wasm_exports.cpp) —
 * the same table Swift's `RAInferenceFramework.displayName`
 * (ModelTypes.swift:186) reads. No TS mirror of the string table exists, so
 * commons is the single source of truth.
 *
 * Returns `"Unknown"` for unspecified/unrecognized values (matching the C
 * default branch) and when no WASM module has registered yet.
 */
import { InferenceFramework } from '@runanywhere/proto-ts/model_types';
import {
  getModuleForCapability,
  type EmscriptenRunanywhereModule,
} from '../../runtime/EmscriptenModule';

interface FrameworkDisplayNameModule extends EmscriptenRunanywhereModule {
  /** Proto-int wrapper over rac_framework_display_name (wasm_exports.cpp). */
  _rac_framework_display_name_proto?(protoFramework: number): number;
}

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
  const module = getModuleForCapability('commons') as FrameworkDisplayNameModule | null;
  if (
    !module ||
    typeof module._rac_framework_display_name_proto !== 'function' ||
    typeof module.UTF8ToString !== 'function'
  ) {
    return 'Unknown';
  }
  const ptr = module._rac_framework_display_name_proto(framework);
  if (!ptr) return 'Unknown';
  return module.UTF8ToString(ptr) || 'Unknown';
}
