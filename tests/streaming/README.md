# GAP 09 Streaming Parity Tests

Each `parity_test.<lang>` feeds the same fixture audio file
(`tests/streaming/fixtures/parity_input.wav`) through the voice agent
and asserts the emitted event sequence is identical across all 5 SDKs.

| Language    | File                       | Status                |
|-------------|----------------------------|-----------------------|
| Swift       | `parity_test.swift`        | Scaffold (Wave C ship) |
| Kotlin/JVM  | `parity_test.kt`           | Scaffold (Wave C ship) |
| Dart        | `parity_test.dart`         | Scaffold (Wave C ship) |
| TypeScript  | `parity_test.ts`           | Scaffold (Wave C ship) |
| C++         | `parity_test.cpp`          | Wave C ship golden producer |

## What the test does

1. Initialise a voice agent handle with deterministic config
   (RAC_FORCE_RUNTIME=cpu, fixed seed in random samplers).
2. Open a stream via the language's adapter (Swift AsyncStream, Kotlin
   Flow, Dart Stream, TS AsyncIterable).
3. Feed `fixtures/parity_input.wav` (10 seconds, 1 utterance).
4. Collect emitted events into a list (event_type, summary_string).
5. Compare against the per-language golden snapshot in
   `tests/streaming/fixtures/golden_events.txt`.

The golden file is written by the C++ test once and re-validated by every
SDK; drift between SDKs surfaces as a diff during PR review.

## Cancellation test

After collecting 5 events:
- Cancel the stream (Swift `task.cancel()`, Kotlin `job.cancel()`, Dart
  `subscription.cancel()`, TS `break`).
- Assert no events arrive within the next 100 ms (no-stale-events).

## Wave C ship vs Wave D ship

Today's commit ships the test scaffolds + adapter wiring. The actual
fixture audio + golden events file land alongside the first end-to-end
voice-agent C++ build (Wave D opens that as part of the Kotlin/Swift
deletion sweep that uses the adapters).
