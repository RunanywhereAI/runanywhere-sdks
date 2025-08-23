import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import { resolve } from 'path';

export default defineConfig({
  plugins: [vue()],
  build: {
    lib: {
      entry: resolve(__dirname, 'src/index.ts'),
      name: 'RunAnywhereVue',
      fileName: (format) => format === 'es' ? 'index.esm.js' : 'index.js',
      formats: ['es', 'cjs']
    },
    rollupOptions: {
      external: ['vue', '@runanywhere/core', '@runanywhere/voice'],
      output: {
        globals: {
          vue: 'Vue'
        }
      }
    },
    emptyOutDir: false,
    sourcemap: true
  }
});
