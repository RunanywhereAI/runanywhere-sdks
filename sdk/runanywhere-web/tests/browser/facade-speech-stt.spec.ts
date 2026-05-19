/**
 * Facade STT end-to-end test via the unified ONNX/Sherpa WASM.
 *
 * Drives `RunAnywhere.transcribe(samples)` against a real Whisper Tiny
 * (English) model:
 *
 *   1. Register the example app's model catalog.
 *   2. Download the `sherpa-onnx-whisper-tiny.en` tarball via the V2
 *      download orchestrator. Extracted into the RACommons MEMFS at
 *      `/opfs/RunAnywhere/Models/Sherpa/<id>/<id>/`.
 *   3. `ONNX.register()` loads `racommons-onnx-sherpa.wasm` and
 *      registers the ONNX + Sherpa vtables with the plugin registry.
 *   4. `RunAnywhere.transcribe(samples, { modelPath })` dispatches
 *      through the proto-byte STT adapter into the registered Sherpa
 *      backend, which constructs `_SherpaOnnxCreateOfflineRecognizer`
 *      and returns the decoded text.
 *   5. Assert the output `text` field is a string (Whisper on a 1 s
 *      silence buffer typically returns "" or "[BLANK_AUDIO]"; we do
 *      not assert specific words, only that the call completed
 *      without throwing).
 *
 * Opt-in via `RA_RUN_SPEECH_E2E=1`. Downloads ~120 MB on first run.
 */
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
      modelRegistry: { availability(): unknown; getModel(id: string): unknown };
      downloadModel(input: { modelId: string; pollIntervalMs?: number }): Promise<unknown>;
      modelLifecycle: {
        currentModel(input: { category: number; includeModelMetadata?: boolean }): {
          modelId?: string;
          resolvedPath?: string;
        } | null;
      };
      transcribe(
        audio: Float32Array | Uint8Array,
        options?: { modelPath?: string; modelId?: string; sampleRate?: number },
      ): Promise<{
        text: string;
        durationMs?: number;
      }>;
    };
    __FACADE_STT_RESULT__?: {
      ok: boolean;
      text: string;
      modelPath: string;
      durationMs: number;
      error?: string;
    };
  }
}

test.describe('RunAnywhere.transcribe via unified ONNX/Sherpa WASM', () => {
  test.skip(!shouldRun, 'Speech/RAG E2E is opt-in (set RA_RUN_SPEECH_E2E=1).');
  test.setTimeout(20 * 60 * 1000);

  test('downloads Whisper Tiny EN and transcribes audio end-to-end', async ({ page }) => {
    page.on('pageerror', (err) => console.error('[page error]', err.message));

    await page.goto('/');
    await page.waitForFunction(
      () => {
        const snap = window.__RUNANYWHERE_AI_READY__;
        return !!snap && (snap.state === 'interactive' || snap.state === 'error');
      },
      null,
      { timeout: 60_000 },
    );

    await page.evaluate(async ({ repoRoot }) => {
      try {
        const onnxPath = `/@fs${repoRoot}/sdk/runanywhere-web/packages/onnx/src/index.ts`;
        const catalogPath = `/@fs${repoRoot}/examples/web/RunAnywhereAI/src/services/model-catalog.ts`;
        const onnx = await import(/* @vite-ignore */ onnxPath);
        const catalog = await import(/* @vite-ignore */ catalogPath);

        const registered = catalog.registerModelCatalog();
        if (!registered) {
          throw new Error('Model catalog registration failed.');
        }

        await onnx.ONNX.register();

        const sdk = window.__RUNANYWHERE_SDK__;
        if (!sdk) throw new Error('SDK singleton not exposed');

        const modelId = 'sherpa-onnx-whisper-tiny.en';
        await sdk.downloadModel({ modelId, pollIntervalMs: 500 });

        const current = sdk.modelLifecycle.currentModel({
          category: 12, // MODEL_CATEGORY_SPEECH_RECOGNITION
          includeModelMetadata: true,
        }) ?? { modelId, resolvedPath: '' };
        const modelPath = current.resolvedPath || `/opfs/RunAnywhere/Models/Sherpa/${modelId}/${modelId}`;

        // 1 s of silence — Whisper typically emits empty / "[BLANK_AUDIO]".
        const audio = new Float32Array(16_000);
        const stt = await sdk.transcribe(audio, {
          modelPath,
          modelId,
          sampleRate: 16000,
        });

        window.__FACADE_STT_RESULT__ = {
          ok: true,
          text: stt.text,
          modelPath,
          durationMs: stt.durationMs ?? 0,
        };
      } catch (err) {
        window.__FACADE_STT_RESULT__ = {
          ok: false,
          text: '',
          modelPath: '',
          durationMs: 0,
          error: err instanceof Error ? `${err.name}: ${err.message}` : String(err),
        };
      }
    }, { repoRoot: REPO_ROOT });

    const result = await page.evaluate(() => window.__FACADE_STT_RESULT__);
    expect(result, 'STT result should be set').toBeDefined();
    expect(result?.error, `STT pipeline failed: ${result?.error ?? 'none'}`).toBeUndefined();
    expect(result?.ok, 'pipeline OK').toBe(true);
    expect(typeof result?.text, 'transcript is a string').toBe('string');
    expect(result?.modelPath?.length, 'model path resolved').toBeGreaterThan(0);
  });
});
