import { describe, expect, it } from 'vitest';
import { resolveLocalRelayRequestURL } from './vite-control-plane-relay';

const EXACT_RELAY_PATH = '/api/runanywhere/api/v1/auth/sdk/authenticate';

describe('Vite control-plane relay URL adaptation', () => {
  it('preserves an exact HTTP/1 browser relay URL', () => {
    expect(resolveLocalRelayRequestURL(
      EXACT_RELAY_PATH,
      { host: '127.0.0.1:5173' },
      false,
    )?.toString()).toBe(`http://127.0.0.1:5173${EXACT_RELAY_PATH}`);
  });

  it('uses HTTP/2 :authority when Host is absent on HTTPS preview', () => {
    expect(resolveLocalRelayRequestURL(
      EXACT_RELAY_PATH,
      { ':authority': 'localtest.me:43173' },
      true,
    )?.toString()).toBe(`https://localtest.me:43173${EXACT_RELAY_PATH}`);
  });

  it('fails closed when Host and :authority disagree', () => {
    expect(resolveLocalRelayRequestURL(
      EXACT_RELAY_PATH,
      {
        host: 'localtest.me:43173',
        ':authority': 'attacker.invalid',
      },
      true,
    )).toBeNull();
  });
});
