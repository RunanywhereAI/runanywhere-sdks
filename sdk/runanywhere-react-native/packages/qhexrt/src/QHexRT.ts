/**
 * @runanywhere/qhexrt - QHexRT Module
 *
 * QHexRT (Qualcomm Hexagon NPU) module wrapper for the RunAnywhere React
 * Native SDK. Provides backend registration and a pre-flight NPU capability
 * probe so apps can warn unsupported devices before loading a model.
 *
 * App-owned model URLs and metadata cross the QHexRT catalog facade, which
 * selects the matching device architecture before composing core lifecycle
 * registration and download services.
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
import {
  type ModelInfo,
  type RegisterModelFromUrlRequest,
} from '@runanywhere/proto-ts/model_types';
import { QHexRTCatalogWire } from './QHexRTCatalogWire';

const log = new SDKLogger('NPU.QHexRT');

// Re-export the generated wire types so consumers never hand-mirror them.
export { NpuCapability, HexagonArch };

/**
 * The unknown/unsupported fallback used when the native probe is unavailable
 * (non-Android platforms, non-Snapdragon devices, or an older commons without
 * rac_qhexrt_probe_proto).
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
 * Provides backend registration, the NPU capability probe, and device-aware
 * registration for app-owned QHexRT catalog definitions.
 *
 * ## Usage
 *
 * ```typescript
 * import { QHexRT } from '@runanywhere/qhexrt';
 * import { RunAnywhere } from '@runanywhere/core';
 *
 * const npu = await QHexRT.probeNpu();
 * if (!npu.qhexrtSupported) {
 *   // warn: this device is not in the validated V75/V79/V81 set
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
   * `runanywhere.v1.NpuCapability` proto emitted by QHexRT's
   * rac_qhexrt_probe_proto(). Returns the unknown/unsupported fallback
   * (socId -1, archName "unknown") when the native module is unavailable
   * (e.g. non-Snapdragon devices).
   */
  async probeNpu(): Promise<NpuCapability> {
    const raw = await QHexRTProvider.probeNpuRaw();
    return decodeNpuCapability(raw);
  },

  /** The native QHexRT support policy; no V75/V79/V81 set is copied in TS. */
  isArchitectureSupported(arch: HexagonArch): boolean {
    return QHexRTProvider.isArchitectureSupported(arch);
  },

  /** Match a model definition's generated architecture values in QHexRT. */
  modelSupportsArchitecture(
    supportedArches: Iterable<HexagonArch>,
    arch: HexagonArch
  ): boolean {
    return QHexRTProvider.modelSupportsArchitecture(
      QHexRTCatalogWire.archValues(supportedArches),
      arch
    );
  },

  /**
   * Register an app-owned URL/model definition only when it matches the
   * current device. Native QHexRT owns probing and chip selection, then
   * composes commons' shared registration/download pipeline. `null` is the
   * normal ineligible model/device outcome.
   */
  async registerModelForDevice(
    request: RegisterModelFromUrlRequest,
    supportedArches: Iterable<HexagonArch>
  ): Promise<ModelInfo | null> {
    const raw = await QHexRTProvider.registerModelForDeviceRaw(
      QHexRTCatalogWire.encodeRequest(request),
      QHexRTCatalogWire.archValues(supportedArches)
    );
    return raw ? QHexRTCatalogWire.decodeModel(raw) : null;
  },
};
