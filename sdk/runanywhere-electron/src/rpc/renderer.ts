// Renderer-side entry: build the v3 facade over the transport the preload
// exposed. Import this in the page's own bundle (it is pure JS, no Node), then
// call connectRenderer() to get the same RunAnywhereApi the main process has.
import { createRunAnywhere } from '../facade.js';
import type { RunAnywhereApi } from '../facade.js';
import { RpcBackend } from './backend.js';
import type { RpcSend } from './backend.js';

interface RpcBridge {
  send: RpcSend;
}

/** Build the RunAnywhere facade over the preload's `window.runanywhereRpc`. */
export function connectRenderer(): RunAnywhereApi {
  const bridge = (globalThis as unknown as { runanywhereRpc?: RpcBridge }).runanywhereRpc;
  if (!bridge?.send) {
    throw new Error(
      'window.runanywhereRpc is unavailable — load @runanywhere/electron/preload in the BrowserWindow preload.'
    );
  }
  return createRunAnywhere(new RpcBackend(bridge.send));
}
