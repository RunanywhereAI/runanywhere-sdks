/**
 * LLMStreamAdapter.ts (React Native)
 *
 * Wraps the Nitro HybridObject's per-message callback as an
 * `AsyncIterable<LLMStreamEvent>` using the same fan-out pattern as
 * VoiceAgentStreamAdapter.ts.
 *
 * Public API:
 *     for await (const evt of new LLMStreamAdapter(handle).stream(req))
 *         handleEvent(evt);
 *
 * Cancellation: standard `for-await break` triggers
 * `AsyncIterator.return()` which calls the transport's cancel function,
 * which deregisters the proto-byte callback on the C++ handle.
 *
 * Multi-collector fan-out:
 *   The underlying C ABI exposes a SINGLE proto-callback slot per handle.
 *   A per-handle `HandleFanOut` is kept in a process-global Map; one Nitro
 *   subscription is installed for the lifetime of the first-through-last
 *   subscriber. Parity with Swift `HandleStreamAdapter`, Kotlin
 *   `HandleStreamAdapter.kt`, Flutter `_LLMFanOutRegistry`, and Web
 *   `HandleFanOut/fanOutCache`.
 */

import { LLM as NitroLLM } from '../Internal/Nitro/NitroLLMSpec';
import { LLMGenerateRequest, LLMStreamEvent } from '@runanywhere/proto-ts/llm_service';
import {
  generateLLM,
  LLMStreamTransport,
} from '@runanywhere/proto-ts/streams/llm_service_stream';

// ---------------------------------------------------------------------------
// Per-handle fan-out — parity with Web HandleFanOut and Swift HandleFanOut.
// ---------------------------------------------------------------------------

interface Subscriber {
  onMessage: (e: LLMStreamEvent) => void;
  onError:   (err: Error)         => void;
  onDone:    ()                   => void;
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
      this.unsubscribeNitro = NitroLLM.subscribeProtoEvents(
        handle,
        (bytes: ArrayBuffer) => {
          let event: LLMStreamEvent;
          try {
            event = LLMStreamEvent.decode(new Uint8Array(bytes));
          } catch (e) {
            this.broadcastError(e);
            return;
          }
          this.broadcast(event);
        },
        () => {
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
    } catch {
      return false;
    }
  }

  private broadcast(event: LLMStreamEvent): void {
    const snapshot = Array.from(this.subscribers);
    for (const s of snapshot) {
      try {
        s.onMessage(event);
      } catch (e) {
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

function fanOutTransportFor(handle: number): LLMStreamTransport {
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
          `NitroLLM.subscribeProtoEvents failed for handle ${handle}`,
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
