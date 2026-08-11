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
export interface RpcErrorPayload {
  message: string;
  name?: string;
  code?: number;
  cAbiCode?: number;
  category?: number;
  nestedMessage?: string;
  fieldPath?: string;
}

export type RpcMessage =
  | { id: number; token: string } // a streamed token (generate / generateVlm)
  | { id: number; call: { seq: number; event: unknown } } // host asks the client something and waits
  | { id: number; done: true; result?: unknown } // stream finished OK (result = resolved value, e.g. downloadModel's ResolvedModel)
  | { id: number; ok: true; result?: unknown } // unary reply
  | { id: number; ok: false; error: string | RpcErrorPayload }; // failure (unary or stream)

/**
 * client -> utility host: the answer to a `{ id, call }`. Only duplex methods
 * produce these, and the host is blocked on the reply, so a client that drops
 * one stalls that call until the native-side executor timeout fires.
 */
export interface RpcCallReply {
  id: number;
  seq: number;
  ok: boolean;
  result?: unknown;
  error?: string | RpcErrorPayload;
}

export function isCallReply(message: unknown): message is RpcCallReply {
  return (
    typeof message === 'object' &&
    message !== null &&
    typeof (message as RpcCallReply).seq === 'number' &&
    typeof (message as RpcCallReply).ok === 'boolean'
  );
}

/**
 * Methods whose last logical argument is a per-event callback the host injects:
 * generate/generateVlm stream tokens; downloadModel streams progress objects. The
 * `v3.*` entries are the streaming operations of the v3 backend contract
 * (see BACKEND_STREAMING_METHODS).
 */
export const STREAMING_METHODS = new Set<string>([
  'generate',
  'generateVlm',
  'downloadModel',
  'v3.resolveModel',
  'v3.llmGenerate',
  'v3.llmGenerateStreamProto',
  'v3.vlmStreamProto',
  'v3.sttTranscribeStream',
  'v3.sttTranscribeStreamProto',
  'v3.ttsSynthesizeStream',
  'v3.ttsSynthesizeStreamProto',
  // The voice agent's VoiceEvent stream is long-lived: it opens with the
  // session and its terminal reply lands when the session closes.
  'v3.voiceEvents',
  'v3.voiceProcessTurn',
  'v3.ragQueryStream',
  // Download progress is one process-wide subscription: it opens on the first
  // download and its terminal reply lands when downloadUnwatch closes it.
  'v3.downloadWatch',
  'v3.vadSetStreamCallback',
]);

/**
 * Methods whose injected callback is a *request*, not a notification: the host
 * is parked inside native code until the client answers. Today that is the
 * tool-calling run loop, whose executors live wherever the app registered them.
 */
export const DUPLEX_METHODS = new Set<string>(['v3.toolRunLoop']);
