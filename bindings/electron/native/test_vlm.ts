// M1b VLM smoke test: load a VLM (GGUF + mmproj) and caption an image, streaming.
// Usage: node dist-native/test_vlm.js <runanywhere_native.node> <model.gguf> <mmproj.gguf> <image.jpg>
import * as os from 'os';
import * as path from 'path';

import type { NativeAddon } from '../dist/bridge';

const [, , addonPath, model, mmproj, image] = process.argv;
if (!addonPath || !model || !mmproj || !image) {
  console.error('usage: node test_vlm.js <.node> <model.gguf> <mmproj.gguf> <image.(jpg|png)>');
  process.exit(2);
}

// eslint-disable-next-line @typescript-eslint/no-var-requires
const ra = require(path.resolve(addonPath)) as NativeAddon;
console.log('[vlm] .node loaded; commons version =', ra.version);

void (async () => {
  await ra.initialize(path.join(os.tmpdir(), 'ra-electron-m1', 'secure'));
  console.log('[vlm] initialized');

  const h = await ra.loadVlmModel(model, mmproj, 'smolvlm-256m', 'SmolVLM 256M');
  console.log('[vlm] model + mmproj loaded, handle =', h);

  process.stdout.write('[vlm] CAPTION: ');
  try {
    await ra.generateVlm(h, image, 'Describe this image in one short sentence.', (tok: string) => {
      process.stdout.write(tok);
    });
  } catch (err: unknown) {
    console.error('\n[vlm] failed:', err instanceof Error ? err.message : err);
    await ra.shutdown();
    process.exit(1);
  }
  console.log('\n[vlm] generation complete (Promise resolved)');
  await ra.unloadVlmModel(h);
  await ra.shutdown();
  console.log('[vlm] done.');
})();
