import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

export default defineConfig({
  plugins: [vue()],
  server: {
    port: 5174
  },
  resolve: {
    alias: {
      '@': '/src'
    }
  }
});
