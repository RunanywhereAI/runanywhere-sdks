/**
 * RunAnywhere+Hardware.ts
 *
 * Canonical `RunAnywhere.hardware.*` namespace. All values come from the
 * `rac_hardware_*` C ABI exposed by the core Nitro hybrid object — there is
 * no JS-side fallback. Stale native binaries that do not implement the proto
 * methods will surface as `notImplemented` errors from the bridge.
 *
 * Mirrors `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RunAnywhere+Hardware.swift`.
 */

import {
  type AcceleratorInfo,
  AccelerationPreference,
  HardwareAcceleratorPreferenceRequest,
  HardwareAcceleratorPreferenceResult,
  HardwareProfileResult as HardwareProfileResultCodec,
  type HardwareProfileResult,
} from '@runanywhere/proto-ts/hardware_profile';
import { NPUChip } from '@runanywhere/proto-ts/storage_types';
import { isNativeModuleAvailable, requireNativeModule } from '../../native';
import { SDKException } from '../../Foundation/Errors/SDKException';
import { arrayBufferToBytes } from '../../services/ProtoBytes';
import { encodeProtoMessage } from '../../services/ProtoWire';

export type {
  AcceleratorInfo,
  HardwareProfileResult,
} from '@runanywhere/proto-ts/hardware_profile';
export { AccelerationPreference } from '@runanywhere/proto-ts/hardware_profile';
export { NPUChip } from '@runanywhere/proto-ts/storage_types';

/** Snapshot the current hardware profile via `rac_hardware_profile_get`. */
export async function getProfile(): Promise<HardwareProfileResult> {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  const native = requireNativeModule();
  if (typeof native.hardwareProfileProto !== 'function') {
    throw SDKException.notImplemented(
      'hardware.getProfile requires native hardwareProfileProto'
    );
  }
  const buffer = await native.hardwareProfileProto();
  if (buffer.byteLength === 0) {
    throw SDKException.protoDecodeFailed('hardwareProfileProto');
  }
  return HardwareProfileResultCodec.decode(arrayBufferToBytes(buffer));
}

/** Chip / SoC name reported by the native hardware profile. */
export async function getChip(): Promise<string> {
  return (await getProfile()).profile?.chip ?? '';
}

/**
 * Resolve the NPU chipset enum for the current device.
 *
 * The chip-string → vendor classification lives in commons
 * (`rac_hardware_abi.cpp`), which encodes the resolved `NPUChip` into the
 * serialized `HardwareProfile`. This reads that field so every SDK shares one
 * mapping instead of re-implementing it client-side.
 */
export async function getNPUChip(): Promise<NPUChip> {
  return (await getProfile()).profile?.npuChip ?? NPUChip.NPU_CHIP_UNSPECIFIED;
}

/** Whether the current device has a dedicated neural engine / NPU. */
export async function hasNeuralEngine(): Promise<boolean> {
  return (await getProfile()).profile?.hasNeuralEngine ?? false;
}

/** Recommended acceleration mode label (`"ane"`, `"npu"`, `"gpu"`, `"cpu"`). */
export async function accelerationMode(): Promise<string> {
  return (await getProfile()).profile?.accelerationMode ?? 'cpu';
}

/** All accelerators reported by the native hardware profile. */
export async function getAccelerators(): Promise<AcceleratorInfo[]> {
  return (await getProfile()).accelerators ?? [];
}

/**
 * Set the preferred accelerator for subsequent inference routing via
 * `rac_hardware_set_accelerator_preference`. Throws `SDKException` when the
 * native bridge or commons rejects the request.
 */
export async function setAcceleratorPreference(
  preference: AccelerationPreference
): Promise<void> {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  const native = requireNativeModule();
  if (typeof native.setAcceleratorPreferenceProto !== 'function') {
    throw SDKException.notImplemented(
      'hardware.setAcceleratorPreference requires native setAcceleratorPreferenceProto'
    );
  }

  const responseBuffer = await native.setAcceleratorPreferenceProto(
    encodeProtoMessage({ preference }, HardwareAcceleratorPreferenceRequest)
  );
  if (responseBuffer.byteLength === 0) {
    throw SDKException.protoDecodeFailed('setAcceleratorPreferenceProto');
  }
  const result = HardwareAcceleratorPreferenceResult.decode(
    arrayBufferToBytes(responseBuffer)
  );
  if (result.success !== true) {
    throw SDKException.unknown(
      result.errorMessage || 'Failed to set accelerator preference'
    );
  }
}

export const Hardware = {
  getProfile,
  getChip,
  getNPUChip,
  hasNeuralEngine,
  accelerationMode,
  getAccelerators,
  setAcceleratorPreference,
};
