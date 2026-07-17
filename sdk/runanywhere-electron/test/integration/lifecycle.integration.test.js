// Integration test for the two-phase lifecycle + event bus against the real addon.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const NATIVE_PATH = process.env.RUNANYWHERE_NATIVE_PATH;
const HAVE_ADDON = Boolean(NATIVE_PATH) && (() => {
  try { return fs.existsSync(NATIVE_PATH); } catch { return false; }
})();
const SKIP = HAVE_ADDON ? {} : { skip: 'RUNANYWHERE_NATIVE_PATH unset or file missing' };

test('two-phase init exposes ready-state and emits lifecycle + telemetry events',
  { timeout: 120000, ...SKIP },
  async () => {
    const { RunAnywhere } = require('../../dist');
    const seen = [];
    const off = RunAnywhere.events.on((e) => seen.push(e.type + (e.modality ? ':' + e.modality : '')));

    // Phase 1 (synchronous).
    assert.equal(RunAnywhere.isInitialized, false);
    RunAnywhere.initialize({ environment: 'staging' });
    assert.equal(RunAnywhere.isInitialized, true);
    assert.equal(RunAnywhere.environment, 'staging');
    assert.ok(seen.includes('initialized'), 'initialized event fired');

    // Phase 2 (background services) — awaitable + idempotent.
    await RunAnywhere.completeServicesInitialization();
    assert.equal(RunAnywhere.areServicesReady, true);
    assert.ok(seen.includes('servicesReady'), 'servicesReady event fired');

    // Model lifecycle events.
    const llm = await RunAnywhere.loadLLM('qwen2.5-0.5b');
    assert.ok(seen.includes('modelLoaded:llm'), 'modelLoaded event fired');

    // generateStream emits a 'generation' telemetry event with metrics on completion.
    let genResult = null;
    const off2 = RunAnywhere.events.on((e) => { if (e.type === 'generation') genResult = e.result; });
    // eslint-disable-next-line no-unused-vars
    for await (const _e of llm.generateStream('Say hi in one short sentence.', { maxTokens: 16 })) {
      /* drain the stream */
    }
    off2();
    assert.ok(genResult, 'a generation telemetry event fired');
    assert.ok(genResult.tokenCount > 0);
    assert.ok(genResult.tokensPerSecond >= 0);

    llm.unload();
    assert.ok(seen.includes('modelUnloaded:llm'), 'modelUnloaded event fired');

    RunAnywhere.shutdown();
    assert.equal(RunAnywhere.isInitialized, false);
    assert.equal(RunAnywhere.areServicesReady, false);
    assert.ok(seen.includes('shutdown'), 'shutdown event fired');
    off();
  }
);
