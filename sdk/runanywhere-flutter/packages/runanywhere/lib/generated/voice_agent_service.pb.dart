// This is a generated file - do not edit.
//
// Generated from voice_agent_service.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'llm_options.pb.dart' as $2;
import 'model_types.pbenum.dart' as $4;
import 'tts_options.pb.dart' as $3;
import 'vad_options.pb.dart' as $1;
import 'voice_agent_service.pbenum.dart';
import 'voice_events.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'voice_agent_service.pbenum.dart';

class VoiceAgentResult extends $pb.GeneratedMessage {
  factory VoiceAgentResult({
    $core.bool? speechDetected,
    $core.String? transcription,
    $core.String? assistantResponse,
    $core.String? thinkingContent,
    $core.List<$core.int>? synthesizedAudio,
    $0.VoiceAgentComponentStates? finalState,
  }) {
    final result = create();
    if (speechDetected != null) result.speechDetected = speechDetected;
    if (transcription != null) result.transcription = transcription;
    if (assistantResponse != null) result.assistantResponse = assistantResponse;
    if (thinkingContent != null) result.thinkingContent = thinkingContent;
    if (synthesizedAudio != null) result.synthesizedAudio = synthesizedAudio;
    if (finalState != null) result.finalState = finalState;
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

  @$pb.TagNumber(1)
  $core.bool get speechDetected => $_getBF(0);
  @$pb.TagNumber(1)
  set speechDetected($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSpeechDetected() => $_has(0);
  @$pb.TagNumber(1)
  void clearSpeechDetected() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get transcription => $_getSZ(1);
  @$pb.TagNumber(2)
  set transcription($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTranscription() => $_has(1);
  @$pb.TagNumber(2)
  void clearTranscription() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get assistantResponse => $_getSZ(2);
  @$pb.TagNumber(3)
  set assistantResponse($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAssistantResponse() => $_has(2);
  @$pb.TagNumber(3)
  void clearAssistantResponse() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get thinkingContent => $_getSZ(3);
  @$pb.TagNumber(4)
  set thinkingContent($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasThinkingContent() => $_has(3);
  @$pb.TagNumber(4)
  void clearThinkingContent() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get synthesizedAudio => $_getN(4);
  @$pb.TagNumber(5)
  set synthesizedAudio($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSynthesizedAudio() => $_has(4);
  @$pb.TagNumber(5)
  void clearSynthesizedAudio() => $_clearField(5);

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
}

/// Turn detection. Field names, units and semantics follow OpenAI Realtime
/// `session.audio.input.turn_detection`.
class TurnDetection extends $pb.GeneratedMessage {
  factory TurnDetection({
    TurnDetection_Type? type,
    $core.double? threshold,
    $core.int? silenceDurationMs,
    $core.int? prefixPaddingMs,
    $core.bool? interruptResponse,
    $core.bool? createResponse,
  }) {
    final result = create();
    if (type != null) result.type = type;
    if (threshold != null) result.threshold = threshold;
    if (silenceDurationMs != null) result.silenceDurationMs = silenceDurationMs;
    if (prefixPaddingMs != null) result.prefixPaddingMs = prefixPaddingMs;
    if (interruptResponse != null) result.interruptResponse = interruptResponse;
    if (createResponse != null) result.createResponse = createResponse;
    return result;
  }

  TurnDetection._();

  factory TurnDetection.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TurnDetection.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TurnDetection',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<TurnDetection_Type>(1, _omitFieldNames ? '' : 'type',
        enumValues: TurnDetection_Type.values)
    ..aD(2, _omitFieldNames ? '' : 'threshold', fieldType: $pb.PbFieldType.OF)
    ..aI(3, _omitFieldNames ? '' : 'silenceDurationMs')
    ..aI(4, _omitFieldNames ? '' : 'prefixPaddingMs')
    ..aOB(5, _omitFieldNames ? '' : 'interruptResponse')
    ..aOB(6, _omitFieldNames ? '' : 'createResponse')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TurnDetection clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TurnDetection copyWith(void Function(TurnDetection) updates) =>
      super.copyWith((message) => updates(message as TurnDetection))
          as TurnDetection;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TurnDetection create() => TurnDetection._();
  @$core.override
  TurnDetection createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TurnDetection getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TurnDetection>(create);
  static TurnDetection? _defaultInstance;

  @$pb.TagNumber(1)
  TurnDetection_Type get type => $_getN(0);
  @$pb.TagNumber(1)
  set type(TurnDetection_Type value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => $_clearField(1);

  /// Activation threshold, 0..1 — the same normalized scale as
  /// VADConfiguration.activation_threshold, and the value that wins on the
  /// voice-agent path when both are set. Raise it for noisy rooms.
  /// 0 means unset; commons applies 0.5.
  @$pb.TagNumber(2)
  $core.double get threshold => $_getN(1);
  @$pb.TagNumber(2)
  set threshold($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasThreshold() => $_has(1);
  @$pb.TagNumber(2)
  void clearThreshold() => $_clearField(2);

  /// Silence after speech before the turn is closed.
  /// 0 means unset; commons applies 500.
  @$pb.TagNumber(3)
  $core.int get silenceDurationMs => $_getIZ(2);
  @$pb.TagNumber(3)
  set silenceDurationMs($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSilenceDurationMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearSilenceDurationMs() => $_clearField(3);

  /// Audio retained before speech onset so the first word is not clipped.
  /// 0 means unset; commons applies 300.
  @$pb.TagNumber(4)
  $core.int get prefixPaddingMs => $_getIZ(3);
  @$pb.TagNumber(4)
  set prefixPaddingMs($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPrefixPaddingMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearPrefixPaddingMs() => $_clearField(4);

  /// Unset means true. False makes the agent finish its sentence
  /// (kiosk, scripted disclosure).
  @$pb.TagNumber(5)
  $core.bool get interruptResponse => $_getBF(4);
  @$pb.TagNumber(5)
  set interruptResponse($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasInterruptResponse() => $_has(4);
  @$pb.TagNumber(5)
  void clearInterruptResponse() => $_clearField(5);

  /// Unset means true. False means the app drives replies itself via say().
  @$pb.TagNumber(6)
  $core.bool get createResponse => $_getBF(5);
  @$pb.TagNumber(6)
  set createResponse($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCreateResponse() => $_has(5);
  @$pb.TagNumber(6)
  void clearCreateResponse() => $_clearField(6);
}

/// One-shot turn: audio in, transcription plus response plus audio out.
///
/// audio_data must be PCM signed 16-bit little-endian, mono, 16 kHz. Commons
/// rejects any other encoding, but it does NOT check or resample the sample
/// rate or the channel count — feeding anything else yields a wrong transcript
/// rather than an error.
class VoiceAgentTurnRequest extends $pb.GeneratedMessage {
  factory VoiceAgentTurnRequest({
    $core.String? requestId,
    $core.String? sessionId,
    $core.List<$core.int>? audioData,
    $core.String? language,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (sessionId != null) result.sessionId = sessionId;
    if (audioData != null) result.audioData = audioData;
    if (language != null) result.language = language;
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
    ..aOS(4, _omitFieldNames ? '' : 'language')
    ..m<$core.String, $core.String>(5, _omitFieldNames ? '' : 'metadata',
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

  /// BCP-47 STT language for this turn only. Overrides
  /// VoiceAgentComposeConfig.language. Unset means the session language, or
  /// model auto-detection when that is unset too.
  @$pb.TagNumber(4)
  $core.String get language => $_getSZ(3);
  @$pb.TagNumber(4)
  set language($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLanguage() => $_has(3);
  @$pb.TagNumber(4)
  void clearLanguage() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(4);
}

/// Streamed capture frame. Same fixed input contract as VoiceAgentTurnRequest.
class VoiceAgentAudioFrame extends $pb.GeneratedMessage {
  factory VoiceAgentAudioFrame({
    $core.List<$core.int>? audioData,
    $core.int? sampleRateHz,
    $core.int? channels,
    $4.AudioEncoding? encoding,
    $core.bool? isFinal,
  }) {
    final result = create();
    if (audioData != null) result.audioData = audioData;
    if (sampleRateHz != null) result.sampleRateHz = sampleRateHz;
    if (channels != null) result.channels = channels;
    if (encoding != null) result.encoding = encoding;
    if (isFinal != null) result.isFinal = isFinal;
    return result;
  }

  VoiceAgentAudioFrame._();

  factory VoiceAgentAudioFrame.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VoiceAgentAudioFrame.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VoiceAgentAudioFrame',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'audioData', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'sampleRateHz')
    ..aI(3, _omitFieldNames ? '' : 'channels')
    ..aE<$4.AudioEncoding>(4, _omitFieldNames ? '' : 'encoding',
        enumValues: $4.AudioEncoding.values)
    ..aOB(5, _omitFieldNames ? '' : 'isFinal')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceAgentAudioFrame clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceAgentAudioFrame copyWith(void Function(VoiceAgentAudioFrame) updates) =>
      super.copyWith((message) => updates(message as VoiceAgentAudioFrame))
          as VoiceAgentAudioFrame;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoiceAgentAudioFrame create() => VoiceAgentAudioFrame._();
  @$core.override
  VoiceAgentAudioFrame createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VoiceAgentAudioFrame getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VoiceAgentAudioFrame>(create);
  static VoiceAgentAudioFrame? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get audioData => $_getN(0);
  @$pb.TagNumber(1)
  set audioData($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAudioData() => $_has(0);
  @$pb.TagNumber(1)
  void clearAudioData() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get sampleRateHz => $_getIZ(1);
  @$pb.TagNumber(2)
  set sampleRateHz($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSampleRateHz() => $_has(1);
  @$pb.TagNumber(2)
  void clearSampleRateHz() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get channels => $_getIZ(2);
  @$pb.TagNumber(3)
  set channels($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasChannels() => $_has(2);
  @$pb.TagNumber(3)
  void clearChannels() => $_clearField(3);

  /// Commons accepts AUDIO_ENCODING_UNSPECIFIED and AUDIO_ENCODING_PCM_S16_LE
  /// and rejects every other value.
  @$pb.TagNumber(4)
  $4.AudioEncoding get encoding => $_getN(3);
  @$pb.TagNumber(4)
  set encoding($4.AudioEncoding value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasEncoding() => $_has(3);
  @$pb.TagNumber(4)
  void clearEncoding() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get isFinal => $_getBF(4);
  @$pb.TagNumber(5)
  set isFinal($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasIsFinal() => $_has(4);
  @$pb.TagNumber(5)
  void clearIsFinal() => $_clearField(5);
}

/// Each component takes a path or an id; commons resolves the id through the
/// model registry.
class VoiceAgentComposeConfig extends $pb.GeneratedMessage {
  factory VoiceAgentComposeConfig({
    $core.String? sttModelPath,
    $core.String? sttModelId,
    $core.String? llmModelPath,
    $core.String? llmModelId,
    $core.String? ttsVoicePath,
    $core.String? ttsVoiceId,
    $1.VADConfiguration? vadConfig,
    $2.LLMGenerationOptions? llmGeneration,
    $core.String? instructions,
    TurnDetection? turnDetection,
    $core.String? language,
  }) {
    final result = create();
    if (sttModelPath != null) result.sttModelPath = sttModelPath;
    if (sttModelId != null) result.sttModelId = sttModelId;
    if (llmModelPath != null) result.llmModelPath = llmModelPath;
    if (llmModelId != null) result.llmModelId = llmModelId;
    if (ttsVoicePath != null) result.ttsVoicePath = ttsVoicePath;
    if (ttsVoiceId != null) result.ttsVoiceId = ttsVoiceId;
    if (vadConfig != null) result.vadConfig = vadConfig;
    if (llmGeneration != null) result.llmGeneration = llmGeneration;
    if (instructions != null) result.instructions = instructions;
    if (turnDetection != null) result.turnDetection = turnDetection;
    if (language != null) result.language = language;
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
    ..aOS(3, _omitFieldNames ? '' : 'llmModelPath')
    ..aOS(4, _omitFieldNames ? '' : 'llmModelId')
    ..aOS(5, _omitFieldNames ? '' : 'ttsVoicePath')
    ..aOS(6, _omitFieldNames ? '' : 'ttsVoiceId')
    ..aOM<$1.VADConfiguration>(7, _omitFieldNames ? '' : 'vadConfig',
        subBuilder: $1.VADConfiguration.create)
    ..aOM<$2.LLMGenerationOptions>(8, _omitFieldNames ? '' : 'llmGeneration',
        subBuilder: $2.LLMGenerationOptions.create)
    ..aOS(9, _omitFieldNames ? '' : 'instructions')
    ..aOM<TurnDetection>(10, _omitFieldNames ? '' : 'turnDetection',
        subBuilder: TurnDetection.create)
    ..aOS(11, _omitFieldNames ? '' : 'language')
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

  /// Normal choice is the id (resolved via the model registry); path is the
  /// escape hatch for an artifact you staged yourself.
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
  $core.String get llmModelPath => $_getSZ(2);
  @$pb.TagNumber(3)
  set llmModelPath($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLlmModelPath() => $_has(2);
  @$pb.TagNumber(3)
  void clearLlmModelPath() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get llmModelId => $_getSZ(3);
  @$pb.TagNumber(4)
  set llmModelId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLlmModelId() => $_has(3);
  @$pb.TagNumber(4)
  void clearLlmModelId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get ttsVoicePath => $_getSZ(4);
  @$pb.TagNumber(5)
  set ttsVoicePath($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTtsVoicePath() => $_has(4);
  @$pb.TagNumber(5)
  void clearTtsVoicePath() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get ttsVoiceId => $_getSZ(5);
  @$pb.TagNumber(6)
  set ttsVoiceId($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTtsVoiceId() => $_has(5);
  @$pb.TagNumber(6)
  void clearTtsVoiceId() => $_clearField(6);

  @$pb.TagNumber(7)
  $1.VADConfiguration get vadConfig => $_getN(6);
  @$pb.TagNumber(7)
  set vadConfig($1.VADConfiguration value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasVadConfig() => $_has(6);
  @$pb.TagNumber(7)
  void clearVadConfig() => $_clearField(7);
  @$pb.TagNumber(7)
  $1.VADConfiguration ensureVadConfig() => $_ensure(6);

  @$pb.TagNumber(8)
  $2.LLMGenerationOptions get llmGeneration => $_getN(7);
  @$pb.TagNumber(8)
  set llmGeneration($2.LLMGenerationOptions value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasLlmGeneration() => $_has(7);
  @$pb.TagNumber(8)
  void clearLlmGeneration() => $_clearField(8);
  @$pb.TagNumber(8)
  $2.LLMGenerationOptions ensureLlmGeneration() => $_ensure(7);

  /// System prompt for the agent. Governs persona AND spoken delivery
  /// ("talk quickly", "sound warm"), not just content. Same name and role as
  /// OpenAI Realtime `session.instructions`. Unset uses the commons voice
  /// default (short, spoken, no markdown).
  ///
  /// This is the only system prompt the voice path reads:
  /// llm_generation.system_prompt is IGNORED here.
  @$pb.TagNumber(9)
  $core.String get instructions => $_getSZ(8);
  @$pb.TagNumber(9)
  set instructions($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasInstructions() => $_has(8);
  @$pb.TagNumber(9)
  void clearInstructions() => $_clearField(9);

  @$pb.TagNumber(10)
  TurnDetection get turnDetection => $_getN(9);
  @$pb.TagNumber(10)
  set turnDetection(TurnDetection value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasTurnDetection() => $_has(9);
  @$pb.TagNumber(10)
  void clearTurnDetection() => $_clearField(10);
  @$pb.TagNumber(10)
  TurnDetection ensureTurnDetection() => $_ensure(9);

  /// BCP-47 STT language for the whole session. One spelling across this
  /// domain and stt_options.proto. Unset means the model auto-detects.
  /// Per-turn override: VoiceAgentTurnRequest.language.
  @$pb.TagNumber(11)
  $core.String get language => $_getSZ(10);
  @$pb.TagNumber(11)
  set language($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasLanguage() => $_has(10);
  @$pb.TagNumber(11)
  void clearLanguage() => $_clearField(11);
}

class VoiceAgentTranscribeProtoRequest extends $pb.GeneratedMessage {
  factory VoiceAgentTranscribeProtoRequest({
    $core.List<$core.int>? audioData,
    $core.String? sessionId,
    $core.String? language,
  }) {
    final result = create();
    if (audioData != null) result.audioData = audioData;
    if (sessionId != null) result.sessionId = sessionId;
    if (language != null) result.language = language;
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
    ..aOS(3, _omitFieldNames ? '' : 'language')
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

  /// BCP-47. Empty means auto-detect.
  @$pb.TagNumber(3)
  $core.String get language => $_getSZ(2);
  @$pb.TagNumber(3)
  set language($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLanguage() => $_has(2);
  @$pb.TagNumber(3)
  void clearLanguage() => $_clearField(3);
}

class VoiceAgentSynthesizeSpeechProtoRequest extends $pb.GeneratedMessage {
  factory VoiceAgentSynthesizeSpeechProtoRequest({
    $core.String? text,
    $core.String? sessionId,
    $3.TTSOptions? options,
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
    ..aOM<$3.TTSOptions>(3, _omitFieldNames ? '' : 'options',
        subBuilder: $3.TTSOptions.create)
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
  $3.TTSOptions get options => $_getN(2);
  @$pb.TagNumber(3)
  set options($3.TTSOptions value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasOptions() => $_has(2);
  @$pb.TagNumber(3)
  void clearOptions() => $_clearField(3);
  @$pb.TagNumber(3)
  $3.TTSOptions ensureOptions() => $_ensure(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
