/**
 * Public handle-free mel-spectrogram vocoder verb.
 *
 * The generic model lifecycle owns the model and native service. Public Web
 * callers work with finite float samples; the compact little-endian byte
 * representation remains confined to the proto boundary.
 */

import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import {
  VocoderRequest as WireVocoderRequest,
  type VocoderResult as WireVocoderResult,
} from '@runanywhere/proto-ts/vocoder';
import { VocoderProtoAdapter } from '../../Adapters/VocoderProtoAdapter.js';
import { ProtoErrorCode, SDKException } from '../../Foundation/SDKException.js';
import { WebModelLifecycle } from './RunAnywhere+ModelLifecycle.js';

export interface VocoderRequest {
  /** Row-major mel values in `[batchSize, melBinCount, frameCount]` order. */
  melSpectrogram: ReadonlyArray<number> | Float32Array;
  batchSize: number;
  melBinCount: number;
  frameCount: number;
}

export interface VocoderResult {
  /** Row-major waveform values in `[batchSize, channelCount, sampleCount]` order. */
  samples: Float32Array;
  batchSize: number;
  channelCount: number;
  /** Samples per channel. */
  sampleCount: number;
  sampleRateHz: number;
  hopLength: number;
  processingTimeMs: number;
  modelId: string;
}

const FLOAT32_BYTES = 4;

function validationFailure(fieldPath: string, message: string): SDKException {
  return SDKException.validationFailed({ fieldPath, message });
}

function requirePositiveInteger(value: number, fieldPath: string): void {
  if (!Number.isSafeInteger(value) || value < 1) {
    throw validationFailure(fieldPath, 'must be a positive safe integer');
  }
}

function checkedProduct(values: readonly number[], fieldPath: string): number {
  let product = 1;
  for (const value of values) {
    requirePositiveInteger(value, fieldPath);
    product *= value;
    if (!Number.isSafeInteger(product)) {
      throw validationFailure(fieldPath, 'dimensions overflow a safe integer');
    }
  }
  return product;
}

function checkedFloat32ByteCount(valueCount: number, fieldPath: string): number {
  if (valueCount > Math.floor(0xffff_ffff / FLOAT32_BYTES)) {
    throw validationFailure(fieldPath, 'float32 payload exceeds the WASM32 address space');
  }
  return valueCount * FLOAT32_BYTES;
}

function requirePositiveResultInteger(value: number, fieldPath: string): void {
  if (!Number.isSafeInteger(value) || value < 1) {
    throw SDKException.processingFailed(`${fieldPath} must be a positive safe integer.`);
  }
}

function checkedResultProduct(values: readonly number[], fieldPath: string): number {
  let product = 1;
  for (const value of values) {
    requirePositiveResultInteger(value, fieldPath);
    product *= value;
    if (!Number.isSafeInteger(product)) {
      throw SDKException.processingFailed(`${fieldPath} dimensions overflow a safe integer.`);
    }
  }
  return product;
}

function encodeFloat32LE(values: ReadonlyArray<number> | Float32Array): Uint8Array {
  const bytes = new Uint8Array(checkedFloat32ByteCount(
    values.length,
    'VocoderRequest.melSpectrogram',
  ));
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index]!;
    const float32Value = Math.fround(value);
    if (!Number.isFinite(float32Value)) {
      throw validationFailure(
        `VocoderRequest.melSpectrogram[${index}]`,
        'must be representable as a finite float32 value',
      );
    }
    view.setFloat32(index * FLOAT32_BYTES, float32Value, true);
  }
  return bytes;
}

function decodeFloat32LE(bytes: Uint8Array, fieldPath: string): Float32Array {
  if (bytes.byteLength % FLOAT32_BYTES !== 0) {
    throw SDKException.processingFailed(`${fieldPath} is not aligned to float32 values.`);
  }
  const values = new Float32Array(bytes.byteLength / FLOAT32_BYTES);
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  for (let index = 0; index < values.length; index += 1) {
    const value = view.getFloat32(index * FLOAT32_BYTES, true);
    if (!Number.isFinite(value)) {
      throw SDKException.processingFailed(`${fieldPath} contains a non-finite sample.`);
    }
    values[index] = value;
  }
  return values;
}

function validateAndEncodeRequest(request: VocoderRequest): WireVocoderRequest {
  const valueCount = checkedProduct(
    [request.batchSize, request.melBinCount, request.frameCount],
    'VocoderRequest.dimensions',
  );
  if (request.melSpectrogram.length !== valueCount) {
    throw validationFailure(
      'VocoderRequest.melSpectrogram',
      `must contain exactly ${valueCount} values`,
    );
  }
  checkedFloat32ByteCount(valueCount, 'VocoderRequest.melSpectrogram');
  return WireVocoderRequest.create({
    melSpectrogramF32Le: encodeFloat32LE(request.melSpectrogram),
    batchSize: request.batchSize,
    melBinCount: request.melBinCount,
    frameCount: request.frameCount,
  });
}

function validateAndDecodeResult(
  request: VocoderRequest,
  result: WireVocoderResult,
  loadedModelId: string,
): VocoderResult {
  requirePositiveResultInteger(result.batchSize, 'VocoderResult.batchSize');
  requirePositiveResultInteger(result.channelCount, 'VocoderResult.channelCount');
  requirePositiveResultInteger(result.sampleCount, 'VocoderResult.sampleCount');
  requirePositiveResultInteger(result.sampleRateHz, 'VocoderResult.sampleRateHz');
  requirePositiveResultInteger(result.hopLength, 'VocoderResult.hopLength');

  if (result.batchSize !== request.batchSize) {
    throw SDKException.processingFailed('Vocoder result batch size does not match the request.');
  }
  if (result.channelCount !== 1) {
    throw SDKException.processingFailed('The BigVGAN vocoder must return one audio channel.');
  }
  const expectedSamplesPerChannel = checkedResultProduct(
    [request.frameCount, result.hopLength],
    'VocoderResult.sampleCount',
  );
  if (result.sampleCount !== expectedSamplesPerChannel) {
    throw SDKException.processingFailed(
      'Vocoder result sample count does not match frameCount * hopLength.',
    );
  }
  const expectedValues = checkedResultProduct(
    [result.batchSize, result.channelCount, result.sampleCount],
    'VocoderResult.dimensions',
  );
  if (expectedValues > Math.floor(0xffff_ffff / FLOAT32_BYTES)) {
    throw SDKException.processingFailed(
      'VocoderResult.samplesF32Le exceeds the WASM32 address space.',
    );
  }
  if (result.samplesF32Le.byteLength !== expectedValues * FLOAT32_BYTES) {
    throw SDKException.processingFailed('Vocoder returned an invalid float32 waveform byte length.');
  }
  if (result.modelId !== loadedModelId) {
    throw SDKException.processingFailed(
      'Vocoder result model ID does not match the lifecycle-owned model.',
    );
  }
  if (!Number.isSafeInteger(result.processingTimeMs) || result.processingTimeMs < 0) {
    throw SDKException.processingFailed('Vocoder returned an invalid processing time.');
  }

  return {
    samples: decodeFloat32LE(result.samplesF32Le, 'VocoderResult.samplesF32Le'),
    batchSize: result.batchSize,
    channelCount: result.channelCount,
    sampleCount: result.sampleCount,
    sampleRateHz: result.sampleRateHz,
    hopLength: result.hopLength,
    processingTimeMs: result.processingTimeMs,
    modelId: result.modelId,
  };
}

function requireInitialized(): void {
  if (!WebModelLifecycle.supportsNativeLifecycle()) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_NOT_INITIALIZED,
      'RunAnywhere.initialize() must complete before the vocoder can be used.',
      'Vocoder',
    );
  }
}

function requireLoadedModelId(): string {
  const current = WebModelLifecycle.currentModel({
    category: ModelCategory.MODEL_CATEGORY_VOCODER,
    includeModelMetadata: false,
  });
  if (!current?.found || !current.modelId) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_MODEL_NOT_LOADED,
      'No vocoder model is loaded.',
      'Load a vocoder model with RunAnywhere.loadModel() first.',
    );
  }
  return current.modelId;
}

function requireAdapter(): VocoderProtoAdapter {
  const adapter = VocoderProtoAdapter.tryDefault();
  if (!adapter || !adapter.supportsLifecycleProtoVocoder()) {
    throw SDKException.backendNotAvailable(
      'Vocoder',
      'Register the ONNX Web backend built with _rac_vocoder_vocode_lifecycle_proto.',
    );
  }
  return adapter;
}

/** Convert a mel spectrogram with the lifecycle-owned vocoder model. */
export async function vocode(request: VocoderRequest): Promise<VocoderResult> {
  requireInitialized();
  const wireRequest = validateAndEncodeRequest(request);
  const loadedModelId = requireLoadedModelId();
  const result = await requireAdapter().vocodeLifecycle(wireRequest);
  if (!result) {
    throw SDKException.backendNotAvailable(
      'Vocoder',
      'The native Web vocoder operation returned no result.',
    );
  }
  return validateAndDecodeResult(request, result, loadedModelId);
}
