// Pure RPC routing for the utility host, factored out so it is unit-testable
// without the addon or Electron. Every method maps 1:1 to a RaBackend operation
// (namespaced `v3.<op>`), so routing is uniform: strip the prefix, look up the
// method, forward the args, and for streaming ops inject a proto-byte sink.

import { BACKEND_METHODS, rpcMethodFor } from '../backend.js';
import type { ProtoBytes, ToolExecutor } from '../backend.js';
import { STREAMING_METHODS } from './protocol.js';
import type { RpcErrorPayload, RpcRequest, ToolExecReply } from './protocol.js';

/** The minimal port surface dispatch needs. */
export interface DispatchPort {
  postMessage(message: unknown): void;
}

/** Explicit allowlist: only the v3 backend operations may be dispatched. */
export const ALLOWED_RPC_METHODS: ReadonlySet<string> = new Set(BACKEND_METHODS.map(rpcMethodFor));

const TOOL_RUN_LOOP = rpcMethodFor('toolRunLoop');

/**
 * The host side of the tool-calling loop. commons drives the loop in the host, but
 * each tool's executor lives in the renderer, so when commons asks for a tool the
 * host posts a `toolExec` and awaits the renderer's `toolResult` for that execId.
 */
export class ToolExecBridge {
  private nextExec = 1;
  private readonly pending = new Map<string, { resolve: (b: ProtoBytes) => void; reject: (e: Error) => void }>();

  constructor(private readonly port: DispatchPort) {}

  /** An onExecute bound to one toolRunLoop request id; each call round-trips to the renderer. */
  executorFor(id: number): ToolExecutor {
    return (toolCall: ProtoBytes) =>
      new Promise<ProtoBytes>((resolve, reject) => {
        const execId = this.nextExec++;
        this.pending.set(`${id}:${execId}`, { resolve, reject });
        this.port.postMessage({ id, toolExec: toolCall, execId });
      });
  }

  /** Deliver a renderer's ToolResult to the waiting executor. */
  resolveReply(reply: ToolExecReply): void {
    const key = `${reply.id}:${reply.execId}`;
    const entry = this.pending.get(key);
    if (!entry) return;
    this.pending.delete(key);
    entry.resolve(reply.toolResult);
  }

  /** Fail any executor still waiting when a loop ends (so a dropped result can't hang). */
  clear(id: number): void {
    for (const key of [...this.pending.keys()]) {
      if (key.startsWith(`${id}:`)) {
        this.pending.get(key)?.reject(new Error('tool-calling loop ended'));
        this.pending.delete(key);
      }
    }
  }
}

/** A backend addressed by operation name (a NativeBackend, cast to a method map). */
export type BackendMap = Record<string, (...args: unknown[]) => unknown>;

export interface DispatchDeps {
  backend: BackendMap;
  streamingMethods?: ReadonlySet<string>;
  allowedMethods?: ReadonlySet<string>;
  /** Present in the utility host so toolRunLoop can round-trip executors to the renderer. */
  toolBridge?: ToolExecBridge;
}

function rpcError(e: unknown): string | RpcErrorPayload {
  if (typeof e === 'string') return e;
  if (e && typeof e === 'object') {
    const x = e as Record<string, unknown>;
    const message = typeof x.message === 'string' ? x.message : String(e);
    const num = (v: unknown): number | undefined =>
      typeof v === 'number' && Number.isFinite(v) ? v : undefined;
    const str = (v: unknown): string | undefined => (typeof v === 'string' ? v : undefined);
    return {
      message,
      ...(str(x.name) ? { name: str(x.name) } : {}),
      ...(num(x.code) !== undefined ? { code: num(x.code) } : {}),
      ...(num(x.cAbiCode) !== undefined ? { cAbiCode: num(x.cAbiCode) } : {}),
      ...(num(x.category) !== undefined ? { category: num(x.category) } : {}),
      ...(str(x.nestedMessage) ? { nestedMessage: str(x.nestedMessage) } : {}),
      ...(str(x.fieldPath) ? { fieldPath: str(x.fieldPath) } : {}),
    };
  }
  return String(e);
}

/** Route one RPC request to the backend and post replies/stream events back. */
export function dispatch(port: DispatchPort, req: RpcRequest, deps: DispatchDeps): void {
  const { id, method, args } = req;
  const streaming = deps.streamingMethods ?? STREAMING_METHODS;
  const allowed = deps.allowedMethods ?? ALLOWED_RPC_METHODS;

  if (!allowed.has(method)) {
    port.postMessage({ id, ok: false, error: `unknown RPC method: '${method}'` });
    return;
  }
  const op = method.slice(3); // strip "v3."
  const fn = deps.backend[op];
  try {
    if (method === TOOL_RUN_LOOP && deps.toolBridge) {
      // Bidirectional: commons runs the loop here, each tool executes in the renderer.
      const onExecute = deps.toolBridge.executorFor(id);
      Promise.resolve(fn.call(deps.backend, ...args, onExecute))
        .then(
          (result) => port.postMessage({ id, ok: true, result }),
          (e) => port.postMessage({ id, ok: false, error: rpcError(e) })
        )
        .finally(() => deps.toolBridge?.clear(id));
      return;
    }
    if (streaming.has(method)) {
      const onChunk = (chunk: unknown): void => port.postMessage({ id, chunk });
      (fn.call(deps.backend, ...args, onChunk) as Promise<unknown>).then(
        (result) =>
          port.postMessage(result === undefined ? { id, done: true } : { id, done: true, result }),
        (e) => port.postMessage({ id, ok: false, error: rpcError(e) })
      );
      return;
    }
    Promise.resolve(fn.call(deps.backend, ...args)).then(
      (result) => port.postMessage({ id, ok: true, result }),
      (e) => port.postMessage({ id, ok: false, error: rpcError(e) })
    );
  } catch (e) {
    port.postMessage({ id, ok: false, error: rpcError(e) });
  }
}
