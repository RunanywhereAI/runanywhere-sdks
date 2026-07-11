import { describe, expect, it } from 'vitest';
import { redactResourceURL } from '../../../src/Foundation/BackendContract';

describe('redactResourceURL', () => {
  it('removes credentials, signed parameters, and fragments from absolute URLs', () => {
    expect(
      redactResourceURL(
        'https://user:secret@example.com/models/backend.js?token=private#fragment',
      ),
    ).toBe('https://example.com/models/backend.js');
  });

  it('removes query parameters and fragments from relative asset paths', () => {
    expect(redactResourceURL('/assets/backend.js?signature=private#fragment'))
      .toBe('/assets/backend.js');
  });

  it('does not log data URL payloads', () => {
    expect(redactResourceURL('data:text/javascript,secret')).toBe('data:[redacted]');
  });
});
