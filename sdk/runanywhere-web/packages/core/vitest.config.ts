// vitest.config.ts — T7.4 Web runner for the cross-SDK streaming harness.
//
// The shared consumers live under `tests/streaming/**` (outside this
// package) and are suffixed `.web.test.ts` so only the Vitest runner in
// this package picks them up — the `.rn.test.ts` siblings belong to the
// React Native Jest harness.
//
// Tests require the C++ producer outputs to be in place:
//   cmake --build build/macos-release --target cancel_producer && \
//     ./build/macos-release/tests/streaming/cancel_parity/cancel_producer
//   cmake --build build/macos-release --target perf_producer && \
//     ./build/macos-release/tests/streaming/perf_bench/perf_producer

import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['../../../../tests/streaming/**/*.web.test.ts'],
    environment: 'node',
    testTimeout: 30_000,
  },
});
