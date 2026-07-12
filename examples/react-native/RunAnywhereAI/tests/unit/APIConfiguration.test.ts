import { normalizeAPIConfiguration } from '../../src/services/APIConfiguration';

describe('normalizeAPIConfiguration', () => {
  it('normalizes a credential-bearing HTTPS configuration', () => {
    expect(
      normalizeAPIConfiguration('  client-key-123  ', 'api.example.test')
    ).toEqual({
      apiKey: 'client-key-123',
      baseURL: 'https://api.example.test',
    });
  });

  it('rejects cleartext remote endpoints even in development', () => {
    expect(() =>
      normalizeAPIConfiguration('client-key-123', 'http://api.example.test', {
        allowInsecureLoopback: true,
      })
    ).toThrow('must use HTTPS');
  });

  it('allows explicit loopback HTTP only when development opts in', () => {
    expect(
      normalizeAPIConfiguration('client-key-123', 'http://127.0.0.1:8080', {
        allowInsecureLoopback: true,
      }).baseURL
    ).toBe('http://127.0.0.1:8080');
    expect(() =>
      normalizeAPIConfiguration('client-key-123', 'http://127.0.0.1:8080')
    ).toThrow('must use HTTPS');
  });

  it.each([
    'https://user:secret@api.example.test',
    'https://api.example.test?token=secret',
    'https://api.example.test#secret',
  ])('rejects secret-bearing URL components: %s', (baseURL) => {
    expect(() => normalizeAPIConfiguration('client-key-123', baseURL)).toThrow(
      'cannot contain credentials'
    );
  });
});
