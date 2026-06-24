/**
 * @runanywhere/qhexrt - QHexRT Module
 *
 * QHexRT (Qualcomm Hexagon NPU) module wrapper for the RunAnywhere React
 * Native SDK. Provides backend registration and a pre-flight NPU capability
 * probe so apps can warn unsupported devices before loading a model.
 *
 * Model registration is done via RunAnywhere.registerModel() on the core SDK,
 * matching the LlamaCPP / Swift pattern where the backend only exposes
 * register(), unregister(), and (here) probeNpu().
 *
 * QHexRT is Qualcomm-only (Snapdragon Hexagon NPU): Android arm64 exclusively.
 * On non-Snapdragon or non-Android devices the probe reports an unsupported,
 * unknown part and register() returns false.
 */

import { QHexRTProvider } from './QHexRTProvider';
import { SDKLogger } from '@runanywhere/core/internal';

const log = new SDKLogger('NPU.QHexRT');

/**
 * Hexagon DSP (HTP) architecture generation reported by the probe.
 * Mirrors the C enum `rac_hexagon_arch_t`. QHexRT requires v79 or v81.
 */
export enum HexagonArch {
  Unknown = 0,
  V68 = 68,
  V69 = 69,
  V73 = 73,
  V75 = 75,
  V79 = 79,
  V81 = 81,
}

/**
 * Result of the pre-flight NPU capability probe.
 *
 * Mirrors the C struct `rac_npu_info_t` returned by `rac_npu_probe()`.
 */
export interface NpuInfo {
  /** SoC model string (e.g. "SM8750"); empty when unknown. */
  readonly socModel: string;
  /** /sys/devices/soc0/soc_id value; -1 when unavailable. */
  readonly socId: number;
  /** Detected Hexagon architecture, or HexagonArch.Unknown. */
  readonly hexagonArch: HexagonArch;
  /** true iff hexagonArch is one QHexRT supports (v79/v81). */
  readonly qhexrtSupported: boolean;
}

/** The unknown/unsupported fallback used when the probe is unavailable. */
export const UNKNOWN_NPU_INFO: NpuInfo = {
  socModel: '',
  socId: -1,
  hexagonArch: HexagonArch.Unknown,
  qhexrtSupported: false,
};

/** Lowercase arch name ("v79", "v81", ..., "unknown"). */
export function hexagonArchName(arch: HexagonArch): string {
  switch (arch) {
    case HexagonArch.V68: return 'v68';
    case HexagonArch.V69: return 'v69';
    case HexagonArch.V73: return 'v73';
    case HexagonArch.V75: return 'v75';
    case HexagonArch.V79: return 'v79';
    case HexagonArch.V81: return 'v81';
    default: return 'unknown';
  }
}

function parseNpuInfo(json: string | null): NpuInfo {
  if (!json) {
    return UNKNOWN_NPU_INFO;
  }
  try {
    const o = JSON.parse(json) as Partial<{
      socModel: string;
      socId: number;
      hexagonArch: number;
      qhexrtSupported: boolean;
    }>;
    return {
      socModel: typeof o.socModel === 'string' ? o.socModel : '',
      socId: typeof o.socId === 'number' ? o.socId : -1,
      hexagonArch: typeof o.hexagonArch === 'number' ? (o.hexagonArch as HexagonArch) : HexagonArch.Unknown,
      qhexrtSupported: o.qhexrtSupported === true,
    };
  } catch (error) {
    log.warning(`Failed to parse NPU probe result: ${error instanceof Error ? error.message : String(error)}`);
    return UNKNOWN_NPU_INFO;
  }
}

/**
 * QHexRT Module
 *
 * Provides backend registration and the NPU capability probe. Model
 * registration is done via RunAnywhere.registerModel() on the core SDK.
 *
 * ## Usage
 *
 * ```typescript
 * import { QHexRT } from '@runanywhere/qhexrt';
 * import { RunAnywhere } from '@runanywhere/core';
 *
 * const npu = await QHexRT.probeNpu();
 * if (!npu.qhexrtSupported) {
 *   // warn: this device's Hexagon part is not v79/v81
 * }
 * await QHexRT.register();
 * ```
 */
export const QHexRT = {
  HexagonArch,

  /**
   * Register the QHexRT module with the SDK.
   * Registers the LLM, VLM, STT, and TTS providers with the C++ registry.
   */
  async register(): Promise<boolean> {
    log.debug('Registering QHexRT module');
    const registered = await QHexRTProvider.register();
    if (registered) {
      log.info('QHexRT module registered');
    }
    return registered;
  },

  /**
   * Unregister the QHexRT module from the SDK.
   */
  async unregister(): Promise<boolean> {
    log.info('Unregistering QHexRT module');
    return QHexRTProvider.unregister();
  },

  /**
   * Check if this module is registered with the native backend registry.
   */
  async isRegistered(): Promise<boolean> {
    return QHexRTProvider.isRegistered();
  },

  /**
   * Pre-flight probe of the device's Qualcomm Hexagon NPU capability.
   * Does NOT load QNN or the engine. Returns the unknown/unsupported fallback
   * when the native module is unavailable (e.g. non-Snapdragon devices).
   */
  async probeNpu(): Promise<NpuInfo> {
    const raw = await QHexRTProvider.probeNpuRaw();
    return parseNpuInfo(raw);
  },
};
