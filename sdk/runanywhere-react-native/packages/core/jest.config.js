/**
 * Jest config for @runanywhere/core unit tests.
 *
 * Mirrors the Swift / Kotlin / Web per-SDK test runners so the cross-SDK
 * matrix has a real RN test surface. Tests live under `tests/unit/` so
 * the production `tsconfig.json` (which only includes `src/**`) doesn't
 * pick them up; the dedicated `tsconfig.test.json` extends the base for
 * type-checking the tests themselves.
 *
 * Run from `sdk/runanywhere-react-native/packages/core`:
 *   yarn test
 *
 * The runner uses ts-jest in the Node environment — the smoke tests
 * cover pure-TS helpers (`SDKException`, `ProtoBytes`, `ProtoWire`)
 * that have no React Native or Nitro runtime dependency.
 */

module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  rootDir: '.',
  roots: ['<rootDir>/tests/unit'],
  testMatch: ['<rootDir>/tests/unit/**/*.test.ts'],
  moduleFileExtensions: ['ts', 'js', 'json'],
  transform: {
    '^.+\\.ts$': [
      'ts-jest',
      {
        tsconfig: '<rootDir>/tsconfig.test.json',
      },
    ],
  },
  testTimeout: 15000,
  verbose: true,
};
