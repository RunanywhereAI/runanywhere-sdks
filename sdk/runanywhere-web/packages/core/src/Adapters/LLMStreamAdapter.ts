/**
 * LLMStreamAdapter.ts (Web / WASM)
 *
 * v2 close-out Phase G-2 — see docs/v2_closeout_phase_g2_report.md.
 *
 * Wraps an Emscripten Module.addFunction() callback as an
 * `AsyncIterable<LLMStreamEvent>` using the codegen'd transport wrapper
 * from `idl/codegen/templates/ts_async_iterable.njk`. Mirrors
 * `VoiceAgentStreamAdapter.ts` (Web) — same fan-out shape, different
 * C ABI (`rac_llm_set_stream_proto_callback` instead of
 * `rac_voice_agent_set_proto_callback`).
 *
 * This is the unified LLM streaming path for the Web SDK. Any hand-
 * rolled `tokenQueue` / `Emscripten callback → string` plumbing in
 * example apps should be migrated to iterate this adapter.
 *
 * Cancellation: `AsyncIterator.return()` (triggered by `for-await break`)
 * calls the cancel function, which removes the subscriber from the
 * fan-out set and — if it was the last — tears down the Emscripten
 * function-table entry and clears the C slot via
 * `_rac_llm_unset_stream_proto_callback`.
 *
 * Multi-collector fan-out:
 *   The underlying C ABI exposes a SINGLE proto-callback slot per
 *   handle. A per-handle subscriber set installs ONE Emscripten
 *   trampoline for the lifetime of the first-through-last subscriber.
 */

import type { LLMGenerateRequest } from '@runanywhere/proto-ts/llm_service';
import { LLMStreamEvent } from '@runanywhere/proto-ts/llm_service';
import type { LLMStreamTransport } from '@runanywhere/proto-ts/streams/llm_service_stream';
import { generateLLM } from '@runanywhere/proto-ts/streams/llm_service_stream';
import {
  runanywhereModule,
  type EmscriptenRunanywhereModule,
} from '../runtime/EmscriptenModule';

/**
 * Adapter that exposes the C++ proto-byte LLM stream callback as a
 * standard JS AsyncIterable. Construct with either:
 *
 *   1. `new LLMStreamAdapter(handle, module?)` — WASM path. `handle`
 *      is an opaque pointer returned from the backend package's
 *      `_rac_llm_component_create*` thunk. The optional `module` arg
 *      lets backend packages (e.g. `@runanywhere/web-llamacpp`) pass
 *      their own Emscripten module instance directly — the global
 *      `runanywhereModule` singleton is only used when no module is
 *      supplied (test harnesses / future single-module deployments).
 *
 *      Why optional `module`? Backend packages (llamacpp, onnx) load
 *      independent Emscripten modules and do not call
 *      `setRunanywhereModule()` (each backend may export a different
 *      symbol surface, so a singleton is the wrong abstraction for
 *      multi-WASM deployments). Allowing an explicit module reference
 *      keeps the adapter usable from backend `RunAnywhere+*.ts`
 *      extensions without coupling them to the singleton.
 *
 *   2. `new LLMStreamAdapter(transport)` — custom transport path for
 *      unit tests that inject a fake transport satisfying the codegen'd
 *      [`LLMStreamTransport`] contract.
 */
export class LLMStreamAdapter {
  private readonly transportImpl: LLMStreamTransport;

  constructor(
    handleOrTransport: number | LLMStreamTransport,
    module: EmscriptenRunanywhereModule = runanywhereModule,
  ) {
    this.transportImpl =
      typeof handleOrTransport === 'number'
        ? fanOutTransportFor(handleOrTransport, module)
        : handleOrTransport;
  }

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
    return generateLLM(this.transportImpl, req);
  }
}

// ---------------------------------------------------------------------------
// WASM transport — parity with voice-agent adapter.
// Routes `rac_llm_set_stream_proto_callback(handle, cb, user_data)` through
// the codegen'd `generateLLM` wrapper.
// ---------------------------------------------------------------------------

interface Subscriber {
  onMessage: (e: LLMStreamEvent) => void;
  onError:   (err: Error) => void;
  onDone:    () => void;
}

class HandleFanOut {
  readonly subscribers = new Set<Subscriber>();

  private cbPtr = 0;
  private installed = false;

  constructor(
    private readonly handle: number,
    private readonly module: EmscriptenRunanywhereModule,
    private readonly onTornDown: () => void,
  ) {}

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
    const cbPtr = m.addFunction(
      (bytesPtr: number, bytesLen: number, _userData: number) => {
        if (bytesPtr === 0 || bytesLen <= 0) return;

        let bytes: Uint8Array;
        try {
          bytes = new Uint8Array(m.HEAPU8.buffer, bytesPtr, bytesLen).slice();
        } catch (e) {
          this.broadcastError(e);
          return;
        }

        let event: LLMStreamEvent;
        try {
          event = LLMStreamEvent.decode(bytes);
        } catch (e) {
          this.broadcastError(e);
          return;
        }

        const snapshot = Array.from(this.subscribers);
        for (const s of snapshot) {
          try {
            s.onMessage(event);
            if (event.isFinal) {
              try { s.onDone(); } catch { /* swallow */ }
              this.subscribers.delete(s);
            }
          } catch (e) {
            try { s.onError(e instanceof Error ? e : new Error(String(e))); }
            catch { /* swallow */ }
            this.subscribers.delete(s);
          }
        }
        if (event.isFinal && this.subscribers.size === 0) {
          this.tearDown();
        }
      },
      'viii',
    );

    const rc = m._rac_llm_set_stream_proto_callback(this.handle, cbPtr, 0);
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
    try { m._rac_llm_unset_stream_proto_callback(this.handle); } catch { /* swallow */ }
    try { m.removeFunction(this.cbPtr); } catch { /* swallow */ }
    this.cbPtr = 0;
    this.installed = false;
    this.onTornDown();
  }
}

const fanOutCache = new WeakMap<EmscriptenRunanywhereModule, Map<number, HandleFanOut>>();

function fanOutTransportFor(
  handle: number,
  module: EmscriptenRunanywhereModule,
): LLMStreamTransport {
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
          `rac_llm_set_stream_proto_callback failed ` +
          `(Protobuf may not be linked into the wasm module)`
        ));
        onDone();
        return () => { /* already torn down by attach() failure */ };
      }
      return cancel;
    },
  };
}

/** @internal — for tests only. */
export const __testing__ = {
  fanOutTransportFor,
};
