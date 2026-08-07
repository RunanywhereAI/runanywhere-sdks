// The wire protocol between a renderer/main and the utility host that owns the
// native addon. One MessagePort carries request/reply plus streaming, correlated
// by a numeric id. Payloads are proto bytes and scalars, so everything is
// structured-cloneable.

import { BACKEND_STREAMING_METHODS, rpcMethodFor } from '../backend.js';

/** renderer/main -> utility host. */
export interface RpcRequest {
  id: number;
  method: string; // an rpcMethodFor(op) name, e.g. "v3.llmGenerate"
  args: unknown[];
}

/** A structured error carried back across the boundary. */
export interface RpcErrorPayload {
  message: string;
  name?: string;
  code?: number;
  cAbiCode?: number;
  category?: number;
  nestedMessage?: string;
  fieldPath?: string;
}

/** utility host -> renderer/main. */
export type RpcMessage =
  | { id: number; chunk: Uint8Array } // one streamed proto-byte event
  | { id: number; toolExec: Uint8Array; execId: number } // host asks the renderer to run a tool
  | { id: number; done: true; result?: unknown } // stream finished OK
  | { id: number; ok: true; result?: unknown } // unary reply
  | { id: number; ok: false; error: string | RpcErrorPayload }; // failure

/**
 * renderer/main -> utility host: the encoded ToolResult for a tool the host asked
 * it to run (the reverse leg of the tool-calling loop; commons drives the loop in
 * the host, the executor lives in the renderer).
 */
export interface ToolExecReply {
  id: number;
  execId: number;
  toolResult: Uint8Array;
}

/** True for a tool-result message coming back from the renderer. */
export function isToolExecReply(m: unknown): m is ToolExecReply {
  return (
    !!m &&
    typeof m === 'object' &&
    typeof (m as { execId?: unknown }).execId === 'number' &&
    (m as { toolResult?: unknown }).toolResult !== undefined
  );
}

/** The v3 operations whose last argument is a per-event proto sink. */
export const STREAMING_METHODS: ReadonlySet<string> = new Set(
  [...BACKEND_STREAMING_METHODS].map(rpcMethodFor)
);
