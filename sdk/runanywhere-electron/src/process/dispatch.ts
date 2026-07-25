// dispatch.ts — the pure RPC routing logic for the utility host, factored out of
// host.ts so it can be unit-tested without loading the native addon or Electron.
// host.ts injects the real addon + model resolver; tests inject fakes.
import * as os from 'os';
import * as path from 'path';

import { RpcErrorPayload, RpcRequest, STREAMING_METHODS } from './rpc';

/** Minimal port surface dispatch needs (a subset of Electron's MessagePortMain). */
export interface DispatchPort {
  postMessage(message: unknown): void;
}

export interface DispatchDeps {
  /** The addon (or a fake) as a callable method map. */
  api: Record<string, (...a: unknown[]) => unknown>;
  /** Returns the runtime/commons version string (addon.version). */
  getVersion: () => string;
  /** Resolve a load* method's args (e.g. download a catalog id) before calling. */
  resolveLoadArgs: (method: string, args: unknown[]) => Promise<unknown[]>;
  /** Override the streaming-method set (defaults to STREAMING_METHODS). */
  streamingMethods?: Set<string>;
  /** Override the load-method matcher (defaults to the built-in). */
  loadRe?: RegExp;
  /** Override the allowed-method set (defaults to ALLOWED_RPC_METHODS). */
  allowedMethods?: Set<string>;
}

const DEFAULT_LOAD_RE = /^load(Model|VlmModel|EmbeddingModel|SttModel|TtsVoice)$/;

/**
 * Explicit allowlist of RPC method names the utility host will dispatch.
 * Matches the native addon surface plus host-owned helpers (downloadModel,
 * modelStatus, exists). Unknown methods are rejected before touching `api`.
 */
export const ALLOWED_RPC_METHODS: ReadonlySet<string> = new Set([
  // lifecycle
  'initialize',
  'shutdown',
  'version',
  // secure store
  'secureSet',
  'secureGet',
  'secureDelete',
  // host-owned filesystem / download
  'downloadModel',
  'modelStatus',
  'exists',
  // VAD
  'createVad',
  'vadProcess',
  'vadIsActive',
  'vadSetThreshold',
  'vadReset',
  'unloadVad',
  // LLM
  'loadModel',
  'generate',
  'unloadModel',
  // VLM
  'loadVlmModel',
  'generateVlm',
  'unloadVlmModel',
  // embeddings
  'loadEmbeddingModel',
  'embed',
  'unloadEmbeddingModel',
  // STT
  'loadSttModel',
  'transcribe',
  'unloadSttModel',
  // TTS
  'loadTtsVoice',
  'synthesize',
  'unloadTtsVoice',
  // registry + RAG
  'registerModel',
  'ragCreateSession',
  'ragIngest',
  'ragQuery',
  'ragStats',
  'ragClear',
  'ragDestroySession',
]);

function rpcError(e: unknown): string | RpcErrorPayload {
  if (typeof e === 'string') return e;
  if (e instanceof Error) {
    const extra = e as Error & {
      code?: unknown;
      cAbiCode?: unknown;
      category?: unknown;
      nestedMessage?: unknown;
      fieldPath?: unknown;
    };
    return {
      name: e.name,
      message: e.message,
      ...(typeof extra.code === 'number' && Number.isFinite(extra.code) ? { code: extra.code } : {}),
      ...(typeof extra.cAbiCode === 'number' && Number.isFinite(extra.cAbiCode)
        ? { cAbiCode: extra.cAbiCode }
        : {}),
      ...(typeof extra.category === 'number' && Number.isFinite(extra.category)
        ? { category: extra.category }
        : {}),
      ...(typeof extra.nestedMessage === 'string' ? { nestedMessage: extra.nestedMessage } : {}),
      ...(typeof extra.fieldPath === 'string' ? { fieldPath: extra.fieldPath } : {}),
    };
  }
  if (e && typeof e === 'object') {
    const obj = e as Record<string, unknown>;
    if (typeof obj.message === 'string') {
      return {
        message: obj.message,
        ...(typeof obj.name === 'string' ? { name: obj.name } : {}),
        ...(typeof obj.code === 'number' && Number.isFinite(obj.code) ? { code: obj.code } : {}),
        ...(typeof obj.cAbiCode === 'number' && Number.isFinite(obj.cAbiCode)
          ? { cAbiCode: obj.cAbiCode }
          : {}),
        ...(typeof obj.category === 'number' && Number.isFinite(obj.category)
          ? { category: obj.category }
          : {}),
        ...(typeof obj.nestedMessage === 'string' ? { nestedMessage: obj.nestedMessage } : {}),
        ...(typeof obj.fieldPath === 'string' ? { fieldPath: obj.fieldPath } : {}),
      };
    }
  }
  return String(e);
}

/**
 * Route one RPC request to the addon and post replies/token-stream events back
 * over `port`. Streaming methods (generate/generateVlm) get an injected onToken
 * that posts `{id, token}` per token and `{id, done:true}` on completion; unary
 * methods post `{id, ok, result}` or `{id, ok:false, error}`.
 */
export function dispatch(port: DispatchPort, req: RpcRequest, deps: DispatchDeps): void {
  const { id, method, args } = req;
  const api = deps.api;
  const streaming = deps.streamingMethods ?? STREAMING_METHODS;
  const loadRe = deps.loadRe ?? DEFAULT_LOAD_RE;
  const allowed = deps.allowedMethods ?? ALLOWED_RPC_METHODS;
  try {
    if (!allowed.has(method)) {
      port.postMessage({
        id,
        ok: false,
        error: `unknown RPC method: '${method}'`,
      });
      return;
    }
    if (streaming.has(method)) {
      const onToken = (token: string) => port.postMessage({ id, token });
      // Carry the resolved value on completion so a streaming method that also
      // returns data (downloadModel -> ResolvedModel) isn't silently dropped;
      // token-only streams (generate) resolve void, so keep their message bare.
      (api[method](...args, onToken) as Promise<unknown>)
        .then((result) =>
          port.postMessage(result === undefined ? { id, done: true } : { id, done: true, result })
        )
        .catch((e) => port.postMessage({ id, ok: false, error: rpcError(e) }));
      return;
    }
    if (method === 'version') {
      port.postMessage({ id, ok: true, result: deps.getVersion() });
      return;
    }
    if (method === 'initialize') {
      const home = path.join(os.homedir(), '.runanywhere');
      const base = (args[1] as string) || home;
      const secure = (args[0] as string) || path.join(base, 'secure');
      api.initialize(secure, base);
      port.postMessage({ id, ok: true });
      return;
    }
    if (loadRe.test(method)) {
      deps
        .resolveLoadArgs(method, args)
        .then((resolved) => {
          try {
            port.postMessage({ id, ok: true, result: api[method](...resolved) });
          } catch (e) {
            port.postMessage({ id, ok: false, error: rpcError(e) });
          }
        })
        .catch((e) => port.postMessage({ id, ok: false, error: rpcError(e) }));
      return;
    }
    // A binding may return a value synchronously OR a Promise (RAG ingest/query
    // run on a worker thread so they don't block the host event loop). Await the
    // thenable case; keep the sync case synchronous.
    const result = api[method](...args) as unknown;
    if (result != null && typeof (result as { then?: unknown }).then === 'function') {
      (result as Promise<unknown>)
        .then((r) => port.postMessage({ id, ok: true, result: r }))
        .catch((e) => port.postMessage({ id, ok: false, error: rpcError(e) }));
    } else {
      port.postMessage({ id, ok: true, result });
    }
  } catch (e) {
    port.postMessage({ id, ok: false, error: rpcError(e) });
  }
}
