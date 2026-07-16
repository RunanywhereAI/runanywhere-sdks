// M1b VLM smoke test: load a VLM (GGUF + mmproj) and caption an image, streaming.
// Usage: node test_vlm.js <runanywhere_native.node> <model.gguf> <mmproj.gguf> <image.jpg>
const os = require('os');
const path = require('path');

const [, , addonPath, model, mmproj, image] = process.argv;
if (!addonPath || !model || !mmproj || !image) {
  console.error('usage: node test_vlm.js <.node> <model.gguf> <mmproj.gguf> <image.(jpg|png)>');
  process.exit(2);
}

const ra = require(path.resolve(addonPath));
console.log('[vlm] .node loaded; commons version =', ra.version);

ra.initialize(path.join(os.tmpdir(), 'ra-electron-m1', 'secure'));
console.log('[vlm] initialized');

const h = ra.loadVlmModel(model, mmproj, 'smolvlm-256m', 'SmolVLM 256M');
console.log('[vlm] model + mmproj loaded, handle =', h);

process.stdout.write('[vlm] CAPTION: ');
ra.generateVlm(h, image, 'Describe this image in one short sentence.', (tok) => {
  process.stdout.write(tok);
})
  .then(() => {
    console.log('\n[vlm] generation complete (Promise resolved)');
    ra.unloadVlmModel(h);
    ra.shutdown();
    console.log('[vlm] done.');
  })
  .catch((err) => {
    console.error('\n[vlm] failed:', err && err.message ? err.message : err);
    ra.shutdown();
    process.exit(1);
  });
