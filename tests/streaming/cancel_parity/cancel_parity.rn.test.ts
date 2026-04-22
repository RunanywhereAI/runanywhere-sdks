/**
 * cancel_parity.rn.test.ts — Jest runner for GAP 09 #7 (v3.1 Phase 5.1).
 *
 * Uses the RN SDK's ts-proto-generated VoiceEvent to determine the
 * payload kind per frame; the shared consumer handles the trace
 * recording and cancel-budget math.
 */

import * as fs from 'fs';
import { runCancelParity, type PayloadKind } from './cancel_parity';
import { VoiceEvent } from '../../../sdk/runanywhere-react-native/packages/core/src/generated/voice_events';

const OUTPUT_PATH = '/tmp/cancel_trace.rn.log';

function extractKindRN(frame: Uint8Array): PayloadKind {
  const event = VoiceEvent.decode(frame);
  // ts-proto represents oneof as `payload.$case`.
  const kind = event.payload?.$case;
  if (!kind) return 'unknown';
  return kind as PayloadKind;
}

describe('cancel_parity (rn)', () => {
  beforeAll(() => {
    if (!fs.existsSync('/tmp/cancel_input.bin')) {
      throw new Error(
        'cancel_parity: /tmp/cancel_input.bin missing. Run: ' +
          'cmake --build build/macos-release --target cancel_producer && ' +
          './build/macos-release/tests/streaming/cancel_parity/cancel_producer',
      );
    }
  });

  it('records interrupt ordinal and cancel-budget trace', async () => {
    const result = await runCancelParity(OUTPUT_PATH, extractKindRN);
    expect(result.total).toBeGreaterThan(0);
    expect(result.interruptOrdinal).not.toBeNull();
    // The aggregator enforces the cross-SDK parity + latency budget
    // across all 5 trace files; per-SDK test only ensures the trace
    // file was written and the interrupt was observed.
  });
});
