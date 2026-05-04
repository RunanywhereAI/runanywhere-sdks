//
//  Generated code. Do not modify.
//  source: voice_agent_service.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'voice_events.pb.dart' as $0;
import 'voice_events.pbenum.dart' as $0;

/// Empty request type — the voice agent already has its config set via
/// `rac_voice_agent_init()` at handle creation time. The Stream rpc just
/// opens a new event subscription on an existing handle.
class VoiceAgentRequest extends $pb.GeneratedMessage {
  factory VoiceAgentRequest({
    $core.String? eventFilter,
  }) {
    final $result = create();
    if (eventFilter != null) {
      $result.eventFilter = eventFilter;
    }
    return $result;
  }
  VoiceAgentRequest._() : super();
  factory VoiceAgentRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VoiceAgentRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VoiceAgentRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'eventFilter')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VoiceAgentRequest clone() => VoiceAgentRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VoiceAgentRequest copyWith(void Function(VoiceAgentRequest) updates) => super.copyWith((message) => updates(message as VoiceAgentRequest)) as VoiceAgentRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoiceAgentRequest create() => VoiceAgentRequest._();
  VoiceAgentRequest createEmptyInstance() => create();
  static $pb.PbList<VoiceAgentRequest> createRepeated() => $pb.PbList<VoiceAgentRequest>();
  @$core.pragma('dart2js:noInline')
  static VoiceAgentRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VoiceAgentRequest>(create);
  static VoiceAgentRequest? _defaultInstance;

  /// Optional: filter the stream to only certain VoiceEvent.payload arms
  /// (e.g. "user_said,assistant_token"). Empty = all events.
  @$pb.TagNumber(1)
  $core.String get eventFilter => $_getSZ(0);
  @$pb.TagNumber(1)
  set eventFilter($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEventFilter() => $_has(0);
  @$pb.TagNumber(1)
  void clearEventFilter() => clearField(1);
}

///  ---------------------------------------------------------------------------
///  v3.2: One-shot voice-turn result.
///
///  Mirrors Swift `VoiceAgentResult`, Kotlin `VoiceAgentResult`, RN
///  `VoiceTurnResult`, Web `VoiceAgentResult`, Flutter (TBD), and the C ABI
///  `rac_voice_agent_result_t` (rac/features/voice_agent/rac_voice_agent.h).
///  Returned by the `processVoiceTurn` ergonomic API where a single audio
///  blob produces transcription + assistant response + synthesized audio in
///  one call (as opposed to the streaming path served by the Stream rpc).
///  ---------------------------------------------------------------------------
class VoiceAgentResult extends $pb.GeneratedMessage {
  factory VoiceAgentResult({
    $core.bool? speechDetected,
    $core.String? transcription,
    $core.String? assistantResponse,
    $core.String? thinkingContent,
    $core.List<$core.int>? synthesizedAudio,
    $0.VoiceAgentComponentStates? finalState,
    $core.int? synthesizedAudioSampleRateHz,
    $core.int? synthesizedAudioChannels,
    $0.AudioEncoding? synthesizedAudioEncoding,
  }) {
    final $result = create();
    if (speechDetected != null) {
      $result.speechDetected = speechDetected;
    }
    if (transcription != null) {
      $result.transcription = transcription;
    }
    if (assistantResponse != null) {
      $result.assistantResponse = assistantResponse;
    }
    if (thinkingContent != null) {
      $result.thinkingContent = thinkingContent;
    }
    if (synthesizedAudio != null) {
      $result.synthesizedAudio = synthesizedAudio;
    }
    if (finalState != null) {
      $result.finalState = finalState;
    }
    if (synthesizedAudioSampleRateHz != null) {
      $result.synthesizedAudioSampleRateHz = synthesizedAudioSampleRateHz;
    }
    if (synthesizedAudioChannels != null) {
      $result.synthesizedAudioChannels = synthesizedAudioChannels;
    }
    if (synthesizedAudioEncoding != null) {
      $result.synthesizedAudioEncoding = synthesizedAudioEncoding;
    }
    return $result;
  }
  VoiceAgentResult._() : super();
  factory VoiceAgentResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VoiceAgentResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VoiceAgentResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'speechDetected')
    ..aOS(2, _omitFieldNames ? '' : 'transcription')
    ..aOS(3, _omitFieldNames ? '' : 'assistantResponse')
    ..aOS(4, _omitFieldNames ? '' : 'thinkingContent')
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'synthesizedAudio', $pb.PbFieldType.OY)
    ..aOM<$0.VoiceAgentComponentStates>(6, _omitFieldNames ? '' : 'finalState', subBuilder: $0.VoiceAgentComponentStates.create)
    ..a<$core.int>(7, _omitFieldNames ? '' : 'synthesizedAudioSampleRateHz', $pb.PbFieldType.O3)
    ..a<$core.int>(8, _omitFieldNames ? '' : 'synthesizedAudioChannels', $pb.PbFieldType.O3)
    ..e<$0.AudioEncoding>(9, _omitFieldNames ? '' : 'synthesizedAudioEncoding', $pb.PbFieldType.OE, defaultOrMaker: $0.AudioEncoding.AUDIO_ENCODING_UNSPECIFIED, valueOf: $0.AudioEncoding.valueOf, enumValues: $0.AudioEncoding.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VoiceAgentResult clone() => VoiceAgentResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VoiceAgentResult copyWith(void Function(VoiceAgentResult) updates) => super.copyWith((message) => updates(message as VoiceAgentResult)) as VoiceAgentResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoiceAgentResult create() => VoiceAgentResult._();
  VoiceAgentResult createEmptyInstance() => create();
  static $pb.PbList<VoiceAgentResult> createRepeated() => $pb.PbList<VoiceAgentResult>();
  @$core.pragma('dart2js:noInline')
  static VoiceAgentResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VoiceAgentResult>(create);
  static VoiceAgentResult? _defaultInstance;

  /// Whether the input audio passed VAD's speech-detected check.
  @$pb.TagNumber(1)
  $core.bool get speechDetected => $_getBF(0);
  @$pb.TagNumber(1)
  set speechDetected($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSpeechDetected() => $_has(0);
  @$pb.TagNumber(1)
  void clearSpeechDetected() => clearField(1);

  /// Transcribed text from STT. Unset when speech_detected=false.
  @$pb.TagNumber(2)
  $core.String get transcription => $_getSZ(1);
  @$pb.TagNumber(2)
  set transcription($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTranscription() => $_has(1);
  @$pb.TagNumber(2)
  void clearTranscription() => clearField(2);

  /// Generated assistant response text from the LLM. Unset when STT
  /// produced no transcription or LLM was skipped.
  @$pb.TagNumber(3)
  $core.String get assistantResponse => $_getSZ(2);
  @$pb.TagNumber(3)
  set assistantResponse($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAssistantResponse() => $_has(2);
  @$pb.TagNumber(3)
  void clearAssistantResponse() => clearField(3);

  /// Thinking content extracted from `<think>...</think>` tags
  /// (qwen3, deepseek-r1). Unset when the active LLM does not emit
  /// a chain-of-thought trace.
  @$pb.TagNumber(4)
  $core.String get thinkingContent => $_getSZ(3);
  @$pb.TagNumber(4)
  set thinkingContent($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasThinkingContent() => $_has(3);
  @$pb.TagNumber(4)
  void clearThinkingContent() => clearField(4);

  /// Synthesized audio data from TTS. Encoding follows AudioFrameEvent
  /// conventions (typically PCM-F32-LE, sample rate per voice). Unset
  /// when TTS was skipped or auto_play_tts=false in VoiceSessionConfig.
  @$pb.TagNumber(5)
  $core.List<$core.int> get synthesizedAudio => $_getN(4);
  @$pb.TagNumber(5)
  set synthesizedAudio($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSynthesizedAudio() => $_has(4);
  @$pb.TagNumber(5)
  void clearSynthesizedAudio() => clearField(5);

  /// Component states captured at the end of the turn — useful for UIs
  /// surfacing readiness / partial-failure breakdowns alongside the
  /// final result. Unset when the caller does not ask for it.
  @$pb.TagNumber(6)
  $0.VoiceAgentComponentStates get finalState => $_getN(5);
  @$pb.TagNumber(6)
  set finalState($0.VoiceAgentComponentStates v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasFinalState() => $_has(5);
  @$pb.TagNumber(6)
  void clearFinalState() => clearField(6);
  @$pb.TagNumber(6)
  $0.VoiceAgentComponentStates ensureFinalState() => $_ensure(5);

  /// Audio metadata for synthesized_audio. 0/UNSPECIFIED = backend default
  /// or unknown.
  @$pb.TagNumber(7)
  $core.int get synthesizedAudioSampleRateHz => $_getIZ(6);
  @$pb.TagNumber(7)
  set synthesizedAudioSampleRateHz($core.int v) { $_setSignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasSynthesizedAudioSampleRateHz() => $_has(6);
  @$pb.TagNumber(7)
  void clearSynthesizedAudioSampleRateHz() => clearField(7);

  @$pb.TagNumber(8)
  $core.int get synthesizedAudioChannels => $_getIZ(7);
  @$pb.TagNumber(8)
  set synthesizedAudioChannels($core.int v) { $_setSignedInt32(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasSynthesizedAudioChannels() => $_has(7);
  @$pb.TagNumber(8)
  void clearSynthesizedAudioChannels() => clearField(8);

  @$pb.TagNumber(9)
  $0.AudioEncoding get synthesizedAudioEncoding => $_getN(8);
  @$pb.TagNumber(9)
  set synthesizedAudioEncoding($0.AudioEncoding v) { setField(9, v); }
  @$pb.TagNumber(9)
  $core.bool hasSynthesizedAudioEncoding() => $_has(8);
  @$pb.TagNumber(9)
  void clearSynthesizedAudioEncoding() => clearField(9);
}

///  ---------------------------------------------------------------------------
///  v3.2: Voice session behavior configuration.
///
///  Mirrors Swift `VoiceSessionConfig` and Kotlin `VoiceSessionConfig`.
///  Controls runtime behavior of the voice agent's session loop — silence
///  timing, speech threshold, auto-TTS playback, continuous mode, and
///  LLM thinking-mode toggle.
///  ---------------------------------------------------------------------------
class VoiceSessionConfig extends $pb.GeneratedMessage {
  factory VoiceSessionConfig({
    $core.int? silenceDurationMs,
    $core.double? speechThreshold,
    $core.bool? autoPlayTts,
    $core.bool? continuousMode,
    $core.bool? thinkingModeEnabled,
    $core.int? maxTokens,
  }) {
    final $result = create();
    if (silenceDurationMs != null) {
      $result.silenceDurationMs = silenceDurationMs;
    }
    if (speechThreshold != null) {
      $result.speechThreshold = speechThreshold;
    }
    if (autoPlayTts != null) {
      $result.autoPlayTts = autoPlayTts;
    }
    if (continuousMode != null) {
      $result.continuousMode = continuousMode;
    }
    if (thinkingModeEnabled != null) {
      $result.thinkingModeEnabled = thinkingModeEnabled;
    }
    if (maxTokens != null) {
      $result.maxTokens = maxTokens;
    }
    return $result;
  }
  VoiceSessionConfig._() : super();
  factory VoiceSessionConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VoiceSessionConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VoiceSessionConfig', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'silenceDurationMs', $pb.PbFieldType.O3)
    ..a<$core.double>(2, _omitFieldNames ? '' : 'speechThreshold', $pb.PbFieldType.OF)
    ..aOB(3, _omitFieldNames ? '' : 'autoPlayTts')
    ..aOB(4, _omitFieldNames ? '' : 'continuousMode')
    ..aOB(5, _omitFieldNames ? '' : 'thinkingModeEnabled')
    ..a<$core.int>(6, _omitFieldNames ? '' : 'maxTokens', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VoiceSessionConfig clone() => VoiceSessionConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VoiceSessionConfig copyWith(void Function(VoiceSessionConfig) updates) => super.copyWith((message) => updates(message as VoiceSessionConfig)) as VoiceSessionConfig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoiceSessionConfig create() => VoiceSessionConfig._();
  VoiceSessionConfig createEmptyInstance() => create();
  static $pb.PbList<VoiceSessionConfig> createRepeated() => $pb.PbList<VoiceSessionConfig>();
  @$core.pragma('dart2js:noInline')
  static VoiceSessionConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VoiceSessionConfig>(create);
  static VoiceSessionConfig? _defaultInstance;

  /// Silence duration (milliseconds) before processing the speech
  /// buffer. Default per Swift/Kotlin: 1500 ms.
  @$pb.TagNumber(1)
  $core.int get silenceDurationMs => $_getIZ(0);
  @$pb.TagNumber(1)
  set silenceDurationMs($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSilenceDurationMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearSilenceDurationMs() => clearField(1);

  /// Minimum audio level to detect speech (0.0 - 1.0). Default per
  /// Swift/Kotlin: 0.1.
  @$pb.TagNumber(2)
  $core.double get speechThreshold => $_getN(1);
  @$pb.TagNumber(2)
  set speechThreshold($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSpeechThreshold() => $_has(1);
  @$pb.TagNumber(2)
  void clearSpeechThreshold() => clearField(2);

  /// Whether to auto-play TTS response after synthesis. Default true.
  @$pb.TagNumber(3)
  $core.bool get autoPlayTts => $_getBF(2);
  @$pb.TagNumber(3)
  set autoPlayTts($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAutoPlayTts() => $_has(2);
  @$pb.TagNumber(3)
  void clearAutoPlayTts() => clearField(3);

  /// Whether to auto-resume listening after TTS playback. Default true.
  @$pb.TagNumber(4)
  $core.bool get continuousMode => $_getBF(3);
  @$pb.TagNumber(4)
  set continuousMode($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasContinuousMode() => $_has(3);
  @$pb.TagNumber(4)
  void clearContinuousMode() => clearField(4);

  /// Whether thinking mode is enabled for the LLM (qwen3, deepseek-r1).
  /// Default false.
  @$pb.TagNumber(5)
  $core.bool get thinkingModeEnabled => $_getBF(4);
  @$pb.TagNumber(5)
  set thinkingModeEnabled($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasThinkingModeEnabled() => $_has(4);
  @$pb.TagNumber(5)
  void clearThinkingModeEnabled() => clearField(5);

  /// Optional per-turn LLM max token limit. 0 = LLM/default.
  @$pb.TagNumber(6)
  $core.int get maxTokens => $_getIZ(5);
  @$pb.TagNumber(6)
  set maxTokens($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasMaxTokens() => $_has(5);
  @$pb.TagNumber(6)
  void clearMaxTokens() => clearField(6);
}

///  ---------------------------------------------------------------------------
///  v3.2: Audio pipeline state-manager configuration.
///
///  Mirrors rac_audio_pipeline_config_t and the Swift state-manager knobs used
///  to prevent microphone/TTS feedback loops.
///  ---------------------------------------------------------------------------
class AudioPipelineConfig extends $pb.GeneratedMessage {
  factory AudioPipelineConfig({
    $core.int? cooldownDurationMs,
    $core.bool? strictTransitions,
    $core.int? maxTtsDurationMs,
  }) {
    final $result = create();
    if (cooldownDurationMs != null) {
      $result.cooldownDurationMs = cooldownDurationMs;
    }
    if (strictTransitions != null) {
      $result.strictTransitions = strictTransitions;
    }
    if (maxTtsDurationMs != null) {
      $result.maxTtsDurationMs = maxTtsDurationMs;
    }
    return $result;
  }
  AudioPipelineConfig._() : super();
  factory AudioPipelineConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AudioPipelineConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AudioPipelineConfig', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'cooldownDurationMs', $pb.PbFieldType.O3)
    ..aOB(2, _omitFieldNames ? '' : 'strictTransitions')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'maxTtsDurationMs', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AudioPipelineConfig clone() => AudioPipelineConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AudioPipelineConfig copyWith(void Function(AudioPipelineConfig) updates) => super.copyWith((message) => updates(message as AudioPipelineConfig)) as AudioPipelineConfig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AudioPipelineConfig create() => AudioPipelineConfig._();
  AudioPipelineConfig createEmptyInstance() => create();
  static $pb.PbList<AudioPipelineConfig> createRepeated() => $pb.PbList<AudioPipelineConfig>();
  @$core.pragma('dart2js:noInline')
  static AudioPipelineConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AudioPipelineConfig>(create);
  static AudioPipelineConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get cooldownDurationMs => $_getIZ(0);
  @$pb.TagNumber(1)
  set cooldownDurationMs($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCooldownDurationMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearCooldownDurationMs() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get strictTransitions => $_getBF(1);
  @$pb.TagNumber(2)
  set strictTransitions($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasStrictTransitions() => $_has(1);
  @$pb.TagNumber(2)
  void clearStrictTransitions() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get maxTtsDurationMs => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxTtsDurationMs($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMaxTtsDurationMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxTtsDurationMs() => clearField(3);
}

///  ---------------------------------------------------------------------------
///  v3.2: Aggregated voice-agent compose configuration.
///
///  Mirrors the C ABI `rac_voice_agent_config_t` and Swift
///  `VoiceAgentConfiguration`. The existing `runanywhere.v1.VoiceAgentConfig`
///  (idl/solutions.proto) is kept frozen for the SolutionConfig oneof — this
///  new message provides the fine-grained sub-component view consumed by the
///  `rac_voice_agent_initialize()` C entry-point.
///
///  Each sub-config string field uses a "model_id" naming convention; the
///  runtime resolves IDs against the model registry. An empty string means
///  "use the currently loaded model/voice for that capability".
///  ---------------------------------------------------------------------------
class VoiceAgentComposeConfig extends $pb.GeneratedMessage {
  factory VoiceAgentComposeConfig({
    $core.String? sttModelPath,
    $core.String? sttModelId,
    $core.String? sttModelName,
    $core.String? llmModelPath,
    $core.String? llmModelId,
    $core.String? llmModelName,
    $core.String? ttsVoicePath,
    $core.String? ttsVoiceId,
    $core.String? ttsVoiceName,
    $core.int? vadSampleRate,
    $core.double? vadFrameLength,
    $core.double? vadEnergyThreshold,
    $core.bool? wakewordEnabled,
    $core.String? wakewordModelPath,
    $core.String? wakewordModelId,
    $core.String? wakewordPhrase,
    $core.double? wakewordThreshold,
    $core.String? wakewordEmbeddingModelPath,
    $core.String? wakewordVadModelPath,
    VoiceSessionConfig? sessionConfig,
    AudioPipelineConfig? audioPipelineConfig,
  }) {
    final $result = create();
    if (sttModelPath != null) {
      $result.sttModelPath = sttModelPath;
    }
    if (sttModelId != null) {
      $result.sttModelId = sttModelId;
    }
    if (sttModelName != null) {
      $result.sttModelName = sttModelName;
    }
    if (llmModelPath != null) {
      $result.llmModelPath = llmModelPath;
    }
    if (llmModelId != null) {
      $result.llmModelId = llmModelId;
    }
    if (llmModelName != null) {
      $result.llmModelName = llmModelName;
    }
    if (ttsVoicePath != null) {
      $result.ttsVoicePath = ttsVoicePath;
    }
    if (ttsVoiceId != null) {
      $result.ttsVoiceId = ttsVoiceId;
    }
    if (ttsVoiceName != null) {
      $result.ttsVoiceName = ttsVoiceName;
    }
    if (vadSampleRate != null) {
      $result.vadSampleRate = vadSampleRate;
    }
    if (vadFrameLength != null) {
      $result.vadFrameLength = vadFrameLength;
    }
    if (vadEnergyThreshold != null) {
      $result.vadEnergyThreshold = vadEnergyThreshold;
    }
    if (wakewordEnabled != null) {
      $result.wakewordEnabled = wakewordEnabled;
    }
    if (wakewordModelPath != null) {
      $result.wakewordModelPath = wakewordModelPath;
    }
    if (wakewordModelId != null) {
      $result.wakewordModelId = wakewordModelId;
    }
    if (wakewordPhrase != null) {
      $result.wakewordPhrase = wakewordPhrase;
    }
    if (wakewordThreshold != null) {
      $result.wakewordThreshold = wakewordThreshold;
    }
    if (wakewordEmbeddingModelPath != null) {
      $result.wakewordEmbeddingModelPath = wakewordEmbeddingModelPath;
    }
    if (wakewordVadModelPath != null) {
      $result.wakewordVadModelPath = wakewordVadModelPath;
    }
    if (sessionConfig != null) {
      $result.sessionConfig = sessionConfig;
    }
    if (audioPipelineConfig != null) {
      $result.audioPipelineConfig = audioPipelineConfig;
    }
    return $result;
  }
  VoiceAgentComposeConfig._() : super();
  factory VoiceAgentComposeConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VoiceAgentComposeConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VoiceAgentComposeConfig', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'sttModelPath')
    ..aOS(2, _omitFieldNames ? '' : 'sttModelId')
    ..aOS(3, _omitFieldNames ? '' : 'sttModelName')
    ..aOS(4, _omitFieldNames ? '' : 'llmModelPath')
    ..aOS(5, _omitFieldNames ? '' : 'llmModelId')
    ..aOS(6, _omitFieldNames ? '' : 'llmModelName')
    ..aOS(7, _omitFieldNames ? '' : 'ttsVoicePath')
    ..aOS(8, _omitFieldNames ? '' : 'ttsVoiceId')
    ..aOS(9, _omitFieldNames ? '' : 'ttsVoiceName')
    ..a<$core.int>(10, _omitFieldNames ? '' : 'vadSampleRate', $pb.PbFieldType.O3)
    ..a<$core.double>(11, _omitFieldNames ? '' : 'vadFrameLength', $pb.PbFieldType.OF)
    ..a<$core.double>(12, _omitFieldNames ? '' : 'vadEnergyThreshold', $pb.PbFieldType.OF)
    ..aOB(13, _omitFieldNames ? '' : 'wakewordEnabled')
    ..aOS(14, _omitFieldNames ? '' : 'wakewordModelPath')
    ..aOS(15, _omitFieldNames ? '' : 'wakewordModelId')
    ..aOS(16, _omitFieldNames ? '' : 'wakewordPhrase')
    ..a<$core.double>(17, _omitFieldNames ? '' : 'wakewordThreshold', $pb.PbFieldType.OF)
    ..aOS(18, _omitFieldNames ? '' : 'wakewordEmbeddingModelPath')
    ..aOS(19, _omitFieldNames ? '' : 'wakewordVadModelPath')
    ..aOM<VoiceSessionConfig>(20, _omitFieldNames ? '' : 'sessionConfig', subBuilder: VoiceSessionConfig.create)
    ..aOM<AudioPipelineConfig>(21, _omitFieldNames ? '' : 'audioPipelineConfig', subBuilder: AudioPipelineConfig.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VoiceAgentComposeConfig clone() => VoiceAgentComposeConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VoiceAgentComposeConfig copyWith(void Function(VoiceAgentComposeConfig) updates) => super.copyWith((message) => updates(message as VoiceAgentComposeConfig)) as VoiceAgentComposeConfig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoiceAgentComposeConfig create() => VoiceAgentComposeConfig._();
  VoiceAgentComposeConfig createEmptyInstance() => create();
  static $pb.PbList<VoiceAgentComposeConfig> createRepeated() => $pb.PbList<VoiceAgentComposeConfig>();
  @$core.pragma('dart2js:noInline')
  static VoiceAgentComposeConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VoiceAgentComposeConfig>(create);
  static VoiceAgentComposeConfig? _defaultInstance;

  /// -------------------------------------------------------------------
  /// STT sub-config (mirrors rac_voice_agent_stt_config_t).
  /// -------------------------------------------------------------------
  @$pb.TagNumber(1)
  $core.String get sttModelPath => $_getSZ(0);
  @$pb.TagNumber(1)
  set sttModelPath($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSttModelPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearSttModelPath() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get sttModelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sttModelId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSttModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSttModelId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get sttModelName => $_getSZ(2);
  @$pb.TagNumber(3)
  set sttModelName($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSttModelName() => $_has(2);
  @$pb.TagNumber(3)
  void clearSttModelName() => clearField(3);

  /// -------------------------------------------------------------------
  /// LLM sub-config (mirrors rac_voice_agent_llm_config_t).
  /// -------------------------------------------------------------------
  @$pb.TagNumber(4)
  $core.String get llmModelPath => $_getSZ(3);
  @$pb.TagNumber(4)
  set llmModelPath($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasLlmModelPath() => $_has(3);
  @$pb.TagNumber(4)
  void clearLlmModelPath() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get llmModelId => $_getSZ(4);
  @$pb.TagNumber(5)
  set llmModelId($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasLlmModelId() => $_has(4);
  @$pb.TagNumber(5)
  void clearLlmModelId() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get llmModelName => $_getSZ(5);
  @$pb.TagNumber(6)
  set llmModelName($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasLlmModelName() => $_has(5);
  @$pb.TagNumber(6)
  void clearLlmModelName() => clearField(6);

  /// -------------------------------------------------------------------
  /// TTS sub-config (mirrors rac_voice_agent_tts_config_t).
  /// -------------------------------------------------------------------
  @$pb.TagNumber(7)
  $core.String get ttsVoicePath => $_getSZ(6);
  @$pb.TagNumber(7)
  set ttsVoicePath($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasTtsVoicePath() => $_has(6);
  @$pb.TagNumber(7)
  void clearTtsVoicePath() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get ttsVoiceId => $_getSZ(7);
  @$pb.TagNumber(8)
  set ttsVoiceId($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasTtsVoiceId() => $_has(7);
  @$pb.TagNumber(8)
  void clearTtsVoiceId() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get ttsVoiceName => $_getSZ(8);
  @$pb.TagNumber(9)
  set ttsVoiceName($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasTtsVoiceName() => $_has(8);
  @$pb.TagNumber(9)
  void clearTtsVoiceName() => clearField(9);

  /// -------------------------------------------------------------------
  /// VAD sub-config (mirrors rac_voice_agent_vad_config_t).
  /// -------------------------------------------------------------------
  @$pb.TagNumber(10)
  $core.int get vadSampleRate => $_getIZ(9);
  @$pb.TagNumber(10)
  set vadSampleRate($core.int v) { $_setSignedInt32(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasVadSampleRate() => $_has(9);
  @$pb.TagNumber(10)
  void clearVadSampleRate() => clearField(10);

  @$pb.TagNumber(11)
  $core.double get vadFrameLength => $_getN(10);
  @$pb.TagNumber(11)
  set vadFrameLength($core.double v) { $_setFloat(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasVadFrameLength() => $_has(10);
  @$pb.TagNumber(11)
  void clearVadFrameLength() => clearField(11);

  @$pb.TagNumber(12)
  $core.double get vadEnergyThreshold => $_getN(11);
  @$pb.TagNumber(12)
  set vadEnergyThreshold($core.double v) { $_setFloat(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasVadEnergyThreshold() => $_has(11);
  @$pb.TagNumber(12)
  void clearVadEnergyThreshold() => clearField(12);

  /// -------------------------------------------------------------------
  /// Wake-word sub-config (mirrors rac_voice_agent_wakeword_config_t /
  /// rac_wakeword_config_t).
  /// -------------------------------------------------------------------
  @$pb.TagNumber(13)
  $core.bool get wakewordEnabled => $_getBF(12);
  @$pb.TagNumber(13)
  set wakewordEnabled($core.bool v) { $_setBool(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasWakewordEnabled() => $_has(12);
  @$pb.TagNumber(13)
  void clearWakewordEnabled() => clearField(13);

  @$pb.TagNumber(14)
  $core.String get wakewordModelPath => $_getSZ(13);
  @$pb.TagNumber(14)
  set wakewordModelPath($core.String v) { $_setString(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasWakewordModelPath() => $_has(13);
  @$pb.TagNumber(14)
  void clearWakewordModelPath() => clearField(14);

  @$pb.TagNumber(15)
  $core.String get wakewordModelId => $_getSZ(14);
  @$pb.TagNumber(15)
  set wakewordModelId($core.String v) { $_setString(14, v); }
  @$pb.TagNumber(15)
  $core.bool hasWakewordModelId() => $_has(14);
  @$pb.TagNumber(15)
  void clearWakewordModelId() => clearField(15);

  @$pb.TagNumber(16)
  $core.String get wakewordPhrase => $_getSZ(15);
  @$pb.TagNumber(16)
  set wakewordPhrase($core.String v) { $_setString(15, v); }
  @$pb.TagNumber(16)
  $core.bool hasWakewordPhrase() => $_has(15);
  @$pb.TagNumber(16)
  void clearWakewordPhrase() => clearField(16);

  @$pb.TagNumber(17)
  $core.double get wakewordThreshold => $_getN(16);
  @$pb.TagNumber(17)
  set wakewordThreshold($core.double v) { $_setFloat(16, v); }
  @$pb.TagNumber(17)
  $core.bool hasWakewordThreshold() => $_has(16);
  @$pb.TagNumber(17)
  void clearWakewordThreshold() => clearField(17);

  @$pb.TagNumber(18)
  $core.String get wakewordEmbeddingModelPath => $_getSZ(17);
  @$pb.TagNumber(18)
  set wakewordEmbeddingModelPath($core.String v) { $_setString(17, v); }
  @$pb.TagNumber(18)
  $core.bool hasWakewordEmbeddingModelPath() => $_has(17);
  @$pb.TagNumber(18)
  void clearWakewordEmbeddingModelPath() => clearField(18);

  @$pb.TagNumber(19)
  $core.String get wakewordVadModelPath => $_getSZ(18);
  @$pb.TagNumber(19)
  set wakewordVadModelPath($core.String v) { $_setString(18, v); }
  @$pb.TagNumber(19)
  $core.bool hasWakewordVadModelPath() => $_has(18);
  @$pb.TagNumber(19)
  void clearWakewordVadModelPath() => clearField(19);

  /// -------------------------------------------------------------------
  /// Session-behavior sub-config. Optional so the C ABI can be invoked
  /// without runtime-behavior overrides (engine defaults applied).
  /// -------------------------------------------------------------------
  @$pb.TagNumber(20)
  VoiceSessionConfig get sessionConfig => $_getN(19);
  @$pb.TagNumber(20)
  set sessionConfig(VoiceSessionConfig v) { setField(20, v); }
  @$pb.TagNumber(20)
  $core.bool hasSessionConfig() => $_has(19);
  @$pb.TagNumber(20)
  void clearSessionConfig() => clearField(20);
  @$pb.TagNumber(20)
  VoiceSessionConfig ensureSessionConfig() => $_ensure(19);

  /// Audio state-machine behavior. Optional so defaults can be applied by
  /// the native voice-agent implementation.
  @$pb.TagNumber(21)
  AudioPipelineConfig get audioPipelineConfig => $_getN(20);
  @$pb.TagNumber(21)
  set audioPipelineConfig(AudioPipelineConfig v) { setField(21, v); }
  @$pb.TagNumber(21)
  $core.bool hasAudioPipelineConfig() => $_has(20);
  @$pb.TagNumber(21)
  void clearAudioPipelineConfig() => clearField(21);
  @$pb.TagNumber(21)
  AudioPipelineConfig ensureAudioPipelineConfig() => $_ensure(20);
}

class VoiceAgentApi {
  $pb.RpcClient _client;
  VoiceAgentApi(this._client);

  $async.Future<$0.VoiceEvent> stream($pb.ClientContext? ctx, VoiceAgentRequest request) =>
    _client.invoke<$0.VoiceEvent>(ctx, 'VoiceAgent', 'Stream', request, $0.VoiceEvent())
  ;
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
