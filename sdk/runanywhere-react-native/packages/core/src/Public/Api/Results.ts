/**
 * Projection of the generated proto results onto the public v3 result shapes.
 *
 * Proto results carry a structured `error` (SDKError) submessage; the public
 * surface throws instead, so every mapper here raises an {@link SDKException}
 * when a proto result reports failure rather than handing back a half-filled
 * object.
 */

import type { LLMGenerationResult } from '@runanywhere/proto-ts/llm_options';
import type { LLMStreamFinalResult } from '@runanywhere/proto-ts/llm_service';
import type { STTOutput, STTServiceState } from '@runanywhere/proto-ts/stt_options';
import type { TTSOutput, TTSVoiceInfo } from '@runanywhere/proto-ts/tts_options';
import { TTSVoiceGender } from '@runanywhere/proto-ts/tts_options';
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
import type { LoRAState } from '@runanywhere/proto-ts/lora_options';
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

function toFinishReason(raw: string, toolCallCount: number): FinishReason {
  if (toolCallCount > 0) return 'toolCalls';
  switch (raw.toLowerCase()) {
    case 'length':
    case 'max_tokens':
      return 'length';
    case 'cancelled':
    case 'canceled':
      return 'cancelled';
    default:
      return 'stop';
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
    toolCalls: [],
    finishReason: toFinishReason(result.finishReason, 0),
    inputTokens: result.usage?.inputTokens ?? 0,
    outputTokens: result.usage?.outputTokens ?? 0,
    timeToFirstTokenMs: Math.round(result.ttftMs ?? 0),
    tokensPerSecond: result.usage?.tokensPerSecond ?? 0,
    requestId,
    model: result.modelUsed,
  };
}

/** Project a terminal stream result onto the public generation result. */
export function toGenerationResultFromStream(
  final: LLMStreamFinalResult,
  requestId: string,
  model: string
): GenerationResult {
  throwIfFailed(final);
  return {
    text: final.text,
    ...(final.thinkingContent ? { thinkingText: final.thinkingContent } : {}),
    toolCalls: final.toolCalls,
    finishReason: toFinishReason(final.finishReason, final.toolCalls.length),
    inputTokens: final.usage?.inputTokens ?? 0,
    outputTokens: final.usage?.outputTokens ?? 0,
    timeToFirstTokenMs: final.timeToFirstTokenMs,
    tokensPerSecond: final.usage?.tokensPerSecond ?? 0,
    requestId,
    model,
  };
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
    finishReason: toFinishReason(result.finishReason, 0),
    inputTokens: result.usage?.inputTokens ?? 0,
    outputTokens: result.usage?.outputTokens ?? 0,
    timeToFirstTokenMs: result.timeToFirstTokenMs,
    tokensPerSecond: result.usage?.tokensPerSecond ?? 0,
    requestId,
    model,
  };
}

/** Fill a generation result for callers that only aggregated tokens. */
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

/** Project a structured-output result onto the public structured result. */
export function toStructuredResult<T>(
  result: StructuredOutputResult,
  metrics: GenerationResult
): StructuredResult<T> {
  throwIfFailed(result);
  const raw = result.rawText ?? '';
  const json = new TextDecoder('utf-8').decode(result.parsedJson);
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

/** Project a TTS voice descriptor onto the public voice. */
export function toVoice(info: TTSVoiceInfo): Voice {
  const gender =
    info.gender === TTSVoiceGender.TTS_VOICE_GENDER_MALE
      ? 'male'
      : info.gender === TTSVoiceGender.TTS_VOICE_GENDER_FEMALE
        ? 'female'
        : info.gender === TTSVoiceGender.TTS_VOICE_GENDER_NEUTRAL
          ? 'neutral'
          : undefined;
  return {
    id: info.id,
    name: info.displayName,
    language: info.languageCode,
    ...(gender ? { gender } : {}),
  };
}

/** Project a VAD result onto the public verdict. */
export function toVadResult(result: VADResult): VadResult {
  throwIfFailed(result);
  return {
    isSpeech: result.isSpeech,
    probability: result.confidence,
    segments:
      result.isSpeech && result.endTimeMs > result.startTimeMs
        ? [{ startMs: result.startTimeMs, endMs: result.endTimeMs }]
        : [],
  };
}

/** Project an embeddings result onto the public vectors, in input order. */
export function toEmbeddings(result: EmbeddingsResult): Embedding[] {
  throwIfFailed(result);
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

/** Project a diffusion result onto the public image result. */
export function toImageResult(result: DiffusionResult): ImageResult {
  throwIfFailed(result);
  const images = [
    ...(result.imageData.byteLength > 0 ? [result.imageData] : []),
    ...result.batchImages,
  ];
  return {
    images: images.map((data) => ({
      data,
      width: result.width,
      height: result.height,
      ...(result.imageMediaType ? { mediaType: result.imageMediaType } : {}),
    })),
    seed: Number(result.seedUsed),
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

/** Project a segmentation result onto the public mask. */
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
    score: chunk.similarityScore,
    metadata: chunk.metadata,
  };
}

/** Project a RAG result onto the public answer plus sources and metrics. */
export function toRagResult(result: RAGResult): RagResult {
  throwIfFailed(result);
  const outputTokens = result.usage?.outputTokens ?? 0;
  const totalMs = Number(result.generationTimeMs);
  return {
    answer: result.answer,
    sources: result.retrievedChunks.map(toMatch),
    text: result.answer,
    ...(result.thinkingContent ? { thinkingText: result.thinkingContent } : {}),
    toolCalls: [],
    finishReason: 'stop',
    inputTokens: result.usage?.inputTokens ?? 0,
    outputTokens,
    timeToFirstTokenMs: Number(result.retrievalTimeMs),
    tokensPerSecond: totalMs > 0 ? outputTokens / (totalMs / 1000) : 0,
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
export function toLoraState(state: LoRAState): LoraState {
  return {
    applied: state.loadedAdapters
      .filter((adapter) => adapter.applied)
      .map((adapter) => ({
        id: adapter.adapterId || adapter.adapterPath,
        scale: adapter.scale,
      })),
  };
}
