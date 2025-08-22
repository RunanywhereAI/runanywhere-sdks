import { defineConfig } from 'vite';
import path from 'path';
import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

export default defineConfig({
  build: {
    lib: {
      entry: path.resolve(__dirname, 'src/index.ts'),
      name: 'RunAnywhereCore',
      fileName: 'index',
      formats: ['es', 'cjs']
    },
    rollupOptions: {
      external: ['eventemitter3'],
      output: {
        globals: {
          eventemitter3: 'EventEmitter3'
        }
      }
    },
    target: 'es2020',
    sourcemap: true,
    minify: false // Don't minify library code
  },
  plugins: [
    {
      name: 'generate-types',
      closeBundle: async () => {
        // Generate type declarations after bundle
        await execAsync('tsc --emitDeclarationOnly');
      }
    }
  ]
});
