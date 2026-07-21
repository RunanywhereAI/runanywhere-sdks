/**
 * Exact Chromium CPU/WASM acceptance for the locally exported NVIDIA BigVGAN
 * bundle. This does not exercise or claim a WebGPU execution provider.
 *
 * Opt in explicitly:
 *
 *   RA_RUN_BIGVGAN_E2E=1 \
 *   RA_BIGVGAN_BUNDLE_DIR=/path/to/runanywhere-bigvgan-export \
 *   npx playwright test tests/browser/bigvgan.e2e.spec.ts
 *
 * When present, `/tmp/runanywhere-bigvgan-export-repo-script` is the local
 * default. The test never downloads, catalogs, publishes, or checks in the
 * approximately 450 MB bundle.
 */
import { expect, test } from '@playwright/test';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { resolve } from 'node:path';

const REPO_ROOT = process.env.RA_REPO_ROOT ?? resolve(__dirname, '..', '..', '..', '..');
const LOCAL_DEFAULT_BUNDLE_DIR = '/tmp/runanywhere-bigvgan-export-repo-script';
const BUNDLE_DIR = process.env.RA_BIGVGAN_BUNDLE_DIR
  ?? (existsSync(LOCAL_DEFAULT_BUNDLE_DIR) ? LOCAL_DEFAULT_BUNDLE_DIR : undefined);
const FILES = [
  'model.onnx',
  'model.onnx.data',
  'config.json',
  'LICENSE',
  'runanywhere-export-manifest.json',
] as const;
const FILE_ALLOWLIST = new Set<string>(FILES);

async function startBundleServer(bundleDir: string): Promise<{
  baseUrl: string;
  close: () => Promise<void>;
}> {
  const server = createServer((request, response) => {
    const responseHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Cross-Origin-Resource-Policy': 'cross-origin',
    };
    const reject = (statusCode: number, message: string): void => {
      response.writeHead(statusCode, {
        ...responseHeaders,
        'Content-Type': 'text/plain; charset=utf-8',
        'Content-Length': Buffer.byteLength(message),
      });
      response.end(message);
    };

    if (request.method !== 'GET') {
      reject(405, 'method not allowed');
      return;
    }

    const pathname = new URL(request.url ?? '/', 'http://127.0.0.1').pathname;
    const prefix = '/__runanywhere_bigvgan__/';
    if (!pathname.startsWith(prefix)) {
      reject(404, 'not found');
      return;
    }

    let filename: string;
    try {
      filename = decodeURIComponent(pathname.slice(prefix.length));
    } catch {
      reject(400, 'invalid path encoding');
      return;
    }
    if (!FILE_ALLOWLIST.has(filename)) {
      reject(404, 'not found');
      return;
    }

    const filePath = resolve(bundleDir, filename);
    let fileSize: number;
    try {
      const stats = statSync(filePath);
      if (!stats.isFile()) {
        reject(404, 'not found');
        return;
      }
      fileSize = stats.size;
    } catch {
      reject(404, 'not found');
      return;
    }

    const contentType = filename.endsWith('.json')
      ? 'application/json'
      : filename === 'LICENSE'
        ? 'text/plain'
        : 'application/octet-stream';
    response.writeHead(200, {
      ...responseHeaders,
      'Content-Type': contentType,
      'Content-Length': fileSize,
      'Cache-Control': 'no-store',
    });
    const stream = createReadStream(filePath);
    stream.on('error', (error) => response.destroy(error));
    stream.pipe(response);
  });

  await new Promise<void>((resolveListen, rejectListen) => {
    server.once('error', rejectListen);
    server.listen(0, '127.0.0.1', () => {
      server.off('error', rejectListen);
      resolveListen();
    });
  });
  const address = server.address();
  if (!address || typeof address === 'string') {
    server.close();
    throw new Error('BigVGAN bundle server did not bind to a TCP port');
  }

  return {
    baseUrl: `http://127.0.0.1:${address.port}/__runanywhere_bigvgan__`,
    close: () => new Promise<void>((resolveClose, rejectClose) => {
      server.close((error) => {
        if (error) rejectClose(error);
        else resolveClose();
      });
    }),
  };
}

const MODEL_ID = 'nvidia-bigvgan-v2-22khz-80band-256x';
const MEL_BIN_COUNT = 80;
const FRAME_COUNT = 3;
const SAMPLE_COUNT = 768;
const SAMPLE_RATE_HZ = 22_050;
const HOP_LENGTH = 256;
const RAMP_INPUT_F32_LE_SHA256 =
  '619b56e2c504856d63fbc0721b240c53bbae611c15324b6cc001bd1a992bf3aa';

// Independent oracle: pinned official NVIDIA PyTorch checkpoint `633ff70`
// with source `7d2b454`, weight norm removed, eval/inference mode, and
// float32 `linspace(-2, 1, 80*3).reshape(1, 80, 3)`. These are numeric
// acceptance anchors because different ONNX Runtime pins are not bit-exact.
const OFFICIAL_RAMP_T3_ORACLE = {
  points: {
    0: -0.0050332266837358475,
    31: -0.17699752748012543,
    127: -0.0050324671901762486,
    255: -0.31465134024620056,
    256: 0.6942927837371826,
    383: 0.13872399926185608,
    511: 0.45309290289878845,
    640: -0.03142954036593437,
    767: 0.005958521738648415,
  },
  mean: 0.0008340676431544125,
  rms: 0.3346756229692144,
  rawFloat32LeSha256: '577b468c3fadf7cb737606e53cdd5b64bfabba7c57eb03183d8d80d930e4aa71',
} as const;

test.describe('BigVGAN browser CPU/WASM', () => {
  test.setTimeout(15 * 60_000);

  test('matches official T=3 ramp anchors through public RunAnywhere.vocode', async ({ page }) => {
    test.skip(
      process.env.RA_RUN_BIGVGAN_E2E !== '1',
      'Set RA_RUN_BIGVGAN_E2E=1 to run the approximately 450 MB local CPU/WASM gate.',
    );
    test.skip(
      !BUNDLE_DIR,
      'Set RA_BIGVGAN_BUNDLE_DIR or prepare /tmp/runanywhere-bigvgan-export-repo-script.',
    );
    if (!BUNDLE_DIR) throw new Error('BigVGAN bundle directory is not configured');

    for (const filename of FILES) {
      const path = resolve(BUNDLE_DIR, filename);
      expect(existsSync(path), `missing exact BigVGAN bundle file: ${path}`).toBe(true);
    }

    const bundleServer = await startBundleServer(BUNDLE_DIR);
    try {
      await page.goto('/');
      await page.waitForFunction(
        () => (window as unknown as { __RUNANYWHERE_SDK__?: { isInitialized: boolean } })
          .__RUNANYWHERE_SDK__?.isInitialized === true,
        null,
        { timeout: 30_000 },
      );

      const result = await page.evaluate(
        async ({ repoRoot, filenames, modelId, melBinCount, frameCount, bundleBaseUrl }) => {
        const onnxPath = `/@fs${repoRoot}/sdk/runanywhere-web/packages/onnx/src/index.ts`;
        const internalPath = `/@fs${repoRoot}/sdk/runanywhere-web/packages/core/src/internal.ts`;
        const modelTypesPath = `/@fs${repoRoot}/sdk/shared/proto-ts/src/model_types.ts`;

        const [{ ONNX }, internal, modelTypes] = await Promise.all([
          import(/* @vite-ignore */ onnxPath),
          import(/* @vite-ignore */ internalPath),
          import(/* @vite-ignore */ modelTypesPath),
        ]);
        await ONNX.register();

        const module = internal.getModuleForCapability('vocoder') as {
          FS?: {
            mkdirTree(path: string): void;
            writeFile(path: string, bytes: Uint8Array): void;
          };
          MountedFiles?: {
            has(path: string): boolean;
          };
        } | null;
        if (!module?.FS) throw new Error('vocoder CPU/WASM module has no filesystem');

        const bundlePath = '/models/nvidia-bigvgan-v2-22khz-80band-256x';
        module.FS.mkdirTree(bundlePath);
        for (const filename of filenames) {
          const response = await fetch(`${bundleBaseUrl}/${encodeURIComponent(filename)}`);
          if (!response.ok) throw new Error(`fixture fetch failed for ${filename}: ${response.status}`);
          module.FS.writeFile(
            `${bundlePath}/${filename}`,
            new Uint8Array(await response.arrayBuffer()),
          );
        }

        type BrowserSDK = {
          isInitialized: boolean;
          modelRegistry: {
            registerModel(model: Record<string, unknown>): boolean;
            defaultFramework(category: number): number;
          };
          loadModel(request: { modelId: string }): Promise<{
            success: boolean;
            modelId: string;
          } | null>;
          unloadModel(request: {
            modelId: string;
            unloadAll: boolean;
          }): Promise<{ success: boolean } | null>;
          vocode(request: {
            melSpectrogram: Float32Array;
            batchSize: number;
            melBinCount: number;
            frameCount: number;
          }): Promise<{
            samples: Float32Array;
            batchSize: number;
            channelCount: number;
            sampleCount: number;
            sampleRateHz: number;
            hopLength: number;
            processingTimeMs: number;
            modelId: string;
          }>;
        };
        const sdk = (window as unknown as { __RUNANYWHERE_SDK__?: BrowserSDK })
          .__RUNANYWHERE_SDK__;
        if (!sdk) throw new Error('RunAnywhere browser SDK is unavailable');

        const category = modelTypes.ModelCategory.MODEL_CATEGORY_VOCODER;
        const framework = modelTypes.InferenceFramework.INFERENCE_FRAMEWORK_ONNX;
        const registered = sdk.modelRegistry.registerModel(modelTypes.ModelInfo.create({
          id: modelId,
          name: 'NVIDIA BigVGAN v2 22 kHz 80-band 256x',
          description: 'Pinned local RunAnywhere ONNX export; browser CPU/WASM acceptance only.',
          category,
          framework,
          format: modelTypes.ModelFormat.MODEL_FORMAT_ONNX,
          localPath: bundlePath,
          isDownloaded: true,
          isAvailable: true,
        }));
        const defaultFramework = sdk.modelRegistry.defaultFramework(category);
        const load = await sdk.loadModel({ modelId });
        const externalDataEntryReleased =
          module.MountedFiles?.has(`${bundlePath}/model.onnx.data`) !== true;

        const melSpectrogram = new Float32Array(melBinCount * frameCount);
        for (let index = 0; index < melSpectrogram.length; index += 1) {
          melSpectrogram[index] = -2 + (3 * index) / (melSpectrogram.length - 1);
        }
        const melDigest = Array.from(
          new Uint8Array(await crypto.subtle.digest('SHA-256', melSpectrogram)),
          (byte) => byte.toString(16).padStart(2, '0'),
        ).join('');

        const output = await sdk.vocode({
          melSpectrogram,
          batchSize: 1,
          melBinCount,
          frameCount,
        });
        const sampleBytes = new Uint8Array(output.samples.byteLength);
        sampleBytes.set(new Uint8Array(
          output.samples.buffer,
          output.samples.byteOffset,
          output.samples.byteLength,
        ));
        const digest = Array.from(
          new Uint8Array(await crypto.subtle.digest('SHA-256', sampleBytes)),
          (byte) => byte.toString(16).padStart(2, '0'),
        ).join('');

        let sum = 0;
        let sumSquares = 0;
        let minimum = Number.POSITIVE_INFINITY;
        let maximum = Number.NEGATIVE_INFINITY;
        let allFinite = true;
        for (const sample of output.samples) {
          allFinite = allFinite && Number.isFinite(sample);
          sum += sample;
          sumSquares += sample * sample;
          minimum = Math.min(minimum, sample);
          maximum = Math.max(maximum, sample);
        }
        const anchorIndices = [0, 31, 127, 255, 256, 383, 511, 640, 767];
        const points = Object.fromEntries(
          anchorIndices.map((index) => [String(index), output.samples[index]]),
        );
        const unload = await sdk.unloadModel({ modelId, unloadAll: false });

        return {
          registered,
          defaultFramework,
          expectedFramework: framework,
          load,
          externalDataEntryReleased,
          unload,
          melDigest,
          shape: [output.batchSize, output.channelCount, output.sampleCount],
          sampleRateHz: output.sampleRateHz,
          hopLength: output.hopLength,
          processingTimeMs: output.processingTimeMs,
          modelId: output.modelId,
          allFinite,
          minimum,
          maximum,
          mean: sum / output.samples.length,
          rms: Math.sqrt(sumSquares / output.samples.length),
          points,
          digest,
        };
      },
        {
          repoRoot: REPO_ROOT,
          filenames: [...FILES],
          modelId: MODEL_ID,
          melBinCount: MEL_BIN_COUNT,
          frameCount: FRAME_COUNT,
          bundleBaseUrl: bundleServer.baseUrl,
        },
      );

      expect(result.registered).toBe(true);
      expect(result.defaultFramework).toBe(result.expectedFramework);
      expect(result.load).toMatchObject({ success: true, modelId: MODEL_ID });
      expect(result.externalDataEntryReleased).toBe(true);
      expect(result.melDigest).toBe(RAMP_INPUT_F32_LE_SHA256);
      expect(result.shape).toEqual([1, 1, SAMPLE_COUNT]);
      expect(result.sampleRateHz).toBe(SAMPLE_RATE_HZ);
      expect(result.hopLength).toBe(HOP_LENGTH);
      expect(result.modelId).toBe(MODEL_ID);
      expect(result.unload).toMatchObject({ success: true });
      expect(result.processingTimeMs).toBeGreaterThanOrEqual(0);
      expect(result.allFinite).toBe(true);
      expect(result.minimum).toBeGreaterThanOrEqual(-1.000_001);
      expect(result.maximum).toBeLessThanOrEqual(1.000_001);

      const numericTolerance = 1e-4;
      for (const [index, expected] of Object.entries(OFFICIAL_RAMP_T3_ORACLE.points)) {
        expect(
          Math.abs(result.points[index]! - expected),
          `official PyTorch ramp anchor at sample ${index}`,
        ).toBeLessThanOrEqual(numericTolerance);
      }
      expect(Math.abs(result.mean - OFFICIAL_RAMP_T3_ORACLE.mean)).toBeLessThanOrEqual(
        numericTolerance,
      );
      expect(Math.abs(result.rms - OFFICIAL_RAMP_T3_ORACLE.rms)).toBeLessThanOrEqual(
        numericTolerance,
      );

      // Raw float bytes vary across otherwise acceptable ONNX Runtime pins.
      // Attach both hashes for diagnostics; numerical anchors above are the gate.
      await test.info().attach('bigvgan-ramp-t3-sha256-diagnostic.json', {
        body: Buffer.from(JSON.stringify({
          cpuWasmCandidate: result.digest,
          officialPyTorchReference: OFFICIAL_RAMP_T3_ORACLE.rawFloat32LeSha256,
        }, null, 2)),
        contentType: 'application/json',
      });
    } finally {
      await bundleServer.close();
    }
  });
});
