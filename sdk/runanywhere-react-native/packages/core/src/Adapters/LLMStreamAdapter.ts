/**
 * LLMStreamAdapter.ts (React Native)
 *
 * Wraps the Nitro HybridObject's per-message callback as an
 * `AsyncIterable<LLMStreamEvent>` over the generic `HandleStreamAdapter`
 * fan-out (port of Swift `Adapters/HandleStreamAdapter.swift`).
 *
 * Public API:
 *     for await (const evt of new LLMStreamAdapter(handle).stream(req))
 *         handleEvent(evt);
 *
 * Cancellation: standard `for-await break` triggers
 * `AsyncIterator.return()` which calls the transport's cancel function,
 * which deregisters the proto-byte callback on the C++ handle.
 *
 * Terminal events: `event.isFinal` finishes every subscriber and tears the
 * Nitro subscription down deterministically (Swift LLMStreamAdapter.swift:63)
 * instead of waiting for the native `onDone`.
 */

import { LLM as NitroLLM } from '../Internal/Nitro/NitroLLMSpec';
import {
  LLMGenerateRequest,
  LLMStreamEvent,
} from '@runanywhere/proto-ts/llm_service';
import {
  generateLLM,
  type LLMStreamTransport,
} from '@runanywhere/proto-ts/streams/llm_service_stream';
import { HandleStreamFanOutRegistry } from './HandleStreamAdapter';

/** Process-global fan-out registry for the LLM stream kind. */
const llmFanOutRegistry = new HandleStreamFanOutRegistry<LLMStreamEvent>({
  label: 'NitroLLM.subscribeProtoEvents',
  subscribe: (handle, onBytes, onDone, onError) =>
    NitroLLM.subscribeProtoEvents(handle, onBytes, onDone, onError),
  decode: (bytes) => LLMStreamEvent.decode(bytes),
  isTerminalEvent: (event) => event.isFinal,
});

function fanOutTransportFor(handle: number): LLMStreamTransport {
  return llmFanOutRegistry.transportFor(handle);
}

/**
 * Adapter that exposes the C++ proto-byte LLM callback as a standard JS
 * AsyncIterable. Multiple concurrent `stream()` calls share one Nitro
 * subscription via per-handle fan-out, matching Swift `HandleStreamAdapter`,
 * Kotlin `HandleStreamAdapter`, Flutter `_LLMFanOutRegistry`, and Web
 * `HandleFanOut`.
 */
export class LLMStreamAdapter {
  constructor(private readonly handle: number) {}

  stream(req: LLMGenerateRequest): AsyncIterable<LLMStreamEvent> {
    return generateLLM(fanOutTransportFor(this.handle), req);
  }
}

/** @internal — for tests only. Do not use in application code. */
export const __testing__ = {
  fanOutTransportFor,
};
