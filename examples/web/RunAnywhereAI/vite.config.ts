import { defineConfig } from 'vite';
import path from 'path';

// Absolute path to the workspace root
const workspaceRoot = path.resolve(__dirname, '../../..');

export default defineConfig({
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
    },
  },
  optimizeDeps: {
    exclude: ['@runanywhere/web'],
  },
  // Ensure .wasm files are treated as assets
  assetsInclude: ['**/*.wasm'],
});
