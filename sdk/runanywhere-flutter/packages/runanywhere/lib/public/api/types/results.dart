// SPDX-License-Identifier: Apache-2.0
//
// Public result types for the v3 API surface. Each type is built from the
// generated proto the commons ABI returns, so field names stay spec-shaped
// while the wire contract stays canonical.

// prefer_initializing_formals cannot apply to LoadedModel/SpeechHandle: their
// handler fields are private and set via named parameters, and Dart forbids
// named initializing formals that start with an underscore.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/diarization.pb.dart' as diar_pb;
import 'package:runanywhere/generated/diffusion_options.pb.dart' as diff_pb;
import 'package:runanywhere/generated/embeddings_options.pb.dart' as embed_pb;
import 'package:runanywhere/generated/llm_options.pb.dart'
    show LLMGenerationResult;
import 'package:runanywhere/generated/llm_options.pbenum.dart'
    as llm_enum
    show FinishReason;
import 'package:runanywhere/generated/lora_options.pb.dart' as lora_pb;
import 'package:runanywhere/generated/model_types.pb.dart' show ModelInfo;
import 'package:runanywhere/generated/model_types.pbenum.dart'
    show AudioFormat, InferenceFramework, ModelCategory;
import 'package:runanywhere/generated/rag.pb.dart' as rag_pb;
import 'package:runanywhere/generated/rerank.pb.dart' as rerank_pb;
import 'package:runanywhere/generated/segmentation.pb.dart' as seg_pb;
import 'package:runanywhere/generated/storage_types.pb.dart' show StorageInfo;
import 'package:runanywhere/generated/structured_output.pb.dart'
    show StructuredOutputResult;
import 'package:runanywhere/generated/stt_options.pb.dart' as stt_pb;
import 'package:runanywhere/generated/tool_calling.pb.dart'
    show ToolCall, ToolResult;
import 'package:runanywhere/generated/tts_options.pb.dart' as tts_pb;
import 'package:runanywhere/generated/vad_options.pb.dart' as vad_pb;
import 'package:runanywhere/generated/vlm_options.pb.dart' as vlm_pb;
import 'package:runanywhere/public/api/types/options.dart'
    show BackendPreference;

/// Why a generation stopped.
enum FinishReason {
  /// The model emitted a stop token or stop sequence.
  stop,

  /// The output-token budget ran out.
  length,

  /// The model asked to call one or more tools.
  toolCalls,

  /// The caller cancelled the request.
  cancelled,
}

/// Maps the generated `FinishReason` enum (llm_options.proto) onto the
/// public v3 [FinishReason]. [hasToolCalls] backstops the UNSPECIFIED /
/// STOP wire values the way the string-based converter used to (a model
/// that made tool calls but whose backend never set the enum still reports
/// `toolCalls`).
FinishReason _finishReason(
  llm_enum.FinishReason wire, {
  bool hasToolCalls = false,
}) {
  switch (wire) {
    case llm_enum.FinishReason.FINISH_REASON_LENGTH:
    case llm_enum.FinishReason.FINISH_REASON_CONTEXT_OVERFLOW:
      return FinishReason.length;
    case llm_enum.FinishReason.FINISH_REASON_CANCELLED:
      return FinishReason.cancelled;
    case llm_enum.FinishReason.FINISH_REASON_TOOL_CALLS:
      return FinishReason.toolCalls;
    case llm_enum.FinishReason.FINISH_REASON_STOP:
    case llm_enum.FinishReason.FINISH_REASON_STOP_SEQUENCE:
    case llm_enum.FinishReason.FINISH_REASON_ERROR:
    case llm_enum.FinishReason.FINISH_REASON_UNSPECIFIED:
    default:
      return hasToolCalls ? FinishReason.toolCalls : FinishReason.stop;
  }
}

/// `VLMResult.finishReason` (vlm_options.proto) is still a raw wire string
/// (VLM never migrated to the shared `FinishReason` enum) — parse it the
/// same way the pre-migration string converter did.
FinishReason _finishReasonFromString(String wire, {bool hasToolCalls = false}) {
  switch (wire.toLowerCase()) {
    case 'length':
    case 'max_tokens':
      return FinishReason.length;
    case 'cancelled':
    case 'canceled':
      return FinishReason.cancelled;
    case 'tool_calls':
      return FinishReason.toolCalls;
    default:
      return hasToolCalls ? FinishReason.toolCalls : FinishReason.stop;
  }
}

/// Text, tool calls, and metrics from one generation.
class GenerationResult {
  /// Build a generation result directly. Prefer the named factories.
  const GenerationResult({
    required this.text,
    this.thinkingText,
    this.toolCalls = const <ToolCall>[],
    this.toolResults = const <ToolResult>[],
    this.finishReason = FinishReason.stop,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.timeToFirstTokenMs = 0,
    this.tokensPerSecond = 0,
    this.requestId = '',
    this.model = '',
  });

  /// Build from the generated unary LLM result.
  factory GenerationResult.fromLlm(
    LLMGenerationResult proto, {
    String requestId = '',
  }) => GenerationResult(
    text: proto.text,
    thinkingText: proto.hasThinkingContent() && proto.thinkingContent.isNotEmpty
        ? proto.thinkingContent
        : null,
    toolCalls: List<ToolCall>.unmodifiable(proto.toolCalls),
    toolResults: List<ToolResult>.unmodifiable(proto.toolResults),
    finishReason: _finishReason(
      proto.finishReason,
      hasToolCalls: proto.toolCalls.isNotEmpty,
    ),
    inputTokens: proto.usage.inputTokens,
    outputTokens: proto.usage.outputTokens,
    timeToFirstTokenMs: proto.usage.hasTtftMs()
        ? proto.usage.ttftMs.toInt()
        : 0,
    tokensPerSecond: proto.usage.decodeTokensPerSecond,
    requestId: requestId,
    model: proto.modelUsed,
  );

  // `GenerationResult.fromStreamFinal` is deleted: `LLMStreamFinalResult` was
  // removed outright (idl/llm_service.proto — "the stream terminates with
  // the same [result]"). The stream now terminates with
  // `LLMStreamEvent.result` (an `LLMGenerationResult`), so callers use
  // `GenerationResult.fromLlm` directly against that field.

  /// Build from the generated VLM result.
  factory GenerationResult.fromVlm(
    vlm_pb.VLMResult proto, {
    String requestId = '',
    String model = '',
  }) => GenerationResult(
    text: proto.text,
    toolCalls: const <ToolCall>[],
    finishReason: _finishReasonFromString(proto.finishReason),
    inputTokens: proto.usage.inputTokens,
    outputTokens: proto.usage.outputTokens,
    timeToFirstTokenMs: proto.usage.hasTtftMs()
        ? proto.usage.ttftMs.toInt()
        : 0,
    tokensPerSecond: proto.usage.decodeTokensPerSecond,
    requestId: requestId,
    model: model,
  );

  /// Generated text with thinking content removed.
  final String text;

  /// Thinking content, when the model produced it and the caller asked for it.
  final String? thinkingText;

  /// Tool calls the model requested.
  final List<ToolCall> toolCalls;

  /// Results of the tool calls the SDK executed during the loop. Beyond the v3
  /// spec, but commons returns them and callers need them to show what ran.
  final List<ToolResult> toolResults;

  /// Why generation stopped.
  final FinishReason finishReason;

  /// Prompt tokens consumed.
  final int inputTokens;

  /// Completion tokens produced.
  final int outputTokens;

  /// Latency to the first emitted token.
  final int timeToFirstTokenMs;

  /// Decode throughput.
  final double tokensPerSecond;

  /// Correlation id for this request.
  final String requestId;

  /// Model that produced the text.
  final String model;
}

/// Parsed value plus the raw text and metrics of a structured generation.
class StructuredResult {
  /// Build a structured result.
  const StructuredResult({
    required this.value,
    required this.raw,
    required this.valid,
    required this.metrics,
  });

  /// Build from the generated structured-output result.
  ///
  /// `StructuredOutputResult.parsedJson` (bytes) was renamed `json` (a plain
  /// UTF-8 string; idl/structured_output.proto: "Parse it client-side").
  factory StructuredResult.fromProto(
    StructuredOutputResult proto,
    GenerationResult metrics,
  ) => StructuredResult(
    value: Uint8List.fromList(utf8.encode(proto.json)),
    raw: proto.hasRawText() ? proto.rawText : metrics.text,
    valid: proto.validation.isValid,
    metrics: metrics,
  );

  /// Canonical JSON bytes of the parsed value.
  final Uint8List value;

  /// Raw model output before parsing.
  final String raw;

  /// True when the output satisfied the schema.
  final bool valid;

  /// Metrics for the generation that produced this value.
  final GenerationResult metrics;
}

/// One word of a transcription with its timing.
class Word {
  /// Build a timed word.
  const Word({
    required this.text,
    required this.startMs,
    required this.endMs,
    required this.confidence,
    this.speakerId,
  });

  /// Word text.
  final String text;

  /// Offset of the word's onset from the start of the audio.
  final int startMs;

  /// Offset of the word's end from the start of the audio.
  final int endMs;

  /// Model confidence in this word.
  final double confidence;

  /// Speaker this word belongs to, when diarization ran.
  final String? speakerId;
}

/// Transcribed text with timings and language.
class Transcription {
  /// Build a transcription.
  const Transcription({
    required this.text,
    this.language,
    this.confidence = 0,
    this.words = const <Word>[],
    this.durationMs = 0,
  });

  /// Build from the generated STT output.
  factory Transcription.fromProto(stt_pb.STTOutput proto) => Transcription(
    text: proto.text,
    language: proto.hasLanguage() && proto.language.isNotEmpty
        ? proto.language
        : null,
    confidence: proto.confidence,
    words: List<Word>.unmodifiable(
      proto.words.map(
        (w) => Word(
          text: w.word,
          startMs: w.startMs.toInt(),
          endMs: w.endMs.toInt(),
          confidence: w.confidence,
          speakerId: w.hasSpeakerId() && w.speakerId.isNotEmpty
              ? w.speakerId
              : null,
        ),
      ),
    ),
    durationMs: proto.durationMs.toInt(),
  );

  /// Full transcript.
  final String text;

  /// Detected or requested BCP-47 language tag.
  final String? language;

  /// Overall model confidence.
  final double confidence;

  /// Per-word timings, when requested.
  final List<Word> words;

  /// Length of the transcribed audio.
  final int durationMs;
}

/// Synthesized audio buffer.
class Audio {
  /// Build a synthesized audio buffer.
  const Audio({
    required this.data,
    required this.sampleRate,
    required this.format,
    required this.durationMs,
  });

  /// Build from the generated TTS output.
  factory Audio.fromProto(tts_pb.TTSOutput proto) => Audio(
    data: Uint8List.fromList(proto.audioData),
    sampleRate: proto.sampleRate,
    format: proto.audioFormat,
    durationMs: proto.durationMs.toInt(),
  );

  /// Raw audio bytes.
  final Uint8List data;

  /// Samples per second.
  final int sampleRate;

  /// Encoding of [data].
  final AudioFormat format;

  /// Playback length.
  final int durationMs;
}

/// One chunk of a streamed synthesis.
class AudioChunk {
  /// Build a synthesis chunk.
  const AudioChunk({
    required this.data,
    required this.index,
    required this.isFinal,
  });

  /// Build from the generated TTS output.
  factory AudioChunk.fromProto(tts_pb.TTSOutput proto) => AudioChunk(
    data: Uint8List.fromList(proto.audioData),
    index: proto.chunkIndex,
    isFinal: proto.isFinal,
  );

  /// Raw audio bytes for this chunk.
  final Uint8List data;

  /// Zero-based position in the chunk sequence.
  final int index;

  /// True on the last chunk.
  final bool isFinal;
}

/// A span of audio, in milliseconds from the start of the buffer.
class Segment {
  /// Build a time span.
  const Segment({required this.startMs, required this.endMs});

  /// Span start.
  final int startMs;

  /// Span end.
  final int endMs;
}

/// Voice-activity verdict for one buffer.
class VadResult {
  /// Build a detection verdict.
  const VadResult({
    required this.isSpeech,
    required this.probability,
    this.segments = const <Segment>[],
  });

  /// Build from the generated VAD result.
  ///
  /// `confidence` was renamed `probability`, and `start_time_ms`/
  /// `end_time_ms` were deleted outright (idl/vad_options.proto) — this
  /// result no longer carries a span, only the per-frame verdict.
  factory VadResult.fromProto(vad_pb.VADResult proto) => VadResult(
    isSpeech: proto.isSpeech,
    probability: proto.probability,
  );

  /// True when the buffer contains speech.
  final bool isSpeech;

  /// Speech probability for the buffer.
  final double probability;

  /// Speech spans found inside the buffer.
  final List<Segment> segments;
}

/// One embedding vector and its position in the input list.
class Embedding {
  /// Build an embedding.
  const Embedding({required this.index, required this.vector});

  /// Build from the generated embedding vector.
  factory Embedding.fromProto(embed_pb.EmbeddingVector proto) => Embedding(
    index: proto.inputIndex,
    vector: Float32List.fromList(proto.values),
  );

  /// Position of the source text in the request.
  final int index;

  /// Embedding components.
  final Float32List vector;
}

/// One reranked document pointer.
class RankedResult {
  /// Build a ranked pointer.
  const RankedResult({required this.index, required this.relevanceScore});

  /// Build from the generated scored item.
  factory RankedResult.fromProto(rerank_pb.RerankScoredItem proto) =>
      RankedResult(index: proto.index, relevanceScore: proto.relevanceScore);

  /// Position of the document in the request list.
  final int index;

  /// Relevance score. Comparable only within one result set.
  final double relevanceScore;
}

/// One generated image.
class ImageData {
  /// Build an image payload.
  const ImageData({
    required this.bytes,
    required this.width,
    required this.height,
    this.mediaType,
  });

  /// Encoded image bytes.
  final Uint8List bytes;

  /// Pixel width.
  final int width;

  /// Pixel height.
  final int height;

  /// MIME type of [bytes], when the backend reported one.
  final String? mediaType;
}

/// Images produced by one generation, plus the sampling parameters used.
class ImageResult {
  /// Build an image-generation result.
  const ImageResult({
    required this.images,
    required this.seed,
    required this.steps,
  });

  /// Build from the generated diffusion result.
  ///
  /// The flat single-image `DiffusionResult` (`image_data`/`width`/`height`/
  /// `seed_used`/`image_media_type`/`batch_images`) was restructured into
  /// `repeated DiffusionImage images` (idl/diffusion_options.proto), each
  /// entry carrying its own `data`/`width`/`height`/`seedUsed`/`mediaType`
  /// per-image — commons still emits exactly one entry until the C ABI grows
  /// a real batch, but the shape now supports N.
  factory ImageResult.fromProto(
    diff_pb.DiffusionResult proto, {
    required int steps,
  }) {
    final images = proto.images.map(
      (image) => ImageData(
        bytes: Uint8List.fromList(image.data),
        width: image.width,
        height: image.height,
        mediaType: image.mediaType.isNotEmpty ? image.mediaType : null,
      ),
    );
    return ImageResult(
      images: List<ImageData>.unmodifiable(images),
      seed: proto.images.isNotEmpty ? proto.images.first.seedUsed.toInt() : 0,
      steps: steps,
    );
  }

  /// Generated images, in batch order.
  final List<ImageData> images;

  /// Seed the sampler actually used.
  final int seed;

  /// Denoising steps run.
  final int steps;
}

/// One diarized span attributed to a speaker.
class SpeakerSegment {
  /// Build a speaker span.
  const SpeakerSegment({
    required this.speakerId,
    required this.startMs,
    required this.endMs,
  });

  /// Speaker label, stable only within one call or session.
  final String speakerId;

  /// Span start.
  final int startMs;

  /// Span end.
  final int endMs;
}

/// Who spoke when.
class DiarizationResult {
  /// Build a diarization result.
  const DiarizationResult({
    required this.segments,
    required this.speakerCount,
  });

  /// Build from the generated diarization result.
  factory DiarizationResult.fromProto(diar_pb.DiarizationResult proto) =>
      DiarizationResult(
        segments: List<SpeakerSegment>.unmodifiable(
          proto.segments.map(
            (s) => SpeakerSegment(
              speakerId: s.speakerId.isNotEmpty
                  ? s.speakerId
                  : 'speaker_${s.speakerIndex}',
              startMs: s.startMs.toInt(),
              endMs: s.endMs.toInt(),
            ),
          ),
        ),
        speakerCount: proto.speakerCount,
      );

  /// Speaker spans in chronological order.
  final List<SpeakerSegment> segments;

  /// Distinct speakers found.
  final int speakerCount;
}

/// One class present in a segmentation mask.
class ClassInfo {
  /// Build a class summary.
  const ClassInfo({
    required this.classId,
    required this.label,
    required this.pixelCount,
    required this.fraction,
  });

  /// Numeric class id used in the mask.
  final int classId;

  /// Human-readable class name.
  final String label;

  /// Pixels assigned to this class.
  final int pixelCount;

  /// Share of the image covered by this class.
  final double fraction;
}

/// Per-pixel class assignment for one image.
class SegmentationResult {
  /// Build a segmentation result.
  const SegmentationResult({
    required this.classMask,
    required this.width,
    required this.height,
    required this.classes,
    this.diagnosticImage,
  });

  /// Build from the generated segmentation result.
  ///
  /// `SegmentationClassSummary.fraction` was deleted outright
  /// (idl/segmentation.proto) — [ClassInfo.fraction] is derived here from
  /// `pixelCount / (width * height)` instead of trusting a wire value.
  factory SegmentationResult.fromProto(seg_pb.SegmentationResult proto) {
    final totalPixels = proto.width * proto.height;
    return SegmentationResult(
      classMask: Uint16List.sublistView(
        Uint8List.fromList(proto.classMaskU16Le),
      ),
      width: proto.width,
      height: proto.height,
      classes: List<ClassInfo>.unmodifiable(
        proto.classSummaries.map(
          (c) => ClassInfo(
            classId: c.classId,
            label: c.label,
            pixelCount: c.pixelCount.toInt(),
            fraction: totalPixels > 0 ? c.pixelCount.toInt() / totalPixels : 0,
          ),
        ),
      ),
      diagnosticImage: proto.hasDiagnosticRgba()
          ? Uint8List.fromList(proto.diagnosticRgba)
          : null,
    );
  }

  /// One class id per pixel, row-major at source dimensions.
  final Uint16List classMask;

  /// Mask width.
  final int width;

  /// Mask height.
  final int height;

  /// Classes present in the mask.
  final List<ClassInfo> classes;

  /// Class-colour RGBA overlay, when requested.
  final Uint8List? diagnosticImage;
}

/// One retrieved chunk and its similarity to the query.
class Match {
  /// Build a retrieval match.
  const Match({
    required this.text,
    required this.score,
    this.metadata = const <String, String>{},
  });

  /// Build from the generated search result.
  factory Match.fromProto(rag_pb.RAGSearchResult proto) => Match(
    text: proto.text,
    score: proto.score,
    metadata: Map<String, String>.unmodifiable(proto.metadata),
  );

  /// Chunk text.
  final String text;

  /// Similarity to the query.
  final double score;

  /// Metadata carried by the source document.
  final Map<String, String> metadata;
}

/// Grounded answer plus the chunks it was drawn from.
class RagResult {
  /// Build a RAG answer.
  const RagResult({
    required this.answer,
    required this.sources,
    required this.metrics,
  });

  /// Build from the generated RAG result.
  factory RagResult.fromProto(rag_pb.RAGResult proto) => RagResult(
    answer: proto.answer,
    sources: List<Match>.unmodifiable(
      proto.retrievedChunks.map(Match.fromProto),
    ),
    metrics: GenerationResult(
      text: proto.answer,
      thinkingText: proto.hasThinkingContent() ? proto.thinkingContent : null,
      inputTokens: proto.usage.inputTokens,
      outputTokens: proto.usage.outputTokens,
      tokensPerSecond: proto.generationTimeMs.toInt() > 0
          ? proto.usage.outputTokens /
                (proto.generationTimeMs.toInt() / 1000.0)
          : 0,
      requestId: proto.requestId,
    ),
  );

  /// Generated answer.
  final String answer;

  /// Chunks retrieved for the answer.
  final List<Match> sources;

  /// Metrics for the generation half of the query.
  final GenerationResult metrics;
}

/// Readiness of the speech-to-text component.
class SttState {
  /// Build an STT state snapshot.
  const SttState({
    required this.isReady,
    this.modelId,
    this.supportsStreaming = false,
    this.languages = const <String>[],
  });

  /// Build from the generated STT service state.
  factory SttState.fromProto(stt_pb.STTServiceState proto) => SttState(
    isReady: proto.isReady,
    modelId: proto.hasCurrentModel() && proto.currentModel.isNotEmpty
        ? proto.currentModel
        : null,
    supportsStreaming: proto.supportsStreaming,
    languages: List<String>.unmodifiable(proto.supportedLanguageCodes),
  );

  /// True when a model is loaded and can transcribe.
  final bool isReady;

  /// Loaded model id.
  final String? modelId;

  /// True when the model supports incremental transcription.
  final bool supportsStreaming;

  /// BCP-47 tags the model recognizes.
  final List<String> languages;
}

/// One synthesis voice offered by the loaded model.
class Voice {
  /// Build a voice descriptor.
  const Voice({
    required this.id,
    required this.name,
    required this.language,
  });

  /// Build from the generated voice info.
  factory Voice.fromProto(tts_pb.TTSVoiceInfo proto) => Voice(
    id: proto.id,
    name: proto.displayName.isNotEmpty ? proto.displayName : proto.id,
    language: proto.languageCode,
  );

  /// Voice id to pass as `TtsOptions.voice`.
  final String id;

  /// Human-readable voice name.
  final String name;

  /// BCP-47 tag the voice speaks.
  final String language;
}

/// What is loaded and how much storage the SDK is using.
class ModelsState {
  /// Build a models-state snapshot.
  const ModelsState({
    required this.loaded,
    required this.storageUsedBytes,
    required this.storageFreeBytes,
  });

  /// Build from the loaded-model map and the generated storage info.
  factory ModelsState.fromProto(
    Map<ModelCategory, ModelInfo> loaded,
    StorageInfo storage,
  ) => ModelsState(
    loaded: Map<ModelCategory, ModelInfo>.unmodifiable(loaded),
    storageUsedBytes: storage.hasApp()
        ? storage.app.totalBytes.toInt()
        : 0,
    storageFreeBytes: storage.hasDevice()
        ? storage.device.freeBytes.toInt()
        : 0,
  );

  /// Loaded model per category.
  final Map<ModelCategory, ModelInfo> loaded;

  /// Bytes the SDK's own storage occupies.
  final int storageUsedBytes;

  /// Bytes still free on the device.
  final int storageFreeBytes;
}

/// One LoRA adapter currently applied to the loaded model.
class AppliedAdapter {
  /// Build an applied-adapter entry.
  const AppliedAdapter({required this.id, required this.scale});

  /// Adapter id.
  final String id;

  /// Blend weight.
  final double scale;
}

/// Adapters currently applied to the loaded model.
class LoraState {
  /// Build a LoRA state snapshot.
  const LoraState({required this.applied});

  /// Build from the generated LoRA state.
  factory LoraState.fromProto(lora_pb.LoraState proto) => LoraState(
    applied: List<AppliedAdapter>.unmodifiable(
      proto.loadedAdapters.map(
        (a) => AppliedAdapter(
          id: a.adapterId.isNotEmpty ? a.adapterId : a.adapterPath,
          scale: a.scale,
        ),
      ),
    ),
  );

  /// Applied adapters, in application order.
  final List<AppliedAdapter> applied;
}

/// Resident-model ownership handle returned by `models.load`.
///
/// [close] and `models.unload(id)` release the same residency; calling
/// either after the other is a no-op.
class LoadedModel {
  /// Internal — build through `models.load`.
  LoadedModel({
    required this.id,
    required this.category,
    this.requestedBackend,
    required this.actualBackend,
    this.actualDevice = 'unknown',
    this.runtimeVersion,
    this.abiVersion,
    this.fallbackReason,
    required Future<void> Function(String id) closeHandler,
  }) : _closeHandler = closeHandler;

  /// Model id.
  final String id;

  /// Category this model was loaded under.
  final ModelCategory category;

  /// Backend preference that was requested, when one was given.
  final BackendPreference? requestedBackend;

  /// Backend the load actually resolved to.
  final InferenceFramework actualBackend;

  /// Where the model actually runs.
  final String actualDevice;

  /// Native runtime version, when the backend reports one.
  final String? runtimeVersion;

  /// Native ABI version, when the backend reports one.
  final String? abiVersion;

  /// Set when the requested backend/accelerator could not be honored.
  final String? fallbackReason;

  final Future<void> Function(String id) _closeHandler;
  bool _closed = false;

  /// Release this model's residency. Idempotent.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _closeHandler(id);
  }
}

/// Handle to one in-flight or completed `tts.speak`/`VoiceSession.say` utterance.
class SpeechHandle {
  /// Internal — build through `tts.speak`/`VoiceSession.say`.
  SpeechHandle({String? id, required Future<void> Function() interruptHandler})
    : id = id ?? 'speech-${DateTime.now().microsecondsSinceEpoch}',
      _interruptHandler = interruptHandler;

  /// Handle id, stable for the lifetime of this utterance.
  final String id;

  final Future<void> Function() _interruptHandler;
  final Completer<void> _done = Completer<void>();
  bool _interrupted = false;

  /// True once [interrupt] has been called.
  bool get interrupted => _interrupted;

  /// Set when synthesis or playback failed.
  SDKException? error;

  /// Stop playback and any in-flight synthesis. Resolves once stopped.
  Future<void> interrupt() async {
    _interrupted = true;
    await _interruptHandler();
    complete();
  }

  /// Resolve once playback finishes, is interrupted, or fails.
  Future<void> waitForPlayout() => _done.future;

  /// Internal — mark this utterance settled.
  void complete([SDKException? failure]) {
    if (failure != null) error = failure;
    if (!_done.isCompleted) _done.complete();
  }
}

/// Whether a modality/backend/feature is honestly available right now.
class UnavailableCapability {
  /// Build an unavailable-capability entry.
  const UnavailableCapability({required this.name, required this.reason});

  /// Namespace or feature name.
  final String name;

  /// Why it is unavailable right now.
  final String reason;
}

/// Per-modality streaming support, keyed by namespace name.
class StreamingCapabilities {
  /// Build a streaming-support snapshot.
  const StreamingCapabilities({
    this.llm = true,
    this.vlm = true,
    this.stt = true,
    this.tts = true,
    this.vad = true,
    this.rag = true,
    this.images = true,
  });

  /// `llm.generateStream` support.
  final bool llm;

  /// `vlm.generateStream` support.
  final bool vlm;

  /// `stt.openStream` support.
  final bool stt;

  /// `tts.synthesizeStream` support.
  final bool tts;

  /// `vad.openStream` support.
  final bool vad;

  /// `RagSession.queryStream` support.
  final bool rag;

  /// `images.generateStream` support.
  final bool images;
}

/// Tool-calling support of the currently registered backends.
class ToolCapabilities {
  /// Build a tool-capability snapshot.
  const ToolCapabilities({
    this.registry = true,
    this.parallel = false,
    this.cancellation = true,
  });

  /// A tool registry is available.
  final bool registry;

  /// Multiple tool calls can run concurrently.
  final bool parallel;

  /// A tool call can be cancelled mid-flight.
  final bool cancellation;
}

/// RAG-session support of the currently registered backends.
class RagCapabilities {
  /// Build a RAG-capability snapshot.
  const RagCapabilities({this.multiSession = true, this.persistent = false});

  /// More than one concurrent session is supported.
  final bool multiSession;

  /// Sessions can persist their index to disk.
  final bool persistent;
}

/// Installed, packaged, and executable surface of this SDK build.
///
/// Generated from packaging and runtime probes, never from IDL enum
/// presence alone. `RunAnywhere.capabilities()` is the source of truth apps
/// should consult before calling into a modality that might not ship on
/// this platform.
class SDKCapabilities {
  /// Build a capabilities snapshot.
  const SDKCapabilities({
    required this.modalities,
    required this.backends,
    required this.audioFormats,
    required this.streaming,
    required this.tools,
    required this.rag,
    required this.unavailable,
  });

  /// Namespace ids present on this build.
  final Set<String> modalities;

  /// Inference backends this build links against.
  final Set<InferenceFramework> backends;

  /// Audio formats this build can round-trip.
  final Set<AudioFormat> audioFormats;

  /// Per-modality streaming support.
  final StreamingCapabilities streaming;

  /// Tool-calling support.
  final ToolCapabilities tools;

  /// RAG-session support.
  final RagCapabilities rag;

  /// Modalities/features honestly unavailable on this build.
  final List<UnavailableCapability> unavailable;
}

/// Size of a RAG session's index.
class RagStats {
  /// Build a RAG statistics snapshot.
  const RagStats({
    required this.documentCount,
    required this.chunkCount,
    required this.indexSizeBytes,
  });

  /// Build from the generated RAG statistics.
  factory RagStats.fromProto(rag_pb.RAGStatistics proto) => RagStats(
    documentCount: proto.indexedDocuments.toInt(),
    chunkCount: proto.indexedChunks.toInt(),
    indexSizeBytes: proto.vectorStoreSizeBytes.toInt(),
  );

  /// Documents ingested.
  final int documentCount;

  /// Chunks indexed across those documents.
  final int chunkCount;

  /// Bytes the vector store occupies.
  final int indexSizeBytes;
}
