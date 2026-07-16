// download.js — prove catalog download: load a model by id (auto-downloads to
// ~/.runanywhere/models if missing), then generate. No local path needed.
//   node examples/download.js
const { RunAnywhere } = require('../dist');

(async () => {
  console.log('@runanywhere/electron — commons version:', RunAnywhere.version);
  RunAnywhere.initialize();

  console.log('[download] loading catalog id "smollm2-135m" (downloads if missing)...');
  let lastPct = -1;
  const llm = await RunAnywhere.loadLLM('smollm2-135m', {
    onProgress: (p) => {
      if (p.percent !== lastPct && p.percent % 20 === 0) {
        lastPct = p.percent;
        process.stdout.write(`  ${p.file}: ${p.percent}%\n`);
      }
    },
  });
  console.log('[download] loaded; generating:');
  process.stdout.write('  ');
  for await (const t of llm.generate('The capital of France is')) process.stdout.write(t);
  console.log();

  llm.unload();
  RunAnywhere.shutdown();
  console.log('[download] OK — resolved by id, downloaded, loaded, and generated.');
})().catch((e) => {
  console.error('FAILED:', e);
  process.exit(1);
});
