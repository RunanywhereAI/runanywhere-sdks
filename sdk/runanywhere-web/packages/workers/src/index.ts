// RunAnywhere Web Workers Package
// Provides Web Worker implementations for performance optimization

// Manager exports
export { WorkerManager } from './managers/worker-manager';
export type {
  WorkerManagerConfig,
  WorkerManagerEvents
} from './managers/worker-manager';

// Audio Worker types
export type {
  WorkerMessage,
  InitializeMessage,
  ProcessAudioMessage,
  DestroyMessage,
  WorkerResponse,
  InitializedResponse,
  VADResultResponse,
  TranscriptionResponse,
  ErrorResponse
} from './workers/audio-processor.worker';

// LLM Worker types
export type {
  LLMWorkerMessage,
  LLMInitializeMessage,
  LLMProcessMessage,
  LLMDestroyMessage,
  LLMWorkerResponse,
  LLMInitializedResponse,
  LLMTextResponse,
  LLMStreamResponse,
  LLMErrorResponse
} from './workers/llm-processor.worker';

// Worker detection utility
export function supportsWebWorkers(): boolean {
  return typeof Worker !== 'undefined';
}

// Worker availability check
export function checkWorkerSupport(): {
  workers: boolean;
  sharedArrayBuffer: boolean;
  offscreenCanvas: boolean;
} {
  return {
    workers: typeof Worker !== 'undefined',
    sharedArrayBuffer: typeof SharedArrayBuffer !== 'undefined',
    offscreenCanvas: typeof OffscreenCanvas !== 'undefined'
  };
}
