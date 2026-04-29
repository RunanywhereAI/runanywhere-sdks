/**
 * NitroLLMSpec.ts
 *
 * Hand-written companion to the Nitrogen-generated HybridObject spec
 * (mirrors `NitroVoiceAgentSpec.ts`). Exposes the singleton `LLM`
 * HybridObject that `LLMStreamAdapter.ts` imports.
 *
 * The actual native implementation lives in
 * `packages/core/cpp/HybridLLM.{cpp,hpp}`. This TS file is the JS-side
 * import surface that lazily constructs the singleton via NitroModules's
 * `createHybridObject('LLM')` factory.
 *
 * Why hand-written instead of auto-generated: Nitrogen currently emits
 * only the TS interface + the C++ base class; the TS singleton access
 * pattern is project-owned convention.
 */

import type { LLM as LLMInterface } from '../specs/LLM.nitro';
import { getNitroModulesProxySync } from '../native/NitroModulesGlobalInit';

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

  // The C++ side registers this HybridObject under the name 'LLM'
  // in its JNI_OnLoad / iOS registerNitroPlugin call site (packages/core/cpp).
  _cached = NitroProxy.createHybridObject('LLM') as LLMInterface;
  return _cached;
}

/**
 * Lazy singleton accessor for the Nitro-backed LLM HybridObject.
 *
 * The proxy getter defers the `createHybridObject` call until the first
 * property access so consumers that only do type-level imports (no
 * method calls) pay no runtime cost. Works with Jest mocks that may
 * inject a replacement before any real call.
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
