/**
 * LLMStreamAdapter.ts (React Native)
 *
 * v2 close-out / G-A2 Round 1 — see v2_audit/03_GAPS.md.
 *
 * Wraps a Nitro HybridObject's per-message callback as an
 * `AsyncIterable<LLMStreamEvent>` using the codegen'd transport wrapper
 * from `idl/codegen/templates/ts_async_iterable.njk`. Mirrors
 * `VoiceAgentStreamAdapter.ts` (RN) and `LLMStreamAdapter.ts` (Web) —
 * same fan-out shape, different C ABI (`rac_llm_set_stream_proto_callback`
 * instead of `rac_voice_agent_set_proto_callback`).
 *
 * This is the unified LLM streaming path for the RN SDK.
 *
 * Public API:
 *     const handle = await RunAnywhere.getLLMHandle();
 *     for await (const evt of new LLMStreamAdapter(handle).stream(req)) {
 *         if (evt.isFinal) break;
 *         appendToken(evt.token);
 *     }
 *
 * Cancellation: standard `for-await break` triggers
 * `AsyncIterator.return()` which calls the transport's cancel function,
 * which in turn calls the Nitro side to deregister the proto-byte
 * callback on the C++ handle.
 */

import { LLM as NitroLLM } from '../generated/NitroLLMSpec';
import type { LLMGenerateRequest } from '@runanywhere/proto-ts/llm_service';
import { LLMStreamEvent } from '@runanywhere/proto-ts/llm_service';
import {
  generateLLM,
  type LLMStreamTransport,
} from '@runanywhere/proto-ts/streams/llm_service_stream';

/**
 * Adapter that exposes the C++ proto-byte LLM stream callback as a
 * standard JS AsyncIterable. Holds an opaque [handle] (the value
 * returned by `RunAnywhere.getLLMHandle()`) and constructs a fresh
 * transport per [stream()] call.
 */
export class LLMStreamAdapter {
  constructor(private readonly handle: number) {}

  /**
   * Open a new event subscription. Each call returns an independent
   * AsyncIterable backed by its own C-side registration.
   */
  stream(
    req: LLMGenerateRequest = {
      prompt: '',
      maxTokens: 0,
      temperature: 0,
      topP: 0,
      topK: 0,
      systemPrompt: '',
      emitThoughts: false,
      repetitionPenalty: 0,
      stopSequences: [],
      streamingEnabled: true,
      preferredFramework: '',
      jsonSchema: '',
      executionTarget: '',
    },
  ): AsyncIterable<LLMStreamEvent> {
    return generateLLM(this.transport(), req);
  }

  /** Construct the platform transport that satisfies the codegen'd
   *  `LLMStreamTransport` interface. The Nitro spec exposes
   *  `subscribeProtoEvents(handle, onBytes, onDone, onError)` returning
   *  an unsubscribe function. */
  private transport(): LLMStreamTransport {
    const handle = this.handle;
    return {
      subscribe(_req, onMessage, onError, onDone) {
        try {
          const unsubscribe = NitroLLM.subscribeProtoEvents(
            handle,
            (bytes: ArrayBuffer) => {
              try {
                onMessage(LLMStreamEvent.decode(new Uint8Array(bytes)));
              } catch (e) {
                onError(e instanceof Error ? e : new Error(String(e)));
              }
            },
            () => onDone(),
            (err: string) => onError(new Error(err)),
          );
          return () => {
            try { unsubscribe(); } catch { /* noop */ }
          };
        } catch (e) {
          onError(e instanceof Error ? e : new Error(String(e)));
          return () => {};
        }
      },
    };
  }
}
