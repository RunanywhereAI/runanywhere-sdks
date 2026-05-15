import { test, expect } from '@playwright/test';

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

    const result = await page.evaluate(async () => {
      const onnx = await import(
        '/@fs/Users/sanchitmonga/development/ODLM/MONOREPOOO/runanywhere-sdks3/runanywhere-sdks-main/sdk/runanywhere-web/packages/onnx/src/index.ts'
      );
      await onnx.ONNX.register();
      const sdk = window.__RUNANYWHERE_SDK__!;
      return {
        stt: sdk.stt.supportsProtoSTT(),
        tts: sdk.tts.supportsProtoTTS(),
        vad: sdk.vad.supportsProtoVAD(),
        rag: sdk.rag.availability(),
      };
    });

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
