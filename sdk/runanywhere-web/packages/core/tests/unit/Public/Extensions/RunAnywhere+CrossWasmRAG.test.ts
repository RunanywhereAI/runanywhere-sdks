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
  RAG,
  ragCreatePipeline,
  ragDestroyPipeline,
  registerRAGProvider,
} from '../../../../src/Public/Extensions/RunAnywhere+RAG';
import { WebModelLifecycle } from '../../../../src/Public/Extensions/RunAnywhere+ModelLifecycle';
import { ModelRegistry } from '../../../../src/Public/Extensions/RunAnywhere+ModelRegistry';

afterEach(() => {
  __testing__.clearPersistentRAGStore();
  __testing__.resetFacadeState();
  vi.restoreAllMocks();
});

describe('CrossWasmRAGProvider', () => {
  it('restores an IndexedDB-compatible persistent index after provider reload', async () => {
    const { loadModel } = installBackendSpies();
    vi.spyOn(Embeddings, 'embedBatch').mockResolvedValue(
      embeddingsResult([vector([1, 0], 'Persistent Zephyr note', 0)]),
    );
    const config = createDefaultRAGConfiguration({
      embeddingModelId: 'all-minilm-l6-v2',
      llmModelId: 'lfm2-350m-q4_k_m',
      persistIndex: true,
      indexPath: 'vitest-persistent-rag',
    });

    __testing__.clearPersistentRAGStore();
    const first = __testing__.createPersistentRAGProvider();
    await first.ragCreatePipeline(config);
    await first.ragIngest('Persistent Zephyr note', JSON.stringify({
      docId: 'persistent-zephyr',
      docName: 'Persistent Zephyr',
    }));
    await first.ragDestroyPipeline();

    const reloaded = __testing__.createPersistentRAGProvider();
    await reloaded.ragCreatePipeline(config);

    await expect(reloaded.ragGetDocumentCount()).resolves.toBe(1);
    expect(reloaded.ragGetCapabilities?.()).toMatchObject({ persistent: true });
    expect(loadModel).toHaveBeenCalled();
    __testing__.clearPersistentRAGStore();
  });

  it('routes embeddings and grounded generation across independent backends', async () => {
    const { loadModel } = installBackendSpies();
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

    // Simulate an acceleration switch replacing the llama.cpp module after
    // the index was built. Query must restore the configured LLM without
    // recreating or clearing the TypeScript-owned document index.
    loadModel.mockClear();

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
    expect(loadModel).toHaveBeenCalledTimes(1);
    expect(loadModel).toHaveBeenCalledWith(expect.objectContaining({
      modelId: 'lfm2-350m-q4_k_m',
      category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
      forceReload: false,
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

  it('increments the facade pipeline identity when a provider is replaced', async () => {
    installBackendSpies();
    expect(registerRAGProvider()).toBe(true);
    const configuration = createDefaultRAGConfiguration({
      embeddingModelId: 'all-minilm-l6-v2',
      llmModelId: 'lfm2-350m-q4_k_m',
    });
    const initialGeneration = RAG.pipelineState().generation;

    try {
      await ragCreatePipeline(configuration);
      const first = RAG.pipelineState();
      expect(first.generation).toBeGreaterThan(initialGeneration);
      expect(first.configuration).toMatchObject({
        embeddingModelId: 'all-minilm-l6-v2',
        llmModelId: 'lfm2-350m-q4_k_m',
      });

      await ragCreatePipeline(configuration);
      const replacement = RAG.pipelineState();
      expect(replacement.generation).toBeGreaterThan(first.generation);
      expect(replacement.configuration).toEqual(first.configuration);
    } finally {
      await ragDestroyPipeline();
    }

    expect(RAG.pipelineState()).toMatchObject({
      generation: expect.any(Number),
      configuration: null,
    });
  });

  it('invalidates provider identity during unconditional SDK cleanup', async () => {
    installBackendSpies();
    expect(registerRAGProvider()).toBe(true);
    await ragCreatePipeline(createDefaultRAGConfiguration({
      embeddingModelId: 'all-minilm-l6-v2',
      llmModelId: 'lfm2-350m-q4_k_m',
    }));
    const created = RAG.pipelineState();

    __testing__.resetFacadeState();

    expect(RAG.availability().available).toBe(false);
    expect(RAG.pipelineState()).toEqual({
      generation: created.generation + 1,
      configuration: null,
    });
  });

  it('evicts a cached cross-WASM pipeline when a required backend disappears', async () => {
    const { supportsLLM } = installBackendSpies();
    expect(registerRAGProvider()).toBe(true);
    await ragCreatePipeline(createDefaultRAGConfiguration({
      embeddingModelId: 'all-minilm-l6-v2',
      llmModelId: 'lfm2-350m-q4_k_m',
    }));
    const created = RAG.pipelineState();

    supportsLLM.mockReturnValue(false);

    expect(RAG.availability()).toMatchObject({
      available: false,
      source: 'unavailable',
    });
    expect(RAG.pipelineState()).toEqual({
      generation: created.generation + 1,
      configuration: null,
    });
  });
});

function installBackendSpies() {
  vi.spyOn(EmbeddingsProtoAdapter, 'tryDefault').mockReturnValue({
    supportsProtoEmbeddings: () => true,
    supportsLifecycleProtoEmbeddings: () => true,
  } as unknown as EmbeddingsProtoAdapter);
  const supportsLLM = vi.spyOn(TextGeneration, 'supportsProtoLLM').mockReturnValue(true);
  vi.spyOn(ModelRegistry, 'getModel').mockReturnValue(null);
  vi.spyOn(WebModelLifecycle, 'currentModel').mockReturnValue(null);
  const loadModel = vi.spyOn(WebModelLifecycle, 'loadModelAsync').mockImplementation(
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
  return { loadModel, supportsLLM };
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
