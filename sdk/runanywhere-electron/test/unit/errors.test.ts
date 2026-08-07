import assert from 'node:assert/strict';
import test from 'node:test';

import {
  ErrorCategory,
  ErrorCode,
  SDKException,
  asSDKException,
  categoryForCode,
  isSDKException,
  raiseForRac,
} from '../../src/errors.js';

test('categoryForCode maps code ranges to the canonical category', () => {
  assert.equal(categoryForCode(0), ErrorCategory.UNSPECIFIED);
  assert.equal(categoryForCode(110), ErrorCategory.MODEL);
  assert.equal(categoryForCode(130), ErrorCategory.COMPONENT);
  assert.equal(categoryForCode(251), ErrorCategory.VALIDATION);
  assert.equal(categoryForCode(380), ErrorCategory.INTERNAL);
  assert.equal(categoryForCode(800), ErrorCategory.INTERNAL);
});

test('SDKException derives category and negative cAbiCode from the code', () => {
  const e = SDKException.of(ErrorCode.MODEL_LOAD_FAILED, 'bad');
  assert.ok(e instanceof Error);
  assert.ok(isSDKException(e));
  assert.equal(e.code, ErrorCode.MODEL_LOAD_FAILED);
  assert.equal(e.category, ErrorCategory.MODEL);
  assert.equal(e.cAbiCode, -111);
});

test('cancelled is classified as expected', () => {
  assert.equal(SDKException.cancelled().isExpected, true);
  assert.equal(SDKException.of(ErrorCode.GENERATION_FAILED, 'x').isExpected, false);
});

test('asSDKException recovers a code from cAbiCode', () => {
  const e = asSDKException({ message: 'load failed', cAbiCode: -111 });
  assert.equal(e.code, ErrorCode.MODEL_LOAD_FAILED);
  assert.equal(e.cAbiCode, -111);
});

test('asSDKException parses a trailing rac code from a message string', () => {
  const e = asSDKException('load_model failed: -111');
  assert.equal(e.code, ErrorCode.MODEL_LOAD_FAILED);
  assert.equal(e.cAbiCode, -111);
});

test('asSDKException passes an existing SDKException through unchanged', () => {
  const original = SDKException.notInitialized('LLM');
  assert.equal(asSDKException(original), original);
});

test('raiseForRac throws an SDKException carrying the raw negative code', () => {
  try {
    raiseForRac(-130, 'generation failed');
    assert.fail('should have thrown');
  } catch (e) {
    assert.ok(isSDKException(e));
    assert.equal((e as SDKException).code, ErrorCode.GENERATION_FAILED);
    assert.equal((e as SDKException).cAbiCode, -130);
  }
});
