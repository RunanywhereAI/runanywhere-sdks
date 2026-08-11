// toPublicFinishReason — commons FinishReason only; never invent from tool counts.
const { test } = require('node:test');
const assert = require('node:assert/strict');

const { FinishReason: ProtoFinishReason } = require('@runanywhere/proto-ts/finish_reason');
const { toPublicFinishReason } = require('../../dist/api/llm-abi');
const { FinishReason } = require('../../dist/api/types');

test('toPublicFinishReason maps STOP / STOP_SEQUENCE → STOP', () => {
  assert.equal(toPublicFinishReason(ProtoFinishReason.FINISH_REASON_STOP), FinishReason.STOP);
  assert.equal(
    toPublicFinishReason(ProtoFinishReason.FINISH_REASON_STOP_SEQUENCE),
    FinishReason.STOP
  );
});

test('toPublicFinishReason maps LENGTH / CONTEXT_OVERFLOW → LENGTH', () => {
  assert.equal(toPublicFinishReason(ProtoFinishReason.FINISH_REASON_LENGTH), FinishReason.LENGTH);
  assert.equal(
    toPublicFinishReason(ProtoFinishReason.FINISH_REASON_CONTEXT_OVERFLOW),
    FinishReason.LENGTH
  );
});

test('toPublicFinishReason preserves TOOL_CALLS / CANCELLED / ERROR', () => {
  assert.equal(
    toPublicFinishReason(ProtoFinishReason.FINISH_REASON_TOOL_CALLS),
    FinishReason.TOOL_CALLS
  );
  assert.equal(
    toPublicFinishReason(ProtoFinishReason.FINISH_REASON_CANCELLED),
    FinishReason.CANCELLED
  );
  assert.equal(toPublicFinishReason(ProtoFinishReason.FINISH_REASON_ERROR), FinishReason.ERROR);
});

test('toPublicFinishReason keeps UNSPECIFIED as UNKNOWN (never invents STOP)', () => {
  assert.equal(
    toPublicFinishReason(ProtoFinishReason.FINISH_REASON_UNSPECIFIED),
    FinishReason.UNKNOWN
  );
});
