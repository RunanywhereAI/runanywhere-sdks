// Unit tests for SDKException — the house-uniform throwable (src/errors.ts).
const { test } = require('node:test');
const assert = require('node:assert/strict');

const {
  SDKException,
  ErrorCode,
  ErrorCategory,
  isSDKException,
  asSDKException,
} = require('../../dist/errors');
const { categoryForCode } = require('../../dist/errors');

test('canonical ErrorCode values match idl/errors.proto', () => {
  assert.equal(ErrorCode.NOT_INITIALIZED, 100);
  assert.equal(ErrorCode.MODEL_NOT_FOUND, 110);
  assert.equal(ErrorCode.MODEL_LOAD_FAILED, 111);
  assert.equal(ErrorCode.GENERATION_FAILED, 130);
  assert.equal(ErrorCode.INVALID_INPUT, 251);
  assert.equal(ErrorCode.INVALID_ARGUMENT, 259);
  assert.equal(ErrorCode.CANCELLED, 380);
  assert.equal(ErrorCode.NOT_IMPLEMENTED, 800);
  assert.equal(ErrorCode.UNKNOWN, 804);
});

test('canonical ErrorCategory values match idl/errors.proto', () => {
  assert.equal(ErrorCategory.NETWORK, 1);
  assert.equal(ErrorCategory.VALIDATION, 2);
  assert.equal(ErrorCategory.MODEL, 3);
  assert.equal(ErrorCategory.COMPONENT, 4);
  assert.equal(ErrorCategory.INTERNAL, 7);
  assert.equal(ErrorCategory.CONFIGURATION, 8);
});

test('categoryForCode maps ranges like the canonical table', () => {
  assert.equal(categoryForCode(0), ErrorCategory.UNSPECIFIED);
  assert.equal(categoryForCode(100), ErrorCategory.CONFIGURATION);
  assert.equal(categoryForCode(110), ErrorCategory.MODEL);
  assert.equal(categoryForCode(130), ErrorCategory.COMPONENT);
  assert.equal(categoryForCode(182), ErrorCategory.IO);
  assert.equal(categoryForCode(259), ErrorCategory.VALIDATION);
  assert.equal(categoryForCode(380), ErrorCategory.INTERNAL);
  assert.equal(categoryForCode(804), ErrorCategory.INTERNAL);
});

test('SDKException is an Error subclass with the right name', () => {
  const e = SDKException.unknown('boom');
  assert.ok(e instanceof Error);
  assert.ok(e instanceof SDKException);
  assert.equal(e.name, 'SDKException');
  assert.equal(e.message, 'boom');
  assert.equal(SDKException.unknown().message, 'Unknown error');
});

test('SDKException.of derives category and cAbiCode', () => {
  const e = SDKException.of(ErrorCode.MODEL_NOT_FOUND, 'nope');
  assert.equal(e.code, 110);
  assert.equal(e.category, ErrorCategory.MODEL);
  assert.equal(e.cAbiCode, -110); // negative rac_result_t for 1..899
  assert.equal(e.message, 'nope');
});

test('notInitialized overrides category to COMPONENT', () => {
  const e = SDKException.notInitialized('LLM');
  assert.equal(e.code, ErrorCode.NOT_INITIALIZED);
  assert.equal(e.category, ErrorCategory.COMPONENT);
  assert.match(e.message, /LLM not initialized/);
  assert.equal(e.recoverySuggestion, 'Initialize the SDK (RunAnywhere.initialize()) before using it.');
});

test('validationFailed carries a field path and VALIDATION category', () => {
  const e = SDKException.validationFailed({ fieldPath: 'tools', message: 'at least one tool is required' });
  assert.equal(e.code, ErrorCode.INVALID_ARGUMENT);
  assert.equal(e.category, ErrorCategory.VALIDATION);
  assert.equal(e.fieldPath, 'tools');
  assert.equal(e.cAbiCode, -259);
});

test('modelLoadFailed preserves the cause as nestedMessage', () => {
  const e = SDKException.modelLoadFailed('qwen', new Error('bad gguf'));
  assert.equal(e.code, ErrorCode.MODEL_LOAD_FAILED);
  assert.equal(e.nestedMessage, 'bad gguf');
});

test('generationFailed is a COMPONENT error', () => {
  const e = SDKException.generationFailed('did not return valid JSON');
  assert.equal(e.code, ErrorCode.GENERATION_FAILED);
  assert.equal(e.category, ErrorCategory.COMPONENT);
});

test('cancelled is expected and INTERNAL', () => {
  const e = SDKException.cancelled();
  assert.equal(e.code, ErrorCode.CANCELLED);
  assert.equal(e.category, ErrorCategory.INTERNAL);
  assert.equal(e.isExpected, true);
});

test('non-cancelled errors are not "expected"', () => {
  assert.equal(SDKException.unknown().isExpected, false);
  assert.equal(SDKException.modelNotFound().isExpected, false);
});

test('recoverySuggestion is undefined for codes without a hint', () => {
  assert.equal(SDKException.generationFailed().recoverySuggestion, undefined);
  assert.equal(SDKException.modelNotFound('x').recoverySuggestion, 'Ensure the model is downloaded and the path/id is correct.');
});

test('isSDKException distinguishes SDKException from other throwables', () => {
  assert.ok(isSDKException(SDKException.unknown()));
  assert.ok(!isSDKException(new Error('x')));
  assert.ok(!isSDKException('x'));
  assert.ok(!isSDKException(null));
});

test('asSDKException coerces any thrown value', () => {
  const orig = SDKException.modelNotFound('m');
  assert.equal(asSDKException(orig), orig, 'passes through existing SDKException');

  const fromError = asSDKException(new Error('plain'));
  assert.ok(isSDKException(fromError));
  assert.equal(fromError.code, ErrorCode.UNKNOWN);
  assert.equal(fromError.nestedMessage, 'plain');

  const fromString = asSDKException('just text');
  assert.equal(fromString.code, ErrorCode.UNKNOWN);
  assert.equal(fromString.message, 'just text');

  const fromObj = asSDKException({ weird: true });
  assert.equal(fromObj.code, ErrorCode.UNKNOWN);
});
