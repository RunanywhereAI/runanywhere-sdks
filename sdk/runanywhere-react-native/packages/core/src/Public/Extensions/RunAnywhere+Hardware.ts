/**
 * RunAnywhere+Hardware.ts
 *
 * Canonical `RunAnywhere.hardware.*` namespace per CANONICAL_API.md §14.
 *
 * Surface (matches Swift / Kotlin / Flutter / Web SDKs):
 *   - `hardware.getProfile() -> HardwareProfileResult`
 *   - `hardware.getChip() -> string`
 *   - `hardware.hasNeuralEngine: boolean`
 *   - `hardware.accelerationMode: string`
 *
 * Wave 3 Step 3.2: this RN extension was missing entirely. The four entry
 * points below mirror the existing platform extensions and will route through
 * the `rac_hardware_profile_get` C ABI once the RN Nitro HybridObject method
 * for hardware profile lands. Until then, values are derived from
 * `Platform.OS` / `Platform.constants` and the existing `getChip()` device
 * probe (see RunAnywhere+Device.ts).
 */

import { Platform } from 'react-native';
import { getChip as getNpuChip } from './RunAnywhere+Device';

/**
 * Aggregated hardware profile for the current device.
 *
 * Wire shape mirrors the proto type `HardwareProfileResult` from
 * `idl/hardware_profile.proto`. Once the RN Nitro thunk exists, this type
 * will be replaced with the proto-generated equivalent without changing
 * the public surface.
 */
export interface HardwareProfileResult {
  chip: string;
  hasNeuralEngine: boolean;
  accelerationMode: string;
  platform: string;
}

function detectAccelerationMode(hasNpu: boolean): string {
  if (Platform.OS === 'ios' || Platform.OS === 'macos') {
    return 'Neural Engine';
  }
  if (hasNpu) return 'NPU';
  return 'CPU';
}

function genericChipLabel(): string {
  switch (Platform.OS) {
    case 'ios':
      return 'Apple Silicon';
    case 'macos':
      return 'Apple Silicon';
    case 'android':
      return 'Android';
    case 'windows':
      return 'Windows';
    default:
      return 'Unknown';
  }
}

/**
 * Snapshot the current hardware profile.
 *
 * Calls `rac_hardware_profile_get` via the Nitro HybridObject when available;
 * falls back to platform inspection. The proto-backed path is gated on the
 * `RNHardwareProfile` Nitro module which is not yet generated (CPP gate).
 */
export async function getProfile(): Promise<HardwareProfileResult> {
  const npuChip = await getNpuChip();
  const hasNeuralEngine =
    Platform.OS === 'ios' || Platform.OS === 'macos' || npuChip !== null;
  const chip = npuChip?.displayName ?? genericChipLabel();
  return {
    chip,
    hasNeuralEngine,
    accelerationMode: detectAccelerationMode(npuChip !== null),
    platform: Platform.OS,
  };
}

/**
 * Get the chip / SoC name for the current device.
 *
 * Returns the NPU chip's display name when detected, otherwise a generic
 * platform label (e.g. "Apple Silicon", "Android").
 */
export async function getChip(): Promise<string> {
  const npuChip = await getNpuChip();
  return npuChip?.displayName ?? genericChipLabel();
}

/**
 * Whether the current device has a dedicated neural engine / NPU.
 *
 * iOS / macOS always reports true (Apple Neural Engine assumption). Android
 * reports true when a supported Qualcomm SoC is detected.
 */
export async function hasNeuralEngine(): Promise<boolean> {
  if (Platform.OS === 'ios' || Platform.OS === 'macos') return true;
  return (await getNpuChip()) !== null;
}

/**
 * Recommended acceleration mode string for on-device AI inference.
 *
 * Possible values: `"Neural Engine"`, `"NPU"`, `"GPU"`, `"CPU"`.
 */
export async function accelerationMode(): Promise<string> {
  const npuChip = await getNpuChip();
  return detectAccelerationMode(npuChip !== null);
}

/**
 * Namespace object exposing the canonical 4-method hardware surface, so callers
 * can write `RunAnywhere.hardware.getProfile()` matching the spec.
 */
export const Hardware = {
  getProfile,
  getChip,
  hasNeuralEngine,
  accelerationMode,
};
