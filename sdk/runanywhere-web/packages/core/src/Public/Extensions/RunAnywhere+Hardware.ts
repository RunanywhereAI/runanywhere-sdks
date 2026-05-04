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
 * Hardware data is currently scraped from `navigator.*` and the active
 * runtime acceleration mode (`Runtime.preferred`) — there is no dedicated
 * `rac_hardware_profile_*` C ABI yet (G-C6 / G-B1 [CPP-BLOCKED]). When that
 * lands the implementation here can drop the `navigator` paths and route
 * through the new C ABI without changing the public shape.
 */

import { Runtime, type RuntimeAccelerationMode } from '../../Foundation/RuntimeConfig';
import {
  AcceleratorPreference,
  type HardwareProfileResult,
} from '@runanywhere/proto-ts/hardware_profile';

export type { HardwareProfile, HardwareProfileResult } from '@runanywhere/proto-ts/hardware_profile';

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

export const Hardware = {
  /** Snapshot the current hardware profile. */
  getProfile(): HardwareProfileResult {
    const nav = getNavigator();
    const accelerationMode = detectAccelerationMode();
    const webgpuAvailable = detectWebGPU();
    return {
      profile: {
        chip: detectChip(),
        hasNeuralEngine: detectChip() === 'apple-silicon',
        accelerationMode,
        totalMemoryBytes: Math.round((nav?.deviceMemory ?? 0) * 1024 * 1024 * 1024),
        coreCount: nav?.hardwareConcurrency ?? 0,
        performanceCores: 0,
        efficiencyCores: 0,
        architecture: detectChip(),
        platform: 'web',
      },
      accelerators: [
        {
          name: webgpuAvailable ? 'webgpu' : accelerationMode,
          type: webgpuAvailable
            ? AcceleratorPreference.ACCELERATOR_PREFERENCE_GPU
            : AcceleratorPreference.ACCELERATOR_PREFERENCE_CPU,
          available: true,
        },
      ],
    };
  },

  /** Best-effort chip name (e.g., "apple-silicon", "x86_64"). */
  getChip(): string {
    return detectChip();
  },

  /**
   * Whether the device has a Neural Engine. Today this is approximated by
   * `chip === 'apple-silicon'`; a real check needs the `rac_hardware_profile_*`
   * C ABI (G-C6 [CPP-BLOCKED]).
   */
  get hasNeuralEngine(): boolean {
    return detectChip() === 'apple-silicon';
  },

  /**
   * Active acceleration mode. Reflects the value of
   * `RunAnywhere.runtime.preferred` (or the resolved `activeMode` when
   * `preferred === 'auto'`).
   */
  get accelerationMode(): string {
    return detectAccelerationMode();
  },
};
