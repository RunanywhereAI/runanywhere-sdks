/**
 * NitroLLMSpec.ts
 *
 * Hand-written companion to the Nitrogen-generated HybridObject spec.
 * Mirrors NitroVoiceAgentSpec.ts — exposes the singleton `LLM`
 * HybridObject that `LLMStreamAdapter.ts` imports.
 *
 * The native implementation lives in `packages/core/cpp/HybridLLM.{cpp,hpp}`.
 * This TS file encapsulates the lazy `createHybridObject('LLM')` singleton
 * access convention so consumers do not need to know about
 * NitroModulesGlobalInit.
 */

import type { LLM as LLMInterface } from '../../specs/LLM.nitro';
import { getNitroModulesProxySync } from '../../native/NitroModulesGlobalInit';

let _cached: LLMInterface | null = null;

function resolveInstance(): LLMInterface {
  if (_cached != null) return _cached;

  const NitroProxy = getNitroModulesProxySync();
  if (NitroProxy == null) {
    throw new Error(
      'NitroModules is not available for LLM. This can happen in ' +
        'Bridgeless mode if NitroModules is not registered. Check ' +
        'NitroModulesGlobalInit wiring.',
    );
  }

  _cached = NitroProxy.createHybridObject('LLM') as LLMInterface;
  return _cached;
}

/**
 * Lazy singleton accessor for the Nitro-backed LLM HybridObject.
 *
 * Defers `createHybridObject` until the first property access so
 * consumers that only do type-level imports pay no runtime cost.
 * Works with Jest mocks that inject a replacement before any real call.
 */
export const LLM: LLMInterface = new Proxy({} as LLMInterface, {
  get(_target, prop) {
    const instance = resolveInstance() as unknown as Record<
      string | symbol,
      unknown
    >;
    const value = instance[prop];
    return typeof value === 'function' ? value.bind(instance) : value;
  },
});
