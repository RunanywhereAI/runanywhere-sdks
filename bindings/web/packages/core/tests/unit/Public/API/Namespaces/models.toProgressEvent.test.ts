import { describe, expect, it } from 'vitest';
import { DownloadState, type DownloadProgress } from '@runanywhere/proto-ts/download_service';
import {
  InferenceFramework,
  ModelCategory,
  ModelInfo,
  ModelLoadRequest,
} from '@runanywhere/proto-ts/model_types';
import { __testing__ } from '../../../../../src/Public/API/Namespaces/models';
import type { LoadOptions } from '../../../../../src/Public/API/Options';

describe('models.load options', () => {
  it('encodes context length and ordered backend preferences on ModelLoadRequest', () => {
    const options: LoadOptions = {
      contextLength: 8_192,
      forceReload: true,
      backendPreferences: [
        { backend: 'onnx' },
        { backend: 'llamaCpp' },
      ],
    };
    const resolved = __testing__.resolveLoadOptions(options);
    const request = __testing__.makeModelLoadRequest(
      'portable-model',
      ModelInfo.create({
        id: 'portable-model',
        category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      }),
      options,
      resolved,
    );
    const roundTrip = ModelLoadRequest.decode(ModelLoadRequest.encode(request).finish());

    expect(roundTrip).toMatchObject({
      modelId: 'portable-model',
      category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
      framework: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
      forceReload: true,
      validateAvailability: true,
      contextLength: 8_192,
      backendPreferences: [
        InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
        InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      ],
    });
  });

  it('folds the deprecated framework alias into backend preferences', () => {
    const resolved = __testing__.resolveLoadOptions({
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    });

    expect(resolved.backendPreferences).toEqual([{ backend: 'llamaCpp' }]);
    expect(resolved.requestedBackend).toEqual({ backend: 'llamaCpp' });
  });

  it('rejects load options the Web request cannot carry honestly', () => {
    expect(() => __testing__.validateLoadOptions({ threads: 4 })).toThrow(/threads was retired/);
    expect(() => __testing__.validateLoadOptions({
      backendPreferences: [{ backend: 'onnx', required: true }],
    })).toThrow(/required cannot be carried/);
  });
});

function progress(partial: Partial<DownloadProgress> = {}): DownloadProgress {
  return {
    modelId: 'm',
    bytesDownloaded: 0,
    totalBytes: 0,
    stageProgress: 0,
    bytesPerSecond: 0,
    state: DownloadState.DOWNLOAD_STATE_DOWNLOADING,
    retryAttempt: 0,
    taskId: 't',
    currentFileIndex: 0,
    totalFiles: 1,
    storageKey: '',
    localPath: '',
    overallProgress: 0,
    startedAtUnixMs: 0,
    updatedAtUnixMs: 0,
    currentFileName: '',
    ...partial,
  };
}

describe('toProgressEvent', () => {
  it('maps commons throughput, ETA, and overall progress onto the public event', () => {
    const event = __testing__.toProgressEvent(
      progress({
        bytesDownloaded: 4_200_000,
        totalBytes: 10_000_000,
        bytesPerSecond: 3_600_000,
        etaSeconds: 2,
        overallProgress: 0.42,
        currentFileName: 'weights.bin',
        retryAttempt: 1,
        currentFileIndex: 0,
        totalFiles: 2,
      }),
      'op-1',
      7,
    );

    expect(event).toEqual({
      type: 'progress',
      operationId: 'op-1',
      sequence: 7,
      bytesDone: 4_200_000,
      bytesTotal: 10_000_000,
      file: 'weights.bin',
      bytesPerSecond: 3_600_000,
      etaSeconds: 2,
      retryAttempt: 1,
      overallProgress: 0.42,
      currentFileIndex: 0,
      totalFiles: 2,
    });
  });

  it('leaves unknown rate, ETA, and overall progress undefined rather than zero', () => {
    const event = __testing__.toProgressEvent(
      progress({
        bytesDownloaded: 100,
        totalBytes: 0,
        bytesPerSecond: 0,
        overallProgress: 0,
      }),
      'op-2',
      1,
    );

    expect(event).toMatchObject({
      type: 'progress',
      bytesDone: 100,
      bytesTotal: 0,
      bytesPerSecond: undefined,
      etaSeconds: undefined,
      overallProgress: undefined,
    });
  });

  it('treats a negative ETA sentinel as unknown', () => {
    const event = __testing__.toProgressEvent(
      progress({ etaSeconds: -1, bytesPerSecond: 1, overallProgress: 0.1 }),
      'op-3',
      2,
    );

    expect(event).toMatchObject({
      type: 'progress',
      etaSeconds: undefined,
      bytesPerSecond: 1,
      overallProgress: 0.1,
    });
  });
});
