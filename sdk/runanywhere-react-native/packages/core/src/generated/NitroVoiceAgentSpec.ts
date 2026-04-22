/**
 * NitroVoiceAgentSpec.ts
 *
 * v3-readiness Phase A3 / GAP 09 #6. Hand-written companion to the
 * Nitrogen-generated HybridObject spec (mirrors the pattern used by
 * TelemetryService.ts for RunAnywhereCore). Exposes the singleton
 * `VoiceAgent` HybridObject that `VoiceAgentStreamAdapter.ts` imports.
 *
 * The actual native implementation lives in
 * `packages/core/cpp/HybridVoiceAgent.{cpp,hpp}`. This TS file is the
 * JS-side import surface that lazily constructs the singleton via
 * NitroModules's `createHybridObject('VoiceAgent')` factory.
 *
 * Why hand-written instead of auto-generated: Nitrogen currently emits
 * only the TS interface + the C++ base class; the TS singleton access
 * pattern is project-owned convention. This file encapsulates that
 * convention so consumers (the streaming adapter) can import a ready
 * object without knowing about NitroModulesGlobalInit.
 */

import type { VoiceAgent as VoiceAgentInterface } from '../specs/VoiceAgent.nitro';
import { getNitroModulesProxySync } from '../native/NitroModulesGlobalInit';

let _cached: VoiceAgentInterface | null = null;

function resolveInstance(): VoiceAgentInterface {
  if (_cached != null) return _cached;

  const NitroProxy = getNitroModulesProxySync();
  if (NitroProxy == null) {
    throw new Error(
      'NitroModules is not available for VoiceAgent. This can happen in ' +
        'Bridgeless mode if NitroModules is not registered. Check ' +
        'NitroModulesGlobalInit wiring.',
    );
  }

  // The C++ side registers this HybridObject under the name 'VoiceAgent'
  // in its JNI_OnLoad / iOS registerNitroPlugin call site (packages/core/cpp).
  _cached = NitroProxy.createHybridObject('VoiceAgent') as VoiceAgentInterface;
  return _cached;
}

/**
 * Lazy singleton accessor for the Nitro-backed VoiceAgent HybridObject.
 *
 * The proxy getter defers the `createHybridObject` call until the first
 * property access so consumers that only do type-level imports (no
 * method calls) pay no runtime cost. Works with Jest mocks that may
 * inject a replacement before any real call.
 */
export const VoiceAgent: VoiceAgentInterface = new Proxy({} as VoiceAgentInterface, {
  get(_target, prop) {
    const instance = resolveInstance() as unknown as Record<
      string | symbol,
      unknown
    >;
    const value = instance[prop];
    return typeof value === 'function' ? value.bind(instance) : value;
  },
});
