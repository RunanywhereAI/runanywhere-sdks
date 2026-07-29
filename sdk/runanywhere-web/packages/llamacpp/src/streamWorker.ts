/**
 * LlamaCPP stream-worker entrypoint.
 *
 * Instantiates a mirror of the llamacpp WASM module inside a dedicated
 * Worker so streaming generation does not block the UI thread. The main
 * thread keeps its own module for load/unload; this worker owns the
 * streaming exports only (T6.1 DECISION-3).
 */

import {
  registerStreamModuleFactory,
  runStreamWorker,
  type StreamWorkerModule,
  type StreamWorkerScope,
} from '@runanywhere/web/backend';
import {
  LLAMACPP_STREAM_WORKER_FACTORY_ID,
  LLAMACPP_STREAM_WORKER_WEBGPU_FACTORY_ID,
} from './streamWorkerFactoryId.js';

type CreateModuleFn = (config: {
  wasmBinary?: ArrayBuffer;
  locateFile?: (path: string) => string;
  print?: (text: string) => void;
  printErr?: (text: string) => void;
}) => Promise<StreamWorkerModule>;

async function instantiate(
  wasmBytes: ArrayBuffer,
  glueName: string,
): Promise<StreamWorkerModule> {
  const glueUrl = new URL(`../wasm/${glueName}`, import.meta.url).href;
  const glue = (await import(/* @vite-ignore */ glueUrl)) as { default: CreateModuleFn };
  const baseUrl = glueUrl.substring(0, glueUrl.lastIndexOf('/') + 1);
  return glue.default({
    wasmBinary: wasmBytes,
    locateFile: (path) => baseUrl + path,
  });
}

registerStreamModuleFactory(
  LLAMACPP_STREAM_WORKER_FACTORY_ID,
  (wasmBytes) => instantiate(wasmBytes, 'racommons-llamacpp.js'),
);
registerStreamModuleFactory(
  LLAMACPP_STREAM_WORKER_WEBGPU_FACTORY_ID,
  (wasmBytes) => instantiate(wasmBytes, 'racommons-llamacpp-webgpu.js'),
);

runStreamWorker(self as unknown as StreamWorkerScope);
