// jest.config.js — T7.4 RN runner for the cross-SDK streaming harness.
//
// The shared consumers live under `tests/streaming/**` (outside this
// package) and are suffixed `.rn.test.ts`; the `.web.test.ts` siblings
// belong to the Web Vitest harness and MUST be excluded to avoid Jest
// tripping on Vitest-only imports (`vitest/describe,it,expect`).
//
// Tests require the C++ producer outputs to be in place:
//   cmake --build build/macos-release --target cancel_producer && \
//     ./build/macos-release/tests/streaming/cancel_parity/cancel_producer
//   cmake --build build/macos-release --target perf_producer && \
//     ./build/macos-release/tests/streaming/perf_bench/perf_producer

/** @type {import('jest').Config} */
module.exports = {
  rootDir: __dirname,
  testEnvironment: 'node',
  // `testMatch` patterns are filtered against files under `roots`; the
  // cross-SDK harness lives outside this package so the repo's
  // `tests/streaming` directory must be added explicitly.
  roots: ['<rootDir>', '<rootDir>/../../../../tests/streaming'],
  testMatch: ['<rootDir>/../../../../tests/streaming/**/*.rn.test.ts'],
  transform: {
    '^.+\\.tsx?$': [
      'ts-jest',
      {
        // The package tsconfig is `composite: true` which ts-jest can't
        // consume directly; feed it an inline override that matches the
        // base config without the composite flag.
        tsconfig: {
          target: 'es2020',
          module: 'commonjs',
          esModuleInterop: true,
          resolveJsonModule: true,
          allowSyntheticDefaultImports: true,
          moduleResolution: 'node',
          strict: false,
          skipLibCheck: true,
        },
        isolatedModules: true,
        diagnostics: false,
      },
    ],
  },
  moduleFileExtensions: ['ts', 'tsx', 'js', 'jsx', 'json'],
};
