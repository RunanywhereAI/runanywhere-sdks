# GAP 09 Streaming Parity Harness

Three test suites verify that all 5 SDKs (Swift, Kotlin, Dart, RN/TS, Web/TS)
observe the same proto-encoded `VoiceEvent` stream as the C++ producer.

## 1. Parity (event-sequence equality)

The C++ binary `parity_test_cpp` runs a deterministic event script through
the dispatcher, decodes the resulting proto bytes, and asserts the formatted
string matches the committed fixture at `fixtures/golden_events.txt`.

Per-language consumers (`parity_test.swift`, `parity_test.kt`,
`parity_test.dart`, `parity_test.ts`) read the same fixture from their own
SDK CI and assert their captured stream matches byte-for-byte
(excluding `seq` and `timestamp_us`, which are the only allowed
runtime-variable fields).

| Language    | File                       | Driver               |
|-------------|----------------------------|----------------------|
| C++ (golden producer) | `parity_test.cpp` | CTest (`parity_test_cpp_check`) — wired in `CMakeLists.txt` |
| Swift       | `parity_test.swift`        | XCTest in the swift SDK CI |
| Kotlin/JVM  | `parity_test.kt`           | JUnit in the kotlin SDK CI |
| Dart        | `parity_test.dart`         | `dart test` in the flutter SDK CI |
| TypeScript (RN) | `parity_test.ts`       | Jest in the RN core CI |

### What the C++ test does

1. Initialise a voice-agent dispatcher in-process with deterministic config
   (no real audio, no real LLM — fixed event schedule).
2. Register `rac_voice_agent_set_proto_callback` and route the proto bytes
   into a formatter that drops `seq` / `timestamp_us`.
3. Compare the formatted lines to `fixtures/golden_events.txt`.
4. `--check` mode (CTest default) fails if the runtime sequence drifts from
   the fixture; `--produce` mode rewrites the fixture (used after a
   deliberate schedule change).

### Cancellation contract

Each SDK consumer additionally verifies that:
- After cancelling the stream (Swift `task.cancel()`, Kotlin `job.cancel()`,
  Dart `subscription.cancel()`, TS `break` from `for-await`), no events
  arrive within the next 50 ms (no-stale-events).

The Phase G cross-cutting work elevates this from per-SDK CI to a
`tests/streaming/cancel_parity` aggregator (see below).

## 2. Performance (per-event latency)

`perf_bench/perf_producer.cpp` emits **N = 10000** timestamped `VoiceEvent`
frames into a binary input file. Per-SDK runners
(`perf_bench.{swift,kt,dart,ts,rn,web}.test.ts`) read the fixture, decode,
and record per-event end-to-end latency. `perf_bench/compute_percentiles.py`
aggregates the per-SDK logs into p50 / p95 / p99 and asserts **p50 < 1 ms**
(GAP 09 #8 success criterion).

CTest:
- `perf_producer_cpp` — runs the C++ producer (writes the fixture)
- `perf_aggregate` — when Python3 is available, runs the aggregator over
  whichever per-SDK logs are present in the build's perf output dir

## 3. Cancellation parity (cross-SDK ordinal agreement)

`cancel_parity/cancel_producer.cpp` emits **N = 1000** `VoiceEvent` frames
with an `InterruptedEvent(reason = APP_STOP)` injected at **index 500**.
Per-SDK consumers (`cancel_parity.{swift,kt,dart,ts,rn,web}.test.ts`)
subscribe, count events received up to the interrupt marker, call their
cancel path, and verify the stream stops within **50 ms** of the marker.
`cancel_parity/compare_cancel_traces.py` aggregates per-SDK traces and
asserts all 5 SDKs observe the cancel at the same ordinal (wire-level
parity).

CTest:
- `cancel_producer_cpp` — runs the producer
- `cancel_aggregate` — when Python3 is available, runs the comparator

## Running locally

```bash
# Configure with tests on
cmake --preset macos-debug -DRAC_BUILD_TESTS=ON
cmake --build --preset macos-debug

# Run all streaming tests
ctest --test-dir build/macos-debug -R "parity_test_cpp_check|perf_|cancel_"

# Per-SDK runners run in their own SDK CI; see each SDK's test driver.
```

## Updating the golden fixture

If you intentionally change the C-side event schedule, regenerate the
fixture and commit the diff:

```bash
./build/macos-debug/tests/streaming/parity_test_cpp --produce \
  > tests/streaming/fixtures/golden_events.txt
```

Per-SDK CIs will then re-validate against the new fixture on the next PR.
