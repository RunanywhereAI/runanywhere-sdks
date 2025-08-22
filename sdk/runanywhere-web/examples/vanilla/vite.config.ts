import { defineConfig } from 'vite';
import path from 'path';

export default defineConfig({
  server: {
    port: 5173,
    open: true
  },
  resolve: {
    alias: {
      '@runanywhere/core': path.resolve(__dirname, '../../packages/core/src'),
      '@runanywhere/voice': path.resolve(__dirname, '../../packages/voice/src')
    }
  },
  build: {
    target: 'es2020',
    sourcemap: true
  }
});
