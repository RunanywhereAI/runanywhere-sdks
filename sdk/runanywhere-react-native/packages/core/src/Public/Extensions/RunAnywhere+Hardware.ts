/**
 * RunAnywhere+Hardware.ts
 *
 * Canonical `RunAnywhere.hardware.*` namespace per CANONICAL_API.md §14.
 *
 * Surface (matches Swift / Kotlin / Flutter / Web SDKs):
 *   - `hardware.getProfile() -> HardwareProfileResult`
 *   - `hardware.getChip() -> string`
 *   - `hardware.getNPUChip() -> NPUChip` (Swift parity — structured vendor enum)
 *   - `hardware.hasNeuralEngine: boolean`
 *   - `hardware.accelerationMode: string`
 *   - `hardware.getAccelerators() -> AcceleratorInfo[]`
 *   - `hardware.setAcceleratorPreference(p) -> Promise<boolean>` (Swift parity)
 *
 * Values come from the `rac_hardware_*` C ABI exposed through the core Nitro
 * HybridObject. A native platform fallback exists only for stale binaries that
 * do not expose the ABI yet.
 */

import { Platform } from 'react-native';
import {
  type AcceleratorInfo,
  AccelerationPreference,
  HardwareAcceleratorPreferenceRequest,
  HardwareAcceleratorPreferenceResult,
  HardwareProfileResult as HardwareProfileResultCodec,
  type HardwareProfileResult,
} from '@runanywhere/proto-ts/hardware_profile';
import { NPUChip } from '@runanywhere/proto-ts/storage_types';
import {
  isNativeModuleAvailable,
  requireDeviceInfoModule,
  requireNativeModule,
} from '../../native';
import { arrayBufferToBytes, bytesToArrayBuffer } from '../../services/ProtoBytes';

export type {
  AcceleratorInfo,
  HardwareProfileResult,
} from '@runanywhere/proto-ts/hardware_profile';
export { AccelerationPreference } from '@runanywhere/proto-ts/hardware_profile';
export { NPUChip } from '@runanywhere/proto-ts/storage_types';

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
 * Map a free-form chip / SoC name to the structured `NPUChip` vendor enum.
 *
 * Used by `getNPUChip()` to resolve the NPU family for Genie backend URL
 * selection and runtime backend wiring. Matches the vendor grouping declared
 * in `idl/storage_types.proto` `NPUChip`:
 *
 *   - Apple A-series / M-series / Apple Silicon -> APPLE_NEURAL_ENGINE
 *   - Qualcomm Snapdragon / Hexagon / SDM / SM8/SM7/SM6 / MSM -> QUALCOMM_HEXAGON
 *   - MediaTek Dimensity / Helio / MT6/MT8 -> MEDIATEK_APU
 *   - Google Tensor / Pixel TPU / GS10x/GS20x/GS30x -> GOOGLE_TPU
 *   - Intel Core Ultra (Meteor Lake / Lunar Lake / Arrow Lake) -> INTEL_NPU
 *   - Samsung Exynos / HiSilicon Kirin -> OTHER (detected NPU, vendor unmapped)
 *
 * Exported for unit tests / host code; the public entry point is `getNPUChip()`.
 */
export function mapChipStringToNPUChip(chip: string): NPUChip {
  const lower = chip.trim().toLowerCase();
  if (lower.length === 0) {
    return NPUChip.NPU_CHIP_UNSPECIFIED;
  }

  // Apple Neural Engine — A-series, M-series, generic "Apple Silicon" label.
  if (
    lower.includes('apple') ||
    /\ba(?:[1-9]|1[0-9])\b/.test(lower) ||
    /\bm[1-9]\b/.test(lower)
  ) {
    return NPUChip.NPU_CHIP_APPLE_NEURAL_ENGINE;
  }

  // Qualcomm Hexagon — Snapdragon, SDM, SM8/SM7/SM6, MSM.
  if (
    lower.includes('snapdragon') ||
    lower.includes('qualcomm') ||
    lower.includes('hexagon') ||
    lower.startsWith('sdm') ||
    lower.startsWith('sm8') ||
    lower.startsWith('sm7') ||
    lower.startsWith('sm6') ||
    lower.startsWith('msm')
  ) {
    return NPUChip.NPU_CHIP_QUALCOMM_HEXAGON;
  }

  // MediaTek APU — Dimensity, Helio, MT6xxx, MT8xxx.
  if (
    lower.includes('mediatek') ||
    lower.includes('dimensity') ||
    lower.includes('helio') ||
    lower.startsWith('mt6') ||
    lower.startsWith('mt8')
  ) {
    return NPUChip.NPU_CHIP_MEDIATEK_APU;
  }

  // Google Tensor — Pixel SoC labels plus GS1xx/GS2xx/GS3xx codes.
  if (
    lower.includes('tensor') ||
    lower.includes('pixel') ||
    lower.startsWith('gs1') ||
    lower.startsWith('gs2') ||
    lower.startsWith('gs3')
  ) {
    return NPUChip.NPU_CHIP_GOOGLE_TPU;
  }

  // Intel Core Ultra NPU — Meteor Lake / Lunar Lake / Arrow Lake families.
  if (
    lower.includes('intel') ||
    lower.includes('core ultra') ||
    lower.includes('meteor lake') ||
    lower.includes('lunar lake') ||
    lower.includes('arrow lake')
  ) {
    return NPUChip.NPU_CHIP_INTEL_NPU;
  }

  // Known-non-NPU vendors: detected SoC but no dedicated NPU mapping yet.
  if (
    lower.includes('exynos') ||
    lower.startsWith('s5e') ||
    lower.includes('samsung') ||
    lower.includes('kirin') ||
    lower.includes('hisilicon')
  ) {
    return NPUChip.NPU_CHIP_OTHER;
  }

  return NPUChip.NPU_CHIP_UNSPECIFIED;
}

/**
 * Resolve the NPU chipset enum for the current device.
 *
 * Mirrors Swift's `NPUChipDetector` behaviour by consuming the chip string
 * reported by the native hardware profile (`rac_hardware_profile_get`). If the
 * native profile reports `hasNeuralEngine == false`, this falls through to the
 * string matcher and may still classify a known vendor (e.g. older Apple
 * devices with no separate ANE silicon but the "Apple" label is still useful
 * for Genie download URL selection).
 *
 * Returns `NPUChip.NPU_CHIP_UNSPECIFIED` for unknown or empty chip strings,
 * and `NPUChip.NPU_CHIP_NONE` when the native profile explicitly reports no
 * neural engine / NPU.
 */
export async function getNPUChip(): Promise<NPUChip> {
  const result = await getProfile();
  const chip = result.profile?.chip ?? '';
  const mapped = mapChipStringToNPUChip(chip);

  if (mapped !== NPUChip.NPU_CHIP_UNSPECIFIED) {
    return mapped;
  }

  // Chip string unrecognised but the platform reports a neural engine / NPU;
  // fall back to OTHER so callers still know an NPU exists.
  if (result.profile?.hasNeuralEngine === true) {
    return NPUChip.NPU_CHIP_OTHER;
  }

  // Explicit "no NPU" signal vs. truly unknown state.
  if (result.profile && result.profile.hasNeuralEngine === false) {
    return NPUChip.NPU_CHIP_NONE;
  }

  return NPUChip.NPU_CHIP_UNSPECIFIED;
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
 * Mirrors Swift's `RunAnywhere.hardware.setAcceleratorPreference(_:)`. Routes
 * through the commons `rac_hardware_set_accelerator_preference` C ABI via the
 * Nitro `setAcceleratorPreferenceProto` method. Returns `true` on success;
 * `false` when the request is rejected (unsupported enum, stale native binary,
 * or commons returned a non-success status).
 */
export async function setAcceleratorPreference(
  preference: AccelerationPreference
): Promise<boolean> {
  if (
    preference !== AccelerationPreference.ACCELERATION_PREFERENCE_AUTO &&
    preference !== AccelerationPreference.ACCELERATION_PREFERENCE_NPU &&
    preference !== AccelerationPreference.ACCELERATION_PREFERENCE_GPU &&
    preference !== AccelerationPreference.ACCELERATION_PREFERENCE_CPU &&
    preference !== AccelerationPreference.ACCELERATION_PREFERENCE_WEBGPU &&
    preference !== AccelerationPreference.ACCELERATION_PREFERENCE_METAL &&
    preference !== AccelerationPreference.ACCELERATION_PREFERENCE_VULKAN
  ) {
    return false;
  }

  if (!isNativeModuleAvailable()) {
    return false;
  }

  const native = requireNativeModule();
  if (typeof native.setAcceleratorPreferenceProto !== 'function') {
    return false;
  }

  try {
    const requestBytes = HardwareAcceleratorPreferenceRequest.encode({
      preference,
    }).finish();
    const responseBuffer = await native.setAcceleratorPreferenceProto(
      bytesToArrayBuffer(requestBytes)
    );
    if (responseBuffer.byteLength === 0) {
      return false;
    }
    const result = HardwareAcceleratorPreferenceResult.decode(
      arrayBufferToBytes(responseBuffer)
    );
    return result.success === true;
  } catch {
    return false;
  }
}

/**
 * Namespace object exposing the canonical hardware surface, so callers
 * can write `RunAnywhere.hardware.getProfile()` matching the spec.
 */
export const Hardware = {
  getProfile,
  getChip,
  getNPUChip,
  hasNeuralEngine,
  accelerationMode,
  getAccelerators,
  setAcceleratorPreference,
};
