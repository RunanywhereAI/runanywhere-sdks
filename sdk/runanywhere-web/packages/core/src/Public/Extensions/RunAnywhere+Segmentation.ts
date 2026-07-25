/**
 * Public semantic-segmentation verb.
 *
 * Model download, registration, loading, and unloading remain owned by the
 * generic model lifecycle. This operation is deliberately handle-free and
 * only runs the semantic-segmentation model that is already loaded.
 */

import { ProtoErrorCode, SDKException } from '../../Foundation/SDKException.js';
import { SegmentationProtoAdapter } from '../../Adapters/SegmentationProtoAdapter.js';
import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import {
  SegmentationPixelFormat,
  type SegmentationClassSummary,
  type SegmentationImage,
  type SegmentationOptions,
  type SegmentationRequest,
  type SegmentationResult,
} from '@runanywhere/proto-ts/segmentation';
import { WebModelLifecycle } from './RunAnywhere+ModelLifecycle.js';

const MAX_SOURCE_DIMENSION = 4096;

function validationFailure(fieldPath: string, message: string): SDKException {
  return SDKException.validationFailed({ fieldPath, message });
}

function validateRequest(request: SegmentationRequest): void {
  const image = request.image;
  if (!image) {
    throw validationFailure('SegmentationRequest.image', 'image is required');
  }
  if (!Number.isInteger(image.width) || image.width < 1 || image.width > MAX_SOURCE_DIMENSION) {
    throw validationFailure(
      'SegmentationRequest.image.width',
      `width must be an integer in 1...${MAX_SOURCE_DIMENSION}`,
    );
  }
  if (!Number.isInteger(image.height) || image.height < 1 || image.height > MAX_SOURCE_DIMENSION) {
    throw validationFailure(
      'SegmentationRequest.image.height',
      `height must be an integer in 1...${MAX_SOURCE_DIMENSION}`,
    );
  }

  let channels: number;
  switch (image.pixelFormat) {
    case SegmentationPixelFormat.SEGMENTATION_PIXEL_FORMAT_RGB8:
      channels = 3;
      break;
    case SegmentationPixelFormat.SEGMENTATION_PIXEL_FORMAT_RGBA8:
    case SegmentationPixelFormat.SEGMENTATION_PIXEL_FORMAT_BGRA8:
      channels = 4;
      break;
    default:
      throw validationFailure(
        'SegmentationRequest.image.pixel_format',
        'pixel_format must be RGB8, RGBA8, or BGRA8',
      );
  }

  const expectedBytes = image.width * image.height * channels;
  if (!Number.isSafeInteger(expectedBytes) || image.data.byteLength !== expectedBytes) {
    throw validationFailure(
      'SegmentationRequest.image.data',
      `data must contain exactly ${expectedBytes} tightly packed bytes`,
    );
  }
}

function validateResult(
  request: SegmentationRequest,
  result: SegmentationResult,
  loadedModelId: string,
): void {
  const image = request.image!;
  if (result.width !== image.width || result.height !== image.height) {
    throw SDKException.processingFailed(
      'Segmentation returned dimensions that do not match the source image.',
    );
  }

  const pixels = result.width * result.height;
  if (result.classMaskU16Le.byteLength !== pixels * 2) {
    throw SDKException.processingFailed(
      'Segmentation returned an invalid uint16 class-mask byte length.',
    );
  }

  const diagnosticBytes = result.diagnosticRgba?.byteLength ?? 0;
  if (request.options?.includeDiagnosticRgba && diagnosticBytes !== pixels * 4) {
    throw SDKException.processingFailed(
      'Segmentation requested a diagnostic RGBA image but received an invalid payload.',
    );
  }
  if (diagnosticBytes !== 0 && diagnosticBytes !== pixels * 4) {
    throw SDKException.processingFailed(
      'Segmentation returned an invalid diagnostic RGBA byte length.',
    );
  }

  let summarizedPixels = 0;
  for (const summary of result.classSummaries) {
    if (!Number.isInteger(summary.pixelCount) || summary.pixelCount < 0) {
      throw SDKException.processingFailed(
        'Segmentation returned an invalid class-summary pixel count.',
      );
    }
    summarizedPixels += summary.pixelCount;
  }
  if (summarizedPixels !== pixels) {
    throw SDKException.processingFailed(
      'Segmentation class-summary counts do not cover the source image exactly.',
    );
  }
  if (result.modelId !== loadedModelId) {
    throw SDKException.processingFailed(
      'Segmentation result model ID does not match the lifecycle-owned model.',
    );
  }
}

function requireInitialized(): void {
  if (!WebModelLifecycle.supportsNativeLifecycle()) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_NOT_INITIALIZED,
      'RunAnywhere.initialize() must complete before segmentation can be used.',
      'Segmentation',
    );
  }
}

function requireLoadedModelId(): string {
  const current = WebModelLifecycle.currentModel({
    category: ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION,
    includeModelMetadata: false,
  });
  if (!current?.found || !current.modelId) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_MODEL_NOT_LOADED,
      'No semantic-segmentation model is loaded.',
      'Load a semantic-segmentation model with RunAnywhere.loadModel() first.',
    );
  }
  return current.modelId;
}

function requireAdapter(): SegmentationProtoAdapter {
  const adapter = SegmentationProtoAdapter.tryDefault();
  if (!adapter || !adapter.supportsLifecycleProtoSegmentation()) {
    throw SDKException.backendNotAvailable(
      'Segmentation',
      'Register the ONNX Web backend built with _rac_segmentation_segment_lifecycle_proto.',
    );
  }
  return adapter;
}

/** Segment an image with the lifecycle-owned semantic-segmentation model. */
export async function segment(
  request: SegmentationRequest,
): Promise<SegmentationResult> {
  requireInitialized();
  validateRequest(request);
  const loadedModelId = requireLoadedModelId();
  const result = await requireAdapter().segmentLifecycle(request);
  if (!result) {
    throw SDKException.backendNotAvailable(
      'Segmentation',
      'The native Web segmentation operation returned no result.',
    );
  }
  validateResult(request, result, loadedModelId);
  return result;
}

export type {
  SegmentationClassSummary,
  SegmentationImage,
  SegmentationOptions,
  SegmentationRequest,
  SegmentationResult,
};
export { SegmentationPixelFormat };
