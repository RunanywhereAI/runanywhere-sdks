/**
 * Browser VLM E2E.
 *
 * Opt-in because SmolVLM2 pulls a primary GGUF plus mmproj sidecar
 * (~279 MB total). The test drives the same Swift-shaped public path as the
 * example app: download -> RunAnywhere.loadModel -> visionLanguage.loadCurrentModel
 * -> RunAnywhere.processImage.
 */
import { test, expect } from '@playwright/test';

const MODEL_ID = 'smolvlm2-256m-video-instruct-q8_0';
const PRIMARY_URL =
  'https://huggingface.co/ggml-org/SmolVLM2-256M-Video-Instruct-GGUF/resolve/main/SmolVLM2-256M-Video-Instruct-Q8_0.gguf';
const MMPROJ_URL =
  'https://huggingface.co/ggml-org/SmolVLM2-256M-Video-Instruct-GGUF/resolve/main/mmproj-SmolVLM2-256M-Video-Instruct-Q8_0.gguf';

const DOWNLOAD_TIMEOUT_MS = 15 * 60 * 1000;
const LOAD_TIMEOUT_MS = 120_000;
const GENERATE_TIMEOUT_MS = 5 * 60 * 1000;

const DOWNLOAD_STATE_COMPLETED = 5;
const DOWNLOAD_STATE_FAILED = 6;
const DOWNLOAD_STATE_CANCELLED = 7;

const shouldRunVLMEndToEnd = process.env.RA_RUN_VLM_E2E === '1';

interface AppReadinessSnapshot {
  ready: boolean;
  state: 'booting' | 'initializing-sdk' | 'building-shell' | 'interactive' | 'error';
  sdk: 'initializing' | 'ready' | 'unavailable';
  shellReady: boolean;
}

declare global {
  interface Window {
    __RUNANYWHERE_AI_READY__?: AppReadinessSnapshot;
    __RUNANYWHERE_SDK__?: {
      isInitialized: boolean;
      runtime: {
        active: unknown;
        setAcceleration(mode: 'cpu' | 'webgpu'): Promise<void>;
      };
      modelRegistry: {
        availability(): { status: string };
        getModel(modelId: string): unknown;
        registerModel(info: unknown): boolean;
      };
      downloads: {
        plan(request: Record<string, unknown>): {
          canStart: boolean;
          errorMessage?: string;
        } | null;
        start(request: {
          modelId: string;
          plan: unknown;
          resume: boolean;
          resumeToken: string;
          updateRegistryOnCompletion: boolean;
        }): {
          accepted: boolean;
          taskId: string;
          errorMessage?: string;
        } | null;
        poll(request: { modelId: string; taskId: string }): {
          state: number;
          overallProgress: number;
          errorMessage?: string;
        } | null;
      };
      loadModel(request: {
        modelId: string;
        forceReload: boolean;
        validateAvailability: boolean;
      }): Promise<{
        success: boolean;
        errorMessage?: string;
      } | null>;
      visionLanguage: {
        isModelLoaded: boolean;
        loadCurrentModel(): Promise<void>;
      };
      processImage(image: unknown, options: unknown): Promise<{
        text: string;
        completionTokens: number;
      }>;
    };
  }
}

function syntheticImage(): {
  rawRgb: Uint8Array;
  width: number;
  height: number;
  format: number;
  mediaType: string;
  name: string;
  sizeBytes: number;
  metadata: Record<string, string>;
} {
  const width = 1;
  const height = 1;
  const rawRgb = new Uint8Array(width * height * 3);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const offset = (y * width + x) * 3;
      rawRgb[offset] = 255;
      rawRgb[offset + 1] = 0;
      rawRgb[offset + 2] = 0;
    }
  }
  return {
    rawRgb,
    width,
    height,
    format: 4,
    mediaType: 'image/rgb',
    name: 'synthetic-red-pixel',
    sizeBytes: rawRgb.byteLength,
    metadata: {},
  };
}

async function withTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number,
  label: string,
): Promise<T> {
  let timeout: ReturnType<typeof setTimeout> | null = null;
  try {
    return await Promise.race([
      promise,
      new Promise<T>((_, reject) => {
        timeout = setTimeout(() => reject(new Error(label)), timeoutMs);
      }),
    ]);
  } finally {
    if (timeout) clearTimeout(timeout);
  }
}

test.describe('Web SDK VLM end-to-end', () => {
  test.skip(
    !shouldRunVLMEndToEnd,
    'VLM E2E is opt-in (set RA_RUN_VLM_E2E=1). SmolVLM2 primary+mmproj is ~279 MB.',
  );

  test.setTimeout(DOWNLOAD_TIMEOUT_MS + LOAD_TIMEOUT_MS + GENERATE_TIMEOUT_MS + 30_000);

  test('downloads SmolVLM2, loads primary+mmproj, and processes an image', async ({ page }) => {
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

    await page.waitForFunction(() => !!window.__RUNANYWHERE_SDK__, null, { timeout: 10_000 });
    await page.waitForFunction(
      () => !!window.__RUNANYWHERE_SDK__?.isInitialized && window.__RUNANYWHERE_SDK__?.runtime.active !== null,
      null,
      { timeout: 30_000 },
    );
    await page.evaluate(() => window.__RUNANYWHERE_SDK__!.runtime.setAcceleration('webgpu'));
    await page.waitForFunction(
      () => {
        const active = window.__RUNANYWHERE_SDK__?.runtime.active;
        return active === 'webgpu' || active === 'cpu';
      },
      null,
      { timeout: 30_000 },
    );

    const registered = await page.evaluate(
      ({ modelId, primaryUrl, mmprojUrl }) => {
        const ra = window.__RUNANYWHERE_SDK__!;
        if (ra.modelRegistry.availability().status !== 'available') return false;
        const now = Date.now();
        return ra.modelRegistry.registerModel({
          id: modelId,
          name: 'SmolVLM2 256M Video Instruct Q8_0',
          category: 6,
          format: 1,
          framework: 2,
          downloadUrl: primaryUrl,
          localPath: '',
          downloadSizeBytes: 278_828_032,
          contextLength: 2048,
          supportsThinking: false,
          supportsLora: false,
          description: 'Small vision-language model with primary GGUF and mmproj.',
          source: 1,
          createdAtUnixMs: now,
          updatedAtUnixMs: now,
          memoryRequiredBytes: 420_000_000,
          artifactType: 7,
          multiFile: {
            files: [
              {
                url: primaryUrl,
                filename: 'SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
                relativePath: 'SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
                destinationPath: 'SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
                isRequired: true,
                role: 1,
                sizeBytes: 175_056_352,
              },
              {
                url: mmprojUrl,
                filename: 'mmproj-SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
                relativePath: 'mmproj-SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
                destinationPath: 'mmproj-SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
                isRequired: true,
                role: 3,
                sizeBytes: 103_771_680,
              },
            ],
          },
          expectedFiles: {
            files: [
              {
                url: primaryUrl,
                filename: 'SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
                relativePath: 'SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
                destinationPath: 'SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
                isRequired: true,
                role: 1,
                sizeBytes: 175_056_352,
              },
              {
                url: mmprojUrl,
                filename: 'mmproj-SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
                relativePath: 'mmproj-SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
                destinationPath: 'mmproj-SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
                isRequired: true,
                role: 3,
                sizeBytes: 103_771_680,
              },
            ],
            rootDirectory: modelId,
            requiredPatterns: [
              'SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
              'mmproj-SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
            ],
            optionalPatterns: [],
            description: 'SmolVLM2 primary model and mmproj sidecar',
          },
        });
      },
      { modelId: MODEL_ID, primaryUrl: PRIMARY_URL, mmprojUrl: MMPROJ_URL },
    );
    expect(registered, 'multifile VLM model registration must succeed').toBe(true);

    const startInfo = await page.evaluate((modelId) => {
      const ra = window.__RUNANYWHERE_SDK__!;
      const model = ra.modelRegistry.getModel(modelId);
      const plan = ra.downloads.plan({
        modelId,
        model,
        resumeExisting: false,
        availableStorageBytes: 0,
        allowMeteredNetwork: true,
        storageNamespace: '',
        validateExistingBytes: false,
        verifyChecksums: false,
        requiredFreeBytesAfterDownload: 0,
      });
      if (!plan || !plan.canStart) {
        return { accepted: false, taskId: '', error: plan?.errorMessage ?? 'plan unavailable' };
      }
      const start = ra.downloads.start({
        modelId,
        plan,
        resume: false,
        resumeToken: '',
        updateRegistryOnCompletion: true,
      });
      return {
        accepted: start?.accepted ?? false,
        taskId: start?.taskId ?? '',
        error: start?.errorMessage ?? '',
      };
    }, MODEL_ID);
    expect(startInfo.accepted, `download start rejected: ${startInfo.error}`).toBe(true);

    const downloadDeadline = Date.now() + DOWNLOAD_TIMEOUT_MS;
    let finalProgress: { state: number; overallProgress: number; errorMessage?: string } | null = null;
    while (Date.now() < downloadDeadline) {
      expect(pageErrors, `page errors during download:\n${pageErrors.join('\n')}`).toHaveLength(0);
      const progress = await page.evaluate(
        ({ modelId, taskId }) => window.__RUNANYWHERE_SDK__?.downloads.poll({ modelId, taskId }) ?? null,
        { modelId: MODEL_ID, taskId: startInfo.taskId },
      );
      if (
        progress &&
        [DOWNLOAD_STATE_COMPLETED, DOWNLOAD_STATE_FAILED, DOWNLOAD_STATE_CANCELLED].includes(progress.state)
      ) {
        finalProgress = progress;
        break;
      }
      await page.waitForTimeout(500);
    }
    expect(finalProgress, 'download must reach a terminal state').not.toBeNull();
    expect(
      finalProgress?.state,
      `download terminal state failed: ${finalProgress?.errorMessage ?? ''}`,
    ).toBe(DOWNLOAD_STATE_COMPLETED);

    const loadResult = await page.evaluate((modelId) => {
      const ra = window.__RUNANYWHERE_SDK__!;
      return ra.loadModel({
        modelId,
        forceReload: true,
        validateAvailability: true,
      });
    }, MODEL_ID);
    expect(loadResult?.success, `loadModel failed: ${loadResult?.errorMessage ?? ''}`).toBe(true);

    await page.evaluate(async () => {
      await window.__RUNANYWHERE_SDK__!.visionLanguage.loadCurrentModel();
    });
    await page.waitForFunction(() => window.__RUNANYWHERE_SDK__?.visionLanguage.isModelLoaded === true, null, {
      timeout: LOAD_TIMEOUT_MS,
    });

    const result = await withTimeout(
      page.evaluate(
        async ({ image, options }) => window.__RUNANYWHERE_SDK__!.processImage(image, options),
        {
          image: syntheticImage(),
          options: {
            prompt: 'Color?',
            maxTokens: 1,
            temperature: 0.2,
            topP: 0.9,
            topK: 1,
            stopSequences: [],
            streamingEnabled: false,
            maxImageSize: 1,
            nThreads: 4,
            useGpu: true,
            modelFamily: 3,
            seed: 0,
            repetitionPenalty: 1.1,
            minP: 0.05,
            emitImageEmbeddings: false,
          },
        },
      ),
      GENERATE_TIMEOUT_MS,
      `RunAnywhere.processImage did not resolve within ${GENERATE_TIMEOUT_MS}ms`,
    );
    expect(result.text.trim().length, 'VLM response text must be non-empty').toBeGreaterThan(0);
    expect(result.completionTokens, 'VLM should emit completion tokens').toBeGreaterThan(0);

    const fatalErrors = consoleErrors.filter((err) => !err.includes('NO_COLOR'));
    expect(fatalErrors, `unexpected console errors:\n${fatalErrors.join('\n')}`).toHaveLength(0);
    expect(pageErrors, `page errors:\n${pageErrors.join('\n')}`).toHaveLength(0);
  });
});
