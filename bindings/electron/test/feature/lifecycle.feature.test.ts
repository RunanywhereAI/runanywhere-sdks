// F2 + F3 — model lifecycle, registry, threads, and residency, against the real
// addon and a real model.
//
// Covers the whole feature in one file, the way it is actually used: an app
// stages a catalog, initialize() seeds it into the commons registry, the app
// lists/filters/registers/unregisters against that registry, and commons resolves
// the on-disk artifacts and takes the model into residency and back out.
//
// Needs RUNANYWHERE_NATIVE_PATH plus a downloaded GGUF; both are checked up front
// so a machine without them skips instead of failing.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as os from 'node:os';
import * as path from 'node:path';

import {
  createRunAnywhere,
  NativeBackend,
  ModelAbi,
  registerCatalog,
  clearCatalog,
} from '../../dist';
import type { Catalog } from '../../dist';
import { exists, nativeAddon } from './support';

const NATIVE_PATH = process.env.RUNANYWHERE_NATIVE_PATH;
const MODELS_ROOT = path.join(os.homedir(), '.runanywhere', 'models');
const MODEL_ID = 'smollm2-135m';
const MODEL_FILE = path.join(MODELS_ROOT, MODEL_ID, 'model.gguf');

const SKIP: { skip?: string } = exists(NATIVE_PATH)
  ? exists(MODEL_FILE)
    ? {}
    : { skip: `model missing: ${MODEL_FILE}` }
  : { skip: 'RUNANYWHERE_NATIVE_PATH unset or file missing' };

const CATALOG: Catalog = {
  [MODEL_ID]: {
    type: 'llm',
    files: [{ url: 'https://example.invalid/smollm2-135m.gguf', as: 'model.gguf' }],
    primary: 'model.gguf',
    label: 'SmolLM2 135M',
    sizeMB: 100,
  },
};

test('models: registry seeding, filtering, registration, and residency', { timeout: 180000, ...SKIP },
  async () => {
    clearCatalog();
    registerCatalog(CATALOG);

    const backend = new NativeBackend(nativeAddon());
    const sdk = createRunAnywhere(backend);
    const abi = new ModelAbi(backend);

    await sdk.initialize({ environment: 'development' });

    // --- the staged catalog became registry rows -----------------------------
    const listed = await sdk.models.list();
    const seeded = listed.find((m) => m.id === MODEL_ID);
    assert.ok(seeded, `${MODEL_ID} is in models.list()`);
    assert.equal(seeded.category, 'LANGUAGE');
    assert.equal(seeded.framework, 'LLAMA_CPP');
    assert.equal(seeded.name, 'SmolLM2 135M');

    const fetched = await sdk.models.get(MODEL_ID);
    assert.equal(fetched?.id, MODEL_ID);
    assert.equal(await sdk.models.get('no-such-model'), null);

    // Filtering is a commons ModelQuery, not a JS .filter() over everything.
    assert.ok((await sdk.models.list({ category: 'LANGUAGE' })).some((m) => m.id === MODEL_ID));
    assert.ok(!(await sdk.models.list({ category: 'TEXT_TO_SPEECH' })).some((m) => m.id === MODEL_ID));

    // --- register / unregister ----------------------------------------------
    const registered = await sdk.models.register({
      id: 'feature-test-registered',
      category: 'LANGUAGE',
      url: 'https://example.invalid/another.gguf',
      name: 'Registered By Test',
    });
    assert.equal(registered.id, 'feature-test-registered');
    assert.equal(registered.category, 'LANGUAGE');
    assert.ok(await sdk.models.get('feature-test-registered'));

    await sdk.models.unregister('feature-test-registered');
    assert.equal(await sdk.models.get('feature-test-registered'), null,
      'unregister drops the row');

    // --- commons resolves the on-disk artifact ------------------------------
    const resolved = await abi.resolvePaths({
      modelId: MODEL_ID,
      forceReload: false,
      validateAvailability: false,
      backendPreferences: [],
    });
    assert.equal(resolved.error, undefined, `resolvePaths: ${resolved.error?.message ?? ''}`);
    assert.equal(resolved.resolvedPath, MODEL_FILE,
      'commons resolved the primary artifact from the registry row');

    // --- residency through the lifecycle ABI --------------------------------
    // No model is resident before the load, and current() says so rather than
    // throwing.
    const before = await abi.current({ includeModelMetadata: false });
    assert.equal(before.found, false, 'nothing is resident before the load');

    // A multi-GB load must not occupy the event loop: the addon runs it on a
    // worker, so a timer scheduled beforehand still fires on time.
    let tickedDuringLoad = false;
    const ticker = setInterval(() => { tickedDuringLoad = true; }, 5);

    const loadResult = await abi.load({
      modelId: MODEL_ID,
      forceReload: false,
      validateAvailability: true,
      backendPreferences: [],
    });
    clearInterval(ticker);

    assert.equal(loadResult.error, undefined, `load: ${loadResult.error?.message ?? ''}`);
    assert.equal(loadResult.modelId, MODEL_ID);
    assert.equal(loadResult.resolvedPath, MODEL_FILE);
    assert.ok(loadResult.loadedAtUnixMs > 0, 'load stamped a time');
    assert.ok(tickedDuringLoad, 'the event loop kept running during the load');

    const current = await abi.current({ includeModelMetadata: true });
    assert.equal(current.found, true, 'the model is resident');
    assert.equal(current.modelId, MODEL_ID);
    assert.equal(current.resolvedPath, MODEL_FILE);

    const unloaded = await abi.unload({ modelId: MODEL_ID, unloadAll: false });
    assert.equal(unloaded.error, undefined, `unload: ${unloaded.error?.message ?? ''}`);
    assert.deepEqual(unloaded.unloadedModelIds, [MODEL_ID]);

    const after = await abi.current({ includeModelMetadata: false });
    assert.equal(after.found, false, 'nothing is resident after the unload');

    // --- refresh reconciles the registry against disk ------------------------
    const refreshed = await sdk.models.refresh();
    assert.ok(Array.isArray(refreshed), 'refresh returns the reconciled rows');
    assert.ok(refreshed.some((m) => m.id === MODEL_ID), 'the seeded row survives a refresh');

    await sdk.reset();
    clearCatalog();
  }
);

// F3 — nothing blocking runs on the event loop, unload waits for the work it
// would otherwise free out from under, and residency is decided by memory
// rather than by whichever screen happens to be open.
test('threads and residency: loads stay off the loop, unload waits, memory evicts',
  { timeout: 300000, ...SKIP },
  async () => {
    clearCatalog();
    registerCatalog(CATALOG);

    const backend = new NativeBackend(nativeAddon());
    const sdk = createRunAnywhere(backend);
    const abi = new ModelAbi(backend);

    await sdk.initialize({ environment: 'development' });

    // --- the machine's memory is real, and reported ---------------------------
    const memory = await backend.memoryInfo();
    assert.ok(memory.totalBytes > 0, 'the platform adapter reported total RAM');
    assert.ok(memory.availableBytes > 0, 'the platform adapter reported free RAM');
    assert.ok(memory.availableBytes <= memory.totalBytes, 'free RAM is bounded by total');

    // --- the secure store answers asynchronously ------------------------------
    await backend.secureSet('f3-feature-key', 'f3-feature-value');
    assert.equal(await backend.secureGet('f3-feature-key'), 'f3-feature-value');
    await backend.secureDelete('f3-feature-key');
    assert.equal(await backend.secureGet('f3-feature-key'), null, 'a miss is null, not a throw');

    // --- a models.load runs on a worker ---------------------------------------
    // Language models go through the lifecycle ABI (F4), so this is the same
    // entry point the test above drives, reached the way an app reaches it. A
    // 5 ms timer has to keep firing throughout.
    let ticks = 0;
    const ticker = setInterval(() => { ticks += 1; }, 5);
    const loaded = await sdk.models.load(MODEL_ID);
    clearInterval(ticker);
    assert.equal(loaded.id, MODEL_ID);
    assert.ok(ticks > 0, 'the event loop kept running during the load');

    const state = await sdk.models.state();
    assert.ok(state.loaded.LANGUAGE, 'the language model is resident');
    assert.equal(state.memoryTotalBytes, memory.totalBytes, 'state reports the same RAM');

    // --- the component slot path still leases and gates -----------------------
    // Nothing in v3 loads a component LLM any more, but the addon's lease and
    // per-handle gate still guard that path, and this is what proves it: unload
    // takes the handle only once the in-flight generation has gone idle.
    await backend.ensure('llm', MODEL_ID);
    let tokens = 0;
    let generationFinished = false;
    const generation = backend
      .llmGenerate('Count slowly from one to twenty.', { maxTokens: 64 }, () => { tokens += 1; })
      .then(() => { generationFinished = true; });
    assert.equal(generationFinished, false, 'the unload below is issued mid-generation');
    const unload = backend.unload('llm').then(() => {
      assert.ok(generationFinished, 'unload waited for the in-flight generation to finish');
    });
    await Promise.all([generation, unload]);
    assert.ok(tokens > 0, 'the generation produced tokens before the unload landed');
    assert.equal(await backend.loaded('llm'), null, 'the slot is free after the unload');

    // --- memory pressure evicts, and only when it has to ----------------------
    // A row with no memory requirement is admitted untouched: commons answers
    // "fits" and the policy leaves residency alone.
    await sdk.models.load(MODEL_ID);
    assert.ok((await sdk.models.state()).loaded.LANGUAGE, 'the language model is resident again');

    const HUGE_ID = 'feature-test-huge-vision';
    await sdk.models.register({
      id: HUGE_ID,
      category: 'VISION',
      path: path.join(MODELS_ROOT, HUGE_ID, 'missing.gguf'),
      name: 'Impossible Vision Model',
    });
    const hugeRow = await abi.get(HUGE_ID);
    assert.ok(hugeRow, 'the registration produced a registry row to update');
    await abi.update({ ...hugeRow, memoryRequiredBytes: memory.totalBytes * 1000 });

    // Loading it cannot succeed — the artifact does not exist — but the residency
    // pass runs first, and it is the release that is under test.
    await assert.rejects(sdk.models.load(HUGE_ID));
    assert.equal(
      (await sdk.models.state()).loaded.LANGUAGE,
      undefined,
      'memory pressure released the language model to make room for another category'
    );

    await sdk.models.unregister(HUGE_ID);
    await sdk.reset();
    clearCatalog();
  }
);
