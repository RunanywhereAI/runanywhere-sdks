import { defineConfig } from 'vite';
import path from 'path';

export default defineConfig({
  server: {
    port: 5173,
    open: true
  },
  resolve: {
    alias: {
      '@runanywhere/core': path.resolve(__dirname, '../../../sdk/runanywhere-web/packages/core/dist/index.js'),
      '@runanywhere/voice': path.resolve(__dirname, '../../../sdk/runanywhere-web/packages/voice/dist/index.js')
    }
  },
  build: {
    target: 'es2020',
    sourcemap: true
  }
});
