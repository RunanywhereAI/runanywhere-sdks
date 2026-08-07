// Guards that every modality the addon claims is actually wired to commons: a
// wired method reaches a real rac error (or succeeds), never NOT_IMPLEMENTED
// (code 800); the documented deferrals still report 800. Gated on a built addon
// (no model needed), so it skips loudly rather than silently passing.
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import test from 'node:test';

import { loadAddon } from '../../src/native/load.js';

const NOT_IMPLEMENTED = 800;
const ready = Boolean(process.env.RUNANYWHERE_NATIVE_PATH);

// Await a value or promise and return the rac error code, or 0 on success.
async function codeOf(call: () => unknown): Promise<number> {
  try {
    const r = call();
    if (r && typeof (r as { then?: unknown }).then === 'function') {
      try {
        await r;
        return 0;
      } catch (e) {
        return (e as { code?: number }).code ?? -1;
      }
    }
    return 0;
  } catch (e) {
    return (e as { code?: number }).code ?? -1;
  }
}

test(
  'addon: wired modalities reach commons; only documented paths are NOT_IMPLEMENTED',
  { skip: ready ? false : 'set RUNANYWHERE_NATIVE_PATH to a built addon to run' },
  async () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const addon = loadAddon() as any;
    const base = fs.mkdtempSync(path.join(os.tmpdir(), 'ra-surface-'));
    addon.initialize(path.join(base, 'secure'), base);
    const empty = new Uint8Array();

    const wired = [
      'structuredParse', 'structuredPreparePrompt', 'vadStart', 'vadStop', 'vadReset',
      'sttState', 'ttsStop', 'ttsListVoices', 'vlmGenerate', 'sttTranscribe',
      'ttsSynthesize', 'embed', 'diarize', 'segment', 'vadConfigure', 'vadProcess',
      'frameworksForCapability',
    ];
    for (const m of wired) {
      const code = await codeOf(() => addon[m](empty));
      assert.notEqual(code, NOT_IMPLEMENTED, `${m} should be wired, got NOT_IMPLEMENTED`);
    }

    const deferred = ['rerank', 'toolRunLoop', 'sttStreamStart'];
    for (const m of deferred) {
      const code = await codeOf(() => addon[m](empty));
      assert.equal(code, NOT_IMPLEMENTED, `${m} should report NOT_IMPLEMENTED, got ${code}`);
    }

    addon.shutdown();
  }
);
