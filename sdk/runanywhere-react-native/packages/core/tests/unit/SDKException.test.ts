/**
 * SDKException unit tests.
 *
 * Smoke coverage for the throwable / type-guard / categoryForCode
 * mapping. Mirrors the Swift `SDKExceptionTests` and the Kotlin
 * `SDKExceptionTest` so cross-SDK code paths stay byte-isomorphic.
 */

import {
  ErrorCategory,
  ErrorCode,
} from '@runanywhere/proto-ts/errors';
import {
  SDKException,
  isSDKException,
  asSDKException,
} from '../../src/Foundation/Errors/SDKException';

describe('SDKException', () => {
  describe('static factories', () => {
    it('notInitialized produces the configured proto code', () => {
      const exception = SDKException.notInitialized('VAD');
      expect(exception.code).toBe(ErrorCode.ERROR_CODE_NOT_INITIALIZED);
      expect(exception.message).toBe('VAD not initialized');
      expect(exception).toBeInstanceOf(Error);
      expect(exception).toBeInstanceOf(SDKException);
    });

    it('nativeModuleUnavailable defaults to NOT_INITIALIZED', () => {
      const exception = SDKException.nativeModuleUnavailable();
      expect(exception.code).toBe(ErrorCode.ERROR_CODE_NOT_INITIALIZED);
      expect(exception.message).toBe('Native module not available');
    });

    it('modelNotFound surfaces the model id in the message', () => {
      const exception = SDKException.modelNotFound('llama-3-8b');
      expect(exception.code).toBe(ErrorCode.ERROR_CODE_MODEL_NOT_FOUND);
      expect(exception.message).toContain('llama-3-8b');
    });

    it('validationFailed encodes field_path metadata and category', () => {
      const exception = SDKException.validationFailed({
        fieldPath: 'VADConfiguration.sample_rate',
        message: 'sample_rate must be > 0',
      });
      expect(exception.code).toBe(ErrorCode.ERROR_CODE_INVALID_ARGUMENT);
      expect(exception.category).toBe(ErrorCategory.ERROR_CATEGORY_VALIDATION);
      expect(exception.cAbiCode).toBe(-259);
      expect(exception.fieldPath).toBe('VADConfiguration.sample_rate');
    });

    it('unknown wraps a JS Error cause in nestedMessage', () => {
      const cause = new Error('underlying boom');
      const exception = SDKException.unknown('high-level failure', cause);
      expect(exception.code).toBe(ErrorCode.ERROR_CODE_UNKNOWN);
      expect(exception.proto.nestedMessage).toBe('underlying boom');
    });
  });

  describe('isSDKException', () => {
    it('recognises SDKException instances', () => {
      const exception = SDKException.notInitialized();
      expect(isSDKException(exception)).toBe(true);
    });

    it('rejects plain Error instances and primitives', () => {
      expect(isSDKException(new Error('not me'))).toBe(false);
      expect(isSDKException('plain string')).toBe(false);
      expect(isSDKException(undefined)).toBe(false);
      expect(isSDKException(null)).toBe(false);
    });
  });

  describe('asSDKException', () => {
    it('passes SDKException through unchanged', () => {
      const original = SDKException.modelNotFound('x');
      expect(asSDKException(original)).toBe(original);
    });

    it('wraps a JS Error into an UNKNOWN SDKException', () => {
      const wrapped = asSDKException(new Error('boom'));
      expect(wrapped.code).toBe(ErrorCode.ERROR_CODE_UNKNOWN);
      expect(wrapped.message).toBe('boom');
      expect(wrapped.proto.nestedMessage).toBe('boom');
    });

    it('wraps a string into an UNKNOWN SDKException', () => {
      const wrapped = asSDKException('only a string');
      expect(wrapped.code).toBe(ErrorCode.ERROR_CODE_UNKNOWN);
      expect(wrapped.message).toBe('only a string');
    });

    it('stringifies non-Error, non-string values', () => {
      const wrapped = asSDKException({ shape: 'unknown' });
      expect(wrapped.code).toBe(ErrorCode.ERROR_CODE_UNKNOWN);
      expect(wrapped.message).toContain('[object Object]');
    });
  });

  describe('categoryForCode (via static factories)', () => {
    it('maps configuration codes (100-109) to CONFIGURATION', () => {
      // notInitialized() deliberately overrides to COMPONENT (Swift parity),
      // so exercise categoryForCode with a non-overridden 100-range code.
      const exception = SDKException.of(
        ErrorCode.ERROR_CODE_INVALID_API_KEY,
        'bad key'
      );
      expect(exception.category).toBe(ErrorCategory.ERROR_CATEGORY_CONFIGURATION);
    });

    it('notInitialized uses COMPONENT category (Swift parity)', () => {
      const exception = SDKException.notInitialized();
      expect(exception.category).toBe(ErrorCategory.ERROR_CATEGORY_COMPONENT);
    });

    it('maps model codes (110-129) to MODEL', () => {
      const exception = SDKException.modelNotFound();
      expect(exception.category).toBe(ErrorCategory.ERROR_CATEGORY_MODEL);
    });

    it('maps auth codes (320-329) to AUTH', () => {
      const exception = SDKException.authenticationFailed();
      expect(exception.category).toBe(ErrorCategory.ERROR_CATEGORY_AUTH);
    });
  });
});
