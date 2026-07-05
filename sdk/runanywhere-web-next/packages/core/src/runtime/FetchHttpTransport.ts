/**
 * FetchHttpTransport.ts
 *
 * JS-side implementation of the commons HTTP transport vtable
 * (`rac_http_transport_ops_t` in
 * `sdk/runanywhere-commons/include/rac/infrastructure/http/rac_http_transport.h`),
 * installed via `_rac_http_transport_register_from_js`.
 *
 * Why it exists in web-next:
 *   The built-in `emscripten_fetch` transport (rac_http_client_emscripten.cpp)
 *   issues its request with `EMSCRIPTEN_FETCH_SYNCHRONOUS`, which needs a
 *   separate proxying thread to run the blocking XHR. The web-next WASM is
 *   built single-threaded (threads were reverted for the small speech models),
 *   so that path has no worker to proxy to and every request fails immediately
 *   with status=0 / RAC_ERROR_NETWORK_ERROR — breaking auth, device
 *   registration, model assignments and telemetry.
 *
 *   This transport issues the synchronous XHR directly from JS inside the WASM
 *   worker (where sync XHR with `responseType='arraybuffer'` is permitted and
 *   warning-free), sidestepping emscripten_fetch's threading requirement. It is
 *   the same approach the old `runanywhere-web` SDK shipped.
 *
 * Runs in the WASM worker (the module + heap live there); XHR is available.
 */

import { SDKLogger } from '../Foundation/SDKLogger';
import type { BootModule } from './WasmModuleLoader';

const logger = new SDKLogger('FetchHttpTransport');

// rac_error.h mirrors.
const RAC_SUCCESS = 0;
const RAC_ERROR_NETWORK_ERROR = -151;
const RAC_ERROR_CANCELLED = -380;
const RAC_TRUE = 1;
const RAC_FALSE = 0;

/**
 * Chunk size used to fan a fully-received body out through the C-side
 * `rac_http_body_chunk_fn` callback. Sync XHR cannot expose a true network
 * stream (the browser holds the response until completion), but splitting the
 * in-memory buffer into bounded chunks keeps the WASM heap-scratch footprint
 * small and gives the C-side progress callback meaningful granularity. Mirrors
 * `RAC_HTTP_DEFAULT_CHUNK_SIZE_BYTES` (1 MiB) in `rac_http_transport.h`.
 */
const STREAM_CHUNK_SIZE = 1 * 1024 * 1024;

interface HTTPHeader {
  name: string;
  value: string;
}

/**
 * Superset of `BootModule` with the runtime helpers and offset accessors this
 * transport needs. All are optional at the type level so a build missing any of
 * them degrades gracefully (the loader falls back to emscripten_fetch).
 */
export interface FetchHttpTransportModule extends BootModule {
  _rac_http_transport_register_from_js?(
    requestSendPtr: number,
    requestStreamPtr: number,
    requestResumePtr: number,
  ): number;

  getWasmTableEntry?(ptr: number): (...args: Array<number | bigint>) => number;

  _rac_wasm_offsetof_http_request_method?(): number;
  _rac_wasm_offsetof_http_request_url?(): number;
  _rac_wasm_offsetof_http_request_headers?(): number;
  _rac_wasm_offsetof_http_request_header_count?(): number;
  _rac_wasm_offsetof_http_request_body_bytes?(): number;
  _rac_wasm_offsetof_http_request_body_len?(): number;
  _rac_wasm_offsetof_http_request_timeout_ms?(): number;
  _rac_wasm_offsetof_http_request_follow_redirects?(): number;

  _rac_wasm_sizeof_http_header_kv?(): number;
  _rac_wasm_offsetof_http_header_kv_name?(): number;
  _rac_wasm_offsetof_http_header_kv_value?(): number;

  _rac_wasm_offsetof_http_response_status?(): number;
  _rac_wasm_offsetof_http_response_redirected_url?(): number;
  _rac_wasm_offsetof_http_response_headers?(): number;
  _rac_wasm_offsetof_http_response_header_count?(): number;
  _rac_wasm_offsetof_http_response_body_bytes?(): number;
  _rac_wasm_offsetof_http_response_body_len?(): number;
}

function i64ToNumber(value: number | bigint): number {
  return typeof value === 'bigint' ? Number(value) : value;
}

/**
 * JS-side HTTP transport installed via the commons transport vtable.
 *
 * Created by `FetchHttpTransport.install(module)`. Holds the `addFunction`
 * trampolines so `uninstall()` can remove them during teardown.
 */
export class FetchHttpTransport {
  private requestSendPtr = 0;
  private requestStreamPtr = 0;
  private requestResumePtr = 0;

  private constructor(private readonly m: FetchHttpTransportModule) {}

  /**
   * Install the JS-side HTTP transport into the given module. Returns the
   * transport instance, or `null` if the module lacks
   * `_rac_http_transport_register_from_js` (caller should keep the
   * emscripten_fetch fallback in that case).
   */
  static install(m: FetchHttpTransportModule): FetchHttpTransport | null {
    if (typeof m._rac_http_transport_register_from_js !== 'function') {
      logger.debug(
        'install: module missing _rac_http_transport_register_from_js; ' +
          'skipping JS HTTP transport (emscripten_fetch fallback remains active)',
      );
      return null;
    }
    const transport = new FetchHttpTransport(m);
    if (!transport.doInstall()) return null;
    return transport;
  }

  /** Remove the JS adapter and free the function-table slots. Idempotent. */
  uninstall(): void {
    if (typeof this.m._rac_http_transport_register_from_js === 'function') {
      try {
        this.m._rac_http_transport_register_from_js(0, 0, 0);
      } catch (err) {
        logger.warning(`uninstall: register(0,0,0) threw: ${err instanceof Error ? err.message : String(err)}`);
      }
    }
    for (const ptr of [this.requestSendPtr, this.requestStreamPtr, this.requestResumePtr]) {
      if (ptr !== 0) {
        try {
          this.m.removeFunction(ptr);
        } catch {
          /* noop */
        }
      }
    }
    this.requestSendPtr = 0;
    this.requestStreamPtr = 0;
    this.requestResumePtr = 0;
  }

  // Implementation

  private doInstall(): boolean {
    // Signatures (i=i32 pointer, j=i64):
    //   request_send:   (user_data*, req*, out_resp*) -> i32                  'iiii'
    //   request_stream: (user_data*, req*, cb*, cb_ud*, out_meta*) -> i32     'iiiiii'
    //   request_resume: (user_data*, req*, resume_j, cb*, cb_ud*, out_meta*)  'iiijiii'
    this.requestSendPtr = this.m.addFunction(
      ((userData: number | bigint, reqPtr: number | bigint, outRespPtr: number | bigint) =>
        this.runSend(Number(userData), Number(reqPtr), Number(outRespPtr))) as (...a: never[]) => unknown,
      'iiii',
    );

    this.requestStreamPtr = this.m.addFunction(
      ((
        userData: number | bigint,
        reqPtr: number | bigint,
        cbPtr: number | bigint,
        cbUd: number | bigint,
        outMetaPtr: number | bigint,
      ) =>
        this.runStream(
          Number(userData),
          Number(reqPtr),
          Number(cbPtr),
          Number(cbUd),
          Number(outMetaPtr),
          /*resumeFromByte=*/ 0,
        )) as (...a: never[]) => unknown,
      'iiiiii',
    );

    this.requestResumePtr = this.m.addFunction(
      ((
        userData: number | bigint,
        reqPtr: number | bigint,
        resumeRaw: number | bigint,
        cbPtr: number | bigint,
        cbUd: number | bigint,
        outMetaPtr: number | bigint,
      ) =>
        this.runStream(
          Number(userData),
          Number(reqPtr),
          Number(cbPtr),
          Number(cbUd),
          Number(outMetaPtr),
          i64ToNumber(resumeRaw),
        )) as (...a: never[]) => unknown,
      'iiijiii',
    );

    const registerFn = this.m._rac_http_transport_register_from_js;
    if (!registerFn) return false;

    const rc = registerFn(this.requestSendPtr, this.requestStreamPtr, this.requestResumePtr);
    if (rc !== RAC_SUCCESS) {
      logger.warning(`register_from_js returned rc=${rc}; uninstalling`);
      this.uninstall();
      return false;
    }
    logger.info('JS HTTP transport activated (send/stream/resume via worker XHR)');
    return true;
  }

  /**
   * `request_send` — single-shot blocking request that buffers the full
   * response body into `body_bytes`/`body_len`.
   */
  private runSend(userData: number, reqPtr: number, outRespPtr: number): number {
    void userData;
    try {
      const req = this.readRequest(reqPtr);
      const xhr = new XMLHttpRequest();
      xhr.open(req.method, req.url, /*async=*/ false);
      let useBinaryTextFallback = false;
      try {
        xhr.responseType = 'arraybuffer';
      } catch {
        useBinaryTextFallback = true;
        xhr.overrideMimeType('text/plain; charset=x-user-defined');
      }

      for (const h of req.headers) {
        try {
          xhr.setRequestHeader(h.name, h.value);
        } catch {
          /* browsers forbid a few reserved headers; ignore. */
        }
      }
      if (req.timeoutMs > 0) xhr.timeout = req.timeoutMs;

      const t0 = this.now();
      xhr.send(this.toSendBody(req.body));
      const elapsedMs = Math.max(0, Math.round(this.now() - t0));

      const status = xhr.status | 0;
      if (status === 0) {
        this.writeResponse(outRespPtr, { status: 0, redirectedUrl: req.url, headers: [], elapsedMs });
        return RAC_ERROR_NETWORK_ERROR;
      }

      const body =
        xhr.response instanceof ArrayBuffer
          ? new Uint8Array(xhr.response)
          : useBinaryTextFallback
            ? this.binaryTextToBytes(xhr.responseText)
            : new Uint8Array(0);

      const responseHeaders = this.parseResponseHeaders(xhr.getAllResponseHeaders());
      const redirectedUrl = xhr.responseURL && xhr.responseURL.length > 0 ? xhr.responseURL : req.url;

      this.writeResponse(outRespPtr, { status, redirectedUrl, headers: responseHeaders, elapsedMs, bodyBytes: body });
      return RAC_SUCCESS;
    } catch (err) {
      logger.warning(`runSend failed: ${err instanceof Error ? err.message : String(err)}`);
      try {
        this.writeResponse(outRespPtr, { status: 0, redirectedUrl: '', headers: [], elapsedMs: 0 });
      } catch {
        /* noop */
      }
      return RAC_ERROR_NETWORK_ERROR;
    }
  }

  /**
   * Shared implementation for `request_stream` and `request_resume`. Issues a
   * synchronous XHR and streams the response back through the C-side chunk
   * callback; leaves `body_bytes`/`body_len` at zero per the streaming contract.
   */
  private runStream(
    userData: number,
    reqPtr: number,
    cbPtr: number,
    cbUd: number,
    outMetaPtr: number,
    resumeFromByte: number,
  ): number {
    void userData;
    try {
      const req = this.readRequest(reqPtr);
      const xhr = new XMLHttpRequest();
      xhr.open(req.method, req.url, /*async=*/ false);
      let useBinaryTextFallback = false;
      try {
        xhr.responseType = 'arraybuffer';
      } catch {
        useBinaryTextFallback = true;
        xhr.overrideMimeType('text/plain; charset=x-user-defined');
      }

      for (const h of req.headers) {
        try {
          xhr.setRequestHeader(h.name, h.value);
        } catch {
          /* noop */
        }
      }
      if (resumeFromByte > 0) {
        try {
          xhr.setRequestHeader('Range', `bytes=${resumeFromByte}-`);
        } catch {
          /* noop */
        }
      }
      if (req.timeoutMs > 0) xhr.timeout = req.timeoutMs;

      const t0 = this.now();
      xhr.send(this.toSendBody(req.body));
      const elapsedMs = Math.max(0, Math.round(this.now() - t0));

      const status = xhr.status | 0;
      if (status === 0) {
        this.writeResponse(outMetaPtr, { status: 0, redirectedUrl: req.url, headers: [], elapsedMs });
        return RAC_ERROR_NETWORK_ERROR;
      }

      const body =
        xhr.response instanceof ArrayBuffer
          ? new Uint8Array(xhr.response)
          : useBinaryTextFallback
            ? this.binaryTextToBytes(xhr.responseText)
            : new Uint8Array(0);
      const bodyLength = body.length;

      // When the server honored the Range request (206) the body holds only the
      // remaining bytes; fold resumeFromByte into the counters so the C-side
      // callback sees a monotonic absolute file position and correct length.
      const honoredRange = status === 206 && resumeFromByte > 0;
      const baseOffset = honoredRange ? resumeFromByte : 0;
      const total = honoredRange ? bodyLength + resumeFromByte : bodyLength;

      let cancelled = false;
      if (cbPtr !== 0 && bodyLength > 0) {
        let offset = 0;
        while (offset < bodyLength) {
          const end = Math.min(offset + STREAM_CHUNK_SIZE, bodyLength);
          const chunk = body.subarray(offset, end);
          const keepGoing = this.invokeChunkCallback(cbPtr, chunk, baseOffset + end, total, cbUd);
          if (keepGoing === RAC_FALSE) {
            cancelled = true;
            break;
          }
          offset = end;
        }
      }

      const responseHeaders = this.parseResponseHeaders(xhr.getAllResponseHeaders());
      const redirectedUrl = xhr.responseURL && xhr.responseURL.length > 0 ? xhr.responseURL : req.url;

      // Emit X-RAC-Range-Honored so the download orchestrator can distinguish a
      // genuine 206 partial-content reply from a CDN wrapping a full body in 206.
      if (resumeFromByte > 0) {
        responseHeaders.push({ name: 'X-RAC-Range-Honored', value: honoredRange ? 'true' : 'false' });
      }

      this.writeResponse(outMetaPtr, { status, redirectedUrl, headers: responseHeaders, elapsedMs });

      return cancelled ? RAC_ERROR_CANCELLED : RAC_SUCCESS;
    } catch (err) {
      logger.warning(`runStream failed: ${err instanceof Error ? err.message : String(err)}`);
      try {
        this.writeResponse(outMetaPtr, { status: 0, redirectedUrl: '', headers: [], elapsedMs: 0 });
      } catch {
        /* noop */
      }
      return RAC_ERROR_NETWORK_ERROR;
    }
  }

  // WASM heap marshaling

  private now(): number {
    return typeof performance !== 'undefined' && typeof performance.now === 'function'
      ? performance.now()
      : Date.now();
  }

  private toSendBody(body: Uint8Array | null): XMLHttpRequestBodyInit | null {
    if (!body || body.length === 0) return null;
    return body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength) as ArrayBuffer;
  }

  private offset(fn: (() => number) | undefined, name: string): number {
    if (!fn) throw new Error(`FetchHttpTransport: WASM module missing offset helper '${name}'`);
    return fn();
  }

  private readRequest(reqPtr: number): {
    method: string;
    url: string;
    headers: HTTPHeader[];
    body: Uint8Array | null;
    timeoutMs: number;
    followRedirects: boolean;
  } {
    const m = this.m;

    const methodPtr = m.getValue(reqPtr + this.offset(m._rac_wasm_offsetof_http_request_method, 'http_request_method'), '*');
    const urlPtr = m.getValue(reqPtr + this.offset(m._rac_wasm_offsetof_http_request_url, 'http_request_url'), '*');
    const headersPtr = m.getValue(reqPtr + this.offset(m._rac_wasm_offsetof_http_request_headers, 'http_request_headers'), '*');
    const headerCount = m.getValue(reqPtr + this.offset(m._rac_wasm_offsetof_http_request_header_count, 'http_request_header_count'), 'i32');
    const bodyBytesPtr = m.getValue(reqPtr + this.offset(m._rac_wasm_offsetof_http_request_body_bytes, 'http_request_body_bytes'), '*');
    const bodyLen = m.getValue(reqPtr + this.offset(m._rac_wasm_offsetof_http_request_body_len, 'http_request_body_len'), 'i32');
    const timeoutMs = m.getValue(reqPtr + this.offset(m._rac_wasm_offsetof_http_request_timeout_ms, 'http_request_timeout_ms'), 'i32');
    const followRedirects = m.getValue(reqPtr + this.offset(m._rac_wasm_offsetof_http_request_follow_redirects, 'http_request_follow_redirects'), 'i32');

    const method = methodPtr !== 0 ? m.UTF8ToString(methodPtr) : 'GET';
    const url = urlPtr !== 0 ? m.UTF8ToString(urlPtr) : '';

    const kvSize = m._rac_wasm_sizeof_http_header_kv ? m._rac_wasm_sizeof_http_header_kv() : 0;
    const offKvName = m._rac_wasm_offsetof_http_header_kv_name ? m._rac_wasm_offsetof_http_header_kv_name() : 0;
    const offKvValue = m._rac_wasm_offsetof_http_header_kv_value ? m._rac_wasm_offsetof_http_header_kv_value() : 0;

    const headers: HTTPHeader[] = [];
    if (headersPtr !== 0 && headerCount > 0 && kvSize > 0) {
      for (let i = 0; i < headerCount; i++) {
        const itemPtr = headersPtr + i * kvSize;
        const namePtr = m.getValue(itemPtr + offKvName, '*');
        const valuePtr = m.getValue(itemPtr + offKvValue, '*');
        if (namePtr !== 0 && valuePtr !== 0) {
          headers.push({ name: m.UTF8ToString(namePtr), value: m.UTF8ToString(valuePtr) });
        }
      }
    }

    let body: Uint8Array | null = null;
    if (bodyBytesPtr !== 0 && bodyLen > 0 && m.HEAPU8) {
      body = m.HEAPU8.slice(bodyBytesPtr, bodyBytesPtr + bodyLen);
    }

    return { method, url, headers, body, timeoutMs: timeoutMs | 0, followRedirects: followRedirects !== 0 };
  }

  private binaryTextToBytes(text: string): Uint8Array {
    const out = new Uint8Array(text.length);
    for (let i = 0; i < text.length; i++) out[i] = text.charCodeAt(i) & 0xff;
    return out;
  }

  /**
   * Write a populated `rac_http_response_t` into WASM memory. Allocates
   * string / header / body buffers with `_malloc` so the caller's
   * `rac_http_response_free` can release them (matching the emscripten adapter).
   */
  private writeResponse(
    outMetaPtr: number,
    resp: { status: number; redirectedUrl: string; headers: HTTPHeader[]; elapsedMs: number; bodyBytes?: Uint8Array },
  ): void {
    const m = this.m;

    m.setValue(outMetaPtr + this.offset(m._rac_wasm_offsetof_http_response_status, 'http_response_status'), resp.status | 0, 'i32');

    const offRedirected = this.offset(m._rac_wasm_offsetof_http_response_redirected_url, 'http_response_redirected_url');
    m.setValue(outMetaPtr + offRedirected, resp.redirectedUrl ? this.allocCString(resp.redirectedUrl) : 0, '*');

    const offHeaders = this.offset(m._rac_wasm_offsetof_http_response_headers, 'http_response_headers');
    const offHeaderCount = this.offset(m._rac_wasm_offsetof_http_response_header_count, 'http_response_header_count');
    const kvSize = m._rac_wasm_sizeof_http_header_kv ? m._rac_wasm_sizeof_http_header_kv() : 0;
    if (resp.headers.length > 0 && kvSize > 0) {
      const offKvName = m._rac_wasm_offsetof_http_header_kv_name ? m._rac_wasm_offsetof_http_header_kv_name() : 0;
      const offKvValue = m._rac_wasm_offsetof_http_header_kv_value ? m._rac_wasm_offsetof_http_header_kv_value() : 0;
      const arrayPtr = m._malloc(kvSize * resp.headers.length);
      if (m.HEAPU8) m.HEAPU8.fill(0, arrayPtr, arrayPtr + kvSize * resp.headers.length);
      for (let i = 0; i < resp.headers.length; i++) {
        const itemPtr = arrayPtr + i * kvSize;
        m.setValue(itemPtr + offKvName, this.allocCString(resp.headers[i].name), '*');
        m.setValue(itemPtr + offKvValue, this.allocCString(resp.headers[i].value), '*');
      }
      m.setValue(outMetaPtr + offHeaders, arrayPtr, '*');
      m.setValue(outMetaPtr + offHeaderCount, resp.headers.length, 'i32');
    } else {
      m.setValue(outMetaPtr + offHeaders, 0, '*');
      m.setValue(outMetaPtr + offHeaderCount, 0, 'i32');
    }

    const offBody = this.offset(m._rac_wasm_offsetof_http_response_body_bytes, 'http_response_body_bytes');
    const offBodyLen = this.offset(m._rac_wasm_offsetof_http_response_body_len, 'http_response_body_len');
    if (resp.bodyBytes && resp.bodyBytes.length > 0) {
      const bodyPtr = m._malloc(resp.bodyBytes.length);
      if (m.HEAPU8) m.HEAPU8.set(resp.bodyBytes, bodyPtr);
      else for (let i = 0; i < resp.bodyBytes.length; i++) m.setValue(bodyPtr + i, resp.bodyBytes[i], 'i8');
      m.setValue(outMetaPtr + offBody, bodyPtr, '*');
      m.setValue(outMetaPtr + offBodyLen, resp.bodyBytes.length, 'i32');
    } else {
      m.setValue(outMetaPtr + offBody, 0, '*');
      m.setValue(outMetaPtr + offBodyLen, 0, 'i32');
    }
  }

  private allocCString(str: string): number {
    const len = this.m.lengthBytesUTF8(str) + 1;
    const ptr = this.m._malloc(len);
    this.m.stringToUTF8(str, ptr, len);
    return ptr;
  }

  /**
   * Invoke the C-side chunk callback (`rac_http_body_chunk_fn`,
   * sig `rac_bool_t (const uint8_t*, size_t, uint64_t, uint64_t, void*)`) with a
   * chunk of response bytes copied into a WASM heap scratch buffer.
   */
  private invokeChunkCallback(cbPtr: number, chunk: Uint8Array, totalWritten: number, contentLength: number, cbUd: number): number {
    if (cbPtr === 0 || chunk.length === 0) return RAC_TRUE;
    const scratchPtr = this.m._malloc(chunk.length);
    try {
      if (this.m.HEAPU8) this.m.HEAPU8.set(chunk, scratchPtr);
      else for (let i = 0; i < chunk.length; i++) this.m.setValue(scratchPtr + i, chunk[i], 'i8');

      const getEntry = this.m.getWasmTableEntry;
      if (typeof getEntry !== 'function') {
        logger.warning('no getWasmTableEntry to dispatch chunk callback; failing stream');
        return RAC_FALSE;
      }
      const callable = getEntry(cbPtr);
      const rv = callable(scratchPtr, chunk.length, BigInt(totalWritten), BigInt(contentLength), cbUd);
      return (rv | 0) === RAC_FALSE ? RAC_FALSE : RAC_TRUE;
    } finally {
      try {
        this.m._free(scratchPtr);
      } catch {
        /* noop */
      }
    }
  }

  /**
   * Parse the raw blob from `XMLHttpRequest.getAllResponseHeaders()` into
   * individual kv pairs (matches the C++ `parse_response_headers()` helper).
   */
  private parseResponseHeaders(raw: string | null): HTTPHeader[] {
    if (!raw) return [];
    const out: HTTPHeader[] = [];
    for (const line of raw.split(/\r?\n/)) {
      if (!line) continue;
      const colon = line.indexOf(':');
      if (colon < 0) continue;
      const name = line.slice(0, colon).trim();
      const value = line.slice(colon + 1).trim();
      if (!name) continue;
      out.push({ name, value });
    }
    return out;
  }
}
