// This is a generated file - do not edit.
//
// Generated from voice_agent_service.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'component_types.pbenum.dart' as $3;
import 'errors.pbenum.dart' as $4;
import 'stt_options.pb.dart' as $2;
import 'tts_options.pb.dart' as $1;
import 'voice_events.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// Empty request type — the voice agent already has its config set via
/// `rac_voice_agent_init()` at handle creation time. The Stream rpc just
/// opens a new event subscription on an existing handle.
class VoiceAgentRequest extends $pb.GeneratedMessage {
  factory VoiceAgentRequest({
    $core.String? eventFilter,
    $core.String? sessionId,
    $core.Iterable<$3.EventCategory>? categories,
    $4.ErrorSeverity? minSeverity,
    $fixnum.Int64? replayFromSeq,
    $core.bool? includeAudio,
  }) {
    final result = create();
    if (eventFilter != null) result.eventFilter = eventFilter;
    if (sessionId != null) result.sessionId = sessionId;
    if (categories != null) result.categories.addAll(categories);
    if (minSeverity != null) result.minSeverity = minSeverity;
    if (replayFromSeq != null) result.replayFromSeq = replayFromSeq;
    if (includeAudio != null) result.includeAudio = includeAudio;
    return result;
  }

  VoiceAgentRequest._();

  factory VoiceAgentRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VoiceAgentRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VoiceAgentRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'eventFilter')
    ..aOS(2, _omitFieldNames ? '' : 'sessionId')
    ..pc<$3.EventCategory>(
        3, _omitFieldNames ? '' : 'categories', $pb.PbFieldType.KE,
        valueOf: $3.EventCategory.valueOf,
        enumValues: $3.EventCategory.values,
        defaultEnumValue: $3.EventCategory.EVENT_CATEGORY_UNSPECIFIED)
    ..aE<$4.ErrorSeverity>(4, _omitFieldNames ? '' : 'minSeverity',
        enumValues: $4.ErrorSeverity.values)
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'replayFromSeq', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(6, _omitFieldNames ? '' : 'includeAudio')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceAgentRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceAgentRequest copyWith(void Function(VoiceAgentRequest) updates) =>
      super.copyWith((message) => updates(message as VoiceAgentRequest))
          as VoiceAgentRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoiceAgentRequest create() => VoiceAgentRequest._();
  @$core.override
  VoiceAgentRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VoiceAgentRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VoiceAgentRequest>(create);
  static VoiceAgentRequest? _defaultInstance;

  /// Optional: filter the stream to only certain VoiceEvent.payload arms
  /// (e.g. "user_said,assistant_token"). Empty = all events.
  @$pb.TagNumber(1)
  $core.String get eventFilter => $_getSZ(0);
  @$pb.TagNumber(1)
  set eventFilter($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEventFilter() => $_has(0);
  @$pb.TagNumber(1)
  void clearEventFilter() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get sessionId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sessionId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSessionId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSessionId() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<$3.EventCategory> get categories => $_getList(2);

  @$pb.TagNumber(4)
  $4.ErrorSeverity get minSeverity => $_getN(3);
  @$pb.TagNumber(4)
  set minSeverity($4.ErrorSeverity value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasMinSeverity() => $_has(3);
  @$pb.TagNumber(4)
  void clearMinSeverity() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get replayFromSeq => $_getI64(4);
  @$pb.TagNumber(5)
  set replayFromSeq($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasReplayFromSeq() => $_has(4);
  @$pb.TagNumber(5)
  void clearReplayFromSeq() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get includeAudio => $_getBF(5);
  @$pb.TagNumber(6)
  set includeAudio($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasIncludeAudio() => $_has(5);
  @$pb.TagNumber(6)
  void clearIncludeAudio() => $_clearField(6);
}

/// ---------------------------------------------------------------------------
/// One-shot voice-turn result.
///
/// Mirrors Swift `VoiceAgentResult`, Kotlin `VoiceAgentResult`, RN
/// `VoiceTurnResult`, Web `VoiceAgentResult`, Flutter (TBD), and the C ABI
/// `rac_voice_agent_result_t` (rac/features/voice_agent/rac_voice_agent.h).
/// Returned by the `processVoiceTurn` ergonomic API where a single audio
/// blob produces transcription + assistant response + synthesized audio in
/// one call (as opposed to the streaming path served by the Stream rpc).
/// ---------------------------------------------------------------------------
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
    $core.String? sessionId,
    $core.String? turnId,
    $fixnum.Int64? sttTimeMs,
    $fixnum.Int64? llmTimeMs,
    $fixnum.Int64? ttsTimeMs,
    $fixnum.Int64? totalTimeMs,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final result = create();
    if (speechDetected != null) result.speechDetected = speechDetected;
    if (transcription != null) result.transcription = transcription;
    if (assistantResponse != null) result.assistantResponse = assistantResponse;
    if (thinkingContent != null) result.thinkingContent = thinkingContent;
    if (synthesizedAudio != null) result.synthesizedAudio = synthesizedAudio;
    if (finalState != null) result.finalState = finalState;
    if (synthesizedAudioSampleRateHz != null)
      result.synthesizedAudioSampleRateHz = synthesizedAudioSampleRateHz;
    if (synthesizedAudioChannels != null)
      result.synthesizedAudioChannels = synthesizedAudioChannels;
    if (synthesizedAudioEncoding != null)
      result.synthesizedAudioEncoding = synthesizedAudioEncoding;
    if (sessionId != null) result.sessionId = sessionId;
    if (turnId != null) result.turnId = turnId;
    if (sttTimeMs != null) result.sttTimeMs = sttTimeMs;
    if (llmTimeMs != null) result.llmTimeMs = llmTimeMs;
    if (ttsTimeMs != null) result.ttsTimeMs = ttsTimeMs;
    if (totalTimeMs != null) result.totalTimeMs = totalTimeMs;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    return result;
  }

  VoiceAgentResult._();

  factory VoiceAgentResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VoiceAgentResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VoiceAgentResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'speechDetected')
    ..aOS(2, _omitFieldNames ? '' : 'transcription')
    ..aOS(3, _omitFieldNames ? '' : 'assistantResponse')
    ..aOS(4, _omitFieldNames ? '' : 'thinkingContent')
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'synthesizedAudio', $pb.PbFieldType.OY)
    ..aOM<$0.VoiceAgentComponentStates>(6, _omitFieldNames ? '' : 'finalState',
        subBuilder: $0.VoiceAgentComponentStates.create)
    ..aI(7, _omitFieldNames ? '' : 'synthesizedAudioSampleRateHz')
    ..aI(8, _omitFieldNames ? '' : 'synthesizedAudioChannels')
    ..aE<$0.AudioEncoding>(9, _omitFieldNames ? '' : 'synthesizedAudioEncoding',
        enumValues: $0.AudioEncoding.values)
    ..aOS(10, _omitFieldNames ? '' : 'sessionId')
    ..aOS(11, _omitFieldNames ? '' : 'turnId')
    ..aInt64(12, _omitFieldNames ? '' : 'sttTimeMs')
    ..aInt64(13, _omitFieldNames ? '' : 'llmTimeMs')
    ..aInt64(14, _omitFieldNames ? '' : 'ttsTimeMs')
    ..aInt64(15, _omitFieldNames ? '' : 'totalTimeMs')
    ..aOS(16, _omitFieldNames ? '' : 'errorMessage')
    ..aI(17, _omitFieldNames ? '' : 'errorCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceAgentResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceAgentResult copyWith(void Function(VoiceAgentResult) updates) =>
      super.copyWith((message) => updates(message as VoiceAgentResult))
          as VoiceAgentResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoiceAgentResult create() => VoiceAgentResult._();
  @$core.override
  VoiceAgentResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VoiceAgentResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VoiceAgentResult>(create);
  static VoiceAgentResult? _defaultInstance;

  /// Whether the input audio passed VAD's speech-detected check.
  @$pb.TagNumber(1)
  $core.bool get speechDetected => $_getBF(0);
  @$pb.TagNumber(1)
  set speechDetected($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSpeechDetected() => $_has(0);
  @$pb.TagNumber(1)
  void clearSpeechDetected() => $_clearField(1);

  /// Transcribed text from STT. Unset when speech_detected=false.
  @$pb.TagNumber(2)
  $core.String get transcription => $_getSZ(1);
  @$pb.TagNumber(2)
  set transcription($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTranscription() => $_has(1);
  @$pb.TagNumber(2)
  void clearTranscription() => $_clearField(2);

  /// Generated assistant response text from the LLM. Unset when STT
  /// produced no transcription or LLM was skipped.
  @$pb.TagNumber(3)
  $core.String get assistantResponse => $_getSZ(2);
  @$pb.TagNumber(3)
  set assistantResponse($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAssistantResponse() => $_has(2);
  @$pb.TagNumber(3)
  void clearAssistantResponse() => $_clearField(3);

  /// Thinking content extracted from `<think>...</think>` tags
  /// (qwen3, deepseek-r1). Unset when the active LLM does not emit
  /// a chain-of-thought trace.
  @$pb.TagNumber(4)
  $core.String get thinkingContent => $_getSZ(3);
  @$pb.TagNumber(4)
  set thinkingContent($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasThinkingContent() => $_has(3);
  @$pb.TagNumber(4)
  void clearThinkingContent() => $_clearField(4);

  /// Synthesized audio data from TTS. Encoding follows AudioFrameEvent
  /// conventions (typically PCM-F32-LE, sample rate per voice). Unset
  /// when TTS was skipped or auto_play_tts=false in VoiceSessionConfig.
  @$pb.TagNumber(5)
  $core.List<$core.int> get synthesizedAudio => $_getN(4);
  @$pb.TagNumber(5)
  set synthesizedAudio($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSynthesizedAudio() => $_has(4);
  @$pb.TagNumber(5)
  void clearSynthesizedAudio() => $_clearField(5);

  /// Component states captured at the end of the turn — useful for UIs
  /// surfacing readiness / partial-failure breakdowns alongside the
  /// final result. Unset when the caller does not ask for it.
  @$pb.TagNumber(6)
  $0.VoiceAgentComponentStates get finalState => $_getN(5);
  @$pb.TagNumber(6)
  set finalState($0.VoiceAgentComponentStates value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasFinalState() => $_has(5);
  @$pb.TagNumber(6)
  void clearFinalState() => $_clearField(6);
  @$pb.TagNumber(6)
  $0.VoiceAgentComponentStates ensureFinalState() => $_ensure(5);

  /// Audio metadata for synthesized_audio. 0/UNSPECIFIED = backend default
  /// or unknown.
  @$pb.TagNumber(7)
  $core.int get synthesizedAudioSampleRateHz => $_getIZ(6);
  @$pb.TagNumber(7)
  set synthesizedAudioSampleRateHz($core.int value) =>
      $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSynthesizedAudioSampleRateHz() => $_has(6);
  @$pb.TagNumber(7)
  void clearSynthesizedAudioSampleRateHz() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get synthesizedAudioChannels => $_getIZ(7);
  @$pb.TagNumber(8)
  set synthesizedAudioChannels($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasSynthesizedAudioChannels() => $_has(7);
  @$pb.TagNumber(8)
  void clearSynthesizedAudioChannels() => $_clearField(8);

  @$pb.TagNumber(9)
  $0.AudioEncoding get synthesizedAudioEncoding => $_getN(8);
  @$pb.TagNumber(9)
  set synthesizedAudioEncoding($0.AudioEncoding value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasSynthesizedAudioEncoding() => $_has(8);
  @$pb.TagNumber(9)
  void clearSynthesizedAudioEncoding() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get sessionId => $_getSZ(9);
  @$pb.TagNumber(10)
  set sessionId($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasSessionId() => $_has(9);
  @$pb.TagNumber(10)
  void clearSessionId() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get turnId => $_getSZ(10);
  @$pb.TagNumber(11)
  set turnId($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasTurnId() => $_has(10);
  @$pb.TagNumber(11)
  void clearTurnId() => $_clearField(11);

  @$pb.TagNumber(12)
  $fixnum.Int64 get sttTimeMs => $_getI64(11);
  @$pb.TagNumber(12)
  set sttTimeMs($fixnum.Int64 value) => $_setInt64(11, value);
  @$pb.TagNumber(12)
  $core.bool hasSttTimeMs() => $_has(11);
  @$pb.TagNumber(12)
  void clearSttTimeMs() => $_clearField(12);

  @$pb.TagNumber(13)
  $fixnum.Int64 get llmTimeMs => $_getI64(12);
  @$pb.TagNumber(13)
  set llmTimeMs($fixnum.Int64 value) => $_setInt64(12, value);
  @$pb.TagNumber(13)
  $core.bool hasLlmTimeMs() => $_has(12);
  @$pb.TagNumber(13)
  void clearLlmTimeMs() => $_clearField(13);

  @$pb.TagNumber(14)
  $fixnum.Int64 get ttsTimeMs => $_getI64(13);
  @$pb.TagNumber(14)
  set ttsTimeMs($fixnum.Int64 value) => $_setInt64(13, value);
  @$pb.TagNumber(14)
  $core.bool hasTtsTimeMs() => $_has(13);
  @$pb.TagNumber(14)
  void clearTtsTimeMs() => $_clearField(14);

  @$pb.TagNumber(15)
  $fixnum.Int64 get totalTimeMs => $_getI64(14);
  @$pb.TagNumber(15)
  set totalTimeMs($fixnum.Int64 value) => $_setInt64(14, value);
  @$pb.TagNumber(15)
  $core.bool hasTotalTimeMs() => $_has(14);
  @$pb.TagNumber(15)
  void clearTotalTimeMs() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.String get errorMessage => $_getSZ(15);
  @$pb.TagNumber(16)
  set errorMessage($core.String value) => $_setString(15, value);
  @$pb.TagNumber(16)
  $core.bool hasErrorMessage() => $_has(15);
  @$pb.TagNumber(16)
  void clearErrorMessage() => $_clearField(16);

  @$pb.TagNumber(17)
  $core.int get errorCode => $_getIZ(16);
  @$pb.TagNumber(17)
  set errorCode($core.int value) => $_setSignedInt32(16, value);
  @$pb.TagNumber(17)
  $core.bool hasErrorCode() => $_has(16);
  @$pb.TagNumber(17)
  void clearErrorCode() => $_clearField(17);
}

class VoiceAgentTurnRequest extends $pb.GeneratedMessage {
  factory VoiceAgentTurnRequest({
    $core.String? requestId,
    $core.String? sessionId,
    $core.List<$core.int>? audioData,
    $core.int? sampleRateHz,
    $core.int? channels,
    $0.AudioEncoding? encoding,
    VoiceSessionConfig? sessionConfig,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (sessionId != null) result.sessionId = sessionId;
    if (audioData != null) result.audioData = audioData;
    if (sampleRateHz != null) result.sampleRateHz = sampleRateHz;
    if (channels != null) result.channels = channels;
    if (encoding != null) result.encoding = encoding;
    if (sessionConfig != null) result.sessionConfig = sessionConfig;
    if (metadata != null) result.metadata.addEntries(metadata);
    return result;
  }

  VoiceAgentTurnRequest._();

  factory VoiceAgentTurnRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VoiceAgentTurnRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VoiceAgentTurnRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOS(2, _omitFieldNames ? '' : 'sessionId')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'audioData', $pb.PbFieldType.OY)
    ..aI(4, _omitFieldNames ? '' : 'sampleRateHz')
    ..aI(5, _omitFieldNames ? '' : 'channels')
    ..aE<$0.AudioEncoding>(6, _omitFieldNames ? '' : 'encoding',
        enumValues: $0.AudioEncoding.values)
    ..aOM<VoiceSessionConfig>(7, _omitFieldNames ? '' : 'sessionConfig',
        subBuilder: VoiceSessionConfig.create)
    ..m<$core.String, $core.String>(8, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'VoiceAgentTurnRequest.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceAgentTurnRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceAgentTurnRequest copyWith(
          void Function(VoiceAgentTurnRequest) updates) =>
      super.copyWith((message) => updates(message as VoiceAgentTurnRequest))
          as VoiceAgentTurnRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoiceAgentTurnRequest create() => VoiceAgentTurnRequest._();
  @$core.override
  VoiceAgentTurnRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VoiceAgentTurnRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VoiceAgentTurnRequest>(create);
  static VoiceAgentTurnRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get sessionId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sessionId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSessionId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSessionId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get audioData => $_getN(2);
  @$pb.TagNumber(3)
  set audioData($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAudioData() => $_has(2);
  @$pb.TagNumber(3)
  void clearAudioData() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get sampleRateHz => $_getIZ(3);
  @$pb.TagNumber(4)
  set sampleRateHz($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSampleRateHz() => $_has(3);
  @$pb.TagNumber(4)
  void clearSampleRateHz() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get channels => $_getIZ(4);
  @$pb.TagNumber(5)
  set channels($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasChannels() => $_has(4);
  @$pb.TagNumber(5)
  void clearChannels() => $_clearField(5);

  @$pb.TagNumber(6)
  $0.AudioEncoding get encoding => $_getN(5);
  @$pb.TagNumber(6)
  set encoding($0.AudioEncoding value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasEncoding() => $_has(5);
  @$pb.TagNumber(6)
  void clearEncoding() => $_clearField(6);

  @$pb.TagNumber(7)
  VoiceSessionConfig get sessionConfig => $_getN(6);
  @$pb.TagNumber(7)
  set sessionConfig(VoiceSessionConfig value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasSessionConfig() => $_has(6);
  @$pb.TagNumber(7)
  void clearSessionConfig() => $_clearField(7);
  @$pb.TagNumber(7)
  VoiceSessionConfig ensureSessionConfig() => $_ensure(6);

  @$pb.TagNumber(8)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(7);
}

/// ---------------------------------------------------------------------------
/// Voice session behavior configuration.
///
/// Mirrors Swift `VoiceSessionConfig` and Kotlin `VoiceSessionConfig`.
/// Controls runtime behavior of the voice agent's session loop — silence
/// timing, speech threshold, auto-TTS playback, continuous mode, and
/// LLM thinking-mode toggle.
/// ---------------------------------------------------------------------------
class VoiceSessionConfig extends $pb.GeneratedMessage {
  factory VoiceSessionConfig({
    $core.int? silenceDurationMs,
    $core.double? speechThreshold,
    $core.bool? autoPlayTts,
    $core.bool? continuousMode,
    $core.bool? thinkingModeEnabled,
    $core.int? maxTokens,
    $core.int? maxRecordingDurationMs,
    $core.String? languageCode,
    $core.String? voiceId,
  }) {
    final result = create();
    if (silenceDurationMs != null) result.silenceDurationMs = silenceDurationMs;
    if (speechThreshold != null) result.speechThreshold = speechThreshold;
    if (autoPlayTts != null) result.autoPlayTts = autoPlayTts;
    if (continuousMode != null) result.continuousMode = continuousMode;
    if (thinkingModeEnabled != null)
      result.thinkingModeEnabled = thinkingModeEnabled;
    if (maxTokens != null) result.maxTokens = maxTokens;
    if (maxRecordingDurationMs != null)
      result.maxRecordingDurationMs = maxRecordingDurationMs;
    if (languageCode != null) result.languageCode = languageCode;
    if (voiceId != null) result.voiceId = voiceId;
    return result;
  }

  VoiceSessionConfig._();

  factory VoiceSessionConfig.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VoiceSessionConfig.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VoiceSessionConfig',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'silenceDurationMs')
    ..aD(2, _omitFieldNames ? '' : 'speechThreshold',
        fieldType: $pb.PbFieldType.OF)
    ..aOB(3, _omitFieldNames ? '' : 'autoPlayTts')
    ..aOB(4, _omitFieldNames ? '' : 'continuousMode')
    ..aOB(5, _omitFieldNames ? '' : 'thinkingModeEnabled')
    ..aI(6, _omitFieldNames ? '' : 'maxTokens')
    ..aI(7, _omitFieldNames ? '' : 'maxRecordingDurationMs')
    ..aOS(8, _omitFieldNames ? '' : 'languageCode')
    ..aOS(9, _omitFieldNames ? '' : 'voiceId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceSessionConfig clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceSessionConfig copyWith(void Function(VoiceSessionConfig) updates) =>
      super.copyWith((message) => updates(message as VoiceSessionConfig))
          as VoiceSessionConfig;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoiceSessionConfig create() => VoiceSessionConfig._();
  @$core.override
  VoiceSessionConfig createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VoiceSessionConfig getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VoiceSessionConfig>(create);
  static VoiceSessionConfig? _defaultInstance;

  /// Silence duration (milliseconds) before processing the speech
  /// buffer. Default per Swift/Kotlin: 1500 ms.
  @$pb.TagNumber(1)
  $core.int get silenceDurationMs => $_getIZ(0);
  @$pb.TagNumber(1)
  set silenceDurationMs($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSilenceDurationMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearSilenceDurationMs() => $_clearField(1);

  /// Minimum audio level to detect speech (0.0 - 1.0). Default per
  /// Swift/Kotlin: 0.1.
  @$pb.TagNumber(2)
  $core.double get speechThreshold => $_getN(1);
  @$pb.TagNumber(2)
  set speechThreshold($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSpeechThreshold() => $_has(1);
  @$pb.TagNumber(2)
  void clearSpeechThreshold() => $_clearField(2);

  /// Whether to auto-play TTS response after synthesis. Default true.
  @$pb.TagNumber(3)
  $core.bool get autoPlayTts => $_getBF(2);
  @$pb.TagNumber(3)
  set autoPlayTts($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAutoPlayTts() => $_has(2);
  @$pb.TagNumber(3)
  void clearAutoPlayTts() => $_clearField(3);

  /// Whether to auto-resume listening after TTS playback. Default true.
  @$pb.TagNumber(4)
  $core.bool get continuousMode => $_getBF(3);
  @$pb.TagNumber(4)
  set continuousMode($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasContinuousMode() => $_has(3);
  @$pb.TagNumber(4)
  void clearContinuousMode() => $_clearField(4);

  /// Whether thinking mode is enabled for the LLM (qwen3, deepseek-r1).
  /// Default false.
  @$pb.TagNumber(5)
  $core.bool get thinkingModeEnabled => $_getBF(4);
  @$pb.TagNumber(5)
  set thinkingModeEnabled($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasThinkingModeEnabled() => $_has(4);
  @$pb.TagNumber(5)
  void clearThinkingModeEnabled() => $_clearField(5);

  /// Optional per-turn LLM max token limit. 0 = LLM/default.
  @$pb.TagNumber(6)
  $core.int get maxTokens => $_getIZ(5);
  @$pb.TagNumber(6)
  set maxTokens($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMaxTokens() => $_has(5);
  @$pb.TagNumber(6)
  void clearMaxTokens() => $_clearField(6);

  /// Maximum recording duration before forcing an end-of-turn. 0 = default.
  @$pb.TagNumber(7)
  $core.int get maxRecordingDurationMs => $_getIZ(6);
  @$pb.TagNumber(7)
  set maxRecordingDurationMs($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasMaxRecordingDurationMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearMaxRecordingDurationMs() => $_clearField(7);

  /// Optional language/voice hints passed to STT/TTS adapters.
  @$pb.TagNumber(8)
  $core.String get languageCode => $_getSZ(7);
  @$pb.TagNumber(8)
  set languageCode($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasLanguageCode() => $_has(7);
  @$pb.TagNumber(8)
  void clearLanguageCode() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get voiceId => $_getSZ(8);
  @$pb.TagNumber(9)
  set voiceId($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasVoiceId() => $_has(8);
  @$pb.TagNumber(9)
  void clearVoiceId() => $_clearField(9);
}

/// ---------------------------------------------------------------------------
/// Audio pipeline state-manager configuration.
///
/// Mirrors rac_audio_pipeline_config_t and the Swift state-manager knobs used
/// to prevent microphone/TTS feedback loops.
/// ---------------------------------------------------------------------------
class AudioPipelineConfig extends $pb.GeneratedMessage {
  factory AudioPipelineConfig({
    $core.int? cooldownDurationMs,
    $core.bool? strictTransitions,
    $core.int? maxTtsDurationMs,
  }) {
    final result = create();
    if (cooldownDurationMs != null)
      result.cooldownDurationMs = cooldownDurationMs;
    if (strictTransitions != null) result.strictTransitions = strictTransitions;
    if (maxTtsDurationMs != null) result.maxTtsDurationMs = maxTtsDurationMs;
    return result;
  }

  AudioPipelineConfig._();

  factory AudioPipelineConfig.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AudioPipelineConfig.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AudioPipelineConfig',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'cooldownDurationMs')
    ..aOB(2, _omitFieldNames ? '' : 'strictTransitions')
    ..aI(3, _omitFieldNames ? '' : 'maxTtsDurationMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AudioPipelineConfig clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AudioPipelineConfig copyWith(void Function(AudioPipelineConfig) updates) =>
      super.copyWith((message) => updates(message as AudioPipelineConfig))
          as AudioPipelineConfig;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AudioPipelineConfig create() => AudioPipelineConfig._();
  @$core.override
  AudioPipelineConfig createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AudioPipelineConfig getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AudioPipelineConfig>(create);
  static AudioPipelineConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get cooldownDurationMs => $_getIZ(0);
  @$pb.TagNumber(1)
  set cooldownDurationMs($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCooldownDurationMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearCooldownDurationMs() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get strictTransitions => $_getBF(1);
  @$pb.TagNumber(2)
  set strictTransitions($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStrictTransitions() => $_has(1);
  @$pb.TagNumber(2)
  void clearStrictTransitions() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get maxTtsDurationMs => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxTtsDurationMs($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMaxTtsDurationMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxTtsDurationMs() => $_clearField(3);
}

/// ---------------------------------------------------------------------------
/// Aggregated voice-agent compose configuration.
///
/// Mirrors the C ABI `rac_voice_agent_config_t` and Swift
/// `VoiceAgentConfiguration`. The existing `runanywhere.v1.VoiceAgentConfig`
/// (idl/solutions.proto) is kept frozen for the SolutionConfig oneof — this
/// new message provides the fine-grained sub-component view consumed by the
/// `rac_voice_agent_initialize()` C entry-point.
///
/// Each sub-config string field uses a "model_id" naming convention; the
/// runtime resolves IDs against the model registry. An empty string means
/// "use the currently loaded model/voice for that capability".
/// ---------------------------------------------------------------------------
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
    $core.String? sessionId,
    $core.String? defaultLanguageCode,
  }) {
    final result = create();
    if (sttModelPath != null) result.sttModelPath = sttModelPath;
    if (sttModelId != null) result.sttModelId = sttModelId;
    if (sttModelName != null) result.sttModelName = sttModelName;
    if (llmModelPath != null) result.llmModelPath = llmModelPath;
    if (llmModelId != null) result.llmModelId = llmModelId;
    if (llmModelName != null) result.llmModelName = llmModelName;
    if (ttsVoicePath != null) result.ttsVoicePath = ttsVoicePath;
    if (ttsVoiceId != null) result.ttsVoiceId = ttsVoiceId;
    if (ttsVoiceName != null) result.ttsVoiceName = ttsVoiceName;
    if (vadSampleRate != null) result.vadSampleRate = vadSampleRate;
    if (vadFrameLength != null) result.vadFrameLength = vadFrameLength;
    if (vadEnergyThreshold != null)
      result.vadEnergyThreshold = vadEnergyThreshold;
    if (wakewordEnabled != null) result.wakewordEnabled = wakewordEnabled;
    if (wakewordModelPath != null) result.wakewordModelPath = wakewordModelPath;
    if (wakewordModelId != null) result.wakewordModelId = wakewordModelId;
    if (wakewordPhrase != null) result.wakewordPhrase = wakewordPhrase;
    if (wakewordThreshold != null) result.wakewordThreshold = wakewordThreshold;
    if (wakewordEmbeddingModelPath != null)
      result.wakewordEmbeddingModelPath = wakewordEmbeddingModelPath;
    if (wakewordVadModelPath != null)
      result.wakewordVadModelPath = wakewordVadModelPath;
    if (sessionConfig != null) result.sessionConfig = sessionConfig;
    if (audioPipelineConfig != null)
      result.audioPipelineConfig = audioPipelineConfig;
    if (sessionId != null) result.sessionId = sessionId;
    if (defaultLanguageCode != null)
      result.defaultLanguageCode = defaultLanguageCode;
    return result;
  }

  VoiceAgentComposeConfig._();

  factory VoiceAgentComposeConfig.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VoiceAgentComposeConfig.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VoiceAgentComposeConfig',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'sttModelPath')
    ..aOS(2, _omitFieldNames ? '' : 'sttModelId')
    ..aOS(3, _omitFieldNames ? '' : 'sttModelName')
    ..aOS(4, _omitFieldNames ? '' : 'llmModelPath')
    ..aOS(5, _omitFieldNames ? '' : 'llmModelId')
    ..aOS(6, _omitFieldNames ? '' : 'llmModelName')
    ..aOS(7, _omitFieldNames ? '' : 'ttsVoicePath')
    ..aOS(8, _omitFieldNames ? '' : 'ttsVoiceId')
    ..aOS(9, _omitFieldNames ? '' : 'ttsVoiceName')
    ..aI(10, _omitFieldNames ? '' : 'vadSampleRate')
    ..aD(11, _omitFieldNames ? '' : 'vadFrameLength',
        fieldType: $pb.PbFieldType.OF)
    ..aD(12, _omitFieldNames ? '' : 'vadEnergyThreshold',
        fieldType: $pb.PbFieldType.OF)
    ..aOB(13, _omitFieldNames ? '' : 'wakewordEnabled')
    ..aOS(14, _omitFieldNames ? '' : 'wakewordModelPath')
    ..aOS(15, _omitFieldNames ? '' : 'wakewordModelId')
    ..aOS(16, _omitFieldNames ? '' : 'wakewordPhrase')
    ..aD(17, _omitFieldNames ? '' : 'wakewordThreshold',
        fieldType: $pb.PbFieldType.OF)
    ..aOS(18, _omitFieldNames ? '' : 'wakewordEmbeddingModelPath')
    ..aOS(19, _omitFieldNames ? '' : 'wakewordVadModelPath')
    ..aOM<VoiceSessionConfig>(20, _omitFieldNames ? '' : 'sessionConfig',
        subBuilder: VoiceSessionConfig.create)
    ..aOM<AudioPipelineConfig>(21, _omitFieldNames ? '' : 'audioPipelineConfig',
        subBuilder: AudioPipelineConfig.create)
    ..aOS(22, _omitFieldNames ? '' : 'sessionId')
    ..aOS(23, _omitFieldNames ? '' : 'defaultLanguageCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceAgentComposeConfig clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceAgentComposeConfig copyWith(
          void Function(VoiceAgentComposeConfig) updates) =>
      super.copyWith((message) => updates(message as VoiceAgentComposeConfig))
          as VoiceAgentComposeConfig;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoiceAgentComposeConfig create() => VoiceAgentComposeConfig._();
  @$core.override
  VoiceAgentComposeConfig createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VoiceAgentComposeConfig getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VoiceAgentComposeConfig>(create);
  static VoiceAgentComposeConfig? _defaultInstance;

  /// -------------------------------------------------------------------
  /// STT sub-config (mirrors rac_voice_agent_stt_config_t).
  /// -------------------------------------------------------------------
  @$pb.TagNumber(1)
  $core.String get sttModelPath => $_getSZ(0);
  @$pb.TagNumber(1)
  set sttModelPath($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSttModelPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearSttModelPath() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get sttModelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sttModelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSttModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSttModelId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get sttModelName => $_getSZ(2);
  @$pb.TagNumber(3)
  set sttModelName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSttModelName() => $_has(2);
  @$pb.TagNumber(3)
  void clearSttModelName() => $_clearField(3);

  /// -------------------------------------------------------------------
  /// LLM sub-config (mirrors rac_voice_agent_llm_config_t).
  /// -------------------------------------------------------------------
  @$pb.TagNumber(4)
  $core.String get llmModelPath => $_getSZ(3);
  @$pb.TagNumber(4)
  set llmModelPath($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLlmModelPath() => $_has(3);
  @$pb.TagNumber(4)
  void clearLlmModelPath() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get llmModelId => $_getSZ(4);
  @$pb.TagNumber(5)
  set llmModelId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasLlmModelId() => $_has(4);
  @$pb.TagNumber(5)
  void clearLlmModelId() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get llmModelName => $_getSZ(5);
  @$pb.TagNumber(6)
  set llmModelName($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLlmModelName() => $_has(5);
  @$pb.TagNumber(6)
  void clearLlmModelName() => $_clearField(6);

  /// -------------------------------------------------------------------
  /// TTS sub-config (mirrors rac_voice_agent_tts_config_t).
  /// -------------------------------------------------------------------
  @$pb.TagNumber(7)
  $core.String get ttsVoicePath => $_getSZ(6);
  @$pb.TagNumber(7)
  set ttsVoicePath($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasTtsVoicePath() => $_has(6);
  @$pb.TagNumber(7)
  void clearTtsVoicePath() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get ttsVoiceId => $_getSZ(7);
  @$pb.TagNumber(8)
  set ttsVoiceId($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasTtsVoiceId() => $_has(7);
  @$pb.TagNumber(8)
  void clearTtsVoiceId() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get ttsVoiceName => $_getSZ(8);
  @$pb.TagNumber(9)
  set ttsVoiceName($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasTtsVoiceName() => $_has(8);
  @$pb.TagNumber(9)
  void clearTtsVoiceName() => $_clearField(9);

  /// -------------------------------------------------------------------
  /// VAD sub-config (mirrors rac_voice_agent_vad_config_t).
  /// -------------------------------------------------------------------
  @$pb.TagNumber(10)
  $core.int get vadSampleRate => $_getIZ(9);
  @$pb.TagNumber(10)
  set vadSampleRate($core.int value) => $_setSignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasVadSampleRate() => $_has(9);
  @$pb.TagNumber(10)
  void clearVadSampleRate() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.double get vadFrameLength => $_getN(10);
  @$pb.TagNumber(11)
  set vadFrameLength($core.double value) => $_setFloat(10, value);
  @$pb.TagNumber(11)
  $core.bool hasVadFrameLength() => $_has(10);
  @$pb.TagNumber(11)
  void clearVadFrameLength() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.double get vadEnergyThreshold => $_getN(11);
  @$pb.TagNumber(12)
  set vadEnergyThreshold($core.double value) => $_setFloat(11, value);
  @$pb.TagNumber(12)
  $core.bool hasVadEnergyThreshold() => $_has(11);
  @$pb.TagNumber(12)
  void clearVadEnergyThreshold() => $_clearField(12);

  /// -------------------------------------------------------------------
  /// Wake-word sub-config (mirrors rac_voice_agent_wakeword_config_t /
  /// rac_wakeword_config_t).
  /// -------------------------------------------------------------------
  @$pb.TagNumber(13)
  $core.bool get wakewordEnabled => $_getBF(12);
  @$pb.TagNumber(13)
  set wakewordEnabled($core.bool value) => $_setBool(12, value);
  @$pb.TagNumber(13)
  $core.bool hasWakewordEnabled() => $_has(12);
  @$pb.TagNumber(13)
  void clearWakewordEnabled() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get wakewordModelPath => $_getSZ(13);
  @$pb.TagNumber(14)
  set wakewordModelPath($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasWakewordModelPath() => $_has(13);
  @$pb.TagNumber(14)
  void clearWakewordModelPath() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.String get wakewordModelId => $_getSZ(14);
  @$pb.TagNumber(15)
  set wakewordModelId($core.String value) => $_setString(14, value);
  @$pb.TagNumber(15)
  $core.bool hasWakewordModelId() => $_has(14);
  @$pb.TagNumber(15)
  void clearWakewordModelId() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.String get wakewordPhrase => $_getSZ(15);
  @$pb.TagNumber(16)
  set wakewordPhrase($core.String value) => $_setString(15, value);
  @$pb.TagNumber(16)
  $core.bool hasWakewordPhrase() => $_has(15);
  @$pb.TagNumber(16)
  void clearWakewordPhrase() => $_clearField(16);

  @$pb.TagNumber(17)
  $core.double get wakewordThreshold => $_getN(16);
  @$pb.TagNumber(17)
  set wakewordThreshold($core.double value) => $_setFloat(16, value);
  @$pb.TagNumber(17)
  $core.bool hasWakewordThreshold() => $_has(16);
  @$pb.TagNumber(17)
  void clearWakewordThreshold() => $_clearField(17);

  @$pb.TagNumber(18)
  $core.String get wakewordEmbeddingModelPath => $_getSZ(17);
  @$pb.TagNumber(18)
  set wakewordEmbeddingModelPath($core.String value) => $_setString(17, value);
  @$pb.TagNumber(18)
  $core.bool hasWakewordEmbeddingModelPath() => $_has(17);
  @$pb.TagNumber(18)
  void clearWakewordEmbeddingModelPath() => $_clearField(18);

  @$pb.TagNumber(19)
  $core.String get wakewordVadModelPath => $_getSZ(18);
  @$pb.TagNumber(19)
  set wakewordVadModelPath($core.String value) => $_setString(18, value);
  @$pb.TagNumber(19)
  $core.bool hasWakewordVadModelPath() => $_has(18);
  @$pb.TagNumber(19)
  void clearWakewordVadModelPath() => $_clearField(19);

  /// -------------------------------------------------------------------
  /// Session-behavior sub-config. Optional so the C ABI can be invoked
  /// without runtime-behavior overrides (engine defaults applied).
  /// -------------------------------------------------------------------
  @$pb.TagNumber(20)
  VoiceSessionConfig get sessionConfig => $_getN(19);
  @$pb.TagNumber(20)
  set sessionConfig(VoiceSessionConfig value) => $_setField(20, value);
  @$pb.TagNumber(20)
  $core.bool hasSessionConfig() => $_has(19);
  @$pb.TagNumber(20)
  void clearSessionConfig() => $_clearField(20);
  @$pb.TagNumber(20)
  VoiceSessionConfig ensureSessionConfig() => $_ensure(19);

  /// Audio state-machine behavior. Optional so defaults can be applied by
  /// the native voice-agent implementation.
  @$pb.TagNumber(21)
  AudioPipelineConfig get audioPipelineConfig => $_getN(20);
  @$pb.TagNumber(21)
  set audioPipelineConfig(AudioPipelineConfig value) => $_setField(21, value);
  @$pb.TagNumber(21)
  $core.bool hasAudioPipelineConfig() => $_has(20);
  @$pb.TagNumber(21)
  void clearAudioPipelineConfig() => $_clearField(21);
  @$pb.TagNumber(21)
  AudioPipelineConfig ensureAudioPipelineConfig() => $_ensure(20);

  /// Correlation and defaults for event streams and one-shot turn APIs.
  @$pb.TagNumber(22)
  $core.String get sessionId => $_getSZ(21);
  @$pb.TagNumber(22)
  set sessionId($core.String value) => $_setString(21, value);
  @$pb.TagNumber(22)
  $core.bool hasSessionId() => $_has(21);
  @$pb.TagNumber(22)
  void clearSessionId() => $_clearField(22);

  @$pb.TagNumber(23)
  $core.String get defaultLanguageCode => $_getSZ(22);
  @$pb.TagNumber(23)
  set defaultLanguageCode($core.String value) => $_setString(22, value);
  @$pb.TagNumber(23)
  $core.bool hasDefaultLanguageCode() => $_has(22);
  @$pb.TagNumber(23)
  void clearDefaultLanguageCode() => $_clearField(23);
}

/// Helper-level proto requests for voice-agent sub-components.
class VoiceAgentTranscribeProtoRequest extends $pb.GeneratedMessage {
  factory VoiceAgentTranscribeProtoRequest({
    $core.List<$core.int>? audioData,
    $core.String? sessionId,
    $core.int? sampleRate,
    $core.String? languageHint,
    $core.int? channels,
    $0.AudioEncoding? encoding,
  }) {
    final result = create();
    if (audioData != null) result.audioData = audioData;
    if (sessionId != null) result.sessionId = sessionId;
    if (sampleRate != null) result.sampleRate = sampleRate;
    if (languageHint != null) result.languageHint = languageHint;
    if (channels != null) result.channels = channels;
    if (encoding != null) result.encoding = encoding;
    return result;
  }

  VoiceAgentTranscribeProtoRequest._();

  factory VoiceAgentTranscribeProtoRequest.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VoiceAgentTranscribeProtoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VoiceAgentTranscribeProtoRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'audioData', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'sessionId')
    ..aI(3, _omitFieldNames ? '' : 'sampleRate')
    ..aOS(4, _omitFieldNames ? '' : 'languageHint')
    ..aI(5, _omitFieldNames ? '' : 'channels')
    ..aE<$0.AudioEncoding>(6, _omitFieldNames ? '' : 'encoding',
        enumValues: $0.AudioEncoding.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceAgentTranscribeProtoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceAgentTranscribeProtoRequest copyWith(
          void Function(VoiceAgentTranscribeProtoRequest) updates) =>
      super.copyWith(
              (message) => updates(message as VoiceAgentTranscribeProtoRequest))
          as VoiceAgentTranscribeProtoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoiceAgentTranscribeProtoRequest create() =>
      VoiceAgentTranscribeProtoRequest._();
  @$core.override
  VoiceAgentTranscribeProtoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VoiceAgentTranscribeProtoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VoiceAgentTranscribeProtoRequest>(
          create);
  static VoiceAgentTranscribeProtoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get audioData => $_getN(0);
  @$pb.TagNumber(1)
  set audioData($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAudioData() => $_has(0);
  @$pb.TagNumber(1)
  void clearAudioData() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get sessionId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sessionId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSessionId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSessionId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get sampleRate => $_getIZ(2);
  @$pb.TagNumber(3)
  set sampleRate($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSampleRate() => $_has(2);
  @$pb.TagNumber(3)
  void clearSampleRate() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get languageHint => $_getSZ(3);
  @$pb.TagNumber(4)
  set languageHint($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLanguageHint() => $_has(3);
  @$pb.TagNumber(4)
  void clearLanguageHint() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get channels => $_getIZ(4);
  @$pb.TagNumber(5)
  set channels($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasChannels() => $_has(4);
  @$pb.TagNumber(5)
  void clearChannels() => $_clearField(5);

  @$pb.TagNumber(6)
  $0.AudioEncoding get encoding => $_getN(5);
  @$pb.TagNumber(6)
  set encoding($0.AudioEncoding value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasEncoding() => $_has(5);
  @$pb.TagNumber(6)
  void clearEncoding() => $_clearField(6);
}

class VoiceAgentSynthesizeSpeechProtoRequest extends $pb.GeneratedMessage {
  factory VoiceAgentSynthesizeSpeechProtoRequest({
    $core.String? text,
    $core.String? sessionId,
    $1.TTSOptions? options,
  }) {
    final result = create();
    if (text != null) result.text = text;
    if (sessionId != null) result.sessionId = sessionId;
    if (options != null) result.options = options;
    return result;
  }

  VoiceAgentSynthesizeSpeechProtoRequest._();

  factory VoiceAgentSynthesizeSpeechProtoRequest.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VoiceAgentSynthesizeSpeechProtoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VoiceAgentSynthesizeSpeechProtoRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOS(2, _omitFieldNames ? '' : 'sessionId')
    ..aOM<$1.TTSOptions>(3, _omitFieldNames ? '' : 'options',
        subBuilder: $1.TTSOptions.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceAgentSynthesizeSpeechProtoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceAgentSynthesizeSpeechProtoRequest copyWith(
          void Function(VoiceAgentSynthesizeSpeechProtoRequest) updates) =>
      super.copyWith((message) =>
              updates(message as VoiceAgentSynthesizeSpeechProtoRequest))
          as VoiceAgentSynthesizeSpeechProtoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoiceAgentSynthesizeSpeechProtoRequest create() =>
      VoiceAgentSynthesizeSpeechProtoRequest._();
  @$core.override
  VoiceAgentSynthesizeSpeechProtoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VoiceAgentSynthesizeSpeechProtoRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          VoiceAgentSynthesizeSpeechProtoRequest>(create);
  static VoiceAgentSynthesizeSpeechProtoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get sessionId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sessionId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSessionId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSessionId() => $_clearField(2);

  @$pb.TagNumber(3)
  $1.TTSOptions get options => $_getN(2);
  @$pb.TagNumber(3)
  set options($1.TTSOptions value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasOptions() => $_has(2);
  @$pb.TagNumber(3)
  void clearOptions() => $_clearField(3);
  @$pb.TagNumber(3)
  $1.TTSOptions ensureOptions() => $_ensure(2);
}

class VoiceAgentApi {
  final $pb.RpcClient _client;

  VoiceAgentApi(this._client);

  /// Server-streaming: the agent emits VoiceEvents until the client
  /// cancels the stream or the agent reaches its terminal state.
  $async.Future<$0.VoiceEvent> stream(
          $pb.ClientContext? ctx, VoiceAgentRequest request) =>
      _client.invoke<$0.VoiceEvent>(
          ctx, 'VoiceAgent', 'Stream', request, $0.VoiceEvent());

  /// One-shot voice turn: audio blob in, transcription + assistant response
  /// + synthesized audio out. Mirrors `processVoiceTurn` ergonomic API.
  $async.Future<VoiceAgentResult> processTurn(
          $pb.ClientContext? ctx, VoiceAgentTurnRequest request) =>
      _client.invoke<VoiceAgentResult>(
          ctx, 'VoiceAgent', 'ProcessTurn', request, VoiceAgentResult());

  /// Helper-level STT transcribe path used by voice-agent sub-components.
  $async.Future<$2.STTOutput> transcribe(
          $pb.ClientContext? ctx, VoiceAgentTranscribeProtoRequest request) =>
      _client.invoke<$2.STTOutput>(
          ctx, 'VoiceAgent', 'Transcribe', request, $2.STTOutput());

  /// Helper-level TTS synthesize-speech path used by voice-agent sub-components.
  $async.Future<$1.TTSOutput> synthesizeSpeech($pb.ClientContext? ctx,
          VoiceAgentSynthesizeSpeechProtoRequest request) =>
      _client.invoke<$1.TTSOutput>(
          ctx, 'VoiceAgent', 'SynthesizeSpeech', request, $1.TTSOutput());

  /// Configure / initialize the voice-agent sub-components (STT/LLM/TTS/VAD/
  /// wake-word). Returns an initial VoiceAgentResult capturing component
  /// readiness and any initialization errors.
  $async.Future<VoiceAgentResult> configure(
          $pb.ClientContext? ctx, VoiceAgentComposeConfig request) =>
      _client.invoke<VoiceAgentResult>(
          ctx, 'VoiceAgent', 'Configure', request, VoiceAgentResult());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
