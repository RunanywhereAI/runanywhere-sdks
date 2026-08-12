// dispatch.ts — the pure RPC routing logic for the utility host, factored out of
// host.ts so it can be unit-tested without loading the native addon or Electron.
// host.ts injects the real addon + model resolver; tests inject fakes.
import * as os from 'os';
import * as path from 'path';

import { BACKEND_METHODS, rpcMethodFor } from '../api/backend';
import {
  DUPLEX_METHODS,
  RpcCallReply,
  RpcErrorPayload,
  RpcRequest,
  STREAMING_METHODS,
} from './rpc';

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
  /** Override the duplex-method set (defaults to DUPLEX_METHODS). */
  duplexMethods?: Set<string>;
  /** Tracks host-initiated calls awaiting a client reply. Required for duplex methods. */
  duplex?: DuplexCalls;
}

/**
 * The host half of the reverse channel. A duplex method's injected callback
 * posts `{ id, call }` and parks until the client answers with a matching
 * `{ id, seq, ok }`; the caller on the other side of that promise is a native
 * thread, so an unanswered call costs one blocked worker until it times out.
 */
export class DuplexCalls {
  private seq = 0;
  private readonly pending = new Map<
    string,
    { resolve: (value: unknown) => void; reject: (error: Error) => void }
  >();

  ask(port: DispatchPort, id: number, event: unknown): Promise<unknown> {
    this.seq += 1;
    const seq = this.seq;
    return new Promise((resolve, reject) => {
      this.pending.set(`${id}:${seq}`, { resolve, reject });
      port.postMessage({ id, call: { seq, event } });
    });
  }

  settle(reply: RpcCallReply): void {
    const key = `${reply.id}:${reply.seq}`;
    const waiter = this.pending.get(key);
    if (!waiter) return;
    this.pending.delete(key);
    if (reply.ok) {
      waiter.resolve(reply.result);
      return;
    }
    const error = reply.error;
    waiter.reject(
      new Error(typeof error === 'string' ? error : error?.message ?? 'duplex call failed')
    );
  }

  /** Fail anything still outstanding once its request has settled. */
  release(id: number): void {
    for (const [key, waiter] of [...this.pending]) {
      if (!key.startsWith(`${id}:`)) continue;
      this.pending.delete(key);
      waiter.reject(new Error('request finished before the executor replied'));
    }
  }
}

const DEFAULT_LOAD_RE = /^load(Model|VlmModel|EmbeddingModel|SttModel|TtsVoice)$/;

/**
 * Explicit allowlist of RPC method names the utility host will dispatch.
 * Unknown methods are rejected before touching `api`.
 *
 * **This list is a security boundary, not a convenience.** `dispatch` resolves an
 * allowed name straight off `deps.api`, and in `host.ts` that object is a Proxy
 * whose fallthrough is the raw addon. So every bare addon-shaped name here would
 * hand any renderer a direct, LEASE-LESS call into native code — bypassing
 * `NativeBackend`, and with it the `take_handle_when_idle` / `begin_op` leases
 * that stop an unload-during-generate use-after-free.
 *
 * It previously carried 38 such names. The v3 facade used exactly one of them
 * (`version`); `RpcBackend` namespaces every other call through
 * {@link rpcMethodFor}. The 37 unused names were removed rather than kept "just
 * in case" — an unreachable capability is still reachable by anything that can
 * post to the port.
 *
 * Adding a bare name here re-opens that hole. Add a `RaBackend` operation
 * instead: it arrives as `v3.<op>` and goes through the lease-taking path.
 */
export const ALLOWED_RPC_METHODS: ReadonlySet<string> = new Set([
  // The ONLY bare name a renderer may send. It is answered from `deps.getVersion()`
  // in `dispatch` and never reaches `api`, so it grants no addon access at all.
  'version',
  // v3 backend contract — one entry per RaBackend operation, namespaced.
  // `host.ts` routes a `v3.<op>` through its NativeBackend instance, so every
  // integer handle stays inside the utility process and every in-flight call
  // takes the `begin_op` lease that makes unload-during-generate safe.
  ...BACKEND_METHODS.map(rpcMethodFor),
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
    const duplexMethods = deps.duplexMethods ?? DUPLEX_METHODS;
    if (duplexMethods.has(method)) {
      const duplex = deps.duplex;
      if (!duplex) {
        port.postMessage({ id, ok: false, error: `no duplex channel for '${method}'` });
        return;
      }
      const onEvent = (event: unknown) => duplex.ask(port, id, event);
      (api[method](...args, onEvent) as Promise<unknown>)
        .then((result) => port.postMessage({ id, ok: true, result }))
        .catch((e) => port.postMessage({ id, ok: false, error: rpcError(e) }))
        .then(() => duplex.release(id));
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
