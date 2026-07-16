// rpc.ts — the tiny wire protocol between the renderer/main and the utility
// process that hosts the native addon. One MessagePort carries request/reply
// plus token streaming, correlated by a numeric id.

/** renderer/main -> utility host. */
export interface RpcRequest {
  id: number;
  method: string; // an addon method name, or "version"
  args: unknown[];
}

/** utility host -> renderer/main. Either a stream event or a terminal reply. */
export type RpcMessage =
  | { id: number; token: string } // a streamed token (generate / generateVlm)
  | { id: number; done: true } // stream finished OK
  | { id: number; ok: true; result?: unknown } // unary reply
  | { id: number; ok: false; error: string }; // failure (unary or stream)

/** Methods whose last logical argument is a per-token callback the host injects. */
export const STREAMING_METHODS = new Set<string>(['generate', 'generateVlm']);
