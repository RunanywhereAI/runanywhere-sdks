// End-to-end through the public facade: createRunAnywhere -> initialize ->
// models.register/load -> llm.generate + llm.generateStream. Gated on a built
// addon + a local GGUF.
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import test from 'node:test';

import { createRunAnywhere } from '../../src/facade.js';
import { NativeBackend } from '../../src/native/backend.js';
import { loadAddon } from '../../src/native/load.js';
import { ModelRegistration } from '../../src/namespaces/models.js';

const MODEL_ID = 'smollm2-135m';
const MODEL_PATH = path.join(os.homedir(), '.runanywhere', 'models', MODEL_ID, 'model.gguf');
const BASE = path.join(os.homedir(), '.runanywhere');
const ready = Boolean(process.env.RUNANYWHERE_NATIVE_PATH) && fs.existsSync(MODEL_PATH);

test(
  'facade: RunAnywhere.llm.generate + generateStream over the real backend',
  { skip: ready ? false : 'set RUNANYWHERE_NATIVE_PATH and provide a local GGUF to run' },
  async () => {
    const ra = createRunAnywhere(new NativeBackend(loadAddon()));
    await ra.initialize({ baseDir: BASE });
    assert.equal(ra.isReady, true);
    assert.ok(ra.version.length > 0);

    const caps = await ra.capabilities();
    assert.ok(caps.device.length > 0, 'capabilities().device should report a backend');
    assert.ok(caps.modalities.includes('llm'));

    await ra.models.register(ModelRegistration.local(MODEL_PATH, { id: MODEL_ID }));
    const loaded = await ra.models.load(MODEL_ID);
    assert.equal(loaded.id, MODEL_ID);

    const result = await ra.llm.generate('Say hello in one short sentence.', { maxOutputTokens: 48 });
    assert.ok(result.text.length > 0, 'generate produced no text');
    assert.ok(result.metrics.outputTokens > 0);

    let tokens = 0;
    let finalText = '';
    for await (const ev of ra.llm.generateStream('Say hi.', { maxOutputTokens: 32 })) {
      if (ev.isFinal) finalText = ev.result?.text ?? '';
      else if (ev.token) tokens += 1;
    }
    assert.ok(tokens > 0, 'stream produced no tokens');
    assert.ok(finalText.length > 0, 'final event carried no text');

    await ra.reset();
    assert.equal(ra.isReady, false);
  }
);
