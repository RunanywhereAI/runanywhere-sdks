import {
  CONTROL_PLANE_RELAY_PREFIX,
  FIRST_PARTY_CONTROL_PLANE_BASE_URL,
  FIRST_PARTY_CONTROL_PLANE_RELAY_CREDENTIAL,
} from '../src/services/control-plane-relay.js';

const AUTHENTICATE_PATH = '/api/v1/auth/sdk/authenticate';
const REFRESH_PATH = '/api/v1/auth/sdk/refresh';
const DEVICE_REGISTRATION_PATH = '/api/v1/devices/register';
const MODEL_ASSIGNMENTS_PATH = '/api/v1/model-assignments/for-sdk';

const MAX_REQUEST_BODY_BYTES = 1024 * 1024;
const MAX_RESPONSE_BODY_BYTES = 2 * 1024 * 1024;
// Leave enough of the Vercel function's 30-second budget to construct and
// flush the relay's structured 504 response after an upstream timeout.
const DEFAULT_UPSTREAM_TIMEOUT_MS = 25_000;
const MAX_AUTHORIZATION_LENGTH = 4096;
const MAX_SDK_VERSION_LENGTH = 64;
const MAX_RETRY_AFTER_LENGTH = 128;
const SERVER_SECRET_SCAFFOLD_PATTERN =
  /^(?:<your[^>]*>|your(?:[-_ ][a-z0-9]+)+|replace[-_ ]?me|placeholder(?:[-_ ][a-z0-9]+)*)$/i;
const SDK_VERSION_PATTERN = /^[a-z0-9][a-z0-9._+-]*$/i;
const BEARER_AUTHORIZATION_PATTERN = /^Bearer [\x21-\x7e]+$/;

type RelayFetch = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

interface ControlPlaneRelayOptions {
  apiKey: string | null | undefined;
  fetchImplementation?: RelayFetch;
  timeoutMs?: number;
}

interface AllowedRoute {
  method: 'GET' | 'POST';
  path: string;
  requiresAuthorization: boolean;
}

interface RelayErrorEnvelope {
  error: {
    code: string;
    message: string;
  };
}

const ALLOWED_ROUTES: readonly AllowedRoute[] = [
  {
    method: 'POST',
    path: AUTHENTICATE_PATH,
    requiresAuthorization: false,
  },
  {
    method: 'POST',
    path: REFRESH_PATH,
    requiresAuthorization: false,
  },
  {
    method: 'POST',
    path: DEVICE_REGISTRATION_PATH,
    requiresAuthorization: true,
  },
  {
    method: 'GET',
    path: MODEL_ASSIGNMENTS_PATH,
    requiresAuthorization: true,
  },
] as const;

class BodyLimitExceededError extends Error {
  constructor() {
    super('Body limit exceeded.');
    this.name = 'BodyLimitExceededError';
  }
}

function errorResponse(
  status: number,
  code: string,
  message: string,
  additionalHeaders?: Readonly<Record<string, string>>,
): Response {
  const body: RelayErrorEnvelope = { error: { code, message } };
  return Response.json(body, {
    status,
    headers: {
      'Cache-Control': 'private, no-store',
      ...additionalHeaders,
    },
  });
}

function configuredServerCredential(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  if (!trimmed || SERVER_SECRET_SCAFFOLD_PATTERN.test(trimmed)) return null;
  return trimmed;
}

function allowedRoute(path: string, method: string): AllowedRoute | null {
  return ALLOWED_ROUTES.find(
    (candidate) => candidate.path === path && candidate.method === method,
  ) ?? null;
}

function allowedMethodsForPath(path: string): readonly AllowedRoute['method'][] {
  return ALLOWED_ROUTES
    .filter((candidate) => candidate.path === path)
    .map((candidate) => candidate.method);
}

function isJsonContentType(value: string | null): boolean {
  return value?.split(';', 1)[0]?.trim().toLowerCase() === 'application/json';
}

function validatedSDKVersion(value: string | null): string | null {
  const trimmed = value?.trim();
  if (
    !trimmed
    || trimmed.length > MAX_SDK_VERSION_LENGTH
    || !SDK_VERSION_PATTERN.test(trimmed)
  ) {
    return null;
  }
  return trimmed;
}

function validatedAuthorization(value: string | null): string | null {
  if (
    !value
    || value.length > MAX_AUTHORIZATION_LENGTH
    || !BEARER_AUTHORIZATION_PATTERN.test(value)
  ) {
    return null;
  }
  return value;
}

function contentLengthExceedsLimit(value: string | null, limit: number): boolean {
  if (value === null) return false;
  if (!/^\d+$/.test(value)) return true;
  return Number(value) > limit;
}

async function readBoundedStream(
  stream: ReadableStream<Uint8Array> | null,
  limit: number,
): Promise<Uint8Array<ArrayBuffer>> {
  if (stream === null) return new Uint8Array(new ArrayBuffer(0));

  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let totalLength = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      totalLength += value.byteLength;
      if (totalLength > limit) throw new BodyLimitExceededError();
      chunks.push(value);
    }
  } catch (error) {
    await reader.cancel().catch(() => undefined);
    throw error;
  } finally {
    reader.releaseLock();
  }

  const body = new Uint8Array(new ArrayBuffer(totalLength));
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return body;
}

function parseJsonObject(body: Uint8Array): Readonly<Record<string, unknown>> | null {
  try {
    const text = new TextDecoder('utf-8', { fatal: true }).decode(body);
    const parsed: unknown = JSON.parse(text);
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) return null;
    return parsed as Readonly<Record<string, unknown>>;
  } catch {
    return null;
  }
}

function requestPath(url: URL): string | null {
  if (
    url.username.length > 0
    || url.password.length > 0
    || url.search.length > 0
    || url.hash.length > 0
    || url.pathname.length > 256
    || url.pathname.includes('%')
    || url.pathname.includes('\\')
    || url.pathname.includes('//')
    || !url.pathname.startsWith(`${CONTROL_PLANE_RELAY_PREFIX}/`)
  ) {
    return null;
  }

  const path = url.pathname.slice(CONTROL_PLANE_RELAY_PREFIX.length);
  return path.startsWith('/') ? path : null;
}

function requestIsSameOrigin(request: Request, url: URL): boolean {
  const origin = request.headers.get('origin');
  if (origin !== null && origin !== url.origin) return false;

  const fetchSite = request.headers.get('sec-fetch-site');
  if (fetchSite !== null && fetchSite !== 'same-origin') return false;

  // The relay is browser-only. Requiring at least one browser context header
  // blocks bare server-to-server clients by default; Vercel WAF supplies the
  // globally deployed abuse boundary for headers that a custom client spoofs.
  return origin !== null || fetchSite !== null;
}

function safeResponseHeaders(upstream: Response): Headers {
  const headers = new Headers({ 'Cache-Control': 'private, no-store' });
  const contentType = upstream.headers.get('content-type');
  if (contentType !== null && contentType.length <= 256) {
    headers.set('Content-Type', contentType);
  }
  const retryAfter = upstream.headers.get('retry-after');
  if (
    retryAfter !== null
    && retryAfter.length <= MAX_RETRY_AFTER_LENGTH
    && /^[\x20-\x7e]+$/.test(retryAfter)
  ) {
    headers.set('Retry-After', retryAfter);
  }
  return headers;
}

function safeRetryAfterHeader(upstream: Response): Readonly<Record<string, string>> | undefined {
  const retryAfter = upstream.headers.get('retry-after');
  if (
    retryAfter === null
    || retryAfter.length > MAX_RETRY_AFTER_LENGTH
    || !/^[\x20-\x7e]+$/.test(retryAfter)
  ) {
    return undefined;
  }
  return { 'Retry-After': retryAfter };
}

function abortControllerForRequest(
  request: Request,
  timeoutMs: number,
): {
  controller: AbortController;
  didTimeout: () => boolean;
  dispose: () => void;
} {
  const controller = new AbortController();
  let timedOut = false;
  const abortForClient = (): void => controller.abort();
  request.signal.addEventListener('abort', abortForClient, { once: true });
  const timeout = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, timeoutMs);

  return {
    controller,
    didTimeout: () => timedOut,
    dispose: () => {
      clearTimeout(timeout);
      request.signal.removeEventListener('abort', abortForClient);
    },
  };
}

/**
 * Relay the exact production control-plane contract to one fixed upstream.
 *
 * This function intentionally emits no logs. Request metadata can contain
 * access and refresh tokens, and the injected server credential must never be
 * observable in application logs or returned error details.
 */
export async function handleControlPlaneRelay(
  request: Request,
  options: ControlPlaneRelayOptions,
): Promise<Response> {
  let url: URL;
  try {
    url = new URL(request.url);
  } catch {
    return errorResponse(400, 'invalid_request_url', 'The relay request URL is invalid.');
  }

  if (url.search.length > 0) {
    return errorResponse(400, 'query_not_allowed', 'Relay query parameters are not allowed.');
  }

  const path = requestPath(url);
  if (path === null) {
    return errorResponse(404, 'route_not_allowed', 'The requested relay route is not available.');
  }

  const route = allowedRoute(path, request.method);
  if (route === null) {
    const allowedMethods = allowedMethodsForPath(path);
    if (allowedMethods.length > 0) {
      return errorResponse(
        405,
        'method_not_allowed',
        'The request method is not allowed for this relay route.',
        { Allow: allowedMethods.join(', ') },
      );
    }
    return errorResponse(404, 'route_not_allowed', 'The requested relay route is not available.');
  }

  if (!requestIsSameOrigin(request, url)) {
    return errorResponse(403, 'cross_origin_denied', 'Cross-origin relay requests are denied.');
  }

  if (request.headers.get('apikey') !== FIRST_PARTY_CONTROL_PLANE_RELAY_CREDENTIAL) {
    return errorResponse(401, 'relay_credential_required', 'The relay credential is invalid.');
  }

  const serverCredential = configuredServerCredential(options.apiKey);
  if (serverCredential === null) {
    return errorResponse(
      503,
      'relay_not_configured',
      'The control-plane relay is not configured.',
    );
  }

  const incomingAuthorization = request.headers.get('authorization');
  const authorization = validatedAuthorization(incomingAuthorization);
  if (route.requiresAuthorization && authorization === null) {
    return errorResponse(401, 'authorization_required', 'A valid bearer token is required.');
  }
  if (!route.requiresAuthorization && incomingAuthorization !== null) {
    return errorResponse(
      400,
      'authorization_not_allowed',
      'Authorization is not accepted for this relay route.',
    );
  }

  let serializedBody: string | undefined;
  if (route.method === 'GET') {
    if (
      request.body !== null
      || contentLengthExceedsLimit(request.headers.get('content-length'), 0)
    ) {
      return errorResponse(400, 'body_not_allowed', 'This relay route does not accept a body.');
    }
  } else {
    if (!isJsonContentType(request.headers.get('content-type'))) {
      return errorResponse(415, 'json_required', 'Relay request bodies must use application/json.');
    }
    if (contentLengthExceedsLimit(
      request.headers.get('content-length'),
      MAX_REQUEST_BODY_BYTES,
    )) {
      return errorResponse(413, 'body_too_large', 'The relay request body is too large.');
    }

    let bodyBytes: Uint8Array<ArrayBuffer>;
    try {
      bodyBytes = await readBoundedStream(request.body, MAX_REQUEST_BODY_BYTES);
    } catch (error) {
      if (error instanceof BodyLimitExceededError) {
        return errorResponse(413, 'body_too_large', 'The relay request body is too large.');
      }
      return errorResponse(400, 'invalid_body', 'The relay request body could not be read.');
    }

    const jsonBody = parseJsonObject(bodyBytes);
    if (jsonBody === null) {
      return errorResponse(400, 'invalid_json', 'The relay request body must be a JSON object.');
    }

    if (route.path === AUTHENTICATE_PATH) {
      if (jsonBody.api_key !== FIRST_PARTY_CONTROL_PLANE_RELAY_CREDENTIAL) {
        return errorResponse(
          400,
          'relay_credential_mismatch',
          'The authenticate payload does not match the relay contract.',
        );
      }
      serializedBody = JSON.stringify({ ...jsonBody, api_key: serverCredential });
    } else {
      serializedBody = JSON.stringify(jsonBody);
    }
  }

  const upstreamHeaders = new Headers({
    Accept: 'application/json',
    apikey: serverCredential,
    'X-Platform': 'web',
    'X-SDK-Client': 'RunAnywhereSDK',
  });
  if (route.method === 'POST') upstreamHeaders.set('Content-Type', 'application/json');
  if (authorization !== null) upstreamHeaders.set('Authorization', authorization);
  const sdkVersion = validatedSDKVersion(request.headers.get('x-sdk-version'));
  if (sdkVersion !== null) upstreamHeaders.set('X-SDK-Version', sdkVersion);

  const upstreamURL = new URL(route.path, FIRST_PARTY_CONTROL_PLANE_BASE_URL);
  const timeoutMs = options.timeoutMs ?? DEFAULT_UPSTREAM_TIMEOUT_MS;
  const abort = abortControllerForRequest(
    request,
    Number.isFinite(timeoutMs) && timeoutMs > 0 ? timeoutMs : DEFAULT_UPSTREAM_TIMEOUT_MS,
  );

  try {
    const fetchImplementation = options.fetchImplementation ?? fetch;
    const upstream = await fetchImplementation(upstreamURL, {
      method: route.method,
      headers: upstreamHeaders,
      body: serializedBody,
      redirect: 'manual',
      signal: abort.controller.signal,
    });

    if (upstream.status >= 300 && upstream.status < 400) {
      return errorResponse(502, 'upstream_redirect_denied', 'The upstream response was rejected.');
    }

    if (!upstream.ok) {
      await upstream.body?.cancel().catch(() => undefined);
      return errorResponse(
        upstream.status,
        'upstream_rejected',
        'The control plane rejected the request.',
        safeRetryAfterHeader(upstream),
      );
    }

    let responseBody: Uint8Array<ArrayBuffer>;
    try {
      responseBody = await readBoundedStream(upstream.body, MAX_RESPONSE_BODY_BYTES);
    } catch {
      return abort.didTimeout()
        ? errorResponse(504, 'upstream_timeout', 'The control plane did not respond in time.')
        : errorResponse(502, 'invalid_upstream_response', 'The upstream response was rejected.');
    }

    const body = upstream.status === 204 || responseBody.byteLength === 0
      ? null
      : responseBody;
    return new Response(body, {
      status: upstream.status,
      headers: safeResponseHeaders(upstream),
    });
  } catch {
    return abort.didTimeout()
      ? errorResponse(504, 'upstream_timeout', 'The control plane did not respond in time.')
      : errorResponse(502, 'upstream_unavailable', 'The control plane is unavailable.');
  } finally {
    abort.dispose();
  }
}
