// M1b embeddings smoke test: load an ONNX embedding model and embed text, with a
// cosine-similarity sanity check (similar sentences should score higher).
// Usage: node dist-native/test_embed.js <runanywhere_native.node> <model.onnx>
import * as os from 'os';
import * as path from 'path';

import type { NativeAddon } from '../dist/bridge';

const [, , addonPath, model] = process.argv;
if (!addonPath || !model) {
  console.error('usage: node test_embed.js <.node> <model.onnx>');
  process.exit(2);
}

// eslint-disable-next-line @typescript-eslint/no-var-requires
const ra = require(path.resolve(addonPath)) as NativeAddon;
console.log('[embed] .node loaded; commons version =', ra.version);

const cos = (x: Float32Array, y: Float32Array): number => {
  let d = 0, nx = 0, ny = 0;
  for (let i = 0; i < x.length; i++) { d += x[i] * y[i]; nx += x[i] * x[i]; ny += y[i] * y[i]; }
  return d / (Math.sqrt(nx) * Math.sqrt(ny));
};

void (async () => {
  await ra.initialize(path.join(os.tmpdir(), 'ra-electron-m1', 'secure'));
  const h = await ra.loadEmbeddingModel(model);
  console.log('[embed] model loaded, handle =', h);

  const v = await ra.embed(h, 'The capital of France is Paris.');
  console.log('[embed] dim =', v.length, 'first5 =', Array.from(v.slice(0, 5)).map((x) => x.toFixed(4)));

  const a = await ra.embed(h, 'A cat sits on the mat.');
  const b = await ra.embed(h, 'A kitten rests on the rug.');
  const c = await ra.embed(h, 'The stock market crashed today.');
  console.log('[embed] cos(cat, kitten) =', cos(a, b).toFixed(4), ' (expect HIGH)');
  console.log('[embed] cos(cat, stocks) =', cos(a, c).toFixed(4), ' (expect LOW)');

  await ra.unloadEmbeddingModel(h);
  await ra.shutdown();
  console.log('[embed] done.');
})();
