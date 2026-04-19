/**
 * RunAnywhere Web SDK - VLM Worker Entry Point (JS proxy)
 *
 * This file exists so that bundlers (Vite, Rollup, Webpack) can resolve the
 * worker URL referenced in VLMWorkerBridge.ts via:
 *   new URL('../workers/vlm-worker.js', import.meta.url)
 *
 * It simply re-exports from the TypeScript source so the bundler compiles
 * and emits the worker as a proper JS module chunk.
 */
export { } from './vlm-worker.ts';

import { startVLMWorkerRuntime } from '../Infrastructure/VLMWorkerRuntime';
startVLMWorkerRuntime();
