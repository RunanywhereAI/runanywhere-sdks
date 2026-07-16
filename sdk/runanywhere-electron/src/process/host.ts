// host.ts — entry point for the Electron utilityProcess that owns the native
// addon. Loads the .node once, then serves RPC requests from one or more
// renderer-connected MessagePorts (each delivered by RunAnywhereMain). Heavy
// inference runs here, isolated from the main + renderer processes.
import * as os from 'os';
import * as path from 'path';

import { addon } from '../bridge';
import { RpcRequest, STREAMING_METHODS } from './rpc';

// electron's utility-process ParentPort / MessagePortMain are loosely typed here
// so this file compiles without pulling electron's full type surface into the
// Node-facing SDK build.
interface Port {
  postMessage(message: unknown): void;
  on(event: 'message', cb: (e: { data: unknown }) => void): void;
  start(): void;
}
interface ParentPort {
  on(event: 'message', cb: (e: { ports: Port[]; data: unknown }) => void): void;
  postMessage(message: unknown): void;
}
const parentPort = (process as unknown as { parentPort: ParentPort }).parentPort;

const errmsg = (e: unknown): string => (e instanceof Error ? e.message : String(e));

function dispatch(port: Port, req: RpcRequest): void {
  const { id, method, args } = req;
  const api = addon as unknown as Record<string, (...a: unknown[]) => unknown>;
  try {
    if (STREAMING_METHODS.has(method)) {
      const onToken = (token: string) => port.postMessage({ id, token });
      (api[method](...args, onToken) as Promise<void>)
        .then(() => port.postMessage({ id, done: true }))
        .catch((e) => port.postMessage({ id, ok: false, error: errmsg(e) }));
      return;
    }
    if (method === 'version') {
      port.postMessage({ id, ok: true, result: addon.version });
      return;
    }
    if (method === 'initialize') {
      const home = path.join(os.homedir(), '.runanywhere');
      const base = (args[1] as string) || home;
      const secure = (args[0] as string) || path.join(base, 'secure');
      addon.initialize(secure, base);
      port.postMessage({ id, ok: true });
      return;
    }
    port.postMessage({ id, ok: true, result: api[method](...args) });
  } catch (e) {
    port.postMessage({ id, ok: false, error: errmsg(e) });
  }
}

parentPort.on('message', (e) => {
  const port = e.ports[0];
  if (!port) return;
  port.on('message', (ev) => dispatch(port, ev.data as RpcRequest));
  port.start();
  parentPort.postMessage({ ready: true });
});
