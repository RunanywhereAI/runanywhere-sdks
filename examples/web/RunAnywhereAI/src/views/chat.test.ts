import { describe, expect, it } from 'vitest';
import { SDKException } from '@runanywhere/web';
import { formatChatError } from './chat';

describe('chat error formatting', () => {
  it('sanitizes SDKException messages before rendering or persistence', () => {
    const error = SDKException.fromCode(
      -1,
      'Request failed at https://example.test/models?token=secret-value with Bearer access-token',
    );

    const formatted = formatChatError(error);

    expect(formatted).toBe(
      'Error: Request failed at https://example.test/models with Bearer [REDACTED]',
    );
    expect(formatted).not.toContain('secret-value');
    expect(formatted).not.toContain('access-token');
  });
});
