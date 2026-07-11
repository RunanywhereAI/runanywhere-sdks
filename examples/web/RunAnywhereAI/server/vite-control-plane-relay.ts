import type { IncomingHttpHeaders, IncomingMessage, ServerResponse } from 'node:http';
import type { Plugin } from 'vite';
import { CONTROL_PLANE_RELAY_PREFIX } from '../src/services/control-plane-relay.js';
import { handleControlPlaneRelay } from './control-plane-relay.js';

const MAX_LOCAL_REQUEST_BODY_BYTES = 1024 * 1024;

class LocalBodyLimitExceededError extends Error {
  constructor() {
    super('Local relay body limit exceeded.');
    this.name = 'LocalBodyLimitExceededError';
  }
}

function isEncryptedRequest(request: IncomingMessage): boolean {
  return 'encrypted' in request.socket && request.socket.encrypted === true;
}

function scalarHeaderValue(value: string | readonly string[] | undefined): string | undefined {
  if (typeof value === 'string') return value;
  return value?.length === 1 ? value[0] : undefined;
}

function requestAuthority(headers: IncomingHttpHeaders): string | null {
  const host = scalarHeaderValue(headers.host);
  const http2Authority = scalarHeaderValue(headers[':authority']);
  if (host && http2Authority && host !== http2Authority) return null;

  const authority = host ?? http2Authority;
  if (!authority || !/^[a-z0-9._[\]:-]+$/i.test(authority)) return null;
  return authority;
}

/** Resolve an HTTP/1 Host or HTTP/2 :authority into the exact local URL. */
export function resolveLocalRelayRequestURL(
  relativeURL: string | undefined,
  headers: IncomingHttpHeaders,
  encrypted: boolean,
): URL | null {
  const authority = requestAuthority(headers);
  if (!authority || !relativeURL) return null;
  try {
    return new URL(relativeURL, `${encrypted ? 'https' : 'http'}://${authority}`);
  } catch {
    return null;
  }
}

function requestURL(request: IncomingMessage): URL | null {
  return resolveLocalRelayRequestURL(
    request.url,
    request.headers,
    isEncryptedRequest(request),
  );
}

function isRelayRequest(request: IncomingMessage): boolean {
  const url = requestURL(request);
  return url !== null && (
    url.pathname === CONTROL_PLANE_RELAY_PREFIX
    || url.pathname.startsWith(`${CONTROL_PLANE_RELAY_PREFIX}/`)
  );
}

function firstHeaderValue(
  headers: IncomingHttpHeaders,
  name: keyof IncomingHttpHeaders,
): string | undefined {
  return scalarHeaderValue(headers[name]);
}

function webRequestHeaders(headers: IncomingHttpHeaders): Headers {
  const result = new Headers();
  const allowedHeaders = [
    'accept',
    'apikey',
    'authorization',
    'content-length',
    'content-type',
    'origin',
    'sec-fetch-site',
    'x-sdk-version',
  ] as const;
  for (const name of allowedHeaders) {
    const value = firstHeaderValue(headers, name);
    if (value !== undefined) result.set(name, value);
  }
  return result;
}

async function readLocalRequestBody(request: IncomingMessage): Promise<Buffer> {
  const chunks: Buffer[] = [];
  let totalLength = 0;
  for await (const chunk of request) {
    const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk as Uint8Array);
    totalLength += bytes.byteLength;
    if (totalLength > MAX_LOCAL_REQUEST_BODY_BYTES) {
      request.resume();
      throw new LocalBodyLimitExceededError();
    }
    chunks.push(bytes);
  }
  return Buffer.concat(chunks, totalLength);
}

function writeJsonError(
  response: ServerResponse,
  status: number,
  code: string,
  message: string,
): void {
  if (response.writableEnded) return;
  response.statusCode = status;
  response.setHeader('Cache-Control', 'private, no-store');
  response.setHeader('Content-Type', 'application/json');
  response.end(JSON.stringify({ error: { code, message } }));
}

async function writeWebResponse(response: ServerResponse, result: Response): Promise<void> {
  if (response.writableEnded) return;
  response.statusCode = result.status;
  result.headers.forEach((value, name) => response.setHeader(name, value));
  const body = Buffer.from(await result.arrayBuffer());
  response.end(body);
}

async function relayLocalRequest(
  request: IncomingMessage,
  response: ServerResponse,
  apiKey: string | undefined,
): Promise<void> {
  const url = requestURL(request);
  if (url === null) {
    writeJsonError(response, 400, 'invalid_request_url', 'The relay request URL is invalid.');
    return;
  }

  let body: Buffer;
  try {
    body = await readLocalRequestBody(request);
  } catch (error) {
    if (error instanceof LocalBodyLimitExceededError) {
      writeJsonError(response, 413, 'body_too_large', 'The relay request body is too large.');
      return;
    }
    writeJsonError(response, 400, 'invalid_body', 'The relay request body could not be read.');
    return;
  }

  const controller = new AbortController();
  const abort = (): void => controller.abort();
  request.once('aborted', abort);
  response.once('close', abort);
  try {
    const method = request.method ?? 'GET';
    const hasBody = body.byteLength > 0 && method !== 'GET' && method !== 'HEAD';
    const webBody = hasBody ? new Uint8Array(body).buffer : undefined;
    const webRequest = new Request(url, {
      method,
      headers: webRequestHeaders(request.headers),
      body: webBody,
      signal: controller.signal,
    });
    const result = await handleControlPlaneRelay(webRequest, { apiKey });
    await writeWebResponse(response, result);
  } catch {
    writeJsonError(response, 500, 'local_relay_failure', 'The local relay failed.');
  } finally {
    request.off('aborted', abort);
    response.off('close', abort);
  }
}

/** Install the same fixed relay contract in Vite dev and preview servers. */
export function viteControlPlaneRelayPlugin(apiKey: string | undefined): Plugin {
  const installMiddleware = (
    request: IncomingMessage,
    response: ServerResponse,
    next: () => void,
  ): void => {
    if (!isRelayRequest(request)) {
      next();
      return;
    }
    void relayLocalRequest(request, response, apiKey);
  };

  return {
    name: 'runanywhere-control-plane-relay',
    configureServer(server) {
      server.middlewares.use(installMiddleware);
    },
    configurePreviewServer(server) {
      server.middlewares.use(installMiddleware);
    },
  };
}
