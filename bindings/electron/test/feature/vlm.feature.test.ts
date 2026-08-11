// F6 — VLM over the commons proto ABI, against the real addon and a real model.
//
// The vision model goes into the same lifecycle store the language model does,
// which is what lets `rac_vlm_generate_proto` find it without a handle. The
// image travels inside the request as a VLMImage, so the three N-API image
// shapes the addon used to accept are gone: a path, encoded bytes, and raw RGB
// all end up as fields on one proto message that commons decodes.
//
// smolvlm-256m is small enough to be honest about: what is asserted is that the
// picture reached the encoder and the model answered about it, not that the
// answer is correct.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

import { createRunAnywhere, NativeBackend, registerCatalog, clearCatalog, image } from '../../dist';
import type { Catalog, ImageInput, RunAnywhereApi } from '../../dist';
import { exists, nativeAddon } from './support';

const NATIVE_PATH = process.env.RUNANYWHERE_NATIVE_PATH;
const MODEL_ID = 'smolvlm-256m';
const MODEL_DIR = path.join(os.homedir(), '.runanywhere', 'models', MODEL_ID);
const MODEL_FILE = path.join(MODEL_DIR, 'model.gguf');
const MMPROJ_FILE = path.join(MODEL_DIR, 'mmproj.gguf');

const SKIP: { skip?: string } = exists(NATIVE_PATH)
  ? exists(MODEL_FILE) && exists(MMPROJ_FILE)
    ? {}
    : { skip: `vision model missing: ${MODEL_FILE} + ${MMPROJ_FILE}` }
  : { skip: 'RUNANYWHERE_NATIVE_PATH unset or file missing' };

const CATALOG: Catalog = {
  [MODEL_ID]: {
    type: 'vlm',
    files: [
      { url: 'https://example.invalid/smolvlm-256m.gguf', as: 'model.gguf' },
      { url: 'https://example.invalid/mmproj.gguf', as: 'mmproj.gguf' },
    ],
    primary: 'model.gguf',
    mmproj: 'mmproj.gguf',
    label: 'SmolVLM 256M',
    sizeMB: 280,
  },
};

// A 4x4 PNG, half red and half blue. Small enough to inline, real enough that
// the encoder has actual pixels to work on.
const PNG_4X4 = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAJUlEQVR4nGP8z4AATAxIYBRD' +
    'YTAyMjIyMjIyMjIyMjIyMjIyAgAtvAIBLQ3rCwAAAABJRU5ErkJggg==',
  'base64'
);

/** One initialized SDK with the vision model resident, plus its teardown. */
async function withVisionModel(run: (sdk: RunAnywhereApi) => Promise<void>): Promise<void> {
  clearCatalog();
  registerCatalog(CATALOG);
  const sdk = createRunAnywhere(new NativeBackend(nativeAddon()));
  await sdk.initialize({ environment: 'production' });
  try {
    await sdk.models.load(MODEL_ID);
    await run(sdk);
  } finally {
    await sdk.reset();
    clearCatalog();
  }
}

test('load: a vision model goes into the lifecycle store, projector and all',
  { timeout: 600000, ...SKIP },
  async () => {
    await withVisionModel(async (sdk) => {
      const state = await sdk.models.state();
      assert.equal(state.loaded.VISION?.id, MODEL_ID, 'commons reports the vision model resident');
      // The projector is a second file on the registry row, not a second
      // argument to the load: commons' artifact resolver matches it on the
      // VISION_PROJECTOR role. A model that loaded without one cannot answer
      // about an image at all, which the next test proves.
      assert.equal(state.loaded.LANGUAGE, undefined, 'and does not occupy the language slot');
    });
  }
);

test('generate: an image on disk goes in, an answer about it comes out',
  { timeout: 600000, ...SKIP },
  async () => {
    await withVisionModel(async (sdk) => {
      const file = path.join(os.tmpdir(), 'runanywhere-vlm-feature.png');
      fs.writeFileSync(file, PNG_4X4);
      try {
        const result = await sdk.vlm.generate(image.file(file), 'Describe this image.', {
          maxOutputTokens: 32,
          temperature: 0,
        });
        assert.ok(result.text.length > 0, `the model answered: ${result.text}`);
        assert.equal(result.model, MODEL_ID, 'the result names the model commons used');
        assert.ok(result.outputTokens > 0, 'the engine counted output tokens');
        assert.ok(
          ['STOP', 'LENGTH'].includes(result.finishReason),
          `finish reason is one commons reported: ${result.finishReason}`
        );
      } finally {
        fs.rmSync(file, { force: true });
      }
    });
  }
);

test('generate: encoded bytes and raw RGB reach the encoder the same way a path does',
  { timeout: 600000, ...SKIP },
  async () => {
    await withVisionModel(async (sdk) => {
      const encoded = await sdk.vlm.generate(image.bytes(PNG_4X4), 'What colour is this?', {
        maxOutputTokens: 24,
        temperature: 0,
      });
      assert.ok(encoded.text.length > 0, 'encoded bytes produced an answer');

      // Tightly packed 3 bytes/px with no row padding; commons rejects a buffer
      // whose length is not width * height * 3, so this also proves the
      // dimensions travel with the pixels.
      const rgb = new Uint8Array(4 * 4 * 3);
      for (let i = 0; i < rgb.length; i += 3) rgb[i] = 255;
      const raw = await sdk.vlm.generate(image.rawRgb(rgb, 4, 4), 'What colour is this?', {
        maxOutputTokens: 24,
        temperature: 0,
      });
      assert.ok(raw.text.length > 0, 'raw pixels produced an answer');

      // Deliberately malformed: raw pixels with no dimensions. The SDK builds
      // the VLMImage, so it is the SDK that must refuse this, not commons.
      const noDimensions = { rgb } as unknown as ImageInput;
      await assert.rejects(
        () => sdk.vlm.generate(noDimensions, 'What colour is this?'),
        /width and height/,
        'raw pixels without dimensions are rejected before the request is built'
      );
    });
  }
);

test('generateStream: token by token, then one completed event carrying the result',
  { timeout: 600000, ...SKIP },
  async () => {
    await withVisionModel(async (sdk) => {
      const pieces: string[] = [];
      let started = 0;
      let completed: Awaited<ReturnType<typeof sdk.vlm.generate>> | null = null;
      for await (const event of sdk.vlm.generateStream(
        image.bytes(PNG_4X4),
        'Describe this image.',
        { maxOutputTokens: 32, temperature: 0 }
      )) {
        if (event.type === 'started') started += 1;
        if (event.type === 'textDelta') pieces.push(event.text);
        if (event.type === 'completed') completed = event.result;
      }

      assert.equal(started, 1, 'exactly one started event');
      assert.ok(pieces.length > 1, 'the answer arrived in pieces rather than all at once');
      assert.ok(completed, 'the stream terminated with a completed event');
      assert.equal(completed.text, pieces.join(''), 'the pieces reassemble into the answer');
      assert.ok(completed.outputTokens > 0, 'the terminal result carries engine metrics');
    });
  }
);

test('cancel: breaking out of the stream stops native work and frees the model',
  { timeout: 600000, ...SKIP },
  async () => {
    await withVisionModel(async (sdk) => {
      let tokens = 0;
      const startedAt = Date.now();
      for await (const event of sdk.vlm.generateStream(
        image.bytes(PNG_4X4),
        'Describe this image in exhaustive detail, at length.',
        { maxOutputTokens: 500 }
      )) {
        if (event.type === 'textDelta' && ++tokens === 5) break;
      }
      const cancelledAfterMs = Date.now() - startedAt;
      assert.equal(tokens, 5, 'the loop stopped where the caller stopped it');
      assert.ok(cancelledAfterMs < 20000, `cancel returned promptly (${cancelledAfterMs}ms)`);

      // The same engine-side cancel race the LLM path documents: the backend
      // clears its cancel flag when a generation starts and the unwinding
      // cancelled loop can store `true` back into it. Settling here keeps the
      // next generation from inheriting a cancel it never asked for.
      await new Promise((resolve) => setTimeout(resolve, 300));

      const after = await sdk.vlm.generate(image.bytes(PNG_4X4), 'One word: what is this?', {
        maxOutputTokens: 8,
      });
      assert.ok(after.text.length > 0, `the model is usable after a cancel: ${after.text}`);
    });
  }
);
