/**
 * NitroAudioPlaybackSpec.ts
 *
 * Hand-written companion to the Nitrogen-generated HybridObject spec.
 * Mirrors NitroLLMSpec.ts — exposes the singleton `AudioPlayback`
 * HybridObject that `AudioPlaybackManager.ts` uses.
 *
 * The native implementations live in `packages/core/ios/HybridAudioPlayback.swift`
 * and `packages/core/android/.../HybridAudioPlayback.kt`. This TS file
 * encapsulates the lazy `createHybridObject('AudioPlayback')` singleton access
 * convention so consumers do not need to know about NitroModulesGlobalInit.
 */

import type { AudioPlayback as AudioPlaybackInterface } from '../../specs/AudioPlayback.nitro';
import { getNitroModulesProxySync } from '../../native/NitroModulesGlobalInit';

let _cached: AudioPlaybackInterface | null = null;

function resolveInstance(): AudioPlaybackInterface {
  if (_cached != null) return _cached;

  const NitroProxy = getNitroModulesProxySync();
  if (NitroProxy == null) {
    throw new Error(
      'NitroModules is not available for AudioPlayback. This can happen in ' +
        'Bridgeless mode if NitroModules is not registered. Check ' +
        'NitroModulesGlobalInit wiring.',
    );
  }

  _cached = NitroProxy.createHybridObject(
    'AudioPlayback',
  ) as AudioPlaybackInterface;
  return _cached;
}

/**
 * Lazy singleton accessor for the Nitro-backed AudioPlayback HybridObject.
 *
 * Defers `createHybridObject` until the first property access so
 * consumers that only do type-level imports pay no runtime cost.
 */
export const AudioPlayback: AudioPlaybackInterface = new Proxy(
  {} as AudioPlaybackInterface,
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
