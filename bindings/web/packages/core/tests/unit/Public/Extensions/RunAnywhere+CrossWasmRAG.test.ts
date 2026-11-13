import { afterEach, describe, expect, it, vi } from 'vitest';
import type {
  EmbeddingsRequest,
  EmbeddingsResult,
  EmbeddingVector,
} from '@runanywhere/proto-ts/embeddings_options';
import type { LLMGenerationResult } from '@runanywhere/proto-ts/llm_options';
import {
  LLMGenerateRequest,
  LLMStreamEvent,
  LLMStreamEventKind,
} from '@runanywhere/proto-ts/llm_service';
import { SDKError } from '@runanywhere/proto-ts/errors';
import { type RAGStreamEvent } from '@runanywhere/proto-ts/rag';
import { FinishReason } from '@runanywhere/proto-ts/finish_reason';
import { ReasoningMode } from '@runanywhere/proto-ts/thinking_tag_pattern';
import {
  InferenceFramework,
  ModelCategory,
  type ModelLoadRequest,
  type ModelLoadResult,
} from '@runanywhere/proto-ts/model_types';
import {
  EmbeddingsProtoAdapter,
  ModalityProtoAdapter,
  type ModalityProtoModule,
} from '../../../../src/Adapters/ModalityProtoAdapter';
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
import {
  clearRunanywhereModule,
  registerWasmModule,
  type EmscriptenRunanywhereModule,
} from '../../../../src/runtime/EmscriptenModule';
import { installCurrentModelRegistryExports } from '../../helpers/CurrentModelRegistryModule';

afterEach(() => {
  __testing__.clearPersistentRAGStore();
  __testing__.resetFacadeState();
  clearRunanywhereModule();
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
    // RAGSearchResult.rank was deleted outright (idl/rag.proto) -- callers
    // reconstruct rank from array position, there is no wire-carried field.
    expect(result.retrievedChunks[0]).toMatchObject({
      sourceDocument: 'Zephyr Notes',
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

  it('ingests a 140,000-code-point document through ragIngest without RangeError (#1014)', async () => {
    // splitRAGText alone never reaches the provider's append into its chunk index,
    // which is where a spread of ~140k chunks used to throw.
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
      chunkSize: 20,
      chunkOverlap: 19,
    }));
    await provider.ragIngest('中'.repeat(140000), JSON.stringify({
      docId: 'large-document',
      docName: 'Large document',
    }));
    await expect(provider.ragGetStatistics?.()).resolves.toMatchObject({
      indexedDocuments: 1,
      indexedChunks: 139981,
    });
  });

  it('keeps the previous version of a document when a replacement ingest fails (#1129)', async () => {
    installBackendSpies();
    const embedBatch = vi.spyOn(Embeddings, 'embedBatch').mockImplementation(
      async (request: EmbeddingsRequest): Promise<EmbeddingsResult> => embeddingsResult(
        request.texts.map((text: string, index: number) => vector([1, 0], text, index)),
      ),
    );
    const provider = __testing__.createCrossWasmRAGProvider();
    await provider.ragCreatePipeline(createDefaultRAGConfiguration({
      embeddingModelId: 'all-minilm-l6-v2',
      llmModelId: 'lfm2-350m-q4_k_m',
    }));
    const metadataJson = JSON.stringify({ docId: 'doc-1', docName: 'One' });
    await provider.ragIngest('The Zephyr launch code is ORBIT-7.', metadataJson);

    // The vector count matches, so the failure lands while the replacement
    // chunks are being built -- after the old chunks used to be dropped.
    embedBatch.mockImplementationOnce(async (request: EmbeddingsRequest) => {
      const result = embeddingsResult(
        request.texts.map((text: string, index: number) => vector([1, 0], text, index)),
      );
      Object.defineProperty(result.vectors, 0, {
        get() { throw new Error('allocation failed'); },
      });
      return result;
    });
    await expect(provider.ragIngest('A replacement document.', metadataJson))
      .rejects.toThrow('allocation failed');

    await expect(provider.ragListDocuments?.()).resolves.toEqual([
      { id: 'doc-1', name: 'One', chunkCount: 1 },
    ]);
    await expect(provider.ragGetStatistics?.()).resolves.toMatchObject({
      indexedDocuments: 1,
      indexedChunks: 1,
    });
    vi.spyOn(Embeddings, 'embed').mockResolvedValue(
      embeddingsResult([vector([1, 0], 'launch code', 0)]),
    );
    const results = await provider.ragSearch?.('launch code', 1);
    expect(results?.map((result) => result.text)).toEqual([
      'The Zephyr launch code is ORBIT-7.',
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
    // RAGStatistics (idl/rag.proto) has no isPersistent field -- persistence
    // is reported by RAGProviderCapabilities.persistent, asserted below.
    await expect(provider.ragGetStatistics?.()).resolves.toMatchObject({
      indexedDocuments: 1,
      indexedChunks: 1,
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

  it('rethrows a mid-stream failure from ragQueryStream without leaking an unhandled rejection', async () => {
    const unhandled: unknown[] = [];
    const onUnhandled = (reason: unknown): void => {
      unhandled.push(reason);
    };
    process.on('unhandledRejection', onUnhandled);

    try {
      installBackendSpies();
      vi.spyOn(Embeddings, 'embedBatch').mockResolvedValue(
        embeddingsResult([vector([1, 0], 'Persistent Zephyr note', 0)]),
      );
      vi.spyOn(Embeddings, 'embed').mockResolvedValue(
        embeddingsResult([vector([1, 0], 'What is the Zephyr code?', 0)]),
      );

      const fakeModule = makeFakeLLMStreamModule(
        (_request, emit) => {
          emit(streamingTokenEvent('The launch code is '));
          emit(LLMStreamEvent.fromPartial({
            eventKind: LLMStreamEventKind.LLM_STREAM_EVENT_KIND_ERROR,
            error: SDKError.fromPartial({ cAbiCode: -42, message: 'forced mid-stream failure' }),
          }));
          return 0;
        },
      );
      ModalityProtoAdapter.registerModuleCapabilities(['llm'], fakeModule);

      const provider = __testing__.createCrossWasmRAGProvider();
      await provider.ragCreatePipeline(createDefaultRAGConfiguration({
        embeddingModelId: 'all-minilm-l6-v2',
        llmModelId: 'lfm2-350m-q4_k_m',
        chunkSize: 64,
        chunkOverlap: 8,
        topK: 2,
      }));
      await provider.ragIngest('The Zephyr launch code is ORBIT-7.');

      let streamingCancelCalled = false;
      const originalGenerateStream = TextGeneration.generateStream;
      vi.spyOn(TextGeneration, 'generateStream').mockImplementation(async (...args) => {
        const streaming = await originalGenerateStream(...args);
        const originalCancel = streaming.cancel.bind(streaming);
        streaming.cancel = () => {
          streamingCancelCalled = true;
          originalCancel();
        };
        return streaming;
      });

      const events: RAGStreamEvent[] = [];
      const consume = async (): Promise<void> => {
        for await (const event of provider.ragQueryStream('What is the Zephyr code?')) {
          events.push(event);
        }
      };

      await expect(consume()).rejects.toThrow(/forced mid-stream failure/);
      expect(events.map((event) => event.token)).toEqual(['', 'The launch code is ']);
      expect(streamingCancelCalled).toBe(false);

      // Node reports unhandled rejections once the current macrotask's
      // microtasks drain, so yield a full turn before checking.
      await new Promise((resolve) => setTimeout(resolve, 0));
    } finally {
      process.off('unhandledRejection', onUnhandled);
    }
    expect(unhandled).toEqual([]);
  });

  it('ingests whitespace-free CJK document into multiple bounded chunks for embedding (#922)', async () => {
    installBackendSpies();
    let embeddedTexts: string[] = [];
    vi.spyOn(Embeddings, 'embedBatch').mockImplementation(
      async (request: EmbeddingsRequest): Promise<EmbeddingsResult> => {
        embeddedTexts = [...request.texts];
        return embeddingsResult(
          request.texts.map((text: string, index: number) => vector([1, 0], text, index)),
        );
      },
    );

    const provider = __testing__.createCrossWasmRAGProvider();
    await provider.ragCreatePipeline(createDefaultRAGConfiguration({
      embeddingModelId: 'all-minilm-l6-v2',
      llmModelId: 'lfm2-350m-q4_k_m',
      chunkSize: 64,
      chunkOverlap: 8,
    }));

    // 500-character CJK string with zero whitespace:
    // "机器学习是人工智能的一个分支致力于通过计算方法利用经验来改善系统自身的性能" repeated
    const cjkSentence = '机器学习是人工智能的一个分支致力于通过计算方法利用经验来改善系统自身的性能';
    const longCjkDoc = cjkSentence.repeat(15); // ~555 characters, no spaces
    expect(longCjkDoc.length).toBeGreaterThan(500);
    expect(/\s/.test(longCjkDoc)).toBe(false);

    await provider.ragIngest(longCjkDoc, JSON.stringify({ docId: 'cjk-doc' }));

    // Must have split into multiple bounded chunks, not one single 555-character chunk
    expect(embeddedTexts.length).toBeGreaterThan(1);
    for (const chunkText of embeddedTexts) {
      expect([...chunkText].length).toBeLessThanOrEqual(64);
    }
    await provider.ragDestroyPipeline();
  });
});

describe('splitRAGText', () => {
  it('splits whitespace-free CJK document into multiple bounded chunks (#922)', () => {
    const cjkSentence = '机器学习是人工智能的一个分支致力于通过计算方法利用经验来改善性能';
    const doc = cjkSentence.repeat(16); // 512 characters, no spaces
    const chunkSize = 100;
    const chunkOverlap = 20;

    const chunks = __testing__.splitRAGText(doc, chunkSize, chunkOverlap);

    // Stride is 80 (100 - 20). 512 chars with stride 80 -> ~7 chunks
    expect(chunks.length).toBeGreaterThan(1);
    expect(chunks.length).toBe(7);

    // Every chunk must be bounded by chunkSize in code points
    for (let i = 0; i < chunks.length; i += 1) {
      const chunk = chunks[i]!;
      const codePointCount = [...chunk.text].length;
      expect(codePointCount).toBeLessThanOrEqual(chunkSize);
      expect(chunk.endOffset - chunk.startOffset).toBe(chunk.text.length);
      expect(doc.slice(chunk.startOffset, chunk.endOffset)).toBe(chunk.text);
      expect(chunk.tokenCount).toBe(codePointCount);
    }

    // Overlap checks between consecutive chunks
    for (let i = 0; i < chunks.length - 1; i += 1) {
      const current = chunks[i]!;
      const next = chunks[i + 1]!;
      const currentCodePoints = [...current.text];
      const nextCodePoints = [...next.text];
      const tail = currentCodePoints.slice(currentCodePoints.length - chunkOverlap).join('');
      const head = nextCodePoints.slice(0, chunkOverlap).join('');
      expect(tail).toBe(head);
    }

    // First chunk starts at 0, last chunk covers through the end
    expect(chunks[0]!.startOffset).toBe(0);
    expect(chunks[chunks.length - 1]!.endOffset).toBe(doc.length);
  });

  it('never cuts across Unicode surrogate pairs on code-point boundaries (#922)', () => {
    // 🦀 (U+1F980) and 𠮷 (U+20BB7) are 2 UTF-16 code units each
    const textWithSurrogates = '你好🦀𠮷世界'.repeat(20); // 120 code points, 160 code units
    const chunkSize = 15;
    const chunkOverlap = 3;

    const chunks = __testing__.splitRAGText(textWithSurrogates, chunkSize, chunkOverlap);

    expect(chunks.length).toBeGreaterThan(1);
    for (const chunk of chunks) {
      // Code point count bounded
      expect([...chunk.text].length).toBeLessThanOrEqual(chunkSize);
      // No unpaired / broken surrogate sequences
      const candidate = chunk.text as unknown as { isWellFormed?: () => boolean };
      if (typeof candidate.isWellFormed === 'function') {
        expect(candidate.isWellFormed()).toBe(true);
      }
      expect(textWithSurrogates.slice(chunk.startOffset, chunk.endOffset)).toBe(chunk.text);
    }
  });

  it('preserves existing behavior for whitespace-separated English words', () => {
    const text = 'The big red dog sat on the rug now';
    const chunks = __testing__.splitRAGText(text, 3, 1);

    expect(chunks.length).toBe(4);
    expect(chunks[0]!.text).toBe('The big red');
    expect(chunks[0]!.tokenCount).toBe(3);
    expect(chunks[1]!.text).toBe('red dog sat');
    expect(chunks[1]!.tokenCount).toBe(3);
    expect(chunks[2]!.text).toBe('sat on the');
    expect(chunks[3]!.text).toBe('the rug now');

    // Regression check: ordinary English words are never split mid-word at small budgets
    const englishNineWords = 'The quick brown fox jumps over the lazy dog';
    const engChunks = __testing__.splitRAGText(englishNineWords, 4, 0);
    expect(engChunks.length).toBe(3);
    expect(engChunks[0]!.text).toBe('The quick brown fox');
    expect(engChunks[1]!.text).toBe('jumps over the lazy');
    expect(engChunks[2]!.text).toBe('dog');
  });

  it('handles mixed English and whitespace-free CJK content', () => {
    const cjk = '机器学习人工智能模型训练'.repeat(10); // 120 CJK chars
    const mixed = `Header Title: ${cjk} Footer Note`;
    const chunks = __testing__.splitRAGText(mixed, 30, 5);

    expect(chunks.length).toBeGreaterThan(1);
    for (const chunk of chunks) {
      expect(chunk.tokenCount).toBeLessThanOrEqual(30);
      expect([...chunk.text].length).toBeLessThanOrEqual(50);
      expect(mixed.slice(chunk.startOffset, chunk.endOffset)).toBe(chunk.text);
    }
  });

  it('returns a single chunk when whitespace-free CJK is smaller than chunkSize', () => {
    const shortCjk = '人工智能'; // 4 chars
    const chunks = __testing__.splitRAGText(shortCjk, 10, 2);
    expect(chunks.length).toBe(1);
    expect(chunks[0]!.text).toBe('人工智能');
    expect(chunks[0]!.startOffset).toBe(0);
    expect(chunks[0]!.endOffset).toBe(4);
  });

  it('splits non-CJK runs exceeding 40 characters into bounded chunks (#922)', () => {
    // 80-character non-CJK token (Cyrillic) with chunkSize 20, overlap 0
    const token = 'Ж'.repeat(80);
    const chunks = __testing__.splitRAGText(token, 20, 0);

    expect(chunks.length).toBe(4);
    for (const chunk of chunks) {
      expect(chunk.tokenCount).toBe(20);
      expect([...chunk.text].length).toBe(20);
      expect(token.slice(chunk.startOffset, chunk.endOffset)).toBe(chunk.text);
    }
  });

  it('splits whitespace-free Thai script runs into bounded chunks (#922)', () => {
    // 80-character Thai token with chunkSize 20, overlap 0
    const thaiDoc = 'ก'.repeat(80);
    const chunks = __testing__.splitRAGText(thaiDoc, 20, 0);

    expect(chunks.length).toBe(4);
    for (const chunk of chunks) {
      expect(chunk.tokenCount).toBe(20);
      expect([...chunk.text].length).toBe(20);
      expect(thaiDoc.slice(chunk.startOffset, chunk.endOffset)).toBe(chunk.text);
    }
  });

  it('bounds retrieved CJK context and preserves whole English words in boundedRAGContext (#922)', () => {
    // English context retains full words rather than slicing characters
    const englishContext = __testing__.boundedRAGContext([{ text: 'Paris France', score: 1 }], 2);
    expect(englishContext).toBe('[Source 1: Document]\nParis France');

    const cjkText = '人工智能机器学习深度学习自然语言处理计算机视觉强化学习';
    const chunks = [
      {
        text: cjkText,
        sourceDocument: 'CJKDoc',
        score: 0.95,
      },
    ];
    // Request only 10 tokens: should slice only the first 10 CJK code points
    const context = __testing__.boundedRAGContext(chunks, 10);
    expect(context).toContain('[Source 1: CJKDoc]');
    expect(context).toContain('人工智能机器学习深度');
    expect(context).not.toContain('强化学习');
  });

  it('keeps an English word intact beside a space-free script (#922)', () => {
    const chunks = __testing__.splitRAGText('Paris人工智能', 4, 0);
    // Latin and CJK are separate budget units now, so the English word is whole in its own chunk.
    expect(chunks.map((c) => c.text)).toEqual(['Paris', '人工智能']);
    expect(__testing__.boundedRAGContext([{ text: 'Paris人工智能', score: 1 }], 2)).toBe(
      '[Source 1: Document]\nParis人',
    );
  });

  it('charges a long CJK run inside a multi-word chunk against the context budget (#922)', () => {
    const context = __testing__.boundedRAGContext([{ text: `hello ${'中'.repeat(200)}`, score: 1 }], 2);
    expect(context).toBe('[Source 1: Document]\nhello 中');
  });
});

describe('renderRAGPrompt', () => {
  it('fills both placeholder styles in a custom template', () => {
    expect(__testing__.renderRAGPrompt(
      'Q: {{query}} / {query}\nC: {{context}} / {context}',
      'the docs',
      'why?',
    )).toBe('Q: why? / why?\nC: the docs / the docs');
  });

  it('uses the default template when none is configured', () => {
    expect(__testing__.renderRAGPrompt(undefined, 'the docs', 'why?')).toBe(
      'Use the context below to answer.\n\nContext:\nthe docs\n\nQuestion: why?',
    );
  });

  it('inserts context and query verbatim when they contain $ sequences', () => {
    const context = "$$E=mc^2$$ costs $& or $' or $1";
    const query = 'is $$ special?';
    expect(__testing__.renderRAGPrompt('{context}|{query}', context, query)).toBe(
      `${context}|${query}`,
    );
  });

  it('does not substitute placeholders that appear inside context or query', () => {
    const context = 'GET /search?q={query} and {{context}}';
    const query = 'what is {context}?';
    expect(__testing__.renderRAGPrompt('{{context}}\n{query}', context, query)).toBe(
      `${context}\n${query}`,
    );
  });
});

describe('splitRAGText (#1014)', () => {
  it('preserves existing behavior for whitespace-separated English words without cutting mid-word', () => {
    const text = 'The quick brown fox jumps over the lazy dog';
    const chunks = __testing__.splitRAGText(text, 4, 0);

    expect(chunks.length).toBe(3);
    expect(chunks[0]!.text).toBe('The quick brown fox');
    expect(chunks[0]!.tokenCount).toBe(4);
    expect(chunks[1]!.text).toBe('jumps over the lazy');
    expect(chunks[1]!.tokenCount).toBe(4);
    expect(chunks[2]!.text).toBe('dog');
    expect(chunks[2]!.tokenCount).toBe(1);
  });

  it('splits 80-character runs of Thai, Cyrillic, ASCII, and supplementary-plane CJK to character budget', () => {
    const size = 20;
    const overlap = 0;

    // Thai (U+0E01)
    const thaiDoc = 'ก'.repeat(80);
    const thaiChunks = __testing__.splitRAGText(thaiDoc, size, overlap);
    expect(thaiChunks.length).toBe(4);
    for (const c of thaiChunks) {
      expect(c.text).toBe('ก'.repeat(size));
      expect([...c.text].length).toBe(size);
    }

    // Tibetan (U+0F40)
    const tibetanDoc = 'ཀ'.repeat(80);
    const tibetanChunks = __testing__.splitRAGText(tibetanDoc, size, overlap);
    expect(tibetanChunks.length).toBe(4);
    for (const c of tibetanChunks) {
      expect(c.text).toBe('ཀ'.repeat(size));
      expect([...c.text].length).toBe(size);
    }

    // Cyrillic (U+0416)
    const cyrDoc = 'Ж'.repeat(80);
    const cyrChunks = __testing__.splitRAGText(cyrDoc, size, overlap);
    expect(cyrChunks.length).toBe(4);
    for (const c of cyrChunks) {
      expect(c.text).toBe('Ж'.repeat(size));
      expect([...c.text].length).toBe(size);
    }

    // ASCII letters (> 40 chars run)
    const asciiDoc = 'a'.repeat(80);
    const asciiChunks = __testing__.splitRAGText(asciiDoc, size, overlap);
    expect(asciiChunks.length).toBe(4);
    for (const c of asciiChunks) {
      expect(c.text).toBe('a'.repeat(size));
      expect([...c.text].length).toBe(size);
    }

    // Supplementary-plane CJK (U+20000, 2 UTF-16 code units per code point)
    const supplCjk = String.fromCodePoint(0x20000).repeat(80);
    const supplChunks = __testing__.splitRAGText(supplCjk, size, overlap);
    expect(supplChunks.length).toBe(4);
    for (const c of supplChunks) {
      expect(c.text).toBe(String.fromCodePoint(0x20000).repeat(size));
      expect([...c.text].length).toBe(size);
    }
  });

  it('keeps 21-40 character spaced-script words atomic, like ordinary words', () => {
    // Only runs past 40 code points (or space-free scripts) are split; a document
    // that merely lacks whitespace does not make an ordinary word eligible.
    expect(__testing__.splitRAGText('a'.repeat(30), 20, 0).map((c) => c.text)).toEqual(['a'.repeat(30)]);
    expect(__testing__.splitRAGText('Ж'.repeat(30), 20, 0).map((c) => c.text)).toEqual(['Ж'.repeat(30)]);
  });

  it('handles 140,000-code-point document without throwing RangeError', () => {
    const largeDoc = '中'.repeat(140000);
    const chunks = __testing__.splitRAGText(largeDoc, 20, 19);
    expect(chunks.length).toBe(139981);
    expect(chunks[0]!.text).toBe('中'.repeat(20));
  });

  it('keeps a standalone ordinary word atomic whatever the document looks like', () => {
    expect(__testing__.splitRAGText('hello', 4, 0).map((c) => c.text)).toEqual(['hello']);
  });

  it('bounds chunks to the code-point budget across many short CJK runs', () => {
    const doc = `${'中'.repeat(20)}
${'中'.repeat(20)}`;
    const chunks = __testing__.splitRAGText(doc, 20, 0);
    expect(chunks.length).toBe(2);
    for (const chunk of chunks) {
      expect([...chunk.text.replace(/\s/g, '')].length).toBeLessThanOrEqual(20);
    }
  });
});

function installBackendSpies() {
  // Cross-WASM RAG ranks chunks via commons `rac_embeddings_similarity`.
  // Register a math-only WASM stub so retrieval never fabricates cosine in TS.
  registerWasmModule(['embedding'], makeEmbeddingsMathModule());
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

/**
 * Minimal WASM stub exporting commons embeddings math. Mirrors
 * `rac_embeddings_similarity` / `rac_embeddings_norm` contracts used by
 * `embeddingCosineSimilarity` after D3 moved vector math out of TypeScript.
 */
function makeEmbeddingsMathModule(): EmscriptenRunanywhereModule {
  const heap = new ArrayBuffer(64 * 1024);
  const heapU8 = new Uint8Array(heap);
  const view = new DataView(heap);
  let nextPtr = 256;

  const readF32 = (ptr: number, index: number): number =>
    view.getFloat32(ptr + index * 4, true);

  return installCurrentModelRegistryExports({
    HEAPU8: heapU8,
    _malloc(size: number): number {
      const aligned = Math.max(4, (size + 3) & ~3);
      const ptr = nextPtr;
      nextPtr += aligned;
      return ptr;
    },
    _free: () => undefined,
    getValue(ptr: number, type: string): number {
      if (type === 'float') return view.getFloat32(ptr, true);
      return view.getInt32(ptr, true);
    },
    _rac_embeddings_norm(vectorPtr: number, dimension: number, outNormPtr: number): number {
      let sumSquares = 0;
      for (let i = 0; i < dimension; i += 1) {
        const value = readF32(vectorPtr, i);
        sumSquares += value * value;
      }
      view.setFloat32(outNormPtr, Math.sqrt(sumSquares), true);
      return 0;
    },
    _rac_embeddings_similarity(
      lhsPtr: number,
      lhsDimension: number,
      rhsPtr: number,
      rhsDimension: number,
      outSimilarityPtr: number,
    ): number {
      view.setFloat32(outSimilarityPtr, 0, true);
      if (lhsDimension === 0 || lhsDimension !== rhsDimension) return 0;
      let dot = 0;
      let lhsNormSq = 0;
      let rhsNormSq = 0;
      for (let i = 0; i < lhsDimension; i += 1) {
        const lhs = readF32(lhsPtr, i);
        const rhs = readF32(rhsPtr, i);
        dot += lhs * rhs;
        lhsNormSq += lhs * lhs;
        rhsNormSq += rhs * rhs;
      }
      const denom = Math.sqrt(lhsNormSq) * Math.sqrt(rhsNormSq);
      if (denom !== 0) {
        view.setFloat32(outSimilarityPtr, dot / denom, true);
      }
      return 0;
    },
  }) as unknown as EmscriptenRunanywhereModule;
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

const PROTO_BUFFER_SIZE = 16;
const OFF_DATA = 0;
const OFF_SIZE = 4;
const OFF_STATUS = 8;
const OFF_ERROR = 12;

function streamingTokenEvent(token: string, isFinal = false): LLMStreamEvent {
  return LLMStreamEvent.fromPartial({
    token,
    eventKind: isFinal
      ? LLMStreamEventKind.LLM_STREAM_EVENT_KIND_COMPLETED
      : LLMStreamEventKind.LLM_STREAM_EVENT_KIND_TOKEN,
    finishReason: isFinal ? FinishReason.FINISH_REASON_STOP : FinishReason.FINISH_REASON_UNSPECIFIED,
  });
}

function makeFakeLLMStreamModule(
  streamHandler: (
    request: LLMGenerateRequest,
    emit: (event: LLMStreamEvent) => void,
  ) => number,
  onCancel?: () => void,
): ModalityProtoModule & EmscriptenRunanywhereModule {
  const heap = new ArrayBuffer(64 * 1024);
  const heapU8 = new Uint8Array(heap);
  const heapU32 = new Uint32Array(heap);
  const heap32 = new Int32Array(heap);
  let nextPtr = 256;

  const malloc = (size: number): number => {
    const alignedSize = Math.max(4, (size + 3) & ~3);
    const ptr = nextPtr;
    nextPtr += alignedSize;
    return ptr;
  };

  const callbackTable = new Map<number, (bytesPtr: number, size: number) => unknown>();
  let nextCallbackId = 1;

  const module: Partial<ModalityProtoModule & EmscriptenRunanywhereModule> = {
    HEAPU8: heapU8,
    HEAPU32: heapU32,
    HEAP32: heap32,
    _malloc: malloc,
    _free: () => undefined,
    addFunction(fn: (...args: number[]) => unknown, _signature: string): number {
      const id = nextCallbackId;
      nextCallbackId += 1;
      callbackTable.set(id, fn as (bytesPtr: number, size: number) => unknown);
      return id;
    },
    removeFunction(ptr: number): void {
      callbackTable.delete(ptr);
    },
    _rac_proto_buffer_init(bufferPtr: number): void {
      heapU32[(bufferPtr + OFF_DATA) >>> 2] = 0;
      heapU32[(bufferPtr + OFF_SIZE) >>> 2] = 0;
      heap32[(bufferPtr + OFF_STATUS) >>> 2] = 0;
      heapU32[(bufferPtr + OFF_ERROR) >>> 2] = 0;
    },
    _rac_proto_buffer_free: () => undefined,
    _rac_wasm_sizeof_proto_buffer: () => PROTO_BUFFER_SIZE,
    _rac_wasm_offsetof_proto_buffer_data: () => OFF_DATA,
    _rac_wasm_offsetof_proto_buffer_size: () => OFF_SIZE,
    _rac_wasm_offsetof_proto_buffer_status: () => OFF_STATUS,
    _rac_wasm_offsetof_proto_buffer_error_message: () => OFF_ERROR,
    _rac_llm_generate_proto(
      _requestPtr: number,
      _requestSize: number,
      outResult: number,
    ): number {
      heapU32[(outResult + OFF_DATA) >>> 2] = 0;
      heapU32[(outResult + OFF_SIZE) >>> 2] = 0;
      heap32[(outResult + OFF_STATUS) >>> 2] = 0;
      return 0;
    },
    _rac_llm_generate_stream_proto(
      requestPtr: number,
      requestSize: number,
      callbackPtr: number,
      _userData: number,
    ): number {
      const fn = callbackTable.get(callbackPtr);
      if (!fn) {
        throw new Error(`_rac_llm_generate_stream_proto: unknown callback id ${callbackPtr}`);
      }
      const requestBytes = heapU8.slice(requestPtr, requestPtr + requestSize);
      const request = LLMGenerateRequest.decode(requestBytes);
      const emit = (event: LLMStreamEvent): void => {
        const eventBytes = LLMStreamEvent.encode(event).finish();
        const ptr = malloc(eventBytes.byteLength);
        heapU8.set(eventBytes, ptr);
        fn(ptr, eventBytes.byteLength);
      };
      return streamHandler(request, emit);
    },
    _rac_llm_cancel_proto(outEventPtr: number): number {
      onCancel?.();
      heapU32[(outEventPtr + OFF_DATA) >>> 2] = 0;
      heapU32[(outEventPtr + OFF_SIZE) >>> 2] = 0;
      heap32[(outEventPtr + OFF_STATUS) >>> 2] = 0;
      return 0;
    },
  };
  return installCurrentModelRegistryExports(module) as
    ModalityProtoModule & EmscriptenRunanywhereModule;
}

