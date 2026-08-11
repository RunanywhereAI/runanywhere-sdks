import { defineConfig } from 'vite';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = path.dirname(fileURLToPath(import.meta.url));

// The renderer bundle only. Main and preload are emitted by tsc (see
// tsconfig.*.build.json) because Electron loads them as CommonJS and they need
// no bundling — externalizing every native dependency is the whole job there.
//
// `@runanywhere/proto-ts` IS aliased, to the built `dist/*.js`.
//
// The tsconfigs map `@runanywhere/proto-ts/*` -> `dist/*.d.ts` as a typecheck-time
// shim (see tsconfig.base.json). Vite 8's rolldown resolver honours tsconfig
// `paths` during the bundle too, so without this alias the renderer resolves a
// *declaration* file, type-stripping leaves an empty module, and any runtime
// value import fails as MISSING_EXPORT (`audioCaptureDefaults` was the first).
// Aliasing to the emitted JS keeps the bundle on exactly the module the package
// `exports` map points at, while typecheck keeps reading the same declarations.
//
// The alias points INTO node_modules, and `preserveSymlinks` below keeps it
// there. A generated MESSAGE module (`model_types`, which carries the domain
// enums) also imports `@bufbuild/protobuf/wire`; resolving that needs proto-ts
// to stay under a `node_modules` that has the runtime beside it. Aliased to the
// source tree — or realpathed out of the link, which rolldown does by default —
// it lands in `sdk/shared/proto-ts/`, which has no `node_modules`, and the build
// fails on the protobuf runtime rather than on anything this app wrote.
const protoTsDist = path.resolve(dir, 'node_modules/@runanywhere/proto-ts/dist');

export default defineConfig({
  root: path.resolve(dir, 'src/renderer'),
  // Assets resolve relative to index.html so the bundle works from file:// in a
  // packaged build, where there is no server and no absolute root.
  base: './',
  resolve: {
    alias: [
      { find: /^@shared\/(.*)$/, replacement: path.resolve(dir, 'src/shared/$1') },
      { find: /^@runanywhere\/proto-ts$/, replacement: path.join(protoTsDist, 'index.js') },
      { find: /^@runanywhere\/proto-ts\/(.*)$/, replacement: path.join(protoTsDist, '$1.js') },
    ],
    // `file:` workspace deps are symlinks. Realpathing them moves resolution out
    // of this app's node_modules, so a linked package can no longer find its own
    // dependencies. Keep the link path.
    preserveSymlinks: true,
  },
  build: {
    outDir: path.resolve(dir, 'out/renderer'),
    emptyOutDir: true,
    // External sourcemaps only: the page CSP forbids eval, so an eval-based
    // sourcemap would break the app outright rather than merely be unhelpful.
    sourcemap: true,
    target: 'chrome128', // Electron 43 ships Chromium 128+
    rollupOptions: {
      // Main shell + preferences window (Swift Settings scene, 560×460).
      input: {
        main: path.resolve(dir, 'src/renderer/index.html'),
        settings: path.resolve(dir, 'src/renderer/settings.html'),
      },
    },
  },
  server: {
    port: 5173,
    strictPort: true,
  },
});
