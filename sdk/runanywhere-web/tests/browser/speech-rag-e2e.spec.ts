import { test, expect } from '@playwright/test';

const shouldRunSpeechE2E = process.env.RA_RUN_SPEECH_E2E === '1';
const DOWNLOAD_TIMEOUT_MS = 20 * 60 * 1000;

interface AppReadinessSnapshot {
  state: 'booting' | 'initializing-sdk' | 'building-shell' | 'interactive' | 'error';
}

declare global {
  interface Window {
    __RUNANYWHERE_AI_READY__?: AppReadinessSnapshot;
    __RUNANYWHERE_SDK__?: {
      isInitialized: boolean;
      modelRegistry: {
        availability(): unknown;
        getModel(modelId: string): unknown;
      };
      downloadModel(input: { modelId: string; pollIntervalMs?: number }): Promise<unknown>;
      loadModel(input: {
        modelId: string;
        forceReload?: boolean;
        validateAvailability?: boolean;
      }): Promise<{ success: boolean; errorMessage?: string } | null>;
      transcribe(audio: Float32Array, options: Record<string, unknown>): Promise<{ text: string }>;
      synthesize(text: string, options?: Record<string, unknown>): Promise<{
        audioData: Uint8Array;
        audioSizeBytes: number;
        sampleRate: number;
        durationMs: number;
      }>;
      detectVoiceActivity(audio: Float32Array, options?: Record<string, unknown>): Promise<{
        isSpeech: boolean;
      }>;
      rag: {
        createNativeProvider(options?: Record<string, unknown>): unknown;
        setProvider(provider: unknown): void;
      };
      downloads: {
        plan(input: Record<string, unknown>): { canStart: boolean; errorMessage?: string } | null;
        start(input: Record<string, unknown>): {
          accepted: boolean;
          taskId: string;
          errorMessage?: string;
        } | null;
        poll(input: Record<string, unknown>): {
          state: number;
          overallProgress: number;
          errorMessage?: string;
        } | null;
      };
      ragIngest(text: string, metadataJson?: string): Promise<void>;
      ragQuery(question: string, options?: Record<string, unknown>): Promise<{
        answer: string;
        results: unknown[];
      }>;
    };
  }
}

async function bootAndRegisterONNX(page: import('@playwright/test').Page): Promise<void> {
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
  await page.evaluate(async () => {
    const onnx = await import(
      '/@fs/Users/sanchitmonga/development/ODLM/MONOREPOOO/runanywhere-sdks3/runanywhere-sdks-main/sdk/runanywhere-web/packages/onnx/src/index.ts'
    );
    await onnx.ONNX.register();
    const catalog = await import(
      '/@fs/Users/sanchitmonga/development/ODLM/MONOREPOOO/runanywhere-sdks3/runanywhere-sdks-main/examples/web/RunAnywhereAI/src/services/model-catalog.ts'
    );
    const count = catalog.registerModelCatalog();
    if (count === 0) {
      throw new Error(`catalog registration failed: ${JSON.stringify(window.__RUNANYWHERE_SDK__!.modelRegistry.availability())}`);
    }
  });
}

async function downloadAndLoad(page: import('@playwright/test').Page, modelId: string): Promise<void> {
  await page.evaluate(
    async (id) => {
      const sdk = window.__RUNANYWHERE_SDK__!;
      const model = sdk.modelRegistry.getModel(id);
      if (!model) {
        throw new Error(`model metadata for ${id} is not registered`);
      }
      const plan = sdk.downloads.plan({
        modelId: id,
        model,
        resumeExisting: false,
        availableStorageBytes: 2_000_000_000,
        allowMeteredNetwork: true,
        storageNamespace: '',
        validateExistingBytes: false,
        verifyChecksums: false,
        requiredFreeBytesAfterDownload: 0,
      });
      if (!plan?.canStart) {
        throw new Error(`download plan failed for ${id}: ${plan?.errorMessage ?? 'plan unavailable'}`);
      }
      const started = sdk.downloads.start({
        modelId: id,
        plan,
        resume: false,
        resumeToken: '',
        updateRegistryOnCompletion: true,
      });
      if (!started?.accepted) {
        throw new Error(`download start failed for ${id}: ${started?.errorMessage ?? 'start unavailable'}`);
      }
      const terminalStates = new Set([5, 6, 7]);
      const deadline = Date.now() + 20 * 60_000;
      let progress = started.taskId ? sdk.downloads.poll({ modelId: id, taskId: started.taskId }) : null;
      while ((!progress || !terminalStates.has(progress.state)) && Date.now() < deadline) {
        await new Promise((resolve) => setTimeout(resolve, 500));
        progress = sdk.downloads.poll({ modelId: id, taskId: started.taskId });
      }
      if (!progress || progress.state !== 5) {
        throw new Error(`download failed for ${id}: state=${progress?.state ?? 'none'} ${progress?.errorMessage ?? ''}`);
      }
      const loaded = await sdk.loadModel({
        modelId: id,
        forceReload: true,
        validateAvailability: true,
      });
      if (!loaded?.success) {
        throw new Error(loaded?.errorMessage || `loadModel(${id}) failed`);
      }
    },
    modelId,
  );
}

test.describe('Web SDK speech and RAG end-to-end', () => {
  test.skip(!shouldRunSpeechE2E, 'Speech/RAG E2E is opt-in (set RA_RUN_SPEECH_E2E=1).');
  test.setTimeout(DOWNLOAD_TIMEOUT_MS + 5 * 60_000);

  test('runs STT, TTS, VAD, and native RAG through ONNX/Sherpa exports', async ({ page }) => {
    const consoleErrors: string[] = [];
    const pageErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });
    page.on('pageerror', (err) => pageErrors.push(err.message));

    await bootAndRegisterONNX(page);

    await downloadAndLoad(page, 'vits-piper-en_US-lessac-medium');
    const tts = await page.evaluate(async () => (
      window.__RUNANYWHERE_SDK__!.synthesize('Hello from RunAnywhere Web.', {
        speakingRate: 1,
        sampleRate: 0,
      })
    ));
    expect(tts.audioSizeBytes || tts.audioData.length, 'TTS should emit audio bytes').toBeGreaterThan(0);
    expect(tts.sampleRate, 'TTS should report sample rate').toBeGreaterThan(0);
    expect(tts.durationMs, 'TTS should report duration').toBeGreaterThan(0);

    await downloadAndLoad(page, 'all-minilm-l6-v2');
    const rag = await page.evaluate(async () => {
      const sdk = window.__RUNANYWHERE_SDK__!;
      const provider = sdk.rag.createNativeProvider({
        config: {
          embeddingModelId: 'all-minilm-l6-v2',
          llmModelId: '',
          embeddingDimension: 384,
          topK: 2,
          chunkSize: 128,
          persistIndex: false,
        },
      });
      sdk.rag.setProvider(provider);
      await sdk.ragIngest('RunAnywhere Web SDK keeps private AI inference inside the browser.');
      return sdk.ragQuery('Where does Web SDK inference run?', { maxTokens: 16 });
    });
    expect(Array.isArray(rag.results), 'RAG should return retrieval results array').toBe(true);

    await downloadAndLoad(page, 'silero-vad');
    const vad = await page.evaluate(async () => {
      const silence = new Float32Array(16_000);
      return window.__RUNANYWHERE_SDK__!.detectVoiceActivity(silence, {
        config: { sampleRate: 16000 },
        sampleRate: 16000,
      });
    });
    expect(typeof vad.isSpeech).toBe('boolean');

    await downloadAndLoad(page, 'sherpa-onnx-whisper-tiny.en');
    const stt = await page.evaluate(async () => {
      const audio = new Float32Array(16_000);
      return window.__RUNANYWHERE_SDK__!.transcribe(audio, { sampleRate: 16000 });
    });
    expect(typeof stt.text).toBe('string');

    const fatalErrors = consoleErrors.filter((err) => !err.includes('NO_COLOR'));
    expect(fatalErrors, `unexpected console errors:\n${fatalErrors.join('\n')}`).toHaveLength(0);
    expect(pageErrors, `page errors:\n${pageErrors.join('\n')}`).toHaveLength(0);
  });
});
