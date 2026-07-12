// Flat ESLint config for RunAnywhere Web SDK (ESLint 9).
// See: https://eslint.org/docs/latest/use/configure/configuration-files
//
// Note: `recommendedTypeChecked` produced 500+ errors dominated by `no-unsafe-*`
// rules that would require invasive type-tightening across the Emscripten/WASM
// bridges (Sherpa-ONNX, llama.cpp). To keep initial scope tractable we use the
// non-type-checked `recommended` preset but explicitly enable the three rules
// that catch real bugs: floating promises, misused promises, and type imports.
import js from '@eslint/js';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  {
    ignores: [
      '**/dist/**',
      '**/wasm/**',
      '**/node_modules/**',
      '**/build/**',
      '**/emsdk/**',
      '**/a.out.js',
      '**/*.d.ts',
      '**/*.test-d.ts',
      '**/__tests__/**',
      // Bundler-facing JS proxy files (re-export TS sources for worker URLs).
      'packages/llamacpp/src/workers/*.js',
    ],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    languageOptions: {
      parserOptions: {
        // Use per-package tsconfigs (one for sources, one for tests) so
        // tests participate in typed-lint without invoking the typescript-
        // eslint project service's `allowDefaultProject` slow path. The
        // explicit project list is finite and bounded — adding a new test
        // file under any covered package's `tests/**` requires no eslint
        // config edit because each tsconfig.test.json `include` already
        // covers `tests/**/*.ts`.
        project: [
          './packages/core/tsconfig.json',
          './packages/core/tsconfig.test.json',
          './packages/llamacpp/tsconfig.json',
          './packages/onnx/tsconfig.json',
        ],
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      // Bug-catching rules that justify type-aware lint on their own.
      '@typescript-eslint/no-floating-promises': 'error',
      '@typescript-eslint/no-misused-promises': 'error',
      '@typescript-eslint/consistent-type-imports': 'error',
      // Allow intentionally unused args/vars when prefixed with `_` (common for
      // Emscripten callbacks where the ABI dictates the signature).
      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          args: 'all',
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          caughtErrorsIgnorePattern: '^_',
          destructuredArrayIgnorePattern: '^_',
        },
      ],
    },
  },
  {
    files: ['packages/core/src/**/*.ts'],
    rules: {
      // Core defines provider-neutral contracts and must never depend on a
      // concrete backend package.
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            '@runanywhere/web-llamacpp',
            '@runanywhere/web-llamacpp/*',
            '@runanywhere/web-onnx',
            '@runanywhere/web-onnx/*',
          ],
        },
      ],
    },
  },
  {
    files: [
      'packages/llamacpp/src/**/*.ts',
      'packages/onnx/src/**/*.ts',
    ],
    rules: {
      // Backends integrate only through the bounded core contract and remain
      // independent of sibling backend implementations.
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            '@runanywhere/web/internal',
            '@runanywhere/web-llamacpp',
            '@runanywhere/web-llamacpp/*',
            '@runanywhere/web-onnx',
            '@runanywhere/web-onnx/*',
          ],
        },
      ],
    },
  },
  {
    // Config/script files outside the typed project — disable type-aware rules.
    files: [
      'eslint.config.mjs',
      'playwright.config.ts',
      'packages/core/src/Infrastructure/AudioCaptureProcessor.js',
      'scripts/**/*.{js,mjs,cjs}',
      'tests/browser/**/*.ts',
    ],
    ...tseslint.configs.disableTypeChecked,
  },
);
