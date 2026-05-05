/**
 * RunAnywhere Web SDK - VLM Worker Entry Point
 *
 * Minimal worker entry — compiled by tsc into `dist/workers/vlm-worker.js`,
 * which is what `package.json#exports["./vlm-worker"]` points at. All
 * worker-side logic lives in `VLMWorkerRuntime` so this file can stay tiny.
 */
import { startVLMWorkerRuntime } from '../Infrastructure/VLMWorkerRuntime';

startVLMWorkerRuntime();
