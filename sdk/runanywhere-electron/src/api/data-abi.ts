// data-abi.ts — typed access to the commons embeddings, rerank, diarization,
// and segmentation proto ABIs.
//
// Three of the four read the model the lifecycle load made resident. Rerank is
// the exception and it is commons' shape, not a shortcut here: there is no
// `rac_rerank_*_lifecycle_proto`, only the component-handle form, so the
// backend supplies the handle and the request omits it.

import {
  DiarizationRequest,
  DiarizationResult,
} from '@runanywhere/proto-ts/diarization';
import {
  EmbeddingsInputType,
  EmbeddingsPoolingStrategy,
  EmbeddingsRequest,
  EmbeddingsResult,
} from '@runanywhere/proto-ts/embeddings_options';
import { AudioEncoding } from '@runanywhere/proto-ts/model_types';
import { RerankRequest, RerankResult } from '@runanywhere/proto-ts/rerank';
import {
  SegmentationPixelFormat,
  SegmentationRequest,
  SegmentationResult,
} from '@runanywhere/proto-ts/segmentation';
import type { RaBackend } from './backend';
import { invokeProto } from './proto-abi';
import { SEGMENTATION_DEFAULTS, optionDefaults } from './options';
import type { DiarizationOptions, EmbedOptions, SegmentationOptions } from './options';
import { NormalizeMode, PoolingMode, newRequestId } from './types';

const POOLING_TO_PROTO: Record<PoolingMode, EmbeddingsPoolingStrategy> = {
  [PoolingMode.MEAN]: EmbeddingsPoolingStrategy.EMBEDDINGS_POOLING_STRATEGY_MEAN,
  [PoolingMode.CLS]: EmbeddingsPoolingStrategy.EMBEDDINGS_POOLING_STRATEGY_CLS,
  [PoolingMode.LAST]: EmbeddingsPoolingStrategy.EMBEDDINGS_POOLING_STRATEGY_LAST,
};

/**
 * One batch of texts plus how to pool and normalize them.
 *
 * `normalize` is the field that used to be lost: the public option existed and
 * the component ABI had nowhere to put it, so L2 and NONE produced the same
 * vectors. It is OPTIONAL on the wire, so unset is left absent and commons
 * applies its own `rac_default`; the plain scalars come from
 * `embeddingsOptionsDefaults()` rather than being typed out here.
 */
export function toEmbeddingsRequest(
  texts: string[],
  options: EmbedOptions,
  requestId = newRequestId('embed')
): EmbeddingsRequest {
  const defaults = optionDefaults.embed();
  return EmbeddingsRequest.fromPartial({
    requestId,
    texts,
    options: {
      ...defaults,
      normalize: options.normalize ? options.normalize === NormalizeMode.L2 : undefined,
      pooling: options.pooling ? POOLING_TO_PROTO[options.pooling] : defaults.pooling,
    },
  });
}

export function toRerankRequest(
  query: string,
  documents: string[],
  topN?: number
): RerankRequest {
  return RerankRequest.fromPartial({
    query,
    documents,
    options: { topN: topN ?? 0, maxTokensPerDoc: 0 },
  });
}

/**
 * Diarization takes raw float samples. Commons accepts F32LE or S16LE and
 * normalizes either before dispatch; it rejects anything else, and it does not
 * resample, so the caller has already brought this to 16 kHz.
 */
export function toDiarizationRequest(
  samples: Float32Array,
  options: DiarizationOptions,
  sampleRate: number
): DiarizationRequest {
  const defaults = optionDefaults.diarization();
  return DiarizationRequest.fromPartial({
    audioData: new Uint8Array(samples.buffer, samples.byteOffset, samples.byteLength),
    options: {
      ...defaults,
      sampleRate,
      channels: 1,
      encoding: AudioEncoding.AUDIO_ENCODING_PCM_F32_LE,
      // Optional on the wire: unset lets commons pick the model's own bar.
      threshold: options.threshold,
      minimumDurationMs: options.minimumDurationMs ?? defaults.minimumDurationMs,
      mergeGapMs: options.mergeGapMs ?? defaults.mergeGapMs,
    },
  });
}

export function toSegmentationRequest(
  data: Uint8Array,
  width: number,
  height: number,
  options: SegmentationOptions
): SegmentationRequest {
  return SegmentationRequest.fromPartial({
    image: {
      data,
      width,
      height,
      pixelFormat: SegmentationPixelFormat.SEGMENTATION_PIXEL_FORMAT_RGB8,
    },
    options: {
      // `SegmentationOptions` carries no `rac_default` annotations, so the
      // proto3 zero value IS the default; SEGMENTATION_DEFAULTS names it once.
      includeDiagnosticRgba:
        options.includeDiagnosticImage ?? SEGMENTATION_DEFAULTS.includeDiagnosticImage,
      includeConfidence: false,
    },
  });
}

/**
 * The class mask is `width * height` little-endian uint16 values. Reading it
 * through a DataView rather than casting the buffer keeps it correct on a
 * big-endian host and on a byte offset a Uint16Array could not accept.
 */
export function toClassMask(result: SegmentationResult): Uint16Array {
  const bytes = result.classMaskU16Le;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const mask = new Uint16Array(Math.floor(bytes.byteLength / 2));
  for (let i = 0; i < mask.length; i++) mask[i] = view.getUint16(i * 2, true);
  return mask;
}

/** The commons embeddings, rerank, diarization, and segmentation layers. */
export class DataAbi {
  constructor(private readonly backend: RaBackend) {}

  async embed(request: EmbeddingsRequest): Promise<EmbeddingsResult> {
    return invokeProto(
      (bytes) => this.backend.embedBatchProto(bytes),
      EmbeddingsRequest,
      request,
      EmbeddingsResult
    );
  }

  async rerank(request: RerankRequest): Promise<RerankResult> {
    return invokeProto(
      (bytes) => this.backend.rerankProto(bytes),
      RerankRequest,
      request,
      RerankResult
    );
  }

  async diarize(request: DiarizationRequest): Promise<DiarizationResult> {
    return invokeProto(
      (bytes) => this.backend.diarizeProto(bytes),
      DiarizationRequest,
      request,
      DiarizationResult
    );
  }

  async segment(request: SegmentationRequest): Promise<SegmentationResult> {
    return invokeProto(
      (bytes) => this.backend.segmentProto(bytes),
      SegmentationRequest,
      request,
      SegmentationResult
    );
  }
}

export type { DiarizationResult, EmbeddingsResult, RerankResult, SegmentationResult };
