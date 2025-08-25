import { defineConfig } from 'vite';
import { resolve } from 'path';

export default defineConfig({
  build: {
    lib: {
      entry: resolve(__dirname, 'src/stt.worker.ts'),
      name: 'STTWorker',
      formats: ['es'],
      fileName: () => 'stt.worker.js'
    },
    rollupOptions: {
      external: [],
      output: {
        format: 'es',
        inlineDynamicImports: true
      }
    },
    outDir: 'dist',
    emptyOutDir: false,
    sourcemap: false,
    minify: false
  },
  optimizeDeps: {
    include: ['@huggingface/transformers']
  }
});
