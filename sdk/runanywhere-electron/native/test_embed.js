// M1b embeddings smoke test: load an ONNX embedding model and embed text, with a
// cosine-similarity sanity check (similar sentences should score higher).
// Usage: node test_embed.js <runanywhere_native.node> <model.onnx>
const os = require('os');
const path = require('path');

const [, , addonPath, model] = process.argv;
if (!addonPath || !model) {
  console.error('usage: node test_embed.js <.node> <model.onnx>');
  process.exit(2);
}

const ra = require(path.resolve(addonPath));
console.log('[embed] .node loaded; commons version =', ra.version);

ra.initialize(path.join(os.tmpdir(), 'ra-electron-m1', 'secure'));
const h = ra.loadEmbeddingModel(model);
console.log('[embed] model loaded, handle =', h);

const v = ra.embed(h, 'The capital of France is Paris.');
console.log('[embed] dim =', v.length, 'first5 =', Array.from(v.slice(0, 5)).map((x) => x.toFixed(4)));

const cos = (x, y) => {
  let d = 0, nx = 0, ny = 0;
  for (let i = 0; i < x.length; i++) { d += x[i] * y[i]; nx += x[i] * x[i]; ny += y[i] * y[i]; }
  return d / (Math.sqrt(nx) * Math.sqrt(ny));
};
const a = ra.embed(h, 'A cat sits on the mat.');
const b = ra.embed(h, 'A kitten rests on the rug.');
const c = ra.embed(h, 'The stock market crashed today.');
console.log('[embed] cos(cat, kitten) =', cos(a, b).toFixed(4), ' (expect HIGH)');
console.log('[embed] cos(cat, stocks) =', cos(a, c).toFixed(4), ' (expect LOW)');

ra.unloadEmbeddingModel(h);
ra.shutdown();
console.log('[embed] done.');
