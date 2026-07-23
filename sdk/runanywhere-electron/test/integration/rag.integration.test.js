const { test } = require('node:test');
const assert = require('node:assert/strict');
const os = require('os');
const path = require('path');

// ---------------------------------------------------------------------------
// Integration test: RAG against the REAL native addon + REAL models. Exercises
// the full cross-ABI path that the unit tests (fake bridge) cannot:
//   proto encode -> addon.registerModel + rac_rag_*_proto (C ABI) ->
//   commons registry id-resolution + embedding + LLM -> proto decode.
//
// Skips gracefully when the native addon isn't present (bridge.ts resolves the
// .node eagerly at require() time, so a require failure means "no addon"). Opt
// in by pointing RUNANYWHERE_NATIVE_PATH at a built runanywhere_native.node.
// ---------------------------------------------------------------------------

let addon = null;
let resolveModel = null;
let proto = null;
let loadError = null;
try {
  ({ addon } = require('../../dist/bridge'));
  ({ resolveModel } = require('../../dist/download'));
  proto = require('../../dist/proto/rag');
} catch (e) {
  loadError = e;
}

// RAG bindings only exist on a freshly-built addon; guard on the method too so an
// older .node without RAG skips instead of throwing.
const ENABLED = addon != null && typeof addon.ragCreateSession === 'function' && typeof addon.registerModel === 'function';

const EMBED = process.env.RUNANYWHERE_EMBED || 'minilm';
const LLM = process.env.RUNANYWHERE_LLM || 'qwen2.5-0.5b';

// rac model-registry enums: category EMBEDDING=7 / LANGUAGE=0, framework ONNX=0 / LLAMACPP=1.
const DOC =
  'The Zephyr Protocol was ratified in 2019. It requires all member stations to rotate ' +
  'their encryption keys every 90 days and to store backups in the Helios vault in Reykjavik.';

const enc = (Msg, obj) => Msg.encode(Msg.fromPartial(obj)).finish();

let session = null;
let setupError = null;

test('setup: initialize, download models, register, create RAG session', { timeout: 300000 }, async (t) => {
  if (!ENABLED) {
    t.skip(`RAG native addon unavailable (${loadError ? loadError.message : 'no ragCreateSession export'})`);
    return;
  }
  try {
    const base = path.join(os.tmpdir(), 'runanywhere-rag-it');
    addon.initialize(path.join(base, 'secure'), base);
    const em = await resolveModel(EMBED);
    const lm = await resolveModel(LLM);
    addon.registerModel(EMBED, em.primary, 7, 0);
    addon.registerModel(LLM, lm.primary, 0, 1);
    const cfg = enc(proto.RAGConfiguration, {
      embeddingModelId: EMBED, llmModelId: LLM, topK: 3, chunkSize: 512, chunkOverlap: 64, maxContextTokens: 1024,
    });
    session = addon.ragCreateSession(cfg);
    assert.equal(typeof session, 'number');
  } catch (e) {
    setupError = e;
    throw e;
  }
});

test('ingest returns index statistics', { timeout: 120000 }, async (t) => {
  if (!ENABLED || session == null) { t.skip(setupError ? setupError.message : 'no session'); return; }
  const statsBytes = await addon.ragIngest(session, enc(proto.RAGDocument, { text: DOC, id: 'zephyr' }));
  const stats = proto.RAGStatistics.decode(statsBytes);
  assert.ok(stats.indexedChunks > 0, 'at least one chunk indexed');
  assert.ok(stats.indexedDocuments >= 1, 'document counted');
});

test('query returns a grounded answer + supporting chunks', { timeout: 180000 }, async (t) => {
  if (!ENABLED || session == null) { t.skip(setupError ? setupError.message : 'no session'); return; }
  const q = enc(proto.RAGQueryOptions, { question: 'How often must member stations rotate their encryption keys?', maxTokens: 96 });
  const res = proto.RAGResult.decode(await addon.ragQuery(session, q));
  assert.ok(res.retrievedChunks.length > 0, 'retrieved supporting chunks');
  assert.match(res.contextUsed, /90/, 'retrieved context carries the grounding fact');
  assert.match(res.answer, /90|ninety|day/i, 'answer is grounded in the retrieved context');
});

test('stats reflect the ingested document, then clear empties the index', { timeout: 60000 }, async (t) => {
  if (!ENABLED || session == null) { t.skip(setupError ? setupError.message : 'no session'); return; }
  const before = proto.RAGStatistics.decode(await Promise.resolve(addon.ragStats(session)));
  assert.ok(before.indexedChunks > 0);
  const after = proto.RAGStatistics.decode(await Promise.resolve(addon.ragClear(session)));
  assert.equal(after.indexedChunks, 0, 'clear drops all chunks');
});

test('teardown: destroy the RAG session', () => {
  if (!ENABLED || session == null) return;
  addon.ragDestroySession(session);
  session = null;
});
