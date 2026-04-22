// perf_bench.ts — RN/Web consumer for the GAP 09 #8 perf bench.
//
// v2.1 quick-wins Item 3 scaffold. Single source for both React Native
// and Web SDKs (both use ts-proto + the same AsyncIterable consumer
// pattern; the runner harness differs per platform).
//
// Reads /tmp/perf_input.bin (produced by perf_producer.cpp), decodes
// each VoiceEvent via ts-proto, computes the consumer-side latency
// delta, and writes per-event delta_ns to /tmp/perf_bench.<rn|web>.log.
//
// Status: SCAFFOLD. Per-platform runner integration (Jest for RN with
// Nitro Module mock, Vitest for Web with Emscripten WASM module load)
// is the v2.1-2 follow-up.

import * as fs from 'fs';
// import { VoiceEvent } from '../../../sdk/runanywhere-react-native/packages/core/src/Generated/voice_events';
// import { VoiceEvent } from '../../../sdk/runanywhere-web/packages/core/src/Generated/voice_events';

const INPUT_PATH = '/tmp/perf_input.bin';
const MAGIC = 0x42504152; // 'RAPB'

export async function runPerfBench(outputPath: string): Promise<void> {
  const buf = fs.readFileSync(INPUT_PATH);
  const view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);

  if (buf.length < 8) {
    throw new Error('Input too short');
  }
  const magic = view.getUint32(0, true);
  if (magic !== MAGIC) {
    throw new Error(`Bad magic: ${magic.toString(16)}`);
  }
  const count = view.getUint32(4, true);
  const deltas = new BigInt64Array(count);

  let cursor = 8;
  for (let i = 0; i < count; i++) {
    if (cursor + 4 > buf.length) break;
    const len = view.getUint32(cursor, true);
    cursor += 4;
    if (cursor + len > buf.length) break;
    const frame = buf.subarray(cursor, cursor + len);
    cursor += len;

    // Mark consumer-receive timestamp BEFORE decode to include
    // proto-decode cost in latency.
    const recvNs = process.hrtime.bigint();

    // SCAFFOLD: replace with actual ts-proto decode.
    // const event = VoiceEvent.decode(frame);
    // const producerNs = BigInt(event.metrics?.tokensGenerated ?? 0);
    void frame.length; // touch to avoid optimizer dead-code elim
    const producerNs = recvNs; // scaffold no-op

    deltas[i] = recvNs - producerNs;
  }

  const lines = Array.from(deltas).map((d) => d.toString()).join('\n') + '\n';
  fs.writeFileSync(outputPath, lines);
  console.log(`perf_bench.ts: wrote ${deltas.length} deltas to ${outputPath}`);
}

// Jest entry point for RN (commented until v2.1-2 integrates):
// describe('perf_bench (rn)', () => {
//   it('p50 under 1ms', async () => {
//     await runPerfBench('/tmp/perf_bench.rn.log');
//     // Aggregator asserts the p50 threshold.
//   });
// });

// Vitest entry point for Web (commented until v2.1-2 integrates):
// import { describe, it } from 'vitest';
// describe('perf_bench (web)', () => {
//   it('p50 under 1ms', async () => {
//     await runPerfBench('/tmp/perf_bench.web.log');
//   });
// });
