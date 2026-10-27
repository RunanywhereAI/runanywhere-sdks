import { describe, expect, it } from 'vitest';
import { ErrorCategory } from '@runanywhere/proto-ts/errors';
import { SDKException } from '../../../src/Foundation/SDKException.js';

describe('SDKException category fallback', () => {
  it('keeps an unmapped raw rac code UNSPECIFIED when proto code is unknown', () => {
    const exception = SDKException.fromRACResult(-12345);

    expect(exception.code).toBe(0);
    expect(exception.cAbiCode).toBe(-12345);
    expect(exception.proto.category).toBe(ErrorCategory.ERROR_CATEGORY_UNSPECIFIED);
  });
});
