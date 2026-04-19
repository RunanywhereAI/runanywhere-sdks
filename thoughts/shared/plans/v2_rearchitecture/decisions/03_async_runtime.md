# Decision 03 — Async runtime per platform

## Question

What threading primitive does the graph scheduler use to run one node
per worker thread?

## Choice

Platform-conditional at compile time:

- **macOS, Linux, Android, Windows**: `std::jthread`.
- **iOS**: GCD (`DispatchQueue`).
- **WASM**: Emscripten asyncify (via `emscripten_sleep` on the main
  thread, or a `pthread` worker when
  `-s USE_PTHREADS=1 -s PTHREAD_POOL_SIZE=N` is enabled).

## Alternatives considered

| Option | Why rejected |
| --- | --- |
| `std::thread` everywhere | Works on iOS but the thread isn't tracked by the OS scheduler; background-state app gets its threads killed without notice |
| `std::async(std::launch::async, ...)` | No cancellation story; non-deterministic worker pool behaviour |
| Boost.Asio / libuv | Extra dependency; we'd inherit their build system quirks |
| Hand-rolled thread pool | Not worth the code |
| Pure callback-based / reactive | Defeats the point of having a graph |

## Reasoning

- `std::jthread` has `request_stop()` built in — pairs naturally with
  our `CancelToken`. Default pick where we have it.
- iOS `std::thread` / `std::jthread` doesn't integrate with GCD's QoS
  or the app lifecycle. Using GCD keeps the voice agent alive through
  app state transitions (e.g. screen lock with audio active) and lets
  the OS prioritise audio work.
- WASM has no real threads on the main browser thread; asyncify is the
  pragmatic choice, and we can still spawn pthreads for workers when
  the host supports SharedArrayBuffer.

The runtime difference is contained inside
`sdk/runanywhere-commons/src/graph/graph_scheduler_*.cpp` with a
single selector in `graph_scheduler.cpp`. Nothing above the scheduler
layer sees the difference.

## Implications

- `GraphScheduler` has three source files and one public header.
- Cancellation model is unified: a `CancelToken` shared_ptr is handed
  into each node at start; nodes loop on `!cancel->is_cancelled()`.
- iOS runtime uses a `DispatchQueue` per node; the queue is suspended
  on pause and resumed on play.
- WASM can run a subset of the graph on the main thread under
  asyncify when workers are unavailable.

Covered by Phase 0 (primitive definitions) and surfaced in Phase 3
(voice agent) / Phase 4 (RAG parallel search).
