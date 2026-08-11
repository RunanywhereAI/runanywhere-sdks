// preload.ts — runs in the RENDERER's isolated preload context. Receives the
// MessagePort brokered by RunAnywhereMain, speaks the RPC protocol to the utility
// host, and exposes a safe `window.runanywhere` API via contextBridge (no direct
// port access leaks into the page). Runs with sandbox:false (it requires SDK
// modules). What it publishes is the v3 facade built over `RpcBackend`, plus the
// renderer-side DSP helpers and the app's staged catalog; SDK lifecycle events
// reach the page through `runanywhere.models`/`llm` streams rather than a second
// event bus.
import { contextBridge, ipcRenderer } from 'electron';

import { downsample, pcm16Bytes, rms } from '../audio';
import { createRunAnywhere } from '../api/facade';
import { Environment } from '../api/types';
import { RpcBackend } from '../api/rpc-backend';
import { catalogEntries } from '../catalog';
import { SDKException, asSDKException } from '../errors';
import type { RpcMessage } from './rpc';

type Pending = {
  resolve: (v: unknown) => void;
  reject: (e: Error) => void;
  onToken?: (t: unknown) => unknown;
};

let port: MessagePort | null = null;
let nextId = 1;
const pending = new Map<number, Pending>();
let ready: Promise<void>;
let markReady: () => void;
// (Re)create the ready gate so a fresh port (initial connect OR a reconnect after
// a host crash) re-enables send().
function armReady(): void {
  ready = new Promise<void>((r) => {
    markReady = r;
  });
}
armReady();

// Reject every in-flight request — used when the utility host dies, so awaiting
// loadLLM/generate calls settle with a clear error instead of hanging forever.
function rejectAllPending(err: Error): void {
  for (const [, p] of pending) p.reject(err);
  pending.clear();
}

// The args of the last successful initialize(), replayed onto a REPLACEMENT host.
// The native addon's initialised state is per-process, so a re-forked host starts
// uninitialised: without this, one host crash leaves the app alive but every
// feature failing "not initialized" until the user restarts it.
let initArgs: { secureDir?: string; baseDir?: string; cp?: ControlPlaneOptions } | null = null;
let sawFirstPort = false;

ipcRenderer.on('runanywhere-port', (event) => {
  const isReplacement = sawFirstPort;
  sawFirstPort = true;
  port = event.ports[0];
  port.onmessage = (ev: MessageEvent) => {
    const m = ev.data as RpcMessage;
    const p = pending.get(m.id);
    if (!p) return;
    if ('token' in m) {
      p.onToken?.(m.token);
      return;
    }
    // A duplex call: the host is parked inside native code until this answers,
    // so both outcomes have to post something back.
    if ('call' in m) {
      const { seq, event } = m.call;
      Promise.resolve(p.onToken?.(event))
        .then((result) => port?.postMessage({ id: m.id, seq, ok: true, result }))
        .catch((e: unknown) =>
          port?.postMessage({
            id: m.id,
            seq,
            ok: false,
            error: e instanceof Error ? e.message : String(e),
          })
        );
      return;
    }
    pending.delete(m.id);
    if ('done' in m) p.resolve((m as { result?: unknown }).result);
    else if (m.ok) p.resolve(m.result);
    else p.reject(asSDKException(m.error));
  };
  port.onmessageerror = () => { /* ignore an undeserializable message rather than wedge the port */ };
  port.start();
  if (isReplacement && initArgs) {
    // Re-initialise BEFORE opening the gate, so calls queued behind `ready` do not
    // race the init and fail. If it fails there is nothing further we can do here;
    // the next call surfaces the error.
    const { secureDir, baseDir, cp } = initArgs;
    new Promise<void>((resolve, reject) => {
      const id = nextId++;
      pending.set(id, { resolve: () => resolve(), reject });
      port!.postMessage({ id, method: 'initialize', args: [secureDir, baseDir] });
    })
      // The fresh host has no tokens, so re-run the HTTP setup on it. The v3
      // facade is already `ready`, which is why this is a retry rather than a
      // second initialize.
      .then(() => (cp ? v3.auth.retry().then(() => undefined) : undefined))
      .catch(() => { /* surfaced by the caller's next request */ })
      .finally(() => markReady());
    return;
  }
  markReady();
});

// The main process reports when the utility host exits (crash or kill). Fail all
// outstanding calls and re-arm the gate so a subsequent connect() recovers.
ipcRenderer.on('runanywhere-host-exited', (_e, code?: number) => {
  port = null;
  armReady();
  rejectAllPending(
    SDKException.unknown(
      `inference host exited unexpectedly (code ${code ?? 'unknown'}) — retrying`
    )
  );
});

function send(method: string, args: unknown[], onToken?: (t: unknown) => unknown): Promise<unknown> {
  return ready.then(
    () =>
      new Promise((resolve, reject) => {
        const id = nextId++;
        pending.set(id, { resolve, reject, onToken });
        port!.postMessage({ id, method, args });
      })
  );
}

/** Control-plane credentials for {@link initialize}. */
type ControlPlaneOptions = { apiKey?: string; baseUrl?: string; environment?: string };

// The v3 surface, built over the same utility host the verbs below talk to.
// `RpcBackend` forwards each call as `v3.<op>`, so the renderer gets the exact
// namespaces the main process has without a second implementation. Everything
// it returns is contextBridge-safe (see iter.ts's bridgeStream).
const v3 = createRunAnywhere(new RpcBackend((method, args, onChunk) => send(method, args, onChunk)));

contextBridge.exposeInMainWorld('runanywhere', {
  ready: (): Promise<void> => ready,

  // ---- v3 namespaces ----
  // The same fourteen the main process gets, from the same `createRunAnywhere`,
  // so page code and Node code are written once against one shape.
  llm: v3.llm,
  vlm: v3.vlm,
  stt: v3.stt,
  tts: v3.tts,
  vad: v3.vad,
  embeddings: v3.embeddings,
  rerank: v3.rerank,
  images: v3.images,
  diarization: v3.diarization,
  segmentation: v3.segmentation,
  voice: v3.voice,
  rag: v3.rag,
  models: v3.models,
  lora: v3.lora,
  // Electron platform extras.
  secure: v3.secure,
  auth: v3.auth,
  telemetry: v3.telemetry,
  // Input constructors: a renderer cannot `require` the package, so carrying
  // these is what lets page code build the same AudioInput / ImageInput /
  // RagDocument values main-process code builds.
  audio: v3.audio,
  image: v3.image,
  ragDocument: v3.ragDocument,

  capabilities: () => v3.capabilities(),
  reset: () => v3.reset(),
  // A function rather than the facade's `version` getter: contextBridge clones
  // what it publishes, and a getter would be read once at expose time — before
  // initialize() has anything to report.
  version: () => send('version', []),
  initialize: (secureDir?: string, baseDir?: string, controlPlane?: ControlPlaneOptions) =>
    v3
      .initialize({
        secureDir,
        baseDir,
        apiKey: controlPlane?.apiKey,
        baseUrl: controlPlane?.baseUrl,
        environment:
          (controlPlane?.environment ?? 'production') === 'production'
            ? Environment.PRODUCTION
            : Environment.DEVELOPMENT,
      })
      .then(() => {
        // Remembered so a re-forked host is initialised automatically (see above).
        initArgs = { secureDir, baseDir, cp: controlPlane };
      }),

  // ---- audio helpers (commons DSP via utility-host RPC) ----
  // Rate conversion + PCM16 packing for the mic -> STT path. Commons owns the
  // math; these forward typed arrays over the same MessagePort as v3.* — never
  // by loading runanywhere_native.node in the preload/renderer.
  downsample: (samples: Float32Array, inRate: number, outRate: number) =>
    downsample(samples, inRate, outRate),
  pcm16Bytes: (samples: Float32Array) => pcm16Bytes(samples),
  rms: (samples: Float32Array) => rms(samples),

  // The app's own staged table, read back for the display metadata commons has
  // no field for: a friendly label, a licence link, a parameter count, and the
  // "heavy" warning. Everything about a model's STATE — downloaded, size on
  // disk, resident — comes from `models` above.
  catalog: () => catalogEntries(),
});

// Test-only hook (kept off the SDK surface) so the example app can signal the
// main process when the headless run finishes.
contextBridge.exposeInMainWorld('runanywhereTest', {
  done: (ok: boolean) => ipcRenderer.send('runanywhere-test-done', ok),
  log: (line: string) => ipcRenderer.send('runanywhere-test-log', line),
});
