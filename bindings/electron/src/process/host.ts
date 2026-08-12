// host.ts — entry point for the Electron utilityProcess that owns the native
// addon. Loads the .node once, then serves RPC requests from one or more
// renderer-connected MessagePorts (each delivered by RunAnywhereMain). Heavy
// inference runs here, isolated from the main + renderer processes. The request
// routing itself lives in dispatch.ts (pure + unit-tested); this file only wires
// the real addon + model resolver into it and manages the parent port.
import * as fs from 'fs';
import * as path from 'path';

import { NativeBackend } from '../api/native-backend';
import { addon } from '../bridge';
import { isCatalogId, registerCatalog } from '../catalog';
import { resolveModel, isRemoteSource, assertRemoteSupported, ModelKind, modelStatus, pathExists } from '../download';
import { dispatch, DuplexCalls } from './dispatch';
import { isCallReply, RpcRequest } from './rpc';

// Catalog registration is per process, and this is the process that resolves and
// downloads models. RunAnywhereMain passes the app's catalog module through
// RUNANYWHERE_CATALOG_PATH; without it a catalog id reaching the host is just an
// unknown string.
const catalogPath = process.env.RUNANYWHERE_CATALOG_PATH;
if (catalogPath) {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const staged = require(catalogPath) as { CATALOG?: Record<string, unknown> };
  if (staged?.CATALOG) registerCatalog(staged.CATALOG as never);
}

/**
 * Apply the main-process registration queue before any RPC (and before
 * initialize via the same env inside the addon). Fat builds skip — backends
 * are compile-linked. Thin builds hand EVERY queued path to `loadPlugin`.
 * Never accept plugin paths over RPC (security — no v3.registerBackendPlugin).
 *
 * A missing artifact is deliberately NOT pre-filtered here. Skipping it would
 * be the quietest possible failure: commons never sees the path, so it cannot
 * derive the backend name from the file stem
 * (`librunanywhere_sherpa.dylib` → `sherpa`) nor record
 * RAC_ERROR_PLUGIN_LOAD_FAILED against it — and `capabilities().unavailable`
 * then omits the very backend the app is missing. Letting the load fail costs
 * one caught rejection and buys a named ledger entry.
 *
 * NEVER REJECTS, and never stops early. Both properties are load-bearing:
 * `pluginsReady` gates every RPC below, so a rejection here used to make
 * `version()`, `capabilities()` and `models.list()` throw forever — commons
 * never even reached `rac_init`. That is one mis-built backend escalated into
 * a dead SDK, which is exactly what `@runanywhere/electron-sherpa` 0.20.17's
 * stub did. A backend that will not load is now recorded in commons'
 * unavailability ledger (visible via `capabilities().unavailable`) while every
 * other backend still registers and the SDK still initializes.
 */
async function applyPluginRegistrationQueue(): Promise<void> {
  if (!addon.thinAddon || typeof addon.loadPlugin !== 'function') return;
  const raw = process.env.RUNANYWHERE_PLUGIN_PATHS;
  if (!raw) return;
  for (const pluginPath of raw.split(path.delimiter).filter(Boolean)) {
    try {
      await addon.loadPlugin(pluginPath);
    } catch (err) {
      // Commons already recorded the reason against the backend's name; this
      // is the human-readable breadcrumb in the host log. `rac_result_t -820`
      // covers every dlopen failure, so say which kind it was — a path that is
      // simply not there is a staging bug, not a broken binary.
      const reason = err instanceof Error ? err.message : String(err);
      const detail = fs.existsSync(pluginPath) ? reason : `${reason}; file does not exist`;
      console.warn(
        `[runanywhere] backend plugin failed to register, continuing without it: ` +
          `${pluginPath} (${detail})`
      );
    }
  }
}

// Resolves once every plugin has had its turn — success or not. `.catch` is
// belt-and-braces: the loop above already swallows per-plugin failures, and
// this guarantees the RPC gate can never be a rejected promise even if a
// future edit throws outside the loop.
const pluginsReady: Promise<void> = applyPluginRegistrationQueue().catch((err: unknown) => {
  const reason = err instanceof Error ? err.message : String(err);
  console.warn(`[runanywhere] plugin registration queue failed: ${reason}`);
});

// Map each load method to its model kind so the shared remote-source guard
// (assertRemoteSupported) rejects a URL/HF STT/TTS/embedder consistently with the
// in-process facade. Catalog ids (archives) and local paths still work.
const METHOD_KIND: Record<string, ModelKind> = {
  loadModel: 'llm',
  loadVlmModel: 'vlm',
  loadEmbeddingModel: 'embedder',
  loadSttModel: 'stt',
  loadTtsVoice: 'tts',
};

// If a load method's first arg is a catalog id, a URL, or a HuggingFace repo,
// download+resolve it (in the utility process, which owns Node I/O) before
// handing concrete paths to the addon. A plain local path passes through.
async function resolveLoadArgs(method: string, args: unknown[]): Promise<unknown[]> {
  const first = args[0];
  if (typeof first !== 'string') return args;
  if (!isCatalogId(first) && !isRemoteSource(first)) return args;
  const kind = METHOD_KIND[method];
  if (kind) assertRemoteSupported(first, kind);
  const m = await resolveModel(first);
  if (method === 'loadVlmModel') {
    // A bare model URL has no mmproj to auto-resolve; forwarding `undefined` to
    // the addon (whose mmprojPath arg is a required string) yields an opaque
    // native error. Fail with a clear message instead. Catalog ids and HF repos
    // resolve their mmproj, so this only trips a direct-URL VLM source.
    const mmproj = m.mmproj ?? args[1];
    if (mmproj == null) {
      throw new Error(
        'vision models need an mmproj — load a VLM by catalog id or HuggingFace repo (auto-resolved) ' +
          'or pass an explicit mmproj path; a bare model URL has none'
      );
    }
    return [m.primary, mmproj, ...args.slice(2)];
  }
  return [m.primary, ...args.slice(1)];
}

// electron's utility-process ParentPort / MessagePortMain are loosely typed here
// so this file compiles without pulling electron's full type surface into the
// Node-facing SDK build.
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

// Route addon methods to the native addon (bound so `this` is the addon), plus
// a host-owned `downloadModel` that runs in this utility process (keeping the
// renderer responsive); its onProgress is the injected stream callback.
// The v3 surface's single source of native state. The renderer's RpcBackend
// forwards each `v3.<op>` call straight to a method on this instance, so every
// integer handle stays inside this process.
const v3Backend = new NativeBackend(addon) as unknown as Record<
  string,
  (...a: unknown[]) => unknown
>;

const addonMap = addon as unknown as Record<string, (...a: unknown[]) => unknown>;
const api = new Proxy(addonMap, {
  get(target, prop: string) {
    if (prop.startsWith('v3.')) {
      const op = prop.slice(3);
      const fn = v3Backend[op];
      return typeof fn === 'function' ? fn.bind(v3Backend) : undefined;
    }
    if (prop === 'downloadModel') {
      return (idOrPath: unknown, onProgress: unknown) =>
        resolveModel(idOrPath as string, { onProgress: onProgress as (p: unknown) => void });
    }
    // Host-owned filesystem queries (kept off the renderer thread).
    if (prop === 'modelStatus') return () => modelStatus();
    if (prop === 'exists') return (p: unknown) => pathExists(p as string);
    const value = target[prop];
    return typeof value === 'function' ? value.bind(target) : value;
  },
}) as Record<string, (...a: unknown[]) => unknown>;

// One per host: duplex replies are correlated by request id, and every port
// this process serves dispatches through the same registry.
const duplex = new DuplexCalls();

const deps = {
  api,
  getVersion: () => addon.version,
  resolveLoadArgs,
  duplex,
};

parentPort.on('message', (e) => {
  const port = e.ports[0];
  if (!port) return;
  // A renderer reload closes its old port; stop dispatching to the dead one so
  // in-flight work isn't posted into the void and the port can be released
  // (avoids a per-reload port leak in the utility process).
  let alive = true;
  port.on('message', (ev) => {
    if (!alive) return;
    if (isCallReply(ev.data)) {
      duplex.settle(ev.data);
      return;
    }
    // Gate every RPC on plugin preload so a thin addon never serves with a
    // half-populated registry. Fat builds no-op when RUNANYWHERE_PLUGIN_PATHS
    // is unset. `pluginsReady` cannot reject (see above), so this is a plain
    // sequencing barrier and not a failure channel — a backend that did not
    // load is reported through `capabilities().unavailable`, not by making
    // every unrelated RPC throw.
    void pluginsReady.then(() => {
      if (!alive) return;
      dispatch(port, ev.data as RpcRequest, deps);
    });
  });
  port.on('close', () => { alive = false; });
  port.start();
  parentPort.postMessage({ ready: true });
});
