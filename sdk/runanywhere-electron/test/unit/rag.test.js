const { test } = require('node:test');
const assert = require('node:assert/strict');

const {
  RagSession,
  createRagSessionFromCatalog,
  frameworkForModelPath,
  RagModelCategory,
  RagInferenceFramework,
} = require('../../dist/rag');
const { isSDKException, ErrorCode } = require('../../dist/errors');
const { RAGConfiguration, RAGQueryOptions, RAGResult, RAGStatistics } = require('../../dist/proto/rag');

// A fake of the low-level bridge (window.runanywhere.rag*), recording calls.
function fakeBridge() {
  const calls = [];
  const stats = { indexedDocuments: 1, indexedChunks: 3, totalTokensIndexed: 42, lastUpdatedMs: 0 };
  return {
    calls,
    ragCreateSession: async (config) => { calls.push(['create', config]); return 7; },
    ragIngest: async (h, doc) => { calls.push(['ingest', h, doc]); return stats; },
    ragQuery: async (h, q) => { calls.push(['query', h, q]); return { answer: 'Paris.', retrievedChunks: [], errorCode: 0 }; },
    ragStats: async (h) => { calls.push(['stats', h]); return stats; },
    ragClear: async (h) => { calls.push(['clear', h]); return { ...stats, indexedDocuments: 0, indexedChunks: 0 }; },
    ragDestroySession: async (h) => { calls.push(['destroy', h]); },
  };
}

function fakeCatalogBridge() {
  const calls = [];
  return {
    calls,
    downloadModel: async (id) => {
      calls.push(['download', id]);
      const primary = id === 'minilm' ? '/models/minilm.onnx' : `/models/${id}.gguf`;
      return { id, primary };
    },
    registerModel: async (id, localPath, category, framework) => {
      calls.push(['register', id, localPath, category, framework]);
    },
    ragCreateSession: async (config) => {
      calls.push(['create', config]);
      return 11;
    },
  };
}

test('RagSession.create requires an embedding model id (throws SDKException)', async () => {
  await assert.rejects(() => RagSession.create(fakeBridge(), {}), (e) => {
    assert.ok(isSDKException(e), 'must be an SDKException, not a bare Error');
    assert.equal(e.code, ErrorCode.INVALID_ARGUMENT);
    assert.match(e.message, /embeddingModelId is required/);
    return true;
  });
});

test('RagSession threads the native handle through ingest/query/close', async () => {
  const b = fakeBridge();
  const s = await RagSession.create(b, { embeddingModelId: 'minilm', llmModelId: 'qwen' });
  assert.equal(s.handle, 7);
  await s.ingest('hello world');
  await s.query('what is the capital?');
  await s.close();
  assert.deepEqual(b.calls[0], ['create', { embeddingModelId: 'minilm', llmModelId: 'qwen' }]);
  assert.deepEqual(b.calls[1], ['ingest', 7, { text: 'hello world' }]);
  assert.deepEqual(b.calls[2], ['query', 7, { question: 'what is the capital?' }]);
  assert.deepEqual(b.calls[3], ['destroy', 7]);
});

test('RagSession accepts full doc/query objects verbatim', async () => {
  const b = fakeBridge();
  const s = await RagSession.create(b, { embeddingModelId: 'minilm' });
  await s.ingest({ text: 'body', id: 'doc1', sourceUri: 'file://x' });
  await s.query({ question: 'q', generation: { maxOutputTokens: 128 }, retrievalTopK: 4 });
  assert.deepEqual(b.calls[1][2], { text: 'body', id: 'doc1', sourceUri: 'file://x' });
  assert.deepEqual(b.calls[2][2], { question: 'q', generation: { maxOutputTokens: 128 }, retrievalTopK: 4 });
});

test('RagSession.close is idempotent and blocks further use', async () => {
  const b = fakeBridge();
  const s = await RagSession.create(b, { embeddingModelId: 'minilm' });
  await s.close();
  await s.close(); // no throw, no second destroy
  assert.equal(b.calls.filter((c) => c[0] === 'destroy').length, 1);
  const closedErr = (e) => { assert.ok(isSDKException(e), 'closed-session error is an SDKException'); assert.match(e.message, /closed/); return true; };
  await assert.rejects(() => s.ingest('x'), closedErr);
  await assert.rejects(() => s.query('x'), closedErr);
});

test('ingestMany ingests in order and returns the final stats', async () => {
  const b = fakeBridge();
  const s = await RagSession.create(b, { embeddingModelId: 'minilm' });
  const stats = await s.ingestMany(['a', { text: 'b' }, 'c']);
  assert.equal(b.calls.filter((c) => c[0] === 'ingest').length, 3);
  assert.equal(stats.indexedChunks, 3);
});

// The vendored proto codec must round-trip the fields the bridge encodes/decodes.
test('vendored proto codec round-trips RAGConfiguration', () => {
  const bytes = RAGConfiguration.encode(
    RAGConfiguration.fromPartial({ embeddingModelId: 'minilm', llmModelId: 'qwen', topK: 5, similarityThreshold: 0.35 })
  ).finish();
  const back = RAGConfiguration.decode(bytes);
  assert.equal(back.embeddingModelId, 'minilm');
  assert.equal(back.llmModelId, 'qwen');
  assert.equal(back.topK, 5);
  assert.ok(Math.abs(back.similarityThreshold - 0.35) < 1e-6);
});

test('vendored proto codec round-trips RAGQueryOptions + RAGResult', () => {
  const q = RAGQueryOptions.decode(
    RAGQueryOptions.encode(
      RAGQueryOptions.fromPartial({ question: 'capital of France?', generation: { maxOutputTokens: 64 } })
    ).finish()
  );
  assert.equal(q.question, 'capital of France?');
  assert.equal(q.generation.maxOutputTokens, 64);

  const r = RAGResult.decode(
    RAGResult.encode(RAGResult.fromPartial({ answer: 'Paris.', retrievedChunks: [{ chunkId: 'c1', text: 'France…', similarityScore: 0.9 }] })).finish()
  );
  assert.equal(r.answer, 'Paris.');
  assert.equal(r.retrievedChunks[0].chunkId, 'c1');
  assert.ok(Math.abs(r.retrievedChunks[0].similarityScore - 0.9) < 1e-6);
});

test('RAGStatistics round-trips through the codec', () => {
  const s = RAGStatistics.decode(
    RAGStatistics.encode(RAGStatistics.fromPartial({ indexedDocuments: 2, indexedChunks: 9 })).finish()
  );
  assert.equal(s.indexedDocuments, 2);
  assert.equal(s.indexedChunks, 9);
});

test('frameworkForModelPath maps onnx→Onnx and gguf→LlamaCpp', () => {
  assert.equal(frameworkForModelPath('/m/minilm.onnx'), RagInferenceFramework.Onnx);
  assert.equal(frameworkForModelPath('/m/minilm.ort'), RagInferenceFramework.Onnx);
  assert.equal(frameworkForModelPath('/m/qwen.gguf'), RagInferenceFramework.LlamaCpp);
  assert.equal(frameworkForModelPath('/m/unknown.bin'), RagInferenceFramework.LlamaCpp);
});

test('createRagSessionFromCatalog downloads, registers with typed enums, then creates', async () => {
  const b = fakeCatalogBridge();
  const handle = await createRagSessionFromCatalog(b, {
    embeddingModelId: 'minilm',
    llmModelId: 'qwen2.5-0.5b',
    topK: 3,
  });
  assert.equal(handle, 11);
  assert.deepEqual(b.calls, [
    ['download', 'minilm'],
    ['register', 'minilm', '/models/minilm.onnx', RagModelCategory.Embedding, RagInferenceFramework.Onnx],
    ['download', 'qwen2.5-0.5b'],
    ['register', 'qwen2.5-0.5b', '/models/qwen2.5-0.5b.gguf', RagModelCategory.Language, RagInferenceFramework.LlamaCpp],
    ['create', { embeddingModelId: 'minilm', llmModelId: 'qwen2.5-0.5b', topK: 3 }],
  ]);
});

test('createRagSessionFromCatalog requires embeddingModelId', async () => {
  await assert.rejects(() => createRagSessionFromCatalog(fakeCatalogBridge(), {}), (e) => {
    assert.ok(isSDKException(e));
    assert.equal(e.code, ErrorCode.INVALID_ARGUMENT);
    return true;
  });
});

test('RagSession.createFromCatalog returns a live session handle', async () => {
  const catalog = fakeCatalogBridge();
  const low = fakeBridge();
  const bridge = {
    ...low,
    downloadModel: catalog.downloadModel,
    registerModel: catalog.registerModel,
    ragCreateSession: catalog.ragCreateSession,
  };
  const s = await RagSession.createFromCatalog(bridge, { embeddingModelId: 'minilm' });
  assert.equal(s.handle, 11);
  assert.ok(catalog.calls.some((c) => c[0] === 'register'));
});
