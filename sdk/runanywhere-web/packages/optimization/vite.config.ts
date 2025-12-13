import { defineConfig } from 'vite';
import { resolve } from 'path';

export default defineConfig({
  build: {
    lib: {
      entry: resolve(__dirname, 'src/index.ts'),
      name: 'RunAnywhereOptimization',
      formats: ['es', 'cjs']
    },
    rollupOptions: {
      external: [
        '@runanywhere/core'
      ],
      output: {
        globals: {
          '@runanywhere/core': 'RunAnywhereCore'
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
  }
});
