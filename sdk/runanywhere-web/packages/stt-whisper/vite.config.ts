import { defineConfig } from 'vite';
import { resolve } from 'path';

export default defineConfig({
  build: {
    lib: {
      entry: resolve(__dirname, 'src/index.ts'),
      name: 'RunAnywhereSTTWhisper',
      formats: ['es', 'cjs'],
      fileName: (format) => format === 'es' ? 'index.mjs' : 'index.js'
    },
    rollupOptions: {
      external: [
        '@runanywhere/core',
        '@xenova/transformers',
        'eventemitter3'
      ],
      output: {
        globals: {
          '@runanywhere/core': 'RunAnywhereCore',
          '@xenova/transformers': 'Transformers',
          'eventemitter3': 'EventEmitter3'
        },
        assetFileNames: (assetInfo) => {
          if (assetInfo.name === 'worker.js') {
            return 'worker.js';
          }
          return '[name].[ext]';
        }
      }
    },
    outDir: 'dist',
    emptyOutDir: true,
    sourcemap: true,
    minify: 'terser'
  },
  worker: {
    format: 'es',
    rollupOptions: {
      external: ['@xenova/transformers']
    }
  }
});
