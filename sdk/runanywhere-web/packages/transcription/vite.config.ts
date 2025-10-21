import { defineConfig } from 'vite';
import { resolve } from 'path';

export default defineConfig({
  build: {
    lib: {
      entry: resolve(__dirname, 'src/index.ts'),
      name: 'RunAnywhereTranscription',
      fileName: 'index',
      formats: ['es']
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
        }
      }
    },
    target: 'esnext',
    sourcemap: true,
    minify: false,
    emptyOutDir: false
  },
  optimizeDeps: {
    exclude: ['@xenova/transformers']
  }
});
