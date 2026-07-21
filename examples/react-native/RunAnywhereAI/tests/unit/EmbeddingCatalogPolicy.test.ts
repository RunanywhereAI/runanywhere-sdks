import { InferenceFramework } from '@runanywhere/proto-ts/model_types';
import {
  PORTABLE_NVIDIA_EMBEDDING_MODELS,
  RAG_EMBEDDING_FRAMEWORKS,
} from '../../src/services/EmbeddingCatalogPolicy';

describe('portable NVIDIA embedding catalog policy', () => {
  it('keeps both validated GGUF artifacts pinned with exact sizes', () => {
    expect(PORTABLE_NVIDIA_EMBEDDING_MODELS).toEqual([
      expect.objectContaining({
        id: 'nemotron-3-embed-1b-q4_k_m',
        url: expect.stringContaining(
          '/resolve/06df1fde6f7009c91f6cc3cd520081921929a678/'
        ),
        memoryRequirement: 749_352_096,
      }),
      expect.objectContaining({
        id: 'llama-nemotron-embed-1b-v2-q4_k_m',
        url: expect.stringContaining(
          '/resolve/bf7c9832b1d76f86777379e58b7b74805ee58006/'
        ),
        memoryRequirement: 807_690_624,
      }),
      expect.objectContaining({
        id: 'llama-embed-nemotron-8b-q4_k_m',
        url: expect.stringContaining(
          '/resolve/e7ae3cbae4f7693bbd75ec959bf293f39e1f2e25/'
        ),
        memoryRequirement: 4_625_233_184,
      }),
    ]);
  });

  it('allows llama.cpp embeddings in the RAG picker', () => {
    expect([...RAG_EMBEDDING_FRAMEWORKS]).toEqual([
      InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
      InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
    ]);
  });
});
