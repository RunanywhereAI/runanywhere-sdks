import { defineConfig } from 'vite';
import { resolve } from 'path';

export default defineConfig({
  build: {
    lib: {
      entry: resolve(__dirname, 'src/index.ts'),
      name: 'RunAnywhereLLM',
      fileName: 'index',
      formats: ['es']
    },
    rollupOptions: {
      external: [
        '@runanywhere/core',
        'eventsource-parser',
        'eventemitter3'
      ],
      output: {
        globals: {
          '@runanywhere/core': 'RunAnywhereCore',
          'eventsource-parser': 'EventSourceParser',
          'eventemitter3': 'EventEmitter3'
        }
      }
    },
    target: 'esnext',
    sourcemap: true,
    minify: false,
    emptyOutDir: false
  }
});
