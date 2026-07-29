// M1a smoke test: load the .node in plain Node, run streaming LLM generation
// through the rac_* C ABI (the same path the Electron utility process will use).
//
// Usage: node test_addon.js <path-to-runanywhere_native.node> <model.gguf>
const os = require('os');
const path = require('path');

const addonPath = process.argv[2];
const modelPath = process.argv[3];
if (!addonPath || !modelPath) {
  console.error('usage: node test_addon.js <runanywhere_native.node> <model.gguf>');
  process.exit(2);
}

const ra = require(path.resolve(addonPath));
console.log('[test] .node loaded; commons version =', ra.version);

const secure = path.join(os.tmpdir(), 'ra-electron-m1', 'secure');
ra.initialize(secure);
console.log('[test] initialized (Win32 adapter + rac_init + llamacpp)');

const h = ra.loadModel(modelPath, 'm1-model', 'M1 Model');
console.log('[test] model loaded, handle =', h);

process.stdout.write('[test] OUTPUT: ');
ra.generate(h, 'What is the capital of France? Answer in one word.', (tok) => {
  process.stdout.write(tok);
})
  .then(() => {
    console.log('\n[test] generation complete (Promise resolved)');
    ra.unloadModel(h);
    ra.shutdown();
    console.log('[test] done.');
  })
  .catch((err) => {
    console.error('\n[test] generate failed:', err && err.message ? err.message : err);
    ra.shutdown();
    process.exit(1);
  });
