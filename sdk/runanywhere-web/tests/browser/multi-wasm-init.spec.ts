/**
 * Multi-WASM initialization smoke test.
 *
 * Verifies the 3-WASM layout produced by Phase P4 of the per-backend
 * modularity work loads cleanly in the browser:
 *
 *   - `@runanywhere/web` core boot wires the commons WASM
 *     (`packages/core/wasm/racommons.{js,wasm}`) into the SDK singleton
 *     via the example app's normal initialization path.
 *   - `@runanywhere/web-llamacpp` `LlamaCPP.register()` loads the
 *     dedicated `packages/llamacpp/wasm/racommons-llamacpp.{js,wasm}`
 *     and registers the unified llama.cpp vtable (LLM + VLM).
 *   - `@runanywhere/web-onnx` `ONNX.register()` loads the dedicated
 *     `packages/onnx/wasm/racommons-onnx-sherpa.{js,wasm}` and
 *     registers the ONNX + Sherpa vtables.
 *
 * No models are loaded — that is covered by the modality-specific specs.
 * Asserts both backend bridges report `isBackendRegistered === true`,
 * no console errors were logged, and reports timing for each WASM load.
 */
import { test, expect } from '@playwright/test';
import { resolve } from 'node:path';

// Repo root, resolved from this file's location, so the Vite `/@fs/...`
// imports work from any checkout location and in CI. Override with
// `RA_REPO_ROOT` if running against a different layout.
const REPO_ROOT = process.env.RA_REPO_ROOT ?? resolve(__dirname, '..', '..', '..', '..');

interface AppReadinessSnapshot {
  state: 'booting' | 'initializing-sdk' | 'building-shell' | 'interactive' | 'error';
}

declare global {
  interface Window {
    __RUNANYWHERE_AI_READY__?: AppReadinessSnapshot;
    __RUNANYWHERE_SDK__?: {
      isInitialized: boolean;
    };
    __MULTI_WASM_RESULT__?: {
      ok: boolean;
      llamacppRegistered: boolean;
      onnxRegistered: boolean;
      llamacppLoadMs: number;
      onnxLoadMs: number;
      error?: string;
    };
  }
}

test.describe('Multi-WASM SDK initialization', () => {
  test.setTimeout(60_000);

  test('loads commons + llamacpp + onnx WASMs independently with no console errors', async ({ page }) => {
    const consoleErrors: string[] = [];
    const pageErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });
    page.on('pageerror', (err) => pageErrors.push(err.message));

    await page.goto('/');

    // Wait for the example app shell to finish initializing the SDK
    // singleton (this loads the commons WASM in the normal init path).
    await page.waitForFunction(() => !!window.__RUNANYWHERE_SDK__?.isInitialized, null, {
      timeout: 15_000,
    });

    await page.evaluate(
      async ({ repoRoot }) => {
        try {
          const llamacppPath = `/@fs${repoRoot}/sdk/runanywhere-web/packages/llamacpp/src/index.ts`;
          const onnxPath = `/@fs${repoRoot}/sdk/runanywhere-web/packages/onnx/src/index.ts`;

          const t0 = performance.now();
          const llamacpp = await import(/* @vite-ignore */ llamacppPath);
          await llamacpp.LlamaCPP.register();
          const t1 = performance.now();
          const llamacppRegistered = !!(llamacpp.LlamaCPP?.isRegistered ?? false);

          const onnx = await import(/* @vite-ignore */ onnxPath);
          await onnx.ONNX.register();
          const t2 = performance.now();
          const onnxRegistered = !!(onnx.ONNX?.isRegistered ?? false);

          window.__MULTI_WASM_RESULT__ = {
            ok: true,
            llamacppRegistered,
            onnxRegistered,
            llamacppLoadMs: Math.round(t1 - t0),
            onnxLoadMs: Math.round(t2 - t1),
          };
        } catch (err) {
          window.__MULTI_WASM_RESULT__ = {
            ok: false,
            llamacppRegistered: false,
            onnxRegistered: false,
            llamacppLoadMs: 0,
            onnxLoadMs: 0,
            error: err instanceof Error ? `${err.name}: ${err.message}` : String(err),
          };
        }
      },
      { repoRoot: REPO_ROOT },
    );

    const result = await page.evaluate(() => window.__MULTI_WASM_RESULT__);
    expect(result, 'multi-WASM result should be set').toBeDefined();
    expect(result?.error, `multi-WASM init failed: ${result?.error ?? 'none'}`).toBeUndefined();
    expect(result?.ok, 'pipeline OK').toBe(true);

    console.log(
      `[multi-wasm-init] llamacpp load+register=${result?.llamacppLoadMs}ms, ` +
      `onnx load+register=${result?.onnxLoadMs}ms`,
    );

    expect(result?.llamacppRegistered, 'LlamaCPP backend reports registered').toBe(true);
    expect(result?.onnxRegistered, 'ONNX/Sherpa backend reports registered').toBe(true);

    const fatalErrors = consoleErrors.filter(
      (err) => !err.includes('NO_COLOR')
        && !err.includes('Failed to load resource')
        // Credential-less local initialization intentionally defers the
        // assignment fetch. The SDK surfaces that as an expected warning;
        // backend registration itself is asserted above.
        && !err.includes('model assignment base URL is not configured'),
    );
    expect(fatalErrors, `unexpected console errors:\n${fatalErrors.join('\n')}`).toHaveLength(0);
    expect(pageErrors, `page errors:\n${pageErrors.join('\n')}`).toHaveLength(0);
  });
});
