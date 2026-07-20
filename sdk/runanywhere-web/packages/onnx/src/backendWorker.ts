import {
  callEmscriptenAsyncNumber,
  OPFSBridge,
  runBackendWorker,
  type BackendWorkerScope,
  type EmscriptenRunanywhereModule,
} from '@runanywhere/web/backend';
import { WorkerOnnxRuntime, type WorkerOnnxModule } from './workerOnnxRuntime.js';

interface WorkerLoadPayload {
  requestBytes: Uint8Array;
  modelInfoBytes?: Uint8Array;
  hydratePaths?: string[];
}

interface WorkerRequestPayload {
  requestBytes: Uint8Array;
}

interface RAGSessionPayload {
  session: number;
  requestBytes?: Uint8Array;
}

const runtime = new WorkerOnnxRuntime();
let activeStreamCancel: (() => void) | null = null;

async function withHeapBytes<T>(
  module: WorkerOnnxModule,
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

async function hydratePaths(module: WorkerOnnxModule, paths: readonly string[]): Promise<void> {
  const emscripten = module as unknown as EmscriptenRunanywhereModule;
  for (const path of paths) {
    if (path) await OPFSBridge.ensureModelPathReadyForLoad([emscripten], path);
  }
}

async function registerModelInfo(module: WorkerOnnxModule, bytes: Uint8Array): Promise<void> {
  const registry = (module._rac_get_model_registry as (() => number) | undefined)?.();
  const register = module._rac_model_registry_register_proto as
    | ((handle: number, bytesPtr: number, bytesSize: number) => number | Promise<number>)
    | undefined;
  if (!registry || !register) throw new Error('Worker WASM missing model registry exports');
  await withHeapBytes(module, bytes, (ptr, size) => register(registry, ptr, size));
}

function requireProtoBuffer(module: WorkerOnnxModule): {
  size: () => number;
  init: (ptr: number) => void;
  free: (ptr: number) => void;
  dataOffset: () => number;
  sizeOffset: () => number;
} {
  const size = module._rac_wasm_sizeof_proto_buffer as (() => number) | undefined;
  const init = module._rac_proto_buffer_init as ((ptr: number) => void) | undefined;
  const free = module._rac_proto_buffer_free as ((ptr: number) => void) | undefined;
  const dataOffset = module._rac_wasm_offsetof_proto_buffer_data as (() => number) | undefined;
  const sizeOffset = module._rac_wasm_offsetof_proto_buffer_size as (() => number) | undefined;
  if (!size || !init || !free || !dataOffset || !sizeOffset) {
    throw new Error('Worker WASM missing proto buffer exports');
  }
  return { size, init, free, dataOffset, sizeOffset };
}

async function callLifecycle(
  module: WorkerOnnxModule,
  exportName: string,
  requestBytes: Uint8Array,
): Promise<Uint8Array> {
  const fn = module[`_${exportName}`] as
    | ((requestPtr: number, requestSize: number, outPtr: number) => number | Promise<number>)
    | undefined;
  if (!fn) throw new Error(`Worker WASM missing ${exportName}`);
  const buffer = requireProtoBuffer(module);
  const outPtr = module._malloc(Math.max(buffer.size(), 1));
  if (!outPtr) throw new Error('Worker out-buffer allocation failed');
  try {
    buffer.init(outPtr);
    const rc = await withHeapBytes(module, requestBytes, (requestPtr, requestSize) => (
      callEmscriptenAsyncNumber(
        module as unknown as EmscriptenRunanywhereModule,
        exportName,
        ['number', 'number', 'number'],
        [requestPtr, requestSize, outPtr],
        () => fn(requestPtr, requestSize, outPtr),
      )
    ));
    if (rc !== 0) throw new Error(`${exportName} failed with code ${rc}`);
    const dataPtr = module.getValue(outPtr + buffer.dataOffset(), '*');
    const dataSize = module.getValue(outPtr + buffer.sizeOffset(), 'i32');
    if (!dataPtr || dataSize <= 0) throw new Error(`${exportName} returned an empty result buffer`);
    return module.HEAPU8.slice(dataPtr, dataPtr + dataSize);
  } finally {
    buffer.free(outPtr);
    module._free(outPtr);
  }
}

async function callLoad(module: WorkerOnnxModule, requestBytes: Uint8Array): Promise<Uint8Array> {
  const registry = (module._rac_get_model_registry as (() => number) | undefined)?.();
  const fn = module._rac_model_lifecycle_load_proto as
    | ((handle: number, requestPtr: number, requestSize: number, outPtr: number) => number | Promise<number>)
    | undefined;
  if (!registry || !fn) throw new Error('Worker WASM missing model lifecycle load exports');
  const buffer = requireProtoBuffer(module);
  const outPtr = module._malloc(Math.max(buffer.size(), 1));
  if (!outPtr) throw new Error('Worker out-buffer allocation failed');
  try {
    buffer.init(outPtr);
    const rc = await withHeapBytes(module, requestBytes, (requestPtr, requestSize) => (
      callEmscriptenAsyncNumber(
        module as unknown as EmscriptenRunanywhereModule,
        'rac_model_lifecycle_load_proto',
        ['number', 'number', 'number', 'number'],
        [registry, requestPtr, requestSize, outPtr],
        () => fn(registry, requestPtr, requestSize, outPtr),
      )
    ));
    if (rc !== 0) throw new Error(`Worker model load failed with code ${rc}`);
    const dataPtr = module.getValue(outPtr + buffer.dataOffset(), '*');
    const dataSize = module.getValue(outPtr + buffer.sizeOffset(), 'i32');
    if (!dataPtr || dataSize <= 0) throw new Error('Worker model load returned an empty result buffer');
    return module.HEAPU8.slice(dataPtr, dataPtr + dataSize);
  } finally {
    buffer.free(outPtr);
    module._free(outPtr);
  }
}

async function callUnload(module: WorkerOnnxModule, requestBytes: Uint8Array): Promise<Uint8Array> {
  return callLifecycle(module, 'rac_model_lifecycle_unload_proto', requestBytes);
}

async function callRAGSessionCreate(
  module: WorkerOnnxModule,
  requestBytes: Uint8Array,
): Promise<number> {
  const fn = module._rac_rag_session_create_proto as
    | ((configPtr: number, configSize: number, outSession: number) => number | Promise<number>)
    | undefined;
  if (!fn) throw new Error('Worker WASM missing rac_rag_session_create_proto');
  const outSession = module._malloc(4);
  if (!outSession) throw new Error('Worker RAG session allocation failed');
  try {
    module.setValue(outSession, 0, 'i32');
    const rc = await withHeapBytes(module, requestBytes, (configPtr, configSize) => (
      callEmscriptenAsyncNumber(
        module as unknown as EmscriptenRunanywhereModule,
        'rac_rag_session_create_proto',
        ['number', 'number', 'number'],
        [configPtr, configSize, outSession],
        () => fn(configPtr, configSize, outSession),
      )
    ));
    if (rc !== 0) {
      throw new Error(
        rc === -110
          ? 'rac_rag_session_create_proto failed with code -110 (MODEL_NOT_FOUND). '
            + 'A required RAG artifact is not in this worker heap; the facade should '
            + 'compose across BackendWorkers when ownership is split.'
          : `rac_rag_session_create_proto failed with code ${rc}`,
      );
    }
    const session = module.getValue(outSession, 'i32');
    if (!session) throw new Error('rac_rag_session_create_proto returned an empty session handle');
    return session;
  } finally {
    module._free(outSession);
  }
}

async function callRAGWithRequest(
  module: WorkerOnnxModule,
  exportName: 'rac_rag_ingest_proto' | 'rac_rag_query_proto',
  session: number,
  requestBytes: Uint8Array,
): Promise<Uint8Array> {
  const fn = module[`_${exportName}`] as
    | ((session: number, requestPtr: number, requestSize: number, outPtr: number) => number | Promise<number>)
    | undefined;
  if (!fn) throw new Error(`Worker WASM missing ${exportName}`);
  const buffer = requireProtoBuffer(module);
  const outPtr = module._malloc(Math.max(buffer.size(), 1));
  if (!outPtr) throw new Error('Worker out-buffer allocation failed');
  try {
    buffer.init(outPtr);
    const rc = await withHeapBytes(module, requestBytes, (requestPtr, requestSize) => (
      callEmscriptenAsyncNumber(
        module as unknown as EmscriptenRunanywhereModule,
        exportName,
        ['number', 'number', 'number', 'number'],
        [session, requestPtr, requestSize, outPtr],
        () => fn(session, requestPtr, requestSize, outPtr),
      )
    ));
    if (rc !== 0) throw new Error(`${exportName} failed with code ${rc}`);
    const dataPtr = module.getValue(outPtr + buffer.dataOffset(), '*');
    const dataSize = module.getValue(outPtr + buffer.sizeOffset(), 'i32');
    if (!dataPtr || dataSize <= 0) throw new Error(`${exportName} returned an empty result buffer`);
    return module.HEAPU8.slice(dataPtr, dataPtr + dataSize);
  } finally {
    buffer.free(outPtr);
    module._free(outPtr);
  }
}

async function callRAGStats(
  module: WorkerOnnxModule,
  exportName: 'rac_rag_clear_proto' | 'rac_rag_stats_proto',
  session: number,
): Promise<Uint8Array> {
  const fn = module[`_${exportName}`] as
    | ((session: number, outPtr: number) => number | Promise<number>)
    | undefined;
  if (!fn) throw new Error(`Worker WASM missing ${exportName}`);
  const buffer = requireProtoBuffer(module);
  const outPtr = module._malloc(Math.max(buffer.size(), 1));
  if (!outPtr) throw new Error('Worker out-buffer allocation failed');
  try {
    buffer.init(outPtr);
    const rc = await callEmscriptenAsyncNumber(
      module as unknown as EmscriptenRunanywhereModule,
      exportName,
      ['number', 'number'],
      [session, outPtr],
      () => fn(session, outPtr),
    );
    if (rc !== 0) throw new Error(`${exportName} failed with code ${rc}`);
    const dataPtr = module.getValue(outPtr + buffer.dataOffset(), '*');
    const dataSize = module.getValue(outPtr + buffer.sizeOffset(), 'i32');
    if (!dataPtr || dataSize <= 0) throw new Error(`${exportName} returned an empty result buffer`);
    return module.HEAPU8.slice(dataPtr, dataPtr + dataSize);
  } finally {
    buffer.free(outPtr);
    module._free(outPtr);
  }
}

async function* streamLifecycle(
  module: WorkerOnnxModule,
  exportName: 'rac_stt_transcribe_stream_lifecycle_proto' | 'rac_tts_synthesize_stream_lifecycle_proto',
  requestBytes: Uint8Array,
): AsyncGenerator<Uint8Array> {
  const fn = module[`_${exportName}`] as
    | ((requestPtr: number, requestSize: number, callbackPtr: number, userData: number) => number | Promise<number>)
    | undefined;
  if (!fn || !module.addFunction || !module.removeFunction) {
    throw new Error(`Worker WASM missing ${exportName} callback exports`);
  }
  const queue: Uint8Array[] = [];
  let done = false;
  let failure: unknown;
  let wake: (() => void) | null = null;
  const requestPtr = module._malloc(Math.max(requestBytes.byteLength, 1));
  if (!requestPtr) throw new Error('Worker stream request allocation failed');
  module.HEAPU8.set(requestBytes, requestPtr);
  const callbackPtr = module.addFunction((bytesPtr: number, size: number): void => {
    if (bytesPtr && size > 0) queue.push(module.HEAPU8.slice(bytesPtr, bytesPtr + size));
    wake?.();
  }, 'viii');
  activeStreamCancel = () => {
    if (exportName === 'rac_tts_synthesize_stream_lifecycle_proto') {
      const stop = module._rac_tts_stop_lifecycle_proto as ((outPtr: number) => number) | undefined;
      if (stop) {
        const buffer = requireProtoBuffer(module);
        const outPtr = module._malloc(Math.max(buffer.size(), 1));
        try {
          if (outPtr) {
            buffer.init(outPtr);
            stop(outPtr);
          }
        } finally {
          if (outPtr) {
            buffer.free(outPtr);
            module._free(outPtr);
          }
        }
      }
    }
  };
  const operation = callEmscriptenAsyncNumber(
    module as unknown as EmscriptenRunanywhereModule,
    exportName,
    ['number', 'number', 'number', 'number'],
    [requestPtr, requestBytes.byteLength, callbackPtr, 0],
    () => fn(requestPtr, requestBytes.byteLength, callbackPtr, 0),
  ).then((rc) => {
    if (rc !== 0) failure = new Error(`${exportName} failed with code ${rc}`);
  }).catch((error: unknown) => {
    failure = error;
  }).finally(() => {
    done = true;
    wake?.();
    module.removeFunction?.(callbackPtr);
    module._free(requestPtr);
    activeStreamCancel = null;
  });
  try {
    while (!done || queue.length) {
      if (queue.length) {
        yield queue.shift()!;
      } else if (!done) {
        await new Promise<void>((resolve) => { wake = resolve; });
        wake = null;
      }
    }
    await operation;
    if (failure) throw failure;
  } finally {
    activeStreamCancel = null;
  }
}

const workerScope = self as unknown as BackendWorkerScope;
runBackendWorker(workerScope, {
  async init(): Promise<void> {
    await runtime.ensureLoaded();
  },

  async loadModel(modality, payload: unknown): Promise<unknown> {
    if (!['stt', 'tts', 'vad', 'embeddings'].includes(modality)) {
      throw new Error(`Unsupported ONNX model modality: ${modality}`);
    }
    const body = payload as WorkerLoadPayload;
    if (!body?.requestBytes) throw new Error('loadModel requires requestBytes');
    const module = runtime.requireModule();
    if (body.modelInfoBytes?.byteLength) await registerModelInfo(module, body.modelInfoBytes);
    await hydratePaths(module, body.hydratePaths ?? []);
    return { resultBytes: await callLoad(module, body.requestBytes) };
  },

  async unloadModel(_modality, payload: unknown): Promise<unknown> {
    const body = payload as WorkerRequestPayload;
    if (!body?.requestBytes) return { ok: true };
    return { resultBytes: await callUnload(runtime.requireModule(), body.requestBytes) };
  },

  async infer(kind, payload: unknown): Promise<unknown> {
    if (kind.startsWith('rag.')) {
      const body = payload as RAGSessionPayload;
      const module = runtime.requireModule();
      if (kind === 'rag.sessionCreate') {
        if (!body?.requestBytes) throw new Error('rag.sessionCreate requires requestBytes');
        return { session: await callRAGSessionCreate(module, body.requestBytes) };
      }
      if (!body || !body.session) throw new Error(`${kind} requires a session handle`);
      if (kind === 'rag.sessionDestroy') {
        const destroy = module._rac_rag_session_destroy_proto as ((session: number) => void) | undefined;
        if (!destroy) throw new Error('Worker WASM missing rac_rag_session_destroy_proto');
        destroy(body.session);
        return { ok: true };
      }
      if (kind === 'rag.ingest' || kind === 'rag.query') {
        if (!body.requestBytes) throw new Error(`${kind} requires requestBytes`);
        const exportName = kind === 'rag.ingest' ? 'rac_rag_ingest_proto' : 'rac_rag_query_proto';
        return { resultBytes: await callRAGWithRequest(module, exportName, body.session, body.requestBytes) };
      }
      if (kind === 'rag.clear' || kind === 'rag.stats') {
        const exportName = kind === 'rag.clear' ? 'rac_rag_clear_proto' : 'rac_rag_stats_proto';
        return { resultBytes: await callRAGStats(module, exportName, body.session) };
      }
      throw new Error(`Unsupported ONNX infer kind: ${kind}`);
    }
    const body = payload as WorkerRequestPayload;
    if (!body?.requestBytes) throw new Error('infer requires requestBytes');
    const exportName = ({
      'stt.transcribe': 'rac_stt_transcribe_lifecycle_proto',
      'tts.synthesize': 'rac_tts_synthesize_lifecycle_proto',
      'vad.process': 'rac_vad_process_lifecycle_proto',
      'embeddings.embed': 'rac_embeddings_embed_batch_lifecycle_proto',
    } as Partial<Record<string, string>>)[kind];
    if (!exportName) throw new Error(`Unsupported ONNX infer kind: ${kind}`);
    return { resultBytes: await callLifecycle(runtime.requireModule(), exportName, body.requestBytes) };
  },

  stream(kind, payload: unknown): AsyncIterable<unknown> {
    const body = payload as WorkerRequestPayload;
    if (!body?.requestBytes) throw new Error('stream requires requestBytes');
    if (kind === 'stt.transcribe') {
      return streamLifecycle(runtime.requireModule(), 'rac_stt_transcribe_stream_lifecycle_proto', body.requestBytes);
    }
    if (kind === 'tts.synthesize') {
      return streamLifecycle(runtime.requireModule(), 'rac_tts_synthesize_stream_lifecycle_proto', body.requestBytes);
    }
    throw new Error(`Unsupported ONNX stream kind: ${kind}`);
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
      details: { backend: 'onnx-sherpa', ownership: 'worker', diagnostics: runtime.recentDiagnostics },
    };
  },
});
