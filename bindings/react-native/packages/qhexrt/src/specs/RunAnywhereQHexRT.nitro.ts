/**
 * RunAnywhereQHexRT Nitrogen Spec
 *
 * QHexRT (Qualcomm Hexagon NPU) backend registration, capability probe, and
 * device-aware catalog adapter.
 *
 * Public lifecycle, generation, VLM, STT, and TTS APIs live in
 * @runanywhere/core and route through commons proto/lifecycle bridges. This
 * backend package registers the native provider and transports capability and
 * catalog calls into the engine-owned QHexRT policy facade.
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
export interface RunAnywhereQHexRT extends HybridObject<{
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
   * Calls rac_qhexrt_probe_proto() in the QHexRT engine; does NOT load QNN.
   * @returns serialized `runanywhere.v1.NpuCapability` proto bytes — decode
   *   with `NpuCapability.decode()` from
   *   `@runanywhere/proto-ts/hardware_profile`. An empty buffer means the
   *   probe is unavailable on this device/build.
   */
  probeNpuProto(): Promise<ArrayBuffer>;

  /** True when `arch` is in QHexRT's native device-validated support set. */
  isArchitectureSupported(arch: number): boolean;

  /** Match native product policy for `modelId` against `arch`. */
  modelSupportsArchitecture(modelId: string, arch: number): boolean;

  /** Whether native product policy marks `modelId` HF-authenticated. */
  modelRequiresHfAuth(modelId: string): boolean;

  /**
   * Register a serialized `RegisterModelFromUrlRequest` only when native
   * product policy allows it on this device. Returns serialized `ModelInfo`,
   * or an empty buffer for a normal ineligible/private-without-token outcome.
   */
  catalogRegisterModelProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;
}
