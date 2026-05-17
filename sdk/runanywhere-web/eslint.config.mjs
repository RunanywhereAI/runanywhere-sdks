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
        // Use the TS-ESLint project service so each package's tsconfig.json
        // is resolved automatically across the workspace packages.
        projectService: {
          // typescript-eslint disallows `**` here, so enumerate each
          // unit-test subdirectory explicitly. Add the new directory here
          // when introducing a fresh `tests/unit/<NewDir>/*.test.ts` file
          // — otherwise the typed-lint lane will fail with
          // `Parsing error: ... was not found by the project service`.
          allowDefaultProject: [
            'packages/core/tests/unit/Adapters/*.test.ts',
            'packages/core/tests/unit/Foundation/*.test.ts',
            'packages/core/tests/unit/Public/Extensions/*.test.ts',
            'packages/core/tests/unit/runtime/*.test.ts',
          ],
          // Default cap is 8; we already exceed that across these subdirs.
          // Bump in lockstep when new test files land.
          maximumDefaultProjectFileMatchCount_THIS_WILL_SLOW_DOWN_LINTING: 20,
        },
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
    // Config/script files outside the typed project — disable type-aware rules.
    files: ['eslint.config.mjs', 'scripts/**/*.{js,mjs,cjs}'],
    ...tseslint.configs.disableTypeChecked,
  },
);
