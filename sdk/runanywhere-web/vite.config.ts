import { defineConfig } from 'vite';
import path from 'path';

export default defineConfig({
  build: {
    target: 'es2020',
    sourcemap: true,
    minify: 'esbuild',
    reportCompressedSize: true,
    chunkSizeWarningLimit: 1000,
  },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: './test/setup.ts',
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      exclude: [
        'node_modules/',
        'test/',
        '*.config.*',
        '**/dist/**'
      ]
    }
  },
  resolve: {
    alias: {
      '@runanywhere/core': path.resolve(__dirname, './packages/core/src'),
      '@runanywhere/voice': path.resolve(__dirname, './packages/voice/src')
    }
  }
});
