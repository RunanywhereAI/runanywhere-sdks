/**
 * Pins commons FinishReason → public FinishReason mapping: no tool-call
 * count heuristics; UNSPECIFIED stays unknown; ERROR stays error.
 */

import { FinishReason as ProtoFinishReason } from '@runanywhere/proto-ts/finish_reason';
import { fromFinishReason } from '../../../../src/Public/Api/Results';

describe('fromFinishReason', () => {
  it('maps STOP and STOP_SEQUENCE to stop', () => {
    expect(fromFinishReason(ProtoFinishReason.FINISH_REASON_STOP)).toBe('stop');
    expect(fromFinishReason(ProtoFinishReason.FINISH_REASON_STOP_SEQUENCE)).toBe('stop');
  });

  it('maps LENGTH and CONTEXT_OVERFLOW to length', () => {
    expect(fromFinishReason(ProtoFinishReason.FINISH_REASON_LENGTH)).toBe('length');
    expect(fromFinishReason(ProtoFinishReason.FINISH_REASON_CONTEXT_OVERFLOW)).toBe('length');
  });

  it('preserves TOOL_CALLS, CANCELLED, and ERROR', () => {
    expect(fromFinishReason(ProtoFinishReason.FINISH_REASON_TOOL_CALLS)).toBe('toolCalls');
    expect(fromFinishReason(ProtoFinishReason.FINISH_REASON_CANCELLED)).toBe('cancelled');
    expect(fromFinishReason(ProtoFinishReason.FINISH_REASON_ERROR)).toBe('error');
  });

  it('keeps UNSPECIFIED as unknown — never invents stop or toolCalls', () => {
    expect(fromFinishReason(ProtoFinishReason.FINISH_REASON_UNSPECIFIED)).toBe('unknown');
  });
});
