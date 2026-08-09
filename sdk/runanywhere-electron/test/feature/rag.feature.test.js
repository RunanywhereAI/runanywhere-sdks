// F15 — RAG over the commons proto ABI, against the real addon and real models.
//
// RAG was already built the right way (rac_rag_*_proto from the start), so this
// feature is a verification rather than a migration: the thing worth proving is
// that it still works now that F2 changed how models resolve and F10 moved
// embeddings onto the lifecycle store.

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const NATIVE_PATH = process.env.RUNANYWHERE_NATIVE_PATH;
const MODELS = path.join(os.homedir(), '.runanywhere', 'models');
const EMBED_ID = 'minilm';
const LLM_ID = 'smollm2-135m';

const exists = (p) => {
  try {
    return Boolean(p) && fs.existsSync(p);
  } catch {
    return false;
  }
};

const SKIP = exists(NATIVE_PATH)
  ? exists(path.join(MODELS, EMBED_ID)) && exists(path.join(MODELS, LLM_ID, 'model.gguf'))
    ? {}
    : { skip: `models missing under ${MODELS}` }
  : { skip: 'RUNANYWHERE_NATIVE_PATH unset or file missing' };

const HF = 'https://huggingface.co';
const CATALOG = {
  [EMBED_ID]: {
    type: 'embedder',
    files: [
      { url: `${HF}/sentence-transformers/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx`, as: 'model.onnx' },
      { url: `${HF}/sentence-transformers/all-MiniLM-L6-v2/resolve/main/vocab.txt`, as: 'vocab.txt' },
    ],
    primary: 'model.onnx',
    label: 'MiniLM L6 v2',
    sizeMB: 90,
  },
  [LLM_ID]: {
    type: 'llm',
    files: [{ url: 'https://example.invalid/smollm2-135m.gguf', as: 'model.gguf' }],
    primary: 'model.gguf',
    label: 'SmolLM2 135M',
    sizeMB: 100,
  },
};

const CORPUS = [
  'RunAnywhere runs language models directly on the user device, with no server round trip.',
  'The Electron SDK loads models through a native addon that talks to a shared C++ core.',
  'Piper is a neural text to speech voice that runs through the sherpa-onnx engine.',
];

async function withSdk(run) {
  const { createRunAnywhere, NativeBackend, registerCatalog, clearCatalog } = require('../../dist');
  const { addon } = require('../../dist/bridge');

  clearCatalog();
  registerCatalog(CATALOG);
  const sdk = createRunAnywhere(new NativeBackend(addon));
  await sdk.initialize({ environment: 'production' });
  try {
    await run(sdk);
  } finally {
    await sdk.reset();
    clearCatalog();
  }
}

/** An open session over the corpus, closed on the way out. */
async function withCorpus(sdk, run) {
  const { ragDocument } = require('../../dist');
  const session = await sdk.rag.open({ id: EMBED_ID }, { id: LLM_ID }, { topK: 2 });
  try {
    await session.ingest(CORPUS.map((text) => ragDocument.text(text)));
    await run(session);
  } finally {
    await session.close();
  }
}

test('rag: open, ingest, and stats agree on what is in the index',
  { timeout: 900000, ...SKIP },
  async () => {
    await withSdk(async (sdk) => {
      await withCorpus(sdk, async (session) => {
        const stats = await session.stats();
        assert.equal(stats.documentCount, CORPUS.length, 'every document was indexed');
        assert.ok(stats.chunkCount >= CORPUS.length, 'and chunked into at least that many');
      });
    });
  }
);

test('rag: search retrieves the relevant chunk, not just any chunk',
  { timeout: 900000, ...SKIP },
  async () => {
    await withSdk(async (sdk) => {
      await withCorpus(sdk, async (session) => {
        const matches = await session.search('how does text to speech work', 2);
        assert.ok(matches.length > 0, 'search returned something');
        // The corpus is three unrelated sentences, so the retriever picking the
        // one about Piper is a real check on the embedding path rather than a
        // check that any string came back.
        assert.ok(
          matches[0].text.includes('Piper'),
          `the speech sentence ranked first: ${matches[0].text}`
        );
        for (const m of matches) assert.equal(typeof m.score, 'number', 'each match is scored');
      });
    });
  }
);

test('rag: query answers from the corpus and reports what it retrieved',
  { timeout: 900000, ...SKIP },
  async () => {
    await withSdk(async (sdk) => {
      await withCorpus(sdk, async (session) => {
        const result = await session.query('Where do the models run?', {
          maxOutputTokens: 64,
          temperature: 0,
        });
        assert.ok(result.answer.length > 0, `the model answered: ${result.answer}`);
        assert.ok(result.sources.length > 0, 'and the answer names its sources');
        // 135M is too small to assert the answer's content, but the grounding
        // is assertable: the retrieved chunk has to come from the corpus.
        assert.ok(
          CORPUS.some((doc) => doc.includes(result.sources[0].text.slice(0, 40))),
          'the top match is a chunk of an ingested document'
        );
      });
    });
  }
);

test('rag: a streamed query emits retrieval, then tokens, then a completed result',
  { timeout: 900000, ...SKIP },
  async () => {
    await withSdk(async (sdk) => {
      await withCorpus(sdk, async (session) => {
        const types = [];
        let completed = null;
        for await (const event of session.queryStream('What is RunAnywhere?', {
          maxOutputTokens: 48,
          temperature: 0,
        })) {
          types.push(event.type);
          if (event.type === 'completed') completed = event.result;
        }
        assert.ok(types.includes('retrieved'), 'retrieval is reported before generation');
        assert.equal(types[types.length - 1], 'completed', 'the stream terminates');
        assert.ok(completed, 'with a result');
        assert.ok(completed.answer.length > 0, 'that carries the answer');
      });
    });
  }
);

test('rag: clear empties the index without closing the session',
  { timeout: 900000, ...SKIP },
  async () => {
    await withSdk(async (sdk) => {
      await withCorpus(sdk, async (session) => {
        await session.clear();
        const stats = await session.stats();
        assert.equal(stats.documentCount, 0, 'the index is empty');
        // The session is still usable: re-ingesting into it has to work, which
        // is what distinguishes clear() from close().
        const { ragDocument } = require('../../dist');
        await session.ingest(ragDocument.text('A second corpus, ingested after a clear.'));
        assert.equal((await session.stats()).documentCount, 1, 'and accepts new documents');
      });
    });
  }
);

test('rag: two sessions keep their corpora separate',
  { timeout: 900000, ...SKIP },
  async () => {
    await withSdk(async (sdk) => {
      const { ragDocument } = require('../../dist');
      const first = await sdk.rag.open({ id: EMBED_ID }, undefined, { topK: 1 });
      const second = await sdk.rag.open({ id: EMBED_ID }, undefined, { topK: 1 });
      try {
        await first.ingest(ragDocument.text('Sessions each own their own index.'));
        assert.equal((await first.stats()).documentCount, 1, 'the first session indexed one');
        assert.equal((await second.stats()).documentCount, 0, 'the second stayed empty');
      } finally {
        await first.close();
        await second.close();
      }
    });
  }
);
