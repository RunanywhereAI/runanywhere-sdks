/**
 * FetchHttpTransport.ts (Stage 3d — real trampolines).
 *
 * JS-side implementation of the commons HTTP transport vtable
 * (`rac_http_transport_ops_t` declared in
 * `sdk/runanywhere-commons/include/rac/infrastructure/http/rac_http_transport.h`).
 *
 * Why this exists:
 *   The C++ `emscripten_fetch` shim in `rac_http_client_emscripten.cpp`
 *   implements the transport vtable and works end-to-end, but every
 *   request pays an extra C++ ↔ JS hop: C++ calls `emscripten_fetch`,
 *   which calls JS `fetch()`, which calls into the browser network
 *   stack. Going straight from JS (via the transport vtable) lets us
 *   plug in retries / caching / service-worker interception without a
 *   round trip through the C++ layer.
 *
 *   This module implements all three ops (`request_send`, `request_stream`,
 *   `request_resume`) directly in TypeScript using synchronous
 *   XMLHttpRequest — the only browser API that can satisfy the synchronous
 *   C ABI without JSPI / ASYNCIFY (sync `fetch()` is not available from JS).
 *   `request_send` buffers the full response body into `body_bytes`/`body_len`;
 *   `request_stream` and `request_resume` deliver the body through the
 *   C-side chunk callback and leave `body_bytes`/`body_len` at zero, per
 *   the `rac_http_request_stream` contract.
 *
 * Synchrony note:
 *   Sync XHR is deprecated on the main thread (browsers emit a console
 *   warning) but is the canonical way to block a WASM call until the
 *   browser returns a response when JSPI / ASYNCIFY are not available.
 *   Browsers forbid `responseType = 'arraybuffer'` for sync XHR issued
 *   from a document, so the main-thread path falls back to the older
 *   `x-user-defined` binary-text mode. In a worker context sync XHR can
 *   still use the arraybuffer path without warnings.
 */

import { SDKLogger } from '../Foundation/SDKLogger';
import type { HTTPModule, HTTPHeader } from './HTTPAdapter';

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
 * stream (the browser holds the response until completion), but splitting
 * the in-memory buffer into bounded chunks keeps the WASM heap-scratch
 * footprint small and gives the C-side progress callback meaningful
 * granularity. Mirrors the commons-side `RAC_HTTP_DEFAULT_CHUNK_SIZE_BYTES`
 * default in `rac_http_transport.h`. 1 MiB matches the commons producer.
 */
const STREAM_CHUNK_SIZE = 1 * 1024 * 1024;

function i64ToNumber(value: number | bigint): number {
  return typeof value === 'bigint' ? Number(value) : value;
}

/**
 * Extension of HTTPModule with the Stage 3d registration export. Stays
 * optional at type level so missing builds fall back to the emscripten
 * transport rather than hard-erroring at import time.
 */
export interface FetchHttpTransportModule extends HTTPModule {
  /**
   * `rac_result_t rac_http_transport_register_from_js(
   *    rac_result_t (*request_send)(void*, const rac_http_request_t*, rac_http_response_t*),
   *    rac_result_t (*request_stream)(void*, const rac_http_request_t*,
   *                                   rac_http_body_chunk_fn, void*, rac_http_response_t*),
   *    rac_result_t (*request_resume)(void*, const rac_http_request_t*, uint64_t,
   *                                   rac_http_body_chunk_fn, void*, rac_http_response_t*));`
   *
   * Pass function-table indices obtained from `Module.addFunction(fn, sig)`
   * for each op you want to route through JS, or 0 to fall back to
   * emscripten_fetch for that op. Passing 0 for all three unregisters
   * the JS adapter.
   */
  _rac_http_transport_register_from_js?(
    requestSendPtr: number,
    requestStreamPtr: number,
    requestResumePtr: number,
  ): number;
}

/**
 * JS-side HTTP transport installed via the commons transport vtable.
 *
 * Created by `FetchHttpTransport.install(module)`. Keeps a handle to the
 * underlying `addFunction` trampolines so `uninstall()` can remove them
 * and return memory to the WASM function table.
 */
export class FetchHttpTransport {
  private requestSendPtr = 0;
  private requestStreamPtr = 0;
  private requestResumePtr = 0;

  private constructor(private readonly m: FetchHttpTransportModule) {}

  /**
   * Install the JS-side HTTP transport into the given Emscripten module.
   *
   * Returns the transport instance (so the caller can `uninstall()` it
   * during teardown) or `null` if the module was built without the
   * Stage 3d export (`_rac_http_transport_register_from_js`).
   */
  static install(m: FetchHttpTransportModule): FetchHttpTransport | null {
    if (typeof m._rac_http_transport_register_from_js !== 'function') {
      logger.debug(
        'FetchHttpTransport.install: module missing _rac_http_transport_register_from_js; ' +
          'skipping JS-side HTTP transport (emscripten_fetch fallback remains active)',
      );
      return null;
    }

    const transport = new FetchHttpTransport(m);
    transport.doInstall();
    return transport;
  }

  /**
   * Remove the JS-side adapter from the transport registry and free
   * the `addFunction` table slots. Idempotent.
   */
  uninstall(): void {
    if (typeof this.m._rac_http_transport_register_from_js === 'function') {
      try {
        this.m._rac_http_transport_register_from_js(0, 0, 0);
      } catch (err) {
        logger.warning(
          `FetchHttpTransport.uninstall: register(0,0,0) threw: ${err instanceof Error ? err.message : String(err)}`,
        );
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

  // -------------------------------------------------------------------------
  // Implementation
  // -------------------------------------------------------------------------

  private doInstall(): void {
    // Signatures (i=i32 pointer, j=i64, v=void):
    //   request_send:   (user_data*, req*, out_resp*) -> i32          sig 'iiii'
    //   request_stream: (user_data*, req*, cb*, cb_ud*, out_meta*) -> i32
    //                                                                 sig 'iiiiii'
    //   request_resume: (user_data*, req*, resume_byte_j, cb*, cb_ud*, out_meta*) -> i32
    //                                                                 sig 'iiijiii'

    this.requestSendPtr = this.m.addFunction(
      (
        userData: number | bigint,
        reqPtr: number | bigint,
        outRespPtr: number | bigint,
      ) => {
        return this.runSend(Number(userData), Number(reqPtr), Number(outRespPtr));
      },
      'iiii',
    );

    this.requestStreamPtr = this.m.addFunction(
      (
        userData: number | bigint,
        reqPtr: number | bigint,
        cbPtr: number | bigint,
        cbUd: number | bigint,
        outMetaPtr: number | bigint,
      ) => {
        return this.runStream(
          Number(userData),
          Number(reqPtr),
          Number(cbPtr),
          Number(cbUd),
          Number(outMetaPtr),
          /*resumeFromByte=*/ 0,
        );
      },
      'iiiiii',
    );

    // Emscripten sig 'iiijiii': return i32; args = i32, i32, i64, i32, i32, i32.
    // Current Emscripten builds pass the i64 resume offset to JS as BigInt.
    this.requestResumePtr = this.m.addFunction(
      (
        userData: number | bigint,
        reqPtr: number | bigint,
        resumeRaw: number | bigint,
        cbPtr: number | bigint,
        cbUd: number | bigint,
        outMetaPtr: number | bigint,
      ) => {
        const resumeFromByte = i64ToNumber(resumeRaw);
        return this.runStream(
          Number(userData),
          Number(reqPtr),
          Number(cbPtr),
          Number(cbUd),
          Number(outMetaPtr),
          resumeFromByte,
        );
      },
      'iiijiii',
    );

    const registerFn = this.m._rac_http_transport_register_from_js;
    if (!registerFn) {
      // Defensive; install() already checks, but the lint pass wants a
      // guard before the non-null assertion below.
      return;
    }

    const rc = registerFn(this.requestSendPtr, this.requestStreamPtr, this.requestResumePtr);
    if (rc !== RAC_SUCCESS) {
      logger.warning(
        `FetchHttpTransport: register_from_js returned rc=${rc}; uninstalling`,
      );
      this.uninstall();
      return;
    }
    logger.debug('FetchHttpTransport: JS HTTP transport activated (send=XHR, stream=XHR, resume=XHR)');
  }

  /**
   * Implementation for `request_send` — single-shot blocking request that
   * buffers the full response body into `body_bytes`/`body_len`.
   *
   * Mirrors the `request_stream` XHR path but populates the response body
   * in the C struct instead of delivering it through a chunk callback,
   * matching the `rac_http_request_send` contract and Swift's
   * `URLSessionHttpTransport.RequestExecutor.send`.
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
          /* browsers forbid setting a few reserved headers; ignore. */
        }
      }
      if (req.timeoutMs > 0) {
        // A synchronous XHR in a document forbids setting `timeout`
        // (InvalidAccessError) — the same class of restriction already handled
        // for `responseType` above. The browser applies its own network
        // timeout, so swallow the throw instead of failing the whole request.
        try {
          xhr.timeout = req.timeoutMs;
        } catch {
          /* sync XHR from a document: timeout not settable; ignored. */
        }
      }

      const t0 =
        typeof performance !== 'undefined' && typeof performance.now === 'function'
          ? performance.now()
          : Date.now();
      const sendBody: BodyInit | null =
        req.body && req.body.length > 0
          ? (req.body.buffer.slice(
              req.body.byteOffset,
              req.body.byteOffset + req.body.byteLength,
            ) as ArrayBuffer)
          : null;
      xhr.send(sendBody as XMLHttpRequestBodyInit | null);
      const elapsedMs = Math.max(
        0,
        Math.round(
          (typeof performance !== 'undefined' && typeof performance.now === 'function'
            ? performance.now()
            : Date.now()) - t0,
        ),
      );

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
      logger.warning(
        `FetchHttpTransport.runSend failed: ${err instanceof Error ? err.message : String(err)}`,
      );
      try {
        this.writeResponse(outRespPtr, { status: 0, redirectedUrl: '', headers: [], elapsedMs: 0 });
      } catch {
        /* noop */
      }
      return RAC_ERROR_NETWORK_ERROR;
    }
  }

  /**
   * Shared implementation for both `request_stream` and `request_resume`.
   *
   * Reads the C-side `rac_http_request_t`, issues a synchronous XHR, and
   * streams the response back through the C-side chunk callback. Writes
   * the status/headers/redirected_url into `outMetaPtr`; leaves
   * `body_bytes`/`body_len` at zero per the streaming contract.
   *
   * Returns a `rac_result_t` (0 on success, negative on error).
   */
  private runStream(
    userData: number,
    reqPtr: number,
    cbPtr: number,
    cbUd: number,
    outMetaPtr: number,
    resumeFromByte: number,
  ): number {
    void userData; // Unused; adapter has no per-instance context.
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
          /* browsers forbid setting a few reserved headers; ignore. */
        }
      }
      if (resumeFromByte > 0) {
        try {
          xhr.setRequestHeader('Range', `bytes=${resumeFromByte}-`);
        } catch {
          /* noop */
        }
      }
      if (req.timeoutMs > 0) {
        // XHR timeout is only honoured for async requests per spec; setting it
        // on a synchronous XHR in a document throws InvalidAccessError, so guard
        // it the same way `responseType` is guarded above.
        try {
          xhr.timeout = req.timeoutMs;
        } catch {
          /* sync XHR from a document: timeout not settable; ignored. */
        }
      }

      const t0 =
        typeof performance !== 'undefined' && typeof performance.now === 'function'
          ? performance.now()
          : Date.now();
      const sendBody: BodyInit | null =
        req.body && req.body.length > 0
          ? (req.body.buffer.slice(
              req.body.byteOffset,
              req.body.byteOffset + req.body.byteLength,
            ) as ArrayBuffer)
          : null;
      xhr.send(sendBody as XMLHttpRequestBodyInit | null);
      const elapsedMs = Math.max(
        0,
        Math.round(
          (typeof performance !== 'undefined' && typeof performance.now === 'function'
            ? performance.now()
            : Date.now()) - t0,
        ),
      );

      const status = xhr.status | 0;
      if (status === 0) {
        this.writeResponse(outMetaPtr, {
          status: 0,
          redirectedUrl: req.url,
          headers: [],
          elapsedMs,
        });
        return RAC_ERROR_NETWORK_ERROR;
      }

      const body =
        xhr.response instanceof ArrayBuffer
          ? new Uint8Array(xhr.response)
          : useBinaryTextFallback
            ? this.binaryTextToBytes(xhr.responseText)
          : new Uint8Array(0);
      const bodyLength = body.length;

      // When the server honored the Range request (206) the body contains
      // only the remaining bytes; fold resumeFromByte into the counters so
      // the C-side chunk callback sees a monotonic absolute file position
      // for `total_written` and a correct `content_length`. Mirrors
      // URLSessionHttpTransport.swift:627-632 and OkHttpHttpTransport.kt:505-513.
      const honoredRange = status === 206 && resumeFromByte > 0;
      const baseOffset = honoredRange ? resumeFromByte : 0;
      const total = honoredRange ? bodyLength + resumeFromByte : bodyLength;

      // Deliver the body through `STREAM_CHUNK_SIZE`-sized callbacks so the
      // C-side `rac_http_body_chunk_fn` sees meaningful progress and the
      // WASM heap-scratch buffer (allocated inside `invokeChunkCallback`)
      // stays bounded — without this, a multi-GB GGUF download would
      // malloc the entire body twice (once in `xhr.response`, once in the
      // heap scratch) and trip the engine's quota.
      //
      // Note: sync XHR cannot expose a true network stream; the browser
      // already holds the full body in memory by this point. The chunk
      // fan-out below recovers progress granularity and bounds the
      // scratch allocation, which is the part of the OOM risk the SDK
      // can address from JS land. Truly streaming network reads require
      // an async transport (fetch + ReadableStream) and JSPI/ASYNCIFY in
      // the WASM build — tracked separately.
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

      // Emit X-RAC-Range-Honored so the commons download orchestrator can
      // distinguish a genuine 206 partial-content reply from a CDN that
      // wraps a full body in 206. Mirrors URLSessionHttpTransport.swift:503-506
      // and OkHttpHttpTransport.kt:687-703.
      if (resumeFromByte > 0) {
        responseHeaders.push({ name: 'X-RAC-Range-Honored', value: honoredRange ? 'true' : 'false' });
      }

      this.writeResponse(outMetaPtr, {
        status,
        redirectedUrl,
        headers: responseHeaders,
        elapsedMs,
      });

      if (cancelled) {
        return RAC_ERROR_CANCELLED;
      }
      return RAC_SUCCESS;
    } catch (err) {
      logger.warning(
        `FetchHttpTransport.runStream failed: ${err instanceof Error ? err.message : String(err)}`,
      );
      // Best-effort zero out the outMeta so downstream readers see a
      // well-defined struct.
      try {
        this.writeResponse(outMetaPtr, {
          status: 0,
          redirectedUrl: '',
          headers: [],
          elapsedMs: 0,
        });
      } catch {
        /* noop */
      }
      return RAC_ERROR_NETWORK_ERROR;
    }
  }

  // -------------------------------------------------------------------------
  // WASM heap marshaling
  // -------------------------------------------------------------------------

  /**
   * Read a `rac_http_request_t` out of WASM memory. Uses the
   * `_rac_wasm_offsetof_*` helpers so field layout changes don't break
   * the adapter silently.
   */
  private readRequest(reqPtr: number): {
    method: string;
    url: string;
    headers: HTTPHeader[];
    body: Uint8Array | null;
    timeoutMs: number;
    followRedirects: boolean;
  } {
    const m = this.m;
    const getOffset = (
      fn: (() => number) | undefined,
      name: string,
    ): number => {
      if (!fn) {
        throw new Error(`FetchHttpTransport: WASM module missing offset helper '${name}'`);
      }
      return fn();
    };

    const methodPtr = m.getValue(
      reqPtr + getOffset(m._rac_wasm_offsetof_http_request_method, 'http_request_method'),
      '*',
    );
    const urlPtr = m.getValue(
      reqPtr + getOffset(m._rac_wasm_offsetof_http_request_url, 'http_request_url'),
      '*',
    );
    const headersPtr = m.getValue(
      reqPtr + getOffset(m._rac_wasm_offsetof_http_request_headers, 'http_request_headers'),
      '*',
    );
    const headerCount = m.getValue(
      reqPtr +
        getOffset(m._rac_wasm_offsetof_http_request_header_count, 'http_request_header_count'),
      'i32',
    );
    const bodyBytesPtr = m.getValue(
      reqPtr + getOffset(m._rac_wasm_offsetof_http_request_body_bytes, 'http_request_body_bytes'),
      '*',
    );
    const bodyLen = m.getValue(
      reqPtr + getOffset(m._rac_wasm_offsetof_http_request_body_len, 'http_request_body_len'),
      'i32',
    );
    const timeoutMs = m.getValue(
      reqPtr + getOffset(m._rac_wasm_offsetof_http_request_timeout_ms, 'http_request_timeout_ms'),
      'i32',
    );
    const followRedirects = m.getValue(
      reqPtr +
        getOffset(
          m._rac_wasm_offsetof_http_request_follow_redirects,
          'http_request_follow_redirects',
        ),
      'i32',
    );

    const method = methodPtr !== 0 ? m.UTF8ToString(methodPtr) : 'GET';
    const url = urlPtr !== 0 ? m.UTF8ToString(urlPtr) : '';

    const kvSize = m._rac_wasm_sizeof_http_header_kv ? m._rac_wasm_sizeof_http_header_kv() : 0;
    const offKvName = m._rac_wasm_offsetof_http_header_kv_name
      ? m._rac_wasm_offsetof_http_header_kv_name()
      : 0;
    const offKvValue = m._rac_wasm_offsetof_http_header_kv_value
      ? m._rac_wasm_offsetof_http_header_kv_value()
      : 0;

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

    return {
      method,
      url,
      headers,
      body,
      timeoutMs: timeoutMs | 0,
      followRedirects: followRedirects !== 0,
    };
  }

  private binaryTextToBytes(text: string): Uint8Array {
    const out = new Uint8Array(text.length);
    for (let i = 0; i < text.length; i++) {
      out[i] = text.charCodeAt(i) & 0xff;
    }
    return out;
  }

  /**
   * Write a populated `rac_http_response_t` into WASM memory at
   * `outMetaPtr`. Mirrors `emscripten_to_response()` in
   * `rac_http_client_emscripten.cpp` — allocates string / header / body
   * buffers inside the WASM heap using `_malloc`/`strdup`-compatible
   * routines so the caller's `rac_http_response_free` can release them.
   *
   * Pass `bodyBytes` for `request_send` calls that buffer the full response.
   * Streaming calls omit it; `body_bytes`/`body_len` are left at zero per
   * the `rac_http_request_stream` contract.
   */
  private writeResponse(
    outMetaPtr: number,
    resp: {
      status: number;
      redirectedUrl: string;
      headers: HTTPHeader[];
      elapsedMs: number;
      bodyBytes?: Uint8Array;
    },
  ): void {
    const m = this.m;
    const getOffset = (fn: (() => number) | undefined, name: string): number => {
      if (!fn) {
        throw new Error(`FetchHttpTransport: WASM module missing offset helper '${name}'`);
      }
      return fn();
    };

    // status
    m.setValue(
      outMetaPtr + getOffset(m._rac_wasm_offsetof_http_response_status, 'http_response_status'),
      resp.status | 0,
      'i32',
    );

    // redirected_url — strdup-style: malloc + stringToUTF8.
    const offRedirected = getOffset(
      m._rac_wasm_offsetof_http_response_redirected_url,
      'http_response_redirected_url',
    );
    if (resp.redirectedUrl) {
      const urlPtr = this.allocCString(resp.redirectedUrl);
      m.setValue(outMetaPtr + offRedirected, urlPtr, '*');
    } else {
      m.setValue(outMetaPtr + offRedirected, 0, '*');
    }

    // headers array
    const offHeaders = getOffset(
      m._rac_wasm_offsetof_http_response_headers,
      'http_response_headers',
    );
    const offHeaderCount = getOffset(
      m._rac_wasm_offsetof_http_response_header_count,
      'http_response_header_count',
    );
    if (resp.headers.length > 0) {
      const kvSize = m._rac_wasm_sizeof_http_header_kv ? m._rac_wasm_sizeof_http_header_kv() : 0;
      const offKvName = m._rac_wasm_offsetof_http_header_kv_name
        ? m._rac_wasm_offsetof_http_header_kv_name()
        : 0;
      const offKvValue = m._rac_wasm_offsetof_http_header_kv_value
        ? m._rac_wasm_offsetof_http_header_kv_value()
        : 0;
      if (kvSize > 0) {
        const arrayPtr = m._malloc(kvSize * resp.headers.length);
        // Zero the block so partial failures leave a well-formed struct.
        if (m.HEAPU8) {
          m.HEAPU8.fill(0, arrayPtr, arrayPtr + kvSize * resp.headers.length);
        }
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
    } else {
      m.setValue(outMetaPtr + offHeaders, 0, '*');
      m.setValue(outMetaPtr + offHeaderCount, 0, 'i32');
    }

    const offBody = getOffset(
      m._rac_wasm_offsetof_http_response_body_bytes,
      'http_response_body_bytes',
    );
    const offBodyLen = getOffset(
      m._rac_wasm_offsetof_http_response_body_len,
      'http_response_body_len',
    );
    if (resp.bodyBytes && resp.bodyBytes.length > 0) {
      const bodyPtr = m._malloc(resp.bodyBytes.length);
      if (m.HEAPU8) {
        m.HEAPU8.set(resp.bodyBytes, bodyPtr);
      } else {
        for (let i = 0; i < resp.bodyBytes.length; i++) {
          m.setValue(bodyPtr + i, resp.bodyBytes[i], 'i8');
        }
      }
      m.setValue(outMetaPtr + offBody, bodyPtr, '*');
      m.setValue(outMetaPtr + offBodyLen, resp.bodyBytes.length, 'i32');
    } else {
      m.setValue(outMetaPtr + offBody, 0, '*');
      m.setValue(outMetaPtr + offBodyLen, 0, 'i32');
    }
  }

  /**
   * Allocate a C string inside the WASM heap. Caller (the C-side
   * `rac_http_response_free`) is responsible for releasing the memory
   * via `free`, matching the `strdup` contract the emscripten_fetch
   * adapter uses for these fields.
   */
  private allocCString(str: string): number {
    const len = this.m.lengthBytesUTF8(str) + 1;
    const ptr = this.m._malloc(len);
    this.m.stringToUTF8(str, ptr, len);
    return ptr;
  }

  /**
   * Invoke the C-side chunk callback (`rac_http_body_chunk_fn`) with a
   * chunk of response bytes. The callback pointer is the raw C function
   * pointer passed by the C layer into the JS trampoline — we route it
   * back through `Module`'s function table using `getWasmTableEntry` via
   * the well-known Emscripten `ccall` doesn't help here because the C
   * ABI is synchronous. We allocate a scratch buffer inside the WASM
   * heap, copy the chunk into it, then call the function pointer
   * through `Module.dynCall_*` or (on newer Emscripten) via
   * `Module.getWasmTableEntry(ptr)`.
   */
  private invokeChunkCallback(
    cbPtr: number,
    chunk: Uint8Array,
    totalWritten: number,
    contentLength: number,
    cbUd: number,
  ): number {
    if (cbPtr === 0 || chunk.length === 0) {
      return RAC_TRUE;
    }
    // Copy chunk into WASM heap so the C callback can read it.
    const scratchPtr = this.m._malloc(chunk.length);
    try {
      if (this.m.HEAPU8) {
        this.m.HEAPU8.set(chunk, scratchPtr);
      } else {
        for (let i = 0; i < chunk.length; i++) {
          this.m.setValue(scratchPtr + i, chunk[i], 'i8');
        }
      }

      // rac_http_body_chunk_fn signature:
      //   rac_bool_t (*)(const uint8_t* chunk, size_t chunk_len,
      //                  uint64_t total_written, uint64_t content_length,
      //                  void* user_data);
      // sig 'iiijji'. Current Emscripten builds pass i64 args as BigInt
      // when calling the table entry from JS.
      const m = this.m as unknown as {
        getWasmTableEntry?: (ptr: number) => (...args: Array<number | bigint>) => number;
        wasmTable?: { get(ptr: number): (...args: Array<number | bigint>) => number };
        dynCall_iiijji?: (
          cbPtr: number,
          chunkPtr: number,
          chunkLen: number,
          totalLo: number,
          totalHi: number,
          contentLo: number,
          contentHi: number,
          ud: number,
        ) => number;
      };

      const totalLo = totalWritten >>> 0;
      const totalHi = Math.floor(totalWritten / 0x100000000) >>> 0;
      const contentLo = contentLength >>> 0;
      const contentHi = Math.floor(contentLength / 0x100000000) >>> 0;

      let callable: ((...args: Array<number | bigint>) => number) | null = null;
      if (typeof m.getWasmTableEntry === 'function') {
        callable = m.getWasmTableEntry(cbPtr);
      } else if (m.wasmTable && typeof m.wasmTable.get === 'function') {
        callable = m.wasmTable.get(cbPtr);
      }

      if (callable) {
        const rv = callable(
          scratchPtr,
          chunk.length,
          BigInt(totalWritten),
          BigInt(contentLength),
          cbUd,
        );
        return (rv | 0) === RAC_FALSE ? RAC_FALSE : RAC_TRUE;
      }
      if (typeof m.dynCall_iiijji === 'function') {
        const rv = m.dynCall_iiijji(
          cbPtr,
          scratchPtr,
          chunk.length,
          totalLo,
          totalHi,
          contentLo,
          contentHi,
          cbUd,
        );
        return (rv | 0) === RAC_FALSE ? RAC_FALSE : RAC_TRUE;
      }
      logger.warning(
        'FetchHttpTransport: no way to dispatch chunk callback (neither ' +
          'getWasmTableEntry nor dynCall_iiijji present); failing stream',
      );
      return RAC_FALSE;
    } finally {
      try {
        this.m._free(scratchPtr);
      } catch {
        /* noop */
      }
    }
  }

  /**
   * Parse the raw header blob returned by `XMLHttpRequest.getAllResponseHeaders()`
   * into individual kv pairs. Matches the format of the C++
   * `parse_response_headers()` helper in `rac_http_client_emscripten.cpp`.
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
