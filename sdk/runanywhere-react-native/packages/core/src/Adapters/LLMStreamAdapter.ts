/**
 * LLMStreamAdapter.ts (React Native)
 *
 * v2 close-out Phase G-2 — see docs/v2_closeout_phase_g2_report.md.
 *
 * Wraps a Nitro HybridObject's per-message callback as an
 * `AsyncIterable<LLMStreamEvent>` using the codegen'd transport wrapper
 * from `idl/codegen/templates/ts_async_iterable.njk`. Mirrors
 * `VoiceAgentStreamAdapter.ts` shape; the difference is the underlying
 * C ABI (`rac_llm_set_stream_proto_callback` vs
 * `rac_voice_agent_set_proto_callback`).
 *
 * This is the unified LLM streaming path — the hand-rolled
 * `tokenGenerator` async generator + per-token callback shim in
 * `RunAnywhere+TextGeneration.ts` should be migrated to call this
 * adapter (tracked as follow-up; this phase ships the adapter itself
 * and the codegen'd transport binding).
 *
 * Public API:
 *     for await (const evt of new LLMStreamAdapter(handle).stream(req)) {
 *         if (evt.isFinal) break;
 *         print(evt.token);
 *     }
 *
 * Cancellation: `for-await break` triggers `AsyncIterator.return()`
 * which calls the transport's cancel function, which deregisters the
 * proto-byte callback on the C++ handle.
 */

import { LLM as NitroLLM } from '../generated/NitroLLMSpec';
import type { LLMGenerateRequest } from '../generated/llm_service';
import { LLMStreamEvent } from '../generated/llm_service';
import {
  generateLLM,
  LLMStreamTransport,
} from '../generated/streams/llm_service_stream';

/**
 * Adapter that exposes the C++ proto-byte LLM stream callback as a
 * standard JS AsyncIterable. Holds an opaque [handle] (the value
 * returned by the backend package's LLM create thunk) and constructs a
 * fresh transport per [stream()] call.
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
    },
  ): AsyncIterable<LLMStreamEvent> {
    return generateLLM(this.transport(), req);
  }

  /**
   * Platform transport conforming to the codegen'd `LLMStreamTransport`
   * interface. The Nitro spec (`LLM.nitro.ts`) exposes
   * `subscribeProtoEvents(handle, onBytes, onDone, onError)` returning
   * an unsubscribe function — same shape as the voice agent.
   */
  private transport(): LLMStreamTransport {
    const handle = this.handle;
    return {
      subscribe(_req, onMessage, onError, onDone) {
        try {
          const unsubscribe = NitroLLM.subscribeProtoEvents(
            handle,
            (bytes: Uint8Array) => {
              try {
                const event = LLMStreamEvent.decode(bytes);
                onMessage(event);
                if (event.isFinal) onDone();
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
