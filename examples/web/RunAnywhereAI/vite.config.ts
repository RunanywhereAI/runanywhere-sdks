import { defineConfig, type Plugin } from 'vite';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

// __dirname is not available in ESM; derive it from import.meta.url
const __dir = path.dirname(fileURLToPath(import.meta.url));

// Absolute path to the workspace root (runanywhere-sdks/)
const workspaceRoot = path.resolve(__dir, '../../..');

// SDK WASM directories (each backend ships its own WASM)
const coreWasmDir = path.resolve(workspaceRoot, 'sdk/runanywhere-web/packages/core/wasm');
const llamacppWasmDir = path.resolve(workspaceRoot, 'sdk/runanywhere-web/packages/llamacpp/wasm');
const onnxWasmDir = path.resolve(workspaceRoot, 'sdk/runanywhere-web/packages/onnx/wasm');
const webCoreSrc = path.resolve(workspaceRoot, 'sdk/runanywhere-web/packages/core/src/index.ts');
const webCoreInternalSrc = path.resolve(workspaceRoot, 'sdk/runanywhere-web/packages/core/src/internal.ts');
const webCoreBrowserSrc = path.resolve(workspaceRoot, 'sdk/runanywhere-web/packages/core/src/browser.ts');
const llamacppSrc = path.resolve(workspaceRoot, 'sdk/runanywhere-web/packages/llamacpp/src/index.ts');
const onnxSrc = path.resolve(workspaceRoot, 'sdk/runanywhere-web/packages/onnx/src/index.ts');

// Local source alias for proto-ts keeps the example on package-root import
// paths while avoiding direct `dist/*` imports in application code/config.
const protoTsSrc = path.resolve(workspaceRoot, 'sdk/shared/proto-ts/src');

/**
 * Vite plugin to copy WASM binaries into the build output.
 *
 * Emscripten JS glue files resolve `.wasm` via `new URL("x.wasm", import.meta.url)`,
 * so the binaries must sit alongside the bundled JS in `dist/assets/`.
 *
 * Four WASM artifacts ship across three SDK packages:
 *   - `racommons.wasm` (commons core, owned by `@runanywhere/web`)
 *   - `racommons-llamacpp.wasm` (CPU LLM backend)
 *   - `racommons-llamacpp-webgpu.wasm` (WebGPU LLM backend)
 *   - `racommons-onnx-sherpa.wasm` (STT/TTS/VAD via Sherpa-ONNX)
 */
function copyWasmPlugin(): Plugin {
  const wasmFiles = [
    // Commons core WASM (loaded by RunAnywhere.initialize())
    { src: path.join(coreWasmDir, 'racommons.wasm'), dest: 'racommons.wasm' },
    // LlamaCpp backend WASM (CPU + WebGPU variants)
    { src: path.join(llamacppWasmDir, 'racommons-llamacpp.wasm'), dest: 'racommons-llamacpp.wasm' },
    { src: path.join(llamacppWasmDir, 'racommons-llamacpp-webgpu.wasm'), dest: 'racommons-llamacpp-webgpu.wasm' },
    // ONNX/Sherpa speech backend WASM (STT/TTS/VAD)
    { src: path.join(onnxWasmDir, 'racommons-onnx-sherpa.wasm'), dest: 'racommons-onnx-sherpa.wasm' },
  ];

  return {
    name: 'copy-wasm',
    writeBundle(options) {
      const outDir = options.dir ?? path.resolve(__dir, 'dist');
      const assetsDir = path.join(outDir, 'assets');
      fs.mkdirSync(assetsDir, { recursive: true });

      for (const { src, dest } of wasmFiles) {
        if (fs.existsSync(src)) {
          fs.copyFileSync(src, path.join(assetsDir, dest));
          const sizeMB = (fs.statSync(src).size / 1_000_000).toFixed(1);
          console.log(`  ✓ Copied ${dest} (${sizeMB} MB)`);
        } else {
          console.warn(`  ⚠ WASM not found: ${src}`);
        }
      }
    },
  };
}

export default defineConfig({
  plugins: [copyWasmPlugin()],
  resolve: {
    alias: [
      // Ensure all packages resolve to the same source modules during development.
      // Without this, package-root imports can resolve to dist/ and create
      // duplicate singletons while the demo runs against local source.
      { find: /^@runanywhere\/web-llamacpp$/, replacement: llamacppSrc },
      { find: /^@runanywhere\/web-onnx$/, replacement: onnxSrc },
      { find: /^@runanywhere\/web\/internal$/, replacement: webCoreInternalSrc },
      { find: /^@runanywhere\/web\/browser$/, replacement: webCoreBrowserSrc },
      { find: /^@runanywhere\/web$/, replacement: webCoreSrc },
      { find: /^@runanywhere\/proto-ts\/(.*)$/, replacement: protoTsSrc + '/$1.ts' },
      { find: '@runanywhere/proto-ts', replacement: protoTsSrc + '/index.ts' },
    ],
  },
  server: {
    headers: {
      // Cross-Origin Isolation — required for SharedArrayBuffer / multi-threaded WASM.
      // Without these headers the SDK falls back to single-threaded mode.
      // Safari doesn't support 'credentialless'; see public/coi-serviceworker.js
      // and the ensureCrossOriginIsolation() call in src/main.ts for the fallback.
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'credentialless',
    },
    fs: {
      // Allow Vite to serve files from the entire workspace
      allow: [workspaceRoot],
      strict: true,
    },
  },
  optimizeDeps: {
    exclude: ['@runanywhere/web', '@runanywhere/web-llamacpp', '@runanywhere/web-onnx'],
  },
  assetsInclude: ['**/*.wasm'],
});
