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
import {
  NpuCapability,
  HexagonArch,
} from '@runanywhere/proto-ts/hardware_profile';

const log = new SDKLogger('NPU.QHexRT');

// Re-export the generated wire types so consumers never hand-mirror them.
export { NpuCapability, HexagonArch };

/**
 * The unknown/unsupported fallback used when the native probe is unavailable
 * (non-Android platforms, non-Snapdragon devices, or an older commons without
 * rac_npu_probe_proto).
 */
function unknownNpuCapability(): NpuCapability {
  return NpuCapability.fromPartial({ socId: -1, archName: 'unknown' });
}

function decodeNpuCapability(buffer: ArrayBuffer | null): NpuCapability {
  if (!buffer || buffer.byteLength === 0) {
    return unknownNpuCapability();
  }
  try {
    return NpuCapability.decode(new Uint8Array(buffer));
  } catch (error) {
    log.warning(
      `Failed to decode NPU probe result: ${error instanceof Error ? error.message : String(error)}`
    );
    return unknownNpuCapability();
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
 *   // warn: this device's Hexagon part is not v75/v79/v81
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
   * Does NOT load QNN or the engine. Decodes the serialized
   * `runanywhere.v1.NpuCapability` proto emitted by commons'
   * rac_npu_probe_proto(). Returns the unknown/unsupported fallback
   * (socId -1, archName "unknown") when the native module is unavailable
   * (e.g. non-Snapdragon devices).
   */
  async probeNpu(): Promise<NpuCapability> {
    const raw = await QHexRTProvider.probeNpuRaw();
    return decodeNpuCapability(raw);
  },
};
