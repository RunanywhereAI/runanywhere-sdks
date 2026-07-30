// SPDX-License-Identifier: Apache-2.0
//
// Public options types for the v3 API surface. Every default resolves from the
// generated `*Convenience.defaults()` factories, which are derived from the
// `rac_default` annotations in idl/*.proto — no literal is copied by hand.

import 'package:fixnum/fixnum.dart' show Int64;
import 'package:runanywhere/generated/convenience/ra_convenience.dart';
import 'package:runanywhere/generated/diarization.pb.dart' as diar_pb;
import 'package:runanywhere/generated/diffusion_options.pb.dart' as diff_pb;
import 'package:runanywhere/generated/diffusion_options.pbenum.dart'
    show DiffusionMode;
import 'package:runanywhere/generated/embeddings_options.pb.dart' as embed_pb;
import 'package:runanywhere/generated/embeddings_options.pbenum.dart'
    show EmbeddingsNormalizeMode, EmbeddingsPoolingStrategy;
import 'package:runanywhere/generated/llm_options.pb.dart'
    show LLMGenerationOptions;
import 'package:runanywhere/generated/model_types.pbenum.dart'
    show AudioFormat, InferenceFramework;
import 'package:runanywhere/generated/rag.pb.dart' show RAGConfiguration;
import 'package:runanywhere/generated/segmentation.pb.dart' as seg_pb;
import 'package:runanywhere/generated/structured_output.pb.dart'
    show JSONSchema, StructuredOutputOptions;
import 'package:runanywhere/generated/stt_options.pb.dart' show STTOptions;
import 'package:runanywhere/generated/thinking_tag_pattern.pb.dart'
    as think_pb;
import 'package:runanywhere/generated/thinking_tag_pattern.pbenum.dart'
    show ReasoningMode;
import 'package:runanywhere/generated/tool_calling.pb.dart'
    show ToolCallingOptions, ToolDefinition;
import 'package:runanywhere/generated/tool_calling.pbenum.dart'
    show ToolChoiceMode;
import 'package:runanywhere/generated/tts_options.pb.dart' show TTSOptions;

import 'package:runanywhere/generated/vad_options.pb.dart' show VADOptions;
import 'package:runanywhere/generated/vlm_options.pb.dart'
    show VLMGenerationOptions;
import 'package:runanywhere/public/api/types/inputs.dart';

export 'package:runanywhere/generated/embeddings_options.pbenum.dart'
    show EmbeddingsNormalizeMode, EmbeddingsPoolingStrategy;
export 'package:runanywhere/generated/model_types.pbenum.dart'
    show AudioFormat, InferenceFramework, ModelCategory;
export 'package:runanywhere/generated/thinking_tag_pattern.pbenum.dart'
    show ReasoningMode;


LLMGenerationOptions? _llmDefaults;
STTOptions? _sttDefaults;
TTSOptions? _ttsDefaults;
VADOptions? _vadDefaults;
embed_pb.EmbeddingsOptions? _embedDefaults;
RAGConfiguration? _ragDefaults;
diff_pb.DiffusionGenerationOptions? _imageDefaults;
diar_pb.DiarizationOptions? _diarizationDefaults;
ToolCallingOptions? _toolDefaults;
StructuredOutputOptions? _structuredDefaults;
VLMGenerationOptions? _vlmDefaults;

LLMGenerationOptions get _llm =>
    _llmDefaults ??= LLMGenerationOptionsConvenience.defaults();
STTOptions get _stt => _sttDefaults ??= STTOptionsConvenience.defaults();
TTSOptions get _tts => _ttsDefaults ??= TTSOptionsConvenience.defaults();
VADOptions get _vad => _vadDefaults ??= VADOptionsConvenience.defaults();
embed_pb.EmbeddingsOptions get _embed =>
    _embedDefaults ??= EmbeddingsOptionsConvenience.defaults();
RAGConfiguration get _rag =>
    _ragDefaults ??= RAGConfigurationConvenience.defaults();
diff_pb.DiffusionGenerationOptions get _image =>
    _imageDefaults ??= DiffusionGenerationOptionsConvenience.defaults();
diar_pb.DiarizationOptions get _diarization =>
    _diarizationDefaults ??= DiarizationOptionsConvenience.defaults();
ToolCallingOptions get _tools =>
    _toolDefaults ??= ToolCallingOptionsConvenience.defaults();
StructuredOutputOptions get _structured =>
    _structuredDefaults ??= StructuredOutputOptionsConvenience.defaults();
VLMGenerationOptions get _vlm =>
    _vlmDefaults ??= VLMGenerationOptionsConvenience.defaults();

/// Thinking-phase control for a generation request.
class ReasoningOptions {
  /// Configure whether the model thinks and whether thoughts reach the caller.
  const ReasoningOptions({
    this.mode = ReasoningMode.REASONING_MODE_ON,
    this.includeInOutput = false,
    this.pattern,
  });

  /// Whether the thinking phase runs at all.
  final ReasoningMode mode;

  /// True streams thought tokens to the caller instead of stripping them.
  final bool includeInOutput;

  /// Opening thinking tag for models whose markers differ from the catalog
  /// default; the closing tag is derived from it. Null uses the model's own.
  final String? pattern;

  /// Build the generated reasoning options.
  think_pb.ReasoningOptions toProto() {
    final proto = think_pb.ReasoningOptions(
      mode: mode,
      includeInOutput: includeInOutput,
    );
    final open = pattern;
    if (open != null && open.isNotEmpty) {
      proto.pattern = think_pb.ThinkingTagPattern(
        openTag: open,
        closeTag: open.startsWith('<')
            ? '</${open.substring(1)}'
            : '/$open',
      );
    }
    return proto;
  }
}

/// How the model may use registered tools during a generation.
class ToolChoice {
  const ToolChoice._(this.mode, this.forcedName);

  /// Let the model decide whether to call a tool.
  static const ToolChoice auto = ToolChoice._(
    ToolChoiceMode.TOOL_CHOICE_MODE_AUTO,
    null,
  );

  /// Forbid tool calls for this generation.
  static const ToolChoice none = ToolChoice._(
    ToolChoiceMode.TOOL_CHOICE_MODE_NONE,
    null,
  );

  /// Require at least one tool call.
  static const ToolChoice required = ToolChoice._(
    ToolChoiceMode.TOOL_CHOICE_MODE_REQUIRED,
    null,
  );

  /// Require a call to exactly this tool.
  factory ToolChoice.forced(String name) =>
      ToolChoice._(ToolChoiceMode.TOOL_CHOICE_MODE_SPECIFIC, name);

  /// Generated choice policy.
  final ToolChoiceMode mode;

  /// Tool name pinned by [ToolChoice.forced].
  final String? forcedName;
}

/// Schema constraint applied to a generation's output.
class StructuredOutput {
  /// Constrain output to [schema].
  const StructuredOutput({required this.schema, this.strict = true});

  /// JSON Schema the output must satisfy.
  final JSONSchema schema;

  /// True rejects output that does not validate instead of repairing it.
  final bool strict;

  /// Build the generated structured-output options.
  StructuredOutputOptions toProto() => StructuredOutputOptions(
    schema: schema,
    strictMode: strict,
    maxRetries: _structured.maxRetries,
  );
}

/// Sampling, prompting, reasoning, and tool controls for `llm` and `vlm`.
class LlmOptions {
  /// Override any subset of the generation defaults.
  LlmOptions({
    this.model,
    int? maxOutputTokens,
    double? temperature,
    double? topP,
    this.topK,
    this.minP,
    this.frequencyPenalty,
    this.presencePenalty,
    double? repetitionPenalty,
    this.seed,
    this.stopSequences = const <String>[],
    this.systemPrompt,
    this.reasoning,
    this.structuredOutput,
    this.tools = const <ToolDefinition>[],
    this.toolChoice = ToolChoice.auto,
    int? maxToolCalls,
  }) : _argMaxOutputTokens = maxOutputTokens,
       _argTemperature = temperature,
       _argTopP = topP,
       _argRepetitionPenalty = repetitionPenalty,
       _argMaxToolCalls = maxToolCalls;

  final int? _argMaxOutputTokens;
  final double? _argTemperature;
  final double? _argTopP;
  final double? _argRepetitionPenalty;
  final int? _argMaxToolCalls;

  /// Model slug to generate with. Absent auto-loads, downloading if needed.
  final String? model;

  /// Hard cap on generated tokens.
  int get maxOutputTokens => _argMaxOutputTokens ?? _llm.maxOutputTokens;

  /// Sampling temperature. 0 is greedy decoding.
  double get temperature => _argTemperature ?? _llm.temperature;

  /// Nucleus-sampling mass.
  double get topP => _argTopP ?? _llm.topP;

  /// Top-k truncation. Null disables it.
  final int? topK;

  /// Minimum-probability truncation. Null disables it.
  final double? minP;

  /// OpenAI-style frequency penalty.
  final double? frequencyPenalty;

  /// OpenAI-style presence penalty.
  final double? presencePenalty;

  /// Repetition penalty. 1.0 is no penalty.
  double get repetitionPenalty => _argRepetitionPenalty ?? _llm.repetitionPenalty;

  /// Deterministic sampling seed.
  final int? seed;

  /// Strings that halt generation when emitted.
  final List<String> stopSequences;

  /// System instruction prepended to the conversation.
  final String? systemPrompt;

  /// Thinking-phase control.
  final ReasoningOptions? reasoning;

  /// Output schema constraint.
  final StructuredOutput? structuredOutput;

  /// Tools offered for this generation. Empty uses the registry.
  final List<ToolDefinition> tools;

  /// How the model may use those tools.
  final ToolChoice toolChoice;

  /// Maximum tool-call round trips before the loop stops.
  int get maxToolCalls => _argMaxToolCalls ?? _tools.maxToolCalls;

  /// Build the generated LLM generation options.
  LLMGenerationOptions toProto({List<ToolDefinition> registeredTools = const <ToolDefinition>[]}) {
    final proto = LLMGenerationOptions(
      maxOutputTokens: maxOutputTokens,
      temperature: temperature,
      topP: topP,
      repetitionPenalty: repetitionPenalty,
      stopSequences: stopSequences,
    );
    if (topK != null) proto.topK = topK!;
    if (minP != null) proto.minP = minP!;
    if (frequencyPenalty != null) proto.frequencyPenalty = frequencyPenalty!;
    if (presencePenalty != null) proto.presencePenalty = presencePenalty!;
    if (seed != null) proto.seed = Int64(seed!);
    if (systemPrompt != null) proto.systemPrompt = systemPrompt!;
    final reasoningOptions = reasoning;
    if (reasoningOptions != null) {
      proto.reasoning = reasoningOptions.toProto();
    }
    final schema = structuredOutput;
    if (schema != null) {
      proto.structuredOutput = schema.toProto();
    }
    final effectiveTools = tools.isNotEmpty ? tools : registeredTools;
    if (effectiveTools.isNotEmpty ||
        toolChoice.mode != ToolChoiceMode.TOOL_CHOICE_MODE_AUTO) {
      final calling = ToolCallingOptions(
        tools: effectiveTools,
        toolChoice: toolChoice.mode,
        maxToolCalls: maxToolCalls,
        autoExecute: true,
      );
      final forced = toolChoice.forcedName;
      if (forced != null) {
        calling.forcedToolName = forced;
      }
      proto.toolCalling = calling;
    }
    return proto;
  }

  /// Build the generated VLM generation options for [prompt].
  VLMGenerationOptions toVlmProto(String prompt) {
    final proto = VLMGenerationOptions(
      prompt: prompt,
      maxOutputTokens: _argMaxOutputTokens ?? _vlm.maxOutputTokens,
      temperature: _argTemperature ?? _vlm.temperature,
      topP: _argTopP ?? _vlm.topP,
      topK: topK ?? _vlm.topK,
      repetitionPenalty: _argRepetitionPenalty ?? _vlm.repetitionPenalty,
      stopSequences: stopSequences,
    );
    if (minP != null) proto.minP = minP!;
    if (seed != null) proto.seed = Int64(seed!);
    if (systemPrompt != null) proto.systemPrompt = systemPrompt!;
    final reasoningOptions = reasoning;
    if (reasoningOptions != null) {
      proto.reasoning = reasoningOptions.toProto();
    }
    return proto;
  }
}

/// Language, formatting, and speaker controls for `stt`.
class SttOptions {
  /// Override any subset of the transcription defaults.
  SttOptions({
    this.language,
    bool? punctuation,
    bool? wordTimestamps,
    this.diarization = false,
    this.maxSpeakers,
    this.translateToEnglish = false,
  }) : _argPunctuation = punctuation,
       _argWordTimestamps = wordTimestamps;

  final bool? _argPunctuation;
  final bool? _argWordTimestamps;

  /// BCP-47 language tag. Null auto-detects.
  final String? language;

  /// True restores punctuation and casing.
  bool get punctuation => _argPunctuation ?? _stt.enablePunctuation;

  /// True attaches per-word timings.
  bool get wordTimestamps => _argWordTimestamps ?? _stt.enableWordTimestamps;

  /// True labels each word with a speaker.
  final bool diarization;

  /// Upper bound on distinct speakers. Null lets the model decide.
  final int? maxSpeakers;

  /// True translates non-English speech into English text.
  final bool translateToEnglish;

  /// Build the generated STT options.
  STTOptions toProto() {
    final proto = STTOptions(
      enablePunctuation: punctuation,
      enableWordTimestamps: wordTimestamps,
      enableDiarization: diarization,
      translateToEnglish: translateToEnglish,
    );
    final tag = language;
    if (tag != null) proto.language = tag;
    if (maxSpeakers != null) proto.maxSpeakers = maxSpeakers!;
    return proto;
  }
}

/// Voice, prosody, and output-format controls for `tts`.
class TtsOptions {
  /// Override any subset of the synthesis defaults.
  TtsOptions({
    this.voice,
    String? language,
    double? speed,
    double? pitch,
    AudioFormat? format,
    int? sampleRate,
  }) : _argLanguage = language,
       _argSpeed = speed,
       _argPitch = pitch,
       _argFormat = format,
       _argSampleRate = sampleRate;

  final String? _argLanguage;
  final double? _argSpeed;
  final double? _argPitch;
  final AudioFormat? _argFormat;
  final int? _argSampleRate;

  /// Voice id inside the loaded model. Null uses the engine default.
  final String? voice;

  /// BCP-47 language tag for the synthesized speech.
  String get language => _argLanguage ?? _tts.languageCode;

  /// Playback rate multiplier.
  double get speed => _argSpeed ?? _tts.speed;

  /// Pitch multiplier.
  double get pitch => _argPitch ?? _tts.pitch;

  /// Encoding of the returned audio.
  AudioFormat get format => _argFormat ?? _tts.audioFormat;

  /// Sample rate of the returned audio.
  int get sampleRate => _argSampleRate ?? _tts.sampleRate;

  /// Build the generated TTS options.
  TTSOptions toProto() {
    final proto = TTSOptions(
      languageCode: language,
      speed: speed,
      pitch: pitch,
      volume: _tts.volume,
      audioFormat: format,
      sampleRate: sampleRate,
    );
    final voiceId = voice;
    if (voiceId != null) proto.voice = voiceId;
    return proto;
  }
}

/// Sensitivity and timing controls for `vad`.
class VadOptions {
  /// Override any subset of the detection defaults.
  VadOptions({
    this.activationThreshold,
    int? minSpeechMs,
    int? minSilenceMs,
    int? prefixPaddingMs,
  }) : _argMinSpeechMs = minSpeechMs,
       _argMinSilenceMs = minSilenceMs,
       _argPrefixPaddingMs = prefixPaddingMs;

  final int? _argMinSpeechMs;
  final int? _argMinSilenceMs;
  final int? _argPrefixPaddingMs;

  /// Speech-probability cutoff. Null uses the model's calibrated default.
  final double? activationThreshold;

  /// Shortest run of speech that opens a segment.
  int get minSpeechMs => _argMinSpeechMs ?? _vad.minSpeechDurationMs;

  /// Shortest run of silence that closes a segment.
  int get minSilenceMs => _argMinSilenceMs ?? _vad.minSilenceDurationMs;

  /// Audio retained ahead of a segment so onsets are not clipped.
  int get prefixPaddingMs => _argPrefixPaddingMs ?? _vad.prefixPaddingMs;

  /// Build the generated VAD options.
  VADOptions toProto() {
    final proto = VADOptions(
      minSpeechDurationMs: minSpeechMs,
      minSilenceDurationMs: minSilenceMs,
      prefixPaddingMs: prefixPaddingMs,
    );
    if (activationThreshold != null) {
      proto.activationThreshold = activationThreshold!;
    }
    return proto;
  }
}

/// Normalization and pooling controls for `embeddings`.
class EmbedOptions {
  /// Override any subset of the embedding defaults.
  EmbedOptions({
    EmbeddingsNormalizeMode? normalize,
    EmbeddingsPoolingStrategy? pooling,
  }) : _argNormalize = normalize,
       _argPooling = pooling;

  final EmbeddingsNormalizeMode? _argNormalize;
  final EmbeddingsPoolingStrategy? _argPooling;

  /// Vector normalization applied after pooling.
  EmbeddingsNormalizeMode get normalize =>
      _argNormalize ?? EmbeddingsNormalizeMode.EMBEDDINGS_NORMALIZE_MODE_L2;

  /// How token vectors collapse into one sentence vector.
  EmbeddingsPoolingStrategy get pooling =>
      _argPooling ?? EmbeddingsPoolingStrategy.EMBEDDINGS_POOLING_STRATEGY_MEAN;

  /// Build the generated embeddings options.
  embed_pb.EmbeddingsOptions toProto() => embed_pb.EmbeddingsOptions(
    normalizeMode: normalize,
    pooling: pooling,
    nThreads: _embed.nThreads,
  );
}

/// Whether `images.generate` synthesizes from scratch or repaints a region.
class ImageMode {
  const ImageMode._(this.mode, this.input, this.mask);

  /// Synthesize a new image from the prompt alone.
  static const ImageMode generate = ImageMode._(
    DiffusionMode.DIFFUSION_MODE_TEXT_TO_IMAGE,
    null,
    null,
  );

  /// Repaint the masked region of [input].
  factory ImageMode.inpaint(ImageInput input, ImageInput mask) =>
      ImageMode._(DiffusionMode.DIFFUSION_MODE_INPAINTING, input, mask);

  /// Generated diffusion mode.
  final DiffusionMode mode;

  /// Base image for inpainting.
  final ImageInput? input;

  /// Mask marking the region to repaint.
  final ImageInput? mask;
}

/// Size, sampling, and progress controls for `images`.
class ImageOptions {
  /// Override any subset of the image-generation defaults.
  ImageOptions({
    this.negativePrompt,
    this.width,
    this.height,
    int? steps,
    double? guidanceScale,
    this.seed,
    this.mode = ImageMode.generate,
    this.reportPartials = false,
  }) : _argSteps = steps,
       _argGuidanceScale = guidanceScale;

  final int? _argSteps;
  final double? _argGuidanceScale;

  /// Concepts to steer away from.
  final String? negativePrompt;

  /// Output width in pixels. Null uses the model's native size.
  final int? width;

  /// Output height in pixels. Null uses the model's native size.
  final int? height;

  /// Denoising steps.
  int get steps => _argSteps ?? _image.steps;

  /// Classifier-free guidance strength.
  double get guidanceScale => _argGuidanceScale ?? _image.guidanceScale;

  /// Deterministic sampling seed.
  final int? seed;

  /// Generate-from-scratch or inpaint.
  final ImageMode mode;

  /// True emits intermediate images through `images.generateStream`.
  final bool reportPartials;

  /// Build the generated diffusion options for [prompt].
  diff_pb.DiffusionGenerationOptions toProto(String prompt) {
    final proto = diff_pb.DiffusionGenerationOptions(
      prompt: prompt,
      steps: steps,
      guidanceScale: guidanceScale,
      mode: mode.mode,
      reportIntermediateImages: reportPartials,
      denoiseStrength: _image.denoiseStrength,
    );
    if (negativePrompt != null) proto.negativePrompt = negativePrompt!;
    if (width != null) proto.width = width!;
    if (height != null) proto.height = height!;
    if (seed != null) proto.seed = Int64(seed!);
    final input = mode.input;
    if (input != null) {
      proto
        ..inputImage = input.bytes
        ..inputImageWidth = input.width
        ..inputImageHeight = input.height;
    }
    final mask = mode.mask;
    if (mask != null) {
      proto.maskImage = mask.bytes;
    }
    return proto;
  }
}

/// Clustering controls for `diarization`.
class DiarizationOptions {
  /// Override any subset of the diarization defaults.
  DiarizationOptions({
    this.threshold,
    this.minimumDurationMs,
    this.mergeGapMs,
  });

  /// Speaker-change sensitivity. Null uses the model default.
  final double? threshold;

  /// Segments shorter than this are dropped.
  final int? minimumDurationMs;

  /// Adjacent same-speaker segments closer than this are merged.
  final int? mergeGapMs;

  /// Build the generated diarization options for [audio].
  diar_pb.DiarizationOptions toProto(AudioInput audio) {
    final defaults = _diarization;
    final proto = diar_pb.DiarizationOptions(
      sampleRate: audio.format.sampleRate > 0
          ? audio.format.sampleRate
          : defaults.sampleRate,
      channels: audio.format.channels,
      encoding: audio.format.encoding == AudioEncoding.pcm16
          ? diar_pb.DiarizationAudioEncoding
                .DIARIZATION_AUDIO_ENCODING_PCM_S16_LE
          : diar_pb.DiarizationAudioEncoding
                .DIARIZATION_AUDIO_ENCODING_PCM_F32_LE,
      threshold: threshold ?? defaults.threshold,
    );
    if (minimumDurationMs != null) {
      proto.minimumDurationMs = Int64(minimumDurationMs!);
    }
    if (mergeGapMs != null) {
      proto.mergeGapMs = Int64(mergeGapMs!);
    }
    return proto;
  }
}

/// Diagnostic controls for `segmentation`.
class SegmentationOptions {
  /// Ask for the human-viewable class-colour overlay alongside the mask.
  const SegmentationOptions({this.includeDiagnosticImage = false});

  /// True also returns a deterministic class-colour RGBA image.
  final bool includeDiagnosticImage;

  /// Build the generated segmentation options.
  seg_pb.SegmentationOptions toProto() => seg_pb.SegmentationOptions(
    includeDiagnosticRgba: includeDiagnosticImage,
  );
}

/// Silence window that ends a user turn in a voice session.
class Endpointing {
  /// Bound how long the session waits for more speech.
  const Endpointing({this.minDelayMs = 500, this.maxDelayMs = 3000});

  /// Silence required before the turn may close.
  final int minDelayMs;

  /// Silence after which the turn closes regardless.
  final int maxDelayMs;
}

/// Barge-in policy for a voice session.
class Interruption {
  /// Allow or forbid the user cutting the agent off.
  const Interruption({this.enabled = true, this.minDurationMs = 500});

  /// True lets user speech stop the agent mid-utterance.
  final bool enabled;

  /// Speech this long counts as an interruption rather than a cough.
  final int minDurationMs;
}

/// Turn-taking behaviour of a voice session.
class TurnHandlingOptions {
  /// Configure endpointing and barge-in.
  const TurnHandlingOptions({
    this.endpointing = const Endpointing(),
    this.interruption = const Interruption(),
  });

  /// When a user turn ends.
  final Endpointing endpointing;

  /// Whether the user may interrupt the agent.
  final Interruption interruption;
}

/// Chunking, retrieval, and persistence controls for a RAG session.
class RagConfig {
  /// Override any subset of the RAG defaults.
  RagConfig({
    int? topK,
    int? chunkSize,
    int? chunkOverlap,
    this.similarityThreshold,
    this.persistPath,
  }) : _argTopK = topK,
       _argChunkSize = chunkSize,
       _argChunkOverlap = chunkOverlap;

  final int? _argTopK;
  final int? _argChunkSize;
  final int? _argChunkOverlap;

  /// Chunks retrieved per query.
  int get topK => _argTopK ?? _rag.topK;

  /// Characters per indexed chunk.
  int get chunkSize => _argChunkSize ?? _rag.chunkSize;

  /// Characters shared between adjacent chunks.
  int get chunkOverlap => _argChunkOverlap ?? _rag.chunkOverlap;

  /// Minimum similarity a chunk needs to be returned.
  final double? similarityThreshold;

  /// Directory the index persists to. Null keeps it in memory.
  final String? persistPath;

  /// Build the generated RAG configuration for the given models.
  RAGConfiguration toProto({
    required String embeddingModelId,
    String? llmModelId,
  }) {
    final proto = RAGConfiguration(
      embeddingModelId: embeddingModelId,
      topK: topK,
      chunkSize: chunkSize,
      chunkOverlap: chunkOverlap,
    );
    if (llmModelId != null) proto.llmModelId = llmModelId;
    if (similarityThreshold != null) {
      proto.similarityThreshold = similarityThreshold!;
    }
    final path = persistPath;
    if (path != null) {
      proto
        ..indexPath = path
        ..persistIndex = true;
    }
    return proto;
  }
}

/// Placement knobs applied when a model is loaded.
class LoadOptions {
  /// Pin an engine or override runtime sizing for one load.
  const LoadOptions({
    this.framework,
    this.contextLength,
    this.threads,
    this.useGpu,
  });

  /// Engine to load with. Null lets the registry choose by priority.
  final InferenceFramework? framework;

  /// Context window in tokens.
  final int? contextLength;

  /// CPU threads the engine may use.
  final int? threads;

  /// True forces GPU offload, false forbids it, null lets the engine decide.
  final bool? useGpu;
}
