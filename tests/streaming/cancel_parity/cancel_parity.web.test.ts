/**
 * cancel_parity.web.test.ts — Vitest runner for GAP 09 #7 (v3.1 Phase 5.1).
 *
 * Uses the Web SDK's ts-proto-generated VoiceEvent. Identical shape to
 * the RN runner; only the VoiceEvent import path differs.
 */

import * as fs from 'fs';
import { describe, it, expect, beforeAll } from 'vitest';
import { runCancelParity, type PayloadKind } from './cancel_parity';
import { VoiceEvent } from '@runanywhere/proto-ts/voice_events';

const OUTPUT_PATH = '/tmp/cancel_trace.web.log';

function extractKindWeb(frame: Uint8Array): PayloadKind {
  const event = VoiceEvent.decode(frame);
  // ts-proto generates oneof arms as top-level optional fields (no
  // `oneofs=unions`). Probe each arm in proto field order.
  if (event.userSaid !== undefined) return 'userSaid';
  if (event.assistantToken !== undefined) return 'assistantToken';
  if (event.audio !== undefined) return 'audio';
  if (event.vad !== undefined) return 'vad';
  if (event.interrupted !== undefined) return 'interrupted';
  if (event.state !== undefined) return 'state';
  if (event.error !== undefined) return 'error';
  if (event.metrics !== undefined) return 'metrics';
  return 'unknown';
}

describe('cancel_parity (web)', () => {
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
    const result = await runCancelParity(OUTPUT_PATH, extractKindWeb);
    expect(result.total).toBeGreaterThan(0);
    expect(result.interruptOrdinal).not.toBeNull();
  });
});
