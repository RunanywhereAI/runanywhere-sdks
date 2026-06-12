// Flat ESLint config for the RunAnywhere React Native example app (ESLint 9+).
// Replaces the legacy `eslintConfig` block in package.json.
//
// `@react-native/eslint-config/flat` already bundles eslint-plugin-react,
// eslint-plugin-react-hooks, eslint-plugin-react-native, the `@react-native`
// plugin, `@typescript-eslint` (parser + plugin), eslint-plugin-jest, and the
// prettier disable-config. We layer the app-specific rules + unused-imports on
// top without re-registering plugins (ESLint flat config rejects duplicate
// plugin definitions).
import reactNativeFlat from '@react-native/eslint-config/flat';
import unusedImportsPlugin from 'eslint-plugin-unused-imports';
import prettierPlugin from 'eslint-plugin-prettier';

export default [
  {
    ignores: [
      'node_modules/**',
      'android/**',
      'ios/**',
      '**/__tests__/**',
      '**/*.test.ts',
      '**/*.test.tsx',
      'babel.config.js',
      'metro.config.js',
      'scripts/**',
      'src/generated/**',
    ],
  },
  ...reactNativeFlat,
  // App-specific overrides for src + entry file. Do NOT re-register the
  // `@typescript-eslint` plugin here — it's already registered by the RN
  // flat preset above, and ESLint flat config errors on duplicate plugin
  // definitions.
  {
    files: ['src/**/*.{ts,tsx}', 'App.tsx'],
    plugins: {
      'unused-imports': unusedImportsPlugin,
      prettier: prettierPlugin,
    },
    rules: {
      'unused-imports/no-unused-imports': 'error',
      'unused-imports/no-unused-vars': [
        'warn',
        {
          vars: 'all',
          varsIgnorePattern: '^_',
          args: 'after-used',
          argsIgnorePattern: '^_',
        },
      ],
      '@typescript-eslint/no-unused-vars': 'off',
      '@typescript-eslint/no-explicit-any': 'warn',
      '@typescript-eslint/consistent-type-imports': [
        'warn',
        {
          prefer: 'type-imports',
          disallowTypeAnnotations: false,
        },
      ],
      '@typescript-eslint/no-require-imports': 'off',
      '@typescript-eslint/no-this-alias': 'warn',
      '@typescript-eslint/no-empty-object-type': 'off',
      '@typescript-eslint/no-non-null-assertion': 'warn',
      'no-console': ['warn', { allow: ['warn', 'error'] }],
      'react/react-in-jsx-scope': 'off',
      'react-native/no-inline-styles': 'warn',
      'prettier/prettier': 'warn',
    },
  },
];
