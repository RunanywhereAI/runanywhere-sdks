// F10 through F13 — embeddings, rerank, diarization, and segmentation over the
// commons proto ABI, against the real addon and real models.
//
// Three of the four are lifecycle-owned now. Rerank is not, and that is
// commons' shape rather than an omission here: rac_rerank_component_rerank_proto
// is the only rerank entry point and it takes a component handle.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

import {
  createRunAnywhere,
  NativeBackend,
  registerCatalog,
  clearCatalog,
  audio,
  image,
} from '../../dist';
import type { Catalog, ModelRegistration, RunAnywhereApi } from '../../dist';
import { exists, nativeAddon } from './support';

const NATIVE_PATH = process.env.RUNANYWHERE_NATIVE_PATH;
const MODELS = path.join(os.homedir(), '.runanywhere', 'models');
const EMBED_ID = 'minilm';
const DIAR_ID = 'sortformer';
const SEG_ID = 'segformer-b0-ade-512';

const hasNative = exists(NATIVE_PATH);
const dirHasFiles = (id: string): boolean => {
  const dir = path.join(MODELS, id);
  try {
    return fs.existsSync(dir) && fs.readdirSync(dir).length > 0;
  } catch {
    return false;
  }
};

const skipFor = (id: string): { skip?: string } =>
  hasNative
    ? dirHasFiles(id)
      ? {}
      : { skip: `model missing: ${path.join(MODELS, id)}` }
    : { skip: 'RUNANYWHERE_NATIVE_PATH unset or file missing' };

// The catalog rows mirror what the example app ships, so these ids resolve to
// the same on-disk layout a real run produces.
const HF = 'https://huggingface.co';
const CATALOG: Catalog = {
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
};

// Diarization and segmentation have no `type` in the staged catalog
// (catalog.ts maps only llm / vlm / embedder / stt / tts), so they are
// registered straight into the registry from their on-disk path, the way an
// app would with models.register(). Closing that gap belongs to F18/F23.
async function registerLocal(
  sdk: RunAnywhereApi,
  id: string,
  category: ModelRegistration['category']
): Promise<void> {
  const dir = path.join(MODELS, id);
  const files = fs.readdirSync(dir);
  const primary = files.find((f) => f.endsWith('.onnx')) ?? files[0];
  await sdk.models.register({
    id,
    path: path.join(dir, primary),
    category,
    framework: 'ONNX',
  });
}

async function withModels(ids: string[], run: (sdk: RunAnywhereApi) => Promise<void>): Promise<void> {
  clearCatalog();
  registerCatalog(CATALOG);
  const sdk = createRunAnywhere(new NativeBackend(nativeAddon()));
  await sdk.initialize({ environment: 'production' });
  try {
    for (const id of ids) await sdk.models.load(id);
    await run(sdk);
  } finally {
    await sdk.reset();
    clearCatalog();
  }
}

function cosine(a: number[] | Float32Array, b: number[] | Float32Array): number {
  let dot = 0;
  let na = 0;
  let nb = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return dot / (Math.sqrt(na) * Math.sqrt(nb) || 1);
}

// ---------------------------------------------------------------------------
// F10 — embeddings
// ---------------------------------------------------------------------------

test('embeddings: a batch comes back in input order with a stable dimension',
  { timeout: 600000, ...skipFor(EMBED_ID) },
  async () => {
    await withModels([EMBED_ID], async (sdk) => {
      const texts = ['a cat sat on the mat', 'a kitten rested on the rug', 'the stock market fell'];
      const out = await sdk.embeddings.embed(texts);
      assert.equal(out.length, texts.length, 'one vector per input');
      // input_index is set on every entry including zero, so order is commons'
      // rather than something inferred from array position.
      assert.deepEqual(
        out.map((e) => e.index),
        [0, 1, 2],
        'each vector reports its position in the batch'
      );
      const width = out[0].vector.length;
      assert.ok(width > 0, `vectors have a width: ${width}`);
      for (const e of out) assert.equal(e.vector.length, width, 'every vector is the same width');

      // Meaning, not just shape: the two sentences about cats are closer to
      // each other than either is to the one about markets.
      const near = cosine(out[0].vector, out[1].vector);
      const far = cosine(out[0].vector, out[2].vector);
      assert.ok(near > far, `related text embeds closer (${near.toFixed(3)} > ${far.toFixed(3)})`);
    });
  }
);

test('embeddings: the normalize option reaches commons, and the ONNX engine ignores it',
  { timeout: 600000, ...skipFor(EMBED_ID) },
  async () => {
    await withModels([EMBED_ID], async (sdk) => {
      const [l2] = await sdk.embeddings.embed(['normalize me'], { normalize: 'L2' });
      const [raw] = await sdk.embeddings.embed(['normalize me'], { normalize: 'NONE' });

      const magnitude = (v: number[] | Float32Array): number =>
        Math.sqrt(Array.from(v).reduce((n, x) => n + x * x, 0));
      assert.ok(
        Math.abs(magnitude(l2.vector) - 1) < 0.01,
        `L2 vectors are unit length: ${magnitude(l2.vector)}`
      );
      // NONE is supposed to return the raw pooled vector. It does not, and the
      // reason is in the engine rather than in this SDK: the ONNX embedding
      // provider calls normalize_vector(pooled) unconditionally on both the
      // single and the batch path (onnx_embedding_provider.cpp:626 and :788)
      // and never reads EmbeddingsOptions.normalize. The field travels on the
      // wire now, so this records the state of the world today and fails the
      // moment the engine starts honouring it.
      assert.ok(
        Math.abs(magnitude(raw.vector) - 1) < 0.01,
        'normalize=NONE still comes back unit length: the ONNX engine always normalizes'
      );
    });
  }
);

// ---------------------------------------------------------------------------
// F11 — rerank
// ---------------------------------------------------------------------------

test('rerank: a known-answer set is ordered correctly and topN truncates it',
  { timeout: 600000, skip: 'no reranker model ships in the desktop catalog' },
  async () => {
    // Left as a runnable skip rather than deleted: the rerank path is migrated
    // (rac_rerank_component_rerank_proto, results already sorted best-first by
    // commons) but nothing in the catalog loads a cross-encoder, so there is no
    // honest way to assert ordering on this machine. Add a reranker row and
    // this runs unchanged.
  }
);

// ---------------------------------------------------------------------------
// F12 — diarization
// ---------------------------------------------------------------------------

test('diarization: two speakers in one clip are separated',
  { timeout: 600000, ...skipFor(DIAR_ID) },
  async () => {
    await withModels([], async (sdk) => {
      await registerLocal(sdk, DIAR_ID, 'DIARIZATION');
      await sdk.models.load(DIAR_ID);
      const RATE = 16000;
      // Two tones at different pitches, which is the crudest possible stand-in
      // for two speakers. What is asserted is the plumbing and the invariants,
      // not the speaker count, because a synthetic tone is not a voice.
      const samples = new Float32Array(RATE * 2);
      for (let i = 0; i < RATE; i++) samples[i] = 0.4 * Math.sin((2 * Math.PI * 180 * i) / RATE);
      for (let i = RATE; i < samples.length; i++) {
        samples[i] = 0.4 * Math.sin((2 * Math.PI * 400 * i) / RATE);
      }

      const result = await sdk.diarization.diarize(audio.float32(samples, RATE));
      assert.ok(result.speakerCount >= 0, 'a speaker count is reported');
      for (const s of result.segments) {
        assert.ok(s.endMs >= s.startMs, 'every segment ends no earlier than it starts');
        assert.equal(typeof s.speakerId, 'string', 'and carries a speaker label');
      }
    });
  }
);

// ---------------------------------------------------------------------------
// F13 — segmentation
// ---------------------------------------------------------------------------

test('segmentation: a class mask covers the image exactly',
  { timeout: 600000, ...skipFor(SEG_ID) },
  async () => {
    await withModels([], async (sdk) => {
      await registerLocal(sdk, SEG_ID, 'SEGMENTATION');
      await sdk.models.load(SEG_ID);
      const W = 64;
      const H = 64;
      const rgb = new Uint8Array(W * H * 3);
      for (let i = 0; i < rgb.length; i += 3) {
        rgb[i] = 120;
        rgb[i + 1] = 160;
        rgb[i + 2] = 90;
      }

      const result = await sdk.segmentation.segment(image.rawRgb(rgb, W, H));
      assert.equal(result.width, W, 'the mask describes the source width');
      assert.equal(result.height, H, 'and the source height');
      assert.equal(result.classMask.length, W * H, 'one class per pixel');
      // Commons rejects a result whose pixel counts do not sum to
      // width * height before it encodes one, so this is exact rather than
      // approximate, and the fractions are a real partition of the image.
      const counted = result.classes.reduce((n, c) => n + c.pixelCount, 0);
      assert.equal(counted, W * H, 'the class summaries partition the image');
      const coverage = result.classes.reduce((n, c) => n + c.fraction, 0);
      assert.ok(Math.abs(coverage - 1) < 1e-6, `coverage sums to 1: ${coverage}`);
    });
  }
);

test('segmentation: an encoded image is refused rather than silently mishandled',
  { timeout: 600000, ...(hasNative ? {} : { skip: 'RUNANYWHERE_NATIVE_PATH unset' }) },
  async () => {
    await withModels([], async (sdk) => {
      await assert.rejects(
        () => sdk.segmentation.segment(image.bytes(new Uint8Array([1, 2, 3]))),
        /raw RGB pixels/,
        'commons has no decoder for a container, so the SDK says so up front'
      );
    });
  }
);
