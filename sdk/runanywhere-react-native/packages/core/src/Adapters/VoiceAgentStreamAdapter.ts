/**
 * VoiceAgentStreamAdapter.ts (React Native)
 *
 * GAP 09 Phase 19 — see v2_gap_specs/GAP_09_STREAMING_CONSISTENCY.md.
 *
 * Wraps a Nitro HybridObject's per-message callback as an
 * `AsyncIterable<VoiceEvent>` using the codegen'd transport wrapper from
 * `idl/codegen/templates/ts_async_iterable.njk` (Phase 14).
 *
 * Public API:
 *     for await (const evt of new VoiceAgentStreamAdapter(handle).stream())
 *         handleEvent(evt);
 *
 * Cancellation: standard `for-await break` triggers
 * `AsyncIterator.return()` which calls the transport's cancel function,
 * which in turn calls the Nitro side to deregister the proto-byte
 * callback on the C++ handle.
 */

import { VoiceAgent as NitroVoiceAgent } from '../generated/NitroVoiceAgentSpec';
import { VoiceAgentRequest } from '@runanywhere/proto-ts/voice_agent_service';
import { VoiceEvent } from '@runanywhere/proto-ts/voice_events';
import {
  streamVoiceAgent,
  VoiceAgentStreamTransport,
} from '@runanywhere/proto-ts/streams/voice_agent_service_stream';

/**
 * Adapter that exposes the C++ proto-byte voice agent callback as a
 * standard JS AsyncIterable. Holds an opaque [handle] (the value
 * returned by `RunAnywhere.voiceAgent.create(...)`) and constructs a
 * fresh transport per [stream()] call.
 */
export class VoiceAgentStreamAdapter {
  constructor(private readonly handle: number) {}

  /**
   * Open a new event subscription. Each call returns an independent
   * AsyncIterable backed by its own C-side registration.
   */
  stream(req: VoiceAgentRequest = { eventFilter: '' }): AsyncIterable<VoiceEvent> {
    return streamVoiceAgent(this.transport(), req);
  }

  /** Construct the platform transport that satisfies the codegen'd
   *  `VoiceAgentStreamTransport` interface. The Nitro spec is expected
   *  to expose `subscribeProtoEvents(handle, onBytes)` returning an
   *  unsubscribe function. */
  private transport(): VoiceAgentStreamTransport {
    const handle = this.handle;
    return {
      subscribe(_req, onMessage, onError, onDone) {
        try {
          const unsubscribe = NitroVoiceAgent.subscribeProtoEvents(
            handle,
            (bytes: ArrayBuffer) => {
              try {
                onMessage(VoiceEvent.decode(new Uint8Array(bytes)));
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
