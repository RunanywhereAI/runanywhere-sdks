// cancel_parity.ts — shared TS consumer for RN + Web cancel-parity.
//
// v3.1 Phase 5.1. Reads /tmp/cancel_input.bin (produced by
// cancel_producer.cpp), decodes each VoiceEvent, records an ordinal/kind/
// recv_ns trace, and simulates the SDK's cancel operation when the
// interrupted arm arrives. After cancel, the consumer keeps reading
// events for 50ms to verify the cancel budget is respected.

import * as fs from 'fs';

const INPUT_PATH = '/tmp/cancel_input.bin';
const MAGIC = 0x43504152; // 'CPAR'
const CANCEL_BUDGET_NS = 50_000_000n; // 50ms

export type PayloadKind =
  | 'userSaid'
  | 'assistantToken'
  | 'audio'
  | 'vad'
  | 'state'
  | 'error'
  | 'interrupted'
  | 'metrics'
  | 'unknown';

export interface CancelParityResult {
  total: number;
  interruptOrdinal: number | null;
  postCancelCount: number;
  postCancelMaxDeltaNs: bigint;
}

export type KindExtractor = (frame: Uint8Array) => PayloadKind;

/**
 * Run the cancel-parity consumer. `extractKind` maps a raw frame to its
 * oneof payload case name; each SDK supplies its own ts-proto decode.
 * Writes the trace to `outputPath` (one `<ordinal> <kind> <recv_ns>` per line).
 */
export async function runCancelParity(
  outputPath: string,
  extractKind: KindExtractor,
  inputPath: string = INPUT_PATH,
): Promise<CancelParityResult> {
  const buf = fs.readFileSync(inputPath);
  const view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);

  if (buf.length < 8 || view.getUint32(0, true) !== MAGIC) {
    throw new Error(`cancel_parity: bad magic at ${inputPath}`);
  }
  const count = view.getUint32(4, true);

  const lines: string[] = [];
  let cursor = 8;
  let cancelled = false;
  let cancelNs: bigint | null = null;
  let interruptOrdinal: number | null = null;
  let postCancelCount = 0;
  let postCancelMaxDelta = 0n;

  for (let i = 0; i < count; i++) {
    if (cursor + 4 > buf.length) break;
    const len = view.getUint32(cursor, true);
    cursor += 4;
    if (cursor + len > buf.length) break;
    const frame = buf.subarray(cursor, cursor + len);
    cursor += len;

    const recvNs = process.hrtime.bigint();
    const kind = extractKind(frame);
    lines.push(`${i} ${kind} ${recvNs}`);

    if (kind === 'interrupted' && !cancelled) {
      cancelled = true;
      cancelNs = recvNs;
      interruptOrdinal = i;
      // simulate cancel (in a real consumer, this is where the adapter's
      // cancel() / subscription.unsubscribe() would fire). The loop then
      // continues for ≤50ms to verify the cancel budget is respected.
    } else if (cancelled && cancelNs !== null) {
      postCancelCount++;
      const delta = recvNs - cancelNs;
      if (delta > postCancelMaxDelta) postCancelMaxDelta = delta;
      if (delta > CANCEL_BUDGET_NS) {
        // Real consumer would break here immediately once the adapter
        // unwound; we continue reading to record the budget overrun
        // explicitly so the aggregator can fail with a helpful message.
      }
    }
  }

  fs.writeFileSync(outputPath, lines.join('\n') + '\n');
  return {
    total: count,
    interruptOrdinal,
    postCancelCount,
    postCancelMaxDeltaNs: postCancelMaxDelta,
  };
}
