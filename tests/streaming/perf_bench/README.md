# Streaming p50 Latency Bench Harness

> **Closes**: GAP 09 #8 measurement infrastructure (the spec criterion
> `p50 ≤ 1ms across 5 SDKs`). Per-SDK CI runner integration is a v2.1
> follow-up — this PR ships the harness; another PR wires it into
> XCTest / JUnit / Jest / `flutter test` / Vitest runners that load
> built native libraries.
>
> Status: **harness shipped**, **per-SDK runner integration deferred**.

## Why a separate harness from `parity_test.cpp`

`parity_test.cpp` (GAP 09 Phase 4) emits a deterministic 8-event
sequence and verifies byte-for-byte wire-format parity across 6
implementations of `VoiceEvent`. That answers "do all SDKs decode the
same bytes the same way?" — the **correctness** question.

`perf_producer.cpp` here emits 10,000 events as fast as
`dispatch_proto_event()` can serialize them, with each event
embedding a high-resolution producer-side timestamp in the
`metrics.created_at_ns` proto field. Per-SDK consumers record the
delta between `created_at_ns` and their decode-completion timestamp,
which answers "how fast does each SDK turn a proto-byte event into a
native object?" — the **performance** question.

## Architecture

```
+-----------------+     proto bytes    +---------------------+
| perf_producer   |  ----------------> | per-SDK consumer    |
| (C++)           |   (10k events)     | (Swift/Kt/Dart/TS)  |
| - emits N evts  |                    | - decodes each event|
| - timestamps in |                    | - records delta_ns  |
|   metrics field |                    | - writes to log     |
+-----------------+                    +---------------------+
                                                 |
                                                 v
                                       +----------------------+
                                       | compute_percentiles  |
                                       | (Python aggregator)  |
                                       | - p50 / p95 / p99    |
                                       | - asserts p50 < 1ms  |
                                       +----------------------+
```

## Files in this directory

| File | Role | Status |
|------|------|--------|
| `README.md` | This document | shipped |
| `perf_producer.cpp` | C++ harness; emits N=10000 timestamped events | shipped + buildable |
| `perf_bench.swift` | Swift consumer scaffold | shipped (not wired to XCTest yet) |
| `perf_bench.kt` | Kotlin consumer scaffold | shipped (not wired to JUnit yet) |
| `perf_bench.dart` | Dart consumer scaffold | shipped (not wired to `flutter test` yet) |
| `perf_bench.ts` | RN/Web consumer scaffold (single source) | shipped (not wired to Jest/Vitest yet) |
| `compute_percentiles.py` | Aggregator: reads N timestamp logs, prints p50/p95/p99 | shipped + runnable |

## Methodology

1. **Producer** (`perf_producer.cpp`):
   - Iterates 1..N (default N=10000).
   - For each iteration, sets `voice_event.metrics.created_at_ns` to the current monotonic-clock timestamp.
   - Calls `rac::voice_agent::dispatch_proto_event()` which serializes to proto bytes and invokes the registered callback.
   - The callback writes the bytes + the producer timestamp to a per-event line in the output file.

2. **Consumer** (per SDK, ~80-120 LOC each):
   - Subscribes to `VoiceAgentStreamAdapter` (already shipped from GAP 09 Phase 16-19).
   - For each event received: parse, read `metrics.created_at_ns`, compute `now() - created_at_ns`, append delta_ns to a per-SDK log file.
   - Per-event work: proto decode + delta computation only — no UI updates, no logging, no allocations beyond the parser's.

3. **Aggregator** (`compute_percentiles.py`):
   - Reads each `/tmp/perf_bench.<sdk>.log`.
   - Sorts the deltas; prints p50, p95, p99, max, and event count.
   - Asserts `p50_ns < 1_000_000` (= 1 ms) per the spec.
   - Writes a summary table to `/tmp/perf_bench.summary.md`.

## Expected latencies (rough estimates, to be measured)

| SDK | Expected p50 | Why |
|-----|--------------|-----|
| Swift | < 100 µs | swift-protobuf is mature, no JNI hop |
| Kotlin | < 500 µs | Wire is fast but JNI marshal adds overhead |
| Dart | < 500 µs | protoc_plugin codegen + dart:ffi callback hop |
| RN | < 1 ms | Nitro Module HybridObject + JSI marshalling |
| Web | < 1 ms | Emscripten Module.addFunction + ts-proto |

If any SDK exceeds 1 ms p50, the spec criterion fails — that's a
performance bug to investigate, not the harness's fault.

## Running locally (after per-SDK runner integration)

```bash
# 1. Build the C++ producer
cmake --build build/macos-release --target perf_producer

# 2. Generate the input event stream (writes /tmp/perf_input.bin)
./build/macos-release/tests/streaming/perf_bench/perf_producer \
    --emit-binary /tmp/perf_input.bin

# 3. Run each per-SDK consumer (NOT YET INTEGRATED — v2.1-2 follow-up)
#    Each writes /tmp/perf_bench.<sdk>.log
swift test --filter PerfBenchTests
./gradlew :commonTest --tests PerfBench
flutter test test/perf_bench_test.dart
yarn test perf_bench

# 4. Aggregate
python3 tests/streaming/perf_bench/compute_percentiles.py \
    /tmp/perf_bench.swift.log \
    /tmp/perf_bench.kt.log \
    /tmp/perf_bench.dart.log \
    /tmp/perf_bench.rn.log \
    /tmp/perf_bench.web.log
# Output: /tmp/perf_bench.summary.md
```

## Why "skeleton" not "shippable"

This PR delivers **the harness** but not **the per-SDK CI runner
integration** that would actually execute the benches against built
native libraries. That integration is the v2.1-2 follow-up because:

- Each SDK has a different test runner with different native-library
  loading semantics (Swift Package Manager + xcconfig, Gradle Android
  + JNI, `flutter test` + `dart:ffi` shared lib resolution, Jest +
  Nitro Module mock vs real, Vitest + Emscripten WASM module load).
- Wiring all 5 reliably is ~1 week of CI infra work, distinct from
  writing the bench logic itself.

After v2.1-2 lands, this harness is the canonical proof that
GAP 09 #8 is met (or which SDK fails it).
