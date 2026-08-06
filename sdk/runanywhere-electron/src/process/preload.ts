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
import { speakableText } from '../speech';
import { formatChat } from '../chat-template';
import type { ChatTemplate, ChatTurn, FormatOptions } from '../chat-template';
import { downsample, pcm16Bytes, rms } from '../audio';
import {
  RAGConfiguration,
  RAGDocument,
  RAGQueryOptions,
  RAGResult,
  RAGStatistics,
} from '../proto/rag';
import { SDKEnvironment } from '../proto/model_types';
import {
  SdkInitPhase1Request,
  SdkInitPhase2Request,
} from '../proto/sdk_init';
import { createRagSessionFromCatalog } from '../rag';
import type { RagConfig, RagDoc, RagQuery, RagResult, RagStats } from '../rag';
import type { JsonSchema } from '../grammar';
import { toolCallSchema, toolCallPrompt, parseStructured } from '../structured';
import type { ToolSpec } from '../structured';
import { toAsyncIterable, streamWithMetrics } from '../stream';
import type { LLMStreamEvent } from '../stream';
import { bus } from '../events';
import type { EventListener, Modality } from '../events';
import { catalogEntries } from '../catalog';
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
      .then(() => runControlPlane(cp)) // re-run auth + telemetry on the fresh host
      .then(() => bus.emit({ type: 'initialized' }))
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

/** Control-plane credentials for {@link initialize}. */
type ControlPlaneOptions = { apiKey?: string; baseUrl?: string; environment?: string };

/** The host OS as the backend's platform enum (macos/linux/windows) — the binding
 * ("electron") is reported separately as sdk_binding. */
function osPlatform(): string {
  if (process.platform === 'darwin') return 'macos';
  if (process.platform === 'win32') return 'windows';
  return 'linux';
}

/** Run the desktop two-phase init (telemetry + auth) over the host's v3 RPCs.
 * Best-effort: HTTP/auth failures are non-fatal and never block local inference. */
async function runControlPlane(cp?: ControlPlaneOptions): Promise<void> {
  if (!cp) return;
  const apiKey = (cp.apiKey ?? '').trim();
  let baseUrl = (cp.baseUrl ?? '').trim();
  if (!apiKey && !baseUrl) return;
  const isProd = (cp.environment ?? 'production') === 'production';
  try {
    const has = (await send('v3.hasControlPlane', [])) as boolean;
    if (!has) {
      // eslint-disable-next-line no-console
      console.warn(
        'RunAnywhere.initialize: apiKey/baseUrl supplied but this build has no desktop ' +
          'control plane (RAC_DESKTOP_ADAPTER=OFF) — no auth or telemetry'
      );
      return;
    }
    if (!baseUrl && !isProd) baseUrl = (await send('v3.devStagingBaseUrl', [])) as string;
    if (!baseUrl || (isProd && !apiKey)) return;
    const deviceId = (await send('v3.devicePersistentId', [])) as string;
    const version = (await send('version', [])) as string;
    const platform = osPlatform();
    const protoEnv = isProd
      ? SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION
      : SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
    const phase1Bytes = SdkInitPhase1Request.encode({
      environment: protoEnv,
      apiKey,
      baseUrl,
      deviceId,
      platform,
      sdkVersion: version,
    }).finish();
    const phase2Bytes = SdkInitPhase2Request.encode({
      buildToken: '',
    }).finish();
    await send('v3.configureControlPlane', [
      {
        environment: isProd ? 2 : 0,
        apiKey,
        baseUrl,
        deviceId,
        platform,
        sdkVersion: version,
        sdkBinding: 'electron',
        appIdentifier: 'ai.runanywhere.electron',
        appName: 'RunAnywhere Electron',
        appVersion: version,
        phase1Bytes,
        phase2Bytes,
      },
    ]);
  } catch {
    // telemetry/auth failure must not block local inference
  }
}

contextBridge.exposeInMainWorld('runanywhere', {
  ready: (): Promise<void> => ready,
  version: () => send('version', []),
  initialize: (secureDir?: string, baseDir?: string, controlPlane?: ControlPlaneOptions) =>
    emitAfter(
      // Base bring-up first, then the desktop control plane (auth + telemetry).
      send('initialize', [secureDir, baseDir]).then(() => runControlPlane(controlPlane)),
      () => {
        // Remembered so a re-forked host is initialised automatically (see above).
        initArgs = { secureDir, baseDir, cp: controlPlane };
        bus.emit({ type: 'initialized' });
      }
    ),

  // ---- lifecycle + telemetry events (local bus, driven by these wrappers) ----
  onEvent: (listener: EventListener) => bus.on(listener),

  // ---- audio helpers (pure DSP; renderer-side, no RPC) ----
  // Anti-aliased rate conversion + PCM16 packing for the mic -> STT path. Doing
  // this by hand in an app folds >8kHz energy into the band Whisper reads.
  downsample: (samples: Float32Array, inRate: number, outRate: number) => downsample(samples, inRate, outRate),
  pcm16Bytes: (samples: Float32Array) => pcm16Bytes(samples),
  rms: (samples: Float32Array) => rms(samples),

  // ---- reasoning ----
  // Split a reasoning model's <think>…</think> from its answer (pure, in-page).
  splitThinking: (text: string) => splitThinking(text),
  // Markdown/symbols -> words a TTS voice can read (no "asterisk asterisk").
  speakableText: (text: string) => speakableText(text),
  // Render a conversation in the markup the model was trained on. Without this a
  // multi-turn chat collapses into a single user turn and the model "forgets".
  formatChat: (turns: ChatTurn[], template?: ChatTemplate, opts?: FormatOptions) => formatChat(turns, template, opts),

  // ---- model catalog + storage ----
  catalog: () => catalogEntries(),
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
    optionsOrOnToken: Record<string, unknown> | ((t: string) => void),
    onToken?: (t: string) => void
  ) =>
    typeof optionsOrOnToken === 'function'
      ? send('generate', [handle, prompt], optionsOrOnToken as (t: unknown) => void)
      : send('generate', [handle, prompt, optionsOrOnToken], onToken as (t: unknown) => void),
  // Stream generation as events with metrics (token per event; final event
  // carries the aggregated result and fires a 'generation' telemetry event).
  generateStream: async (
    handle: number,
    prompt: string,
    options: Record<string, unknown>,
    onEvent: (e: LLMStreamEvent) => void
  ): Promise<void> => {
    const source = toAsyncIterable((onToken) =>
      send('generate', [handle, prompt, options], onToken as (t: unknown) => void) as Promise<void>
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
    options: Record<string, unknown> = {}
  ): Promise<unknown> => {
    const grammar = jsonSchemaToGrammar(schema);
    let out = '';
    await send('generate', [handle, prompt, { ...options, grammar }], (t) => {
      out += t as string;
    });
    return parseStructured(out, 'generateStructured');
  },
  /** @deprecated Use generateStructured. */
  generateObject: async (
    handle: number,
    prompt: string,
    schema: JsonSchema,
    options: Record<string, unknown> = {}
  ): Promise<unknown> => {
    const grammar = jsonSchemaToGrammar(schema);
    let out = '';
    await send('generate', [handle, prompt, { ...options, grammar }], (t) => {
      out += t as string;
    });
    return parseStructured(out, 'generateStructured');
  },
  generateToolCall: async (
    handle: number,
    prompt: string,
    tools: ToolSpec[],
    options: Record<string, unknown> = {}
  ): Promise<unknown> => {
    if (!tools || !tools.length) {
      throw SDKException.validationFailed({
        fieldPath: 'tools',
        message: 'at least one tool is required',
      });
    }
    const grammar = jsonSchemaToGrammar(toolCallSchema(tools));
    let out = '';
    await send('generate', [handle, toolCallPrompt(prompt, tools), { ...options, grammar }], (t) => {
      out += t as string;
    });
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
    const bytes = RAGQueryOptions.encode(
      RAGQueryOptions.fromPartial({
        query: query.query,
        generation: query.generation,
        retrieval: {
          topK: query.retrievalTopK,
          scoreThreshold: query.scoreThreshold,
        },
      })
    ).finish();
    const raw = RAGResult.decode((await send('ragQuery', [handle, bytes])) as Uint8Array);
    // RAGResult dropped total_time_ms (deleted from idl/rag.proto); derive it —
    // retrieval + generation is the whole of what the pipeline measures per-call.
    return {
      ...raw,
      totalTimeMs: raw.retrievalTimeMs + raw.generationTimeMs,
    } as RagResult;
  },
  ragStats: async (handle: number): Promise<RagStats> =>
    RAGStatistics.decode((await send('ragStats', [handle])) as Uint8Array) as RagStats,
  ragClear: async (handle: number): Promise<RagStats> =>
    RAGStatistics.decode((await send('ragClear', [handle])) as Uint8Array) as RagStats,
  ragDestroySession: (handle: number): Promise<void> => send('ragDestroySession', [handle]) as Promise<void>,

  secureSet: (key: string, value: string) => send('secureSet', [key, value]),
  secureGet: (key: string) => send('secureGet', [key]),
  secureDelete: (key: string) => send('secureDelete', [key]),

  createVad: (threshold?: number) => send('createVad', [threshold]),
  vadProcess: (handle: number, samples: Float32Array) => send('vadProcess', [handle, samples]),
  vadIsActive: (handle: number) => send('vadIsActive', [handle]),
  vadSetThreshold: (handle: number, threshold: number) => send('vadSetThreshold', [handle, threshold]),
  vadReset: (handle: number) => send('vadReset', [handle]),
  unloadVad: (handle: number) => send('unloadVad', [handle]),

  shutdown: () => send('shutdown', []),
});

// Test-only hook (kept off the SDK surface) so the example app can signal the
// main process when the headless run finishes.
contextBridge.exposeInMainWorld('runanywhereTest', {
  done: (ok: boolean) => ipcRenderer.send('runanywhere-test-done', ok),
  log: (line: string) => ipcRenderer.send('runanywhere-test-log', line),
});
