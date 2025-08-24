import { defineConfig } from 'vite';
import { resolve } from 'path';

export default defineConfig({
  build: {
    lib: {
      entry: resolve(__dirname, 'src/index.ts'),
      name: 'RunAnywhereVADSilero',
      formats: ['es', 'cjs'],
      fileName: (format) => format === 'es' ? 'index.mjs' : 'index.js'
    },
    rollupOptions: {
      external: [
        '@runanywhere/core',
        '@ricky0123/vad-web',
        'eventemitter3'
      ],
      output: {
        globals: {
          '@runanywhere/core': 'RunAnywhereCore',
          '@ricky0123/vad-web': 'VADWeb',
          'eventemitter3': 'EventEmitter3'
        }
      }
    },
    outDir: 'dist',
    emptyOutDir: true,
    sourcemap: true,
    minify: 'terser'
  }
});
