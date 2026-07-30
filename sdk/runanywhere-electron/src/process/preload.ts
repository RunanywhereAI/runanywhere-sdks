// preload.ts — runs in the RENDERER's isolated preload context. Receives the
// MessagePort brokered by RunAnywhereMain, speaks the RPC protocol to the utility
// host, and exposes a safe `window.runanywhere` API via contextBridge (no direct
// port access leaks into the page). Streaming methods take a callback that
// contextBridge proxies back to the page. Runs with sandbox:false (it requires
// SDK modules); a local event bus mirrors the facade's lifecycle/telemetry events
// so a renderer can subscribe without the Node facade.
import { contextBridge, ipcRenderer } from 'electron';

import { jsonSchemaToGrammar } from '../grammar';
import { splitThinking } from '../thinking';
import {
  RAGConfiguration,
  RAGDocument,
  RAGQueryOptions,
  RAGResult,
  RAGStatistics,
} from '../proto/rag';
import { createRagSessionFromCatalog } from '../rag';
import type { RagConfig, RagDoc, RagQuery, RagResult, RagStats } from '../rag';
import type { JsonSchema } from '../grammar';
import { toolCallSchema, toolCallPrompt, parseStructured } from '../structured';
import type { ToolSpec } from '../structured';
import { toNativeGenerateOptions } from '../legacy-options';
import type { GenerateOptions } from '../legacy-options';
import { createRunAnywhere } from '../api/facade';
import { RpcBackend } from '../api/rpc-backend';
import { toAsyncIterable, streamWithMetrics } from '../stream';
import type { LLMStreamEvent } from '../stream';
import { bus } from '../events';
import type { EventListener, Modality } from '../events';
import { CATALOG } from '../catalog';
import { SDKException, asSDKException } from '../errors';
import type { RpcMessage } from './rpc';

type Pending = {
  resolve: (v: unknown) => void;
  reject: (e: Error) => void;
  onToken?: (t: unknown) => void;
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

ipcRenderer.on('runanywhere-port', (event) => {
  port = event.ports[0];
  port.onmessage = (ev: MessageEvent) => {
    const m = ev.data as RpcMessage;
    const p = pending.get(m.id);
    if (!p) return;
    if ('token' in m) {
      p.onToken?.(m.token);
      return;
    }
    pending.delete(m.id);
    if ('done' in m) p.resolve((m as { result?: unknown }).result);
    else if (m.ok) p.resolve(m.result);
    else p.reject(asSDKException(m.error));
  };
  port.onmessageerror = () => { /* ignore an undeserializable message rather than wedge the port */ };
  port.start();
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

function send(method: string, args: unknown[], onToken?: (t: unknown) => void): Promise<unknown> {
  return ready.then(
    () =>
      new Promise((resolve, reject) => {
        const id = nextId++;
        pending.set(id, { resolve, reject, onToken });
        port!.postMessage({ id, method, args });
      })
  );
}

// Emit a lifecycle event after `p` resolves (fire-and-forget), then pass through.
function emitAfter<T>(p: Promise<T>, event: () => void): Promise<T> {
  return p.then((v) => {
    event();
    return v;
  });
}

// The v3 surface, built from the same factory the main process uses. Every stream
// it returns is a plain self-iterating object (see api/iter.ts), which is what lets
// contextBridge carry AsyncIterables and sessions into the page intact.
const v3 = createRunAnywhere(new RpcBackend(send));

// contextBridge copies values and proxies functions, but it does not proxy
// accessors, and the object it hands the page is frozen: a getter is invoked once
// during the clone, and the page can neither redefine nor add a property
// afterwards. So `isReady`/`version`/`deviceId`/`environment`/`events` are read
// through these two proxied functions, and buildMainWorldApi() assembles the real
// `window.runanywhere` in the page from them — which is how the renderer ends up
// with the same live shape as the main-process facade.
const readCoreState = (): {
  isReady: boolean;
  version: string;
  deviceId: string;
  environment: string;
} => ({
  isReady: v3.isReady,
  version: v3.version,
  deviceId: v3.deviceId,
  environment: v3.environment,
});

const surface = {
  // ---- v3 core ----
  /**
   * Bring the SDK up. The pre-v3 positional form `initialize(secureDir, baseDir)`
   * is still accepted and folds into the options object.
   */
  initialize: (
    optionsOrSecureDir?: Parameters<typeof v3.initialize>[0] | string,
    baseDir?: string
  ): Promise<void> =>
    typeof optionsOrSecureDir === 'string' || typeof baseDir === 'string'
      ? v3.initialize({ secureDir: optionsOrSecureDir as string | undefined, baseDir })
      : v3.initialize(optionsOrSecureDir),
  reset: () => v3.reset(),

  // isReady / version / deviceId / environment / events are deliberately absent
  // here: contextBridge would clone them as non-configurable data properties
  // frozen at clone time. buildMainWorldApi() adds them as live accessors.

  // Internal plumbing for buildMainWorldApi(); not part of the public surface.
  __coreState: readCoreState,
  __events: () => v3.events,

  // ---- v3 namespaces ----
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
  secure: v3.secure,
  audio: v3.audio,
  image: v3.image,
  ragDocument: v3.ragDocument,

  // ---- deprecated (pre-v3), kept for one release ----
  ready: (): Promise<void> => ready,
  /** @deprecated Read the `version` property; initialize() populates it. */
  versionAsync: () => send('version', []),

  // ---- lifecycle + telemetry events (local bus, driven by these wrappers) ----
  onEvent: (listener: EventListener) => bus.on(listener),

  // ---- reasoning ----
  // Split a reasoning model's <think>…</think> from its answer (pure, in-page).
  splitThinking: (text: string) => splitThinking(text),

  // ---- model catalog + storage ----
  catalog: () => CATALOG,
  // modelStatus/exists run their fs work in the utility host (off the renderer
  // thread), so both are async RPCs.
  modelStatus: () => send('modelStatus', []),
  exists: (p: string) => send('exists', [p]),
  // Download a catalog model (runs in the utility host so the renderer stays
  // responsive); onProgress receives { file, received, total, percent }.
  downloadModel: (idOrPath: string, onProgress?: (p: unknown) => void) =>
    send('downloadModel', [idOrPath], onProgress),

  loadLLM: (modelPath: string) =>
    emitAfter(send('loadModel', [modelPath]), () => bus.emit({ type: 'modelLoaded', modality: 'llm', id: modelPath })),
  generate: (
    handle: number,
    prompt: string,
    optionsOrOnToken: GenerateOptions | ((t: string) => void),
    onToken?: (t: string) => void
  ) =>
    typeof optionsOrOnToken === 'function'
      ? send('generate', [handle, prompt], optionsOrOnToken as (t: unknown) => void)
      : send(
          'generate',
          [handle, prompt, toNativeGenerateOptions(optionsOrOnToken)],
          onToken as (t: unknown) => void
        ),
  // Stream generation as events with metrics (token per event; final event
  // carries the aggregated result and fires a 'generation' telemetry event).
  generateStream: async (
    handle: number,
    prompt: string,
    options: GenerateOptions,
    onEvent: (e: LLMStreamEvent) => void
  ): Promise<void> => {
    const native = toNativeGenerateOptions(options);
    const source = toAsyncIterable((onToken) =>
      send('generate', [handle, prompt, native], onToken as (t: unknown) => void) as Promise<void>
    );
    for await (const event of streamWithMetrics(source)) {
      if (event.isFinal && event.result) bus.emit({ type: 'generation', result: event.result });
      onEvent(event);
    }
  },
  generateStructured: async (
    handle: number,
    prompt: string,
    schema: JsonSchema,
    options: GenerateOptions = {}
  ): Promise<unknown> => {
    const grammar = jsonSchemaToGrammar(schema);
    let out = '';
    await send('generate', [handle, prompt, toNativeGenerateOptions({ ...options, grammar })], (t) => {
      out += t as string;
    });
    return parseStructured(out, 'generateStructured');
  },
  /** @deprecated Use generateStructured. */
  generateObject: async (
    handle: number,
    prompt: string,
    schema: JsonSchema,
    options: GenerateOptions = {}
  ): Promise<unknown> => {
    const grammar = jsonSchemaToGrammar(schema);
    let out = '';
    await send('generate', [handle, prompt, toNativeGenerateOptions({ ...options, grammar })], (t) => {
      out += t as string;
    });
    return parseStructured(out, 'generateStructured');
  },
  generateToolCall: async (
    handle: number,
    prompt: string,
    tools: ToolSpec[],
    options: GenerateOptions = {}
  ): Promise<unknown> => {
    if (!tools || !tools.length) {
      throw SDKException.validationFailed({
        fieldPath: 'tools',
        message: 'at least one tool is required',
      });
    }
    const grammar = jsonSchemaToGrammar(toolCallSchema(tools));
    let out = '';
    await send(
      'generate',
      [handle, toolCallPrompt(prompt, tools), toNativeGenerateOptions({ ...options, grammar })],
      (t) => {
        out += t as string;
      }
    );
    return parseStructured(out, 'generateToolCall');
  },
  unloadLLM: (handle: number) =>
    emitAfter(send('unloadModel', [handle]), () => bus.emit({ type: 'modelUnloaded', modality: 'llm' })),

  loadVLM: (modelPath: string, mmprojPath: string) =>
    emitAfter(send('loadVlmModel', [modelPath, mmprojPath]), () => bus.emit({ type: 'modelLoaded', modality: 'vlm', id: modelPath })),
  generateVlm: (handle: number, imagePath: string, prompt: string, onToken: (t: string) => void) =>
    send('generateVlm', [handle, imagePath, prompt], onToken as (t: unknown) => void),
  unloadVLM: (handle: number) =>
    emitAfter(send('unloadVlmModel', [handle]), () => bus.emit({ type: 'modelUnloaded', modality: 'vlm' })),

  loadEmbedder: (modelPath: string) =>
    emitAfter(send('loadEmbeddingModel', [modelPath]), () => bus.emit({ type: 'modelLoaded', modality: 'embedder', id: modelPath })),
  embed: (handle: number, text: string) => send('embed', [handle, text]),
  unloadEmbedder: (handle: number) =>
    emitAfter(send('unloadEmbeddingModel', [handle]), () => bus.emit({ type: 'modelUnloaded', modality: 'embedder' })),

  loadSTT: (modelDir: string) =>
    emitAfter(send('loadSttModel', [modelDir]), () => bus.emit({ type: 'modelLoaded', modality: 'stt', id: modelDir })),
  transcribe: (handle: number, pcm16: Uint8Array) => send('transcribe', [handle, pcm16]),
  unloadSTT: (handle: number) =>
    emitAfter(send('unloadSttModel', [handle]), () => bus.emit({ type: 'modelUnloaded', modality: 'stt' })),

  loadTTS: (voiceDir: string) =>
    emitAfter(send('loadTtsVoice', [voiceDir]), () => bus.emit({ type: 'modelLoaded', modality: 'tts', id: voiceDir })),
  synthesize: (handle: number, text: string) => send('synthesize', [handle, text]),
  unloadTTS: (handle: number) =>
    emitAfter(send('unloadTtsVoice', [handle]), () => bus.emit({ type: 'modelUnloaded', modality: 'tts' as Modality })),

  // Register a downloaded model (id -> local path) in commons' global registry so
  // RAG can resolve embedding/LLM ids. Prefer ragCreateSessionFromCatalog from
  // apps — it owns category/framework selection. Low-level escape hatch only.
  registerModel: (id: string, localPath: string, category?: number, framework?: number) =>
    send('registerModel', [id, localPath, category, framework]),

  // ---- RAG (retrieval-augmented generation) ----
  // Object-in / object-out: we encode the runanywhere.v1 proto messages here and
  // pass raw bytes over the RPC; commons returns serialized RAGResult/RAGStatistics
  // which we decode back. The addon (utility host) is a generic proto-byte pass-through.
  ragCreateSession: (config: RagConfig): Promise<number> =>
    send('ragCreateSession', [RAGConfiguration.encode(RAGConfiguration.fromPartial(config)).finish()]) as Promise<number>,
  // Download catalog models, register them, and open a session — single entry
  // point for apps (no raw registry enum ints / multi-step bootstrap in the UI).
  ragCreateSessionFromCatalog: (config: RagConfig): Promise<number> =>
    createRagSessionFromCatalog(
      {
        downloadModel: (idOrPath) =>
          send('downloadModel', [idOrPath]) as Promise<{ id: string; primary: string }>,
        registerModel: (id, localPath, category, framework) =>
          send('registerModel', [id, localPath, category, framework]),
        ragCreateSession: (cfg) =>
          send('ragCreateSession', [
            RAGConfiguration.encode(RAGConfiguration.fromPartial(cfg)).finish(),
          ]) as Promise<number>,
      },
      config,
    ),
  ragIngest: async (handle: number, doc: RagDoc): Promise<RagStats> => {
    const bytes = RAGDocument.encode(RAGDocument.fromPartial(doc)).finish();
    // send() already resolves a Uint8Array (a Buffer degrades to one across the
    // MessagePort) and decode() accepts it directly — no re-wrap/copy needed.
    return RAGStatistics.decode((await send('ragIngest', [handle, bytes])) as Uint8Array) as RagStats;
  },
  ragQuery: async (handle: number, query: RagQuery): Promise<RagResult> => {
    const bytes = RAGQueryOptions.encode(RAGQueryOptions.fromPartial(query)).finish();
    return RAGResult.decode((await send('ragQuery', [handle, bytes])) as Uint8Array) as RagResult;
  },
  ragStats: async (handle: number): Promise<RagStats> =>
    RAGStatistics.decode((await send('ragStats', [handle])) as Uint8Array) as RagStats,
  ragClear: async (handle: number): Promise<RagStats> =>
    RAGStatistics.decode((await send('ragClear', [handle])) as Uint8Array) as RagStats,
  ragDestroySession: (handle: number): Promise<void> => send('ragDestroySession', [handle]) as Promise<void>,

  secureSet: (key: string, value: string) => send('secureSet', [key, value]),
  secureGet: (key: string) => send('secureGet', [key]),
  secureDelete: (key: string) => send('secureDelete', [key]),

  createVad: (activationThreshold?: number) => send('createVad', [activationThreshold]),
  vadProcess: (handle: number, samples: Float32Array) => send('vadProcess', [handle, samples]),
  vadIsActive: (handle: number) => send('vadIsActive', [handle]),
  vadSetThreshold: (handle: number, threshold: number) => send('vadSetThreshold', [handle, threshold]),
  vadReset: (handle: number) => send('vadReset', [handle]),
  unloadVad: (handle: number) => send('unloadVad', [handle]),

  shutdown: () => send('shutdown', []),
};

/** The page-side property names that must be live rather than cloned. */
const LIVE_KEYS = ['isReady', 'version', 'deviceId', 'environment'];

/**
 * Assemble `window.runanywhere` inside the page from the bridged surface, adding
 * the live core-state accessors. Runs in the main world (so the object is the
 * page's own and therefore extensible) and returns false when this Electron build
 * has no `executeInMainWorld`.
 */
function buildMainWorldApi(): boolean {
  const bridge = contextBridge as unknown as {
    executeInMainWorld?: (script: { func: (...a: unknown[]) => unknown; args?: unknown[] }) => unknown;
  };
  if (typeof bridge.executeInMainWorld !== 'function') return false;
  contextBridge.exposeInMainWorld('__runanywhereBridge', surface);
  try {
    return (
      bridge.executeInMainWorld({
        // Serialized into the page: no closures, no imports — read everything off
        // the bridged object.
        func: (...a: unknown[]) => {
          const liveKeys = a[0] as string[];
          const w = globalThis as unknown as Record<string, unknown>;
          const b = w.__runanywhereBridge as Record<string, unknown> | undefined;
          if (!b) return false;
          const api: Record<string, unknown> = {};
          for (const key of Object.keys(b)) {
            if (!key.startsWith('__')) api[key] = b[key];
          }
          const state = b.__coreState as () => Record<string, unknown>;
          for (const key of liveKeys) {
            Object.defineProperty(api, key, { get: () => state()[key], enumerable: true });
          }
          Object.defineProperty(api, 'events', {
            get: () => (b.__events as () => unknown)(),
            enumerable: true,
          });
          w.runanywhere = api;
          return true;
        },
        args: [LIVE_KEYS],
      }) === true
    );
  } catch {
    return false;
  }
}

// Fall back to exposing the bridged surface directly when the page-side assembly
// is unavailable. The verbs all work; the core-state properties are then frozen
// snapshots, so say that instead of letting a renderer believe the SDK never
// became ready.
if (!buildMainWorldApi()) {
  contextBridge.exposeInMainWorld('runanywhere', surface);
  console.warn(
    '[runanywhere] this Electron build cannot assemble window.runanywhere in the page: ' +
      'isReady/version/deviceId/environment/events are unavailable there. ' +
      'Call window.runanywhere.__coreState() or read them in the main process.'
  );
}

// Test-only hook (kept off the SDK surface) so the example app can signal the
// main process when the headless run finishes.
contextBridge.exposeInMainWorld('runanywhereTest', {
  done: (ok: boolean) => ipcRenderer.send('runanywhere-test-done', ok),
  log: (line: string) => ipcRenderer.send('runanywhere-test-log', line),
});
