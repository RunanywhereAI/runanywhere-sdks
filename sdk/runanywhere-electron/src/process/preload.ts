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
import type { JsonSchema } from '../grammar';
import { toolCallSchema, toolCallPrompt, parseStructured } from '../structured';
import type { ToolSpec } from '../structured';
import { toAsyncIterable, streamWithMetrics } from '../stream';
import type { LLMStreamEvent } from '../stream';
import { bus } from '../events';
import type { EventListener, Modality } from '../events';
import { CATALOG } from '../catalog';
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
    else p.reject(new Error(m.error));
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
  rejectAllPending(new Error(`inference host exited unexpectedly (code ${code ?? 'unknown'}) — retrying`));
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

contextBridge.exposeInMainWorld('runanywhere', {
  ready: (): Promise<void> => ready,
  version: () => send('version', []),
  initialize: (secureDir?: string, baseDir?: string) =>
    emitAfter(send('initialize', [secureDir, baseDir]), () => bus.emit({ type: 'initialized' })),

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
    if (!tools || !tools.length) throw new Error('generateToolCall: at least one tool is required');
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
