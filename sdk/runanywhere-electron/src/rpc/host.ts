// Entry point for the Electron utilityProcess that owns the native addon. Loads
// the .node once, wraps it in a NativeBackend, and serves RPC requests from one
// or more renderer-connected MessagePorts (each delivered by RunAnywhereMain).
// Heavy inference runs here, isolated from the main and renderer processes; the
// routing itself lives in dispatch.ts.
import { NativeBackend } from '../native/backend.js';
import { loadAddon } from '../native/load.js';
import { dispatch, ToolExecBridge } from './dispatch.js';
import type { BackendMap } from './dispatch.js';
import { isToolExecReply } from './protocol.js';
import type { RpcRequest } from './protocol.js';

const backend = new NativeBackend(loadAddon()) as unknown as BackendMap;

// Electron's utility-process ParentPort / MessagePortMain are loosely typed here
// so this file compiles without pulling Electron's full type surface into the
// Node-facing build.
interface Port {
  postMessage(message: unknown): void;
  on(event: 'message', cb: (e: { data: unknown }) => void): void;
  on(event: 'close', cb: () => void): void;
  start(): void;
}
interface ParentPort {
  on(event: 'message', cb: (e: { ports: Port[]; data: unknown }) => void): void;
  postMessage(message: unknown): void;
}

const parentPort = (process as unknown as { parentPort: ParentPort }).parentPort;

parentPort.on('message', (e) => {
  const port = e.ports[0];
  if (!port) return;
  // A renderer reload closes its old port; stop dispatching to a dead one so
  // in-flight work isn't posted into the void and the port can be released.
  let alive = true;
  const toolBridge = new ToolExecBridge(port);
  port.on('message', (ev) => {
    if (!alive) return;
    if (isToolExecReply(ev.data)) {
      toolBridge.resolveReply(ev.data);
      return;
    }
    dispatch(port, ev.data as RpcRequest, { backend, toolBridge });
  });
  port.on('close', () => {
    alive = false;
  });
  port.start();
  parentPort.postMessage({ ready: true });
});
