// Manual, network-backed check of the comprehensive model-support paths:
//   1. HuggingFace repo id -> auto-resolve GGUF (+ mmproj) -> download
//   2. direct URL -> download by filename
//   3. isRemoteSource classification
// Uses a tiny model so it finishes quickly. Not part of the unit suite.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { resolveModel, isRemoteSource } = require('../dist/download');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ra-resolve-'));
const pct = { v: 0 };
const onProgress = (p) => { if (p.percent >= pct.v + 20) { pct.v = p.percent; process.stdout.write(` ${p.file} ${p.percent}%`); } };

(async () => {
  let ok = true;
  const check = (name, cond, extra = '') => { console.log(`${cond ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + extra : ''}`); ok = ok && cond; };

  // 1. classification (pure)
  check('isRemoteSource HF repo', isRemoteSource('bartowski/SmolLM2-135M-Instruct-GGUF'));
  check('isRemoteSource URL', isRemoteSource('https://x/y.gguf'));
  check('isRemoteSource local path is false', !isRemoteSource(path.join(tmp, 'a.gguf')));

  // 2. HuggingFace repo id -> pick Q4_K_M and download
  pct.v = 0;
  const repo = 'bartowski/SmolLM2-135M-Instruct-GGUF';
  const hf = await resolveModel(repo, { dir: tmp, onProgress });
  process.stdout.write('\n');
  check('HF resolves an id starting hf-', hf.id.startsWith('hf-'), hf.id);
  check('HF picks a Q4_K_M gguf', /q4_k_m/i.test(hf.primary), path.basename(hf.primary));
  check('HF downloaded file exists', fs.existsSync(hf.primary) && fs.statSync(hf.primary).size > 1e6, fs.existsSync(hf.primary) ? Math.round(fs.statSync(hf.primary).size / 1e6) + ' MB' : 'missing');

  // 3. direct URL -> download by filename (tiny file, proves the mechanic)
  pct.v = 0;
  const url = 'https://huggingface.co/bartowski/SmolLM2-135M-Instruct-GGUF/resolve/main/README.md';
  const u = await resolveModel(url, { dir: tmp, onProgress });
  process.stdout.write('\n');
  check('URL resolves an id starting url-', u.id.startsWith('url-'), u.id);
  check('URL downloaded file exists', fs.existsSync(u.primary), path.basename(u.primary));

  // 4. re-resolve is idempotent (no re-download; same paths)
  const hf2 = await resolveModel(repo, { dir: tmp });
  check('HF re-resolve is idempotent', hf2.primary === hf.primary);

  fs.rmSync(tmp, { recursive: true, force: true });
  console.log(ok ? '\nALL PASS' : '\nSOME FAILED');
  process.exit(ok ? 0 : 1);
})().catch((e) => { console.error('ERROR', e); try { fs.rmSync(tmp, { recursive: true, force: true }); } catch { /* ignore */ } process.exit(1); });
