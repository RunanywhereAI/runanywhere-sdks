import { defineConfig, loadEnv, type Plugin } from 'vite';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import {
  controlPlaneRelayIsEnabled,
} from './src/services/control-plane-relay';
import { viteControlPlaneRelayPlugin } from './server/vite-control-plane-relay';

// __dirname is not available in ESM; derive it from import.meta.url
const __dir = path.dirname(fileURLToPath(import.meta.url));

// Absolute path to the workspace root (runanywhere-sdks/)
const workspaceRoot = path.resolve(__dir, '../../..');

// SDK WASM directories (each backend ships its own WASM)
const coreWasmDir = path.resolve(workspaceRoot, 'sdk/runanywhere-web/packages/core/wasm');
const llamacppWasmDir = path.resolve(workspaceRoot, 'sdk/runanywhere-web/packages/llamacpp/wasm');
const onnxWasmDir = path.resolve(workspaceRoot, 'sdk/runanywhere-web/packages/onnx/wasm');
const webCoreSrc = path.resolve(workspaceRoot, 'sdk/runanywhere-web/packages/core/src/index.ts');
const webCoreBackendSrc = path.resolve(workspaceRoot, 'sdk/runanywhere-web/packages/core/src/backend.ts');
const webCoreBrowserSrc = path.resolve(workspaceRoot, 'sdk/runanywhere-web/packages/core/src/browser.ts');
const llamacppSrc = path.resolve(workspaceRoot, 'sdk/runanywhere-web/packages/llamacpp/src/index.ts');
const onnxSrc = path.resolve(workspaceRoot, 'sdk/runanywhere-web/packages/onnx/src/index.ts');

// Local source alias for proto-ts keeps the example on package-root import
// paths while avoiding direct `dist/*` imports in application code/config.
const protoTsSrc = path.resolve(workspaceRoot, 'sdk/shared/proto-ts/src');

/**
 * Vite plugin to copy the canonical Emscripten runtime artifacts into the
 * build output.
 *
 * Emscripten JS glue files resolve `.wasm` via `new URL("x.wasm", import.meta.url)`,
 * so the binaries must sit alongside the bundled JS in `dist/assets/`. Each
 * pthread-enabled glue module also starts workers using its original filename
 * (for example, `new Worker(new URL("racommons.js", import.meta.url))`). Vite
 * hashes the imported main-thread copy, so the canonical `.js` module must be
 * emitted as well; otherwise the worker request falls through to the SPA HTML
 * and Emscripten waits forever for its pthread pool.
 *
 * Four JS/WASM artifact pairs ship across three SDK packages. Vite bundles the
 * Emscripten JS glue while this plugin copies each canonical pair next to it:
 *   - `racommons.{js,wasm}` (commons core, owned by `@runanywhere/web`)
 *   - `racommons-llamacpp.{js,wasm}` (CPU LLM backend)
 *   - `racommons-llamacpp-webgpu.{js,wasm}` (WebGPU LLM backend)
 *   - `racommons-onnx-sherpa.{js,wasm}` (STT/TTS/VAD via Sherpa-ONNX)
 */
const wasmArtifacts = [
  { directory: coreWasmDir, baseName: 'racommons' },
  { directory: llamacppWasmDir, baseName: 'racommons-llamacpp' },
  { directory: llamacppWasmDir, baseName: 'racommons-llamacpp-webgpu' },
  { directory: onnxWasmDir, baseName: 'racommons-onnx-sherpa' },
] as const;

function copyWasmPlugin(requireCompleteArtifacts: boolean): Plugin {
  const requiredFiles = wasmArtifacts.flatMap(({ directory, baseName }) => [
    path.join(directory, `${baseName}.js`),
    path.join(directory, `${baseName}.wasm`),
  ]);

  return {
    name: 'copy-wasm',
    buildStart() {
      // Keep `vite` development startup lightweight, but never produce a
      // partial production bundle that will fail only after deployment.
      if (!requireCompleteArtifacts) return;

      const missingOrEmpty = requiredFiles.filter(
        (file) => !fs.existsSync(file) || fs.statSync(file).size === 0,
      );
      if (missingOrEmpty.length > 0) {
        const formattedFiles = missingOrEmpty
          .map((file) => `  - ${path.relative(workspaceRoot, file)}`)
          .join('\n');
        this.error(
          `Required Web SDK WASM artifacts are missing or empty:\n${formattedFiles}\n` +
            'Run `npm run build:wasm:all` from sdk/runanywhere-web before building the example.',
        );
      }
    },
    writeBundle(options) {
      const outDir = options.dir ?? path.resolve(__dir, 'dist');
      const assetsDir = path.join(outDir, 'assets');
      fs.mkdirSync(assetsDir, { recursive: true });

      for (const { directory, baseName } of wasmArtifacts) {
        for (const extension of ['js', 'wasm'] as const) {
          const src = path.join(directory, `${baseName}.${extension}`);
          const dest = `${baseName}.${extension}`;
          fs.copyFileSync(src, path.join(assetsDir, dest));
          const sizeMB = (fs.statSync(src).size / 1_000_000).toFixed(1);
          console.log(`  ✓ Copied ${dest} (${sizeMB} MB)`);
        }
      }
    },
  };
}

function localHTTPSOptions(): { key: Buffer; cert: Buffer } | undefined {
  const keyPath = process.env.RA_E2E_HTTPS_KEY_PATH;
  const certPath = process.env.RA_E2E_HTTPS_CERT_PATH;
  if (!keyPath && !certPath) return undefined;
  if (!keyPath || !certPath) {
    throw new Error('Both RA_E2E_HTTPS_KEY_PATH and RA_E2E_HTTPS_CERT_PATH are required.');
  }
  return {
    key: fs.readFileSync(keyPath),
    cert: fs.readFileSync(certPath),
  };
}

const isolationHeaders = {
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Embedder-Policy': 'credentialless',
} as const;

export default defineConfig(({ command, mode }) => {
  const env = loadEnv(mode, __dir, '');
  const relayEnabled = controlPlaneRelayIsEnabled(env.VITE_RUNANYWHERE_RELAY_ENABLED);
  const serverApiKey = process.env.RUNANYWHERE_API_KEY ?? env.RUNANYWHERE_API_KEY;
  const https = localHTTPSOptions();
  const relayPlugin = command === 'serve' && relayEnabled
    ? [viteControlPlaneRelayPlugin(serverApiKey)]
    : [];

  return {
    plugins: [copyWasmPlugin(command === 'build'), ...relayPlugin],
    resolve: {
    alias: [
      // Ensure all packages resolve to the same source modules during development.
      // Without this, package-root imports can resolve to dist/ and create
      // duplicate singletons while the demo runs against local source.
      { find: /^@runanywhere\/web-llamacpp$/, replacement: llamacppSrc },
      { find: /^@runanywhere\/web-onnx$/, replacement: onnxSrc },
      { find: /^@runanywhere\/web\/backend$/, replacement: webCoreBackendSrc },
      { find: /^@runanywhere\/web\/browser$/, replacement: webCoreBrowserSrc },
      { find: /^@runanywhere\/web$/, replacement: webCoreSrc },
      { find: /^@runanywhere\/proto-ts\/(.*)$/, replacement: protoTsSrc + '/$1.ts' },
      { find: '@runanywhere/proto-ts', replacement: protoTsSrc + '/index.ts' },
    ],
    },
    server: {
      headers: isolationHeaders,
      https,
      cors: false,
      allowedHosts: ['localtest.me'],
      fs: {
        // Allow Vite to serve files from the entire workspace
        allow: [workspaceRoot],
        strict: true,
      },
    },
    preview: {
      headers: isolationHeaders,
      https,
      cors: false,
      allowedHosts: ['localtest.me'],
    },
    optimizeDeps: {
      exclude: ['@runanywhere/web', '@runanywhere/web-llamacpp', '@runanywhere/web-onnx'],
    },
    assetsInclude: ['**/*.wasm'],
  };
});
