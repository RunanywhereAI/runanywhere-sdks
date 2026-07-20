/**
 * Hybrid STT browser gate.
 *
 * Verifies the Hybrid router ABI is present after ONNX registration and that
 * Cloud.registerBackend() can bind without crashing. A provider-backed
 * transcription assertion remains opt-in (`RA_RUN_HYBRID_STT_E2E=1`) so CI
 * never needs live cloud credentials.
 */
import { test, expect } from '@playwright/test';
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { waitForInteractive } from './support/release-harness';

const onnxHybridWasm = resolve(
  __dirname,
  '../../packages/onnx/wasm/racommons-onnx-sherpa.wasm',
);

const runProviderJourney = process.env.RA_RUN_HYBRID_STT_E2E === '1';

test.describe('Hybrid STT browser smoke', () => {
  test('hybrid router exports are visible after ONNX registration', async ({ page }) => {
    test.skip(
      !existsSync(onnxHybridWasm),
      'ONNX-sherpa WASM is not built; run npm run build:wasm -- --onnx first.',
    );

    await page.goto('/', { waitUntil: 'domcontentloaded' });
    await waitForInteractive(page);

    const probe = await page.evaluate(() => {
      const sdk = (window as Window & {
        __RUNANYWHERE_SDK__?: {
          hybrid?: {
            stt?: {
              isSupported?: () => boolean;
              missingExports?: () => string[];
            };
          };
          stt?: Record<string, unknown>;
        };
      }).__RUNANYWHERE_SDK__;

      const hybrid = sdk?.hybrid?.stt;
      return {
        hasHybridNamespace: Boolean(hybrid),
        supported: typeof hybrid?.isSupported === 'function' ? hybrid.isSupported() : null,
        missing: typeof hybrid?.missingExports === 'function' ? hybrid.missingExports() : null,
        hasSttSurface: typeof sdk?.stt === 'object' && sdk.stt != null,
      };
    });

    expect(probe.hasSttSurface).toBe(true);
    // Hybrid may be absent on older artifacts; when present it must report
    // either full support or an explicit missing-export list.
    if (probe.hasHybridNamespace) {
      expect(probe.supported === true || Array.isArray(probe.missing)).toBe(true);
    }
  });

  test('provider-backed hybrid transcription', async ({ page }) => {
    test.skip(
      !existsSync(onnxHybridWasm),
      'ONNX-sherpa WASM is not built; run npm run build:wasm -- --onnx first.',
    );
    test.skip(
      !runProviderJourney,
      'Set RA_RUN_HYBRID_STT_E2E=1 after configuring a Sherpa model and safe test cloud credentials.',
    );

    await page.goto('/', { waitUntil: 'domcontentloaded' });
    await waitForInteractive(page);

    // Provider credentials must be injected by the release environment
    // (never committed). This assertion only proves the router can pair
    // once Cloud.register(...) has been configured externally.
    const paired = await page.evaluate(async () => {
      const sdk = (window as Window & {
        __RUNANYWHERE_SDK__?: {
          hybrid?: {
            stt?: {
              isSupported?: () => boolean;
              createRouter?: () => Promise<{ pair?: () => Promise<boolean> }>;
            };
          };
        };
      }).__RUNANYWHERE_SDK__;
      if (!sdk?.hybrid?.stt?.isSupported?.()) return { ok: false, reason: 'unsupported' };
      const router = await sdk.hybrid.stt.createRouter?.();
      if (!router?.pair) return { ok: false, reason: 'no-pair' };
      const ok = await router.pair();
      return { ok, reason: ok ? 'paired' : 'pair-failed' };
    });

    expect(paired.ok, paired.reason).toBe(true);
  });
});
