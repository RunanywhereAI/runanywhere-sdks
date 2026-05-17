/**
 * Facade speech-via-standalone-Sherpa end-to-end test.
 *
 * Proves that `RunAnywhere.detectVoiceActivity(samples)` works without the
 * caller touching any low-level Sherpa C API, after `ONNX.register()`
 * installs the standalone Sherpa speech provider on the V2 facade.
 *
 * Wiring under test:
 *
 *   1. The example app loads the llamacpp backend, which installs the
 *      RACommons WASM module + platform adapter (filesystem callbacks
 *      backed by OPFS / MEMFS).
 *   2. The spec calls `ONNX.register({ skipProtoBytePlugins: true })`,
 *      which installs the `StandaloneSherpaSpeechProvider` on the V2
 *      `SpeechProvider` registry. The proto-byte plugin path is
 *      skipped to keep this test independent of the unified-WASM
 *      Sherpa link (which still hits the function-signature mismatch).
 *   3. The spec stages the bundled v4 `silero_vad.onnx` fixture into
 *      the RACommons MEMFS via the platform adapter's file_write
 *      callback (using `commons.FS.writeFile` directly), then invokes
 *      `RunAnywhere.detectVoiceActivity(audio, { modelPath })`.
 *   4. The facade routes through the speech provider, which mirrors
 *      the model into the standalone Sherpa MEMFS, constructs the
 *      detector, and returns a `VADResult`.
 */
import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const shouldRun = process.env.RA_RUN_SPEECH_E2E === '1';

// Repo root, resolved from this file's location, so the Vite `/@fs/...`
// imports work from any checkout location and in CI. Override with
// `RA_REPO_ROOT` if running against a different layout.
const REPO_ROOT = process.env.RA_REPO_ROOT ?? resolve(__dirname, '..', '..', '..', '..');

const SILERO_VAD_FIXTURE = shouldRun
  ? readFileSync(join(__dirname, 'fixtures', 'silero_vad.onnx'))
  : Buffer.alloc(0);

interface AppReadinessSnapshot {
  state: 'booting' | 'initializing-sdk' | 'building-shell' | 'interactive' | 'error';
}

declare global {
  interface Window {
    __RUNANYWHERE_AI_READY__?: AppReadinessSnapshot;
    __RUNANYWHERE_SDK__?: {
      isInitialized: boolean;
      detectVoiceActivity(
        audio: Float32Array,
        options?: { modelPath?: string; modelId?: string; config?: { sampleRate?: number } },
      ): Promise<{
        isSpeech: boolean;
        confidence?: number;
        durationMs?: number;
      }>;
    };
    __FACADE_VAD_RESULT__?: {
      ok: boolean;
      silenceIsSpeech: boolean;
      noiseIsSpeech: boolean;
      providerInstalled: boolean;
      error?: string;
    };
  }
}

test.describe('RunAnywhere.detectVoiceActivity via standalone Sherpa speech provider', () => {
  test.skip(!shouldRun, 'Speech/RAG E2E is opt-in (set RA_RUN_SPEECH_E2E=1).');
  test.setTimeout(60_000);

  test('dispatches through the speech provider and returns a typed VADResult', async ({ page }) => {
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

    await page.evaluate(
      async ({ vadBytes, repoRoot }) => {
        try {
          const onnxPath = `/@fs${repoRoot}/sdk/runanywhere-web/packages/onnx/src/index.ts`;
          const internalPath = `/@fs${repoRoot}/sdk/runanywhere-web/packages/core/src/internal.ts`;
          const onnx = await import(/* @vite-ignore */ onnxPath);
          const internal = await import(/* @vite-ignore */ internalPath);

          // Install the standalone Sherpa speech provider; skip the
          // unified-WASM proto-byte plugin path so we keep this test
          // independent of the static-link mismatch.
          await onnx.ONNX.register({ skipProtoBytePlugins: true });
          const providerInstalled =
            internal.getSpeechProvider()?.id === 'standalone-sherpa-onnx';

          // Stage the bundled v4 silero_vad.onnx fixture directly into
          // the RACommons MEMFS at /opfs/RunAnywhere/Models/Sherpa/
          // silero-vad/silero_vad.onnx. The speech provider mirrors
          // it into the standalone Sherpa MEMFS automatically.
          const commons = internal.tryRunanywhereModule() as Record<string, unknown> & {
            FS?: {
              mkdirTree?(path: string): void;
              mkdir?(path: string, mode?: number): void;
              writeFile(path: string, data: Uint8Array): void;
            };
          } | null;
          if (!commons?.FS) {
            throw new Error('RACommons module FS not available — did llamacpp register?');
          }
          const stagingDir = '/opfs/RunAnywhere/Models/Sherpa/silero-vad';
          const stagedPath = `${stagingDir}/silero_vad.onnx`;
          if (typeof commons.FS.mkdirTree === 'function') {
            commons.FS.mkdirTree(stagingDir);
          } else if (typeof commons.FS.mkdir === 'function') {
            const parts = stagingDir.split('/').filter((p) => p.length > 0);
            let path = '';
            for (const p of parts) {
              path = `${path}/${p}`;
              try {
                commons.FS.mkdir(path);
              } catch {
                /* exists */
              }
            }
          }
          commons.FS.writeFile(stagedPath, vadBytes);

          const sdk = window.__RUNANYWHERE_SDK__;
          if (!sdk) throw new Error('SDK singleton not exposed');

          // 1 s of silence → expect isSpeech=false.
          const silence = new Float32Array(16_000);
          const silenceResult = await sdk.detectVoiceActivity(silence, {
            modelPath: stagedPath,
            modelId: 'silero-vad',
            config: { sampleRate: 16000 },
          });

          // 1 s of synthesized speech-shaped tone → may or may not be
          // flagged as speech (Silero is trained on real voice, a tone
          // does not always trip the threshold). We only assert the
          // call returns a typed boolean; the silence assertion is the
          // one that proves the model is actually running.
          const tone = new Float32Array(16_000);
          for (let i = 0; i < tone.length; i += 1) {
            tone[i] = Math.sin(2 * Math.PI * 220 * (i / 16_000)) * 0.5;
          }
          const noiseResult = await sdk.detectVoiceActivity(tone, {
            modelPath: stagedPath,
            modelId: 'silero-vad',
            config: { sampleRate: 16000 },
          });

          window.__FACADE_VAD_RESULT__ = {
            ok: true,
            silenceIsSpeech: silenceResult.isSpeech,
            noiseIsSpeech: noiseResult.isSpeech,
            providerInstalled,
          };
        } catch (err) {
          window.__FACADE_VAD_RESULT__ = {
            ok: false,
            silenceIsSpeech: false,
            noiseIsSpeech: false,
            providerInstalled: false,
            error: err instanceof Error ? `${err.name}: ${err.message}` : String(err),
          };
        }
      },
      { vadBytes: new Uint8Array(SILERO_VAD_FIXTURE), repoRoot: REPO_ROOT },
    );

    const result = await page.evaluate(() => window.__FACADE_VAD_RESULT__);
    expect(result, 'facade VAD probe should be set').toBeDefined();
    expect(result?.error, `facade VAD failed: ${result?.error ?? 'none'}`).toBeUndefined();
    expect(result?.ok, 'pipeline OK').toBe(true);
    expect(result?.providerInstalled, 'standalone Sherpa speech provider installed').toBe(true);
    expect(result?.silenceIsSpeech, 'silence should NOT register as speech').toBe(false);
    expect(typeof result?.noiseIsSpeech).toBe('boolean');
  });
});
