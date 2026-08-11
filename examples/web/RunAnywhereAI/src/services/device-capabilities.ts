/**
 * Display-only device capability label for the model picker banner.
 *
 * Commons does not publish a typed capability tier on DeviceInfo, so the
 * example surfaces `unknown` rather than inventing RAM / WebGPU thresholds
 * or memory budgets. Model fit uses SDK `models.checkCompatibility` →
 * `canRun` when available.
 */

/**
 * Coarse capability label for UI copy. Only `unknown` is produced today —
 * typed tiers would come from an SDK/commons field when one exists.
 */
export type HardwareTier = 'unknown' | 'high' | 'mid' | 'low';

export interface DeviceCapabilities {
  /** RAM in GB from `navigator.deviceMemory` when the browser reports it. */
  deviceMemoryGb: number | null;
  /** Logical cores from `navigator.hardwareConcurrency` when reported. */
  hardwareConcurrency: number | null;
  /** True when a real WebGPU adapter could be acquired; null when unprobed. */
  hasWebGPU: boolean | null;
  /** Whether `SharedArrayBuffer` is available (cross-origin isolation set). */
  hasSharedArrayBuffer: boolean;
  /**
   * Always `unknown` until commons owns a capability_tier. Kept for banner
   * CSS hooks (`device-banner--unknown`); never drives model-fit policy.
   */
  tier: HardwareTier;
}

/**
 * Probe optional browser signals for the banner. Never invents a tier or
 * memory budget — model fit is SDK/commons `can_run`.
 */
export async function detectDeviceCapabilities(): Promise<DeviceCapabilities> {
  const nav: Navigator | undefined =
    typeof navigator === 'undefined' ? undefined : navigator;

  return {
    deviceMemoryGb: readDeviceMemoryGb(nav),
    hardwareConcurrency: readHardwareConcurrency(nav),
    hasWebGPU: await detectWebGPU(nav),
    hasSharedArrayBuffer: typeof SharedArrayBuffer !== 'undefined',
    tier: 'unknown',
  };
}

/**
 * Human-readable one-liner for the picker's device banner. Surfaces facts
 * when known; otherwise says capabilities are unknown.
 */
export function describeCapabilities(caps: DeviceCapabilities): string {
  const parts: string[] = [];
  if (caps.hasWebGPU === true) parts.push('WebGPU');
  else if (caps.hasWebGPU === false) parts.push('CPU (WASM)');
  if (caps.deviceMemoryGb != null) parts.push(`${caps.deviceMemoryGb} GB`);
  parts.push(TIER_LABEL[caps.tier]);
  return parts.join(' \u00b7 ');
}

const TIER_LABEL: Record<HardwareTier, string> = {
  unknown: 'Capabilities unknown',
  high: 'High-performance',
  mid: 'Balanced',
  low: 'Lightweight',
};

function readDeviceMemoryGb(nav: Navigator | undefined): number | null {
  const value = (nav as { deviceMemory?: number } | undefined)?.deviceMemory;
  return typeof value === 'number' && value > 0 ? value : null;
}

function readHardwareConcurrency(nav: Navigator | undefined): number | null {
  const value = nav?.hardwareConcurrency;
  return typeof value === 'number' && value > 0 ? value : null;
}

async function detectWebGPU(nav: Navigator | undefined): Promise<boolean | null> {
  if (!nav || !('gpu' in nav)) return false;
  try {
    const gpu = (nav as { gpu?: { requestAdapter(): Promise<unknown> } }).gpu;
    if (!gpu?.requestAdapter) return false;
    const adapter = await gpu.requestAdapter();
    return adapter != null;
  } catch {
    return null;
  }
}
