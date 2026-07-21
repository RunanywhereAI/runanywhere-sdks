/**
 * Exact browser-WASM acceptance for the restricted NVIDIA SegFormer bundle.
 *
 * Opt in explicitly:
 *
 *   RA_RUN_SEGFORMER_E2E=1 \
 *   RA_SEGFORMER_BUNDLE_DIR=/path/to/pinned/bc01a2c/bundle \
 *   npx playwright test tests/browser/segformer.e2e.spec.ts
 *
 * The bundle is never checked in, downloaded, or cataloged by this test. The
 * application-level ONNX registration flag is the browser equivalent of the
 * native RAC_ACCEPT_NVIDIA_SEGFORMER_NONCOMMERCIAL_LICENSE environment gate.
 */
import { expect, test } from '@playwright/test';
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';

const REPO_ROOT = process.env.RA_REPO_ROOT ?? resolve(__dirname, '..', '..', '..', '..');
const BUNDLE_DIR = process.env.RA_SEGFORMER_BUNDLE_DIR
  ?? '/tmp/runanywhere-segformer-bc01a2c';
const FILES = [
  'model.onnx',
  'config.json',
  'preprocessor_config.json',
  'runanywhere-segmentation.json',
] as const;

declare global {
  interface Window {
    __RUNANYWHERE_SDK__?: {
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
      segment(request: Record<string, unknown>): Promise<{
        width: number;
        height: number;
        classMaskU16Le: Uint8Array;
        diagnosticRgba: Uint8Array;
        modelId: string;
        classSummaries: Array<{ classId: number; pixelCount: number }>;
      }>;
    };
  }
}

test.describe('SegFormer browser WASM', () => {
  test.setTimeout(120_000);

  test('matches the pinned native mask oracle through the public API', async ({ page }) => {
    test.skip(
      process.env.RA_RUN_SEGFORMER_E2E !== '1',
      'Set RA_RUN_SEGFORMER_E2E=1 only after accepting the pinned NVIDIA license.',
    );

    for (const filename of FILES) {
      const path = resolve(BUNDLE_DIR, filename);
      expect(existsSync(path), `missing exact SegFormer bundle file: ${path}`).toBe(true);
    }

    await page.route('**/__runanywhere_segformer__/*', async (route) => {
      const filename = new URL(route.request().url()).pathname.split('/').pop() ?? '';
      if (!FILES.includes(filename as (typeof FILES)[number])) {
        await route.abort('blockedbyclient');
        return;
      }
      await route.fulfill({
        path: resolve(BUNDLE_DIR, filename),
        contentType: filename.endsWith('.json') ? 'application/json' : 'application/octet-stream',
      });
    });

    await page.goto('/');
    await page.waitForFunction(() => window.__RUNANYWHERE_SDK__?.isInitialized === true, null, {
      timeout: 30_000,
    });

    const result = await page.evaluate(
      async ({ repoRoot, filenames }) => {
        const onnxPath = `/@fs${repoRoot}/sdk/runanywhere-web/packages/onnx/src/index.ts`;
        const internalPath = `/@fs${repoRoot}/sdk/runanywhere-web/packages/core/src/internal.ts`;
        const modelTypesPath = `/@fs${repoRoot}/sdk/shared/proto-ts/src/model_types.ts`;
        const segmentationPath = `/@fs${repoRoot}/sdk/shared/proto-ts/src/segmentation.ts`;

        const [{ ONNX }, internal, modelTypes, segmentation] = await Promise.all([
          import(/* @vite-ignore */ onnxPath),
          import(/* @vite-ignore */ internalPath),
          import(/* @vite-ignore */ modelTypesPath),
          import(/* @vite-ignore */ segmentationPath),
        ]);
        await ONNX.register({ acceptNvidiaSegformerNoncommercialLicense: true });

        const module = internal.getModuleForCapability('segmentation') as {
          FS?: {
            mkdirTree(path: string): void;
            writeFile(path: string, bytes: Uint8Array): void;
          };
        } | null;
        if (!module?.FS) throw new Error('segmentation WASM module has no filesystem');

        const bundlePath = '/models/nvidia-segformer-b0-ade-512-512';
        module.FS.mkdirTree(bundlePath);
        for (const filename of filenames) {
          const response = await fetch(`/__runanywhere_segformer__/${filename}`);
          if (!response.ok) throw new Error(`fixture fetch failed for ${filename}: ${response.status}`);
          module.FS.writeFile(`${bundlePath}/${filename}`, new Uint8Array(await response.arrayBuffer()));
        }

        const sdk = window.__RUNANYWHERE_SDK__!;
        const modelId = 'nvidia-segformer-b0-ade-512-512';
        const category = modelTypes.ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION;
        const framework = modelTypes.InferenceFramework.INFERENCE_FRAMEWORK_ONNX;
        const registered = sdk.modelRegistry.registerModel(modelTypes.ModelInfo.create({
          id: modelId,
          name: 'NVIDIA SegFormer B0 ADE20K',
          description: 'Pinned user-supplied noncommercial evaluation bundle.',
          category,
          framework,
          format: modelTypes.ModelFormat.MODEL_FORMAT_ONNX,
          localPath: bundlePath,
          isDownloaded: true,
          isAvailable: true,
        }));
        const defaultFramework = sdk.modelRegistry.defaultFramework(category);
        const load = await sdk.loadModel({ modelId });

        const width = 37;
        const height = 29;
        const rgb = new Uint8Array(width * height * 3);
        for (let y = 0; y < height; y += 1) {
          for (let x = 0; x < width; x += 1) {
            const offset = (y * width + x) * 3;
            rgb[offset] = (x * 7 + y * 3) % 256;
            rgb[offset + 1] = (x * 11 + y * 5 + 17) % 256;
            rgb[offset + 2] = (x * 13 + y * 19 + 29) % 256;
          }
        }

        const output = await sdk.segment({
          image: {
            data: rgb,
            width,
            height,
            pixelFormat: segmentation.SegmentationPixelFormat.SEGMENTATION_PIXEL_FORMAT_RGB8,
          },
          options: { includeDiagnosticRgba: true },
        });
        const digest = Array.from(
          new Uint8Array(await crypto.subtle.digest('SHA-256', output.classMaskU16Le)),
          (byte) => byte.toString(16).padStart(2, '0'),
        ).join('');
        const counts = Object.fromEntries(
          output.classSummaries.map((summary) => [String(summary.classId), summary.pixelCount]),
        );
        const unload = await sdk.unloadModel({ modelId, unloadAll: false });

        return {
          registered,
          defaultFramework,
          expectedFramework: framework,
          load,
          unload,
          width: output.width,
          height: output.height,
          modelId: output.modelId,
          maskBytes: output.classMaskU16Le.byteLength,
          diagnosticBytes: output.diagnosticRgba.byteLength,
          digest,
          counts,
        };
      },
      { repoRoot: REPO_ROOT, filenames: [...FILES] },
    );

    expect(result.registered).toBe(true);
    expect(result.defaultFramework).toBe(result.expectedFramework);
    expect(result.load).toMatchObject({ success: true, modelId: 'nvidia-segformer-b0-ade-512-512' });
    expect(result).toMatchObject({
      width: 37,
      height: 29,
      modelId: 'nvidia-segformer-b0-ade-512-512',
      maskBytes: 37 * 29 * 2,
      diagnosticBytes: 37 * 29 * 4,
      digest: 'fd68d059416df80f316c61292dd32e3ea5d7e90b17e568c8eb40f0cf0db317e7',
      counts: { '0': 320, '2': 699, '5': 24, '29': 29, '59': 1 },
    });
    expect(result.unload).toMatchObject({ success: true });
  });
});
