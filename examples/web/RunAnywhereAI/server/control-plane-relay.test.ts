import { describe, expect, it, vi } from 'vitest';
import {
  CONTROL_PLANE_RELAY_PREFIX,
  FIRST_PARTY_CONTROL_PLANE_BASE_URL,
  FIRST_PARTY_CONTROL_PLANE_RELAY_CREDENTIAL,
} from '../src/services/control-plane-relay';
import { handleControlPlaneRelay } from './control-plane-relay';

const TEST_SERVER_CREDENTIAL = 'test-server-credential';
const TEST_ORIGIN = 'https://web.runanywhere.test';
const AUTHENTICATE_PATH = '/api/v1/auth/sdk/authenticate';
const REFRESH_PATH = '/api/v1/auth/sdk/refresh';
const DEVICE_REGISTRATION_PATH = '/api/v1/devices/register';
const MODEL_ASSIGNMENTS_PATH = '/api/v1/model-assignments/for-sdk';

type RelayOptions = Parameters<typeof handleControlPlaneRelay>[1];
type RelayFetch = NonNullable<RelayOptions['fetchImplementation']>;

interface RelayRequestOptions {
  method?: string;
  body?: Readonly<Record<string, unknown>> | string;
  headers?: Readonly<Record<string, string>>;
  query?: string;
}

function relayRequest(path: string, options: RelayRequestOptions = {}): Request {
  const method = options.method ?? 'POST';
  const headers = new Headers({
    apikey: FIRST_PARTY_CONTROL_PLANE_RELAY_CREDENTIAL,
    Origin: TEST_ORIGIN,
    'Sec-Fetch-Site': 'same-origin',
    'X-SDK-Version': '0.19.13',
    ...options.headers,
  });
  const hasBody = options.body !== undefined;
  if (hasBody && !headers.has('Content-Type')) headers.set('Content-Type', 'application/json');
  const body = typeof options.body === 'string'
    ? options.body
    : options.body === undefined
      ? undefined
      : JSON.stringify(options.body);
  return new Request(
    `${TEST_ORIGIN}${CONTROL_PLANE_RELAY_PREFIX}${path}${options.query ?? ''}`,
    { method, headers, body },
  );
}

async function errorCode(response: Response): Promise<string> {
  const decoded: unknown = await response.json();
  if (
    typeof decoded !== 'object'
    || decoded === null
    || !('error' in decoded)
    || typeof decoded.error !== 'object'
    || decoded.error === null
    || !('code' in decoded.error)
    || typeof decoded.error.code !== 'string'
  ) {
    throw new Error('Expected a structured relay error.');
  }
  return decoded.error.code;
}

describe('server control-plane relay', () => {
  it.each([
    {
      method: 'POST',
      path: AUTHENTICATE_PATH,
      body: { api_key: FIRST_PARTY_CONTROL_PLANE_RELAY_CREDENTIAL, device_id: 'device' },
      authorization: false,
    },
    {
      method: 'POST',
      path: REFRESH_PATH,
      body: { device_id: 'device', refresh_token: 'refresh-token' },
      authorization: false,
    },
    {
      method: 'POST',
      path: DEVICE_REGISTRATION_PATH,
      body: { device_id: 'device', platform: 'web' },
      authorization: true,
    },
    {
      method: 'GET',
      path: MODEL_ASSIGNMENTS_PATH,
      body: undefined,
      authorization: true,
    },
  ])('allows only $method $path', async ({ method, path, body, authorization }) => {
    const fetchImplementation = vi.fn<RelayFetch>(async () => Response.json({ ok: true }));
    const response = await handleControlPlaneRelay(relayRequest(path, {
      method,
      body,
      headers: authorization ? { Authorization: 'Bearer access-token' } : undefined,
    }), {
      apiKey: TEST_SERVER_CREDENTIAL,
      fetchImplementation,
    });

    expect(response.status).toBe(200);
    expect(fetchImplementation).toHaveBeenCalledOnce();
    expect(String(fetchImplementation.mock.calls[0]?.[0])).toBe(
      `${FIRST_PARTY_CONTROL_PLANE_BASE_URL}${path}`,
    );
  });

  it('replaces both public authenticate markers with the server credential', async () => {
    let upstreamHeaders = new Headers();
    let upstreamBody = '';
    const fetchImplementation: RelayFetch = async (_input, init) => {
      upstreamHeaders = new Headers(init?.headers);
      upstreamBody = String(init?.body ?? '');
      return Response.json({ access_token: 'response-token' });
    };
    const response = await handleControlPlaneRelay(relayRequest(AUTHENTICATE_PATH, {
      body: {
        api_key: FIRST_PARTY_CONTROL_PLANE_RELAY_CREDENTIAL,
        device_id: 'device',
        platform: 'web',
      },
    }), { apiKey: TEST_SERVER_CREDENTIAL, fetchImplementation });

    expect(response.status).toBe(200);
    expect(upstreamHeaders.get('apikey')).toBe(TEST_SERVER_CREDENTIAL);
    expect(JSON.parse(upstreamBody)).toMatchObject({ api_key: TEST_SERVER_CREDENTIAL });
    expect(upstreamBody).not.toContain(FIRST_PARTY_CONTROL_PLANE_RELAY_CREDENTIAL);
  });

  it('rebuilds route-scoped upstream headers and strips browser metadata', async () => {
    let upstreamHeaders = new Headers();
    const fetchImplementation: RelayFetch = async (_input, init) => {
      upstreamHeaders = new Headers(init?.headers);
      return new Response('{}', {
        headers: {
          'Content-Type': 'application/json',
          'Set-Cookie': 'session=unsafe',
          Location: 'https://attacker.invalid',
          'Access-Control-Allow-Origin': '*',
          Server: 'upstream',
          'Retry-After': '3',
        },
      });
    };
    const response = await handleControlPlaneRelay(relayRequest(DEVICE_REGISTRATION_PATH, {
      body: { device_id: 'device' },
      headers: {
        Authorization: 'Bearer access-token',
        Cookie: 'private=cookie',
        Referer: 'https://attacker.invalid',
        'X-Forwarded-Host': 'attacker.invalid',
        'X-Platform': 'spoofed',
        'X-SDK-Client': 'spoofed',
      },
    }), { apiKey: TEST_SERVER_CREDENTIAL, fetchImplementation });

    expect(upstreamHeaders.get('authorization')).toBe('Bearer access-token');
    expect(upstreamHeaders.get('x-platform')).toBe('web');
    expect(upstreamHeaders.get('x-sdk-client')).toBe('RunAnywhereSDK');
    expect(upstreamHeaders.get('cookie')).toBeNull();
    expect(upstreamHeaders.get('referer')).toBeNull();
    expect(upstreamHeaders.get('x-forwarded-host')).toBeNull();
    expect(response.headers.get('cache-control')).toBe('private, no-store');
    expect(response.headers.get('retry-after')).toBe('3');
    expect(response.headers.get('set-cookie')).toBeNull();
    expect(response.headers.get('location')).toBeNull();
    expect(response.headers.get('access-control-allow-origin')).toBeNull();
    expect(response.headers.get('server')).toBeNull();
  });

  it.each([
    { path: '/v1/health', method: 'GET', expectedStatus: 404 },
    { path: '/api/v1/models/available', method: 'GET', expectedStatus: 404 },
    { path: `${AUTHENTICATE_PATH}/`, method: 'POST', expectedStatus: 404 },
    { path: AUTHENTICATE_PATH, method: 'GET', expectedStatus: 405 },
    { path: '/%2e%2e/api/v1/devices/register', method: 'POST', expectedStatus: 404 },
  ])('rejects $method $path', async ({ path, method, expectedStatus }) => {
    const fetchImplementation = vi.fn<RelayFetch>();
    const response = await handleControlPlaneRelay(relayRequest(path, { method }), {
      apiKey: TEST_SERVER_CREDENTIAL,
      fetchImplementation,
    });

    expect(response.status).toBe(expectedStatus);
    expect(fetchImplementation).not.toHaveBeenCalled();
    expect(response.headers.get('cache-control')).toBe('private, no-store');
  });

  it('rejects every query before contacting the upstream', async () => {
    const fetchImplementation = vi.fn<RelayFetch>();
    const response = await handleControlPlaneRelay(relayRequest(AUTHENTICATE_PATH, {
      body: { api_key: FIRST_PARTY_CONTROL_PLANE_RELAY_CREDENTIAL },
      query: '?target=https://attacker.invalid',
    }), { apiKey: TEST_SERVER_CREDENTIAL, fetchImplementation });

    expect(response.status).toBe(400);
    expect(await errorCode(response)).toBe('query_not_allowed');
    expect(fetchImplementation).not.toHaveBeenCalled();
  });

  it('rejects cross-origin, missing-marker, and missing-server-key requests safely', async () => {
    const crossOrigin = await handleControlPlaneRelay(relayRequest(AUTHENTICATE_PATH, {
      body: { api_key: FIRST_PARTY_CONTROL_PLANE_RELAY_CREDENTIAL },
      headers: { Origin: 'https://attacker.invalid' },
    }), { apiKey: TEST_SERVER_CREDENTIAL });
    expect(crossOrigin.status).toBe(403);

    const missingMarker = await handleControlPlaneRelay(relayRequest(AUTHENTICATE_PATH, {
      body: { api_key: FIRST_PARTY_CONTROL_PLANE_RELAY_CREDENTIAL },
      headers: { apikey: 'unexpected-client-value' },
    }), { apiKey: TEST_SERVER_CREDENTIAL });
    expect(missingMarker.status).toBe(401);

    const missingServerKey = await handleControlPlaneRelay(relayRequest(AUTHENTICATE_PATH, {
      body: { api_key: FIRST_PARTY_CONTROL_PLANE_RELAY_CREDENTIAL },
    }), { apiKey: undefined });
    expect(missingServerKey.status).toBe(503);
    expect(JSON.stringify(await missingServerKey.json())).not.toContain(TEST_SERVER_CREDENTIAL);
  });

  it('rejects a bare non-browser client even when it knows the public marker', async () => {
    const request = relayRequest(AUTHENTICATE_PATH, {
      body: { api_key: FIRST_PARTY_CONTROL_PLANE_RELAY_CREDENTIAL },
    });
    request.headers.delete('origin');
    request.headers.delete('sec-fetch-site');

    const fetchImplementation = vi.fn<RelayFetch>();
    const response = await handleControlPlaneRelay(request, {
      apiKey: TEST_SERVER_CREDENTIAL,
      fetchImplementation,
    });

    expect(response.status).toBe(403);
    expect(await errorCode(response)).toBe('cross_origin_denied');
    expect(fetchImplementation).not.toHaveBeenCalled();
  });

  it.each([
    {
      name: 'POST carrying Origin',
      request: () => {
        const request = relayRequest(REFRESH_PATH, {
          body: { device_id: 'device', refresh_token: 'token' },
        });
        request.headers.delete('sec-fetch-site');
        return request;
      },
    },
    {
      name: 'GET carrying Sec-Fetch-Site',
      request: () => {
        const request = relayRequest(MODEL_ASSIGNMENTS_PATH, {
          method: 'GET',
          headers: { Authorization: 'Bearer access-token' },
        });
        request.headers.delete('origin');
        return request;
      },
    },
  ])('accepts a same-origin browser $name', async ({ request }) => {
    const fetchImplementation = vi.fn<RelayFetch>(async () => Response.json({ ok: true }));
    const response = await handleControlPlaneRelay(request(), {
      apiKey: TEST_SERVER_CREDENTIAL,
      fetchImplementation,
    });

    expect(response.status).toBe(200);
    expect(fetchImplementation).toHaveBeenCalledOnce();
  });

  it.each([
    {
      name: 'non-JSON media type',
      request: () => relayRequest(REFRESH_PATH, {
        body: '{}',
        headers: { 'Content-Type': 'text/plain' },
      }),
      status: 415,
    },
    {
      name: 'malformed JSON',
      request: () => relayRequest(REFRESH_PATH, { body: '{' }),
      status: 400,
    },
    {
      name: 'array JSON',
      request: () => relayRequest(REFRESH_PATH, { body: '[]' }),
      status: 400,
    },
    {
      name: 'oversized declared body',
      request: () => relayRequest(REFRESH_PATH, {
        body: '{}',
        headers: { 'Content-Length': String(1024 * 1024 + 1) },
      }),
      status: 413,
    },
  ])('rejects $name', async ({ request, status }) => {
    const fetchImplementation = vi.fn<RelayFetch>();
    const response = await handleControlPlaneRelay(request(), {
      apiKey: TEST_SERVER_CREDENTIAL,
      fetchImplementation,
    });
    expect(response.status).toBe(status);
    expect(fetchImplementation).not.toHaveBeenCalled();
  });

  it('does not forward authorization to authentication routes', async () => {
    const fetchImplementation = vi.fn<RelayFetch>();
    const response = await handleControlPlaneRelay(relayRequest(AUTHENTICATE_PATH, {
      body: { api_key: FIRST_PARTY_CONTROL_PLANE_RELAY_CREDENTIAL },
      headers: { Authorization: 'Bearer access-token' },
    }), { apiKey: TEST_SERVER_CREDENTIAL, fetchImplementation });
    expect(response.status).toBe(400);
    expect(fetchImplementation).not.toHaveBeenCalled();
  });

  it('blocks upstream redirects and returns generic transport failures', async () => {
    const redirect = await handleControlPlaneRelay(relayRequest(REFRESH_PATH, {
      body: { device_id: 'device', refresh_token: 'token' },
    }), {
      apiKey: TEST_SERVER_CREDENTIAL,
      fetchImplementation: async () => new Response(null, {
        status: 302,
        headers: { Location: 'https://attacker.invalid' },
      }),
    });
    expect(redirect.status).toBe(502);
    expect(redirect.headers.get('location')).toBeNull();

    const unavailable = await handleControlPlaneRelay(relayRequest(REFRESH_PATH, {
      body: { device_id: 'device', refresh_token: 'token' },
    }), {
      apiKey: TEST_SERVER_CREDENTIAL,
      fetchImplementation: async () => {
        throw new Error('sensitive network detail');
      },
    });
    expect(unavailable.status).toBe(502);
    expect(JSON.stringify(await unavailable.json())).not.toContain('sensitive network detail');
  });

  it('does not expose an upstream error body or unsafe response headers', async () => {
    const response = await handleControlPlaneRelay(relayRequest(REFRESH_PATH, {
      body: { device_id: 'device', refresh_token: 'token' },
    }), {
      apiKey: TEST_SERVER_CREDENTIAL,
      fetchImplementation: async () => new Response(
        `rejected ${TEST_SERVER_CREDENTIAL}`,
        {
          status: 401,
          headers: {
            Location: 'https://attacker.invalid',
            'Retry-After': '5',
            'Set-Cookie': 'unsafe=true',
          },
        },
      ),
    });

    expect(response.status).toBe(401);
    expect(response.headers.get('retry-after')).toBe('5');
    expect(response.headers.get('location')).toBeNull();
    expect(response.headers.get('set-cookie')).toBeNull();
    expect(JSON.stringify(await response.json())).not.toContain(TEST_SERVER_CREDENTIAL);
  });
});
