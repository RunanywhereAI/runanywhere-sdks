/**
 * LlamaCPP model-owning BackendWorker entrypoint.
 *
 * The worker owns the LlamaCpp WASM module, hydrates model bytes from OPFS,
 * and serves load/unload/stream/cancel over the BackendWorker RPC protocol so
 * generation does not run on the UI thread.
 */

import {
  callEmscriptenAsyncNumber,
  OPFSBridge,
  runBackendWorker,
  type BackendWorkerScope,
  type EmscriptenRunanywhereModule,
} from '@runanywhere/web/backend';
import { WorkerLlamaRuntime, type WorkerLlamaModule } from './workerLlamaRuntime.js';

export interface LlamaBackendWorkerInitPayload {
  acceleration?: 'auto' | 'webgpu' | 'cpu';
}

export interface LlamaBackendWorkerLoadPayload {
  requestBytes: Uint8Array;
  /** Encoded ModelInfo — registered into the worker WASM registry before load. */
  modelInfoBytes?: Uint8Array;
  hydratePaths?: string[];
}

export interface LlamaBackendWorkerUnloadPayload {
  requestBytes?: Uint8Array;
}

export interface LlamaBackendWorkerStreamPayload {
  requestBytes: Uint8Array;
}

export interface LlamaBackendWorkerInferPayload {
  requestBytes: Uint8Array;
}

interface LlamaBackendWorkerToolSessionPayload {
  requestBytes?: Uint8Array;
  sessionHandle?: bigint;
}

interface ToolSessionState {
  callbackPtr: number;
  events: Uint8Array[];
}

const runtime = new WorkerLlamaRuntime();
let activeStreamCancel: (() => void) | null = null;
const toolSessions = new Map<bigint, ToolSessionState>();

async function callUnaryProto(
  module: WorkerLlamaModule,
  exportName: string,
  requestBytes: Uint8Array,
): Promise<Uint8Array> {
  const fn = module[`_${exportName}`] as
    | ((requestPtr: number, requestSize: number, outPtr: number) => number | Promise<number>)
    | undefined;
  if (typeof fn !== 'function') {
    throw new Error(`Worker WASM missing ${exportName}`);
  }
  if (
    typeof module._rac_wasm_sizeof_proto_buffer !== 'function'
    || typeof module._rac_proto_buffer_init !== 'function'
    || typeof module._rac_proto_buffer_free !== 'function'
    || typeof module._rac_wasm_offsetof_proto_buffer_data !== 'function'
    || typeof module._rac_wasm_offsetof_proto_buffer_size !== 'function'
  ) {
    throw new Error('Worker WASM missing proto buffer exports');
  }
  // Keep request + out buffers alive for the full Asyncify lifetime. Nested
  // withHeapBytes + finally free races the WebGPU resume path and can Abort().
  const requestPtr = module._malloc(Math.max(requestBytes.byteLength, 1));
  if (!requestPtr) throw new Error(`Worker ${exportName} request alloc failed`);
  module.HEAPU8.set(requestBytes, requestPtr);
  const requestSize = requestBytes.byteLength;
  const outPtr = module._malloc(Math.max(module._rac_wasm_sizeof_proto_buffer(), 1));
  if (!outPtr) {
    module._free(requestPtr);
    throw new Error('Worker out-buffer allocation failed');
  }
  try {
    module._rac_proto_buffer_init(outPtr);
    let rc: number;
    try {
      rc = await callEmscriptenAsyncNumber(
        module as unknown as EmscriptenRunanywhereModule,
        exportName,
        ['number', 'number', 'number'],
        [requestPtr, requestSize, outPtr],
        () => fn(requestPtr, requestSize, outPtr),
      );
    } catch (error) {
      const diag = runtime.recentDiagnostics.slice(-20).join('\n');
      const base = error instanceof Error ? error.message : String(error);
      throw new Error(diag ? `${base}\n--- worker wasm ---\n${diag}` : base);
    }
    if (rc !== 0) {
      const diag = runtime.recentDiagnostics.slice(-20).join('\n');
      throw new Error(
        diag
          ? `${exportName} failed with code ${rc}\n--- worker wasm ---\n${diag}`
          : `${exportName} failed with code ${rc}`,
      );
    }
    const dataPtr = module.getValue(
      outPtr + module._rac_wasm_offsetof_proto_buffer_data(),
      '*',
    );
    const dataSize = module.getValue(
      outPtr + module._rac_wasm_offsetof_proto_buffer_size(),
      'i32',
    );
    if (!dataPtr || dataSize <= 0) {
      throw new Error(`${exportName} returned an empty result buffer`);
    }
    return module.HEAPU8.slice(dataPtr, dataPtr + dataSize);
  } finally {
    try {
      module._rac_proto_buffer_free(outPtr);
    } catch {
      /* ignore */
    }
    module._free(outPtr);
    module._free(requestPtr);
  }
}

async function callToolSessionCreate(
  module: WorkerLlamaModule,
  requestBytes: Uint8Array,
): Promise<{ sessionHandle: bigint; eventBytes: Uint8Array[] }> {
  const fn = module._rac_tool_calling_session_create_proto as
    | ((
      requestPtr: number,
      requestSize: number,
      callbackPtr: number,
      userData: number,
      handleCallbackPtr: number,
      handleUserData: number,
    ) => number | Promise<number>)
    | undefined;
  if (typeof fn !== 'function') {
    throw new Error('Worker WASM missing rac_tool_calling_session_create_proto');
  }
  const requestPtr = module._malloc(Math.max(requestBytes.byteLength, 1));
  if (!requestPtr) throw new Error('Worker tool session request alloc failed');
  module.HEAPU8.set(requestBytes, requestPtr);

  const state: ToolSessionState = { callbackPtr: 0, events: [] };
  let handleCallbackPtr = 0;
  let sessionHandle = 0n;
  const addFunction = module.addFunction as unknown as (
    callback: (...args: unknown[]) => void,
    signature: string,
  ) => number;
  try {
    state.callbackPtr = addFunction((bytesPtr: unknown, size: unknown) => {
      const ptr = Number(bytesPtr);
      const byteLength = Number(size);
      if (ptr && byteLength > 0) {
        state.events.push(module.HEAPU8.slice(ptr, ptr + byteLength));
      }
    }, 'viii');
    handleCallbackPtr = addFunction((handle: unknown) => {
      sessionHandle = BigInt(handle as bigint | number | string);
    }, 'vji');
    const rc = await callEmscriptenAsyncNumber(
      module as unknown as EmscriptenRunanywhereModule,
      'rac_tool_calling_session_create_proto',
      ['number', 'number', 'number', 'number', 'number', 'number'],
      [requestPtr, requestBytes.byteLength, state.callbackPtr, 0, handleCallbackPtr, 0],
      () => fn(
        requestPtr,
        requestBytes.byteLength,
        state.callbackPtr,
        0,
        handleCallbackPtr,
        0,
      ),
    );
    if (rc !== 0) {
      throw new Error(`rac_tool_calling_session_create_proto failed with code ${rc}`);
    }
    if (sessionHandle === 0n) {
      throw new Error('rac_tool_calling_session_create_proto returned no session handle');
    }
    toolSessions.set(sessionHandle, state);
    return { sessionHandle, eventBytes: state.events.splice(0) };
  } catch (error) {
    if (state.callbackPtr) module.removeFunction(state.callbackPtr);
    throw error;
  } finally {
    if (handleCallbackPtr) module.removeFunction(handleCallbackPtr);
    module._free(requestPtr);
  }
}

async function callToolSessionStep(
  module: WorkerLlamaModule,
  requestBytes: Uint8Array,
  sessionHandle: bigint,
): Promise<{ eventBytes: Uint8Array[] }> {
  const fn = module._rac_tool_calling_session_step_with_result_proto as
    | ((requestPtr: number, requestSize: number) => number | Promise<number>)
    | undefined;
  if (typeof fn !== 'function') {
    throw new Error('Worker WASM missing rac_tool_calling_session_step_with_result_proto');
  }
  const requestPtr = module._malloc(Math.max(requestBytes.byteLength, 1));
  if (!requestPtr) throw new Error('Worker tool session step alloc failed');
  module.HEAPU8.set(requestBytes, requestPtr);
  const state = toolSessions.get(sessionHandle);
  if (!state) {
    module._free(requestPtr);
    throw new Error(`Unknown tool-calling session handle: ${sessionHandle}`);
  }
  try {
    const rc = await callEmscriptenAsyncNumber(
      module as unknown as EmscriptenRunanywhereModule,
      'rac_tool_calling_session_step_with_result_proto',
      ['number', 'number'],
      [requestPtr, requestBytes.byteLength],
      () => fn(requestPtr, requestBytes.byteLength),
    );
    if (rc !== 0) {
      throw new Error(`rac_tool_calling_session_step_with_result_proto failed with code ${rc}`);
    }
    // commons dispatches events through the callback retained at create time.
    return { eventBytes: state.events.splice(0) };
  } finally {
    module._free(requestPtr);
  }
}

function callToolSessionControl(
  module: WorkerLlamaModule,
  operation: 'destroy' | 'cancel',
  sessionHandle: bigint,
): void {
  const exportName = operation === 'destroy'
    ? '_rac_tool_calling_session_destroy_proto'
    : '_rac_tool_calling_session_cancel_proto';
  const fn = module[exportName] as ((handle: bigint) => number) | undefined;
  if (typeof fn !== 'function') throw new Error(`Worker WASM missing ${exportName.slice(1)}`);
  const rc = fn(sessionHandle);
  if (rc !== 0) throw new Error(`${exportName.slice(1)} failed with code ${rc}`);
  if (operation === 'destroy') {
    const state = toolSessions.get(sessionHandle);
    if (state) {
      module.removeFunction(state.callbackPtr);
      toolSessions.delete(sessionHandle);
    }
  }
}

/** Best-effort: surface WASM abort/stderr before the DedicatedWorker dies. */
function installCrashDiagnostics(scope: BackendWorkerScope): void {
  const report = (source: string, detail: string): void => {
    try {
      scope.postMessage({
        type: 'error',
        message: `${source}: ${detail}`,
        // Host may ignore unknown fields; diagnostics also land in message.
      } as never);
      const lines = runtime.recentDiagnostics;
      if (lines.length) {
        scope.postMessage({
          type: 'error',
          message: `Worker diagnostics (${source}):\n${lines.join('\n')}`,
        });
      }
    } catch {
      /* ignore */
    }
  };
  const workerGlobal = self as unknown as {
    addEventListener?(type: string, listener: (event: Event) => void): void;
  };
  workerGlobal.addEventListener?.('error', (event) => {
    const err = event as ErrorEvent;
    report('uncaught', err.message || String(err.error ?? event));
  });
  workerGlobal.addEventListener?.('unhandledrejection', (event) => {
    const reason = (event as PromiseRejectionEvent).reason;
    report(
      'unhandledrejection',
      reason instanceof Error ? reason.message : String(reason),
    );
  });
}

async function hydratePaths(module: WorkerLlamaModule, paths: string[]): Promise<void> {
  if (!paths.length) return;
  const emscripten = module as unknown as EmscriptenRunanywhereModule;
  for (const path of paths) {
    if (!path) continue;
    await OPFSBridge.ensureModelPathReadyForLoad([emscripten], path);
  }
}

async function withHeapBytes<T>(
  module: WorkerLlamaModule,
  bytes: Uint8Array,
  fn: (ptr: number, size: number) => Promise<T> | T,
): Promise<T> {
  const ptr = module._malloc(Math.max(bytes.byteLength, 1));
  if (!ptr) throw new Error('Worker heap allocation failed');
  try {
    module.HEAPU8.set(bytes, ptr);
    return await fn(ptr, bytes.byteLength);
  } finally {
    module._free(ptr);
  }
}

async function registerModelInfo(
  module: WorkerLlamaModule,
  modelInfoBytes: Uint8Array,
): Promise<void> {
  const registry = module._rac_get_model_registry?.();
  if (!registry) {
    throw new Error('Worker model registry handle is null');
  }
  const registerFn = module._rac_model_registry_register_proto as
    | ((handle: number, bytes: number, size: number) => number)
    | undefined;
  if (typeof registerFn !== 'function') {
    throw new Error('Worker WASM missing rac_model_registry_register_proto');
  }
  const rc = await withHeapBytes(module, modelInfoBytes, (ptr, size) => (
    registerFn(registry, ptr, size)
  ));
  // 0 = success. Non-zero can mean already-registered depending on build;
  // lifecycle load will surface a real missing-entry failure if needed.
  if (rc !== 0) {
    // Best-effort: continue — update path may still succeed via overwrite.
  }
}

async function callLoad(
  module: WorkerLlamaModule,
  requestBytes: Uint8Array,
): Promise<Uint8Array> {
  const registry = module._rac_get_model_registry?.();
  if (!registry) throw new Error('Worker model registry handle is null');
  if (
    typeof module._rac_model_lifecycle_load_proto !== 'function'
    || typeof module._rac_wasm_sizeof_proto_buffer !== 'function'
    || typeof module._rac_proto_buffer_init !== 'function'
    || typeof module._rac_proto_buffer_free !== 'function'
    || typeof module._rac_wasm_offsetof_proto_buffer_data !== 'function'
    || typeof module._rac_wasm_offsetof_proto_buffer_size !== 'function'
  ) {
    throw new Error('Worker WASM missing model lifecycle / proto buffer exports');
  }

  const outSize = module._rac_wasm_sizeof_proto_buffer();
  const outPtr = module._malloc(Math.max(outSize, 1));
  if (!outPtr) throw new Error('Worker out-buffer allocation failed');
  try {
    module._rac_proto_buffer_init(outPtr);
    const rc = await withHeapBytes(module, requestBytes, (requestPtr, requestSize) => (
      callEmscriptenAsyncNumber(
        module as unknown as EmscriptenRunanywhereModule,
        'rac_model_lifecycle_load_proto',
        ['number', 'number', 'number', 'number'],
        [registry, requestPtr, requestSize, outPtr],
        () => module._rac_model_lifecycle_load_proto!(
          registry,
          requestPtr,
          requestSize,
          outPtr,
        ),
      )
    ));
    if (rc !== 0) {
      throw new Error(`Worker model load failed with code ${rc}`);
    }
    const dataPtr = module.getValue(
      outPtr + module._rac_wasm_offsetof_proto_buffer_data(),
      '*',
    );
    const dataSize = module.getValue(
      outPtr + module._rac_wasm_offsetof_proto_buffer_size(),
      'i32',
    );
    if (!dataPtr || dataSize <= 0) {
      throw new Error('Worker model load returned an empty result buffer');
    }
    return module.HEAPU8.slice(dataPtr, dataPtr + dataSize);
  } finally {
    module._rac_proto_buffer_free(outPtr);
    module._free(outPtr);
  }
}

async function callUnload(
  module: WorkerLlamaModule,
  requestBytes: Uint8Array,
): Promise<Uint8Array | undefined> {
  if (typeof module._rac_model_lifecycle_unload_proto !== 'function') {
    throw new Error('Worker WASM missing unload export');
  }
  if (
    typeof module._rac_wasm_sizeof_proto_buffer !== 'function'
    || typeof module._rac_proto_buffer_init !== 'function'
    || typeof module._rac_proto_buffer_free !== 'function'
  ) {
    throw new Error('Worker WASM missing proto buffer exports');
  }
  const outSize = module._rac_wasm_sizeof_proto_buffer();
  const outPtr = module._malloc(Math.max(outSize, 1));
  if (!outPtr) throw new Error('Worker out-buffer allocation failed');
  try {
    module._rac_proto_buffer_init(outPtr);
    await withHeapBytes(module, requestBytes, (requestPtr, requestSize) => (
      callEmscriptenAsyncNumber(
        module as unknown as EmscriptenRunanywhereModule,
        'rac_model_lifecycle_unload_proto',
        ['number', 'number', 'number'],
        [requestPtr, requestSize, outPtr],
        () => module._rac_model_lifecycle_unload_proto!(
          requestPtr,
          requestSize,
          outPtr,
        ),
      )
    ));
    const dataOffset = module._rac_wasm_offsetof_proto_buffer_data?.() ?? 0;
    const sizeOffset = module._rac_wasm_offsetof_proto_buffer_size?.() ?? 0;
    if (!dataOffset || !sizeOffset) return undefined;
    const dataPtr = module.getValue(outPtr + dataOffset, '*');
    const dataSize = module.getValue(outPtr + sizeOffset, 'i32');
    if (!dataPtr || dataSize <= 0) return undefined;
    return module.HEAPU8.slice(dataPtr, dataPtr + dataSize);
  } finally {
    module._rac_proto_buffer_free(outPtr);
    module._free(outPtr);
  }
}

type WorkerStreamExport = {
  streamName: string;
  streamFn: (
    requestPtr: number,
    requestSize: number,
    callbackPtr: number,
    userData: number,
  ) => number | Promise<number>;
  cancelName?: string;
  cancelFn?: (outEvent: number) => number;
};

async function* streamProtoEvents(
  module: WorkerLlamaModule,
  requestBytes: Uint8Array,
  exports: WorkerStreamExport,
  label: string,
): AsyncGenerator<Uint8Array> {
  if (!module.addFunction || !module.removeFunction) {
    throw new Error('Worker WASM missing addFunction/removeFunction');
  }

  const queue: Uint8Array[] = [];
  let done = false;
  let failed: Error | null = null;
  let waiters: Array<() => void> = [];
  const wake = (): void => {
    const pending = waiters;
    waiters = [];
    for (const resolve of pending) resolve();
  };

  // Keep request bytes alive for the full Asyncify call — do not free them
  // from a short-lived withHeapBytes scope that races WebGPU resume.
  const requestPtr = module._malloc(Math.max(requestBytes.byteLength, 1));
  if (!requestPtr) throw new Error(`Worker ${label} stream request alloc failed`);
  module.HEAPU8.set(requestBytes, requestPtr);
  const requestSize = requestBytes.byteLength;

  const callbackPtr = module.addFunction((bytesPtr: number, size: number): void => {
    if (!bytesPtr || size <= 0) return;
    queue.push(module.HEAPU8.slice(bytesPtr, bytesPtr + size));
    wake();
  }, 'viii');

  let cancelPosted = false;
  activeStreamCancel = () => {
    if (cancelPosted) return;
    cancelPosted = true;
    if (
      exports.cancelFn
      && module._rac_wasm_sizeof_proto_buffer
      && module._rac_proto_buffer_init
      && module._rac_proto_buffer_free
    ) {
      const sz = module._rac_wasm_sizeof_proto_buffer();
      const bufPtr = module._malloc(Math.max(sz, 1));
      if (bufPtr) {
        try {
          module._rac_proto_buffer_init(bufPtr);
          exports.cancelFn(bufPtr);
        } finally {
          module._rac_proto_buffer_free(bufPtr);
          module._free(bufPtr);
        }
      }
    }
  };

  const streamPromise = callEmscriptenAsyncNumber(
    module as unknown as EmscriptenRunanywhereModule,
    exports.streamName,
    ['number', 'number', 'number', 'number'],
    [requestPtr, requestSize, callbackPtr, 0],
    () => exports.streamFn(requestPtr, requestSize, callbackPtr, 0),
  ).then((rc) => {
    if (rc !== 0) {
      failed = new Error(`Worker ${label} stream failed with code ${rc}`);
    }
  }).catch((error: unknown) => {
    failed = error instanceof Error ? error : new Error(String(error));
  }).finally(() => {
    done = true;
    wake();
    try {
      module.removeFunction(callbackPtr);
    } catch {
      /* ignore */
    }
    module._free(requestPtr);
    activeStreamCancel = null;
  });

  try {
    while (!done || queue.length > 0) {
      if (queue.length === 0) {
        if (done) break;
        await new Promise<void>((resolve) => { waiters.push(resolve); });
        continue;
      }
      yield queue.shift()!;
    }
    await streamPromise;
    if (failed) throw failed;
  } finally {
    activeStreamCancel = null;
  }
}

async function* streamLLM(
  module: WorkerLlamaModule,
  requestBytes: Uint8Array,
): AsyncGenerator<Uint8Array> {
  if (typeof module._rac_llm_generate_stream_proto !== 'function') {
    throw new Error('Worker WASM missing rac_llm_generate_stream_proto');
  }
  yield* streamProtoEvents(module, requestBytes, {
    streamName: 'rac_llm_generate_stream_proto',
    streamFn: (requestPtr, requestSize, callbackPtr, userData) => (
      module._rac_llm_generate_stream_proto!(requestPtr, requestSize, callbackPtr, userData)
    ),
    cancelName: 'rac_llm_cancel_proto',
    cancelFn: module._rac_llm_cancel_proto
      ? (outEvent) => module._rac_llm_cancel_proto!(outEvent)
      : undefined,
  }, 'LLM');
}

async function* streamVLM(
  module: WorkerLlamaModule,
  requestBytes: Uint8Array,
): AsyncGenerator<Uint8Array> {
  const streamFn = module._rac_vlm_stream_proto as WorkerStreamExport['streamFn'] | undefined;
  if (typeof streamFn !== 'function') {
    throw new Error('Worker WASM missing rac_vlm_stream_proto');
  }
  const cancelFn = module._rac_vlm_cancel_lifecycle_proto as
    | ((outEvent: number) => number)
    | undefined;
  yield* streamProtoEvents(module, requestBytes, {
    streamName: 'rac_vlm_stream_proto',
    streamFn,
    cancelName: 'rac_vlm_cancel_lifecycle_proto',
    cancelFn,
  }, 'VLM');
}

const workerScope = self as unknown as BackendWorkerScope;
installCrashDiagnostics(workerScope);

runBackendWorker(workerScope, {
  async init(payload: unknown): Promise<void> {
    const options = (payload ?? {}) as LlamaBackendWorkerInitPayload;
    await runtime.ensureLoaded(options.acceleration ?? 'auto');
  },

  async loadModel(_modality, payload: unknown): Promise<unknown> {
    const body = payload as LlamaBackendWorkerLoadPayload;
    if (!body?.requestBytes) throw new Error('loadModel requires requestBytes');
    const module = runtime.requireModule();
    // Worker WASM has its own s_model_registry. Catalog registration on the
    // main thread does not propagate here — seed ModelInfo before lifecycle.
    if (body.modelInfoBytes?.byteLength) {
      await registerModelInfo(module, body.modelInfoBytes);
    }
    await hydratePaths(module, body.hydratePaths ?? []);
    const resultBytes = await callLoad(module, body.requestBytes);
    return { resultBytes };
  },

  async unloadModel(_modality, payload: unknown): Promise<unknown> {
    const body = (payload ?? {}) as LlamaBackendWorkerUnloadPayload;
    const module = runtime.requireModule();
    if (!body.requestBytes) return { ok: true };
    const resultBytes = await callUnload(module, body.requestBytes);
    return { resultBytes };
  },

  async infer(kind, payload: unknown): Promise<unknown> {
    if (kind === 'lora.apply' || kind === 'lora.remove') {
      const body = payload as LlamaBackendWorkerInferPayload;
      if (!body?.requestBytes) throw new Error('infer requires requestBytes');
      const exportName = kind === 'lora.apply'
        ? 'rac_lora_apply_proto'
        : 'rac_lora_remove_proto';
      return {
        resultBytes: await callUnaryProto(runtime.requireModule(), exportName, body.requestBytes),
      };
    }
    if (kind === 'structured.parse') {
      const body = payload as LlamaBackendWorkerInferPayload;
      if (!body?.requestBytes) throw new Error('structured.parse requires requestBytes');
      return {
        resultBytes: await callUnaryProto(
          runtime.requireModule(),
          'rac_structured_output_parse_proto',
          body.requestBytes,
        ),
      };
    }
    if (
      kind === 'tool.sessionCreate'
      || kind === 'tool.sessionStep'
      || kind === 'tool.sessionDestroy'
      || kind === 'tool.sessionCancel'
    ) {
      const body = payload as LlamaBackendWorkerToolSessionPayload;
      const module = runtime.requireModule();
      if (kind === 'tool.sessionCreate') {
        if (!body?.requestBytes) throw new Error('tool.sessionCreate requires requestBytes');
        return callToolSessionCreate(module, body.requestBytes);
      }
      if (kind === 'tool.sessionStep') {
        if (!body?.requestBytes) throw new Error('tool.sessionStep requires requestBytes');
        if (body.sessionHandle === undefined) {
          throw new Error('tool.sessionStep requires sessionHandle');
        }
        return callToolSessionStep(module, body.requestBytes, body.sessionHandle);
      }
      if (body?.sessionHandle === undefined) {
        throw new Error(`${kind} requires sessionHandle`);
      }
      callToolSessionControl(
        module,
        kind === 'tool.sessionDestroy' ? 'destroy' : 'cancel',
        body.sessionHandle,
      );
      return { ok: true };
    }
    if (kind !== 'llm.generate' && kind !== 'vlm.generate') {
      throw new Error(`Unsupported infer kind: ${kind}`);
    }
    const body = payload as LlamaBackendWorkerInferPayload;
    if (!body?.requestBytes) throw new Error('infer requires requestBytes');
    const module = runtime.requireModule();
    const exportName = kind === 'llm.generate'
      ? 'rac_llm_generate_proto'
      : 'rac_vlm_generate_proto';
    return {
      resultBytes: await callUnaryProto(module, exportName, body.requestBytes),
    };
  },

  stream(kind, payload: unknown): AsyncIterable<unknown> {
    if (kind !== 'llm.generate' && kind !== 'vlm.generate') {
      throw new Error(`Unsupported stream kind: ${kind}`);
    }
    const body = payload as LlamaBackendWorkerStreamPayload;
    if (!body?.requestBytes) throw new Error('stream requires requestBytes');
    const module = runtime.requireModule();
    return kind === 'llm.generate'
      ? streamLLM(module, body.requestBytes)
      : streamVLM(module, body.requestBytes);
  },

  cancel(): void {
    activeStreamCancel?.();
  },

  async teardown(): Promise<void> {
    activeStreamCancel?.();
    await runtime.teardown();
  },

  health() {
    return {
      healthy: runtime.isLoaded,
      details: {
        acceleration: runtime.acceleration,
        diagnostics: runtime.recentDiagnostics,
      },
    };
  },
});
