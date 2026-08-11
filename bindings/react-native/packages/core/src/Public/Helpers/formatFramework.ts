/**
 * formatFramework.ts
 *
 * Delegates to the canonical `rac_inference_framework_display_name` C ABI
 * mapping in runanywhere-commons — the same table Swift's
 * `RAInferenceFramework.displayName` (ModelTypes.swift:187) delegates to.
 * The Nitro method is synchronous (pure table lookup), so consumers (UI
 * banners, status labels) keep resolving labels synchronously; results are
 * memoized to avoid repeated JSI hops from render paths.
 */
import { InferenceFramework } from '@runanywhere/proto-ts/model_types';
import {
  isNativeModuleAvailable,
  requireNativeModule,
} from '../../native/NativeRunAnywhereCore';

const displayNameCache = new Map<InferenceFramework, string>();

/**
 * Return the canonical human-readable display name for an
 * `InferenceFramework`, resolved from the commons C ABI so cross-platform
 * UIs render the same label.
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
  const cached = displayNameCache.get(framework);
  if (cached !== undefined) {
    return cached;
  }
  if (!isNativeModuleAvailable()) {
    return 'Unknown';
  }
  const name = requireNativeModule().frameworkDisplayName(framework);
  displayNameCache.set(framework, name);
  return name;
}
