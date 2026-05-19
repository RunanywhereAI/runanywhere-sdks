/**
 * Facade TTS end-to-end test via the unified ONNX/Sherpa WASM.
 *
 * Drives `RunAnywhere.synthesize(text)` against a real Piper VITS voice:
 *
 *   1. Register the example app's model catalog.
 *   2. Download the `vits-piper-en_US-lessac-medium` tarball via the V2
 *      download orchestrator (`RunAnywhere.downloadModel`). This goes
 *      through commons HTTP transport + libarchive extraction into the
 *      RACommons MEMFS at `/opfs/RunAnywhere/Models/Sherpa/<id>/<id>/`.
 *   3. `ONNX.register()` loads `racommons-onnx-sherpa.wasm` and
 *      registers the ONNX + Sherpa vtables with the plugin registry.
 *   4. `RunAnywhere.synthesize(text, { voicePath })` dispatches through
 *      the proto-byte TTS adapter into the registered Sherpa backend,
 *      which constructs the VITS `_SherpaOnnxCreateOfflineTts` handle
 *      and returns PCM audio.
 *   5. Assert the output has a sane sample rate, > 100 ms duration,
 *      and non-trivial RMS energy (i.e. real audio was synthesized).
 *
 * Opt-in via `RA_RUN_SPEECH_E2E=1`. Downloads ~60 MB on first run.
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
      synthesize(
        text: string,
        options?: { voicePath?: string; voiceId?: string; speakingRate?: number },
      ): Promise<{
        audioData: Uint8Array;
        audioSizeBytes: number;
        sampleRate: number;
        durationMs: number;
      }>;
    };
    __FACADE_TTS_RESULT__?: {
      ok: boolean;
      sampleRate: number;
      durationMs: number;
      audioBytes: number;
      rms: number;
      voicePath: string;
      error?: string;
    };
  }
}

test.describe('RunAnywhere.synthesize via unified ONNX/Sherpa WASM', () => {
  test.skip(!shouldRun, 'Speech/RAG E2E is opt-in (set RA_RUN_SPEECH_E2E=1).');
  test.setTimeout(15 * 60 * 1000);

  test('downloads VITS Piper voice and synthesizes speech end-to-end', async ({ page }) => {
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
          throw new Error('Model catalog registration failed (no native registry available).');
        }

        await onnx.ONNX.register();

        const sdk = window.__RUNANYWHERE_SDK__;
        if (!sdk) throw new Error('SDK singleton not exposed');

        const modelId = 'vits-piper-en_US-lessac-medium';
        await sdk.downloadModel({ modelId, pollIntervalMs: 500 });

        // Resolve where the SDK extracted the tarball.
        const current = sdk.modelLifecycle.currentModel({
          category: 13, // MODEL_CATEGORY_SPEECH_SYNTHESIS
          includeModelMetadata: true,
        }) ?? { modelId, resolvedPath: '' };
        const voicePath = current.resolvedPath || `/opfs/RunAnywhere/Models/Sherpa/${modelId}/${modelId}`;

        const tts = await sdk.synthesize('Hello from RunAnywhere Web SDK.', {
          voicePath,
          voiceId: modelId,
          speakingRate: 1.0,
        });

        // RMS of the produced PCM16 little-endian audio buffer.
        let rmsAccum = 0;
        let count = 0;
        const view = new DataView(tts.audioData.buffer, tts.audioData.byteOffset, tts.audioData.byteLength);
        for (let i = 0; i + 1 < tts.audioData.byteLength; i += 2) {
          const sample = view.getInt16(i, true) / 32768;
          rmsAccum += sample * sample;
          count += 1;
        }
        const rms = count > 0 ? Math.sqrt(rmsAccum / count) : 0;

        window.__FACADE_TTS_RESULT__ = {
          ok: true,
          sampleRate: tts.sampleRate,
          durationMs: tts.durationMs,
          audioBytes: tts.audioSizeBytes || tts.audioData.byteLength,
          rms,
          voicePath,
        };
      } catch (err) {
        window.__FACADE_TTS_RESULT__ = {
          ok: false,
          sampleRate: 0,
          durationMs: 0,
          audioBytes: 0,
          rms: 0,
          voicePath: '',
          error: err instanceof Error ? `${err.name}: ${err.message}` : String(err),
        };
      }
    }, { repoRoot: REPO_ROOT });

    const result = await page.evaluate(() => window.__FACADE_TTS_RESULT__);
    expect(result, 'TTS result should be set').toBeDefined();
    expect(result?.error, `TTS pipeline failed: ${result?.error ?? 'none'}`).toBeUndefined();
    expect(result?.ok, 'pipeline OK').toBe(true);
    expect(result?.sampleRate, 'sample rate set').toBeGreaterThanOrEqual(16_000);
    expect(result?.durationMs, 'duration > 100 ms').toBeGreaterThan(100);
    expect(result?.audioBytes, 'audio buffer non-empty').toBeGreaterThan(0);
    expect(result?.rms, 'audio RMS > 0 (real speech, not silence)').toBeGreaterThan(0.001);
  });
});
