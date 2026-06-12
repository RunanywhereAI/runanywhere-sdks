/**
 * NativeRunAnywhereCore.ts
 *
 * Lazy accessor for the `RunAnywhereCore` Nitro hybrid object that mirrors
 * the C++ `runanywhere-commons` ABI. All SDK capabilities (LLM, STT, TTS,
 * VAD, VLM, RAG, hardware, registry, storage, events, …) are reached
 * through this single proxy. Backend packages register themselves with
 * commons separately (`@runanywhere/llamacpp`, `@runanywhere/onnx`).
 */

import type { RunAnywhereCore } from '../specs/RunAnywhereCore.nitro';
import {
  getNitroModulesProxySync,
  type NitroProxy,
} from './NitroModulesGlobalInit';

export type NativeRunAnywhereModule = RunAnywhereCore;

function getNitroModulesProxy(): NitroProxy | null {
  return getNitroModulesProxySync();
}

let _nativeModule: NativeRunAnywhereModule | undefined;

/**
 * Retrieve the `RunAnywhereCore` hybrid object, throwing if NitroModules is
 * not installed. Callers that want a soft check should use
 * `isNativeModuleAvailable()` first.
 */
export function requireNativeModule(): NativeRunAnywhereModule {
  if (_nativeModule) return _nativeModule;
  const proxy = getNitroModulesProxy();
  if (!proxy) {
    throw new Error(
      'NitroModules is not available. This can happen in Bridgeless mode if ' +
        'react-native-nitro-modules is not properly linked.'
    );
  }
  _nativeModule = proxy.createHybridObject('RunAnywhereCore') as RunAnywhereCore;
  return _nativeModule;
}

export function isNativeModuleAvailable(): boolean {
  try {
    requireNativeModule();
    return true;
  } catch {
    return false;
  }
}
