/**
 * Public cross-encoder reranking verb.
 *
 * Model download, registration, loading, and unloading remain owned by the
 * generic model lifecycle. Unlike segmentation / diarization, the revived
 * rerank primitive publishes only the handle-scoped verb
 * `rac_rerank_component_rerank_proto` (its commons `acquire_service` is
 * owner-scoped), so this facade owns a rerank component handle and loads the
 * lifecycle-resolved model into it before scoring. Mirrors the Swift/Kotlin
 * `RunAnywhere.rerank` entry point.
 */

import { ProtoErrorCode, SDKException } from '../../Foundation/SDKException.js';
import { RerankProtoAdapter } from '../../Adapters/RerankProtoAdapter.js';
import { SDKComponent } from '@runanywhere/proto-ts/sdk_events';
import { ComponentLifecycleState } from '@runanywhere/proto-ts/component_types';
import {
  type RerankCandidate,
  type RerankOptions,
  type RerankRequest,
  type RerankResult,
  type RerankScoredItem,
} from '@runanywhere/proto-ts/rerank';
import { WebModelLifecycle } from './RunAnywhere+ModelLifecycle.js';

// Persistent component handle + its loaded model id, mirroring the module-level
// state the Swift/Kotlin `CppBridge.Rerank` actors keep. The handle is created
// lazily and reused; the model is (re)loaded only when the lifecycle-resolved
// rerank model changes.
let rerankHandle = 0;
let loadedModelID: string | null = null;

interface LoadedRerankModel {
  modelId: string;
  modelPath: string;
  modelName: string;
}

function requireInitialized(): void {
  if (!WebModelLifecycle.supportsNativeLifecycle()) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_NOT_INITIALIZED,
      'RunAnywhere.initialize() must complete before reranking can be used.',
      'Rerank',
    );
  }
}

function validateRequest(request: RerankRequest): void {
  if (!request.query) {
    throw SDKException.validationFailed({
      fieldPath: 'RerankRequest.query',
      message: 'query must be a non-empty string',
    });
  }
  if (!request.candidates || request.candidates.length === 0) {
    throw SDKException.validationFailed({
      fieldPath: 'RerankRequest.candidates',
      message: 'candidates must contain at least one item',
    });
  }
}

function requireLoadedModel(): LoadedRerankModel {
  const snapshot = WebModelLifecycle.componentLifecycleSnapshot(
    SDKComponent.SDK_COMPONENT_RERANK,
  );
  const modelId = snapshot?.modelId || snapshot?.model?.id || '';
  const modelPath = snapshot?.resolvedPath || snapshot?.model?.localPath || '';
  if (
    !snapshot
    || snapshot.state !== ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY
    || !modelId
    || !modelPath
  ) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_MODEL_NOT_LOADED,
      'No rerank model is loaded.',
      'Load a rerank model with RunAnywhere.loadModel() first.',
    );
  }
  return { modelId, modelPath, modelName: snapshot.model?.name || modelId };
}

function requireAdapter(): RerankProtoAdapter {
  const adapter = RerankProtoAdapter.tryDefault();
  if (!adapter || !adapter.supportsProtoRerank()) {
    throw SDKException.backendNotAvailable(
      'Rerank',
      'Register a Web backend built with _rac_rerank_component_rerank_proto (llama.cpp rank-pooling GGUF).',
    );
  }
  return adapter;
}

async function ensureHandle(
  adapter: RerankProtoAdapter,
  model: LoadedRerankModel,
): Promise<number> {
  if (rerankHandle !== 0 && loadedModelID === model.modelId) {
    return rerankHandle;
  }
  if (rerankHandle === 0) {
    rerankHandle = adapter.createComponent();
    if (rerankHandle === 0) {
      throw SDKException.backendNotAvailable(
        'Rerank',
        'Failed to create the native rerank component.',
      );
    }
  }
  const rc = await adapter.loadModel(
    rerankHandle,
    model.modelPath,
    model.modelId,
    model.modelName,
  );
  if (rc !== 0) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_MODEL_LOAD_FAILED,
      `Failed to load the rerank model into the component (rc=${rc}).`,
      'Rerank',
    );
  }
  loadedModelID = model.modelId;
  return rerankHandle;
}

/** Rerank candidates against a query with the lifecycle-owned rerank model. */
export async function rerank(request: RerankRequest): Promise<RerankResult> {
  requireInitialized();
  validateRequest(request);
  const model = requireLoadedModel();
  const adapter = requireAdapter();
  const handle = await ensureHandle(adapter, model);
  const result = await adapter.rerank(handle, request);
  if (!result) {
    throw SDKException.backendNotAvailable(
      'Rerank',
      'The native Web rerank operation returned no result.',
    );
  }
  return result;
}

export type {
  RerankCandidate,
  RerankOptions,
  RerankRequest,
  RerankResult,
  RerankScoredItem,
};
