/**
 * RunAnywhere Web SDK - VLM Worker Entry Point
 *
 * Minimal entry point for the VLM Web Worker. This file is the bundle target
 * that gets loaded as a separate Worker thread. All logic lives in
 * VLMWorkerRuntime — this file just boots it.
 */

import { startVLMWorkerRuntime } from '../Infrastructure/VLMWorkerRuntime';

startVLMWorkerRuntime();
