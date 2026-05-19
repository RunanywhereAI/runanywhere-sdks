import { test, expect } from '@playwright/test';
import { resolve } from 'node:path';

const shouldRun = process.env.RA_RUN_SPEECH_E2E === '1';

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
      stt: { supportsProtoSTT(): boolean };
      tts: { supportsProtoTTS(): boolean };
      vad: { supportsProtoVAD(): boolean };
      rag: {
        availability(): {
          available: boolean;
          source: string;
          reason: string;
          missingExports: string[];
        };
      };
    };
  }
}

test.describe('Web SDK backend readiness', () => {
  test.skip(!shouldRun, 'Speech/RAG E2E is opt-in (set RA_RUN_SPEECH_E2E=1); needs the racommons-onnx-sherpa.wasm artifact.');
  test('registers ONNX/Sherpa and exposes speech plus RAG native exports', async ({ page }) => {
    const consoleErrors: string[] = [];
    const pageErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });
    page.on('pageerror', (err) => pageErrors.push(err.message));

    await page.goto('/');
    await page.waitForFunction(
      () => {
        const snap = window.__RUNANYWHERE_AI_READY__;
        return !!snap && (snap.state === 'interactive' || snap.state === 'error');
      },
      null,
      { timeout: 60_000 },
    );

    const readiness = await page.evaluate(() => window.__RUNANYWHERE_AI_READY__);
    expect(readiness?.state, `readiness error: ${readiness?.state}`).not.toBe('error');
    await page.waitForFunction(() => !!window.__RUNANYWHERE_SDK__?.isInitialized, null, {
      timeout: 30_000,
    });

    const result = await page.evaluate(async ({ repoRoot }) => {
      const onnxPath = `/@fs${repoRoot}/sdk/runanywhere-web/packages/onnx/src/index.ts`;
      const onnx = await import(/* @vite-ignore */ onnxPath);
      await onnx.ONNX.register();
      const sdk = window.__RUNANYWHERE_SDK__!;
      return {
        stt: sdk.stt.supportsProtoSTT(),
        tts: sdk.tts.supportsProtoTTS(),
        vad: sdk.vad.supportsProtoVAD(),
        rag: sdk.rag.availability(),
      };
    }, { repoRoot: REPO_ROOT });

    expect(result.stt, 'STT proto/component exports should be available').toBe(true);
    expect(result.tts, 'TTS proto/component exports should be available').toBe(true);
    expect(result.vad, 'VAD proto/component exports should be available').toBe(true);
    expect(
      result.rag.missingExports,
      `RAG missing exports: ${result.rag.missingExports.join(', ')}`,
    ).toHaveLength(0);
    expect(
      ['wasm-exports', 'wasm-session', 'provider'].includes(result.rag.source),
      `unexpected RAG source: ${result.rag.source} (${result.rag.reason})`,
    ).toBe(true);

    const fatalErrors = consoleErrors.filter((err) => !err.includes('NO_COLOR'));
    expect(fatalErrors, `unexpected console errors:\n${fatalErrors.join('\n')}`).toHaveLength(0);
    expect(pageErrors, `page errors:\n${pageErrors.join('\n')}`).toHaveLength(0);
  });
});
