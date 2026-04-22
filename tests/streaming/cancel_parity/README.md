# GAP 09 #7 — Cancellation parity harness

_v3.1 Phase 5.1. Closes the cross-SDK cancel-parity criterion._

## What it measures

1. **Wire parity** — all 5 SDKs (Swift, Kotlin, Dart, RN, Web) observe
   the same `InterruptedEvent` at the same ordinal index in the proto
   stream. Proves the adapter + decode paths don't drop or reorder
   events.

2. **Cancel latency** — each SDK stops emitting events within 50 ms
   of receiving the `InterruptedEvent`. Proves the adapter unwires
   cleanly when the C-side injects a stop signal.

## How it works

1. C++ producer (`cancel_producer.cpp`, built as
   `tests/streaming/cancel_parity/cancel_producer`) emits 1,000
   `VoiceEvent` frames into `/tmp/cancel_input.bin` with an
   `InterruptedEvent` injected at index 500.

2. Each SDK has a consumer that:
   - Reads the binary file.
   - Feeds frames one-by-one to the SDK's `VoiceAgentStreamAdapter`
     via a test double (the adapter's ABI is
     `rac_voice_agent_set_proto_callback`, so the test invokes the
     registered callback directly).
   - Records `(ordinal, payload_kind, recv_ns)` per received event
     into `/tmp/cancel_trace.<lang>.log`.
   - After receiving the `interrupted` arm, calls the SDK's cancel
     method (e.g. `Stream.cancel()` / `collector.cancel()` /
     `Subscription.cancel()` / `iterator.return()`).
   - Continues to receive any events that arrive within 50 ms.
     These extras get recorded too — the aggregator verifies there
     are zero or few of them with bounded latency.

3. `compare_cancel_traces.py` aggregates the 5 trace files and
   asserts:
   - Every SDK observed exactly one `interrupted` event at the
     SAME ordinal (~500 by default).
   - Events after the interrupt arrive within 50,000,000 ns (50 ms)
     OR not at all.

## Trace format

One line per event:

```
<ordinal> <payload_kind> <recv_ns>
```

- `ordinal`: integer, the index of the event in the input stream.
- `payload_kind`: one of `userSaid`, `assistantToken`, `audio`,
  `vad`, `state`, `error`, `interrupted`, `metrics`.
- `recv_ns`: consumer-side monotonic timestamp in nanoseconds.

## Running

```sh
# 1. Build the producer:
cmake --build build/macos-release --target cancel_producer

# 2. Generate the input binary:
./build/macos-release/tests/streaming/cancel_parity/cancel_producer \
  --count 1000 --cancel-at 500 --out /tmp/cancel_input.bin

# 3. Run per-SDK consumers (one each):
#    Each SDK's test-runner invocation pattern:
swift test --filter CancelParityTests
cd sdk/runanywhere-kotlin && ./gradlew jvmTest --tests *CancelParityTest*
cd sdk/runanywhere-flutter/packages/runanywhere && flutter test test/cancel_parity_test.dart
cd sdk/runanywhere-react-native/packages/core && yarn jest cancel_parity.rn.test
cd sdk/runanywhere-web/packages/core && pnpm vitest run cancel_parity.web.test

# 4. Aggregate results:
python tests/streaming/cancel_parity/compare_cancel_traces.py
```

## Per-SDK consumer library

Each SDK's consumer is a small wrapper (< 100 LOC) that decodes the
binary format, feeds frames to the C callback, and records traces.
The pattern is identical across SDKs; only the proto library +
cancel API differs.

See:
- `sdk/runanywhere-swift/Tests/CancelParityTests.swift`
- `sdk/runanywhere-kotlin/src/jvmTest/kotlin/.../CancelParityTest.kt`
- `sdk/runanywhere-flutter/packages/runanywhere/test/cancel_parity_test.dart`
- `tests/streaming/cancel_parity/cancel_parity.rn.test.ts` (jest)
- `tests/streaming/cancel_parity/cancel_parity.web.test.ts` (vitest)

## What this does NOT test

- Actual production voice-agent cancel (the voice agent's stop
  operation). This harness is wire-level cancel: it verifies the
  proto pipeline + adapter cancel paths work. A separate
  integration test (future scope) would exercise the full voice
  agent with real STT/LLM/TTS models and verify the stop call
  reaches the models.

- Cancel-during-audio-playback on RN/Swift audio threads. That's a
  device-specific QA item (GAP 08 #10).

## Exit criteria

Aggregator returns 0 and prints `PASS` for all 5 SDKs plus the
wire-parity line. CI wires this into `pr-build.yml`.
