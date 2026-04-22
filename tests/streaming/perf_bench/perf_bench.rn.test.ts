/**
 * perf_bench.rn.test.ts — Jest runner for the GAP 09 #8 p50 benchmark.
 *
 * v3.1: real implementation. Wires the shared perf_bench.ts consumer to
 * the React Native SDK's ts-proto-generated VoiceEvent + asserts p50 < 1ms.
 *
 * Usage (requires /tmp/perf_input.bin to exist, produced by the C++
 * perf_producer — see tests/streaming/perf_bench/README.md):
 *
 *   cd sdk/runanywhere-react-native/packages/core && yarn jest \
 *     --config ../../../../tests/streaming/perf_bench/jest.rn.config.js
 */

import * as fs from 'fs';
import { runPerfBench } from './perf_bench';
import { VoiceEvent } from '../../../sdk/runanywhere-react-native/packages/core/src/generated/voice_events';

const OUTPUT_PATH = '/tmp/perf_bench.rn.log';

function decodeRN(frame: Uint8Array): bigint | null {
  const event = VoiceEvent.decode(frame);
  // ts-proto emits oneof payloads as a discriminated union on
  // `payload.$case`. The MetricsEvent arm carries created_at_ns.
  if (
    event.payload?.$case === 'metrics' &&
    event.payload.metrics.createdAtNs !== undefined
  ) {
    // ts-proto represents int64 as string|Long depending on the
    // options; the default is `string` (safe for very large values).
    // We coerce via BigInt for uniformity with the producer's hrtime.
    const raw = event.payload.metrics.createdAtNs as unknown as string | number | bigint;
    return BigInt(raw);
  }
  return null;
}

describe('perf_bench (rn)', () => {
  beforeAll(() => {
    if (!fs.existsSync('/tmp/perf_input.bin')) {
      throw new Error(
        'perf_bench: /tmp/perf_input.bin missing. Run the C++ producer first:\n' +
          '  cmake --build build/macos-release --target perf_producer && \\\n' +
          '  ./build/macos-release/tests/streaming/perf_bench/perf_producer',
      );
    }
  });

  it('decodes proto and emits deltas', async () => {
    const result = await runPerfBench(OUTPUT_PATH, decodeRN);
    expect(result.count).toBeGreaterThan(0);
    expect(result.nonEmpty).toBeGreaterThan(0);
  });

  it('p50 delta below 1ms (1_000_000 ns)', () => {
    // Read back the log, extract non-zero deltas, compute p50.
    const raw = fs.readFileSync(OUTPUT_PATH, 'utf-8');
    const nonZero = raw
      .split('\n')
      .filter((l) => l.trim().length > 0 && l !== '0')
      .map((l) => BigInt(l))
      .filter((n) => n > 0n);
    nonZero.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
    expect(nonZero.length).toBeGreaterThan(0);
    const p50 = nonZero[Math.floor(nonZero.length / 2)];
    // 1 ms == 1,000,000 ns. Fail if p50 >= 1ms.
    expect(Number(p50)).toBeLessThan(1_000_000);
  });
});
