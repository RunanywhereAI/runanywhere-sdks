// dispatch.ts — the pure RPC routing logic for the utility host, factored out of
// host.ts so it can be unit-tested without loading the native addon or Electron.
// host.ts injects the real addon + model resolver; tests inject fakes.
import * as os from 'os';
import * as path from 'path';

import { RpcRequest, STREAMING_METHODS } from './rpc';

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
}

const DEFAULT_LOAD_RE = /^load(Model|VlmModel|EmbeddingModel|SttModel|TtsVoice)$/;

const errmsg = (e: unknown): string => (e instanceof Error ? e.message : String(e));

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
  try {
    if (streaming.has(method)) {
      const onToken = (token: string) => port.postMessage({ id, token });
      // Carry the resolved value on completion so a streaming method that also
      // returns data (downloadModel -> ResolvedModel) isn't silently dropped;
      // token-only streams (generate) resolve void, so keep their message bare.
      (api[method](...args, onToken) as Promise<unknown>)
        .then((result) =>
          port.postMessage(result === undefined ? { id, done: true } : { id, done: true, result })
        )
        .catch((e) => port.postMessage({ id, ok: false, error: errmsg(e) }));
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
            port.postMessage({ id, ok: false, error: errmsg(e) });
          }
        })
        .catch((e) => port.postMessage({ id, ok: false, error: errmsg(e) }));
      return;
    }
    port.postMessage({ id, ok: true, result: api[method](...args) });
  } catch (e) {
    port.postMessage({ id, ok: false, error: errmsg(e) });
  }
}
