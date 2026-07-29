// Download the Gemma models curated for a 16 GB desktop GPU. Safe to rerun:
// completed files are skipped and interrupted .part files resume.
const { resolveModel } = require('../dist/download');

const DEFAULT_MODELS = ['gemma-4-e2b', 'gemma-4-e4b', 'gemma-4-12b'];
const models = process.argv.slice(2);
if (!models.length) models.push(...DEFAULT_MODELS);

(async () => {
  for (const id of models) {
    let lastPercent = -1;
    let lastPrint = 0;
    console.log(`[gemma] resolving ${id}`);
    const resolved = await resolveModel(id, {
      onProgress(p) {
        const now = Date.now();
        if (p.percent === lastPercent && now - lastPrint < 5000) return;
        if (p.percent !== 100 && p.percent < lastPercent + 2 && now - lastPrint < 5000) return;
        lastPercent = p.percent;
        lastPrint = now;
        const received = (p.received / 1024 ** 3).toFixed(2);
        const total = p.total ? (p.total / 1024 ** 3).toFixed(2) : '?';
        console.log(`[gemma] ${id} ${p.file}: ${p.percent}% (${received}/${total} GiB)`);
      },
    });
    console.log(`[gemma] ready ${id}: ${resolved.primary}${resolved.mmproj ? ` + ${resolved.mmproj}` : ''}`);
  }
})().catch((error) => {
  console.error('[gemma] download failed:', error && error.stack ? error.stack : error);
  process.exitCode = 1;
});
