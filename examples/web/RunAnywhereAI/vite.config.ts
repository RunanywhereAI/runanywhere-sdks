import { defineConfig } from 'vite';
import path from 'path';

// Absolute path to the workspace root
const workspaceRoot = path.resolve(__dirname, '../../..');

export default defineConfig({
  server: {
    headers: {
      // Required for SharedArrayBuffer (pthreads) and WASM threads
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp',
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
