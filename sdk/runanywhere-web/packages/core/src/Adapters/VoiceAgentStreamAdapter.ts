/**
 * VoiceAgentStreamAdapter.ts (Web / WASM)
 *
 * GAP 09 Phase 19 — see v2_gap_specs/GAP_09_STREAMING_CONSISTENCY.md.
 *
 * Wraps an Emscripten Module.addFunction() callback as an
 * `AsyncIterable<VoiceEvent>` using the codegen'd transport wrapper
 * from `idl/codegen/templates/ts_async_iterable.njk` (Phase 14).
 *
 * Cancellation: `AsyncIterator.return()` (triggered by `for-await break`)
 * calls our cancel function, which removes the subscriber from the
 * fan-out set and, if it was the last subscriber, tears down the
 * Emscripten function table entry and tells C++ to clear the callback slot.
 *
 * Multi-collector fan-out (B29):
 *   The underlying C ABI exposes a SINGLE proto-callback slot per handle.
 *   Without fan-out, a second `stream()` collector silently replaces the
 *   first by re-calling `_rac_voice_agent_set_proto_callback(handle, cbPtr, 0)`.
 *   To preserve AsyncIterable fan-out semantics we keep a per-handle
 *   subscriber set and install ONE Emscripten trampoline for the lifetime
 *   of the first-through-last subscriber.
 */

import type { VoiceAgentRequest } from '../generated/voice_agent_service';
import { VoiceEvent } from '../generated/voice_events';
import type { VoiceAgentStreamTransport } from '../generated/streams/voice_agent_service_stream';
import { streamVoiceAgent } from '../generated/streams/voice_agent_service_stream';
import {
  runanywhereModule,
  type EmscriptenRunanywhereModule,
} from '../runtime/EmscriptenModule';

/**
 * Adapter that exposes the C++ proto-byte voice agent callback as a
 * standard JS AsyncIterable. Construct with either:
 *
 *   1. `new VoiceAgentStreamAdapter(handle)` — WASM path. `handle` is an
 *      opaque pointer returned from the backend package's
 *      `_rac_voice_agent_create*` thunk. This is the canonical path,
 *      parity with iOS / Android / Flutter / React Native.
 *
 *   2. `new VoiceAgentStreamAdapter(transport)` — custom transport path.
 *      Useful for apps that drive a TS-side orchestrator (e.g.
 *      [`VoicePipeline`]) and want to emit `VoiceEvent`s, or for unit
 *      tests that inject a fake transport. The transport must satisfy
 *      the codegen'd [`VoiceAgentStreamTransport`] contract.
 *
 * When constructed from a `handle`, multiple `.stream()` collectors on
 * the same adapter share a single C callback registration (per-handle
 * fan-out). When constructed from a `transport`, fan-out semantics are
 * delegated to the caller-supplied transport.
 */
export class VoiceAgentStreamAdapter {
  private readonly transportImpl: VoiceAgentStreamTransport;

  constructor(handleOrTransport: number | VoiceAgentStreamTransport) {
    this.transportImpl =
      typeof handleOrTransport === 'number'
        ? fanOutTransportFor(handleOrTransport, runanywhereModule)
        : handleOrTransport;
  }

  stream(req: VoiceAgentRequest = { eventFilter: '' }): AsyncIterable<VoiceEvent> {
    return streamVoiceAgent(this.transportImpl, req);
  }
}

// ---------------------------------------------------------------------------
// WASM transport — parity with iOS / Android / Flutter / RN proto-stream path.
// Routes the C++ `rac_voice_agent_set_proto_callback(handle, cb, user_data)`
// entrypoint through the codegen'd `streamVoiceAgent` wrapper.
//
// Fan-out: one Emscripten trampoline per handle broadcasts every decoded
// VoiceEvent to every AsyncIterable subscribed to that handle. The
// trampoline is installed lazily on first subscriber and torn down when
// the last subscriber cancels.
// ---------------------------------------------------------------------------

interface Subscriber {
  onMessage: (e: VoiceEvent) => void;
  onError:   (err: Error) => void;
  onDone:    () => void;
}

/**
 * Per-handle fan-out state. Holds the active Emscripten function pointer,
 * the current subscriber set, and a reference back to the module so
 * tear-down can null the C slot.
 */
class HandleFanOut {
  readonly subscribers = new Set<Subscriber>();

  private cbPtr = 0;
  private installed = false;

  constructor(
    private readonly handle: number,
    private readonly module: EmscriptenRunanywhereModule,
    private readonly onTornDown: () => void,
  ) {}

  /**
   * Attach a subscriber. Installs the shared trampoline on first attach;
   * returns a cancel function that removes the subscriber (and tears the
   * trampoline down when the last one leaves).
   *
   * Returns `null` if first-time installation failed — in that case the
   * caller should surface the error to its own AsyncIterable.
   */
  attach(sub: Subscriber): (() => void) | null {
    if (!this.installed) {
      const ok = this.installTrampoline();
      if (!ok) return null;
    }
    this.subscribers.add(sub);
    return () => this.detach(sub);
  }

  private installTrampoline(): boolean {
    const m = this.module;
    // Allocate a JS function pointer in the Emscripten function table.
    // The C signature is `(uint8_t*, size_t, void*) -> void`, encoded as
    // 'viii' (3 i32 args, void return).
    const cbPtr = m.addFunction(
      (bytesPtr: number, bytesLen: number, _userData: number) => {
        if (bytesPtr === 0 || bytesLen <= 0) return;
        // Copy off the WASM heap (the buffer is invalidated when this
        // callback returns; the proto deserializer keeps no reference
        // to the original memory).
        let bytes: Uint8Array;
        try {
          bytes = new Uint8Array(m.HEAPU8.buffer, bytesPtr, bytesLen).slice();
        } catch (e) {
          this.broadcastError(e);
          return;
        }

        let event: VoiceEvent;
        try {
          event = VoiceEvent.decode(bytes);
        } catch (e) {
          this.broadcastError(e);
          return;
        }

        // Iterate over a snapshot so a subscriber that cancels in its
        // onMessage handler cannot mutate the set underneath us.
        const snapshot = Array.from(this.subscribers);
        for (const s of snapshot) {
          try {
            s.onMessage(event);
          } catch (e) {
            // Deliver the throw to *that* subscriber only; don't let a
            // misbehaving collector starve its peers.
            try { s.onError(e instanceof Error ? e : new Error(String(e))); }
            catch { /* swallow */ }
            this.subscribers.delete(s);
          }
        }
      },
      'viii',
    );

    const rc = m._rac_voice_agent_set_proto_callback(this.handle, cbPtr, 0);
    if (rc !== 0) {
      m.removeFunction(cbPtr);
      return false;
    }
    this.cbPtr = cbPtr;
    this.installed = true;
    return true;
  }

  private broadcastError(e: unknown) {
    const err = e instanceof Error ? e : new Error(String(e));
    for (const s of Array.from(this.subscribers)) {
      try { s.onError(err); } catch { /* swallow */ }
    }
    // An error invalidates the stream for everyone; drop the set.
    this.subscribers.clear();
    this.tearDown();
  }

  private detach(sub: Subscriber): void {
    this.subscribers.delete(sub);
    if (this.subscribers.size === 0) {
      this.tearDown();
    }
  }

  private tearDown(): void {
    if (!this.installed) return;
    const m = this.module;
    try { m._rac_voice_agent_set_proto_callback(this.handle, 0, 0); } catch { /* swallow */ }
    try { m.removeFunction(this.cbPtr); } catch { /* swallow */ }
    this.cbPtr = 0;
    this.installed = false;
    this.onTornDown();
  }
}

/**
 * Keyed by `${handle}::${module-identity}` so test modules and production
 * modules never cross-contaminate, even if they share a handle value.
 */
const fanOutCache = new WeakMap<EmscriptenRunanywhereModule, Map<number, HandleFanOut>>();

function fanOutTransportFor(
  handle: number,
  module: EmscriptenRunanywhereModule,
): VoiceAgentStreamTransport {
  return {
    subscribe(_req, onMessage, onError, onDone) {
      let perModule = fanOutCache.get(module);
      if (!perModule) {
        perModule = new Map();
        fanOutCache.set(module, perModule);
      }
      let fan = perModule.get(handle);
      if (!fan) {
        const captured = perModule;
        fan = new HandleFanOut(handle, module, () => captured.delete(handle));
        perModule.set(handle, fan);
      }

      const sub: Subscriber = { onMessage, onError, onDone };
      const cancel = fan.attach(sub);
      if (!cancel) {
        onError(new Error(
          `rac_voice_agent_set_proto_callback failed ` +
          `(Protobuf may not be linked into the wasm module)`
        ));
        onDone();
        return () => { /* already torn down by attach() failure */ };
      }
      return cancel;
    },
  };
}

// ---------------------------------------------------------------------------
// Test-only export — surfaces the fan-out transport so unit tests can
// verify single-installation invariants without going through the
// adapter constructor (which would require a real Emscripten module).
// ---------------------------------------------------------------------------

/** @internal — for tests only. Do not use in application code. */
export const __testing__ = {
  fanOutTransportFor,
};
