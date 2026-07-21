/**
 * Worker-side dispatcher for the backend-neutral inference RPC protocol.
 *
 * @internal
 */

import type {
  BackendWorkerInferenceKind,
  BackendWorkerLoadModelRequest,
  BackendWorkerModality,
  BackendWorkerRequest,
  BackendWorkerResponse,
  BackendWorkerStreamInferenceRequest,
  BackendWorkerUnloadModelRequest,
} from './BackendWorkerProtocol.js';

export interface BackendWorkerScope {
  onmessage: ((event: MessageEvent<BackendWorkerRequest>) => void) | null;
  postMessage(message: BackendWorkerResponse, transfer?: Transferable[]): void;
}

export interface BackendWorkerHandlers {
  init?(payload: unknown): Promise<void> | void;
  loadModel?(
    modality: BackendWorkerModality,
    payload: unknown,
  ): Promise<unknown> | unknown;
  unloadModel?(
    modality: BackendWorkerModality,
    payload: unknown,
  ): Promise<unknown> | unknown;
  infer?(kind: BackendWorkerInferenceKind, payload: unknown): Promise<unknown> | unknown;
  stream?(
    kind: BackendWorkerInferenceKind,
    payload: unknown,
  ): AsyncIterable<unknown> | Promise<AsyncIterable<unknown>>;
  cancel?(requestId: string): Promise<void> | void;
  teardown?(): Promise<void> | void;
  health?(): Promise<{ healthy: boolean; details?: unknown }> | { healthy: boolean; details?: unknown };
}

/**
 * Installs an RPC dispatcher into a backend's worker entrypoint.
 *
 * A worker bootstrap typically imports its Emscripten factory, supplies
 * handlers that invoke the worker-owned module, then calls this function with
 * `self`. Core intentionally contains no `new Worker(...)` or backend WASM
 * imports, so it remains bundler and backend neutral.
 */
export function runBackendWorker(scope: BackendWorkerScope, handlers: BackendWorkerHandlers): void {
  let initialized = false;
  const cancelled = new Set<string>();

  const postError = (message: string, requestId?: string): void => {
    scope.postMessage({ type: 'error', requestId, message });
  };
  const requireHandler = <T>(handler: T | undefined, operation: string): T => {
    if (!handler) throw new Error(`Backend worker does not implement ${operation}`);
    return handler;
  };
  const runUnary = async (
    request: BackendWorkerLoadModelRequest | BackendWorkerUnloadModelRequest,
  ): Promise<void> => {
    const result = request.type === 'loadModel'
      ? await requireHandler(handlers.loadModel, 'loadModel')(request.modality, request.payload)
      : await requireHandler(handlers.unloadModel, 'unloadModel')(request.modality, request.payload);
    scope.postMessage({ type: 'result', requestId: request.requestId, result });
  };
  const runStream = async (request: BackendWorkerStreamInferenceRequest): Promise<void> => {
    const stream = await requireHandler(handlers.stream, 'stream')(request.kind, request.payload);
    for await (const payload of stream) {
      if (cancelled.has(request.requestId)) break;
      scope.postMessage({ type: 'streamEvent', requestId: request.requestId, payload });
    }
    cancelled.delete(request.requestId);
    scope.postMessage({ type: 'complete', requestId: request.requestId });
  };

  scope.onmessage = (event: MessageEvent<BackendWorkerRequest>): void => {
    const request = event.data;
    void (async (): Promise<void> => {
      try {
        switch (request.type) {
          case 'init':
            await handlers.init?.(request.payload);
            initialized = true;
            scope.postMessage({ type: 'ready', requestId: request.requestId });
            return;
          case 'health': {
            const health = await handlers.health?.() ?? { healthy: initialized };
            scope.postMessage({ type: 'health', requestId: request.requestId, ...health });
            return;
          }
          case 'teardown':
            await handlers.teardown?.();
            initialized = false;
            scope.postMessage({ type: 'complete', requestId: request.requestId });
            return;
          case 'cancel':
            cancelled.add(request.targetRequestId);
            await handlers.cancel?.(request.targetRequestId);
            scope.postMessage({ type: 'complete', requestId: request.requestId });
            return;
          default:
            if (!initialized) throw new Error('Backend worker received request before init');
        }

        switch (request.type) {
          case 'loadModel':
          case 'unloadModel':
            await runUnary(request);
            return;
          case 'infer': {
            const result = await requireHandler(handlers.infer, 'infer')(request.kind, request.payload);
            scope.postMessage({ type: 'result', requestId: request.requestId, result });
            return;
          }
          case 'stream':
            await runStream(request);
            return;
        }
      } catch (error) {
        postError(error instanceof Error ? error.message : String(error), request.requestId);
      }
    })();
  };
}
