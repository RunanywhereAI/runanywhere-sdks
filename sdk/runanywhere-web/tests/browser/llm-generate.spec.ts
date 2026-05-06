/**
 * Browser LLM E2E — Wave 3e WEB-09.
 *
 * Drives a full download → load → `generateStream` flow on the example app
 * using SmolLM2-360M Q8_0 (~400 MB), then asserts the stream yields at least
 * one token and terminates with a structured result.
 *
 * Opt-in gate: the SmolLM2 download is large and pulls from Hugging Face,
 * so this spec only runs when `RA_RUN_LLM_E2E=1` is set in the environment.
 * Without the flag it becomes a no-op `test.skip(...)` so `npm run test:browser`
 * stays hermetic on fresh checkouts and in CI. The "skip CI wiring" direction
 * from Wave 3e means we ship the file now and wire a dedicated workflow later.
 *
 * Running locally:
 *   cd sdk/runanywhere-web
 *   ./scripts/build-web.sh --build-wasm --llamacpp   # ensure WASM is built
 *   cd ../../examples/web/RunAnywhereAI && npm install && npm run dev &
 *   cd -
 *   RA_RUN_LLM_E2E=1 npm run test:browser -- tests/browser/llm-generate.spec.ts
 *
 * Independent of WEB-01-VENDOR: this spec only exercises the llamacpp backend.
 * STT/TTS/VAD E2E tests are blocked on Sherpa-ONNX WASM vendoring.
 */
import { test, expect } from '@playwright/test';

// Catalog id from `examples/web/RunAnywhereAI/src/services/model-catalog.ts`.
// Size ~400 MB — too large for CI without a dedicated harness; gated via
// RA_RUN_LLM_E2E=1.
const MODEL_ID = 'smollm2-360m-q8_0';
const PROMPT = 'Say hi in one word.';

// Total time budget: WASM cold-start + 400 MB HTTP download + model load +
// generation. The download dominates. Kept wide so noisy networks don't flake.
const DOWNLOAD_TIMEOUT_MS = 10 * 60 * 1000; // 10 minutes
const LOAD_TIMEOUT_MS = 60_000;
const GENERATE_TIMEOUT_MS = 90_000;

// Matches main.ts readiness snapshot published on window.
interface AppReadinessSnapshot {
  ready: boolean;
  state: 'booting' | 'initializing-sdk' | 'building-shell' | 'interactive' | 'error';
  sdk: 'initializing' | 'ready' | 'unavailable';
  shellReady: boolean;
}

declare global {
  // eslint-disable-next-line @typescript-eslint/consistent-type-definitions
  interface Window {
    __RUNANYWHERE_AI_READY__?: AppReadinessSnapshot;
    __RUNANYWHERE_SDK__?: {
      version: string;
      isInitialized: boolean;
      runtime: { active: unknown };
      modelRegistry: {
        availability(): { status: string };
        register(info: unknown): boolean;
      };
      modelLifecycle: {
        load(request: { modelId: string; forceReload: boolean; validateAvailability: boolean }): {
          success: boolean;
          errorMessage?: string;
        } | null;
      };
      downloads: {
        plan(request: Record<string, unknown>): {
          canStart: boolean;
          errorMessage?: string;
        } | null;
        start(request: { modelId: string; plan: unknown; resume: boolean; resumeToken: string; updateRegistryOnCompletion: boolean }): {
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
      generateStream(
        prompt: string,
        options: { maxTokens?: number },
      ): Promise<{
        stream: AsyncIterable<string>;
        result: Promise<unknown>;
        cancel: () => void;
      }>;
    };
  }
}

// Proto enum values mirror @runanywhere/proto-ts/download_service DownloadState.
// Duplicated here so the spec does not need to import the workspace types.
const DOWNLOAD_STATE_COMPLETED = 5;
const DOWNLOAD_STATE_FAILED = 6;
const DOWNLOAD_STATE_CANCELLED = 7;

const shouldRunLLMEndToEnd = process.env.RA_RUN_LLM_E2E === '1';

test.describe('Web SDK LLM end-to-end', () => {
  test.skip(
    !shouldRunLLMEndToEnd,
    'LLM E2E is opt-in (set RA_RUN_LLM_E2E=1). SmolLM2-360M is ~400 MB.',
  );

  // The download + inference budget needs to cover the full pipeline.
  test.setTimeout(DOWNLOAD_TIMEOUT_MS + LOAD_TIMEOUT_MS + GENERATE_TIMEOUT_MS + 30_000);

  test('downloads SmolLM2-360M, loads it, and streams tokens from generateStream', async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });

    await page.goto('/');

    // Wait for the example app shell + SDK init to settle.
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

    // SDK singleton must be on window and backend must have registered the
    // WASM module (`runtime.active` becomes non-null in LlamaCppBridge).
    await page.waitForFunction(() => !!window.__RUNANYWHERE_SDK__, null, { timeout: 10_000 });
    const backendReady = await page.evaluate(() => {
      const ra = window.__RUNANYWHERE_SDK__!;
      return {
        isInitialized: ra.isInitialized,
        hasRuntimeActive: ra.runtime.active !== null,
        registryStatus: ra.modelRegistry.availability().status,
      };
    });
    expect(backendReady.isInitialized, 'SDK phase 1 initialize() must have completed').toBe(true);
    expect(
      backendReady.hasRuntimeActive,
      'LlamaCPP backend must have registered (rebuild WASM via ./scripts/build-web.sh --build-wasm --llamacpp)',
    ).toBe(true);
    expect(
      backendReady.registryStatus,
      'Proto model-registry adapter must be installed by the WASM backend',
    ).toBe('available');

    // Register the model catalog (chat tab does this on activation; the
    // E2E spec drives it explicitly so we do not depend on DOM side-effects).
    const catalogOk = await page.evaluate((modelId) => {
      // The example app exports registerModelCatalog() via its services
      // module. We cannot import from the test context, so we register the
      // single SmolLM2 entry inline — duplicating only the fields the proto
      // registry consumes (ModelInfo shape mirrored from model-catalog.ts).
      const ra = window.__RUNANYWHERE_SDK__!;
      const now = Date.now();
      const info = {
        id: modelId,
        name: 'SmolLM2 360M Q8_0',
        // Proto enum values (ModelCategory.MODEL_CATEGORY_LANGUAGE = 1,
        // ModelFormat.MODEL_FORMAT_GGUF = 1,
        // InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP = 1,
        // ModelSource.MODEL_SOURCE_REMOTE = 1). Duplicated so the spec does
        // not import proto-ts.
        category: 1,
        format: 1,
        framework: 1,
        downloadUrl:
          'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
        localPath: '',
        downloadSizeBytes: 400_000_000,
        contextLength: 2048,
        supportsThinking: false,
        supportsLora: false,
        description: 'Small instruction-tuned LLM (E2E fixture).',
        source: 1,
        createdAtUnixMs: now,
        updatedAtUnixMs: now,
        memoryRequiredBytes: 500_000_000,
      };
      return ra.modelRegistry.register(info);
    }, MODEL_ID);
    expect(catalogOk, 'model registration with proto registry must succeed').toBe(true);

    // Kick off the download via the Downloads capability (matches the flow
    // exercised by components/model-selection.ts).
    const startInfo = await page.evaluate((modelId) => {
      const ra = window.__RUNANYWHERE_SDK__!;
      const plan = ra.downloads.plan({
        modelId,
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
      if (!start) return { accepted: false, taskId: '', error: 'start returned null' };
      return { accepted: start.accepted, taskId: start.taskId, error: start.errorMessage ?? '' };
    }, MODEL_ID);
    expect(startInfo.accepted, `download start rejected: ${startInfo.error}`).toBe(true);

    // Poll until the download reaches a terminal state. The proto adapter
    // pipes progress from C++ (commons) back into the TS runtime.
    await page.waitForFunction(
      ({ modelId, taskId, completed, failed, cancelled }) => {
        const ra = window.__RUNANYWHERE_SDK__!;
        const progress = ra.downloads.poll({ modelId, taskId });
        if (!progress) return false;
        return (
          progress.state === completed ||
          progress.state === failed ||
          progress.state === cancelled
        );
      },
      {
        modelId: MODEL_ID,
        taskId: startInfo.taskId,
        completed: DOWNLOAD_STATE_COMPLETED,
        failed: DOWNLOAD_STATE_FAILED,
        cancelled: DOWNLOAD_STATE_CANCELLED,
      },
      { timeout: DOWNLOAD_TIMEOUT_MS, polling: 1_000 },
    );

    const finalProgress = await page.evaluate(
      ({ modelId, taskId }) => {
        const ra = window.__RUNANYWHERE_SDK__!;
        return ra.downloads.poll({ modelId, taskId });
      },
      { modelId: MODEL_ID, taskId: startInfo.taskId },
    );
    expect(finalProgress?.state, `download failed: ${finalProgress?.errorMessage ?? ''}`).toBe(
      DOWNLOAD_STATE_COMPLETED,
    );

    // Load the model into the llamacpp backend.
    const loadResult = await page.evaluate((modelId) => {
      const ra = window.__RUNANYWHERE_SDK__!;
      return ra.modelLifecycle.load({
        modelId,
        forceReload: false,
        validateAvailability: true,
      });
    }, MODEL_ID);
    expect(loadResult?.success, `model load failed: ${loadResult?.errorMessage ?? ''}`).toBe(true);

    // Run a short generation via generateStream. We assert:
    //   1. at least one non-empty token is emitted,
    //   2. the result promise resolves (terminal completion event).
    const genResult = await page.evaluate(
      async ({ prompt, maxTokens }) => {
        const ra = window.__RUNANYWHERE_SDK__!;
        const stream = await ra.generateStream(prompt, { maxTokens });
        const tokens: string[] = [];
        const start = performance.now();
        try {
          for await (const token of stream.stream) {
            tokens.push(token);
            // Guard against runaway generation — SmolLM2 with maxTokens=16
            // should terminate quickly, but cap defensively.
            if (tokens.length > 256) break;
          }
          const result = await stream.result;
          return {
            ok: true,
            tokenCount: tokens.length,
            firstToken: tokens[0] ?? '',
            concatenated: tokens.join(''),
            elapsedMs: Math.round(performance.now() - start),
            resultType: typeof result,
            resultNotNull: result !== null && result !== undefined,
          } as const;
        } catch (err) {
          return {
            ok: false,
            error: err instanceof Error ? err.message : String(err),
          } as const;
        }
      },
      { prompt: PROMPT, maxTokens: 16 },
    );

    if (!genResult.ok) {
      throw new Error(`generateStream failed: ${genResult.error}`);
    }
    expect(genResult.tokenCount).toBeGreaterThan(0);
    expect(genResult.concatenated.length).toBeGreaterThan(0);
    expect(genResult.resultNotNull, 'terminal result event must be delivered').toBe(true);

    // No unexpected console errors during the whole run (warnings about WASM
    // not being built are filtered because we already asserted it is loaded).
    const fatalErrors = consoleErrors.filter(
      (err) =>
        !err.includes('WASM') &&
        !err.includes('wasm') &&
        !err.includes('sherpa-onnx') &&
        !err.includes('racommons-llamacpp'),
    );
    expect(fatalErrors, `unexpected console errors:\n${fatalErrors.join('\n')}`).toHaveLength(0);
  });
});
