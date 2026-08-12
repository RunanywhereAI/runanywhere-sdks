/** Runtime companion to nodenext-consumer.mts: package exports must load in a
 * standards-compliant ESM resolver without bundler extension inference. */
const [core, backend, browser, llamacpp, onnx] = await Promise.all([
  import('@runanywhere/web'),
  import('@runanywhere/web/backend'),
  import('@runanywhere/web/browser'),
  import('@runanywhere/web-llamacpp'),
  import('@runanywhere/web-onnx'),
]);

const requiredExports = [
  ['@runanywhere/web', core.RunAnywhere],
  ['@runanywhere/web/backend', backend.registerWasmModule],
  ['@runanywhere/web/browser', browser.AudioCapture],
  ['@runanywhere/web-llamacpp', llamacpp.LlamaCPP],
  ['@runanywhere/web-onnx', onnx.ONNX],
];

for (const [packageName, value] of requiredExports) {
  if (value === null || (typeof value !== 'function' && typeof value !== 'object')) {
    throw new Error(`${packageName} did not expose its expected runtime entrypoint`);
  }
}

process.stdout.write('Verified Node ESM runtime resolution for all Web package entrypoints.\n');
