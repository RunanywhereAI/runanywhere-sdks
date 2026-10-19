import { afterEach, describe, expect, it } from 'vitest';
import { DownloadState, type DownloadProgress } from '@runanywhere/proto-ts/download_service';
import { ModelCategory, InferenceFramework } from '@runanywhere/proto-ts/model_types';
import { __testing__ } from '../../../../../src/Public/API/Namespaces/models';
import { setRuntimeDegradedReason } from '../../../../../src/Foundation/RuntimeConfig.js';

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

describe('toLoadedModel fallbackReason', () => {
  afterEach(() => {
    setRuntimeDegradedReason(null);
  });

  const dummyResolved = {
    requestedBackend: { backend: 'onnx' as const },
  };

  it('surfaces native fallbackReason on LoadedModel', () => {
    const loaded = __testing__.toLoadedModel(
      'model-1',
      ModelCategory.MODEL_CATEGORY_LLM,
      dummyResolved,
      InferenceFramework.INFERENCE_FRAMEWORK_LLAMACPP,
      {
        modelId: 'model-1',
        category: ModelCategory.MODEL_CATEGORY_LLM,
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMACPP,
        resolvedPath: '/models/model-1.gguf',
        loadedAtUnixMs: 1234567890n,
        warnings: [],
        alreadyLoaded: false,
        resolvedArtifacts: [],
        fallbackReason: 'ONNX WebGPU not available; fell back to llama.cpp',
      },
    );

    expect(loaded.fallbackReason).toBe('ONNX WebGPU not available; fell back to llama.cpp');
  });

  it('falls back to warnings[0] when fallbackReason is absent', () => {
    const loaded = __testing__.toLoadedModel(
      'model-2',
      ModelCategory.MODEL_CATEGORY_LLM,
      dummyResolved,
      InferenceFramework.INFERENCE_FRAMEWORK_LLAMACPP,
      {
        modelId: 'model-2',
        category: ModelCategory.MODEL_CATEGORY_LLM,
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMACPP,
        resolvedPath: '/models/model-2.gguf',
        loadedAtUnixMs: 1234567890n,
        warnings: ['Skipped onnx backend preference because wasm not registered'],
        alreadyLoaded: false,
        resolvedArtifacts: [],
      },
    );

    expect(loaded.fallbackReason).toBe(
      'Skipped onnx backend preference because wasm not registered',
    );
  });

  it('asserts the native fallbackReason wins over Runtime.degradedReason', () => {
    setRuntimeDegradedReason('Global runtime WebGPU context lost');

    const loaded = __testing__.toLoadedModel(
      'model-3',
      ModelCategory.MODEL_CATEGORY_LLM,
      dummyResolved,
      InferenceFramework.INFERENCE_FRAMEWORK_LLAMACPP,
      {
        modelId: 'model-3',
        category: ModelCategory.MODEL_CATEGORY_LLM,
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMACPP,
        resolvedPath: '/models/model-3.gguf',
        loadedAtUnixMs: 1234567890n,
        warnings: ['Warning: backend preference skipped'],
        alreadyLoaded: false,
        resolvedArtifacts: [],
        fallbackReason: 'Specific load fallback reason',
      },
    );

    expect(loaded.fallbackReason).toBe('Specific load fallback reason');
  });

  it('asserts native warnings[0] wins over Runtime.degradedReason when fallbackReason is unset', () => {
    setRuntimeDegradedReason('Global runtime WebGPU context lost');

    const loaded = __testing__.toLoadedModel(
      'model-4',
      ModelCategory.MODEL_CATEGORY_LLM,
      dummyResolved,
      InferenceFramework.INFERENCE_FRAMEWORK_LLAMACPP,
      {
        modelId: 'model-4',
        category: ModelCategory.MODEL_CATEGORY_LLM,
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMACPP,
        resolvedPath: '/models/model-4.gguf',
        loadedAtUnixMs: 1234567890n,
        warnings: ['Warning: backend preference skipped'],
        alreadyLoaded: false,
        resolvedArtifacts: [],
      },
    );

    expect(loaded.fallbackReason).toBe('Warning: backend preference skipped');
  });

  it('falls back to Runtime.degradedReason when native result has no fallbackReason or warnings', () => {
    setRuntimeDegradedReason('Global runtime WebGPU context lost');

    const loaded = __testing__.toLoadedModel(
      'model-5',
      ModelCategory.MODEL_CATEGORY_LLM,
      dummyResolved,
      InferenceFramework.INFERENCE_FRAMEWORK_LLAMACPP,
      {
        modelId: 'model-5',
        category: ModelCategory.MODEL_CATEGORY_LLM,
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMACPP,
        resolvedPath: '/models/model-5.gguf',
        loadedAtUnixMs: 1234567890n,
        warnings: [],
        alreadyLoaded: false,
        resolvedArtifacts: [],
      },
    );

    expect(loaded.fallbackReason).toBe('Global runtime WebGPU context lost');
  });

  it('leaves fallbackReason undefined when neither native nor runtime degraded reason is present', () => {
    const loaded = __testing__.toLoadedModel(
      'model-6',
      ModelCategory.MODEL_CATEGORY_LLM,
      dummyResolved,
      InferenceFramework.INFERENCE_FRAMEWORK_LLAMACPP,
      {
        modelId: 'model-6',
        category: ModelCategory.MODEL_CATEGORY_LLM,
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMACPP,
        resolvedPath: '/models/model-6.gguf',
        loadedAtUnixMs: 1234567890n,
        warnings: [],
        alreadyLoaded: false,
        resolvedArtifacts: [],
      },
    );

    expect(loaded.fallbackReason).toBeUndefined();
  });
});

