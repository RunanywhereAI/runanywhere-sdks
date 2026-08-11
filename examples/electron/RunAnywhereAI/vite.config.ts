import { defineConfig } from 'vite';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = path.dirname(fileURLToPath(import.meta.url));

// The renderer bundle only. Main and preload are emitted by tsc (see
// tsconfig.*.build.json) because Electron loads them as CommonJS and they need
// no bundling — externalizing every native dependency is the whole job there.
//
// `@runanywhere/proto-ts` is intentionally NOT aliased: it is a real dependency
// that resolves through node_modules to its built ESM, matching what the
// tsconfigs typecheck against. The renderer imports only generated enums and
// message types from it — never SDK code, which is Node-flavoured.

export default defineConfig({
  root: path.resolve(dir, 'src/renderer'),
  // Assets resolve relative to index.html so the bundle works from file:// in a
  // packaged build, where there is no server and no absolute root.
  base: './',
  resolve: {
    alias: [{ find: /^@shared\/(.*)$/, replacement: path.resolve(dir, 'src/shared/$1') }],
  },
  build: {
    outDir: path.resolve(dir, 'out/renderer'),
    emptyOutDir: true,
    // External sourcemaps only: the page CSP forbids eval, so an eval-based
    // sourcemap would break the app outright rather than merely be unhelpful.
    sourcemap: true,
    target: 'chrome128', // Electron 43 ships Chromium 128+
  },
  server: {
    port: 5173,
    strictPort: true,
  },
});
