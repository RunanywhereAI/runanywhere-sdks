import {
  isUsableCredential,
  isUsableHTTPURL,
} from '../../src/services/Network/NetworkConfiguration';

describe('NetworkConfiguration validation', () => {
  test('rejects empty and scaffolding credentials', () => {
    expect(isUsableCredential('')).toBe(false);
    expect(isUsableCredential('YOUR_API_KEY')).toBe(false);
    expect(isUsableCredential('your-key')).toBe(false);
    expect(isUsableCredential(' client-issued-key ')).toBe(true);
    expect(isUsableCredential('valid-placeholder-inside-opaque-key')).toBe(true);
  });

  test('accepts only absolute HTTP(S) base URLs with a host', () => {
    expect(isUsableHTTPURL('https://api.runanywhere.ai')).toBe(true);
    expect(isUsableHTTPURL(' http://127.0.0.1:8080/v1 ')).toBe(true);
    expect(isUsableHTTPURL('api.runanywhere.ai')).toBe(false);
    expect(isUsableHTTPURL('file:///tmp/config')).toBe(false);
    expect(isUsableHTTPURL('https://<your-host>')).toBe(false);
    expect(isUsableHTTPURL('https://user:secret@example.com')).toBe(false);
    expect(isUsableHTTPURL('https://example.com?api_key=secret')).toBe(false);
    expect(isUsableHTTPURL('https://example.com/#token')).toBe(false);
  });

  test('requires HTTPS only for production validation', () => {
    expect(isUsableHTTPURL('http://127.0.0.1:8080', { requireHTTPS: true })).toBe(false);
    expect(isUsableHTTPURL('https://api.runanywhere.ai', { requireHTTPS: true })).toBe(true);
  });
});
