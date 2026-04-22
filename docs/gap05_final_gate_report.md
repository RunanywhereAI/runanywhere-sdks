# GAP 05 — DAG Runtime · Final Gate Report

_Closed in v3.1 Phase 9._

## Spec criteria status

Per [GAP_05_DAG_RUNTIME.md](../v2_gap_specs/GAP_05_DAG_RUNTIME.md)
L62, only 3 primitives were deemed to have real value:

| # | Primitive | Status | Evidence |
|---|---|---|---|
| 1 | `CancelToken` | **OK** | `include/rac/graph/cancel_token.hpp` + 5 tests |
| 2 | `RingBuffer<T>` | **OK** | `include/rac/graph/ring_buffer.hpp` + 3 tests (incl. concurrent SPSC @ 10k items) |
| 3 | `StreamEdge<T>` | **OK** | `include/rac/graph/stream_edge.hpp` + 5 tests (all 3 overflow policies + cancel + close + parallel stress) |

## Deliberately deferred (per spec L63-64)

| # | Primitive | Status | Rationale |
|---|---|---|---|
| 4 | `GraphScheduler` | DEFERRED | Needs ≥2 concrete pipelines to validate the scheduler design. Only voice-agent exists today. |
| 5 | `PipelineNode` | DEFERRED | Pre-deployed base class would constrain future node shapes without load-bearing benefit. |
| 6 | `MemoryPool` | DEFERRED | Standard allocator covers the current perf profile; pool matters when reusable buffer reuse is a hot path. |

## Test evidence

```sh
$ cmake --build build/macos-release --target test_graph_primitives
$ ./build/macos-release/sdk/runanywhere-commons/tests/test_graph_primitives
13 test(s) passed, 0 test(s) failed
```

Test coverage:
- CancelToken: basic, parent-child cascade, born-cancelled,
  grandchild cascade, multi-threaded cancel
- RingBuffer: push-pop, wrap-around, concurrent SPSC (10k items)
- StreamEdge: DropNewest, DropOldest, BlockProducer + cancel,
  close unblocks consumer, producer-consumer parallel (1k items)

## Documentation

[`docs/graph_primitives.md`](graph_primitives.md) — when-to-use
guide, API walkthrough, integration notes, ABI stability note.

## Integration

Zero first-party consumers today (by design — the spec's expectation).
The primitives are available to new pipelines. Wiring into
`voice_pipeline.cpp` is explicitly held off per spec L63-64 until a
second pipeline needs them.

## Result

**GAP 05 CLOSED** as "skeleton shipped, scheduler deferred per spec".
