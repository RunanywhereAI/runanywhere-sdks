import { afterEach, describe, expect, it, vi } from 'vitest';
import type {
  EmbeddingsResult,
  EmbeddingVector,
} from '@runanywhere/proto-ts/embeddings_options';
import type { LLMGenerationResult } from '@runanywhere/proto-ts/llm_options';
import {
  InferenceFramework,
  ModelCategory,
  type ModelLoadResult,
} from '@runanywhere/proto-ts/model_types';
import { EmbeddingsProtoAdapter } from '../../../../src/Adapters/ModalityProtoAdapter';
import { Embeddings } from '../../../../src/Public/Extensions/RunAnywhere+Embeddings';
import { TextGeneration } from '../../../../src/Public/Extensions/RunAnywhere+TextGeneration';
import {
  __testing__,
  createDefaultRAGConfiguration,
} from '../../../../src/Public/Extensions/RunAnywhere+RAG';
import { WebModelLifecycle } from '../../../../src/Public/Extensions/RunAnywhere+ModelLifecycle';
import { ModelRegistry } from '../../../../src/Public/Extensions/RunAnywhere+ModelRegistry';

afterEach(() => {
  vi.restoreAllMocks();
});

describe('CrossWasmRAGProvider', () => {
  it('routes embeddings and grounded generation across independent backends', async () => {
    installBackendSpies();
    const embedBatch = vi.spyOn(Embeddings, 'embedBatch').mockImplementation(
      async (request): Promise<EmbeddingsResult> => embeddingsResult(
        request.texts.map((text, index) => vector(
          text.includes('Zephyr') ? [1, 0] : [0, 1],
          text,
          index,
        )),
      ),
    );
    vi.spyOn(Embeddings, 'embed').mockResolvedValue(
      embeddingsResult([vector([1, 0], 'What is the Zephyr code?', 0)]),
    );
    const generate = vi.spyOn(TextGeneration, 'generate').mockResolvedValue(
      generationResult('The Zephyr launch code is ORBIT-7.'),
    );

    const provider = __testing__.createCrossWasmRAGProvider();
    await provider.ragCreatePipeline(createDefaultRAGConfiguration({
      embeddingModelId: 'all-minilm-l6-v2',
      llmModelId: 'lfm2-350m-q4_k_m',
      chunkSize: 64,
      chunkOverlap: 8,
      topK: 2,
    }));
    await provider.ragIngest(
      'Project Zephyr uses launch code ORBIT-7 and retains telemetry for 14 days.',
      JSON.stringify({ docId: 'zephyr', docName: 'Zephyr Notes' }),
    );
    await provider.ragIngest(
      'Project Maple uses green branding.',
      JSON.stringify({ docId: 'maple', docName: 'Maple Notes' }),
    );

    const result = await provider.ragQuery('What is the Zephyr launch code?', {
      retrievalTopK: 1,
      maxTokens: 64,
      disableThinking: true,
    });

    expect(embedBatch).toHaveBeenCalledTimes(2);
    expect(result.answer).toContain('ORBIT-7');
    expect(result.retrievedChunks).toHaveLength(1);
    expect(result.retrievedChunks[0]).toMatchObject({
      sourceDocument: 'Zephyr Notes',
      rank: 1,
    });
    expect(result.contextUsed).toContain('ORBIT-7');
    expect(generate).toHaveBeenCalledWith(expect.objectContaining({
      prompt: expect.stringContaining('ORBIT-7'),
      disableThinking: true,
    }));
    await expect(provider.ragListDocuments?.()).resolves.toEqual([
      { id: 'zephyr', name: 'Zephyr Notes', chunkCount: 1 },
      { id: 'maple', name: 'Maple Notes', chunkCount: 1 },
    ]);
  });

  it('supports typed document removal, clear, and statistics', async () => {
    installBackendSpies();
    vi.spyOn(Embeddings, 'embedBatch').mockImplementation(
      async (request): Promise<EmbeddingsResult> => embeddingsResult(
        request.texts.map((text, index) => vector([1, 0], text, index)),
      ),
    );

    const provider = __testing__.createCrossWasmRAGProvider();
    await provider.ragCreatePipeline(createDefaultRAGConfiguration({
      embeddingModelId: 'all-minilm-l6-v2',
      llmModelId: 'lfm2-350m-q4_k_m',
    }));
    await provider.ragIngest('A short document.', JSON.stringify({ docId: 'doc-1', docName: 'One' }));

    await expect(provider.ragGetDocumentCount()).resolves.toBe(1);
    await expect(provider.ragGetStatistics?.()).resolves.toMatchObject({
      indexedDocuments: 1,
      indexedChunks: 1,
      isPersistent: false,
      errorCode: 0,
    });
    expect(provider.ragGetCapabilities?.()).toEqual({
      native: false,
      persistent: false,
      documentListing: true,
      documentRemoval: true,
    });

    await provider.ragRemoveDocument?.('doc-1');
    await expect(provider.ragGetDocumentCount()).resolves.toBe(0);
    await provider.ragIngest('Another document.', JSON.stringify({ docId: 'doc-2' }));
    await provider.ragClearDocuments();
    await expect(provider.ragGetDocumentCount()).resolves.toBe(0);
  });
});

function installBackendSpies(): void {
  vi.spyOn(EmbeddingsProtoAdapter, 'tryDefault').mockReturnValue({
    supportsProtoEmbeddings: () => true,
  } as unknown as EmbeddingsProtoAdapter);
  vi.spyOn(TextGeneration, 'supportsProtoLLM').mockReturnValue(true);
  vi.spyOn(ModelRegistry, 'getModel').mockReturnValue(null);
  vi.spyOn(WebModelLifecycle, 'loadModelAsync').mockImplementation(
    async (request): Promise<ModelLoadResult> => ({
      success: true,
      modelId: request.modelId,
      category: request.category ?? ModelCategory.MODEL_CATEGORY_UNSPECIFIED,
      framework: request.framework ?? InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN,
      resolvedPath: `/models/${request.modelId}`,
      loadedAtUnixMs: Date.now(),
      errorMessage: '',
      warnings: [],
      alreadyLoaded: false,
      resolvedArtifacts: [],
    }),
  );
}

function vector(values: number[], text: string, inputIndex: number): EmbeddingVector {
  return {
    values,
    norm: Math.sqrt(values.reduce((sum, value) => sum + value * value, 0)),
    text,
    dimension: values.length,
    inputIndex,
    metadata: {},
  };
}

function embeddingsResult(vectors: EmbeddingVector[]): EmbeddingsResult {
  return {
    vectors,
    dimension: vectors[0]?.dimension ?? 0,
    processingTimeMs: 1,
    tokensUsed: vectors.length,
    modelId: 'all-minilm-l6-v2',
    errorMessage: undefined,
    errorCode: 0,
    requestId: 'test-embeddings',
  };
}

function generationResult(text: string): LLMGenerationResult {
  return {
    text,
    thinkingContent: undefined,
    inputTokens: 12,
    tokensGenerated: 8,
    modelUsed: 'lfm2-350m-q4_k_m',
    generationTimeMs: 2,
    ttftMs: undefined,
    tokensPerSecond: 10,
    framework: 'llamacpp',
    finishReason: 'stop',
    thinkingTokens: 0,
    responseTokens: 8,
    jsonOutput: undefined,
    performance: undefined,
    executedOn: undefined,
    structuredOutputValidation: undefined,
    totalTokens: 20,
    errorMessage: undefined,
    errorCode: 0,
    cachedPromptTokens: 0,
    promptEvalTimeMs: 1,
    decodeTimeMs: 1,
    toolCalls: [],
    toolResults: [],
  };
}
