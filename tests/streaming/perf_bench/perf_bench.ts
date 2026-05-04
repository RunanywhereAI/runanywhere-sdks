// perf_bench.ts — RN/Web consumer for the GAP 09 #8 perf bench.
//
// v3.2: in-process decode latency (mirrors perf_bench.kt / perf_bench.dart).
//
// Why not `now() - metrics.created_at_ns`: the C++ producer stamps
// `created_at_ns` from `std::chrono::steady_clock`, which is monotonic
// but has a process-local, platform-defined epoch. Node's
// `process.hrtime.bigint()` is also monotonic with its own origin
// (process start). Subtracting the two yields garbage deltas (observed:
// ~158 s offset on macOS), which the `>0` filter still accepts but
// blows past the 1ms p50 budget. Decode latency in-process is what the
// README spec actually describes — "per-event work: proto decode +
// delta computation only" — so we bracket `process.hrtime.bigint()`
// directly around the `decode` callback. Same clock, same process,
// measures exactly the cost the p50 budget is meant to bound.
//
// Single source for both React Native (Jest) and Web (Vitest) SDKs.
//
// Input format (matches perf_producer.cpp):
//   uint32_t magic = 0x42504152 ('RAPB')
//   uint32_t count
//   count × { uint32_t len; uint8_t[len] proto_bytes }

import * as fs from 'fs';

const DEFAULT_INPUT_PATH = '/tmp/perf_input.bin';
const MAGIC = 0x42504152;

/**
 * Decode one VoiceEvent frame and return the producer-side
 * `metrics.created_at_ns` if present, else null. Used only to
 * count "non-empty" frames; the perf delta is the bracketed
 * decode time, not a cross-clock subtraction.
 */
export type VoiceEventDecoder = (frame: Uint8Array) => bigint | null;

/**
 * Run the perf bench consumer against /tmp/perf_input.bin. Each
 * delta is the in-process decode time of one VoiceEvent (bracketed
 * with `process.hrtime.bigint()`), not a cross-process clock diff.
 *
 * @returns { count, nonEmpty } — `nonEmpty` counts frames whose
 *           MetricsEvent arm carries `created_at_ns > 0`.
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

    // Bracket decode in-process — same monotonic clock, same process.
    const startNs = process.hrtime.bigint();
    const producerNs = decode(frame);
    const endNs = process.hrtime.bigint();
    const decodeNs = endNs - startNs;

    if (decodeNs > 0n) {
      deltas[i] = decodeNs;
      if (producerNs !== null && producerNs > 0n) nonEmpty++;
    } else {
      deltas[i] = 0n;
    }
  }

  const lines = Array.from(deltas).map((d) => d.toString()).join('\n') + '\n';
  fs.writeFileSync(outputPath, lines);

  // eslint-disable-next-line no-console
  console.log(
    `perf_bench.ts: wrote ${count} deltas (${nonEmpty} non-empty) to ${outputPath}`,
  );
  return { count, nonEmpty };
}
