# DAG Graph Primitives

_v3.1 Phase 9 / GAP 05. Closes the "DAG runtime skeleton" criterion
per [GAP_05_DAG_RUNTIME.md L62](../v2_gap_specs/GAP_05_DAG_RUNTIME.md)
which flagged `StreamEdge<T>`, `RingBuffer<T>`, and `CancelToken` as
"the three primitives that carry real value"._

## When to reach for these primitives

### Reach for them if you're

1. Building a NEW multi-stage pipeline where audio/events flow
   through a DAG of transforms (e.g. audio → VAD → STT → LLM → TTS).
2. Need fine-grained backpressure control between pipeline nodes
   (e.g. TTS synthesis can't keep up with LLM token generation).
3. Need cooperative cancellation that cascades through a tree of
   async operations (parent cancel → all children stop).
4. Need lock-free SPSC audio frame delivery (capture thread →
   processing thread) with no chance of producer blocking.

### Don't use them if you're

1. Wiring a single callback (just use a function pointer or lambda).
2. Using the existing hardcoded voice-agent orchestrator. That
   orchestrator works; swapping it to this DAG runtime adds cognitive
   overhead without a second-pipeline consumer.
3. Doing IPC or network streaming. These primitives are in-process
   only; use gRPC / the proto-byte callback ABI for cross-process.

## Primitives

### `CancelToken` — hierarchical cancellation

```cpp
#include "rac/graph/cancel_token.hpp"

auto parent = std::make_shared<rac::graph::CancelToken>();
auto child  = parent->create_child();

// In a pipeline node:
while (!child->is_cancelled()) {
    // ... process one frame ...
}

// User presses stop:
parent->cancel();   // child->is_cancelled() returns true
```

`is_cancelled()` is lock-free on the hot path (atomic load with acquire
semantics). `cancel()` is idempotent. Children are notified via a
thread-safe cascade. See
[`include/rac/graph/cancel_token.hpp`](../sdk/runanywhere-commons/include/rac/graph/cancel_token.hpp)
for full API.

### `RingBuffer<T>` — lock-free SPSC queue

```cpp
#include "rac/graph/ring_buffer.hpp"

rac::graph::RingBuffer<AudioFrame> rb(64);

// Producer thread (audio capture):
AudioFrame frame = capture_one_frame();
while (!rb.push(frame)) std::this_thread::yield();

// Consumer thread (STT):
AudioFrame frame;
if (rb.pop(frame)) {
    process(frame);
}
```

Wait-free on both sides when the buffer isn't full/empty. Designed for
one producer and one consumer — multi-producer / multi-consumer
scenarios need `StreamEdge` (which uses a mutex). Cache-line-aligned
head/tail atomics prevent false sharing (~30% throughput win on x86
at audio frame rates).

### `StreamEdge<T>` — bounded queue with overflow policies

```cpp
#include "rac/graph/stream_edge.hpp"

using rac::graph::StreamEdge;
using rac::graph::OverflowPolicy;

// Token stream: loss is not acceptable, block the producer instead.
StreamEdge<Token> token_edge(64, OverflowPolicy::BlockProducer);

// Transient UI updates: if the consumer is slow, drop NEW events.
StreamEdge<UIState> ui_edge(4, OverflowPolicy::DropNewest);

// Audio frames to a slow UI meter: drop the OLDEST frames.
StreamEdge<MeterSample> meter_edge(8, OverflowPolicy::DropOldest);
```

`push()` accepts an optional `CancelToken*` — `BlockProducer` honors
cancel and returns `false` when cancelled. `pop()` similarly blocks
until an item arrives OR cancel fires OR the edge is `close()`d.

## Intentional non-goals (per GAP 05 L63-64)

GAP 05 flags `GraphScheduler`, `PipelineNode`, and `MemoryPool` as
"pre-deployed dead code — build them when a second pipeline actually
needs them". v3.1 Phase 9 does NOT ship these. Reasons:

- `GraphScheduler` would need a real topology + multiple concrete
  node types to validate its design. Currently the only pipeline is
  the voice-agent, which doesn't benefit from a general scheduler.
- `PipelineNode` would become a CRTP or type-erased base that every
  node inherits; adding it now constrains future designs without
  load-bearing benefit.
- `MemoryPool` specifically for reusable buffer allocation; standard
  allocator + object reuse pattern covers the current perf profile.

Add them when the second-pipeline scenario materializes (e.g. a
diffusion pipeline or multi-model RAG graph).

## Integration notes

These primitives live in `sdk/runanywhere-commons/include/rac/graph/`
(header-only; no separate `.cpp` files). Any C++ TU within the
commons build or engine build can include them directly.

SDK frontends (Swift/Kotlin/Dart/RN/Web) can't use them directly —
they're C++-only. If a frontend needs DAG-style cancellation, use
the existing `VoiceAgentStreamAdapter` cancellation path (iterator
return → C callback deregistration) which is already wired up in
all 5 SDKs.

## Tests

[`tests/test_graph_primitives.cpp`](../sdk/runanywhere-commons/tests/test_graph_primitives.cpp)
— 13 tests covering:

- CancelToken: basic cancel, parent/child cascade, born-cancelled,
  grandchild cascade, multi-threaded cancel.
- RingBuffer: basic push/pop, wrap-around, concurrent SPSC
  (10k items at audio-frame rate).
- StreamEdge: DropNewest overflow, DropOldest overflow,
  BlockProducer + cancel, close unblocks consumer, full
  producer-consumer parallel stress (1k items).

All 13 pass as of v3.1.0.

## ABI stability

Header-only C++20. No C ABI exposed — these primitives never cross
the C boundary. If a frontend needs to cancel a C++ pipeline, the
C++ side holds a `std::shared_ptr<CancelToken>` and wires it to the
platform's cancel callback via existing mechanisms.
