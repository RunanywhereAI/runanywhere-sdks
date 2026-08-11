// Flat ESLint config for RunAnywhere React Native SDK workspaces (ESLint 9+).
// Replaces the legacy `eslintConfig` block in package.json. Applies to the
// all inner packages (core plus backend packages) — ESLint walks up from each
// package's cwd until it finds this file.
//
// See https://eslint.org/docs/latest/use/configure/configuration-files
import js from '@eslint/js';
import tsParser from '@typescript-eslint/parser';
import tsPlugin from '@typescript-eslint/eslint-plugin';
import prettierConfig from 'eslint-config-prettier';

export default [
  {
    ignores: [
      '**/node_modules/**',
      '**/lib/**',
      '**/dist/**',
      '**/build/**',
      '**/nitrogen/generated/**',
      '**/ios/**',
      '**/android/**',
      '**/cpp/**',
      '**/*.d.ts',
    ],
  },
  js.configs.recommended,
  // ts-eslint's flat preset is a 3-entry array: plugin/parser registration,
  // eslint-recommended rule disables (no-undef, no-redeclare, etc. that TS
  // already covers), and the @typescript-eslint/recommended rule set. Spread
  // all three so the legacy `extends: ["plugin:@typescript-eslint/recommended"]`
  // behaviour is preserved.
  ...tsPlugin.configs['flat/recommended'],
  {
    files: ['**/*.{ts,tsx}'],
    languageOptions: {
      parser: tsParser,
      parserOptions: {
        ecmaVersion: 2020,
        sourceType: 'module',
      },
    },
    rules: {
      '@typescript-eslint/no-unused-vars': 'off',
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-require-imports': 'off',
      'no-console': 'error',
      // The flat-config base `recommended` flags `no-unused-vars` independently
      // of the @typescript-eslint variant; the legacy preset turned it off.
      'no-unused-vars': 'off',
    },
  },
  // Apply prettier config last to disable conflicting stylistic rules.
  prettierConfig,
];
