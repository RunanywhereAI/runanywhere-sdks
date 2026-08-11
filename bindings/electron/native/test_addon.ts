// M1a smoke test: load the .node in plain Node, run streaming LLM generation
// through the rac_* C ABI (the same path the Electron utility process will use).
//
// Usage: node dist-native/test_addon.js <path-to-runanywhere_native.node> <model.gguf>
import * as os from 'os';
import * as path from 'path';

import type { NativeAddon } from '../dist/bridge';

const addonPath = process.argv[2];
const modelPath = process.argv[3];
if (!addonPath || !modelPath) {
  console.error('usage: node test_addon.js <runanywhere_native.node> <model.gguf>');
  process.exit(2);
}

// eslint-disable-next-line @typescript-eslint/no-var-requires
const ra = require(path.resolve(addonPath)) as NativeAddon;
console.log('[test] .node loaded; commons version =', ra.version);

void (async () => {
  const secure = path.join(os.tmpdir(), 'ra-electron-m1', 'secure');
  await ra.initialize(secure);
  console.log('[test] initialized (platform adapter + rac_init + llamacpp)');

  const h = await ra.loadModel(modelPath, 'm1-model', 'M1 Model');
  console.log('[test] model loaded, handle =', h);

  process.stdout.write('[test] OUTPUT: ');
  try {
    await ra.generate(h, 'What is the capital of France? Answer in one word.', (tok: string) => {
      process.stdout.write(tok);
    });
  } catch (err: unknown) {
    console.error('\n[test] generate failed:', err instanceof Error ? err.message : err);
    await ra.shutdown();
    process.exit(1);
  }
  console.log('\n[test] generation complete (Promise resolved)');
  await ra.unloadModel(h);
  await ra.shutdown();
  console.log('[test] done.');
})();
