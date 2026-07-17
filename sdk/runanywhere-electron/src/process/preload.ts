// preload.ts — runs in the RENDERER's isolated preload context. Receives the
// MessagePort brokered by RunAnywhereMain, speaks the RPC protocol to the utility
// host, and exposes a safe `window.runanywhere` API via contextBridge (no Node,
// no direct port access leaks into the page). Streaming methods take an onToken
// callback (contextBridge proxies it back to the page).
import { contextBridge, ipcRenderer } from 'electron';

import { jsonSchemaToGrammar } from '../grammar';
import type { JsonSchema } from '../grammar';
import { toolCallSchema, toolCallPrompt, parseStructured } from '../structured';
import type { ToolSpec } from '../structured';
import type { RpcMessage } from './rpc';

type Pending = {
  resolve: (v: unknown) => void;
  reject: (e: Error) => void;
  onToken?: (t: string) => void;
};

let port: MessagePort | null = null;
let nextId = 1;
const pending = new Map<number, Pending>();
let markReady: () => void;
const ready = new Promise<void>((r) => {
  markReady = r;
});

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
    if ('done' in m) p.resolve(undefined);
    else if (m.ok) p.resolve(m.result);
    else p.reject(new Error(m.error));
  };
  port.start();
  markReady();
});

function send(method: string, args: unknown[], onToken?: (t: string) => void): Promise<unknown> {
  return ready.then(
    () =>
      new Promise((resolve, reject) => {
        const id = nextId++;
        pending.set(id, { resolve, reject, onToken });
        port!.postMessage({ id, method, args });
      })
  );
}

contextBridge.exposeInMainWorld('runanywhere', {
  ready: (): Promise<void> => ready,
  version: () => send('version', []),
  initialize: (secureDir?: string, baseDir?: string) => send('initialize', [secureDir, baseDir]),

  loadLLM: (modelPath: string) => send('loadModel', [modelPath]),
  generate: (
    handle: number,
    prompt: string,
    optionsOrOnToken: Record<string, unknown> | ((t: string) => void),
    onToken?: (t: string) => void
  ) =>
    typeof optionsOrOnToken === 'function'
      ? send('generate', [handle, prompt], optionsOrOnToken)
      : send('generate', [handle, prompt, optionsOrOnToken], onToken),
  // Structured output: constrain decoding to JSON matching `schema` and return
  // the parsed object (grammar built here in the preload; streaming accumulated).
  generateStructured: async (
    handle: number,
    prompt: string,
    schema: JsonSchema,
    options: Record<string, unknown> = {}
  ): Promise<unknown> => {
    const grammar = jsonSchemaToGrammar(schema);
    let out = '';
    await send('generate', [handle, prompt, { ...options, grammar }], (t) => {
      out += t;
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
      out += t;
    });
    return parseStructured(out, 'generateStructured');
  },
  // Tool calling: force a well-formed { name, arguments } call for one of `tools`.
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
      out += t;
    });
    return parseStructured(out, 'generateToolCall');
  },
  unloadLLM: (handle: number) => send('unloadModel', [handle]),

  loadVLM: (modelPath: string, mmprojPath: string) => send('loadVlmModel', [modelPath, mmprojPath]),
  generateVlm: (handle: number, imagePath: string, prompt: string, onToken: (t: string) => void) =>
    send('generateVlm', [handle, imagePath, prompt], onToken),
  unloadVLM: (handle: number) => send('unloadVlmModel', [handle]),

  loadEmbedder: (modelPath: string) => send('loadEmbeddingModel', [modelPath]),
  embed: (handle: number, text: string) => send('embed', [handle, text]),
  unloadEmbedder: (handle: number) => send('unloadEmbeddingModel', [handle]),

  loadSTT: (modelDir: string) => send('loadSttModel', [modelDir]),
  transcribe: (handle: number, pcm16: Uint8Array) => send('transcribe', [handle, pcm16]),
  unloadSTT: (handle: number) => send('unloadSttModel', [handle]),

  loadTTS: (voiceDir: string) => send('loadTtsVoice', [voiceDir]),
  synthesize: (handle: number, text: string) => send('synthesize', [handle, text]),
  unloadTTS: (handle: number) => send('unloadTtsVoice', [handle]),

  secureSet: (key: string, value: string) => send('secureSet', [key, value]),
  secureGet: (key: string) => send('secureGet', [key]),
  secureDelete: (key: string) => send('secureDelete', [key]),

  shutdown: () => send('shutdown', []),
});

// Test-only hook (kept off the SDK surface) so the example app can signal the
// main process when the headless run finishes.
contextBridge.exposeInMainWorld('runanywhereTest', {
  done: (ok: boolean) => ipcRenderer.send('runanywhere-test-done', ok),
  log: (line: string) => ipcRenderer.send('runanywhere-test-log', line),
});
