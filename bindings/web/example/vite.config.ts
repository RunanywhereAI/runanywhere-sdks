import { defineConfig, type Plugin } from 'vite';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

// __dirname is not available in ESM; derive it from import.meta.url.
const __dir = path.dirname(fileURLToPath(import.meta.url));
const workspaceRoot = path.resolve(__dir, '../../..');

// Default: build against the in-repo SDK source (contributor harness).
// `RAC_USE_INSTALLED_SDK=1` builds against installed tarballs instead, which is
// what the release consumer gate does after `npm install`.
const useInstalledSDK = process.env.RAC_USE_INSTALLED_SDK === '1';

/** WASM directory of one SDK package: installed tarball, or workspace source. */
function wasmDir(installedPackage: string, workspacePackage: string): string {
  return useInstalledSDK
    ? path.resolve(__dir, 'node_modules', installedPackage, 'wasm')
    : path.resolve(workspaceRoot, 'bindings/web/packages', workspacePackage, 'wasm');
}

const coreWasmDir = wasmDir('@runanywhere/web', 'core');
const llamacppWasmDir = wasmDir('@runanywhere/web-llamacpp', 'llamacpp');
const onnxWasmDir = wasmDir('@runanywhere/web-onnx', 'onnx');

// Every package must resolve to the same source modules, otherwise a
// package-root import can land on `dist/` and create a duplicate SDK singleton.
const protoTsSrc = path.resolve(workspaceRoot, 'bindings/shared/proto-ts/src');
const webCoreSrc = path.resolve(workspaceRoot, 'bindings/web/packages/core/src');
const localSDKSourceAliases = [
  {
    find: /^@runanywhere\/web-llamacpp$/,
    replacement: path.resolve(workspaceRoot, 'bindings/web/packages/llamacpp/src/index.ts'),
  },
  { find: /^@runanywhere\/web\/backend$/, replacement: path.join(webCoreSrc, 'backend.ts') },
  { find: /^@runanywhere\/web\/browser$/, replacement: path.join(webCoreSrc, 'browser.ts') },
  { find: /^@runanywhere\/web$/, replacement: path.join(webCoreSrc, 'index.ts') },
  { find: /^@runanywhere\/proto-ts\/(.*)$/, replacement: `${protoTsSrc}/$1.ts` },
  { find: '@runanywhere/proto-ts', replacement: `${protoTsSrc}/index.ts` },
];

/**
 * Copy the canonical Emscripten runtime artifacts into the build output.
 *
 * Emscripten glue resolves its binary via `new URL("x.wasm", import.meta.url)`,
 * so each `.wasm` must sit beside the bundled JS in `dist/assets/`. Each
 * pthread-enabled glue module also spawns workers under its original filename,
 * and Vite hashes the main-thread copy it bundles — so the canonical `.js` has
 * to be emitted too, or the worker request falls through to the SPA HTML and
 * Emscripten waits forever for its pthread pool.
 *
 * Four canonical JS/WASM pairs ship across the three publishable packages.
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
      // Keep `vite dev` startup lightweight, but never emit a partial
      // production bundle that only fails after deployment.
      if (!requireCompleteArtifacts) return;
      const missing = requiredFiles.filter(
        (file) => !fs.existsSync(file) || fs.statSync(file).size === 0,
      );
      if (missing.length > 0) {
        this.error(
          `Required Web SDK WASM artifacts are missing or empty:\n${
            missing.map((file) => `  - ${path.relative(workspaceRoot, file)}`).join('\n')
          }\nRun \`npm run build:wasm:all\` from bindings/web before building this example.`,
        );
      }
    },
    writeBundle(options) {
      const assetsDir = path.join(options.dir ?? path.resolve(__dir, 'dist'), 'assets');
      fs.mkdirSync(assetsDir, { recursive: true });
      for (const { directory, baseName } of wasmArtifacts) {
        for (const extension of ['js', 'wasm'] as const) {
          const src = path.join(directory, `${baseName}.${extension}`);
          fs.copyFileSync(src, path.join(assetsDir, `${baseName}.${extension}`));
          console.log(`  ✓ Copied ${baseName}.${extension} (${(fs.statSync(src).size / 1_000_000).toFixed(1)} MB)`);
        }
      }
    },
  };
}

// SharedArrayBuffer — and therefore the pthread CPU WASM build — requires
// cross-origin isolation on both the dev server and the preview server.
const isolationHeaders = {
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Embedder-Policy': 'credentialless',
} as const;

export default defineConfig(({ command }) => ({
  plugins: [copyWasmPlugin(command === 'build')],
  // Chrome 86 is the Web SDK's documented floor; pin it so a Vite major cannot
  // silently raise it through its moving `baseline-widely-available` default.
  build: { target: 'chrome86' },
  resolve: { alias: useInstalledSDK ? [] : localSDKSourceAliases },
  server: {
    host: 'localhost',
    port: 3000,
    strictPort: true,
    headers: isolationHeaders,
    cors: false,
    fs: { allow: [workspaceRoot], strict: true },
  },
  preview: {
    host: 'localhost',
    port: 3000,
    strictPort: true,
    headers: isolationHeaders,
    cors: false,
  },
  optimizeDeps: { exclude: ['@runanywhere/web', '@runanywhere/web-llamacpp'] },
  assetsInclude: ['**/*.wasm'],
}));
