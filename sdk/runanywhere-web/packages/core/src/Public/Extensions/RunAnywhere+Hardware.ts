/**
 * RunAnywhere+Hardware.ts
 *
 * Canonical `RunAnywhere.hardware.*` namespace per CANONICAL_API.md §14.
 *
 * Surface:
 *   - `hardware.getProfile() → HardwareProfile`
 *   - `hardware.getChip() → string`
 *   - `hardware.hasNeuralEngine: boolean`
 *   - `hardware.accelerationMode: string`
 *
 * Hardware data is decoded from the commons serialized-proto ABI when the
 * active WASM module exports it. Browser-owned facts (`navigator.*`, WebGPU,
 * and the active Runtime acceleration mode) stay in the Web adapter and are
 * merged into missing proto fields.
 */

import { Runtime, type RuntimeAccelerationMode } from '../../Foundation/RuntimeConfig';
import { HardwareAdapter } from '../../Adapters/HardwareAdapter';
import {
  AccelerationPreference,
  type AcceleratorInfo,
  type HardwareProfileResult,
} from '@runanywhere/proto-ts/hardware_profile';
import { NPUChip } from '@runanywhere/proto-ts/storage_types';

export type {
  AcceleratorInfo,
  HardwareProfile,
  HardwareProfileResult,
} from '@runanywhere/proto-ts/hardware_profile';

type NavigatorWithExtras = Omit<Navigator, 'hardwareConcurrency'> & {
  deviceMemory?: number;
  hardwareConcurrency?: number;
  gpu?: unknown;
};

function getNavigator(): NavigatorWithExtras | null {
  return typeof navigator !== 'undefined'
    ? (navigator as NavigatorWithExtras)
    : null;
}

function detectChip(): string {
  const nav = getNavigator();
  if (!nav) return 'unknown';
  const ua = nav.userAgent ?? '';
  // Apple Silicon detection — `userAgentData.architecture` would be cleaner
  // but support is patchy; fall back to user-agent sniffing.
  if (/Mac/.test(ua)) {
    return 'apple-silicon';
  }
  if (/Android|arm/i.test(ua)) {
    return 'arm';
  }
  if (/x86_64|Win64|Linux x86/i.test(ua)) {
    return 'x86_64';
  }
  return 'unknown';
}

function detectAccelerationMode(): string {
  const mode = Runtime.preferred as RuntimeAccelerationMode;
  if (mode === 'auto') {
    return Runtime.active ?? 'auto';
  }
  return mode;
}

function detectWebGPU(): boolean {
  const nav = getNavigator();
  return nav?.gpu != null;
}

function browserHardwareProfileResult(): HardwareProfileResult {
  const nav = getNavigator();
  const chip = detectChip();
  const accelerationMode = detectAccelerationMode();
  const webgpuAvailable = detectWebGPU();
  return {
    profile: {
      chip,
      hasNeuralEngine: chip === 'apple-silicon',
      accelerationMode,
      totalMemoryBytes: Math.round((nav?.deviceMemory ?? 0) * 1024 * 1024 * 1024),
      coreCount: nav?.hardwareConcurrency ?? 0,
      performanceCores: 0,
      efficiencyCores: 0,
      architecture: chip,
      platform: 'web',
      npuChip: NPUChip.NPU_CHIP_NONE,
    },
    accelerators: [
      {
        name: webgpuAvailable ? 'webgpu' : accelerationMode,
        type: webgpuAvailable
          ? AccelerationPreference.ACCELERATION_PREFERENCE_GPU
          : AccelerationPreference.ACCELERATION_PREFERENCE_CPU,
        available: true,
      },
    ],
  };
}

function mergeBrowserFacts(
  protoResult: HardwareProfileResult,
  browserResult: HardwareProfileResult,
): HardwareProfileResult {
  const protoProfile = protoResult.profile;
  const browserProfile = browserResult.profile;
  const acceleratorsByName = new Map(
    protoResult.accelerators.map((accelerator) => [accelerator.name, accelerator]),
  );
  for (const accelerator of browserResult.accelerators) {
    if (!acceleratorsByName.has(accelerator.name)) {
      acceleratorsByName.set(accelerator.name, accelerator);
    }
  }

  return {
    profile: protoProfile && browserProfile
      ? {
          chip: protoProfile.chip || browserProfile.chip,
          hasNeuralEngine: protoProfile.hasNeuralEngine || browserProfile.hasNeuralEngine,
          accelerationMode: protoProfile.accelerationMode || browserProfile.accelerationMode,
          totalMemoryBytes: protoProfile.totalMemoryBytes || browserProfile.totalMemoryBytes,
          coreCount: protoProfile.coreCount || browserProfile.coreCount,
          performanceCores: protoProfile.performanceCores || browserProfile.performanceCores,
          efficiencyCores: protoProfile.efficiencyCores || browserProfile.efficiencyCores,
          architecture: protoProfile.architecture || browserProfile.architecture,
          platform: protoProfile.platform || browserProfile.platform,
          npuChip: protoProfile.npuChip || browserProfile.npuChip,
        }
      : protoProfile ?? browserProfile,
    accelerators: Array.from(acceleratorsByName.values()),
  };
}

export const Hardware = {
  /** Snapshot the current hardware profile. */
  getProfile(): HardwareProfileResult {
    const browserResult = browserHardwareProfileResult();
    const protoResult = HardwareAdapter.tryDefault()?.getProfile();
    return protoResult ? mergeBrowserFacts(protoResult, browserResult) : browserResult;
  },

  /** Best-effort chip name (e.g., "apple-silicon", "x86_64"). */
  getChip(): string {
    return Hardware.getProfile().profile?.chip || detectChip();
  },

  /**
   * Whether the device has a Neural Engine. The proto bridge is authoritative
   * when present; browser detection fills the gap for older or partial modules.
   */
  get hasNeuralEngine(): boolean {
    return Hardware.getProfile().profile?.hasNeuralEngine ?? detectChip() === 'apple-silicon';
  },

  /**
   * Active acceleration mode. Reflects the value of
   * `RunAnywhere.runtime.preferred` (or the resolved `activeMode` when
   * `preferred === 'auto'`).
   */
  get accelerationMode(): string {
    return Hardware.getProfile().profile?.accelerationMode || detectAccelerationMode();
  },

  /**
   * Returns the available accelerators as a list. Swift parity:
   * `getAccelerators() throws -> [RAAcceleratorInfo]`. When the proto
   * bridge is unavailable the browser-detected accelerator list is
   * returned (single GPU/CPU entry, see {@link browserHardwareProfileResult}).
   */
  getAccelerators(): AcceleratorInfo[] {
    const fromProto = HardwareAdapter.tryDefault()?.getAccelerators();
    if (fromProto) return fromProto.accelerators;
    return Hardware.getProfile().accelerators;
  },

  /**
   * Set the preferred accelerator for subsequent inference. Swift parity:
   * `setAcceleratorPreference(_ preference: RAAccelerationPreference)`.
   */
  setAcceleratorPreference(preference: AccelerationPreference): boolean {
    return HardwareAdapter.tryDefault()?.setAccelerationPreference(preference) ?? false;
  },
};
