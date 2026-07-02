import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

const dir = fileURLToPath(new URL('.', import.meta.url));
const sdk = (p: string): string => resolve(dir, '../../../sdk/runanywhere-web-next', p);
const protoSrc = resolve(dir, '../../../sdk/shared/proto-ts/src');
const repoRoot = resolve(dir, '../../..');

export default defineConfig({
  plugins: [svelte()],
  resolve: {
    alias: [
      { find: /^@runanywhere\/web\/internal$/, replacement: sdk('packages/core/dist/internal.js') },
      { find: /^@runanywhere\/web$/, replacement: sdk('packages/core/dist/index.js') },
      { find: /^@runanywhere\/web-llamacpp$/, replacement: sdk('packages/llamacpp/dist/index.js') },
      { find: /^@runanywhere\/web-onnx$/, replacement: sdk('packages/onnx/dist/index.js') },
      { find: /^@runanywhere\/proto-ts\/(.*)$/, replacement: `${protoSrc}/$1.ts` },
      { find: /^@runanywhere\/proto-ts$/, replacement: `${protoSrc}/index.ts` },
    ],
  },
  worker: { format: 'es' },
  server: {
    host: true,
    headers: {
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'credentialless',
    },
    fs: { allow: [repoRoot], strict: true },
  },
  optimizeDeps: {
    exclude: ['@runanywhere/web', '@runanywhere/web-llamacpp', '@runanywhere/web-onnx'],
  },
  assetsInclude: ['**/*.wasm'],
});
