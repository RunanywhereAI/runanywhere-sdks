import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  InferenceFramework,
  ModelSource,
  type ModelInfo,
} from '@runanywhere/proto-ts/model_types';
import { ModelRegistry } from '../../../../../src/Public/Extensions/RunAnywhere+ModelRegistry.js';
import { models } from '../../../../../src/Public/API/Namespaces/models.js';

describe('models.register metadata', () => {
  afterEach(() => vi.restoreAllMocks());

  it('persists explicit metadata through registration and read-back', () => {
    const rows = new Map<string, ModelInfo>();
    vi.spyOn(ModelRegistry, 'registerModel').mockImplementation((model) => {
      rows.set(model.id, model);
      return true;
    });
    vi.spyOn(ModelRegistry, 'getModel').mockImplementation((id) => rows.get(id) ?? null);

    const registered = models.register({
      id: 'metadata-web',
      name: 'Metadata Web',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      url: 'https://example.invalid/metadata.gguf',
      sizeBytes: 1234,
      contextLength: 4096,
      source: ModelSource.MODEL_SOURCE_LOCAL,
      description: 'Web metadata fixture',
    });

    expect(registered).toMatchObject({
      downloadSizeBytes: 1234,
      contextLength: 4096,
      source: ModelSource.MODEL_SOURCE_LOCAL,
      description: 'Web metadata fixture',
    });
    expect(models.get('metadata-web')).toMatchObject({
      downloadSizeBytes: 1234,
      contextLength: 4096,
      source: ModelSource.MODEL_SOURCE_LOCAL,
      description: 'Web metadata fixture',
    });
  });
});
