// F16 — LoRA over the commons lifecycle ABI, against the real addon and a real
// model.
//
// These entry points exist because F4 removed the component handle the old ones
// needed: language models live in commons' lifecycle store now, and
// rac_lora_{apply,remove,state}_proto act on whatever is resident there.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as os from 'node:os';
import * as path from 'node:path';

import { createRunAnywhere, NativeBackend, registerCatalog, clearCatalog } from '../../dist';
import type { Catalog, RunAnywhereApi } from '../../dist';
import { exists, nativeAddon } from './support';

const NATIVE_PATH = process.env.RUNANYWHERE_NATIVE_PATH;
const MODEL_ID = 'smollm2-135m';
const MODEL_FILE = path.join(os.homedir(), '.runanywhere', 'models', MODEL_ID, 'model.gguf');
// A real GGUF LoRA adapter, when one is staged. Applying an adapter needs a
// file the engine can actually read, so the cases that need one skip without it
// rather than asserting against a fabricated file.
const ADAPTER = process.env.RUNANYWHERE_LORA_ADAPTER;

const SKIP: { skip?: string } = exists(NATIVE_PATH)
  ? exists(MODEL_FILE)
    ? {}
    : { skip: `model missing: ${MODEL_FILE}` }
  : { skip: 'RUNANYWHERE_NATIVE_PATH unset or file missing' };
const ADAPTER_SKIP: { skip?: string } = SKIP.skip
  ? SKIP
  : exists(ADAPTER)
    ? {}
    : { skip: 'RUNANYWHERE_LORA_ADAPTER unset — no adapter staged to apply' };

const CATALOG: Catalog = {
  [MODEL_ID]: {
    type: 'llm',
    files: [{ url: 'https://example.invalid/smollm2-135m.gguf', as: 'model.gguf' }],
    primary: 'model.gguf',
    label: 'SmolLM2 135M',
    sizeMB: 100,
  },
};

async function withModel(run: (sdk: RunAnywhereApi) => Promise<void>): Promise<void> {
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

test('lora: the namespace answers instead of rejecting as unimplemented',
  { timeout: 300000, ...SKIP },
  async () => {
    await withModel(async (sdk) => {
      // Before F16 every verb here rejected with a notImplemented naming the
      // missing lifecycle ABI. The bar for "migrated" is that a read succeeds
      // against a loaded model and reports an empty set rather than an error.
      const state = await sdk.lora.list();
      assert.ok(Array.isArray(state.applied), 'list() reports an adapter array');
      assert.equal(state.applied.length, 0, 'nothing is applied on a fresh load');
    });
  }
);

test('lora: removeAll on a model with no adapters is a no-op, not a failure',
  { timeout: 300000, ...SKIP },
  async () => {
    await withModel(async (sdk) => {
      await sdk.lora.removeAll();
      const state = await sdk.lora.list();
      assert.equal(state.applied.length, 0, 'still nothing applied');
      // The model has to survive the call: a clear that tore down the base
      // model would show up here rather than at the next generation.
      const after = await sdk.llm.generate('Say ok.', { maxOutputTokens: 8 });
      assert.ok(after.text.length > 0, 'the base model still generates');
    });
  }
);

test('lora: applying an adapter shows up in list, and removing it restores the base',
  { timeout: 300000, ...ADAPTER_SKIP },
  async () => {
    await withModel(async (sdk) => {
      const base = await sdk.llm.generate('The capital of France is', {
        maxOutputTokens: 16,
        temperature: 0,
      });

      // Guarded by ADAPTER_SKIP: this case only runs with an adapter staged.
      await sdk.lora.apply(ADAPTER as string, 0.8);
      const applied = await sdk.lora.list();
      assert.equal(applied.applied.length, 1, 'the adapter is reported as applied');
      assert.ok(applied.applied[0].id, 'with an id');
      assert.ok(applied.applied[0].scale > 0, 'and the scale it was applied at');

      const adapted = await sdk.llm.generate('The capital of France is', {
        maxOutputTokens: 16,
        temperature: 0,
      });
      assert.ok(adapted.text.length > 0, 'the adapted model still generates');

      await sdk.lora.removeAll();
      assert.equal((await sdk.lora.list()).applied.length, 0, 'removal empties the set');

      const restored = await sdk.llm.generate('The capital of France is', {
        maxOutputTokens: 16,
        temperature: 0,
      });
      // Greedy decoding at temperature 0 makes this deterministic, so the base
      // output returning is a real check that the adapter was detached rather
      // than left half-applied.
      assert.equal(restored.text, base.text, 'removing the adapter restores base output');
    });
  }
);
