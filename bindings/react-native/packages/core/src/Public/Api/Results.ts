/**
 * Projection of the generated proto results onto the public v3 result shapes.
 *
 * Proto results carry a structured `error` (SDKError) submessage; the public
 * surface throws instead, so every mapper here raises an {@link SDKException}
 * when a proto result reports failure rather than handing back a half-filled
 * object.
 */

import { FinishReason as ProtoFinishReason } from '@runanywhere/proto-ts/finish_reason';
import type { LLMGenerationResult } from '@runanywhere/proto-ts/llm_options';
import type { STTOutput, STTServiceState } from '@runanywhere/proto-ts/stt_options';
import type { TTSOutput, TTSVoiceInfo } from '@runanywhere/proto-ts/tts_options';
import type { VADResult } from '@runanywhere/proto-ts/vad_options';
import type { EmbeddingsResult } from '@runanywhere/proto-ts/embeddings_options';
import type { RerankResult } from '@runanywhere/proto-ts/rerank';
import type { DiffusionResult } from '@runanywhere/proto-ts/diffusion_options';
import type { DiarizationResult as DiarizationResultProto } from '@runanywhere/proto-ts/diarization';
import type { SegmentationResult as SegmentationResultProto } from '@runanywhere/proto-ts/segmentation';
import type {
  RAGResult,
  RAGSearchResult,
  RAGStatistics,
} from '@runanywhere/proto-ts/rag';
import type { LoraState as LoraStateProto } from '@runanywhere/proto-ts/lora_options';
import type { StructuredOutputResult } from '@runanywhere/proto-ts/structured_output';
import type { VLMResult } from '@runanywhere/proto-ts/vlm_options';
import type { SDKError } from '@runanywhere/proto-ts/errors';

import { SDKException } from '../../Foundation/Errors/SDKException';
import { fromAudioFormat } from './Options';
import type {
  Audio,
  AudioChunk,
  DiarizationResult,
  Embedding,
  FinishReason,
  GenerationResult,
  ImageResult,
  LoraState,
  Match,
  RagResult,
  RagStats,
  RankedResult,
  SegmentationResult,
  StructuredOutputMode,
  StructuredResult,
  SttState,
  Transcription,
  VadResult,
  Voice,
} from './Types';

/** Raise the structured proto error carried by a result, if any. */
function throwIfFailed(result: { error?: SDKError }): void {
  if (!result.error) return;
  throw new SDKException(result.error);
}

/**
 * Map VLM's raw finish-reason string onto the public union.
 *
 * `VLMResult.finishReason` stays a plain string on the wire ("stop" |
 * "length" | "stop_sequence"), unlike the LLM path's `FinishReason` enum.
 */
function toFinishReason(raw: string): FinishReason {
  switch (raw.toLowerCase()) {
    case 'length':
    case 'max_tokens':
      return 'length';
    case 'tool_calls':
    case 'toolcalls':
      return 'toolCalls';
    case 'cancelled':
    case 'canceled':
      return 'cancelled';
    case 'error':
      return 'error';
    case '':
    case 'unspecified':
    case 'unknown':
      return 'unknown';
    default:
      return 'stop';
  }
}

/**
 * Map the wire `FinishReason` enum onto the public union.
 * Never invents `toolCalls` / `stop` from tool-call counts or local state;
 * `UNSPECIFIED` stays `unknown`.
 */
export function fromFinishReason(raw: ProtoFinishReason): FinishReason {
  switch (raw) {
    case ProtoFinishReason.FINISH_REASON_STOP:
    case ProtoFinishReason.FINISH_REASON_STOP_SEQUENCE:
      return 'stop';
    case ProtoFinishReason.FINISH_REASON_LENGTH:
    case ProtoFinishReason.FINISH_REASON_CONTEXT_OVERFLOW:
      return 'length';
    case ProtoFinishReason.FINISH_REASON_TOOL_CALLS:
      return 'toolCalls';
    case ProtoFinishReason.FINISH_REASON_CANCELLED:
      return 'cancelled';
    case ProtoFinishReason.FINISH_REASON_ERROR:
      return 'error';
    case ProtoFinishReason.FINISH_REASON_UNSPECIFIED:
    default:
      return 'unknown';
  }
}

/** Project a one-shot LLM result onto the public generation result. */
export function toGenerationResult(
  result: LLMGenerationResult,
  requestId: string
): GenerationResult {
  throwIfFailed(result);
  return {
    text: result.text,
    ...(result.thinkingContent ? { thinkingText: result.thinkingContent } : {}),
    toolCalls: result.toolCalls,
    finishReason: fromFinishReason(result.finishReason),
    inputTokens: result.usage?.inputTokens ?? 0,
    outputTokens: result.usage?.outputTokens ?? 0,
    timeToFirstTokenMs: Math.round(result.usage?.ttftMs ?? 0),
    tokensPerSecond: result.usage?.decodeTokensPerSecond ?? 0,
    requestId,
    model: result.modelUsed,
  };
}

/**
 * Project a terminal stream result onto the public generation result.
 *
 * `LLMStreamFinalResult` is deleted outright: the stream terminates with the
 * same `LLMGenerationResult` the unary call returns, so this is
 * `toGenerationResult` with a `model` fallback for when `modelUsed` is empty.
 */
export function toGenerationResultFromStream(
  final: LLMGenerationResult,
  requestId: string,
  model: string
): GenerationResult {
  const result = toGenerationResult(final, requestId);
  return result.model ? result : { ...result, model };
}

/** Project a VLM result onto the public generation result. */
export function toGenerationResultFromVlm(
  result: VLMResult,
  requestId: string,
  model: string
): GenerationResult {
  throwIfFailed(result);
  return {
    text: result.text,
    toolCalls: [],
    finishReason: toFinishReason(result.finishReason),
    inputTokens: result.usage?.inputTokens ?? 0,
    outputTokens: result.usage?.outputTokens ?? 0,
    timeToFirstTokenMs: Math.round(result.usage?.ttftMs ?? 0),
    tokensPerSecond: result.usage?.decodeTokensPerSecond ?? 0,
    requestId,
    model,
  };
}

/**
 * Empty metrics shell for a terminal stream event that carries no
 * `LLMGenerationResult`. Metrics stay zero — never wall-clock fabricated.
 * Callers may overlay accumulated transport text/thinking as content only.
 */
export function emptyGenerationResult(
  requestId: string,
  model: string
): GenerationResult {
  return {
    text: '',
    toolCalls: [],
    finishReason: 'stop',
    inputTokens: 0,
    outputTokens: 0,
    timeToFirstTokenMs: 0,
    tokensPerSecond: 0,
    requestId,
    model,
  };
}

/**
 * Terminal stream completion without a commons result: preserve accumulated
 * text/thinking as transport content only. Metrics remain zero.
 */
export function generationResultFromAccumulated(
  requestId: string,
  model: string,
  text: string,
  thinking = ''
): GenerationResult {
  return {
    ...emptyGenerationResult(requestId, model),
    text,
    ...(thinking ? { thinkingText: thinking } : {}),
  };
}

/**
 * Project a structured-output result onto the public structured result.
 *
 * `StructuredOutputResult.parsedJson` (bytes) is renamed `json` (a plain UTF-8
 * string) outright — no decode step is needed anymore.
 */
export function toStructuredResult<T>(
  result: StructuredOutputResult,
  metrics: GenerationResult,
  mode: StructuredOutputMode = 'validationOnly'
): StructuredResult<T> {
  throwIfFailed(result);
  const raw = result.rawText ?? '';
  const json = result.json;
  let value: T | null = null;
  let parsed = false;
  if (json.length > 0) {
    try {
      value = JSON.parse(json) as T;
      parsed = true;
    } catch {
      value = null;
    }
  }
  return {
    ...metrics,
    text: raw.length > 0 ? raw : json,
    value,
    raw: raw.length > 0 ? raw : json,
    valid: parsed && (result.validation?.isValid ?? true),
    mode,
  };
}

/** Project an STT result onto the public transcription. */
export function toTranscription(output: STTOutput): Transcription {
  throwIfFailed(output);
  return {
    text: output.text,
    ...(output.language ? { language: output.language } : {}),
    confidence: output.confidence,
    words: output.words.map((word) => ({
      text: word.word,
      startMs: word.startMs,
      endMs: word.endMs,
      confidence: word.confidence,
      ...(word.speakerId ? { speakerId: word.speakerId } : {}),
    })),
    durationMs: output.durationMs,
  };
}

/** Project the STT component state onto the public state. */
export function toSttState(state: STTServiceState): SttState {
  return {
    isReady: state.isReady,
    ...(state.currentModel ? { modelId: state.currentModel } : {}),
    supportsStreaming: state.supportsStreaming,
    languages: state.supportedLanguageCodes,
  };
}

/** Project a TTS result onto the public audio. */
export function toAudio(output: TTSOutput): Audio {
  throwIfFailed(output);
  return {
    data: output.audioData,
    sampleRate: output.sampleRate,
    format: fromAudioFormat(output.audioFormat),
    durationMs: output.durationMs,
  };
}

/** Project a streamed TTS chunk onto the public audio chunk. */
export function toAudioChunk(output: TTSOutput): AudioChunk {
  throwIfFailed(output);
  return {
    data: output.audioData,
    index: output.chunkIndex,
    isFinal: output.isFinal,
  };
}

/**
 * Project a TTS voice descriptor onto the public voice.
 *
 * `TTSVoiceGender` and `TTSVoiceInfo.gender` are deleted from
 * `tts_options.proto` outright — voice gender is no longer exposed.
 */
export function toVoice(info: TTSVoiceInfo): Voice {
  return {
    id: info.id,
    name: info.displayName,
    language: info.languageCode,
  };
}

/**
 * Project a VAD result onto the public verdict.
 *
 * `VADResult.confidence`/`startTimeMs`/`endTimeMs` are deleted outright
 * (idl/vad_options.proto): confidence is renamed `probability`, and the
 * start/end pair has no replacement — the result now only carries
 * `timestampMs` (frame start) + `durationMs` (frame length). Derive the one
 * segment this frame represents from that pair instead of a span, mirroring
 * Swift's `VadResult.init(proto:)`.
 */
export function toVadResult(result: VADResult): VadResult {
  throwIfFailed(result);
  return {
    isSpeech: result.isSpeech,
    probability: result.probability,
    segments:
      result.isSpeech && result.durationMs > 0
        ? [
            {
              startMs: result.timestampMs,
              endMs: result.timestampMs + result.durationMs,
            },
          ]
        : [],
  };
}

/**
 * Project an embeddings result onto the public vectors, in input order.
 *
 * `EmbeddingsResult.error` is deleted outright — the message carries no
 * failure channel, so there is nothing left to `throwIfFailed` on here.
 */
export function toEmbeddings(result: EmbeddingsResult): Embedding[] {
  return result.vectors
    .map((vector, position) => ({
      index: vector.inputIndex > 0 ? vector.inputIndex : position,
      vector: vector.values,
    }))
    .sort((left, right) => left.index - right.index);
}

/** Project a rerank result onto the public ranked pointers, best first. */
export function toRankedResults(result: RerankResult): RankedResult[] {
  return result.items
    .map((item) => ({ index: item.index, relevanceScore: item.relevanceScore }))
    .sort((left, right) => right.relevanceScore - left.relevanceScore);
}

/**
 * Project a diffusion result onto the public image result.
 *
 * `DiffusionResult.imageData`/`batchImages`/`width`/`height`/
 * `imageMediaType`/`seedUsed` are deleted outright: the result now carries a
 * flat `images: DiffusionImage[]`, each with its own `data`/`width`/`height`/
 * `mediaType`/`seedUsed`.
 */
export function toImageResult(result: DiffusionResult): ImageResult {
  return {
    images: result.images.map((image) => ({
      data: image.data,
      width: image.width,
      height: image.height,
      ...(image.mediaType ? { mediaType: image.mediaType } : {}),
    })),
    seed: Number(result.images[0]?.seedUsed ?? 0),
    steps: 0,
  };
}

/** Project a diarization result onto the public speaker turns. */
export function toDiarizationResult(
  result: DiarizationResultProto
): DiarizationResult {
  return {
    segments: result.segments.map((segment) => ({
      speakerId: segment.speakerId || `speaker-${segment.speakerIndex}`,
      startMs: segment.startMs,
      endMs: segment.endMs,
    })),
    speakerCount: result.speakerCount,
  };
}

/**
 * Project a segmentation result onto the public mask.
 *
 * Commons owns `SegmentationClassSummary.fraction` (tag 5).
 */
export function toSegmentationResult(
  result: SegmentationResultProto
): SegmentationResult {
  const mask = result.classMaskU16Le;
  const classMask = new Uint16Array(
    mask.buffer.slice(mask.byteOffset, mask.byteOffset + mask.byteLength)
  );
  return {
    classMask,
    width: result.width,
    height: result.height,
    classes: result.classSummaries.map((summary) => ({
      id: summary.classId,
      label: summary.label,
      pixelCount: Number(summary.pixelCount),
      fraction: summary.fraction,
    })),
    ...(result.diagnosticRgba && result.diagnosticRgba.byteLength > 0
      ? { diagnosticImage: result.diagnosticRgba }
      : {}),
  };
}

/** Project a retrieved chunk onto the public match. */
export function toMatch(chunk: RAGSearchResult): Match {
  return {
    text: chunk.text,
    score: chunk.score,
    metadata: chunk.metadata,
  };
}

/** Project a RAG result onto the public answer plus sources and metrics. */
export function toRagResult(result: RAGResult): RagResult {
  throwIfFailed(result);
  return {
    answer: result.answer,
    sources: result.retrievedChunks.map(toMatch),
    text: result.answer,
    ...(result.thinkingContent ? { thinkingText: result.thinkingContent } : {}),
    toolCalls: [],
    finishReason: 'stop',
    inputTokens: result.usage?.inputTokens ?? 0,
    outputTokens: result.usage?.outputTokens ?? 0,
    // Commons TokenUsage only — never map retrievalTimeMs→TTFT or derive tok/s.
    timeToFirstTokenMs: Math.round(result.usage?.ttftMs ?? 0),
    tokensPerSecond: result.usage?.decodeTokensPerSecond ?? 0,
    requestId: result.requestId,
    model: '',
  };
}

/** Project RAG index counters onto the public stats. */
export function toRagStats(stats: RAGStatistics): RagStats {
  return {
    documentCount: Number(stats.indexedDocuments),
    chunkCount: Number(stats.indexedChunks),
    indexSizeBytes: Number(stats.vectorStoreSizeBytes),
  };
}

/** Project the LoRA snapshot onto the public applied-adapter list. */
export function toLoraState(state: LoraStateProto): LoraState {
  return {
    applied: state.loadedAdapters
      .filter((adapter) => adapter.applied)
      .map((adapter) => ({
        id: adapter.adapterId || adapter.adapterPath,
        scale: adapter.scale,
      })),
  };
}
