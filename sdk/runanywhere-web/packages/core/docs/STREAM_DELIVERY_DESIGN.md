# Web Stream Delivery — Architecture & Roadmap

Owner: Web Core / Adapters
Status: T3.1 MVP shipped; T6.1 Worker path landed (DECISION-3 Option A)
Surface: `streamCallback` in `src/Adapters/ProtoAdapterTypes.ts` +
`OffscreenRuntimeBridge` in `src/runtime/OffscreenRuntimeBridge.ts`
Consumers: `LLMProtoAdapter`, `STTProtoAdapter`, `TTSProtoAdapter`,
`VLMProtoAdapter`, `DiffusionProtoAdapter` (any modality with a
`_rac_*_stream_proto` Emscripten export)

## Problem statement

Every Web modality stream — LLM tokens, STT partials, TTS chunks, VAD
events, VLM tokens, diffusion progress — is driven by an Emscripten
export of the form:

```c
int _rac_<modality>_<op>_stream_proto(
    /* request args… */,
    void (*cb)(const uint8_t* bytes, size_t size),
    void* user_data);
```

The export is **synchronous**: the JS thread enters native code, the
native loop emits N proto-encoded events back through the JS callback,
the export returns, then JS regains control. The consumer's
`AsyncIterable.next()` microtask cannot run while the export is on the
stack — every event the consumer sees was buffered inside the export's
synchronous frame.

Earlier waves of work fixed two adjacent problems:

1. **Handle observability** — `streamCallback` defers the blocking
   native call onto a fresh microtask via `queueMicrotask`, so
   `await generateStream(...)` resolves its handle **before** native
   generation begins. ([HOTSPOT-WEB-CORE-002 / WEB-CORE-001])
2. **Cancellation interleaving** — because the call is deferred, the
   consumer's `iterator.return()` (or facade `cancel()`) can reach the
   `onCancel` hook before the blocking export starts, killing tests
   that latch on a deferred signal.

What the previous waves explicitly did **not** fix is **live token
delivery during the native call**. The consumer still observes every
event only **after** the export returns. For long-running LLM streams
this manifests as bursty UI updates and a measurable lag between
"native is producing" and "consumer sees a token".

## What shipped in T6.1 (Worker path landed)

T6.1 picks DECISION-3 Option A from the roadmap below and ships it
behind a runtime feature flag. The synchronous main-thread path is
preserved verbatim so non-Worker callers (and the existing T3.1
test fakes) keep working.

### Change set (T6.1)

- New singleton `OffscreenRuntimeBridge` (`src/runtime/OffscreenRuntimeBridge.ts`)
  spawns a Web Worker on first use and routes per-call streaming
  requests (`stream.llm.generate`, `stream.stt.transcribe`,
  `stream.tts.synthesize`, `stream.vlm.process`) over a typed
  discriminated-union message protocol defined in
  `src/runtime/StreamWorker.ts`.
- `StreamWorker.ts` doubles as (a) the wire protocol types
  (`WorkerRequest` / `WorkerResponse`, imported via `import type` by
  the bridge so no worker runtime leaks into the main bundle) and
  (b) the worker-thread dispatch (`runStreamWorker`,
  `registerStreamModuleFactory`).
- `StreamWorkerFactoryRegistry.ts` exposes `setStreamWorkerFactory(fn)`.
  Core's worker orchestration stays bundler-neutral — backend-specific
  `new Worker(new URL(...))` construction lives in `@runanywhere/web-llamacpp` and
  `@runanywhere/web-onnx`. When no factory is registered, every
  adapter `*Stream` method transparently falls back to the
  T3.1 main-thread `queueMicrotask` path.
- `Runtime.streamingMode: 'auto' | 'worker' | 'main'` (default
  `'auto'`) added to `RuntimeConfig.ts`. Apps can force the
  Worker path or pin to the legacy main path for A/B perf testing.
- `LLMProtoAdapter.generateStream`, `STTProtoAdapter.transcribeStream`,
  `TTSProtoAdapter.synthesizeStream`, and `VLMProtoAdapter.streamEvents`
  consult `OffscreenRuntimeBridge.tryGet()` first; if non-null they
  route via the bridge, otherwise they call `streamCallback` exactly
  as before. The AsyncIterable contract is byte-identical from the
  consumer's perspective.

### Trade-offs explicitly accepted (T6.1)

- **~2× memory for streaming WASM** — the worker maintains its own
  Emscripten module instance for streaming exports only. Non-streaming
  exports stay on the main-thread `EmscriptenModule` singleton.
  Mirroring the full module simplifies the contract (no per-call
  marshalling of state across the boundary) at the cost of duplicated
  WASM linear memory + code section. Measured against the live
  delivery win this is the smaller cost.
- **Slot-based callbacks excluded** — `VAD activity` callback (set
  once via `_rac_vad_component_set_activity_proto_callback`, fires
  many times across separate `process` calls) and `VoiceAgentStreamAdapter`
  (subscribe-once, fan-out fanout via `_rac_voice_agent_set_proto_callback`)
  are NOT routed through the Worker path. They don't fit the per-call
  request/response message pattern and would need a different
  "channel" abstraction. Tracked as a follow-up; not in T6.1.
- **Deep cancel for VLM** — the worker `cancel` handler pokes
  `_rac_llm_cancel_proto` but has no per-requestId handle bookkeeping
  for VLM (`_rac_vlm_cancel_proto` takes a handle the worker doesn't
  retain). Consumer-side cancellation is still deterministic — the
  bridge ends the iterator immediately — but C-side compute may
  continue to drain to completion. Follow-up: track outstanding
  handles in the worker so `cancel` can call the matching verb.

### Test coverage (T6.1)

`tests/unit/runtime/StreamWorker.test.ts` (Vitest, node env, fake
Worker via `setStreamWorkerFactory`):
- `Worker mode delivers first callback before done` — the central
  invariant: the consumer iterator observes the first decoded event
  BEFORE the worker has posted its terminating `done` message.
- `cancel() interrupts mid-stream` — after the consumer breaks the
  for-await loop, the bridge posts `{type:'cancel', requestId}` to
  the worker, the iterator immediately reports `done: true`, and any
  in-flight `callback` messages for the cancelled requestId are
  dropped before reaching the consumer.
- `falls back to main-thread when no factory registered` — exercises
  the T3.1 `streamCallback` path to verify the Worker switch is
  truly opt-in and the legacy path stays correct.

Test env note: DECISION-7 called for `environment: 'happy-dom'`
+ a `worker_threads`-backed shim. The agent sandbox in which T6.1
landed couldn't install `happy-dom` (npm cache `EACCES`), so the
test keeps Vitest's `node` env. The Worker dependency is injected
via the factory and never reaches a real `Worker` constructor, so
the env choice doesn't affect what's asserted. Inline in the test
file in case the next reader wonders.

## What shipped earlier in T3.1

A minimum-viable, lower-risk change focused on **unlocking** live
delivery without rewriting any caller.

### Change set

- `streamCallback`'s `call` parameter now accepts
  `(callbackPtr: number) => number | Promise<number>` (was: `number`).
- `runNativeCall` is now `async` and `await`s the `call` result. A sync
  wrapper (`return 0`) still works — `await 0` is one microtask hop.
- New exported helper `streamYield()` returns a microtask-resolved
  `Promise<void>` for cooperative wrappers to await between batches.
- New constant `DEFAULT_STREAM_YIELD_EVERY = 16` documents the default
  batch size used by the internal callback-yield counter.
- The `emit` path increments an `emitsSinceYield` counter and posts an
  empty microtask barrier every `yieldEvery` emissions. The barrier is
  observable by async wrappers via `await streamYield()` and is a no-op
  for purely synchronous wrappers (a sync JS frame cannot be preempted
  from inside `emit`).

### What this unlocks

- **Tests today** can simulate live delivery by writing an async
  wrapper that interleaves `emitValue(...)` with `await streamYield()`.
  See `tests/unit/Adapters/StreamLiveDelivery.test.ts` — the
  "delivers the first event BEFORE the async wrapper Promise resolves"
  test directly asserts the previously-unreachable contract.
- **Asyncify / Web Worker backends tomorrow** plug in by exposing
  their native call as an async wrapper — `streamCallback` requires
  zero further change.
- **Every existing caller** keeps working unchanged. The four
  production callers (LLM, STT, TTS, VLM) still pass a sync wrapper
  that returns `number`; their behaviour is byte-identical to before.

### Anti-non-goal: do NOT pretend sync exports can be preempted

The MVP deliberately does **not** claim the synchronous llamacpp /
ONNX exports now stream live. They do not — they cannot be preempted
from JS, full stop. The MVP is structural: it makes the surface ready
for the backend changes that follow, and it documents the boundary
that callers can opt into.

## Why live delivery requires a backend change

A purely synchronous Emscripten export holds the JS call stack from
entry to return. Inside that frame:

- Microtasks queued by the callback (e.g. `waiter.resolve(event)`) sit
  in the microtask queue.
- Macrotasks (`setTimeout`, network I/O, frame callbacks) are also
  blocked.
- The consumer's `await iterator.next()` continuation cannot run until
  the export returns.

No amount of JS-side cleverness changes this. The export must either
(a) be made asynchronous at the WASM boundary, or (b) run off the main
thread so the main thread's event loop is free to drain consumer
microtasks while native code executes.

## Follow-up options for true live delivery

The MVP intentionally defers the choice between three viable
backends. Each has different cost, blast radius, and tradeoffs.

### Option A — Web Worker + transferable byte queue

Move the entire Emscripten module into a dedicated worker. The main
thread holds a thin RPC client; each `_rac_*_stream_proto` export
becomes an async wrapper that:

1. Posts a `{ request, userData }` message into the worker.
2. The worker invokes the real (still-sync) export. Its callback
   serialises each event onto a `MessageChannel` (or `SharedArrayBuffer`
   ring) back to the main thread.
3. Main thread receives the message, decodes, calls `emit`.
4. Worker returns when the export returns; main thread resolves the
   wrapper Promise with the result code.

Pros:
- Native code runs on a thread that does not block the UI.
- No Emscripten rebuild required — same `.wasm` works in a worker.
- Fits cleanly behind the existing `streamCallback` contract — the
  wrapper is just async.
- SharedArrayBuffer ring buffer avoids per-event `postMessage` cost.

Cons:
- Requires the example app to ship cross-origin isolation headers
  (already required for SAB and WebGPU).
- Worker bootstrap cost on first use (~10–50 ms cold path).
- Doubles peak memory if the WASM module is large (model weights live
  in the worker).
- Callback trampolines that need the host-thread GC graph
  (`addFunction` with a closure) need an extra trip through the RPC
  layer.

### Option B — Emscripten Asyncify

Re-compile RACommons with `-sASYNCIFY=1` and instrument the
`_rac_*_stream_proto` exports to call a JS-provided async yield helper
after every N emissions. Asyncify transforms the C code so the export
can `await` a JS Promise mid-execution, unwinding the C stack and
restoring it when the Promise resolves.

Pros:
- Native call runs on the main thread (no worker dance, no SAB
  required, no extra memory).
- The async wrapper signature `streamCallback` now accepts maps 1:1
  onto the Asyncified export.
- Cancellation semantics are simpler — the JS host pauses native code
  on every yield, so a flag check between batches truly preempts.

Cons:
- **Significant** binary size cost (~10–30% bloat for the modalities
  that touch the streaming path).
- **Significant** runtime cost (~5–15% slowdown on the streaming hot
  path due to the stack save/restore).
- Requires touching every C streaming entry point to insert the yield
  hook. Cross-platform discipline matters — the same C code is used
  by iOS / Android / desktop where Asyncify is irrelevant.
- Asyncify and JSPI are mutually exclusive in practice; choosing
  Asyncify now mortgages the cleaner JSPI path.

### Option C — Callback-slot ring buffer (zero-copy on main thread)

Keep the native export synchronous on the main thread, but change its
callback contract: instead of calling a JS function pointer per event,
the native code writes events into a **fixed-capacity ring buffer in
shared memory** and signals via `Atomics.notify`. The JS side drains
the ring from a `MessageChannel` `onmessage` handler that runs as a
macrotask — i.e. between native batches.

This still does not get true live delivery on the main thread because
the native call still blocks the main thread for its full duration.
The only way it would help is if combined with Option A (run native
in a worker, ring-buffer to the main thread for decode). In that
combined form it strictly dominates A on per-event cost, at the cost
of more complex memory management (ring overflow policy, back-pressure
signalling, etc.).

Pros (when combined with A):
- Zero-copy event handoff between worker and main thread.
- Constant per-event overhead regardless of event size.
- Back-pressure is explicit and observable (consumer-controlled head
  pointer).

Cons:
- Implementation complexity is materially higher than plain A.
- Requires SharedArrayBuffer (cross-origin isolation).
- Need a well-defined overflow policy — drop oldest? block native?
  emit synthetic "buffer overflow" event?

## Recommended next step

**Ship Option A first**, evaluate the cost, then decide whether to
move to A+C (ring buffer) or pivot to B (Asyncify) based on measured
data:

1. Plumb the existing modality adapters through an async-wrapper
   factory so `LLMProtoAdapter.generateStream` (and siblings) can opt
   into the worker path without touching every call site. The MVP in
   this PR already lets the adapter return an async wrapper — the
   factory just decides whether to dispatch to the worker.
2. Land the worker behind a capability flag
   (e.g. `RunAnywhere.configure({ runtime: { streamingMode: 'worker' } })`).
   Default to the legacy sync path; opt-in for canary apps and our own
   example app first.
3. Add a streaming perf benchmark to `tests/streaming/perf_bench` that
   measures first-token latency and per-token jitter for sync vs.
   worker. Use the existing C++ producer harness so the numbers are
   directly comparable across SDKs.
4. Decide between A-only, A+C, or B based on the perf data and the
   binary-size budget at the time. The decision is reversible because
   `streamCallback`'s public surface does not change.

In the meantime, **today**:
- Web SDK gets true live delivery on test fakes (this PR).
- Production traffic continues on the buffered-sync path — no
  performance or correctness regression.
- Anyone writing a new modality stream uses `streamCallback` and
  immediately benefits when the backend swap lands.

## References

- HOTSPOT-WEB-CORE-002 / WEB-CORE-001 — handle-observability defer.
- `tests/unit/Public/Extensions/RunAnywhere+TextGenerationStream.test.ts`
  — pre-existing observability + cancel coverage.
- `tests/unit/Adapters/StreamLiveDelivery.test.ts` — T3.1 coverage
  added by this PR.
- `tests/unit/Adapters/VoiceAgentStreamAdapter.fanout.test.ts` —
  fan-out coverage for the single-callback-slot adapters.
