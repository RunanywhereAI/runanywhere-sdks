/**
 * `RunAnywhere.segmentation` — per-pixel class masks.
 */

import {
  SegmentationRequest,
  SegmentationResult as SegmentationResultMessage,
} from '@runanywhere/proto-ts/segmentation';

import { decode, encode, preflight } from './Bridge';
import { toSegmentationImage } from './Inputs';
import { toSegmentationOptions } from './Options';
import { toSegmentationResult } from './Results';
import type {
  ImageInput,
  SegmentationOptions,
  SegmentationResult,
} from './Types';

/** Image segmentation over the loaded segmentation model. */
export const segmentation = {
  /**
   * Produce a per-pixel class mask for `image`.
   *
   * @example
   * const result = await RunAnywhere.segmentation.segment(ImageInputs.rawRgba(pixels, w, h));
   * console.log(result.classes.map((c) => c.label));
   *
   * @throws SDKException when the image is not raw pixels, no segmentation
   * model is loaded, or the run fails.
   */
  async segment(
    image: ImageInput,
    options?: SegmentationOptions
  ): Promise<SegmentationResult> {
    const native = await preflight();
    const request = SegmentationRequest.fromPartial({
      image: toSegmentationImage(image),
      options: toSegmentationOptions(options),
    });
    const resultBytes = await native.segmentationSegmentLifecycleProto(
      encode(request, SegmentationRequest)
    );
    return toSegmentationResult(
      decode(resultBytes, SegmentationResultMessage, 'segmentationSegment')
    );
  },
};
