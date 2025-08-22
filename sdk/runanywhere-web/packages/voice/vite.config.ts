import { defineConfig } from 'vite';
import path from 'path';

export default defineConfig({
  build: {
    lib: {
      entry: path.resolve(__dirname, 'src/index.ts'),
      name: 'RunAnywhereVoice',
      fileName: 'index',
      formats: ['es', 'cjs']
    },
    rollupOptions: {
      external: [
        'eventemitter3',
        '@runanywhere/core',
        '@ricky0123/vad-web'
      ],
      output: {
        globals: {
          'eventemitter3': 'EventEmitter3',
          '@runanywhere/core': 'RunAnywhereCore',
          '@ricky0123/vad-web': 'VADWeb'
        }
      }
    },
    target: 'es2020',
    sourcemap: true,
    minify: false
  }
});
