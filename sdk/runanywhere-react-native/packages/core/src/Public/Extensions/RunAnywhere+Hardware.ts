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
 *   - `hardware.getAccelerators() -> AcceleratorInfo[]` (Swift parity)
 *   - `hardware.setAccelerationPreference(p) -> Promise<boolean>` (Swift parity)
 *
 * Values come from the `rac_hardware_profile_get` C ABI exposed through the
 * core Nitro object. A native platform fallback exists only for stale binaries
 * that do not expose the ABI yet.
 */

import { Platform } from 'react-native';
import {
  type AcceleratorInfo,
  AccelerationPreference,
  HardwareProfileResult as HardwareProfileResultCodec,
  type HardwareProfileResult,
} from '@runanywhere/proto-ts/hardware_profile';
import {
  isNativeModuleAvailable,
  requireDeviceInfoModule,
  requireNativeModule,
} from '../../native';
import { arrayBufferToBytes } from '../../services/ProtoBytes';

export type {
  AcceleratorInfo,
  HardwareProfileResult,
} from '@runanywhere/proto-ts/hardware_profile';
export { AccelerationPreference } from '@runanywhere/proto-ts/hardware_profile';

// In-memory cache for the preferred accelerator. The Nitro spec does not
// surface `rac_hardware_set_accelerator_preference` yet, so the SDK persists
// the preference here and exposes it through `getAccelerationPreference()`.
// Mirrors Swift's `setAccelerationPreference(_:)` Public surface.
let _acceleratorPreference: AccelerationPreference =
  AccelerationPreference.ACCELERATION_PREFERENCE_AUTO;

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
  let chip = genericChipLabel();
  let totalMemoryBytes = 0;
  let coreCount = 0;
  let hasNpu = false;

  try {
    const deviceInfo = requireDeviceInfoModule();
    const [chipName, memory, cores, nativeHasNpu] = await Promise.all([
      deviceInfo.getChipName(),
      deviceInfo.getTotalRAM(),
      deviceInfo.getCPUCores(),
      deviceInfo.hasNPU(),
    ]);
    if (chipName && chipName !== 'Unknown') {
      chip = chipName;
    }
    totalMemoryBytes = Number.isFinite(memory) ? memory : 0;
    coreCount = Number.isFinite(cores) ? cores : 0;
    hasNpu = nativeHasNpu;
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
            ? AccelerationPreference.ACCELERATION_PREFERENCE_NPU
            : acceleration === 'gpu'
              ? AccelerationPreference.ACCELERATION_PREFERENCE_GPU
              : AccelerationPreference.ACCELERATION_PREFERENCE_CPU,
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
 * Return the list of available hardware accelerators.
 *
 * Mirrors Swift's `RunAnywhere.hardware.getAccelerators()`. Backed by the
 * `accelerators` field of the `HardwareProfileResult` returned by
 * `rac_hardware_profile_get` (the same proto bytes also expose
 * `rac_hardware_get_accelerators` server-side).
 */
export async function getAccelerators(): Promise<AcceleratorInfo[]> {
  const result = await getProfile();
  return result.accelerators ?? [];
}

/**
 * Set the preferred accelerator for subsequent inference routing.
 *
 * Mirrors Swift's `RunAnywhere.hardware.setAccelerationPreference(_:)`.
 *
 * The Nitro spec does not yet surface `rac_hardware_set_accelerator_preference`
 * directly; this implementation persists the preference in-memory and exposes
 * it via `getAccelerationPreference()`. When the Nitro bridge is updated to
 * include the C ABI call this function will forward through to the native
 * implementation without breaking callers.
 */
export async function setAccelerationPreference(
  preference: AccelerationPreference
): Promise<boolean> {
  if (
    preference !== AccelerationPreference.ACCELERATION_PREFERENCE_AUTO &&
    preference !== AccelerationPreference.ACCELERATION_PREFERENCE_NPU &&
    preference !== AccelerationPreference.ACCELERATION_PREFERENCE_GPU &&
    preference !== AccelerationPreference.ACCELERATION_PREFERENCE_CPU
  ) {
    return false;
  }

  _acceleratorPreference = preference;

  // Best-effort forward to the native side if a future Nitro spec update
  // exposes a `setAccelerationPreferenceProto`-style entry point.
  try {
    if (isNativeModuleAvailable()) {
      const native = requireNativeModule() as unknown as {
        setAccelerationPreference?: (p: number) => Promise<boolean>;
      };
      if (typeof native.setAccelerationPreference === 'function') {
        return await native.setAccelerationPreference(preference);
      }
    }
  } catch {
    // Native call not available; the in-memory cache above is sufficient.
  }

  return true;
}

/**
 * Read back the most recently set accelerator preference.
 *
 * Returns `ACCELERATION_PREFERENCE_AUTO` if no preference has been set in this
 * SDK session.
 */
export function getAccelerationPreference(): AccelerationPreference {
  return _acceleratorPreference;
}

/**
 * Namespace object exposing the canonical hardware surface, so callers
 * can write `RunAnywhere.hardware.getProfile()` matching the spec.
 */
export const Hardware = {
  getProfile,
  getChip,
  hasNeuralEngine,
  accelerationMode,
  getAccelerators,
  setAccelerationPreference,
  getAccelerationPreference,
};
