import { defineConfig } from 'vite';

export default defineConfig({
  build: {
    lib: {
      entry: 'src/worker.ts',
      name: 'STTWhisperWebWorker',
      fileName: 'worker',
      formats: ['es']
    },
    rollupOptions: {
      output: {
        format: 'es'
      }
    },
    target: 'esnext',
    // Default to dist-worker to avoid conflicts with TypeScript build
    outDir: 'dist-worker'
  },
  define: {
    'process.env': {}
  }
});
