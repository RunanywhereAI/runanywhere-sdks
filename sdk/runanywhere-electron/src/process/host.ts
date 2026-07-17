// host.ts — entry point for the Electron utilityProcess that owns the native
// addon. Loads the .node once, then serves RPC requests from one or more
// renderer-connected MessagePorts (each delivered by RunAnywhereMain). Heavy
// inference runs here, isolated from the main + renderer processes. The request
// routing itself lives in dispatch.ts (pure + unit-tested); this file only wires
// the real addon + model resolver into it and manages the parent port.
import { addon } from '../bridge';
import { isCatalogId } from '../catalog';
import { resolveModel } from '../download';
import { dispatch } from './dispatch';
import { RpcRequest } from './rpc';

// If a load method's first arg is a catalog id, download+resolve it (in the
// utility process, which owns Node I/O) before handing paths to the addon.
async function resolveLoadArgs(method: string, args: unknown[]): Promise<unknown[]> {
  const first = args[0];
  if (typeof first !== 'string' || !isCatalogId(first)) return args;
  const m = await resolveModel(first);
  if (method === 'loadVlmModel') return [m.primary, m.mmproj ?? args[1], ...args.slice(2)];
  return [m.primary, ...args.slice(1)];
}

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

// Route addon methods to the native addon (bound so `this` is the addon), plus
// a host-owned `downloadModel` that runs in this utility process (keeping the
// renderer responsive); its onProgress is the injected stream callback.
const addonMap = addon as unknown as Record<string, (...a: unknown[]) => unknown>;
const api = new Proxy(addonMap, {
  get(target, prop: string) {
    if (prop === 'downloadModel') {
      return (idOrPath: unknown, onProgress: unknown) =>
        resolveModel(idOrPath as string, { onProgress: onProgress as (p: unknown) => void });
    }
    const value = target[prop];
    return typeof value === 'function' ? value.bind(target) : value;
  },
}) as Record<string, (...a: unknown[]) => unknown>;

const deps = {
  api,
  getVersion: () => addon.version,
  resolveLoadArgs,
};

parentPort.on('message', (e) => {
  const port = e.ports[0];
  if (!port) return;
  port.on('message', (ev) => dispatch(port, ev.data as RpcRequest, deps));
  port.start();
  parentPort.postMessage({ ready: true });
});
