import { defineConfig } from 'vite';
import { resolve } from 'path';

export default defineConfig({
  build: {
    lib: {
      entry: resolve(__dirname, 'src/index.ts'),
      name: 'RunAnywhereAngular',
      fileName: (format) => format === 'es' ? 'index.esm.js' : 'index.js',
      formats: ['es', 'cjs']
    },
    rollupOptions: {
      external: ['@angular/core', '@angular/common', 'rxjs', '@runanywhere/core', '@runanywhere/voice'],
      output: {
        globals: {
          '@angular/core': 'ng.core',
          '@angular/common': 'ng.common',
          'rxjs': 'rxjs'
        }
      }
    },
    emptyOutDir: false,
    sourcemap: true
  }
});
