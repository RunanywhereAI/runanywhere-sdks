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
 * Values come from the `rac_hardware_profile_get` C ABI exposed through the
 * core Nitro object. A native platform fallback exists only for stale binaries
 * that do not expose the ABI yet.
 */

import { Platform } from 'react-native';
import {
  AcceleratorPreference,
  HardwareProfileResult as HardwareProfileResultCodec,
  type HardwareProfileResult,
} from '@runanywhere/proto-ts/hardware_profile';
import {
  isNativeModuleAvailable,
  requireDeviceInfoModule,
  requireNativeModule,
} from '../../native';
import { arrayBufferToBytes } from '../../services/ProtoBytes';
import { getChip as getNpuChip } from './RunAnywhere+Device';

export type { HardwareProfileResult } from '@runanywhere/proto-ts/hardware_profile';

function detectAccelerationMode(hasNpu: boolean): string {
  if (Platform.OS === 'ios' || Platform.OS === 'macos') {
    return 'ane';
  }
  if (hasNpu) return 'gpu';
  return 'cpu';
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

async function buildPlatformFallbackProfile(): Promise<HardwareProfileResult> {
  const npuChip = await getNpuChip();
  const hasNpuFromChip = npuChip !== null;
  let chip = npuChip?.displayName ?? genericChipLabel();
  let totalMemoryBytes = 0;
  let coreCount = 0;
  let hasNpu = hasNpuFromChip;

  try {
    const deviceInfo = requireDeviceInfoModule();
    const [chipName, memory, cores, nativeHasNpu] = await Promise.all([
      deviceInfo.getChipName(),
      deviceInfo.getTotalRAM(),
      deviceInfo.getCPUCores(),
      deviceInfo.hasNPU(),
    ]);
    if (!npuChip && chipName && chipName !== 'Unknown') {
      chip = chipName;
    }
    totalMemoryBytes = Number.isFinite(memory) ? memory : 0;
    coreCount = Number.isFinite(cores) ? cores : 0;
    hasNpu = hasNpu || nativeHasNpu;
  } catch {
    // Keep the generic fallback shape when the device info HybridObject is not available.
  }

  const acceleration = detectAccelerationMode(hasNpu);
  return {
    profile: {
      chip,
      hasNeuralEngine: hasNpu || Platform.OS === 'ios' || Platform.OS === 'macos',
      accelerationMode: acceleration,
      totalMemoryBytes,
      coreCount,
      performanceCores: 0,
      efficiencyCores: 0,
      architecture: '',
      platform: Platform.OS,
    },
    accelerators: [
      {
        name: acceleration,
        type:
          acceleration === 'ane'
            ? AcceleratorPreference.ACCELERATOR_PREFERENCE_ANE
            : acceleration === 'gpu'
              ? AcceleratorPreference.ACCELERATOR_PREFERENCE_GPU
              : AcceleratorPreference.ACCELERATOR_PREFERENCE_CPU,
        available: true,
      },
    ],
  };
}

/**
 * Snapshot the current hardware profile.
 *
 * Calls `rac_hardware_profile_get` via the core Nitro HybridObject when
 * available; falls back to native platform inspection only for stale binaries.
 */
export async function getProfile(): Promise<HardwareProfileResult> {
  try {
    if (isNativeModuleAvailable()) {
      const native = requireNativeModule();
      if (typeof native.hardwareProfileProto === 'function') {
        const buffer = await native.hardwareProfileProto();
        if (buffer.byteLength > 0) {
          return HardwareProfileResultCodec.decode(arrayBufferToBytes(buffer));
        }
      }
    }
  } catch {
    // Stale native binary or ABI unavailable; use platform fallback below.
  }

  return buildPlatformFallbackProfile();
}

/**
 * Get the chip / SoC name for the current device.
 *
 * Returns the chip name reported by the native hardware profile, otherwise a
 * generic platform label (e.g. "Apple Silicon", "Android").
 */
export async function getChip(): Promise<string> {
  return (await getProfile()).profile?.chip || genericChipLabel();
}

/**
 * Whether the current device has a dedicated neural engine / NPU.
 *
 * Delegates to the native hardware profile when available.
 */
export async function hasNeuralEngine(): Promise<boolean> {
  return (await getProfile()).profile?.hasNeuralEngine ?? false;
}

/**
 * Recommended acceleration mode string for on-device AI inference.
 *
 * Possible values: `"Neural Engine"`, `"NPU"`, `"GPU"`, `"CPU"`.
 */
export async function accelerationMode(): Promise<string> {
  return (await getProfile()).profile?.accelerationMode || 'cpu';
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
