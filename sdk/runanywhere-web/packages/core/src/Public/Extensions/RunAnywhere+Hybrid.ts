/**
 * RunAnywhere+Hybrid.ts
 *
 * Hybrid STT router namespace — `RunAnywhere.hybrid.*`. Cross-SDK parity with
 * Kotlin (`RACRouter`) and Swift (`HybridSTTRouter`): per-request dispatch
 * between an on-device (offline, sherpa) and a cloud (online, cloud) STT
 * service, with commons owning the entire routing decision.
 *
 * Thin facade over `HybridSttRouter` + `CloudSTT` + the device-state /
 * custom-filter installers. See `Hybrid/HybridWasmModule.ts` for the WASM
 * build delta this needs to run end-to-end.
 */

import { HybridSttRouter } from './Hybrid/HybridSttRouter';
import { CloudSTT, cloud, type CloudSTTConfig } from './Hybrid/CloudSTT';
import {
  registerCloudSttProvider,
  unregisterCloudSttProvider,
  type SttProviderHandler,
} from './Hybrid/CloudSttProvider';
import {
  setHybridDeviceStateProvider,
  browserDeviceStateProvider,
  type HybridDeviceStateProvider,
} from './Hybrid/HybridDeviceState';

export const Hybrid = {
  /** True iff the loaded WASM exports the hybrid STT router ABI (the build
   * delta in Hybrid/HybridWasmModule.ts has landed). */
  isSupported(): boolean {
    return HybridSttRouter.isSupported();
  },

  /** Create a hybrid STT router. Throws `backendNotAvailable` when the WASM
   * build lacks the router exports. The caller owns the router and MUST
   * `close()` it. Mirrors `RACRouter.stt.init(...)` / `HybridSTTRouter()`. */
  createSttRouter(): Promise<HybridSttRouter> {
    return HybridSttRouter.create();
  },

  /** Register a cloud-STT model the router can refer to by id from the online
   * side (`onlineCloud(id)`). Provider is data (default "sarvam"). */
  registerCloudModel(config: CloudSTTConfig): void {
    CloudSTT.register(config);
  },

  /** Build a cloud-STT registry entry from a generic provider config without
   * registering it: `cloud({ provider: 'sarvam', apiKey, model })`. */
  cloud,

  /** Fold the cloud engine plugin into the WASM registry so the online
   * side is routable. Returns false when the build doesn't link the cloud engine. */
  registerCloudBackend(): boolean {
    return CloudSTT.registerBackend();
  },

  /** Register a developer-defined cloud STT provider handler by name (the
   * host owns build + HTTP + parse). Mirrors Swift `Cloud.registerProvider`. */
  registerCloudProvider(name: string, handler: SttProviderHandler): boolean {
    return registerCloudSttProvider(name, handler);
  },

  /** Remove a developer-defined cloud STT provider. Idempotent for unknown
   * names. Mirrors Swift `Cloud.unregisterProvider`. */
  unregisterCloudProvider(name: string): void {
    unregisterCloudSttProvider(name);
  },

  /** Install the host device-state provider the router consults for the
   * NETWORK / Battery filters. Pass `null` to restore the commons default. */
  setDeviceStateProvider(provider: HybridDeviceStateProvider | null): boolean {
    return setHybridDeviceStateProvider(provider);
  },

  /** A default `navigator`-backed device-state provider (tracks online/offline;
   * battery=100, thermal=false since the browser exposes neither synchronously). */
  browserDeviceStateProvider,
};
