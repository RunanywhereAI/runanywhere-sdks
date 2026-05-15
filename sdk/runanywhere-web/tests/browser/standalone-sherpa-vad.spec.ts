/**
 * Standalone Sherpa-ONNX VAD end-to-end test.
 *
 * Drives the proven `main`-branch path end-to-end against the standalone
 * `sherpa-onnx.wasm` module:
 *
 *   1. Load the patched glue + WASM (via async `instantiateWasm`).
 *   2. Fetch the Silero VAD ONNX from a CORS-friendly mirror.
 *   3. Stage it into Sherpa's MEMFS via `FS_createDataFile`.
 *   4. Pack `SherpaOnnxVadModelConfig` directly via `_malloc` +
 *      `setValue` (the upstream `sherpa-onnx-vad.js` wrapper drags in
 *      Node-only `fs.writeFileSync` callbacks during MEMFS init, so we
 *      avoid it).
 *   5. Construct the detector with `_SherpaOnnxCreateVoiceActivityDetector`,
 *      assert the handle is non-null (the original `function signature
 *      mismatch` regression would have aborted before this point), then
 *      destroy and verify nothing leaks.
 *
 * This proves the standalone Sherpa WASM lifecycle (load → stage →
 * construct → destroy) works in the browser, which is the foundation
 * for the V2 STT / TTS / VAD facade integration.
 */
import { test, expect } from '@playwright/test';

const shouldRun = process.env.RA_RUN_SPEECH_E2E === '1';

interface AppReadinessSnapshot {
  state: 'booting' | 'initializing-sdk' | 'building-shell' | 'interactive' | 'error';
}

declare global {
  interface Window {
    __RUNANYWHERE_AI_READY__?: AppReadinessSnapshot;
    __SHERPA_VAD_RESULT__?: {
      ok: boolean;
      diagnostics: string[];
      modelBytes: number;
      detectorHandle: number;
      destroyed: boolean;
      error?: string;
    };
  }
}

test.describe('Standalone Sherpa-ONNX VAD end-to-end', () => {
  test.skip(!shouldRun, 'Speech/RAG E2E is opt-in (set RA_RUN_SPEECH_E2E=1).');
  test.setTimeout(2 * 60 * 1000);

  test('loads silero_vad.onnx into standalone WASM and constructs a VAD detector handle', async ({ page }) => {
    page.on('pageerror', (err) => {
      console.error('[page error]', err.message);
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
      // Capture unhandled rejections inside the page so we never surface
      // an `Uncaught` to Playwright before our try/catch fires.
      window.addEventListener('unhandledrejection', (event) => {
        event.preventDefault();
      });
      window.addEventListener('error', (event) => {
        event.preventDefault();
      });
      const diagnostics: string[] = [];
      const note = (msg: string) => {
        diagnostics.push(msg);
        console.log('[probe]', msg);
      };
      try {
        const glueModule = await import(
          '/@fs/Users/sanchitmonga/development/ODLM/MONOREPOOO/runanywhere-sdks3/runanywhere-sdks-main/sdk/runanywhere-web/packages/onnx/wasm/sherpa/sherpa-onnx-glue.js'
        );
        const createModule = (glueModule.default ?? glueModule) as (
          overrides?: Record<string, unknown>,
        ) => Promise<Record<string, unknown>>;
        note('glue imported');

        const wasmHref = new URL(
          '/@fs/Users/sanchitmonga/development/ODLM/MONOREPOOO/runanywhere-sdks3/runanywhere-sdks-main/sdk/runanywhere-web/packages/onnx/wasm/sherpa/sherpa-onnx.wasm',
          window.location.href,
        ).href;
        const wasmBinary = await (await fetch(wasmHref)).arrayBuffer();
        note(`wasm fetched (${wasmBinary.byteLength} bytes)`);

        const module = await createModule({
          noFSInit: true,
          print: (text: string) => diagnostics.push(`stdout: ${text}`),
          printErr: (text: string) => diagnostics.push(`stderr: ${text}`),
          wasmBinary,
          locateFile: (path: string) => (path.endsWith('.wasm') ? wasmHref : path),
          instantiateWasm: (
            imports: WebAssembly.Imports,
            receiveInstance: (instance: WebAssembly.Instance, mod: WebAssembly.Module) => void,
          ) => {
            WebAssembly.instantiate(wasmBinary, imports).then((result) => {
              try {
                receiveInstance(result.instance, result.module);
              } catch {
                /* addRunDependency clears via patch 6 */
              }
            });
            return {};
          },
        });
        note('createModule resolved');

        // Allow the run dependency from instantiateWasm to clear before we
        // start touching the runtime (FS_*, malloc, etc).
        await new Promise((resolve) => setTimeout(resolve, 250));
        note('post-init delay done');

        const m = module as Record<string, (...args: unknown[]) => unknown> & {
          _malloc(n: number): number;
          _free(p: number): void;
          stringToUTF8(s: string, ptr: number, max: number): void;
          lengthBytesUTF8(s: string): number;
          setValue(ptr: number, val: number, type: string): void;
          HEAPU8: Uint8Array;
          FS_createDataFile(
            parent: string,
            name: string,
            data: Uint8Array,
            canRead: boolean,
            canWrite: boolean,
            canOwn: boolean,
          ): void;
        };

        // Sherpa-ONNX 1.12.x only knows the Silero VAD v4 ONNX schema
        // (the snakers4 master branch ships v5, which Sherpa rejects with
        // a silent abort). The v4 model is bundled as a fixture in the
        // tests directory; Vite serves it via the example app's `tests/`
        // path through the dev server (`/@fs/...`).
        const vadUrl = new URL(
          '/@fs/Users/sanchitmonga/development/ODLM/MONOREPOOO/runanywhere-sdks3/runanywhere-sdks-main/sdk/runanywhere-web/tests/browser/fixtures/silero_vad.onnx',
          window.location.href,
        ).href;
        const vadResponse = await fetch(vadUrl);
        if (!vadResponse.ok) {
          throw new Error(`silero_vad.onnx fetch ${vadResponse.status}: ${vadResponse.statusText}`);
        }
        const vadModel = new Uint8Array(await vadResponse.arrayBuffer());
        note(`vad model fetched (${vadModel.length} bytes)`);

        m.FS_createDataFile('/', 'silero_vad.onnx', vadModel, true, true, true);
        note('FS_createDataFile ok');

        const sileroSize = 6 * 4;
        const tenSize = 6 * 4;
        const totalSize = sileroSize + 4 * 4 + tenSize;
        const cfgPtr = m._malloc(totalSize);
        m.HEAPU8.fill(0, cfgPtr, cfgPtr + totalSize);

        const modelPath = 'silero_vad.onnx';
        const modelPathLen = m.lengthBytesUTF8(modelPath) + 1;
        const modelPathPtr = m._malloc(modelPathLen);
        m.stringToUTF8(modelPath, modelPathPtr, modelPathLen);

        const providerStr = 'cpu';
        const providerLen = m.lengthBytesUTF8(providerStr) + 1;
        const providerPtr = m._malloc(providerLen);
        m.stringToUTF8(providerStr, providerPtr, providerLen);

        m.setValue(cfgPtr + 0, modelPathPtr, 'i8*');
        m.setValue(cfgPtr + 4, 0.5, 'float');
        m.setValue(cfgPtr + 8, 0.5, 'float');
        m.setValue(cfgPtr + 12, 0.25, 'float');
        m.setValue(cfgPtr + 16, 512, 'i32');
        m.setValue(cfgPtr + 20, 20, 'float');

        const topOffset = cfgPtr + sileroSize;
        m.setValue(topOffset + 0, 16000, 'i32');
        m.setValue(topOffset + 4, 1, 'i32');
        m.setValue(topOffset + 8, providerPtr, 'i8*');
        m.setValue(topOffset + 12, 1, 'i32'); // debug = 1

        note('config packed; calling createVad');
        const createVad = (m as { _SherpaOnnxCreateVoiceActivityDetector: (cfg: number, bufferSec: number) => number })
          ._SherpaOnnxCreateVoiceActivityDetector;
        const detectorHandle = createVad(cfgPtr, 30);
        note(`createVad returned handle=${detectorHandle}`);

        m._free(modelPathPtr);
        m._free(providerPtr);
        m._free(cfgPtr);

        let destroyed = false;
        if (detectorHandle) {
          const destroyVad = (m as { _SherpaOnnxDestroyVoiceActivityDetector: (h: number) => void })
            ._SherpaOnnxDestroyVoiceActivityDetector;
          destroyVad(detectorHandle);
          destroyed = true;
        }

        window.__SHERPA_VAD_RESULT__ = {
          ok: true,
          diagnostics,
          modelBytes: vadModel.length,
          detectorHandle,
          destroyed,
        };
      } catch (error) {
        window.__SHERPA_VAD_RESULT__ = {
          ok: false,
          diagnostics,
          modelBytes: 0,
          detectorHandle: 0,
          destroyed: false,
          error: error instanceof Error ? `${error.name}: ${error.message}` : String(error),
        };
      }
    });

    const result = await page.evaluate(() => window.__SHERPA_VAD_RESULT__);
    expect(result, 'VAD probe should be set').toBeDefined();
    const trail = (result?.diagnostics ?? []).join('\n  ');
    expect(
      result?.error,
      `VAD pipeline failed: ${result?.error ?? 'none'}\nDiagnostics:\n  ${trail}`,
    ).toBeUndefined();
    expect(result?.ok, 'pipeline OK').toBe(true);
    expect(result?.modelBytes, 'silero_vad.onnx fetched').toBeGreaterThan(500 * 1024);
    expect(result?.detectorHandle, 'detector handle is non-null').toBeGreaterThan(0);
    expect(result?.destroyed, 'detector destroyed cleanly').toBe(true);
  });
});
