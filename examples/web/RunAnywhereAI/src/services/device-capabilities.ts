/**
 * Device capability detection — a small, defensive probe of the browser's
 * hardware surface used to tailor the model picker's recommendations.
 *
 * All inputs come from optional/experimental browser APIs, so every access is
 * guarded and falls back to a conservative default. The result is a flat,
 * typed object; the recommendation engine (`model-recommendation.ts`) is the
 * only consumer that maps it to concrete model suggestions.
 */

/**
 * Coarse hardware bucket the picker uses to size its recommendations.
 * `high` unlocks the largest LLM (qwen3-4b); `low` sticks to sub-500M models.
 */
export type HardwareTier = 'high' | 'mid' | 'low';

export interface DeviceCapabilities {
  /** RAM in GB from `navigator.deviceMemory`; falls back to 8 when unknown. */
  deviceMemoryGb: number;
  /** Logical cores from `navigator.hardwareConcurrency`; falls back to 4. */
  hardwareConcurrency: number;
  /** True when a real WebGPU adapter could be acquired. */
  hasWebGPU: boolean;
  /** Whether `SharedArrayBuffer` is available (cross-origin isolation set). */
  hasSharedArrayBuffer: boolean;
  /** Derived bucket used to size recommendations. */
  tier: HardwareTier;
  /** Memory budget, in bytes, a model's `memoryRequiredBytes` must fit under. */
  memoryBudgetBytes: number;
}

const DEFAULT_DEVICE_MEMORY_GB = 8;
const DEFAULT_HARDWARE_CONCURRENCY = 4;

/**
 * WASM builds run against a 32-bit heap capped near 4 GB, and a single model
 * ArrayBuffer must fit in memory. We keep budgets well under the reported RAM
 * so downloads + runtime overhead stay comfortable.
 */
const MEMORY_BUDGET_BYTES: Record<HardwareTier, number> = {
  high: 3_200_000_000,
  mid: 1_100_000_000,
  low: 650_000_000,
};

/**
 * Probe the browser for hardware signals. Pure with respect to the DOM (reads
 * only `navigator`/globals) and never throws — a hostile or missing API just
 * degrades the tier. `requestAdapter()` is awaited behind a try/catch because
 * some browsers expose `navigator.gpu` but reject adapter acquisition.
 */
export async function detectDeviceCapabilities(): Promise<DeviceCapabilities> {
  const nav: Navigator | undefined =
    typeof navigator === 'undefined' ? undefined : navigator;

  const deviceMemoryGb = readDeviceMemoryGb(nav);
  const hardwareConcurrency = readHardwareConcurrency(nav);
  const hasWebGPU = await detectWebGPU(nav);
  const hasSharedArrayBuffer = typeof SharedArrayBuffer !== 'undefined';

  const tier = deriveTier(deviceMemoryGb, hasWebGPU);

  return {
    deviceMemoryGb,
    hardwareConcurrency,
    hasWebGPU,
    hasSharedArrayBuffer,
    tier,
    memoryBudgetBytes: MEMORY_BUDGET_BYTES[tier],
  };
}

/** WebGPU + >=8 GB → high; >=4 GB → mid; otherwise low. */
function deriveTier(deviceMemoryGb: number, hasWebGPU: boolean): HardwareTier {
  if (hasWebGPU && deviceMemoryGb >= 8) return 'high';
  if (deviceMemoryGb >= 4) return 'mid';
  return 'low';
}

function readDeviceMemoryGb(nav: Navigator | undefined): number {
  const value = (nav as { deviceMemory?: number } | undefined)?.deviceMemory;
  return typeof value === 'number' && value > 0
    ? value
    : DEFAULT_DEVICE_MEMORY_GB;
}

function readHardwareConcurrency(nav: Navigator | undefined): number {
  const value = nav?.hardwareConcurrency;
  return typeof value === 'number' && value > 0
    ? value
    : DEFAULT_HARDWARE_CONCURRENCY;
}

async function detectWebGPU(nav: Navigator | undefined): Promise<boolean> {
  if (!nav || !('gpu' in nav)) return false;
  try {
    const gpu = (nav as { gpu?: { requestAdapter(): Promise<unknown> } }).gpu;
    if (!gpu?.requestAdapter) return false;
    const adapter = await gpu.requestAdapter();
    return adapter != null;
  } catch {
    return false;
  }
}

/**
 * Human-readable one-liner for the picker's device banner, e.g.
 * "WebGPU · 8 GB · High-performance".
 */
export function describeCapabilities(caps: DeviceCapabilities): string {
  const parts: string[] = [];
  parts.push(caps.hasWebGPU ? 'WebGPU' : 'CPU (WASM)');
  parts.push(`${caps.deviceMemoryGb} GB`);
  parts.push(TIER_LABEL[caps.tier]);
  return parts.join(' \u00b7 ');
}

const TIER_LABEL: Record<HardwareTier, string> = {
  high: 'High-performance',
  mid: 'Balanced',
  low: 'Lightweight',
};
