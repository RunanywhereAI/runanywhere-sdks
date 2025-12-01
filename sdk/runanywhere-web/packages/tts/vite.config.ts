import { defineConfig } from 'vite';

export default defineConfig({
  build: {
    lib: {
      entry: 'src/index.ts',
      name: 'RunAnywhereTTS',
      fileName: (format) => `index.${format === 'es' ? 'js' : format}`,
      formats: ['es']
    },
    rollupOptions: {
      external: ['@runanywhere/core', 'eventemitter3'],
      output: {
        globals: {
          '@runanywhere/core': 'RunAnywhereCore',
          'eventemitter3': 'EventEmitter3'
        }
      }
    },
    target: 'es2020',
    minify: false,
    sourcemap: true,
    emptyOutDir: false
  }
});
