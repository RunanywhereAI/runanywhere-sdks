import { defineConfig } from 'vite';
import path from 'path';
import { fileURLToPath } from 'url';

// __dirname is not available in ESM; derive it from import.meta.url
const __dir = path.dirname(fileURLToPath(import.meta.url));

// Absolute path to the workspace root (runanywhere-sdks/)
const workspaceRoot = path.resolve(__dir, '../../..');

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
      strict: true,
    },
  },
  optimizeDeps: {
    exclude: ['@runanywhere/web'],
  },
  // Ensure .wasm files are treated as assets
  assetsInclude: ['**/*.wasm'],
});
