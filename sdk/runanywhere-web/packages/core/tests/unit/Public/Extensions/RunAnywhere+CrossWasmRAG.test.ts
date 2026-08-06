import { afterEach, describe, expect, it, vi } from 'vitest';
import type {
  EmbeddingsRequest,
  EmbeddingsResult,
  EmbeddingVector,
} from '@runanywhere/proto-ts/embeddings_options';
import { FinishReason, type LLMGenerationResult } from '@runanywhere/proto-ts/llm_options';
import { ReasoningMode } from '@runanywhere/proto-ts/thinking_tag_pattern';
import {
  InferenceFramework,
  ModelCategory,
  type ModelLoadRequest,
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
    // `persistIndex`/`indexPath` were deleted outright from RAGConfiguration
    // -- the RAG index is in-memory only on the wire now. PersistentRAGProvider
    // derives its own Web-only IndexedDB storage key from embedding/LLM model
    // ids instead (see RunAnywhere+RAG.ts's `ragCreatePipeline()`).
    const config = createDefaultRAGConfiguration({
      embeddingModelId: 'all-minilm-l6-v2',
      llmModelId: 'lfm2-350m-q4_k_m',
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
      async (request: EmbeddingsRequest): Promise<EmbeddingsResult> => embeddingsResult(
        request.texts.map((text: string, index: number) => vector(
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
      // The flat `retrievalTopK` knob was collapsed onto nested
      // `RAGRetrievalOptions.topK` (idl/rag.proto realignment).
      retrieval: { topK: 1, enableMultiQuery: false },
      generation: {
        maxOutputTokens: 64,
        reasoning: {
          mode: ReasoningMode.REASONING_MODE_OFF,
          includeInOutput: false,
        },
        // LLMGenerationOptions has no optional presence for these four --
        // every explicit `generation` override must supply them.
        stopSequences: [],
        preferredFramework: InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN,
        repeatLastN: 0,
        echoPrompt: false,
      },
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
      maxOutputTokens: 64,
      reasoning: expect.objectContaining({
        mode: ReasoningMode.REASONING_MODE_OFF,
      }),
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
      async (request: EmbeddingsRequest): Promise<EmbeddingsResult> => embeddingsResult(
        request.texts.map((text: string, index: number) => vector([1, 0], text, index)),
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

  it('composes RAG when embedding and LLM ownership span different BackendWorkers', async () => {
    installBackendSpies();
    const { markModelOwnedByBackendWorker, clearModelOwnedByBackendWorker } = await import(
      '../../../../src/runtime/BackendWorkerModelOwnership'
    );
    markModelOwnedByBackendWorker('all-minilm-l6-v2', 'onnx');
    markModelOwnedByBackendWorker('lfm2-350m-q4_k_m', 'llamacpp');

    const plan = __testing__.resolveRagExecutionPlan(createDefaultRAGConfiguration({
      embeddingModelId: 'all-minilm-l6-v2',
      llmModelId: 'lfm2-350m-q4_k_m',
    }));
    expect(plan.mode).toBe('composed');

    const nativeCreate = vi.fn(async () => {
      throw new Error('rac_rag_session_create_proto failed with code -110');
    });
    RAG.setProvider({
      providerKind: 'wasm-session',
      async ragCreatePipeline() {
        await nativeCreate();
      },
      async ragDestroyPipeline() {},
      async ragIngest() {},
      async ragQuery() {
        return { answer: '', retrievedChunks: [] } as never;
      },
      async ragClearDocuments() {},
      async ragGetDocumentCount() {
        return 0;
      },
    });

    try {
      await ragCreatePipeline(createDefaultRAGConfiguration({
        embeddingModelId: 'all-minilm-l6-v2',
        llmModelId: 'lfm2-350m-q4_k_m',
      }));

      expect(nativeCreate).not.toHaveBeenCalled();
      expect(RAG.availability()).toMatchObject({
        available: true,
        source: 'cross-wasm',
      });
      await ragDestroyPipeline();
    } finally {
      clearModelOwnedByBackendWorker('all-minilm-l6-v2', 'onnx');
      clearModelOwnedByBackendWorker('lfm2-350m-q4_k_m', 'llamacpp');
    }
  });

  it('keeps native RAG when every artifact is co-located with the RAG ABI host', async () => {
    installBackendSpies();
    const { markModelOwnedByBackendWorker, clearModelOwnedByBackendWorker } = await import(
      '../../../../src/runtime/BackendWorkerModelOwnership'
    );
    markModelOwnedByBackendWorker('all-minilm-l6-v2', 'onnx');
    // Embed-only / same-host LLM: both on onnx worker → native is viable.
    markModelOwnedByBackendWorker('onnx-local-llm', 'onnx');

    try {
      expect(__testing__.resolveRagExecutionPlan(createDefaultRAGConfiguration({
        embeddingModelId: 'all-minilm-l6-v2',
        llmModelId: 'onnx-local-llm',
      })).mode).toBe('native');

      expect(__testing__.resolveRagExecutionPlan(createDefaultRAGConfiguration({
        embeddingModelId: 'all-minilm-l6-v2',
        llmModelId: '',
      })).mode).toBe('native');
    } finally {
      clearModelOwnedByBackendWorker('all-minilm-l6-v2', 'onnx');
      clearModelOwnedByBackendWorker('onnx-local-llm', 'onnx');
    }
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
    async (request: ModelLoadRequest): Promise<ModelLoadResult> => ({
      // `ModelLoadResult.success` was deleted outright -- an absent `error`
      // is the sole success signal now.
      modelId: request.modelId,
      category: request.category ?? ModelCategory.MODEL_CATEGORY_UNSPECIFIED,
      framework: request.framework ?? InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN,
      resolvedPath: `/models/${request.modelId}`,
      loadedAtUnixMs: Date.now(),
      warnings: [],
      alreadyLoaded: false,
      resolvedArtifacts: [],
    }),
  );
  return { loadModel, supportsLLM };
}

// `EmbeddingVector.norm`/`.dimension` and `.text` were deleted outright
// (idl/embeddings_options.proto): dimension lives solely on the enclosing
// EmbeddingsResult now, and only `values`/`inputIndex` remain per-vector.
// `text` is dropped from this test helper's signature too since nothing on
// the wire carries it back.
function vector(values: number[], _text: string, inputIndex: number): EmbeddingVector {
  return { values, inputIndex };
}

// `EmbeddingsResult.errorMessage`/`.errorCode` were deleted outright.
function embeddingsResult(vectors: EmbeddingVector[]): EmbeddingsResult {
  return {
    vectors,
    dimension: vectors[0]?.values.length ?? 0,
    processingTimeMs: 1,
    tokensUsed: vectors.length,
    modelId: 'all-minilm-l6-v2',
    requestId: 'test-embeddings',
  };
}

// `LLMGenerationResult.finishReason` is the `FinishReason` enum now, not a
// bare string; `tokensPerSecond`/`inputTokens`/`totalTokens`/`errorMessage`/
// `errorCode` were all deleted outright (TokenUsage on `usage` is the
// canonical replacement, unused by this in-memory RAG test double).
function generationResult(text: string): LLMGenerationResult {
  return {
    text,
    thinkingContent: undefined,
    modelUsed: 'lfm2-350m-q4_k_m',
    generationTimeMs: 2,
    framework: 'llamacpp',
    finishReason: FinishReason.FINISH_REASON_STOP,
    thinkingTokens: 0,
    responseTokens: 8,
    jsonOutput: undefined,
    performance: undefined,
    executedOn: undefined,
    structuredOutputValidation: undefined,
    cachedPromptTokens: 0,
    promptEvalTimeMs: 1,
    decodeTimeMs: 1,
    toolCalls: [],
    toolResults: [],
  };
}
