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

const runtime = new WorkerLlamaRuntime();
let activeStreamCancel: (() => void) | null = null;

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

async function* streamLLM(
  module: WorkerLlamaModule,
  requestBytes: Uint8Array,
): AsyncGenerator<Uint8Array> {
  if (typeof module._rac_llm_generate_stream_proto !== 'function') {
    throw new Error('Worker WASM missing rac_llm_generate_stream_proto');
  }
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
      module._rac_llm_cancel_proto
      && module._rac_wasm_sizeof_proto_buffer
      && module._rac_proto_buffer_init
      && module._rac_proto_buffer_free
    ) {
      const sz = module._rac_wasm_sizeof_proto_buffer();
      const bufPtr = module._malloc(Math.max(sz, 1));
      if (bufPtr) {
        try {
          module._rac_proto_buffer_init(bufPtr);
          module._rac_llm_cancel_proto(bufPtr);
        } finally {
          module._rac_proto_buffer_free(bufPtr);
          module._free(bufPtr);
        }
      }
    }
  };

  const streamPromise = withHeapBytes(module, requestBytes, (requestPtr, requestSize) => (
    callEmscriptenAsyncNumber(
      module as unknown as EmscriptenRunanywhereModule,
      'rac_llm_generate_stream_proto',
      ['number', 'number', 'number', 'number'],
      [requestPtr, requestSize, callbackPtr, 0],
      () => module._rac_llm_generate_stream_proto!(
        requestPtr,
        requestSize,
        callbackPtr,
        0,
      ),
    )
  )).then((rc) => {
    if (rc !== 0) {
      failed = new Error(`Worker LLM stream failed with code ${rc}`);
    }
  }).catch((error: unknown) => {
    failed = error instanceof Error ? error : new Error(String(error));
  }).finally(() => {
    done = true;
    wake();
    module.removeFunction(callbackPtr);
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

runBackendWorker(self as unknown as BackendWorkerScope, {
  async init(payload: unknown): Promise<void> {
    const options = (payload ?? {}) as LlamaBackendWorkerInitPayload;
    await runtime.ensureLoaded(options.acceleration ?? 'auto');
  },

  async loadModel(_modality, payload: unknown): Promise<unknown> {
    const body = payload as LlamaBackendWorkerLoadPayload;
    if (!body?.requestBytes) throw new Error('loadModel requires requestBytes');
    const module = runtime.requireModule();
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
    if (kind !== 'llm.generate') {
      throw new Error(`Unsupported infer kind: ${kind}`);
    }
    const body = payload as LlamaBackendWorkerInferPayload;
    if (!body?.requestBytes) throw new Error('infer requires requestBytes');
    const module = runtime.requireModule();
    if (typeof module._rac_llm_generate_proto !== 'function') {
      throw new Error('Worker WASM missing rac_llm_generate_proto');
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
    const outSize = module._rac_wasm_sizeof_proto_buffer();
    const outPtr = module._malloc(Math.max(outSize, 1));
    if (!outPtr) throw new Error('Worker out-buffer allocation failed');
    try {
      module._rac_proto_buffer_init(outPtr);
      const rc = await withHeapBytes(module, body.requestBytes, (requestPtr, requestSize) => (
        callEmscriptenAsyncNumber(
          module as unknown as EmscriptenRunanywhereModule,
          'rac_llm_generate_proto',
          ['number', 'number', 'number'],
          [requestPtr, requestSize, outPtr],
          () => module._rac_llm_generate_proto!(requestPtr, requestSize, outPtr),
        )
      ));
      if (rc !== 0) throw new Error(`Worker LLM generate failed with code ${rc}`);
      const dataPtr = module.getValue(
        outPtr + module._rac_wasm_offsetof_proto_buffer_data(),
        '*',
      );
      const dataSize = module.getValue(
        outPtr + module._rac_wasm_offsetof_proto_buffer_size(),
        'i32',
      );
      if (!dataPtr || dataSize <= 0) {
        throw new Error('Worker LLM generate returned an empty result buffer');
      }
      return { resultBytes: module.HEAPU8.slice(dataPtr, dataPtr + dataSize) };
    } finally {
      module._rac_proto_buffer_free(outPtr);
      module._free(outPtr);
    }
  },

  stream(kind, payload: unknown): AsyncIterable<unknown> {
    if (kind !== 'llm.generate') {
      throw new Error(`Unsupported stream kind: ${kind}`);
    }
    const body = payload as LlamaBackendWorkerStreamPayload;
    if (!body?.requestBytes) throw new Error('stream requires requestBytes');
    const module = runtime.requireModule();
    return streamLLM(module, body.requestBytes);
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
      details: { acceleration: runtime.acceleration },
    };
  },
});
