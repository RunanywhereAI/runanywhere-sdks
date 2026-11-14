import { BackendWorkerHost } from '../../../packages/core/src/runtime/BackendWorkerHost';
import { clearAllBackendWorkerHosts } from '../../../packages/core/src/runtime/BackendWorkerHostRegistry';
import { Logging, LogLevel } from '../../../packages/core/src/Public/Extensions/RunAnywhere+Logging';
import '../../../packages/core/src/runtime/EmscriptenModule';

export async function exerciseWorkerLogging() {
  clearAllBackendWorkerHosts();
  const createHost = (backendId: 'llamacpp' | 'onnx') => new BackendWorkerHost(() => {
    const url = new URL('../fixtures/log-level-worker.ts', import.meta.url);
    url.searchParams.set('backend', backendId);
    return new Worker(url, { type: 'module' });
  }, { backendId, initTimeoutMs: 120_000 });
  const llama = createHost('llamacpp');
  const onnx = createHost('onnx');
  try {
    Logging.setLogLevel(LogLevel.LOG_LEVEL_DEBUG);
    await llama.init();
    const initial = (await llama.health()).details;
    const loading = onnx.init();
    // This message follows init in the worker queue, while WASM loads asynchronously.
    Logging.setLogLevel(LogLevel.LOG_LEVEL_ERROR);
    await loading;
    const afterInit = [(await llama.health()).details, (await onnx.health()).details];
    Logging.setLogLevel(LogLevel.LOG_LEVEL_TRACE);
    const live = [(await llama.health()).details, (await onnx.health()).details];
    llama.dispose();
    Logging.setLogLevel(LogLevel.LOG_LEVEL_WARNING);
    const recreated = createHost('llamacpp');
    await recreated.init();
    return { initial, afterInit, live, recreated: (await recreated.health()).details };
  } finally {
    clearAllBackendWorkerHosts();
  }
}

/** Uses the harness's registered real model and the production inference worker. */
export async function generateWithLogLevel(level?: LogLevel, nextLevel?: LogLevel) {
  const { RunAnywhere } = await import('../../../packages/core/src/index');
  if (level !== undefined) {
    await RunAnywhere.runtime.setAcceleration('cpu');
    Logging.setLogLevel(level);
  }
  let changedDuringStream = false;
  let text = '';
  for await (const event of RunAnywhere.llm.generateStream('Say hello in one short sentence.', {
    model: 'smollm2-360m-q8_0', maxOutputTokens: 16,
  })) {
    if (event.type === 'textDelta') {
      text += event.text;
      if (!changedDuringStream && nextLevel !== undefined) {
        Logging.setLogLevel(nextLevel);
        changedDuringStream = true;
      }
    }
    if (event.type === 'failed') throw new Error(event.error.message);
    if (event.type === 'completed') text = event.result.text || text;
  }
  return {
    text, changedDuringStream,
    executionContext: RunAnywhere.runtime.execution.context,
    acceleration: RunAnywhere.runtime.active,
  };
}
