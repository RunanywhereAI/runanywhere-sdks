/**
 * FetchHttpTransport.test.ts
 *
 * Covers the chunked body-delivery behavior and
 * the install/uninstall lifecycle that the JS-side trampolines depend on.
 *
 * The transport's `request_stream` op buffers the response in `xhr.response`
 * (sync XHR has no streaming choice on the main thread) and then fans the
 * buffer out through the C-side `rac_http_body_chunk_fn` callback in
 * `STREAM_CHUNK_SIZE`-bounded slices. These tests stub `XMLHttpRequest`
 * and a minimal Emscripten module so we can assert:
 *
 *   1. install() returns null when the module lacks the JS-side transport export
 *      (so the emscripten_fetch fallback stays active).
 *   2. install() registers the request_send + request_stream + request_resume
 *      trampolines and returns a transport handle when the export is present.
 *      (All three ops route through XHR for parity with the Swift
 *      URLSessionHttpTransport, which registers request_send/_stream/_resume.)
 *   3. uninstall() unregisters and removes the trampolines (idempotent).
 *   4. A small body fits in a single chunk callback.
 *   5. A multi-MiB body fans out across >1 chunk callback at the
 *      `STREAM_CHUNK_SIZE` boundary.
 *   6. A callback returning RAC_FALSE (cancel) aborts the chunk loop.
 *
 * Runner: vitest (already used by this package).
 */

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  FetchHttpTransport,
  type FetchHttpTransportModule,
} from '../../../src/Adapters/FetchHttpTransport';

// ---------------------------------------------------------------------------
// XHR stub
// ---------------------------------------------------------------------------

interface RecordedHeader {
  name: string;
  value: string;
}

interface XHRStubConfig {
  /** Bytes returned by the fake server. */
  body: Uint8Array;
  /** Response status. */
  status: number;
  /** Response URL after redirects. */
  responseURL?: string;
  /** Raw `getAllResponseHeaders()` blob. */
  rawHeaders?: string;
  /** Whether `responseType = 'arraybuffer'` should throw (forces binary-text fallback). */
  arrayBufferUnsupported?: boolean;
  /** Mirror Window-owned synchronous XHR rejecting a non-zero timeout. */
  timeoutAssignmentUnsupported?: boolean;
}

class XHRStub {
  static lastInstance: XHRStub | null = null;
  static config: XHRStubConfig = {
    body: new Uint8Array(0),
    status: 200,
    responseURL: '',
    rawHeaders: 'Content-Type: application/octet-stream\r\n',
  };
  static recordedHeaders: RecordedHeader[] = [];
  static lastUrl = '';
  static lastMethod = '';

  status = 0;
  responseURL = '';
  responseType: '' | 'arraybuffer' | 'text' = '';
  response: ArrayBuffer | string | null = null;
  responseText = '';
  private configuredTimeout = 0;
  private headerBlob = '';

  get timeout(): number {
    return this.configuredTimeout;
  }

  set timeout(value: number) {
    if (value > 0 && XHRStub.config.timeoutAssignmentUnsupported) {
      throw new DOMException(
        'Timeouts cannot be set for synchronous requests made from a document.',
        'InvalidAccessError',
      );
    }
    this.configuredTimeout = value;
  }

  constructor() {
    XHRStub.lastInstance = this;
    XHRStub.recordedHeaders = [];
  }

  open(method: string, url: string, _async: boolean): void {
    XHRStub.lastMethod = method;
    XHRStub.lastUrl = url;
  }

  setRequestHeader(name: string, value: string): void {
    XHRStub.recordedHeaders.push({ name, value });
  }

  send(_body: unknown): void {
    if (XHRStub.config.arrayBufferUnsupported && this.responseType === 'arraybuffer') {
      // Tests can flip this branch by setting responseType first; the
      // transport falls back via a try/catch in the responseType assignment.
      return;
    }
    this.status = XHRStub.config.status;
    this.responseURL = XHRStub.config.responseURL ?? '';
    if (this.responseType === 'arraybuffer') {
      this.response = XHRStub.config.body.buffer.slice(
        XHRStub.config.body.byteOffset,
        XHRStub.config.body.byteOffset + XHRStub.config.body.byteLength,
      ) as ArrayBuffer;
    } else {
      let s = '';
      for (let i = 0; i < XHRStub.config.body.length; i += 1) {
        s += String.fromCharCode(XHRStub.config.body[i]);
      }
      this.responseText = s;
    }
    this.headerBlob = XHRStub.config.rawHeaders ?? '';
  }

  overrideMimeType(_mime: string): void {
    // The transport uses this when forced into x-user-defined mode.
  }

  getAllResponseHeaders(): string {
    return this.headerBlob;
  }
}

// ---------------------------------------------------------------------------
// Module + WASM heap stub
// ---------------------------------------------------------------------------

type Trampoline = (...args: Array<number | bigint>) => number | void;

interface ChunkCall {
  bytes: Uint8Array;
  totalWritten: number;
  contentLength: number;
}

interface FakeModuleHandle {
  module: FetchHttpTransportModule;
  registrations: Array<{ send: number; stream: number; resume: number }>;
  trampolines: Map<number, Trampoline>;
  removedTrampolines: number[];
  /** Synchronous chunk-callback recorder — populated by `installChunkCallback`. */
  chunkCalls: ChunkCall[];
  /** Chunk-callback id the transport will dispatch through `getWasmTableEntry`. */
  chunkCallbackId: number;
  /** Strategy used by the chunk callback (continue = keep going, cancelAt = abort after N). */
  chunkStrategy: 'continue' | { cancelAt: number };
}

function makeFakeModule(
  opts: { withRegister?: boolean; timeoutMs?: number } = {},
): FakeModuleHandle {
  const heap = new ArrayBuffer(1 << 24); // 16 MiB scratch heap
  const heapU8 = new Uint8Array(heap);
  const heapU32 = new Uint32Array(heap);
  let nextPtr = 256;
  const malloc = (size: number): number => {
    const aligned = Math.max(4, (size + 3) & ~3);
    const ptr = nextPtr;
    nextPtr += aligned;
    return ptr;
  };
  const trampolines = new Map<number, Trampoline>();
  let nextTrampolineId = 1;
  const removed: number[] = [];
  const registrations: Array<{ send: number; stream: number; resume: number }> = [];

  const handle: FakeModuleHandle = {
    module: null as unknown as FetchHttpTransportModule,
    registrations,
    trampolines,
    removedTrampolines: removed,
    chunkCalls: [],
    chunkCallbackId: 0,
    chunkStrategy: 'continue',
  };

  // Synchronous chunk callback that the transport will dispatch through the
  // wasmTable. We install it once and stash its id on the handle so the
  // tests can pass it through `cbPtr` to the trampoline directly.
  const chunkCallback: Trampoline = (
    chunkPtr,
    chunkLen,
    totalWritten,
    contentLength,
    _userData,
  ) => {
    const ptr = Number(chunkPtr);
    const len = Number(chunkLen);
    const bytes = heapU8.slice(ptr, ptr + len);
    handle.chunkCalls.push({
      bytes,
      totalWritten: typeof totalWritten === 'bigint' ? Number(totalWritten) : Number(totalWritten),
      contentLength:
        typeof contentLength === 'bigint' ? Number(contentLength) : Number(contentLength),
    });
    if (handle.chunkStrategy === 'continue') return 1;
    return handle.chunkCalls.length >= handle.chunkStrategy.cancelAt ? 0 : 1;
  };
  const chunkCbId = nextTrampolineId++;
  trampolines.set(chunkCbId, chunkCallback);
  handle.chunkCallbackId = chunkCbId;

  const module: Partial<FetchHttpTransportModule> & {
    getWasmTableEntry?: (ptr: number) => Trampoline;
  } = {
    HEAPU8: heapU8,
    _malloc: malloc,
    _free: () => undefined,
    addFunction(fn: Trampoline, _sig: string): number {
      const id = nextTrampolineId++;
      trampolines.set(id, fn);
      return id;
    },
    removeFunction(ptr: number): void {
      removed.push(ptr);
      trampolines.delete(ptr);
    },
    setValue(_ptr: number, _value: number, _type: string): void {
      // The transport's writeResponse uses this; we capture it loosely.
    },
    getValue(ptr: number, _type: string): number {
      return ptr === 28 ? (opts.timeoutMs ?? 0) : 0;
    },
    UTF8ToString(_ptr: number): string {
      return '';
    },
    stringToUTF8(_str: string, _ptr: number, _maxBytes: number): void { /* noop */ },
    lengthBytesUTF8(_str: string): number {
      return 0;
    },
    // Tests do not exercise readRequest — runStream's reqPtr is 0 and the
    // transport gracefully treats missing helpers as defaults.
    _rac_wasm_offsetof_http_request_method: () => 0,
    _rac_wasm_offsetof_http_request_url: () => 0,
    _rac_wasm_offsetof_http_request_headers: () => 0,
    _rac_wasm_offsetof_http_request_header_count: () => 0,
    _rac_wasm_offsetof_http_request_body_bytes: () => 0,
    _rac_wasm_offsetof_http_request_body_len: () => 0,
    _rac_wasm_offsetof_http_request_timeout_ms: () => 28,
    _rac_wasm_offsetof_http_request_follow_redirects: () => 0,
    _rac_wasm_offsetof_http_request_expected_checksum_hex: () => 0,
    _rac_wasm_offsetof_http_response_status: () => 0,
    _rac_wasm_offsetof_http_response_redirected_url: () => 4,
    _rac_wasm_offsetof_http_response_headers: () => 8,
    _rac_wasm_offsetof_http_response_header_count: () => 12,
    _rac_wasm_offsetof_http_response_body_bytes: () => 16,
    _rac_wasm_offsetof_http_response_body_len: () => 20,
    _rac_wasm_sizeof_http_header_kv: () => 8,
    _rac_wasm_offsetof_http_header_kv_name: () => 0,
    _rac_wasm_offsetof_http_header_kv_value: () => 4,
    getWasmTableEntry(ptr: number): Trampoline {
      const fn = trampolines.get(ptr);
      if (!fn) throw new Error(`getWasmTableEntry: no trampoline at ${ptr}`);
      return fn;
    },
  };

  if (opts.withRegister !== false) {
    module._rac_http_transport_register_from_js = (
      sendPtr: number,
      streamPtr: number,
      resumePtr: number,
    ): number => {
      registrations.push({ send: sendPtr, stream: streamPtr, resume: resumePtr });
      return 0;
    };
  }
  // The shadow heap we hand back so chunkCallback reads bytes from a stable
  // place.
  void heapU32;

  handle.module = module as FetchHttpTransportModule;
  return handle;
}

// ---------------------------------------------------------------------------
// Vitest suite
// ---------------------------------------------------------------------------

const originalXHR = globalThis.XMLHttpRequest;

describe('FetchHttpTransport', () => {
  beforeEach(() => {
    XHRStub.lastInstance = null;
    XHRStub.config = {
      body: new Uint8Array(0),
      status: 200,
      responseURL: '',
      rawHeaders: 'Content-Type: application/octet-stream\r\n',
    };
    (globalThis as unknown as { XMLHttpRequest: unknown }).XMLHttpRequest =
      XHRStub as unknown as typeof XMLHttpRequest;
  });

  afterEach(() => {
    (globalThis as unknown as { XMLHttpRequest: unknown }).XMLHttpRequest =
      originalXHR as unknown as typeof XMLHttpRequest;
    vi.restoreAllMocks();
  });

  it('install() returns null when the module lacks the JS-side transport export', () => {
    const handle = makeFakeModule({ withRegister: false });
    const transport = FetchHttpTransport.install(handle.module);
    expect(transport).toBeNull();
    expect(handle.registrations).toHaveLength(0);
  });

  it('install() registers send + stream + resume trampolines and uninstall() reverses it', () => {
    const handle = makeFakeModule();
    const transport = FetchHttpTransport.install(handle.module);
    expect(transport).not.toBeNull();
    expect(handle.registrations).toHaveLength(1);
    const reg = handle.registrations[0];
    // All three ops are wired through XHR for parity with the Swift
    // URLSessionHttpTransport (request_send/_stream/_resume), so each gets a
    // distinct non-zero function-table trampoline.
    expect(reg.send).not.toBe(0);
    expect(reg.stream).not.toBe(0);
    expect(reg.resume).not.toBe(0);
    expect(new Set([reg.send, reg.stream, reg.resume]).size).toBe(3);

    transport!.uninstall();
    // After uninstall: register(0,0,0) was called and the function-table
    // entries were removed.
    expect(handle.registrations).toHaveLength(2);
    expect(handle.registrations[1]).toEqual({ send: 0, stream: 0, resume: 0 });
    expect(handle.removedTrampolines).toContain(reg.send);
    expect(handle.removedTrampolines).toContain(reg.stream);
    expect(handle.removedTrampolines).toContain(reg.resume);

    // Idempotent.
    transport!.uninstall();
  });

  it('delivers a small body in a single chunk callback', () => {
    const handle = makeFakeModule();
    XHRStub.config.body = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]);
    XHRStub.config.status = 200;

    const transport = FetchHttpTransport.install(handle.module);
    expect(transport).not.toBeNull();
    const streamPtr = handle.registrations[0].stream;
    const stream = handle.trampolines.get(streamPtr);
    expect(stream).toBeDefined();

    const rc = stream!(/*user*/0, /*req*/0, handle.chunkCallbackId, /*cbUd*/0, /*outMeta*/0);
    expect(rc).toBe(0); // RAC_SUCCESS
    expect(handle.chunkCalls).toHaveLength(1);
    expect(handle.chunkCalls[0].bytes).toEqual(XHRStub.config.body);
    expect(handle.chunkCalls[0].totalWritten).toBe(XHRStub.config.body.length);
    expect(handle.chunkCalls[0].contentLength).toBe(XHRStub.config.body.length);
  });

  it('receives the uint64 resume offset as bigint under WASM_BIGINT', () => {
    const handle = makeFakeModule();
    XHRStub.config.body = new Uint8Array([1, 2, 3]);

    const transport = FetchHttpTransport.install(handle.module);
    expect(transport).not.toBeNull();
    const resumePtr = handle.registrations[0].resume;
    const rc = handle.trampolines.get(resumePtr)!(
      /*user*/0,
      /*req*/0,
      5n,
      handle.chunkCallbackId,
      /*cbUd*/0,
      /*outMeta*/0,
    );

    expect(rc).toBe(0);
    expect(XHRStub.recordedHeaders).toContainEqual({ name: 'Range', value: 'bytes=5-' });
  });

  it('fans a multi-MiB body out across multiple chunk callbacks', () => {
    const handle = makeFakeModule();
    // 2.5 MiB body — STREAM_CHUNK_SIZE is 1 MiB, so this should produce
    // 3 callbacks (1 MiB, 1 MiB, 0.5 MiB).
    const total = (2 * 1024 * 1024) + (512 * 1024);
    const body = new Uint8Array(total);
    for (let i = 0; i < total; i += 1) body[i] = i & 0xff;
    XHRStub.config.body = body;
    XHRStub.config.status = 200;

    const transport = FetchHttpTransport.install(handle.module);
    const streamPtr = handle.registrations[0].stream;
    const rc = handle.trampolines.get(streamPtr)!(
      /*user*/0, /*req*/0, handle.chunkCallbackId, /*cbUd*/0, /*outMeta*/0,
    );
    expect(rc).toBe(0);
    expect(handle.chunkCalls.length).toBeGreaterThanOrEqual(3);
    // Sum of chunk lengths == total.
    const sum = handle.chunkCalls.reduce((acc, c) => acc + c.bytes.length, 0);
    expect(sum).toBe(total);
    // First chunk is bounded by STREAM_CHUNK_SIZE (1 MiB).
    expect(handle.chunkCalls[0].bytes.length).toBe(1024 * 1024);
    // Last chunk carries the residual.
    expect(handle.chunkCalls[handle.chunkCalls.length - 1].bytes.length)
      .toBe(total - 2 * 1024 * 1024);
    // totalWritten increases monotonically and reaches `total` on the last.
    expect(handle.chunkCalls[handle.chunkCalls.length - 1].totalWritten).toBe(total);
    void transport;
  });

  it('honours a chunk callback returning RAC_FALSE and surfaces RAC_ERROR_CANCELLED', () => {
    const handle = makeFakeModule();
    const total = 3 * 1024 * 1024; // 3 MiB — expect 3 callbacks at most
    const body = new Uint8Array(total);
    XHRStub.config.body = body;
    XHRStub.config.status = 200;
    handle.chunkStrategy = { cancelAt: 1 };

    const transport = FetchHttpTransport.install(handle.module);
    const streamPtr = handle.registrations[0].stream;
    const rc = handle.trampolines.get(streamPtr)!(
      /*user*/0, /*req*/0, handle.chunkCallbackId, /*cbUd*/0, /*outMeta*/0,
    );
    expect(rc).toBe(-380); // RAC_ERROR_CANCELLED
    expect(handle.chunkCalls).toHaveLength(1);
    void transport;
  });

  it('surfaces network error when XHR returns status=0', () => {
    const handle = makeFakeModule();
    XHRStub.config.body = new Uint8Array(0);
    XHRStub.config.status = 0; // browser network failure

    const transport = FetchHttpTransport.install(handle.module);
    const streamPtr = handle.registrations[0].stream;
    const rc = handle.trampolines.get(streamPtr)!(
      /*user*/0, /*req*/0, handle.chunkCallbackId, /*cbUd*/0, /*outMeta*/0,
    );
    expect(rc).toBe(-151); // RAC_ERROR_NETWORK_ERROR
    expect(handle.chunkCalls).toHaveLength(0);
    void transport;
  });

  it('sends and streams when Window rejects a synchronous XHR timeout', () => {
    const handle = makeFakeModule({ timeoutMs: 30_000 });
    XHRStub.config.body = new Uint8Array([10, 20, 30]);
    XHRStub.config.status = 200;
    XHRStub.config.timeoutAssignmentUnsupported = true;

    const transport = FetchHttpTransport.install(handle.module);
    expect(transport).not.toBeNull();
    const { send, stream } = handle.registrations[0];

    const sendResult = handle.trampolines.get(send)!(
      /*user*/0,
      /*req*/0,
      /*outResponse*/0,
    );
    expect(sendResult).toBe(0);

    const streamResult = handle.trampolines.get(stream)!(
      /*user*/0,
      /*req*/0,
      handle.chunkCallbackId,
      /*cbUd*/0,
      /*outMeta*/0,
    );
    expect(streamResult).toBe(0);
    expect(handle.chunkCalls).toHaveLength(1);
    expect(handle.chunkCalls[0].bytes).toEqual(XHRStub.config.body);
  });
});
