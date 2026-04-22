// perf_bench.ts — RN/Web consumer for the GAP 09 #8 perf bench.
//
// v3.1: real implementation. Reads /tmp/perf_input.bin (produced by
// perf_producer.cpp), decodes each VoiceEvent via ts-proto, extracts
// the producer-side timestamp from `metrics.created_at_ns`, and
// computes consumer-side latency deltas. Writes per-event delta_ns
// to /tmp/perf_bench.<rn|web>.log.
//
// Single source for both React Native (Jest) and Web (Vitest) SDKs
// since both use ts-proto and the same AsyncIterable consumer pattern.
// The runner harnesses differ per platform; each test file imports
// the correct VoiceEvent proto path via the `voiceEventPath` parameter.
//
// Input format (matches perf_producer.cpp):
//   uint32_t magic = 0x42504152 ('RAPB')
//   uint32_t count
//   count × { uint32_t len; uint8_t[len] proto_bytes }

import * as fs from 'fs';

const DEFAULT_INPUT_PATH = '/tmp/perf_input.bin';
const MAGIC = 0x42504152;

/**
 * Decode one VoiceEvent frame and extract the producer timestamp
 * from `metrics.created_at_ns` (v3.1 schema). Returns nanoseconds or
 * null if the event has no metrics arm.
 */
export type VoiceEventDecoder = (frame: Uint8Array) => bigint | null;

/**
 * Run the perf bench consumer against /tmp/perf_input.bin.
 *
 * @param outputPath    Where to write per-event delta_ns (one per line).
 * @param decode        VoiceEvent decoder. Each platform wires its own
 *                      ts-proto import (RN / Web) and returns the
 *                      producer-side ns or null.
 * @param inputPath     Override for the input binary. Defaults to
 *                      /tmp/perf_input.bin.
 * @returns             { count, nonEmpty } so the caller can sanity-
 *                      check whether the producer wrote useful data.
 */
export async function runPerfBench(
  outputPath: string,
  decode: VoiceEventDecoder,
  inputPath: string = DEFAULT_INPUT_PATH,
): Promise<{ count: number; nonEmpty: number }> {
  const buf = fs.readFileSync(inputPath);
  const view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);

  if (buf.length < 8) {
    throw new Error('perf_bench input too short (<8 bytes)');
  }
  const magic = view.getUint32(0, true);
  if (magic !== MAGIC) {
    throw new Error(
      `perf_bench bad magic: 0x${magic.toString(16)} (expected 0x${MAGIC.toString(16)})`,
    );
  }
  const count = view.getUint32(4, true);
  const deltas = new BigInt64Array(count);

  let cursor = 8;
  let nonEmpty = 0;

  for (let i = 0; i < count; i++) {
    if (cursor + 4 > buf.length) break;
    const len = view.getUint32(cursor, true);
    cursor += 4;
    if (cursor + len > buf.length) break;

    const frame = buf.subarray(cursor, cursor + len);
    cursor += len;

    // Mark consumer-receive BEFORE decode so proto-decode cost is
    // attributed to latency (this is what a real consumer pays).
    const recvNs = process.hrtime.bigint();

    const producerNs = decode(frame);
    if (producerNs === null) {
      // Event has no metrics arm — record zero so aggregator's
      // percentile math stays stable. compute_percentiles.py knows
      // to filter zero values when computing meaningful stats.
      deltas[i] = 0n;
      continue;
    }

    deltas[i] = recvNs - producerNs;
    nonEmpty++;
  }

  const lines = Array.from(deltas).map((d) => d.toString()).join('\n') + '\n';
  fs.writeFileSync(outputPath, lines);

  // eslint-disable-next-line no-console
  console.log(
    `perf_bench.ts: wrote ${count} deltas (${nonEmpty} non-empty) to ${outputPath}`,
  );
  return { count, nonEmpty };
}
