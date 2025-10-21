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
        'eventemitter3'
      ],
      output: {
        globals: {
          '@runanywhere/core': 'RunAnywhereCore',
          'eventemitter3': 'EventEmitter3'
        }
      }
    },
    outDir: 'dist',
    emptyOutDir: false,
    sourcemap: true,
    minify: false // Disable minification for better debugging
  },
  worker: {
    format: 'es',
    rollupOptions: {
      external: []
    }
  },
  optimizeDeps: {
    include: ['@huggingface/transformers']
  }
});
