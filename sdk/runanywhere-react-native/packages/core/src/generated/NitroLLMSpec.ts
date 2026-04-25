/**
 * NitroLLMSpec.ts
 *
 * v2 close-out Phase G-2. Hand-written companion to the
 * Nitrogen-generated HybridObject spec (mirrors the pattern used by
 * NitroVoiceAgentSpec.ts). Exposes the singleton `LLM` HybridObject
 * that `LLMStreamAdapter.ts` imports.
 *
 * The actual native implementation lives in
 * `packages/core/cpp/HybridLLM.{cpp,hpp}` (scaffolded under this phase;
 * wiring `rac_llm_set_stream_proto_callback` on the JSI side mirrors
 * HybridVoiceAgent's proto-byte dispatch).
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

  _cached = NitroProxy.createHybridObject('LLM') as LLMInterface;
  return _cached;
}

/**
 * Lazy singleton accessor for the Nitro-backed LLM HybridObject.
 * Parity with `NitroVoiceAgentSpec`'s Proxy pattern — type-only imports
 * pay no runtime cost.
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
