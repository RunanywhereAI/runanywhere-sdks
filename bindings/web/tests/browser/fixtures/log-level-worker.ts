/** Real WASM runtimes; health exposes native state only for this browser gate. */
import { runBackendWorker, SDKLogger, type BackendWorkerScope } from '@runanywhere/web/backend';
import { WorkerLlamaRuntime } from '../../../packages/llamacpp/src/workerLlamaRuntime';
import { WorkerOnnxRuntime } from '../../../packages/onnx/src/workerOnnxRuntime';

const backend = new URL(import.meta.url).searchParams.get('backend');
const runtime = backend === 'onnx' ? new WorkerOnnxRuntime() : new WorkerLlamaRuntime();
runBackendWorker(self as unknown as BackendWorkerScope, {
  setLogLevel: (level) => runtime.setLogLevel(level),
  init: () => runtime instanceof WorkerLlamaRuntime
    ? runtime.ensureLoaded('cpu')
    : runtime.ensureLoaded({ acceleration: 'cpu' }),
  teardown: () => runtime.teardown(),
  health: () => {
    const getter = runtime.requireModule()._rac_logger_get_min_level;
    if (typeof getter !== 'function') {
      throw new Error('Build current WASM sources: rac_logger_get_min_level is required by this gate');
    }
    return { healthy: true, details: { native: getter(), javascript: SDKLogger.level } };
  },
});
