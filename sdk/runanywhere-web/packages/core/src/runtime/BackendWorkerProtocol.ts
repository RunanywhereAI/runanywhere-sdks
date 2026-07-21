/**
 * Backend-neutral RPC protocol for inference workers.
 *
 * @internal
 *
 * Backends own the bundler-specific Worker bootstrap. Core owns this small,
 * structured-clone-safe protocol so a host and a worker bundle can evolve
 * independently. `payload` and `result` deliberately remain `unknown`: the
 * modality adapters will supply their existing proto-byte contracts during
 * the later wiring stages.
 */

/** Logical backend that owns a DedicatedWorker + WASM heap. */
export type BackendWorkerBackendId = 'llamacpp' | 'onnx';

export type BackendWorkerModality =
  | 'llm'
  | 'stt'
  | 'tts'
  | 'vlm'
  | 'vad'
  | 'embeddings';
export type BackendWorkerInferenceKind =
  | 'llm.generate'
  | 'lora.apply'
  | 'lora.remove'
  | 'tool.sessionCreate'
  | 'tool.sessionStep'
  | 'tool.sessionDestroy'
  | 'tool.sessionCancel'
  | 'structured.parse'
  | 'rag.sessionCreate'
  | 'rag.ingest'
  | 'rag.query'
  | 'rag.clear'
  | 'rag.stats'
  | 'rag.sessionDestroy'
  | 'stt.transcribe'
  | 'tts.synthesize'
  | 'vlm.generate'
  | 'vad.process'
  | 'embeddings.embed';

export interface BackendWorkerInitRequest {
  type: 'init';
  requestId: string;
  payload?: unknown;
}

export interface BackendWorkerLoadModelRequest {
  type: 'loadModel';
  requestId: string;
  modality: BackendWorkerModality;
  payload: unknown;
}

export interface BackendWorkerUnloadModelRequest {
  type: 'unloadModel';
  requestId: string;
  modality: BackendWorkerModality;
  payload?: unknown;
}

export interface BackendWorkerUnaryInferenceRequest {
  type: 'infer';
  requestId: string;
  kind: BackendWorkerInferenceKind;
  payload: unknown;
}

export interface BackendWorkerStreamInferenceRequest {
  type: 'stream';
  requestId: string;
  kind: BackendWorkerInferenceKind;
  payload: unknown;
}

export interface BackendWorkerCancelRequest {
  type: 'cancel';
  requestId: string;
  targetRequestId: string;
}

export interface BackendWorkerTeardownRequest {
  type: 'teardown';
  requestId: string;
}

export interface BackendWorkerHealthRequest {
  type: 'health';
  requestId: string;
}

export type BackendWorkerRequest =
  | BackendWorkerInitRequest
  | BackendWorkerLoadModelRequest
  | BackendWorkerUnloadModelRequest
  | BackendWorkerUnaryInferenceRequest
  | BackendWorkerStreamInferenceRequest
  | BackendWorkerCancelRequest
  | BackendWorkerTeardownRequest
  | BackendWorkerHealthRequest;

export interface BackendWorkerReadyResponse {
  type: 'ready';
  requestId: string;
}

export interface BackendWorkerResultResponse {
  type: 'result';
  requestId: string;
  result?: unknown;
}

export interface BackendWorkerStreamEventResponse {
  type: 'streamEvent';
  requestId: string;
  payload: unknown;
}

export interface BackendWorkerCompleteResponse {
  type: 'complete';
  requestId: string;
  result?: unknown;
}

export interface BackendWorkerHealthResponse {
  type: 'health';
  requestId: string;
  healthy: boolean;
  details?: unknown;
}

export interface BackendWorkerErrorResponse {
  type: 'error';
  requestId?: string;
  message: string;
}

export type BackendWorkerResponse =
  | BackendWorkerReadyResponse
  | BackendWorkerResultResponse
  | BackendWorkerStreamEventResponse
  | BackendWorkerCompleteResponse
  | BackendWorkerHealthResponse
  | BackendWorkerErrorResponse;

export interface BackendWorkerDiagnostics {
  executionContext: 'main' | 'worker';
  queueDepth: number;
}
