// Runs in the renderer's isolated preload context. Receives the MessagePort
// brokered by RunAnywhereMain, speaks the RPC protocol to the utility host, and
// exposes a single safe transport function via contextBridge. The renderer then
// builds the same v3 facade over it (see connectRenderer), so no port and no
// native handle ever leak into the page.
import { contextBridge, ipcRenderer } from 'electron';

import { asSDKException } from '../errors.js';
import type { RpcMessage } from './protocol.js';

type Pending = {
  resolve: (value: unknown) => void;
  reject: (error: Error) => void;
  onChunk?: (chunk: unknown) => void;
  onToolExec?: (toolCall: Uint8Array) => Uint8Array | Promise<Uint8Array>;
};

let port: MessagePort | null = null;
let nextId = 1;
const pending = new Map<number, Pending>();
let ready: Promise<void>;
let markReady: () => void = () => {};

// (Re)create the ready gate so a fresh port (initial connect or a reconnect after
// a host crash) re-enables send().
function armReady(): void {
  ready = new Promise<void>((resolve) => {
    markReady = resolve;
  });
}
armReady();

function rejectAllPending(error: Error): void {
  for (const [, p] of pending) p.reject(error);
  pending.clear();
}

ipcRenderer.on('runanywhere-port', (event) => {
  port = event.ports[0];
  port.onmessage = (ev: MessageEvent) => {
    const m = ev.data as RpcMessage;
    const p = pending.get(m.id);
    if (!p) return;
    if ('chunk' in m) {
      p.onChunk?.(m.chunk);
      return;
    }
    if ('toolExec' in m) {
      // The host asked us to run a tool; execute it here and post the result back.
      const exec = p.onToolExec;
      const reply = (toolResult: Uint8Array): void =>
        port!.postMessage({ id: m.id, execId: m.execId, toolResult });
      if (!exec) {
        reply(new Uint8Array());
        return;
      }
      Promise.resolve(exec(m.toolExec)).then(reply, () => reply(new Uint8Array()));
      return;
    }
    pending.delete(m.id);
    if ('done' in m) p.resolve((m as { result?: unknown }).result);
    else if (m.ok) p.resolve(m.result);
    else p.reject(asSDKException(m.error));
  };
  port.onmessageerror = () => {
    /* ignore an undeserializable message rather than wedge the port */
  };
  port.start();
  markReady();
});

// The main process reports when the utility host exits (crash or kill). Fail all
// outstanding calls and re-arm the gate so a later connect() recovers.
ipcRenderer.on('runanywhere-host-exited', (_e, code?: number) => {
  port = null;
  armReady();
  rejectAllPending(
    asSDKException(`inference host exited unexpectedly (code ${code ?? 'unknown'})`)
  );
});

function send(
  method: string,
  args: unknown[],
  onChunk?: (chunk: unknown) => void,
  onToolExec?: (toolCall: Uint8Array) => Uint8Array | Promise<Uint8Array>
): Promise<unknown> {
  return ready.then(
    () =>
      new Promise((resolve, reject) => {
        const id = nextId++;
        pending.set(id, { resolve, reject, onChunk, onToolExec });
        port!.postMessage({ id, method, args });
      })
  );
}

// The renderer builds `new RpcBackend(window.runanywhereRpc.send)` (see
// connectRenderer). Only this transport crosses the bridge; the facade itself
// runs in the page's own isolated world.
contextBridge.exposeInMainWorld('runanywhereRpc', { send });
