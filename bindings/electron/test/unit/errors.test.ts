// Unit tests for SDKException — the house-uniform throwable (src/errors.ts).
import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  SDKException,
  ErrorCodes,
  ErrorCategories,
  isSDKException,
  asSDKException,
  raiseForRac,
  categoryForCode,
} from '../../dist/errors';

test('canonical ErrorCode values match idl/errors.proto', () => {
  assert.equal(ErrorCodes.NOT_INITIALIZED, 100);
  assert.equal(ErrorCodes.MODEL_NOT_FOUND, 110);
  assert.equal(ErrorCodes.MODEL_LOAD_FAILED, 111);
  assert.equal(ErrorCodes.GENERATION_FAILED, 130);
  assert.equal(ErrorCodes.INVALID_INPUT, 251);
  assert.equal(ErrorCodes.INVALID_ARGUMENT, 259);
  assert.equal(ErrorCodes.CANCELLED, 380);
  assert.equal(ErrorCodes.NOT_IMPLEMENTED, 800);
  assert.equal(ErrorCodes.UNKNOWN, 804);
});

test('canonical ErrorCategory values match idl/errors.proto', () => {
  assert.equal(ErrorCategories.NETWORK, 1);
  assert.equal(ErrorCategories.VALIDATION, 2);
  assert.equal(ErrorCategories.MODEL, 3);
  assert.equal(ErrorCategories.COMPONENT, 4);
  assert.equal(ErrorCategories.INTERNAL, 7);
  assert.equal(ErrorCategories.CONFIGURATION, 8);
});

test('categoryForCode maps ranges like the canonical table', () => {
  assert.equal(categoryForCode(0), ErrorCategories.UNSPECIFIED);
  assert.equal(categoryForCode(100), ErrorCategories.CONFIGURATION);
  assert.equal(categoryForCode(110), ErrorCategories.MODEL);
  // Generation (-130..-149) is in none of the table's ranges, so it takes the
  // INTERNAL fallback — exactly as commons' rac_result_to_proto_category does.
  assert.equal(categoryForCode(130), ErrorCategories.INTERNAL);
  assert.equal(categoryForCode(182), ErrorCategories.IO);
  assert.equal(categoryForCode(259), ErrorCategories.VALIDATION);
  assert.equal(categoryForCode(380), ErrorCategories.INTERNAL);
  assert.equal(categoryForCode(804), ErrorCategories.INTERNAL);
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
  const e = SDKException.of(ErrorCodes.MODEL_NOT_FOUND, 'nope');
  assert.equal(e.code, 110);
  assert.equal(e.category, ErrorCategories.MODEL);
  assert.equal(e.cAbiCode, -110); // negative rac_result_t for 1..899
  assert.equal(e.message, 'nope');
});

test('notInitialized overrides category to COMPONENT', () => {
  const e = SDKException.notInitialized('LLM');
  assert.equal(e.code, ErrorCodes.NOT_INITIALIZED);
  assert.equal(e.category, ErrorCategories.COMPONENT);
  assert.match(e.message, /LLM not initialized/);
  assert.equal(e.recoverySuggestion, 'Initialize the SDK (RunAnywhere.initialize()) before using it.');
});

test('validationFailed carries a field path and VALIDATION category', () => {
  const e = SDKException.validationFailed({ fieldPath: 'tools', message: 'at least one tool is required' });
  assert.equal(e.code, ErrorCodes.INVALID_ARGUMENT);
  assert.equal(e.category, ErrorCategories.VALIDATION);
  assert.equal(e.fieldPath, 'tools');
  assert.equal(e.cAbiCode, -259);
});

test('modelLoadFailed preserves the cause as nestedMessage', () => {
  const e = SDKException.modelLoadFailed('qwen', new Error('bad gguf'));
  assert.equal(e.code, ErrorCodes.MODEL_LOAD_FAILED);
  assert.equal(e.nestedMessage, 'bad gguf');
});

test('generationFailed takes the canonical table INTERNAL fallback', () => {
  const e = SDKException.generationFailed('did not return valid JSON');
  assert.equal(e.code, ErrorCodes.GENERATION_FAILED);
  assert.equal(e.category, ErrorCategories.INTERNAL);
});

test('cancelled is expected and INTERNAL', () => {
  const e = SDKException.cancelled();
  assert.equal(e.code, ErrorCodes.CANCELLED);
  assert.equal(e.category, ErrorCategories.INTERNAL);
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
  assert.equal(fromError.code, ErrorCodes.UNKNOWN);
  assert.equal(fromError.nestedMessage, 'plain');

  const fromString = asSDKException('just text');
  assert.equal(fromString.code, ErrorCodes.UNKNOWN);
  assert.equal(fromString.message, 'just text');

  const fromObj = asSDKException({ weird: true });
  assert.equal(fromObj.code, ErrorCodes.UNKNOWN);
});

test('raiseForRac preserves the positive SDK code and negative ABI code', () => {
  assert.throws(
    () => raiseForRac(-231, 'native invalid state'),
    (e: unknown) => {
      assert.ok(isSDKException(e));
      assert.equal(e.code, ErrorCodes.INVALID_STATE);
      assert.equal(e.cAbiCode, -231);
      assert.equal(e.category, ErrorCategories.COMPONENT);
      assert.equal(e.message, 'native invalid state');
      return true;
    }
  );
});

test('asSDKException prefers structured native fields over UNKNOWN', () => {
  const e = asSDKException({
    message: 'load_model failed: -111',
    code: 111,
    cAbiCode: -111,
    category: ErrorCategories.MODEL,
  });
  assert.ok(isSDKException(e));
  assert.equal(e.code, ErrorCodes.MODEL_LOAD_FAILED);
  assert.equal(e.cAbiCode, -111);
  assert.equal(e.category, ErrorCategories.MODEL);
});

test('asSDKException maps trailing rac codes in native strings', () => {
  const e = asSDKException('stream failed: -130');
  assert.equal(e.code, ErrorCodes.GENERATION_FAILED);
  assert.equal(e.cAbiCode, -130);
  assert.equal(e.category, ErrorCategories.INTERNAL);
});

test('raiseForRac maps -111 to MODEL_LOAD_FAILED', () => {
  assert.throws(
    () => raiseForRac(-111),
    (e: unknown) => {
      assert.ok(isSDKException(e));
      assert.equal(e.code, ErrorCodes.MODEL_LOAD_FAILED);
      assert.equal(e.category, ErrorCategories.MODEL);
      assert.equal(e.cAbiCode, -111);
      return true;
    }
  );
});

test('raiseForRac unknown code falls back to UNKNOWN', () => {
  assert.throws(
    () => raiseForRac(-9999, 'boom'),
    (e: unknown) => {
      assert.ok(isSDKException(e));
      assert.equal(e.code, ErrorCodes.UNKNOWN);
      assert.equal(e.message, 'boom');
      assert.equal(e.cAbiCode, -9999);
      return true;
    }
  );
});

test('asSDKException parses native "failed: -<rac>" messages', () => {
  const e = asSDKException(new Error('load_model failed: -111'));
  assert.ok(isSDKException(e));
  assert.equal(e.code, ErrorCodes.MODEL_LOAD_FAILED);
  assert.equal(e.category, ErrorCategories.MODEL);
  assert.equal(e.cAbiCode, -111);
  assert.match(e.message, /load_model failed: -111/);
});

test('asSDKException prefers structured cAbiCode from native Errors', () => {
  const native = Object.assign(new Error('load_model failed: -111'), {
    code: 111,
    cAbiCode: -111,
  });
  const e = asSDKException(native);
  assert.equal(e.code, ErrorCodes.MODEL_LOAD_FAILED);
  assert.equal(e.cAbiCode, -111);
});
