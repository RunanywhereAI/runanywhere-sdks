/**
 * Standalone Sherpa-ONNX WASM smoke test.
 *
 * Validates the proven `main`-branch path: loads the upstream-built
 * `sherpa-onnx-wasm-nodejs` Emscripten module (in-tree at
 * `packages/onnx/wasm/sherpa/sherpa-onnx-glue.js`, post-processed by
 * `wasm/scripts/patch-sherpa-glue.js`) and confirms the C API exports
 * (`_SherpaOnnxCreateOfflineTts`, `_SherpaOnnxOfflineTtsSampleRate`, …)
 * are present and do not throw a `RuntimeError: function signature
 * mismatch` at module init.
 *
 * The current V2 unified `racommons-llamacpp.wasm` artifact still hits
 * the JS-emulated exception trampoline mismatch on
 * `Ort::InferenceSession::ConstructorCommon`. This spec verifies that
 * the standalone Sherpa module — which does its own consistent
 * Emscripten link of ORT + Sherpa — runs cleanly in the browser and is
 * the right path to wire speech through.
 */
import { test, expect } from '@playwright/test';

interface AppReadinessSnapshot {
  state: 'booting' | 'initializing-sdk' | 'building-shell' | 'interactive' | 'error';
}

declare global {
  interface Window {
    __RUNANYWHERE_AI_READY__?: AppReadinessSnapshot;
    __SHERPA_PROBE__?: {
      moduleLoaded: boolean;
      hasOfflineTtsCreate: boolean;
      hasVadCreate: boolean;
      hasOfflineRecognizerCreate: boolean;
      hasFs: boolean;
      hasMalloc: boolean;
      error?: string;
    };
  }
}

test('standalone sherpa-onnx WASM loads and exposes C API exports', async ({ page }) => {
  const consoleErrors: string[] = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });

  await page.goto('/');
  await page.waitForFunction(
    () => {
      const snap = window.__RUNANYWHERE_AI_READY__;
      return !!snap && (snap.state === 'interactive' || snap.state === 'error');
    },
    null,
    { timeout: 60_000 },
  );

  await page.evaluate(async () => {
    try {
      const glueModule = await import(
        '/@fs/Users/sanchitmonga/development/ODLM/MONOREPOOO/runanywhere-sdks3/runanywhere-sdks-main/sdk/runanywhere-web/packages/onnx/wasm/sherpa/sherpa-onnx-glue.js'
      );
      const createModule = (glueModule.default ?? glueModule) as (
        overrides?: Record<string, unknown>,
      ) => Promise<Record<string, unknown>>;

      const wasmUrl = new URL(
        '/@fs/Users/sanchitmonga/development/ODLM/MONOREPOOO/runanywhere-sdks3/runanywhere-sdks-main/sdk/runanywhere-web/packages/onnx/wasm/sherpa/sherpa-onnx.wasm',
        window.location.href,
      );
      const wasmResponse = await fetch(wasmUrl.href);
      const wasmBinary = await wasmResponse.arrayBuffer();

      const module = await createModule({
        noFSInit: true,
        print: () => undefined,
        printErr: () => undefined,
        wasmBinary,
        locateFile: (path: string) => {
          if (path.endsWith('.wasm')) return wasmUrl.href;
          return path;
        },
        instantiateWasm: (
          imports: WebAssembly.Imports,
          receiveInstance: (instance: WebAssembly.Instance, module: WebAssembly.Module) => void,
        ) => {
          WebAssembly.instantiate(wasmBinary, imports).then((result) => {
            try {
              receiveInstance(result.instance, result.module);
            } catch {
              // Patch 6 in patch-sherpa-glue.js wraps this in addRunDependency,
              // so receiveInstance can return after the run dependency clears.
            }
          }).catch((error) => {
            throw error;
          });
          return {};
        },
      });

      const m = module as Record<string, unknown>;
      // Emscripten 5.x exposes filesystem helpers as standalone
      // FS_createDataFile/FS_createPath/FS_unlink rather than a single
      // `module.FS` namespace. SherpaONNXBridge uses these to stage model
      // files into MEMFS before invoking the C API.
      window.__SHERPA_PROBE__ = {
        moduleLoaded: true,
        hasOfflineTtsCreate: typeof m._SherpaOnnxCreateOfflineTts === 'function',
        hasVadCreate: typeof m._SherpaOnnxCreateVoiceActivityDetector === 'function',
        hasOfflineRecognizerCreate: typeof m._SherpaOnnxCreateOfflineRecognizer === 'function',
        hasFs: typeof m.FS_createDataFile === 'function'
          && typeof m.FS_createPath === 'function'
          && typeof m.FS_unlink === 'function',
        hasMalloc: typeof m._malloc === 'function',
      };
    } catch (error) {
      window.__SHERPA_PROBE__ = {
        moduleLoaded: false,
        hasOfflineTtsCreate: false,
        hasVadCreate: false,
        hasOfflineRecognizerCreate: false,
        hasFs: false,
        hasMalloc: false,
        error: error instanceof Error
          ? `${error.name}: ${error.message}\n${error.stack ?? ''}`
          : String(error),
      };
    }
  });

  const probe = await page.evaluate(() => window.__SHERPA_PROBE__);

  expect(probe, 'probe should be set').toBeDefined();
  expect(probe?.error, `module load error: ${probe?.error ?? 'none'}`).toBeUndefined();
  expect(probe?.moduleLoaded, 'sherpa standalone WASM module loads').toBe(true);
  expect(probe?.hasOfflineTtsCreate, '_SherpaOnnxCreateOfflineTts is exported').toBe(true);
  expect(probe?.hasVadCreate, '_SherpaOnnxCreateVoiceActivityDetector is exported').toBe(true);
  expect(probe?.hasOfflineRecognizerCreate, '_SherpaOnnxCreateOfflineRecognizer is exported').toBe(true);
  expect(probe?.hasFs, 'FS namespace available for staging model files').toBe(true);
  expect(probe?.hasMalloc, '_malloc available for argument marshalling').toBe(true);

  const fatalErrors = consoleErrors.filter(
    (err) => !err.includes('NO_COLOR') && !err.includes('Failed to load resource'),
  );
  expect(fatalErrors, `unexpected console errors:\n${fatalErrors.join('\n')}`).toHaveLength(0);
});
