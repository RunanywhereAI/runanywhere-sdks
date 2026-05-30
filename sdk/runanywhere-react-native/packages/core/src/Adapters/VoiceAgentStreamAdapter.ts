/**
 * VoiceAgentStreamAdapter.ts (React Native)
 *
 * Wraps a Nitro HybridObject's per-message callback as an
 * `AsyncIterable<VoiceEvent>` using the codegen'd transport wrapper from
 * `idl/codegen/templates/ts_async_iterable.njk`.
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
 * Multi-collector fan-out:
 *   The underlying C ABI exposes a SINGLE proto-callback slot per handle.
 *   Without fan-out, a second `stream()` collector silently replaces the
 *   first by re-calling `NitroVoiceAgent.subscribeProtoEvents(handle, ...)`.
 *   To preserve AsyncIterable fan-out semantics a per-handle
 *   `HandleFanOut` is kept in a process-global Map and one Nitro
 *   subscription is installed for the lifetime of the first-through-last
 *   subscriber. Parity with iOS (HandleStreamAdapter), Kotlin
 *   (HandleStreamAdapter.kt), Flutter (_VoiceFanOutRegistry), and Web
 *   (HandleFanOut/fanOutCache).
 */

import { VoiceAgent as NitroVoiceAgent } from '../Internal/Nitro/NitroVoiceAgentSpec';
import { VoiceAgentRequest } from '@runanywhere/proto-ts/voice_agent_service';
import { VoiceEvent } from '@runanywhere/proto-ts/voice_events';
import {
  streamVoiceAgent,
  VoiceAgentStreamTransport,
} from '@runanywhere/proto-ts/streams/voice_agent_service_stream';

// ---------------------------------------------------------------------------
// Per-handle fan-out — parity with Web HandleFanOut and Swift HandleFanOut.
// ---------------------------------------------------------------------------

interface Subscriber {
  onMessage: (e: VoiceEvent) => void;
  onError:   (err: Error)    => void;
  onDone:    ()              => void;
}

/**
 * Per-handle fan-out state. Holds the active subscriber set and a single
 * Nitro unsubscribe closure installed for the lifetime of the first
 * through last subscriber against this handle.
 */
class HandleFanOut {
  private readonly subscribers = new Set<Subscriber>();
  private unsubscribeNitro: (() => void) | null = null;

  constructor(
    private readonly handle: number,
    private readonly onTornDown: () => void,
  ) {}

  /**
   * Attach a subscriber. Installs the shared Nitro subscription on first
   * attach. Returns a cancel function that removes the subscriber (and
   * tears the Nitro subscription down when the last one leaves), or null
   * if the initial Nitro registration failed.
   */
  attach(sub: Subscriber): (() => void) | null {
    if (this.unsubscribeNitro === null) {
      const ok = this.installNitro();
      if (!ok) return null;
    }
    this.subscribers.add(sub);
    return () => this.detach(sub);
  }

  private installNitro(): boolean {
    try {
      const handle = this.handle;
      this.unsubscribeNitro = NitroVoiceAgent.subscribeProtoEvents(
        handle,
        (bytes: ArrayBuffer) => {
          let event: VoiceEvent;
          try {
            event = VoiceEvent.decode(new Uint8Array(bytes));
          } catch (e) {
            this.broadcastError(e);
            return;
          }
          this.broadcast(event);
        },
        () => {
          // Native signalled end-of-stream; finish all subscribers.
          const snapshot = Array.from(this.subscribers);
          this.subscribers.clear();
          for (const s of snapshot) {
            try { s.onDone(); } catch { /* swallow */ }
          }
          this.tearDown();
        },
        (err: string) => {
          this.broadcastError(new Error(err));
        },
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  private broadcast(event: VoiceEvent): void {
    // Iterate a snapshot so a subscriber that cancels in its onMessage
    // handler cannot mutate the set underneath us.
    const snapshot = Array.from(this.subscribers);
    for (const s of snapshot) {
      try {
        s.onMessage(event);
      } catch (e) {
        // Deliver the throw to that subscriber only; don't starve peers.
        try { s.onError(e instanceof Error ? e : new Error(String(e))); }
        catch { /* swallow */ }
        this.subscribers.delete(s);
      }
    }
  }

  private broadcastError(e: unknown): void {
    const err = e instanceof Error ? e : new Error(String(e));
    const snapshot = Array.from(this.subscribers);
    this.subscribers.clear();
    for (const s of snapshot) {
      try { s.onError(err); } catch { /* swallow */ }
    }
    this.tearDown();
  }

  private detach(sub: Subscriber): void {
    this.subscribers.delete(sub);
    if (this.subscribers.size === 0) {
      this.tearDown();
    }
  }

  private tearDown(): void {
    if (this.unsubscribeNitro === null) return;
    const fn = this.unsubscribeNitro;
    this.unsubscribeNitro = null;
    try { fn(); } catch { /* swallow */ }
    this.onTornDown();
  }
}

/** Process-global fan-out registry keyed by handle. */
const fanOutCache = new Map<number, HandleFanOut>();

function fanOutTransportFor(handle: number): VoiceAgentStreamTransport {
  return {
    subscribe(_req, onMessage, onError, onDone) {
      let fan = fanOutCache.get(handle);
      if (!fan) {
        fan = new HandleFanOut(handle, () => fanOutCache.delete(handle));
        fanOutCache.set(handle, fan);
      }

      const sub: Subscriber = { onMessage, onError, onDone };
      const cancel = fan.attach(sub);
      if (!cancel) {
        onError(new Error(
          `NitroVoiceAgent.subscribeProtoEvents failed for handle ${handle}`,
        ));
        onDone();
        return () => { /* already torn down by attach() failure */ };
      }
      return cancel;
    },
  };
}

// ---------------------------------------------------------------------------
// Public adapter
// ---------------------------------------------------------------------------

/**
 * Adapter that exposes the C++ proto-byte voice agent callback as a
 * standard JS AsyncIterable. Multiple concurrent `stream()` calls share
 * one Nitro subscription via per-handle fan-out, matching Swift
 * `HandleStreamAdapter`, Kotlin `HandleStreamAdapter`, Flutter
 * `_VoiceFanOutRegistry`, and Web `HandleFanOut`.
 */
export class VoiceAgentStreamAdapter {
  constructor(private readonly handle: number) {}

  stream(req: VoiceAgentRequest = VoiceAgentRequest.fromPartial({ eventFilter: '' })): AsyncIterable<VoiceEvent> {
    return streamVoiceAgent(fanOutTransportFor(this.handle), req);
  }
}

// ---------------------------------------------------------------------------
// Test-only export — mirrors Web __testing__ for unit-test invariant checks.
// ---------------------------------------------------------------------------

/** @internal — for tests only. Do not use in application code. */
export const __testing__ = {
  fanOutTransportFor,
};
