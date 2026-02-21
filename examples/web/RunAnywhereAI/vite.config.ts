import { defineConfig, type Plugin } from 'vite';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

// __dirname is not available in ESM; derive it from import.meta.url
const __dir = path.dirname(fileURLToPath(import.meta.url));

// Absolute path to the workspace root (runanywhere-sdks/)
const workspaceRoot = path.resolve(__dir, '../../..');

// SDK WASM directories (each backend ships its own WASM)
const llamacppWasmDir = path.resolve(workspaceRoot, 'sdk/runanywhere-web/packages/llamacpp/wasm');
const onnxWasmDir = path.resolve(workspaceRoot, 'sdk/runanywhere-web/packages/onnx/wasm/sherpa');

/**
 * Vite plugin to copy WASM binaries into the build output.
 *
 * Emscripten JS glue files resolve `.wasm` via `new URL("x.wasm", import.meta.url)`,
 * so the binaries must sit alongside the bundled JS in `dist/assets/`.
 */
function copyWasmPlugin(): Plugin {
  const wasmFiles = [
    // LlamaCpp backend WASM
    { src: path.join(llamacppWasmDir, 'racommons-llamacpp.wasm'), dest: 'racommons-llamacpp.wasm' },
    { src: path.join(llamacppWasmDir, 'racommons-llamacpp-webgpu.wasm'), dest: 'racommons-llamacpp-webgpu.wasm' },
    // ONNX backend WASM (sherpa-onnx)
    { src: path.join(onnxWasmDir, 'sherpa-onnx.wasm'), dest: 'sherpa-onnx.wasm' },
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

/**
 * Vite plugin to serve onnxruntime-web WASM/worker files.
 *
 * onnxruntime-web dynamically imports worker .mjs files and fetches .wasm
 * binaries at absolute paths (e.g. /ort-wasm-simd-threaded.wasm). Vite's
 * dep optimizer rewrites the import but can't resolve the sibling files.
 * This plugin intercepts those requests and serves them from node_modules.
 */
function serveOrtFilesPlugin(): Plugin {
  const ortDistDir = path.resolve(__dir, 'node_modules/onnxruntime-web/dist');

  return {
    name: 'serve-ort-files',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        const url = req.url ?? '';
        // Match /ort-wasm-*.wasm and /ort-wasm-*.mjs (with optional ?query)
        const match = url.match(/^\/(ort-wasm[^?]*\.(wasm|mjs))(\?.*)?$/);
        if (!match) return next();

        const filename = match[1];
        const filePath = path.join(ortDistDir, filename);

        if (!fs.existsSync(filePath)) return next();

        const ext = match[2];
        const mime = ext === 'wasm' ? 'application/wasm' : 'application/javascript';
        res.setHeader('Content-Type', mime);
        res.setHeader('Cache-Control', 'public, max-age=31536000');
        fs.createReadStream(filePath).pipe(res);
      });
    },
  };
}

export default defineConfig({
  plugins: [copyWasmPlugin(), serveOrtFilesPlugin()],
  resolve: {
    alias: {
      // Ensure all packages resolve to the same source modules during development.
      // Without this, @runanywhere/web imports from llamacpp/onnx packages resolve
      // to dist/ while main.ts imports from src/, creating duplicate singletons.
      '@runanywhere/web': path.resolve(workspaceRoot, 'sdk/runanywhere-web/packages/core/src/index.ts'),
    },
  },
  server: {
    headers: {
      // Required for SharedArrayBuffer (pthreads) and WASM threads
      'Cross-Origin-Opener-Policy': 'same-origin',
      // 'credentialless' allows cross-origin resource loading
      'Cross-Origin-Embedder-Policy': 'credentialless',
    },
    fs: {
      // Allow Vite to serve files from the entire workspace
      allow: [workspaceRoot],
      strict: true,
    },
  },
  optimizeDeps: {
    exclude: ['@runanywhere/web'],
  },
  assetsInclude: ['**/*.wasm', '**/*.onnx'],
});
