import js from '@eslint/js';
import tseslint from 'typescript-eslint';

// Mirrors examples/web/RunAnywhereAI/eslint.config.mjs so one habit set covers
// both example apps, plus the Electron-specific process boundaries.
export default tseslint.config(
  {
    ignores: ['out/**', 'dist/**', 'node_modules/**', 'src/**/*.d.ts'],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['src/**/*.ts', 'assets/**/*.ts'],
    languageOptions: {
      parserOptions: {
        // Three projects: a rule that needs type information has to be able to
        // resolve a file in whichever process it belongs to.
        project: ['./tsconfig.main.json', './tsconfig.preload.json', './tsconfig.renderer.json'],
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      '@typescript-eslint/consistent-type-imports': 'error',
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-floating-promises': 'error',
      '@typescript-eslint/no-misused-promises': 'error',
      '@typescript-eslint/no-unnecessary-condition': 'error',
      '@typescript-eslint/switch-exhaustiveness-check': 'error',
      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          args: 'all',
          argsIgnorePattern: '^_',
          caughtErrorsIgnorePattern: '^_',
          destructuredArrayIgnorePattern: '^_',
          varsIgnorePattern: '^_',
        },
      ],
      // Renderer logs must route through the app logger, which forwards to the
      // main-side file log; a bare console.log is invisible in a packaged build.
      'no-console': 'error',
      eqeqeq: ['error', 'always', { null: 'ignore' }],
      'no-restricted-globals': [
        'error',
        { name: 'require', message: 'Use ESM imports; the renderer has no require.' },
      ],
    },
  },
  {
    // The renderer is browser-only. It may never reach for Electron or Node —
    // everything it needs comes over the typed contextBridge surfaces.
    files: ['src/renderer/**/*.ts'],
    rules: {
      'no-restricted-imports': [
        'error',
        {
          paths: [
            {
              name: 'electron',
              message:
                'The renderer must not import electron. Add the capability to the preload bridge (src/preload) and call it through window.runanywhere / window.appStore.',
            },
          ],
          patterns: [
            {
              group: ['node:*', 'fs', 'path', 'os', 'child_process'],
              message: 'Node built-ins are not available in the renderer. Do it in main and expose it over IPC.',
            },
            {
              group: ['**/main/**'],
              message: 'The renderer must not import main-process modules. Share code through src/shared instead.',
            },
          ],
        },
      ],
    },
  },
  {
    // Main and preload are the only places allowed to touch Electron and Node.
    // The self-test writes to stdout on purpose: it is a CLI contract.
    files: ['src/main/**/*.ts', 'src/preload/**/*.ts', 'assets/**/*.ts'],
    rules: {
      'no-restricted-globals': 'off',
    },
  },
  {
    files: ['src/main/selftest.ts', 'assets/**/*.ts'],
    rules: {
      'no-console': 'off',
    },
  },
);
