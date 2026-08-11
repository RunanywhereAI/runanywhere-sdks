/**
 * Public standalone speaker-diarization verb.
 *
 * Model download, registration, loading, and unloading remain owned by the
 * generic model lifecycle. This operation is deliberately handle-free and only
 * runs the speaker-diarization model that is already loaded. Mirrors the
 * segmentation facade and the Swift `RunAnywhere.diarize` offline entry point.
 */

import { ProtoErrorCode, SDKException } from '../../Foundation/SDKException.js';
import { DiarizationProtoAdapter } from '../../Adapters/DiarizationProtoAdapter.js';
import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import {
  type DiarizationOptions,
  type DiarizationRequest,
  type DiarizationResult,
  type DiarizationSegment,
} from '@runanywhere/proto-ts/diarization';
import { WebModelLifecycle } from './RunAnywhere+ModelLifecycle.js';

function requireInitialized(): void {
  if (!WebModelLifecycle.supportsNativeLifecycle()) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_NOT_INITIALIZED,
      'RunAnywhere.initialize() must complete before diarization can be used.',
      'Diarization',
    );
  }
}

function validateRequest(request: DiarizationRequest): void {
  if (!request.audioData || request.audioData.byteLength === 0) {
    throw SDKException.validationFailed({
      fieldPath: 'DiarizationRequest.audio_data',
      message: 'audio_data must contain at least one PCM frame',
    });
  }
}

function requireLoadedModelId(): string {
  const current = WebModelLifecycle.currentModel({
    category: ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION,
    includeModelMetadata: false,
  });
  if (!current?.found || !current.modelId) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_MODEL_NOT_LOADED,
      'No speaker-diarization model is loaded.',
      'Load a speaker-diarization model with RunAnywhere.loadModel() first.',
    );
  }
  return current.modelId;
}

function requireAdapter(): DiarizationProtoAdapter {
  const adapter = DiarizationProtoAdapter.tryDefault();
  if (!adapter || !adapter.supportsLifecycleProtoDiarization()) {
    throw SDKException.backendNotAvailable(
      'Diarization',
      'Register a Web backend built with _rac_diarization_diarize_lifecycle_proto.',
    );
  }
  return adapter;
}

function validateResult(result: DiarizationResult, loadedModelId: string): void {
  if (!Number.isInteger(result.speakerCount) || result.speakerCount < 0) {
    throw SDKException.processingFailed(
      'Diarization returned an invalid speaker count.',
    );
  }
  if (result.modelId && result.modelId !== loadedModelId) {
    throw SDKException.processingFailed(
      'Diarization result model ID does not match the lifecycle-owned model.',
    );
  }
}

/** Diarize raw audio with the lifecycle-owned speaker-diarization model. */
export async function diarize(
  request: DiarizationRequest,
): Promise<DiarizationResult> {
  requireInitialized();
  validateRequest(request);
  const loadedModelId = requireLoadedModelId();
  const result = await requireAdapter().diarizeLifecycle(request);
  if (!result) {
    throw SDKException.backendNotAvailable(
      'Diarization',
      'The native Web diarization operation returned no result.',
    );
  }
  validateResult(result, loadedModelId);
  return result;
}

export type {
  DiarizationOptions,
  DiarizationRequest,
  DiarizationResult,
  DiarizationSegment,
};
