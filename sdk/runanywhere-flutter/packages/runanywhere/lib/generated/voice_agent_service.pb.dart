///
//  Generated code. Do not modify.
//  source: voice_agent_service.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'voice_events.pb.dart' as $0;

class VoiceAgentRequest extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'VoiceAgentRequest', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'eventFilter')
    ..hasRequiredFields = false
  ;

  VoiceAgentRequest._() : super();
  factory VoiceAgentRequest({
    $core.String? eventFilter,
  }) {
    final _result = create();
    if (eventFilter != null) {
      _result.eventFilter = eventFilter;
    }
    return _result;
  }
  factory VoiceAgentRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VoiceAgentRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VoiceAgentRequest clone() => VoiceAgentRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VoiceAgentRequest copyWith(void Function(VoiceAgentRequest) updates) => super.copyWith((message) => updates(message as VoiceAgentRequest)) as VoiceAgentRequest; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static VoiceAgentRequest create() => VoiceAgentRequest._();
  VoiceAgentRequest createEmptyInstance() => create();
  static $pb.PbList<VoiceAgentRequest> createRepeated() => $pb.PbList<VoiceAgentRequest>();
  @$core.pragma('dart2js:noInline')
  static VoiceAgentRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VoiceAgentRequest>(create);
  static VoiceAgentRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get eventFilter => $_getSZ(0);
  @$pb.TagNumber(1)
  set eventFilter($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEventFilter() => $_has(0);
  @$pb.TagNumber(1)
  void clearEventFilter() => clearField(1);
}

class VoiceAgentResult extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'VoiceAgentResult', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'speechDetected')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'transcription')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'assistantResponse')
    ..aOS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'thinkingContent')
    ..a<$core.List<$core.int>>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'synthesizedAudio', $pb.PbFieldType.OY)
    ..aOM<$0.VoiceAgentComponentStates>(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'finalState', subBuilder: $0.VoiceAgentComponentStates.create)
    ..hasRequiredFields = false
  ;

  VoiceAgentResult._() : super();
  factory VoiceAgentResult({
    $core.bool? speechDetected,
    $core.String? transcription,
    $core.String? assistantResponse,
    $core.String? thinkingContent,
    $core.List<$core.int>? synthesizedAudio,
    $0.VoiceAgentComponentStates? finalState,
  }) {
    final _result = create();
    if (speechDetected != null) {
      _result.speechDetected = speechDetected;
    }
    if (transcription != null) {
      _result.transcription = transcription;
    }
    if (assistantResponse != null) {
      _result.assistantResponse = assistantResponse;
    }
    if (thinkingContent != null) {
      _result.thinkingContent = thinkingContent;
    }
    if (synthesizedAudio != null) {
      _result.synthesizedAudio = synthesizedAudio;
    }
    if (finalState != null) {
      _result.finalState = finalState;
    }
    return _result;
  }
  factory VoiceAgentResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VoiceAgentResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VoiceAgentResult clone() => VoiceAgentResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VoiceAgentResult copyWith(void Function(VoiceAgentResult) updates) => super.copyWith((message) => updates(message as VoiceAgentResult)) as VoiceAgentResult; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static VoiceAgentResult create() => VoiceAgentResult._();
  VoiceAgentResult createEmptyInstance() => create();
  static $pb.PbList<VoiceAgentResult> createRepeated() => $pb.PbList<VoiceAgentResult>();
  @$core.pragma('dart2js:noInline')
  static VoiceAgentResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VoiceAgentResult>(create);
  static VoiceAgentResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get speechDetected => $_getBF(0);
  @$pb.TagNumber(1)
  set speechDetected($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSpeechDetected() => $_has(0);
  @$pb.TagNumber(1)
  void clearSpeechDetected() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get transcription => $_getSZ(1);
  @$pb.TagNumber(2)
  set transcription($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTranscription() => $_has(1);
  @$pb.TagNumber(2)
  void clearTranscription() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get assistantResponse => $_getSZ(2);
  @$pb.TagNumber(3)
  set assistantResponse($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAssistantResponse() => $_has(2);
  @$pb.TagNumber(3)
  void clearAssistantResponse() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get thinkingContent => $_getSZ(3);
  @$pb.TagNumber(4)
  set thinkingContent($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasThinkingContent() => $_has(3);
  @$pb.TagNumber(4)
  void clearThinkingContent() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get synthesizedAudio => $_getN(4);
  @$pb.TagNumber(5)
  set synthesizedAudio($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSynthesizedAudio() => $_has(4);
  @$pb.TagNumber(5)
  void clearSynthesizedAudio() => clearField(5);

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
}

class VoiceSessionConfig extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'VoiceSessionConfig', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.int>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'silenceDurationMs', $pb.PbFieldType.O3)
    ..a<$core.double>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'speechThreshold', $pb.PbFieldType.OF)
    ..aOB(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'autoPlayTts')
    ..aOB(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'continuousMode')
    ..aOB(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'thinkingModeEnabled')
    ..hasRequiredFields = false
  ;

  VoiceSessionConfig._() : super();
  factory VoiceSessionConfig({
    $core.int? silenceDurationMs,
    $core.double? speechThreshold,
    $core.bool? autoPlayTts,
    $core.bool? continuousMode,
    $core.bool? thinkingModeEnabled,
  }) {
    final _result = create();
    if (silenceDurationMs != null) {
      _result.silenceDurationMs = silenceDurationMs;
    }
    if (speechThreshold != null) {
      _result.speechThreshold = speechThreshold;
    }
    if (autoPlayTts != null) {
      _result.autoPlayTts = autoPlayTts;
    }
    if (continuousMode != null) {
      _result.continuousMode = continuousMode;
    }
    if (thinkingModeEnabled != null) {
      _result.thinkingModeEnabled = thinkingModeEnabled;
    }
    return _result;
  }
  factory VoiceSessionConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VoiceSessionConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VoiceSessionConfig clone() => VoiceSessionConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VoiceSessionConfig copyWith(void Function(VoiceSessionConfig) updates) => super.copyWith((message) => updates(message as VoiceSessionConfig)) as VoiceSessionConfig; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static VoiceSessionConfig create() => VoiceSessionConfig._();
  VoiceSessionConfig createEmptyInstance() => create();
  static $pb.PbList<VoiceSessionConfig> createRepeated() => $pb.PbList<VoiceSessionConfig>();
  @$core.pragma('dart2js:noInline')
  static VoiceSessionConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VoiceSessionConfig>(create);
  static VoiceSessionConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get silenceDurationMs => $_getIZ(0);
  @$pb.TagNumber(1)
  set silenceDurationMs($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSilenceDurationMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearSilenceDurationMs() => clearField(1);

  @$pb.TagNumber(2)
  $core.double get speechThreshold => $_getN(1);
  @$pb.TagNumber(2)
  set speechThreshold($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSpeechThreshold() => $_has(1);
  @$pb.TagNumber(2)
  void clearSpeechThreshold() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get autoPlayTts => $_getBF(2);
  @$pb.TagNumber(3)
  set autoPlayTts($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAutoPlayTts() => $_has(2);
  @$pb.TagNumber(3)
  void clearAutoPlayTts() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get continuousMode => $_getBF(3);
  @$pb.TagNumber(4)
  set continuousMode($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasContinuousMode() => $_has(3);
  @$pb.TagNumber(4)
  void clearContinuousMode() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get thinkingModeEnabled => $_getBF(4);
  @$pb.TagNumber(5)
  set thinkingModeEnabled($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasThinkingModeEnabled() => $_has(4);
  @$pb.TagNumber(5)
  void clearThinkingModeEnabled() => clearField(5);
}

class VoiceAgentComposeConfig extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'VoiceAgentComposeConfig', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sttModelPath')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sttModelId')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sttModelName')
    ..aOS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'llmModelPath')
    ..aOS(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'llmModelId')
    ..aOS(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'llmModelName')
    ..aOS(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'ttsVoicePath')
    ..aOS(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'ttsVoiceId')
    ..aOS(9, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'ttsVoiceName')
    ..a<$core.int>(10, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'vadSampleRate', $pb.PbFieldType.O3)
    ..a<$core.double>(11, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'vadFrameLength', $pb.PbFieldType.OF)
    ..a<$core.double>(12, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'vadEnergyThreshold', $pb.PbFieldType.OF)
    ..aOB(13, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'wakewordEnabled')
    ..aOS(14, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'wakewordModelPath')
    ..aOS(15, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'wakewordModelId')
    ..aOS(16, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'wakewordPhrase')
    ..a<$core.double>(17, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'wakewordThreshold', $pb.PbFieldType.OF)
    ..aOS(18, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'wakewordEmbeddingModelPath')
    ..aOS(19, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'wakewordVadModelPath')
    ..aOM<VoiceSessionConfig>(20, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sessionConfig', subBuilder: VoiceSessionConfig.create)
    ..hasRequiredFields = false
  ;

  VoiceAgentComposeConfig._() : super();
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
  }) {
    final _result = create();
    if (sttModelPath != null) {
      _result.sttModelPath = sttModelPath;
    }
    if (sttModelId != null) {
      _result.sttModelId = sttModelId;
    }
    if (sttModelName != null) {
      _result.sttModelName = sttModelName;
    }
    if (llmModelPath != null) {
      _result.llmModelPath = llmModelPath;
    }
    if (llmModelId != null) {
      _result.llmModelId = llmModelId;
    }
    if (llmModelName != null) {
      _result.llmModelName = llmModelName;
    }
    if (ttsVoicePath != null) {
      _result.ttsVoicePath = ttsVoicePath;
    }
    if (ttsVoiceId != null) {
      _result.ttsVoiceId = ttsVoiceId;
    }
    if (ttsVoiceName != null) {
      _result.ttsVoiceName = ttsVoiceName;
    }
    if (vadSampleRate != null) {
      _result.vadSampleRate = vadSampleRate;
    }
    if (vadFrameLength != null) {
      _result.vadFrameLength = vadFrameLength;
    }
    if (vadEnergyThreshold != null) {
      _result.vadEnergyThreshold = vadEnergyThreshold;
    }
    if (wakewordEnabled != null) {
      _result.wakewordEnabled = wakewordEnabled;
    }
    if (wakewordModelPath != null) {
      _result.wakewordModelPath = wakewordModelPath;
    }
    if (wakewordModelId != null) {
      _result.wakewordModelId = wakewordModelId;
    }
    if (wakewordPhrase != null) {
      _result.wakewordPhrase = wakewordPhrase;
    }
    if (wakewordThreshold != null) {
      _result.wakewordThreshold = wakewordThreshold;
    }
    if (wakewordEmbeddingModelPath != null) {
      _result.wakewordEmbeddingModelPath = wakewordEmbeddingModelPath;
    }
    if (wakewordVadModelPath != null) {
      _result.wakewordVadModelPath = wakewordVadModelPath;
    }
    if (sessionConfig != null) {
      _result.sessionConfig = sessionConfig;
    }
    return _result;
  }
  factory VoiceAgentComposeConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VoiceAgentComposeConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VoiceAgentComposeConfig clone() => VoiceAgentComposeConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VoiceAgentComposeConfig copyWith(void Function(VoiceAgentComposeConfig) updates) => super.copyWith((message) => updates(message as VoiceAgentComposeConfig)) as VoiceAgentComposeConfig; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static VoiceAgentComposeConfig create() => VoiceAgentComposeConfig._();
  VoiceAgentComposeConfig createEmptyInstance() => create();
  static $pb.PbList<VoiceAgentComposeConfig> createRepeated() => $pb.PbList<VoiceAgentComposeConfig>();
  @$core.pragma('dart2js:noInline')
  static VoiceAgentComposeConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VoiceAgentComposeConfig>(create);
  static VoiceAgentComposeConfig? _defaultInstance;

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
}

class VoiceAgentApi {
  $pb.RpcClient _client;
  VoiceAgentApi(this._client);

  $async.Future<$0.VoiceEvent> stream($pb.ClientContext? ctx, VoiceAgentRequest request) {
    var emptyResponse = $0.VoiceEvent();
    return _client.invoke<$0.VoiceEvent>(ctx, 'VoiceAgent', 'Stream', request, emptyResponse);
  }
}

