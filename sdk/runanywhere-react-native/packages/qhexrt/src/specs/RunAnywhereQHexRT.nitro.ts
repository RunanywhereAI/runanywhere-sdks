/**
 * RunAnywhereQHexRT Nitrogen Spec
 *
 * QHexRT (Qualcomm Hexagon NPU) backend registration + NPU capability probe.
 *
 * Public lifecycle, generation, VLM, STT, and TTS APIs live in
 * @runanywhere/core and route through commons proto/lifecycle bridges. This
 * backend package only registers the native provider and exposes a pre-flight
 * NPU probe so the app can warn unsupported devices before loading a model.
 *
 * NOTE: After editing this file, run `yarn qhexrt:nitrogen` (nitro-codegen) to
 * regenerate the bridge code under `nitrogen/generated/`. Those files are
 * auto-generated and must not be hand-edited.
 */
import type { HybridObject } from 'react-native-nitro-modules';

/**
 * QHexRT native registration + probe interface.
 *
 * The single `registerBackend()` / `unregisterBackend()` pair covers all
 * QHexRT modalities (LLM, VLM, STT, TTS) — the underlying C++ symbol
 * `rac_backend_qhexrt_register()` registers every per-domain service.
 *
 * QHexRT is Qualcomm-only (Snapdragon Hexagon NPU); the package ships
 * arm64-v8a Android binaries exclusively.
 */
export interface RunAnywhereQHexRT
  extends HybridObject<{
    android: 'c++';
  }> {
  /**
   * Register the QHexRT backend with the C++ service registry.
   * Calls rac_backend_qhexrt_register(); the single call covers LLM, VLM,
   * STT, and TTS. Safe to call multiple times - subsequent calls are no-ops.
   * @returns true if registered successfully (or already registered)
   */
  registerBackend(): Promise<boolean>;

  /**
   * Unregister the QHexRT backend from the C++ service registry.
   * @returns true if unregistered successfully
   */
  unregisterBackend(): Promise<boolean>;

  /**
   * Check if the QHexRT backend is registered.
   * @returns true if backend is registered
   */
  isBackendRegistered(): Promise<boolean>;

  /**
   * Pre-flight probe of the device's Qualcomm Hexagon NPU capability.
   * Calls rac_npu_probe_proto() in commons; does NOT load QNN or the engine.
   * @returns serialized `runanywhere.v1.NpuCapability` proto bytes — decode
   *   with `NpuCapability.decode()` from
   *   `@runanywhere/proto-ts/hardware_profile`. An empty buffer means the
   *   probe is unavailable on this device/build.
   */
  probeNpuProto(): Promise<ArrayBuffer>;
}
