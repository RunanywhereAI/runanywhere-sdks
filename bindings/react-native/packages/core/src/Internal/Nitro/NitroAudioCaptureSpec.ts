/**
 * NitroAudioCaptureSpec.ts
 *
 * Hand-written companion to the Nitrogen-generated HybridObject spec.
 * Mirrors NitroLLMSpec.ts — exposes the singleton `AudioCapture`
 * HybridObject that `AudioCaptureManager.ts` uses.
 *
 * The native implementations live in `packages/core/ios/HybridAudioCapture.swift`
 * and `packages/core/android/.../HybridAudioCapture.kt`. This TS file
 * encapsulates the lazy `createHybridObject('AudioCapture')` singleton access
 * convention so consumers do not need to know about NitroModulesGlobalInit.
 */

import type { AudioCapture as AudioCaptureInterface } from '../../specs/AudioCapture.nitro';
import { getNitroModulesProxySync } from '../../native/NitroModulesGlobalInit';

let _cached: AudioCaptureInterface | null = null;

function resolveInstance(): AudioCaptureInterface {
  if (_cached != null) return _cached;

  const NitroProxy = getNitroModulesProxySync();
  if (NitroProxy == null) {
    throw new Error(
      'NitroModules is not available for AudioCapture. This can happen in ' +
        'Bridgeless mode if NitroModules is not registered. Check ' +
        'NitroModulesGlobalInit wiring.',
    );
  }

  _cached = NitroProxy.createHybridObject('AudioCapture') as AudioCaptureInterface;
  return _cached;
}

/**
 * Lazy singleton accessor for the Nitro-backed AudioCapture HybridObject.
 *
 * Defers `createHybridObject` until the first property access so
 * consumers that only do type-level imports pay no runtime cost.
 */
export const AudioCapture: AudioCaptureInterface = new Proxy(
  {} as AudioCaptureInterface,
  {
    get(_target, prop) {
      const instance = resolveInstance() as unknown as Record<
        string | symbol,
        unknown
      >;
      const value = instance[prop];
      return typeof value === 'function' ? value.bind(instance) : value;
    },
  },
);
