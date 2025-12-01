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
      fileName: (format) => format === 'es' ? 'bundle.js' : 'bundle.cjs',
      formats: ['es', 'cjs']
    },
    rollupOptions: {
      external: ['eventemitter3'],
      output: {
        globals: {
          eventemitter3: 'EventEmitter3'
        },
        // Preserve module structure
        preserveModules: false, // Bundle everything into single files
        preserveModulesRoot: 'src'
      }
    },
    target: 'es2020',
    sourcemap: true,
    minify: false // Don't minify library code
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src')
    }
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
