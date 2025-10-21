import { defineConfig } from 'vite';
import { resolve } from 'path';

export default defineConfig({
  build: {
    lib: {
      entry: resolve(__dirname, 'src/index.ts'),
      name: 'RunAnywhereWorkers',
      formats: ['es', 'cjs']
    },
    rollupOptions: {
      external: [
        '@runanywhere/core',
        '@runanywhere/transcription',
        '@runanywhere/voice',
        '@ricky0123/vad-web',
        '@xenova/transformers'
      ],
      output: {
        globals: {
          '@runanywhere/core': 'RunAnywhereCore',
          '@runanywhere/transcription': 'RunAnywhereTranscription',
          '@runanywhere/voice': 'RunAnywhereVoice'
        }
      }
    },
    target: 'es2022',
    outDir: 'dist',
    sourcemap: true,
    emptyOutDir: true
  },
  define: {
    'process.env.NODE_ENV': JSON.stringify('production')
  },
  worker: {
    format: 'es'
  }
});
