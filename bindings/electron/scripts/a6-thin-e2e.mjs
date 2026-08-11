#!/usr/bin/env node
/**
 * Track A6 — prove thin shared-commons Electron path end-to-end on macOS.
 * Staging must already have put thin .node + commons + plugins in prebuilds/.
 * Does NOT download models. Fails clearly if lfm2.5-230m (or override) is absent.
 */
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const pkgRoot = path.resolve(__dirname, '..');
const plat = `${process.platform}-${process.arch}`;

const CORE_DIR = path.join(pkgRoot, 'prebuilds', plat);
const LLAMA_DIR = path.join(pkgRoot, 'packages', 'llamacpp', 'prebuilds', plat);
const SHERPA_DIR = path.join(pkgRoot, 'packages', 'sherpa', 'prebuilds', plat);

const NODE = path.join(CORE_DIR, 'runanywhere_native.node');
const COMMONS = path.join(CORE_DIR, 'librac_commons.dylib');
const LLAMA = path.join(LLAMA_DIR, 'librunanywhere_llamacpp.dylib');
const LLAMA_BACKEND = path.join(LLAMA_DIR, 'librac_backend_llamacpp.dylib');
const SHERPA = path.join(SHERPA_DIR, 'librunanywhere_sherpa.dylib');
const SHERPA_BACKEND = path.join(SHERPA_DIR, 'librac_backend_sherpa.dylib');

const MODEL_ID = process.env.RA_A6_MODEL_ID || 'lfm2.5-230m';
const MODEL_FILE = path.join(os.homedir(), '.runanywhere', 'models', MODEL_ID, 'model.gguf');
const MODEL_ALT = path.join(
  os.homedir(),
  '.runanywhere',
  'RunAnywhere',
  'Models',
  'LlamaCpp',
  MODEL_ID,
  'model.gguf'
);

function mustExist(p, label) {
  if (!fs.existsSync(p)) {
    console.error(`FAIL: missing ${label}: ${p}`);
    process.exit(2);
  }
  const st = fs.statSync(p);
  console.log(`  ok ${label}: ${p} (${(st.size / 1e6).toFixed(2)} MB)`);
}

console.log('=== A6 staging check ===');
mustExist(NODE, 'thin .node');
mustExist(COMMONS, 'librac_commons');
mustExist(LLAMA, 'llamacpp carrier');
mustExist(LLAMA_BACKEND, 'llamacpp backend sidecar');
mustExist(SHERPA, 'sherpa carrier');
mustExist(SHERPA_BACKEND, 'sherpa backend sidecar');

const modelPath = fs.existsSync(MODEL_FILE)
  ? MODEL_FILE
  : fs.existsSync(MODEL_ALT)
    ? MODEL_ALT
    : null;
if (!modelPath) {
  console.error(
    [
      `FAIL: model ${MODEL_ID} not found locally — refusing to download.`,
      `  looked for: ${MODEL_FILE}`,
      `  looked for: ${MODEL_ALT}`,
      '  Place a small GGUF there or set RA_A6_MODEL_ID to a cached id.',
    ].join('\n')
  );
  process.exit(3);
}
console.log(`  ok model: ${modelPath} (${(fs.statSync(modelPath).size / 1e6).toFixed(1)} MB)`);

// Prefer thin staged prebuild; pin explicitly so a fat tree cannot win.
process.env.RUNANYWHERE_NATIVE_PATH = NODE;
// Start with llamacpp only — sherpa loaded later via loadPlugin for dual-registry proof.
process.env.RUNANYWHERE_PLUGIN_PATHS = LLAMA;

const { createRunAnywhere, NativeBackend, registerCatalog, clearCatalog } = require('../dist');
const { addon } = require('../dist/bridge');

async function main() {
  console.log('\n=== A6 thin addon probe ===');
  console.log(`  thinAddon=${addon.thinAddon}`);
  console.log(`  pluginApiVersion=${typeof addon.pluginApiVersion === 'function' ? addon.pluginApiVersion() : 'n/a'}`);
  if (addon.thinAddon !== true) {
    console.error('FAIL: expected thinAddon === true');
    process.exit(4);
  }

  clearCatalog();
  registerCatalog({
    [MODEL_ID]: {
      type: 'llm',
      files: [{ url: 'https://example.invalid/model.gguf', as: 'model.gguf' }],
      primary: 'model.gguf',
      label: MODEL_ID,
      sizeMB: Math.round(fs.statSync(modelPath).size / 1e6),
    },
  });

  const sdk = createRunAnywhere(new NativeBackend(addon));
  await sdk.initialize({ environment: 'production' });

  let listed = addon.listPlugins();
  console.log(`  listPlugins after init (llamacpp env): ${JSON.stringify(listed)}`);
  if (!listed.map(String).some((n) => /llama/i.test(n))) {
    console.error('FAIL: llamacpp not in registry after RUNANYWHERE_PLUGIN_PATHS init');
    process.exit(5);
  }

  console.log('\n=== A6 load + generate ===');
  await sdk.models.load(MODEL_ID);
  const result = await sdk.llm.generate('Name one colour.', {
    maxOutputTokens: 24,
    temperature: 0,
    reasoning: { mode: 'OFF' },
  });
  const snippet = (result.text || '').trim().slice(0, 120);
  console.log(`  text: ${JSON.stringify(snippet)}`);
  console.log(
    `  tokens: in=${result.inputTokens} out=${result.outputTokens} tok/s=${result.tokensPerSecond?.toFixed?.(1) ?? result.tokensPerSecond}`
  );
  if (!snippet || !(result.outputTokens > 0)) {
    console.error('FAIL: generate produced no tokens');
    process.exit(6);
  }

  console.log('\n=== A6 dual-plugin registry ===');
  await addon.loadPlugin(SHERPA);
  listed = addon.listPlugins();
  console.log(`  listPlugins after loadPlugin(sherpa): ${JSON.stringify(listed)}`);
  const names = listed.map(String);
  const hasLlama = names.some((n) => /llama/i.test(n));
  const hasSherpa = names.some((n) => /sherpa/i.test(n));
  if (!hasLlama || !hasSherpa) {
    console.error(`FAIL: expected both llamacpp and sherpa in registry, got ${JSON.stringify(names)}`);
    process.exit(7);
  }

  // Cross-plugin handle validity: generation still works after sherpa joins the registry.
  const again = await sdk.llm.generate('Say hello in one word.', {
    maxOutputTokens: 16,
    temperature: 0,
    reasoning: { mode: 'OFF' },
  });
  const snippet2 = (again.text || '').trim().slice(0, 80);
  console.log(`  post-sherpa generate: ${JSON.stringify(snippet2)} (out=${again.outputTokens})`);
  if (!snippet2 || !(again.outputTokens > 0)) {
    console.error('FAIL: LLM handle invalid after loading second plugin');
    process.exit(8);
  }

  await sdk.reset();
  clearCatalog();
  console.log('\n=== A6 SUCCESS ===');
  console.log(
    JSON.stringify(
      {
        thinAddon: true,
        plugins: names,
        generate1: snippet,
        generate2: snippet2,
        outputTokens: [result.outputTokens, again.outputTokens],
      },
      null,
      2
    )
  );
}

main().catch((err) => {
  console.error('FAIL:', err);
  process.exit(1);
});
