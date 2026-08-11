/**
 * VoiceAgentStreamAdapter.ts (React Native)
 *
 * Wraps a Nitro HybridObject's per-message callback as an
 * `AsyncIterable<VoiceEvent>` over the generic `HandleStreamAdapter`
 * fan-out (port of Swift `Adapters/HandleStreamAdapter.swift`).
 *
 * Public API:
 *     for await (const evt of new VoiceAgentStreamAdapter(handle).stream())
 *         handleEvent(evt);
 *
 * Cancellation: standard `for-await break` triggers
 * `AsyncIterator.return()` which calls the transport's cancel function,
 * which in turn calls the Nitro side to deregister the proto-byte
 * callback on the C++ handle when the last subscriber detaches.
 *
 * No terminal-event predicate: voice events fan out until consumers detach
 * or the native side signals done (the Swift VoiceAgent case).
 */

import { VoiceAgent as NitroVoiceAgent } from '../Internal/Nitro/NitroVoiceAgentSpec';
import { VoiceAgentTurnRequest } from '@runanywhere/proto-ts/voice_agent_service';
import { VoiceEvent } from '@runanywhere/proto-ts/voice_events';
import {
  streamVoiceAgent,
  type VoiceAgentStreamTransport,
} from '@runanywhere/proto-ts/streams/voice_agent_service_stream';
import { HandleStreamFanOutRegistry } from './HandleStreamAdapter';

/** Process-global fan-out registry for the voice-agent stream kind. */
const voiceFanOutRegistry = new HandleStreamFanOutRegistry<VoiceEvent>({
  label: 'NitroVoiceAgent.subscribeProtoEvents',
  subscribe: (handle, onBytes, onDone, onError) =>
    NitroVoiceAgent.subscribeProtoEvents(handle, onBytes, onDone, onError),
  decode: (bytes) => VoiceEvent.decode(bytes),
});

function fanOutTransportFor(handle: number): VoiceAgentStreamTransport {
  return voiceFanOutRegistry.transportFor(handle);
}

/**
 * Adapter that exposes the C++ proto-byte voice agent callback as a
 * standard JS AsyncIterable. Multiple concurrent `stream()` calls share
 * one Nitro subscription via per-handle fan-out, matching Swift
 * `HandleStreamAdapter`, Kotlin `HandleStreamAdapter`, Flutter
 * `_VoiceFanOutRegistry`, and Web `HandleFanOut`.
 */
export class VoiceAgentStreamAdapter {
  constructor(private readonly handle: number) {}

  // `VoiceAgentRequest` is deleted outright; the generated stream wrapper's
  // request type is now `VoiceAgentTurnRequest`. The underlying fan-out
  // transport ignores the request value entirely (subscription is keyed on
  // `handle`, not `req` — see `HandleStreamAdapter.transportFor`), so an
  // empty request is a faithful stand-in for the deleted `eventFilter: ''`.
  stream(
    req: VoiceAgentTurnRequest = VoiceAgentTurnRequest.fromPartial({})
  ): AsyncIterable<VoiceEvent> {
    return streamVoiceAgent(fanOutTransportFor(this.handle), req);
  }
}

/** @internal — for tests only. Do not use in application code. */
export const __testing__ = {
  fanOutTransportFor,
};
