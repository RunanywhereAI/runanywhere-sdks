// The segmentation namespace: semantic segmentation over the proto-byte backend.
// Auto-loads the segmentation model named in options.model. The backend takes raw
// RGB pixels, so ImageInput must be `rawRgb` here (encoded/file inputs need a
// decoder commons owns for other modalities, not wired on this path).
import {
  SegmentationImage,
  SegmentationOptions,
  SegmentationPixelFormat,
  SegmentationRequest,
  SegmentationResult,
} from '@runanywhere/proto-ts/segmentation';

import type { RaBackend } from '../backend.js';
import { SDKException } from '../errors.js';
import type { ImageInput } from '../types.js';
import type { ModelResolver } from './llm.js';

/** Segmentation controls. Mirrors Swift `SegmentationOptions`. */
export interface SegmentationParams {
  /** Segmentation model id; loaded (and downloaded) first if not resident. */
  model?: string;
  includeDiagnosticImage?: boolean;
}

/** A segmentation result. */
export interface Segmentation {
  width: number;
  height: number;
  classSummaries: SegmentationResult['classSummaries'];
  diagnosticRgba?: Uint8Array;
}

export interface SegmentationNamespace {
  segment(image: ImageInput, options?: SegmentationParams): Promise<Segmentation>;
}

export function createSegmentationNamespace(backend: RaBackend, resolve: ModelResolver): SegmentationNamespace {
  return {
    async segment(image, options = {}) {
      if (options.model) await resolve(options.model);
      if (image.kind !== 'rawRgb') {
        throw SDKException.invalidInput('segmentation needs a rawRgb ImageInput (decoded pixels)');
      }
      const req = SegmentationRequest.fromPartial({
        image: SegmentationImage.fromPartial({
          data: image.data,
          width: image.width,
          height: image.height,
          // rawRgb is 3 bytes/pixel; pixelFormat is required or commons rejects it (-106).
          pixelFormat: SegmentationPixelFormat.SEGMENTATION_PIXEL_FORMAT_RGB8,
          strideBytes: image.width * 3,
        }),
        options: SegmentationOptions.fromPartial({
          includeDiagnosticRgba: options.includeDiagnosticImage ?? false,
        }),
      });
      const out = SegmentationResult.decode(await backend.segment(SegmentationRequest.encode(req).finish()));
      return {
        width: out.width,
        height: out.height,
        classSummaries: out.classSummaries,
        diagnosticRgba: out.diagnosticRgba,
      };
    },
  };
}
