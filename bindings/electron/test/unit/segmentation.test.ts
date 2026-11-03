// Segmentation binding error propagation.
//
// The native payload check returns -331 (RAC_ERROR_ENCODING_ERROR) when an
// engine reports a confidence mask that is not exactly width * height. These
// tests pin the JS half of that chain: the facade must reject with the typed
// SDKException instead of returning a partial result.
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { createSegmentationNamespace, type AssetDeps } from '../../dist/api/assets';
import type { RaBackend } from '../../dist/api/backend';
import { image } from '../../dist/api/types';
import { ErrorCodes, isSDKException, raiseForRac } from '../../dist/errors';

function fakeDeps(segmentProto: () => Promise<Uint8Array>): AssetDeps {
  return {
    backend: { segmentProto } as unknown as RaBackend,
    hub: {} as AssetDeps['hub'],
    requireReady() {},
  };
}

test('segmentation surfaces a native encoding failure unchanged', async () => {
  const deps = fakeDeps(async () => {
    raiseForRac(-331, 'backend returned an invalid segmentation result');
  });
  const namespace = createSegmentationNamespace(deps);

  await assert.rejects(
    () =>
      namespace.segment(image.rawRgb(new Uint8Array(2 * 2 * 3), 2, 2), {
        includeConfidence: true,
      }),
    (error: unknown) => {
      assert.ok(isSDKException(error));
      assert.equal(error.code, ErrorCodes.ENCODING_ERROR);
      assert.equal(error.cAbiCode, -331);
      assert.match(error.message, /invalid segmentation result/);
      return true;
    }
  );
});

test('segmentation does not swallow non-SDK failures', async () => {
  const deps = fakeDeps(async () => {
    throw new Error('segmentProto exploded');
  });
  const namespace = createSegmentationNamespace(deps);

  await assert.rejects(
    () => namespace.segment(image.rawRgb(new Uint8Array(1 * 1 * 3), 1, 1)),
    /segmentProto exploded/
  );
});
