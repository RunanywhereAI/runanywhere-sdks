import { defineConfig, type Plugin } from 'vite';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

// __dirname is not available in ESM; derive it from import.meta.url
const __dir = path.dirname(fileURLToPath(import.meta.url));

// Absolute path to the workspace root (runanywhere-sdks/)
const workspaceRoot = path.resolve(__dir, '../../..');

// SDK WASM directory
const sdkWasmDir = path.resolve(workspaceRoot, 'sdk/runanywhere-web/packages/core/wasm');

/**
 * Vite plugin to copy WASM binaries into the build output.
 *
 * Emscripten JS glue files resolve `.wasm` via `new URL("x.wasm", import.meta.url)`,
 * so the binaries must sit alongside the bundled JS in `dist/assets/`.
 */
function copyWasmPlugin(): Plugin {
  const wasmFiles = [
    { src: path.join(sdkWasmDir, 'racommons.wasm'), dest: 'racommons.wasm' },
    { src: path.join(sdkWasmDir, 'racommons-webgpu.wasm'), dest: 'racommons-webgpu.wasm' },
    { src: path.join(sdkWasmDir, 'sherpa/sherpa-onnx.wasm'), dest: 'sherpa-onnx.wasm' },
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
  server: {
    headers: {
      // Required for SharedArrayBuffer (pthreads) and WASM threads
      'Cross-Origin-Opener-Policy': 'same-origin',
      // 'credentialless' allows cross-origin resource loading (e.g. model downloads
      // from GitHub releases, HuggingFace CDN) without requiring CORS headers on every
      // response, while still enabling SharedArrayBuffer for WASM pthreads.
      // Supported in Chrome 96+ and Firefox 119+.
      'Cross-Origin-Embedder-Policy': 'credentialless',
    },
    fs: {
      // Allow Vite to serve files from the entire workspace
      // (SDK TypeScript source + WASM output)
      allow: [workspaceRoot],
      strict: true,
    },
  },
  optimizeDeps: {
    exclude: ['@runanywhere/web'],
  },
  // Ensure .wasm files are treated as assets
  assetsInclude: ['**/*.wasm'],
});
