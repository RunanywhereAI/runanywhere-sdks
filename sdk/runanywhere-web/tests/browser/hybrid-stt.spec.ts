/**
 * Hybrid STT browser gate.
 *
 * A real journey needs a WASM artifact built from the current export list, a
 * downloaded Sherpa model, and a test cloud provider/credential. Keep this
 * smoke stub in the default suite so fresh checkouts explicitly skip instead
 * of claiming hybrid STT coverage without the ONNX-sherpa WASM artifact.
 */
import { test } from '@playwright/test';
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';

const onnxHybridWasm = resolve(
  __dirname,
  '../../packages/onnx/wasm/racommons-onnx-sherpa.wasm',
);

test.describe('Hybrid STT browser smoke', () => {
  test('requires the hybrid router and cloud registration WASM gate', async () => {
    test.skip(
      !existsSync(onnxHybridWasm),
      'ONNX-sherpa WASM is not built; run npm run build:wasm -- --onnx first.',
    );
    test.skip(
      process.env.RA_RUN_HYBRID_STT_E2E !== '1',
      'Set RA_RUN_HYBRID_STT_E2E=1 after configuring a Sherpa model and safe test cloud credentials.',
    );

    // The enabled journey must verify:
    // 1. HybridSttRouter.isSupported() sees every router export.
    // 2. Cloud.registerBackend() succeeds after ONNX.register().
    // 3. Cloud.register(...) configures an online model and the router can
    //    pair it with a downloaded offline Sherpa STT model.
    //
    // Do not add client credentials to this suite. The real provider-backed
    // transcription assertion belongs in the opt-in release environment.
  });
});
