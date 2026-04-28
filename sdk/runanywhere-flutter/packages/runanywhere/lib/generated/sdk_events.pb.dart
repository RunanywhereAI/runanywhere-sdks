///
//  Generated code. Do not modify.
//  source: sdk_events.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'voice_events.pb.dart' as $0;

import 'sdk_events.pbenum.dart';

export 'sdk_events.pbenum.dart';

class InitializationEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'InitializationEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<InitializationStage>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'stage', $pb.PbFieldType.OE, defaultOrMaker: InitializationStage.INITIALIZATION_STAGE_UNSPECIFIED, valueOf: InitializationStage.valueOf, enumValues: InitializationStage.values)
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'source')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'error')
    ..aOS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'version')
    ..hasRequiredFields = false
  ;

  InitializationEvent._() : super();
  factory InitializationEvent({
    InitializationStage? stage,
    $core.String? source,
    $core.String? error,
    $core.String? version,
  }) {
    final _result = create();
    if (stage != null) {
      _result.stage = stage;
    }
    if (source != null) {
      _result.source = source;
    }
    if (error != null) {
      _result.error = error;
    }
    if (version != null) {
      _result.version = version;
    }
    return _result;
  }
  factory InitializationEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory InitializationEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  InitializationEvent clone() => InitializationEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  InitializationEvent copyWith(void Function(InitializationEvent) updates) => super.copyWith((message) => updates(message as InitializationEvent)) as InitializationEvent; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static InitializationEvent create() => InitializationEvent._();
  InitializationEvent createEmptyInstance() => create();
  static $pb.PbList<InitializationEvent> createRepeated() => $pb.PbList<InitializationEvent>();
  @$core.pragma('dart2js:noInline')
  static InitializationEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<InitializationEvent>(create);
  static InitializationEvent? _defaultInstance;

  @$pb.TagNumber(1)
  InitializationStage get stage => $_getN(0);
  @$pb.TagNumber(1)
  set stage(InitializationStage v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasStage() => $_has(0);
  @$pb.TagNumber(1)
  void clearStage() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get source => $_getSZ(1);
  @$pb.TagNumber(2)
  set source($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSource() => $_has(1);
  @$pb.TagNumber(2)
  void clearSource() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get error => $_getSZ(2);
  @$pb.TagNumber(3)
  set error($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(3)
  void clearError() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get version => $_getSZ(3);
  @$pb.TagNumber(4)
  set version($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasVersion() => $_has(3);
  @$pb.TagNumber(4)
  void clearVersion() => clearField(4);
}

class ConfigurationEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ConfigurationEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<ConfigurationEventKind>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: ConfigurationEventKind.CONFIGURATION_EVENT_KIND_UNSPECIFIED, valueOf: ConfigurationEventKind.valueOf, enumValues: ConfigurationEventKind.values)
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'source')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'error')
    ..pPS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'changedKeys')
    ..aOS(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'settingsJson')
    ..aOS(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'routingPolicy')
    ..aOS(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'privacyMode')
    ..aOB(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'analyticsEnabled')
    ..aOS(9, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'oldValueJson')
    ..aOS(10, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'newValueJson')
    ..hasRequiredFields = false
  ;

  ConfigurationEvent._() : super();
  factory ConfigurationEvent({
    ConfigurationEventKind? kind,
    $core.String? source,
    $core.String? error,
    $core.Iterable<$core.String>? changedKeys,
    $core.String? settingsJson,
    $core.String? routingPolicy,
    $core.String? privacyMode,
    $core.bool? analyticsEnabled,
    $core.String? oldValueJson,
    $core.String? newValueJson,
  }) {
    final _result = create();
    if (kind != null) {
      _result.kind = kind;
    }
    if (source != null) {
      _result.source = source;
    }
    if (error != null) {
      _result.error = error;
    }
    if (changedKeys != null) {
      _result.changedKeys.addAll(changedKeys);
    }
    if (settingsJson != null) {
      _result.settingsJson = settingsJson;
    }
    if (routingPolicy != null) {
      _result.routingPolicy = routingPolicy;
    }
    if (privacyMode != null) {
      _result.privacyMode = privacyMode;
    }
    if (analyticsEnabled != null) {
      _result.analyticsEnabled = analyticsEnabled;
    }
    if (oldValueJson != null) {
      _result.oldValueJson = oldValueJson;
    }
    if (newValueJson != null) {
      _result.newValueJson = newValueJson;
    }
    return _result;
  }
  factory ConfigurationEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ConfigurationEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ConfigurationEvent clone() => ConfigurationEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ConfigurationEvent copyWith(void Function(ConfigurationEvent) updates) => super.copyWith((message) => updates(message as ConfigurationEvent)) as ConfigurationEvent; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ConfigurationEvent create() => ConfigurationEvent._();
  ConfigurationEvent createEmptyInstance() => create();
  static $pb.PbList<ConfigurationEvent> createRepeated() => $pb.PbList<ConfigurationEvent>();
  @$core.pragma('dart2js:noInline')
  static ConfigurationEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ConfigurationEvent>(create);
  static ConfigurationEvent? _defaultInstance;

  @$pb.TagNumber(1)
  ConfigurationEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(ConfigurationEventKind v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get source => $_getSZ(1);
  @$pb.TagNumber(2)
  set source($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSource() => $_has(1);
  @$pb.TagNumber(2)
  void clearSource() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get error => $_getSZ(2);
  @$pb.TagNumber(3)
  set error($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(3)
  void clearError() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.String> get changedKeys => $_getList(3);

  @$pb.TagNumber(5)
  $core.String get settingsJson => $_getSZ(4);
  @$pb.TagNumber(5)
  set settingsJson($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSettingsJson() => $_has(4);
  @$pb.TagNumber(5)
  void clearSettingsJson() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get routingPolicy => $_getSZ(5);
  @$pb.TagNumber(6)
  set routingPolicy($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasRoutingPolicy() => $_has(5);
  @$pb.TagNumber(6)
  void clearRoutingPolicy() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get privacyMode => $_getSZ(6);
  @$pb.TagNumber(7)
  set privacyMode($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasPrivacyMode() => $_has(6);
  @$pb.TagNumber(7)
  void clearPrivacyMode() => clearField(7);

  @$pb.TagNumber(8)
  $core.bool get analyticsEnabled => $_getBF(7);
  @$pb.TagNumber(8)
  set analyticsEnabled($core.bool v) { $_setBool(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasAnalyticsEnabled() => $_has(7);
  @$pb.TagNumber(8)
  void clearAnalyticsEnabled() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get oldValueJson => $_getSZ(8);
  @$pb.TagNumber(9)
  set oldValueJson($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasOldValueJson() => $_has(8);
  @$pb.TagNumber(9)
  void clearOldValueJson() => clearField(9);

  @$pb.TagNumber(10)
  $core.String get newValueJson => $_getSZ(9);
  @$pb.TagNumber(10)
  set newValueJson($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasNewValueJson() => $_has(9);
  @$pb.TagNumber(10)
  void clearNewValueJson() => clearField(10);
}

class GenerationEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'GenerationEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<GenerationEventKind>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: GenerationEventKind.GENERATION_EVENT_KIND_UNSPECIFIED, valueOf: GenerationEventKind.valueOf, enumValues: GenerationEventKind.values)
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sessionId')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'prompt')
    ..aOS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'token')
    ..aOS(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'streamingText')
    ..a<$core.int>(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'tokensCount', $pb.PbFieldType.O3)
    ..aOS(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'response')
    ..a<$core.int>(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'tokensUsed', $pb.PbFieldType.O3)
    ..aInt64(9, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'latencyMs')
    ..aInt64(10, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'firstTokenLatencyMs')
    ..aOS(11, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'error')
    ..aOS(12, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'modelId')
    ..a<$core.double>(13, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'costAmount', $pb.PbFieldType.OD)
    ..a<$core.double>(14, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'costSavedAmount', $pb.PbFieldType.OD)
    ..aOS(15, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'routingTarget')
    ..aOS(16, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'routingReason')
    ..hasRequiredFields = false
  ;

  GenerationEvent._() : super();
  factory GenerationEvent({
    GenerationEventKind? kind,
    $core.String? sessionId,
    $core.String? prompt,
    $core.String? token,
    $core.String? streamingText,
    $core.int? tokensCount,
    $core.String? response,
    $core.int? tokensUsed,
    $fixnum.Int64? latencyMs,
    $fixnum.Int64? firstTokenLatencyMs,
    $core.String? error,
    $core.String? modelId,
    $core.double? costAmount,
    $core.double? costSavedAmount,
    $core.String? routingTarget,
    $core.String? routingReason,
  }) {
    final _result = create();
    if (kind != null) {
      _result.kind = kind;
    }
    if (sessionId != null) {
      _result.sessionId = sessionId;
    }
    if (prompt != null) {
      _result.prompt = prompt;
    }
    if (token != null) {
      _result.token = token;
    }
    if (streamingText != null) {
      _result.streamingText = streamingText;
    }
    if (tokensCount != null) {
      _result.tokensCount = tokensCount;
    }
    if (response != null) {
      _result.response = response;
    }
    if (tokensUsed != null) {
      _result.tokensUsed = tokensUsed;
    }
    if (latencyMs != null) {
      _result.latencyMs = latencyMs;
    }
    if (firstTokenLatencyMs != null) {
      _result.firstTokenLatencyMs = firstTokenLatencyMs;
    }
    if (error != null) {
      _result.error = error;
    }
    if (modelId != null) {
      _result.modelId = modelId;
    }
    if (costAmount != null) {
      _result.costAmount = costAmount;
    }
    if (costSavedAmount != null) {
      _result.costSavedAmount = costSavedAmount;
    }
    if (routingTarget != null) {
      _result.routingTarget = routingTarget;
    }
    if (routingReason != null) {
      _result.routingReason = routingReason;
    }
    return _result;
  }
  factory GenerationEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GenerationEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GenerationEvent clone() => GenerationEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GenerationEvent copyWith(void Function(GenerationEvent) updates) => super.copyWith((message) => updates(message as GenerationEvent)) as GenerationEvent; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static GenerationEvent create() => GenerationEvent._();
  GenerationEvent createEmptyInstance() => create();
  static $pb.PbList<GenerationEvent> createRepeated() => $pb.PbList<GenerationEvent>();
  @$core.pragma('dart2js:noInline')
  static GenerationEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GenerationEvent>(create);
  static GenerationEvent? _defaultInstance;

  @$pb.TagNumber(1)
  GenerationEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(GenerationEventKind v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get sessionId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sessionId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSessionId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSessionId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get prompt => $_getSZ(2);
  @$pb.TagNumber(3)
  set prompt($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPrompt() => $_has(2);
  @$pb.TagNumber(3)
  void clearPrompt() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get token => $_getSZ(3);
  @$pb.TagNumber(4)
  set token($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasToken() => $_has(3);
  @$pb.TagNumber(4)
  void clearToken() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get streamingText => $_getSZ(4);
  @$pb.TagNumber(5)
  set streamingText($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasStreamingText() => $_has(4);
  @$pb.TagNumber(5)
  void clearStreamingText() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get tokensCount => $_getIZ(5);
  @$pb.TagNumber(6)
  set tokensCount($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTokensCount() => $_has(5);
  @$pb.TagNumber(6)
  void clearTokensCount() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get response => $_getSZ(6);
  @$pb.TagNumber(7)
  set response($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasResponse() => $_has(6);
  @$pb.TagNumber(7)
  void clearResponse() => clearField(7);

  @$pb.TagNumber(8)
  $core.int get tokensUsed => $_getIZ(7);
  @$pb.TagNumber(8)
  set tokensUsed($core.int v) { $_setSignedInt32(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasTokensUsed() => $_has(7);
  @$pb.TagNumber(8)
  void clearTokensUsed() => clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get latencyMs => $_getI64(8);
  @$pb.TagNumber(9)
  set latencyMs($fixnum.Int64 v) { $_setInt64(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasLatencyMs() => $_has(8);
  @$pb.TagNumber(9)
  void clearLatencyMs() => clearField(9);

  @$pb.TagNumber(10)
  $fixnum.Int64 get firstTokenLatencyMs => $_getI64(9);
  @$pb.TagNumber(10)
  set firstTokenLatencyMs($fixnum.Int64 v) { $_setInt64(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasFirstTokenLatencyMs() => $_has(9);
  @$pb.TagNumber(10)
  void clearFirstTokenLatencyMs() => clearField(10);

  @$pb.TagNumber(11)
  $core.String get error => $_getSZ(10);
  @$pb.TagNumber(11)
  set error($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasError() => $_has(10);
  @$pb.TagNumber(11)
  void clearError() => clearField(11);

  @$pb.TagNumber(12)
  $core.String get modelId => $_getSZ(11);
  @$pb.TagNumber(12)
  set modelId($core.String v) { $_setString(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasModelId() => $_has(11);
  @$pb.TagNumber(12)
  void clearModelId() => clearField(12);

  @$pb.TagNumber(13)
  $core.double get costAmount => $_getN(12);
  @$pb.TagNumber(13)
  set costAmount($core.double v) { $_setDouble(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasCostAmount() => $_has(12);
  @$pb.TagNumber(13)
  void clearCostAmount() => clearField(13);

  @$pb.TagNumber(14)
  $core.double get costSavedAmount => $_getN(13);
  @$pb.TagNumber(14)
  set costSavedAmount($core.double v) { $_setDouble(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasCostSavedAmount() => $_has(13);
  @$pb.TagNumber(14)
  void clearCostSavedAmount() => clearField(14);

  @$pb.TagNumber(15)
  $core.String get routingTarget => $_getSZ(14);
  @$pb.TagNumber(15)
  set routingTarget($core.String v) { $_setString(14, v); }
  @$pb.TagNumber(15)
  $core.bool hasRoutingTarget() => $_has(14);
  @$pb.TagNumber(15)
  void clearRoutingTarget() => clearField(15);

  @$pb.TagNumber(16)
  $core.String get routingReason => $_getSZ(15);
  @$pb.TagNumber(16)
  set routingReason($core.String v) { $_setString(15, v); }
  @$pb.TagNumber(16)
  $core.bool hasRoutingReason() => $_has(15);
  @$pb.TagNumber(16)
  void clearRoutingReason() => clearField(16);
}

class ModelEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ModelEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<ModelEventKind>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: ModelEventKind.MODEL_EVENT_KIND_UNSPECIFIED, valueOf: ModelEventKind.valueOf, enumValues: ModelEventKind.values)
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'modelId')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'taskId')
    ..a<$core.double>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'progress', $pb.PbFieldType.OF)
    ..aInt64(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'bytesDownloaded')
    ..aInt64(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'totalBytes')
    ..aOS(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'downloadState')
    ..aOS(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'localPath')
    ..aOS(9, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'error')
    ..a<$core.int>(10, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'modelCount', $pb.PbFieldType.O3)
    ..aOS(11, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'customModelName')
    ..aOS(12, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'customModelUrl')
    ..hasRequiredFields = false
  ;

  ModelEvent._() : super();
  factory ModelEvent({
    ModelEventKind? kind,
    $core.String? modelId,
    $core.String? taskId,
    $core.double? progress,
    $fixnum.Int64? bytesDownloaded,
    $fixnum.Int64? totalBytes,
    $core.String? downloadState,
    $core.String? localPath,
    $core.String? error,
    $core.int? modelCount,
    $core.String? customModelName,
    $core.String? customModelUrl,
  }) {
    final _result = create();
    if (kind != null) {
      _result.kind = kind;
    }
    if (modelId != null) {
      _result.modelId = modelId;
    }
    if (taskId != null) {
      _result.taskId = taskId;
    }
    if (progress != null) {
      _result.progress = progress;
    }
    if (bytesDownloaded != null) {
      _result.bytesDownloaded = bytesDownloaded;
    }
    if (totalBytes != null) {
      _result.totalBytes = totalBytes;
    }
    if (downloadState != null) {
      _result.downloadState = downloadState;
    }
    if (localPath != null) {
      _result.localPath = localPath;
    }
    if (error != null) {
      _result.error = error;
    }
    if (modelCount != null) {
      _result.modelCount = modelCount;
    }
    if (customModelName != null) {
      _result.customModelName = customModelName;
    }
    if (customModelUrl != null) {
      _result.customModelUrl = customModelUrl;
    }
    return _result;
  }
  factory ModelEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelEvent clone() => ModelEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelEvent copyWith(void Function(ModelEvent) updates) => super.copyWith((message) => updates(message as ModelEvent)) as ModelEvent; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ModelEvent create() => ModelEvent._();
  ModelEvent createEmptyInstance() => create();
  static $pb.PbList<ModelEvent> createRepeated() => $pb.PbList<ModelEvent>();
  @$core.pragma('dart2js:noInline')
  static ModelEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelEvent>(create);
  static ModelEvent? _defaultInstance;

  @$pb.TagNumber(1)
  ModelEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(ModelEventKind v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get taskId => $_getSZ(2);
  @$pb.TagNumber(3)
  set taskId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTaskId() => $_has(2);
  @$pb.TagNumber(3)
  void clearTaskId() => clearField(3);

  @$pb.TagNumber(4)
  $core.double get progress => $_getN(3);
  @$pb.TagNumber(4)
  set progress($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasProgress() => $_has(3);
  @$pb.TagNumber(4)
  void clearProgress() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get bytesDownloaded => $_getI64(4);
  @$pb.TagNumber(5)
  set bytesDownloaded($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasBytesDownloaded() => $_has(4);
  @$pb.TagNumber(5)
  void clearBytesDownloaded() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get totalBytes => $_getI64(5);
  @$pb.TagNumber(6)
  set totalBytes($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTotalBytes() => $_has(5);
  @$pb.TagNumber(6)
  void clearTotalBytes() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get downloadState => $_getSZ(6);
  @$pb.TagNumber(7)
  set downloadState($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasDownloadState() => $_has(6);
  @$pb.TagNumber(7)
  void clearDownloadState() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get localPath => $_getSZ(7);
  @$pb.TagNumber(8)
  set localPath($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasLocalPath() => $_has(7);
  @$pb.TagNumber(8)
  void clearLocalPath() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get error => $_getSZ(8);
  @$pb.TagNumber(9)
  set error($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasError() => $_has(8);
  @$pb.TagNumber(9)
  void clearError() => clearField(9);

  @$pb.TagNumber(10)
  $core.int get modelCount => $_getIZ(9);
  @$pb.TagNumber(10)
  set modelCount($core.int v) { $_setSignedInt32(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasModelCount() => $_has(9);
  @$pb.TagNumber(10)
  void clearModelCount() => clearField(10);

  @$pb.TagNumber(11)
  $core.String get customModelName => $_getSZ(10);
  @$pb.TagNumber(11)
  set customModelName($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasCustomModelName() => $_has(10);
  @$pb.TagNumber(11)
  void clearCustomModelName() => clearField(11);

  @$pb.TagNumber(12)
  $core.String get customModelUrl => $_getSZ(11);
  @$pb.TagNumber(12)
  set customModelUrl($core.String v) { $_setString(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasCustomModelUrl() => $_has(11);
  @$pb.TagNumber(12)
  void clearCustomModelUrl() => clearField(12);
}

class VoiceLifecycleEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'VoiceLifecycleEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<VoiceEventKind>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: VoiceEventKind.VOICE_EVENT_KIND_UNSPECIFIED, valueOf: VoiceEventKind.valueOf, enumValues: VoiceEventKind.values)
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sessionId')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'text')
    ..a<$core.double>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'confidence', $pb.PbFieldType.OF)
    ..aOS(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'responseText')
    ..aOS(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'audioBase64')
    ..aInt64(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'durationMs')
    ..a<$core.double>(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'audioLevel', $pb.PbFieldType.OF)
    ..aOS(9, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'transcription')
    ..aOS(10, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'turnResponse')
    ..aOS(11, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'turnAudioBase64')
    ..aOS(12, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'error')
    ..hasRequiredFields = false
  ;

  VoiceLifecycleEvent._() : super();
  factory VoiceLifecycleEvent({
    VoiceEventKind? kind,
    $core.String? sessionId,
    $core.String? text,
    $core.double? confidence,
    $core.String? responseText,
    $core.String? audioBase64,
    $fixnum.Int64? durationMs,
    $core.double? audioLevel,
    $core.String? transcription,
    $core.String? turnResponse,
    $core.String? turnAudioBase64,
    $core.String? error,
  }) {
    final _result = create();
    if (kind != null) {
      _result.kind = kind;
    }
    if (sessionId != null) {
      _result.sessionId = sessionId;
    }
    if (text != null) {
      _result.text = text;
    }
    if (confidence != null) {
      _result.confidence = confidence;
    }
    if (responseText != null) {
      _result.responseText = responseText;
    }
    if (audioBase64 != null) {
      _result.audioBase64 = audioBase64;
    }
    if (durationMs != null) {
      _result.durationMs = durationMs;
    }
    if (audioLevel != null) {
      _result.audioLevel = audioLevel;
    }
    if (transcription != null) {
      _result.transcription = transcription;
    }
    if (turnResponse != null) {
      _result.turnResponse = turnResponse;
    }
    if (turnAudioBase64 != null) {
      _result.turnAudioBase64 = turnAudioBase64;
    }
    if (error != null) {
      _result.error = error;
    }
    return _result;
  }
  factory VoiceLifecycleEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VoiceLifecycleEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VoiceLifecycleEvent clone() => VoiceLifecycleEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VoiceLifecycleEvent copyWith(void Function(VoiceLifecycleEvent) updates) => super.copyWith((message) => updates(message as VoiceLifecycleEvent)) as VoiceLifecycleEvent; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static VoiceLifecycleEvent create() => VoiceLifecycleEvent._();
  VoiceLifecycleEvent createEmptyInstance() => create();
  static $pb.PbList<VoiceLifecycleEvent> createRepeated() => $pb.PbList<VoiceLifecycleEvent>();
  @$core.pragma('dart2js:noInline')
  static VoiceLifecycleEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VoiceLifecycleEvent>(create);
  static VoiceLifecycleEvent? _defaultInstance;

  @$pb.TagNumber(1)
  VoiceEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(VoiceEventKind v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get sessionId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sessionId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSessionId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSessionId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get text => $_getSZ(2);
  @$pb.TagNumber(3)
  set text($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasText() => $_has(2);
  @$pb.TagNumber(3)
  void clearText() => clearField(3);

  @$pb.TagNumber(4)
  $core.double get confidence => $_getN(3);
  @$pb.TagNumber(4)
  set confidence($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasConfidence() => $_has(3);
  @$pb.TagNumber(4)
  void clearConfidence() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get responseText => $_getSZ(4);
  @$pb.TagNumber(5)
  set responseText($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasResponseText() => $_has(4);
  @$pb.TagNumber(5)
  void clearResponseText() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get audioBase64 => $_getSZ(5);
  @$pb.TagNumber(6)
  set audioBase64($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasAudioBase64() => $_has(5);
  @$pb.TagNumber(6)
  void clearAudioBase64() => clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get durationMs => $_getI64(6);
  @$pb.TagNumber(7)
  set durationMs($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasDurationMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearDurationMs() => clearField(7);

  @$pb.TagNumber(8)
  $core.double get audioLevel => $_getN(7);
  @$pb.TagNumber(8)
  set audioLevel($core.double v) { $_setFloat(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasAudioLevel() => $_has(7);
  @$pb.TagNumber(8)
  void clearAudioLevel() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get transcription => $_getSZ(8);
  @$pb.TagNumber(9)
  set transcription($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasTranscription() => $_has(8);
  @$pb.TagNumber(9)
  void clearTranscription() => clearField(9);

  @$pb.TagNumber(10)
  $core.String get turnResponse => $_getSZ(9);
  @$pb.TagNumber(10)
  set turnResponse($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasTurnResponse() => $_has(9);
  @$pb.TagNumber(10)
  void clearTurnResponse() => clearField(10);

  @$pb.TagNumber(11)
  $core.String get turnAudioBase64 => $_getSZ(10);
  @$pb.TagNumber(11)
  set turnAudioBase64($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasTurnAudioBase64() => $_has(10);
  @$pb.TagNumber(11)
  void clearTurnAudioBase64() => clearField(11);

  @$pb.TagNumber(12)
  $core.String get error => $_getSZ(11);
  @$pb.TagNumber(12)
  set error($core.String v) { $_setString(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasError() => $_has(11);
  @$pb.TagNumber(12)
  void clearError() => clearField(12);
}

class PerformanceEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'PerformanceEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<PerformanceEventKind>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: PerformanceEventKind.PERFORMANCE_EVENT_KIND_UNSPECIFIED, valueOf: PerformanceEventKind.valueOf, enumValues: PerformanceEventKind.values)
    ..aInt64(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'memoryBytes')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'thermalState')
    ..aOS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'operation')
    ..aInt64(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'milliseconds')
    ..a<$core.double>(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'tokensPerSecond', $pb.PbFieldType.OD)
    ..hasRequiredFields = false
  ;

  PerformanceEvent._() : super();
  factory PerformanceEvent({
    PerformanceEventKind? kind,
    $fixnum.Int64? memoryBytes,
    $core.String? thermalState,
    $core.String? operation,
    $fixnum.Int64? milliseconds,
    $core.double? tokensPerSecond,
  }) {
    final _result = create();
    if (kind != null) {
      _result.kind = kind;
    }
    if (memoryBytes != null) {
      _result.memoryBytes = memoryBytes;
    }
    if (thermalState != null) {
      _result.thermalState = thermalState;
    }
    if (operation != null) {
      _result.operation = operation;
    }
    if (milliseconds != null) {
      _result.milliseconds = milliseconds;
    }
    if (tokensPerSecond != null) {
      _result.tokensPerSecond = tokensPerSecond;
    }
    return _result;
  }
  factory PerformanceEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PerformanceEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PerformanceEvent clone() => PerformanceEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PerformanceEvent copyWith(void Function(PerformanceEvent) updates) => super.copyWith((message) => updates(message as PerformanceEvent)) as PerformanceEvent; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static PerformanceEvent create() => PerformanceEvent._();
  PerformanceEvent createEmptyInstance() => create();
  static $pb.PbList<PerformanceEvent> createRepeated() => $pb.PbList<PerformanceEvent>();
  @$core.pragma('dart2js:noInline')
  static PerformanceEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PerformanceEvent>(create);
  static PerformanceEvent? _defaultInstance;

  @$pb.TagNumber(1)
  PerformanceEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(PerformanceEventKind v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get memoryBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set memoryBytes($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMemoryBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearMemoryBytes() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get thermalState => $_getSZ(2);
  @$pb.TagNumber(3)
  set thermalState($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasThermalState() => $_has(2);
  @$pb.TagNumber(3)
  void clearThermalState() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get operation => $_getSZ(3);
  @$pb.TagNumber(4)
  set operation($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasOperation() => $_has(3);
  @$pb.TagNumber(4)
  void clearOperation() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get milliseconds => $_getI64(4);
  @$pb.TagNumber(5)
  set milliseconds($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasMilliseconds() => $_has(4);
  @$pb.TagNumber(5)
  void clearMilliseconds() => clearField(5);

  @$pb.TagNumber(6)
  $core.double get tokensPerSecond => $_getN(5);
  @$pb.TagNumber(6)
  set tokensPerSecond($core.double v) { $_setDouble(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTokensPerSecond() => $_has(5);
  @$pb.TagNumber(6)
  void clearTokensPerSecond() => clearField(6);
}

class NetworkEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'NetworkEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<NetworkEventKind>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: NetworkEventKind.NETWORK_EVENT_KIND_UNSPECIFIED, valueOf: NetworkEventKind.valueOf, enumValues: NetworkEventKind.values)
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'url')
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'statusCode', $pb.PbFieldType.O3)
    ..aOB(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'isOnline')
    ..aOS(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'error')
    ..aInt64(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'latencyMs')
    ..hasRequiredFields = false
  ;

  NetworkEvent._() : super();
  factory NetworkEvent({
    NetworkEventKind? kind,
    $core.String? url,
    $core.int? statusCode,
    $core.bool? isOnline,
    $core.String? error,
    $fixnum.Int64? latencyMs,
  }) {
    final _result = create();
    if (kind != null) {
      _result.kind = kind;
    }
    if (url != null) {
      _result.url = url;
    }
    if (statusCode != null) {
      _result.statusCode = statusCode;
    }
    if (isOnline != null) {
      _result.isOnline = isOnline;
    }
    if (error != null) {
      _result.error = error;
    }
    if (latencyMs != null) {
      _result.latencyMs = latencyMs;
    }
    return _result;
  }
  factory NetworkEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory NetworkEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  NetworkEvent clone() => NetworkEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  NetworkEvent copyWith(void Function(NetworkEvent) updates) => super.copyWith((message) => updates(message as NetworkEvent)) as NetworkEvent; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static NetworkEvent create() => NetworkEvent._();
  NetworkEvent createEmptyInstance() => create();
  static $pb.PbList<NetworkEvent> createRepeated() => $pb.PbList<NetworkEvent>();
  @$core.pragma('dart2js:noInline')
  static NetworkEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<NetworkEvent>(create);
  static NetworkEvent? _defaultInstance;

  @$pb.TagNumber(1)
  NetworkEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(NetworkEventKind v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get url => $_getSZ(1);
  @$pb.TagNumber(2)
  set url($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasUrl() => $_has(1);
  @$pb.TagNumber(2)
  void clearUrl() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get statusCode => $_getIZ(2);
  @$pb.TagNumber(3)
  set statusCode($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasStatusCode() => $_has(2);
  @$pb.TagNumber(3)
  void clearStatusCode() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get isOnline => $_getBF(3);
  @$pb.TagNumber(4)
  set isOnline($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasIsOnline() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsOnline() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get error => $_getSZ(4);
  @$pb.TagNumber(5)
  set error($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasError() => $_has(4);
  @$pb.TagNumber(5)
  void clearError() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get latencyMs => $_getI64(5);
  @$pb.TagNumber(6)
  set latencyMs($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasLatencyMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearLatencyMs() => clearField(6);
}

class StorageEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'StorageEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<StorageEventKind>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: StorageEventKind.STORAGE_EVENT_KIND_UNSPECIFIED, valueOf: StorageEventKind.valueOf, enumValues: StorageEventKind.values)
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'modelId')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'error')
    ..aInt64(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'totalBytes')
    ..aInt64(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'availableBytes')
    ..aInt64(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'usedBytes')
    ..a<$core.int>(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'storedModelCount', $pb.PbFieldType.O3)
    ..aOS(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'cacheKey')
    ..aInt64(9, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'evictedBytes')
    ..hasRequiredFields = false
  ;

  StorageEvent._() : super();
  factory StorageEvent({
    StorageEventKind? kind,
    $core.String? modelId,
    $core.String? error,
    $fixnum.Int64? totalBytes,
    $fixnum.Int64? availableBytes,
    $fixnum.Int64? usedBytes,
    $core.int? storedModelCount,
    $core.String? cacheKey,
    $fixnum.Int64? evictedBytes,
  }) {
    final _result = create();
    if (kind != null) {
      _result.kind = kind;
    }
    if (modelId != null) {
      _result.modelId = modelId;
    }
    if (error != null) {
      _result.error = error;
    }
    if (totalBytes != null) {
      _result.totalBytes = totalBytes;
    }
    if (availableBytes != null) {
      _result.availableBytes = availableBytes;
    }
    if (usedBytes != null) {
      _result.usedBytes = usedBytes;
    }
    if (storedModelCount != null) {
      _result.storedModelCount = storedModelCount;
    }
    if (cacheKey != null) {
      _result.cacheKey = cacheKey;
    }
    if (evictedBytes != null) {
      _result.evictedBytes = evictedBytes;
    }
    return _result;
  }
  factory StorageEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StorageEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StorageEvent clone() => StorageEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StorageEvent copyWith(void Function(StorageEvent) updates) => super.copyWith((message) => updates(message as StorageEvent)) as StorageEvent; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static StorageEvent create() => StorageEvent._();
  StorageEvent createEmptyInstance() => create();
  static $pb.PbList<StorageEvent> createRepeated() => $pb.PbList<StorageEvent>();
  @$core.pragma('dart2js:noInline')
  static StorageEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StorageEvent>(create);
  static StorageEvent? _defaultInstance;

  @$pb.TagNumber(1)
  StorageEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(StorageEventKind v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get error => $_getSZ(2);
  @$pb.TagNumber(3)
  set error($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(3)
  void clearError() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get totalBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set totalBytes($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTotalBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalBytes() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get availableBytes => $_getI64(4);
  @$pb.TagNumber(5)
  set availableBytes($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAvailableBytes() => $_has(4);
  @$pb.TagNumber(5)
  void clearAvailableBytes() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get usedBytes => $_getI64(5);
  @$pb.TagNumber(6)
  set usedBytes($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasUsedBytes() => $_has(5);
  @$pb.TagNumber(6)
  void clearUsedBytes() => clearField(6);

  @$pb.TagNumber(7)
  $core.int get storedModelCount => $_getIZ(6);
  @$pb.TagNumber(7)
  set storedModelCount($core.int v) { $_setSignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasStoredModelCount() => $_has(6);
  @$pb.TagNumber(7)
  void clearStoredModelCount() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get cacheKey => $_getSZ(7);
  @$pb.TagNumber(8)
  set cacheKey($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasCacheKey() => $_has(7);
  @$pb.TagNumber(8)
  void clearCacheKey() => clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get evictedBytes => $_getI64(8);
  @$pb.TagNumber(9)
  set evictedBytes($fixnum.Int64 v) { $_setInt64(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasEvictedBytes() => $_has(8);
  @$pb.TagNumber(9)
  void clearEvictedBytes() => clearField(9);
}

class FrameworkEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'FrameworkEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<FrameworkEventKind>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: FrameworkEventKind.FRAMEWORK_EVENT_KIND_UNSPECIFIED, valueOf: FrameworkEventKind.valueOf, enumValues: FrameworkEventKind.values)
    ..a<$core.int>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'framework', $pb.PbFieldType.O3)
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'adapterName')
    ..a<$core.int>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'adapterCount', $pb.PbFieldType.O3)
    ..a<$core.int>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'frameworkCount', $pb.PbFieldType.O3)
    ..a<$core.int>(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'modelCount', $pb.PbFieldType.O3)
    ..aOS(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'modality')
    ..aOS(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'error')
    ..hasRequiredFields = false
  ;

  FrameworkEvent._() : super();
  factory FrameworkEvent({
    FrameworkEventKind? kind,
    $core.int? framework,
    $core.String? adapterName,
    $core.int? adapterCount,
    $core.int? frameworkCount,
    $core.int? modelCount,
    $core.String? modality,
    $core.String? error,
  }) {
    final _result = create();
    if (kind != null) {
      _result.kind = kind;
    }
    if (framework != null) {
      _result.framework = framework;
    }
    if (adapterName != null) {
      _result.adapterName = adapterName;
    }
    if (adapterCount != null) {
      _result.adapterCount = adapterCount;
    }
    if (frameworkCount != null) {
      _result.frameworkCount = frameworkCount;
    }
    if (modelCount != null) {
      _result.modelCount = modelCount;
    }
    if (modality != null) {
      _result.modality = modality;
    }
    if (error != null) {
      _result.error = error;
    }
    return _result;
  }
  factory FrameworkEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FrameworkEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FrameworkEvent clone() => FrameworkEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FrameworkEvent copyWith(void Function(FrameworkEvent) updates) => super.copyWith((message) => updates(message as FrameworkEvent)) as FrameworkEvent; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static FrameworkEvent create() => FrameworkEvent._();
  FrameworkEvent createEmptyInstance() => create();
  static $pb.PbList<FrameworkEvent> createRepeated() => $pb.PbList<FrameworkEvent>();
  @$core.pragma('dart2js:noInline')
  static FrameworkEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FrameworkEvent>(create);
  static FrameworkEvent? _defaultInstance;

  @$pb.TagNumber(1)
  FrameworkEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(FrameworkEventKind v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get framework => $_getIZ(1);
  @$pb.TagNumber(2)
  set framework($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasFramework() => $_has(1);
  @$pb.TagNumber(2)
  void clearFramework() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get adapterName => $_getSZ(2);
  @$pb.TagNumber(3)
  set adapterName($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAdapterName() => $_has(2);
  @$pb.TagNumber(3)
  void clearAdapterName() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get adapterCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set adapterCount($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAdapterCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearAdapterCount() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get frameworkCount => $_getIZ(4);
  @$pb.TagNumber(5)
  set frameworkCount($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasFrameworkCount() => $_has(4);
  @$pb.TagNumber(5)
  void clearFrameworkCount() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get modelCount => $_getIZ(5);
  @$pb.TagNumber(6)
  set modelCount($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasModelCount() => $_has(5);
  @$pb.TagNumber(6)
  void clearModelCount() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get modality => $_getSZ(6);
  @$pb.TagNumber(7)
  set modality($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasModality() => $_has(6);
  @$pb.TagNumber(7)
  void clearModality() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get error => $_getSZ(7);
  @$pb.TagNumber(8)
  set error($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasError() => $_has(7);
  @$pb.TagNumber(8)
  void clearError() => clearField(8);
}

class DeviceEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'DeviceEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<DeviceEventKind>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: DeviceEventKind.DEVICE_EVENT_KIND_UNSPECIFIED, valueOf: DeviceEventKind.valueOf, enumValues: DeviceEventKind.values)
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'deviceId')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'osName')
    ..aOS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'osVersion')
    ..aOS(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'model')
    ..aOS(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'error')
    ..aOS(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'property')
    ..aOS(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'newValue')
    ..aOS(9, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'oldValue')
    ..a<$core.double>(10, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'batteryLevel', $pb.PbFieldType.OF)
    ..aOB(11, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'isCharging')
    ..aOS(12, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'thermalState')
    ..aOB(13, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'isConnected')
    ..aOS(14, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'connectionType')
    ..hasRequiredFields = false
  ;

  DeviceEvent._() : super();
  factory DeviceEvent({
    DeviceEventKind? kind,
    $core.String? deviceId,
    $core.String? osName,
    $core.String? osVersion,
    $core.String? model,
    $core.String? error,
    $core.String? property,
    $core.String? newValue,
    $core.String? oldValue,
    $core.double? batteryLevel,
    $core.bool? isCharging,
    $core.String? thermalState,
    $core.bool? isConnected,
    $core.String? connectionType,
  }) {
    final _result = create();
    if (kind != null) {
      _result.kind = kind;
    }
    if (deviceId != null) {
      _result.deviceId = deviceId;
    }
    if (osName != null) {
      _result.osName = osName;
    }
    if (osVersion != null) {
      _result.osVersion = osVersion;
    }
    if (model != null) {
      _result.model = model;
    }
    if (error != null) {
      _result.error = error;
    }
    if (property != null) {
      _result.property = property;
    }
    if (newValue != null) {
      _result.newValue = newValue;
    }
    if (oldValue != null) {
      _result.oldValue = oldValue;
    }
    if (batteryLevel != null) {
      _result.batteryLevel = batteryLevel;
    }
    if (isCharging != null) {
      _result.isCharging = isCharging;
    }
    if (thermalState != null) {
      _result.thermalState = thermalState;
    }
    if (isConnected != null) {
      _result.isConnected = isConnected;
    }
    if (connectionType != null) {
      _result.connectionType = connectionType;
    }
    return _result;
  }
  factory DeviceEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DeviceEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DeviceEvent clone() => DeviceEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DeviceEvent copyWith(void Function(DeviceEvent) updates) => super.copyWith((message) => updates(message as DeviceEvent)) as DeviceEvent; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static DeviceEvent create() => DeviceEvent._();
  DeviceEvent createEmptyInstance() => create();
  static $pb.PbList<DeviceEvent> createRepeated() => $pb.PbList<DeviceEvent>();
  @$core.pragma('dart2js:noInline')
  static DeviceEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeviceEvent>(create);
  static DeviceEvent? _defaultInstance;

  @$pb.TagNumber(1)
  DeviceEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(DeviceEventKind v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get deviceId => $_getSZ(1);
  @$pb.TagNumber(2)
  set deviceId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeviceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get osName => $_getSZ(2);
  @$pb.TagNumber(3)
  set osName($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasOsName() => $_has(2);
  @$pb.TagNumber(3)
  void clearOsName() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get osVersion => $_getSZ(3);
  @$pb.TagNumber(4)
  set osVersion($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasOsVersion() => $_has(3);
  @$pb.TagNumber(4)
  void clearOsVersion() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get model => $_getSZ(4);
  @$pb.TagNumber(5)
  set model($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasModel() => $_has(4);
  @$pb.TagNumber(5)
  void clearModel() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get error => $_getSZ(5);
  @$pb.TagNumber(6)
  set error($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(6)
  void clearError() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get property => $_getSZ(6);
  @$pb.TagNumber(7)
  set property($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasProperty() => $_has(6);
  @$pb.TagNumber(7)
  void clearProperty() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get newValue => $_getSZ(7);
  @$pb.TagNumber(8)
  set newValue($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasNewValue() => $_has(7);
  @$pb.TagNumber(8)
  void clearNewValue() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get oldValue => $_getSZ(8);
  @$pb.TagNumber(9)
  set oldValue($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasOldValue() => $_has(8);
  @$pb.TagNumber(9)
  void clearOldValue() => clearField(9);

  @$pb.TagNumber(10)
  $core.double get batteryLevel => $_getN(9);
  @$pb.TagNumber(10)
  set batteryLevel($core.double v) { $_setFloat(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasBatteryLevel() => $_has(9);
  @$pb.TagNumber(10)
  void clearBatteryLevel() => clearField(10);

  @$pb.TagNumber(11)
  $core.bool get isCharging => $_getBF(10);
  @$pb.TagNumber(11)
  set isCharging($core.bool v) { $_setBool(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasIsCharging() => $_has(10);
  @$pb.TagNumber(11)
  void clearIsCharging() => clearField(11);

  @$pb.TagNumber(12)
  $core.String get thermalState => $_getSZ(11);
  @$pb.TagNumber(12)
  set thermalState($core.String v) { $_setString(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasThermalState() => $_has(11);
  @$pb.TagNumber(12)
  void clearThermalState() => clearField(12);

  @$pb.TagNumber(13)
  $core.bool get isConnected => $_getBF(12);
  @$pb.TagNumber(13)
  set isConnected($core.bool v) { $_setBool(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasIsConnected() => $_has(12);
  @$pb.TagNumber(13)
  void clearIsConnected() => clearField(13);

  @$pb.TagNumber(14)
  $core.String get connectionType => $_getSZ(13);
  @$pb.TagNumber(14)
  set connectionType($core.String v) { $_setString(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasConnectionType() => $_has(13);
  @$pb.TagNumber(14)
  void clearConnectionType() => clearField(14);
}

class ComponentInitializationEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ComponentInitializationEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<ComponentInitializationEventKind>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: ComponentInitializationEventKind.COMPONENT_INIT_EVENT_KIND_UNSPECIFIED, valueOf: ComponentInitializationEventKind.valueOf, enumValues: ComponentInitializationEventKind.values)
    ..e<SDKComponent>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'component', $pb.PbFieldType.OE, defaultOrMaker: SDKComponent.SDK_COMPONENT_UNSPECIFIED, valueOf: SDKComponent.valueOf, enumValues: SDKComponent.values)
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'modelId')
    ..aInt64(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sizeBytes')
    ..a<$core.double>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'progress', $pb.PbFieldType.OF)
    ..aOS(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'error')
    ..aOS(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'oldState')
    ..aOS(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'newState')
    ..pc<SDKComponent>(9, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'components', $pb.PbFieldType.KE, valueOf: SDKComponent.valueOf, enumValues: SDKComponent.values, defaultEnumValue: SDKComponent.SDK_COMPONENT_UNSPECIFIED)
    ..pc<SDKComponent>(10, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'readyComponents', $pb.PbFieldType.KE, valueOf: SDKComponent.valueOf, enumValues: SDKComponent.values, defaultEnumValue: SDKComponent.SDK_COMPONENT_UNSPECIFIED)
    ..pc<SDKComponent>(11, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'pendingComponents', $pb.PbFieldType.KE, valueOf: SDKComponent.valueOf, enumValues: SDKComponent.values, defaultEnumValue: SDKComponent.SDK_COMPONENT_UNSPECIFIED)
    ..aOB(12, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'initSuccess')
    ..a<$core.int>(13, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'readyCount', $pb.PbFieldType.O3)
    ..a<$core.int>(14, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'failedCount', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  ComponentInitializationEvent._() : super();
  factory ComponentInitializationEvent({
    ComponentInitializationEventKind? kind,
    SDKComponent? component,
    $core.String? modelId,
    $fixnum.Int64? sizeBytes,
    $core.double? progress,
    $core.String? error,
    $core.String? oldState,
    $core.String? newState,
    $core.Iterable<SDKComponent>? components,
    $core.Iterable<SDKComponent>? readyComponents,
    $core.Iterable<SDKComponent>? pendingComponents,
    $core.bool? initSuccess,
    $core.int? readyCount,
    $core.int? failedCount,
  }) {
    final _result = create();
    if (kind != null) {
      _result.kind = kind;
    }
    if (component != null) {
      _result.component = component;
    }
    if (modelId != null) {
      _result.modelId = modelId;
    }
    if (sizeBytes != null) {
      _result.sizeBytes = sizeBytes;
    }
    if (progress != null) {
      _result.progress = progress;
    }
    if (error != null) {
      _result.error = error;
    }
    if (oldState != null) {
      _result.oldState = oldState;
    }
    if (newState != null) {
      _result.newState = newState;
    }
    if (components != null) {
      _result.components.addAll(components);
    }
    if (readyComponents != null) {
      _result.readyComponents.addAll(readyComponents);
    }
    if (pendingComponents != null) {
      _result.pendingComponents.addAll(pendingComponents);
    }
    if (initSuccess != null) {
      _result.initSuccess = initSuccess;
    }
    if (readyCount != null) {
      _result.readyCount = readyCount;
    }
    if (failedCount != null) {
      _result.failedCount = failedCount;
    }
    return _result;
  }
  factory ComponentInitializationEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ComponentInitializationEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ComponentInitializationEvent clone() => ComponentInitializationEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ComponentInitializationEvent copyWith(void Function(ComponentInitializationEvent) updates) => super.copyWith((message) => updates(message as ComponentInitializationEvent)) as ComponentInitializationEvent; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ComponentInitializationEvent create() => ComponentInitializationEvent._();
  ComponentInitializationEvent createEmptyInstance() => create();
  static $pb.PbList<ComponentInitializationEvent> createRepeated() => $pb.PbList<ComponentInitializationEvent>();
  @$core.pragma('dart2js:noInline')
  static ComponentInitializationEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ComponentInitializationEvent>(create);
  static ComponentInitializationEvent? _defaultInstance;

  @$pb.TagNumber(1)
  ComponentInitializationEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(ComponentInitializationEventKind v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => clearField(1);

  @$pb.TagNumber(2)
  SDKComponent get component => $_getN(1);
  @$pb.TagNumber(2)
  set component(SDKComponent v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasComponent() => $_has(1);
  @$pb.TagNumber(2)
  void clearComponent() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get modelId => $_getSZ(2);
  @$pb.TagNumber(3)
  set modelId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasModelId() => $_has(2);
  @$pb.TagNumber(3)
  void clearModelId() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get sizeBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set sizeBytes($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSizeBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearSizeBytes() => clearField(4);

  @$pb.TagNumber(5)
  $core.double get progress => $_getN(4);
  @$pb.TagNumber(5)
  set progress($core.double v) { $_setFloat(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasProgress() => $_has(4);
  @$pb.TagNumber(5)
  void clearProgress() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get error => $_getSZ(5);
  @$pb.TagNumber(6)
  set error($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(6)
  void clearError() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get oldState => $_getSZ(6);
  @$pb.TagNumber(7)
  set oldState($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasOldState() => $_has(6);
  @$pb.TagNumber(7)
  void clearOldState() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get newState => $_getSZ(7);
  @$pb.TagNumber(8)
  set newState($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasNewState() => $_has(7);
  @$pb.TagNumber(8)
  void clearNewState() => clearField(8);

  @$pb.TagNumber(9)
  $core.List<SDKComponent> get components => $_getList(8);

  @$pb.TagNumber(10)
  $core.List<SDKComponent> get readyComponents => $_getList(9);

  @$pb.TagNumber(11)
  $core.List<SDKComponent> get pendingComponents => $_getList(10);

  @$pb.TagNumber(12)
  $core.bool get initSuccess => $_getBF(11);
  @$pb.TagNumber(12)
  set initSuccess($core.bool v) { $_setBool(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasInitSuccess() => $_has(11);
  @$pb.TagNumber(12)
  void clearInitSuccess() => clearField(12);

  @$pb.TagNumber(13)
  $core.int get readyCount => $_getIZ(12);
  @$pb.TagNumber(13)
  set readyCount($core.int v) { $_setSignedInt32(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasReadyCount() => $_has(12);
  @$pb.TagNumber(13)
  void clearReadyCount() => clearField(13);

  @$pb.TagNumber(14)
  $core.int get failedCount => $_getIZ(13);
  @$pb.TagNumber(14)
  set failedCount($core.int v) { $_setSignedInt32(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasFailedCount() => $_has(13);
  @$pb.TagNumber(14)
  void clearFailedCount() => clearField(14);
}

enum SDKEvent_Event {
  initialization, 
  configuration, 
  generation, 
  model, 
  performance, 
  network, 
  storage, 
  framework, 
  device, 
  componentInit, 
  voice, 
  voicePipeline, 
  notSet
}

class SDKEvent extends $pb.GeneratedMessage {
  static const $core.Map<$core.int, SDKEvent_Event> _SDKEvent_EventByTag = {
    3 : SDKEvent_Event.initialization,
    4 : SDKEvent_Event.configuration,
    5 : SDKEvent_Event.generation,
    6 : SDKEvent_Event.model,
    7 : SDKEvent_Event.performance,
    8 : SDKEvent_Event.network,
    9 : SDKEvent_Event.storage,
    10 : SDKEvent_Event.framework,
    11 : SDKEvent_Event.device,
    12 : SDKEvent_Event.componentInit,
    17 : SDKEvent_Event.voice,
    18 : SDKEvent_Event.voicePipeline,
    0 : SDKEvent_Event.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'SDKEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..oo(0, [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 17, 18])
    ..aInt64(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'timestampMs')
    ..e<EventSeverity>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'severity', $pb.PbFieldType.OE, defaultOrMaker: EventSeverity.EVENT_SEVERITY_DEBUG, valueOf: EventSeverity.valueOf, enumValues: EventSeverity.values)
    ..aOM<InitializationEvent>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'initialization', subBuilder: InitializationEvent.create)
    ..aOM<ConfigurationEvent>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'configuration', subBuilder: ConfigurationEvent.create)
    ..aOM<GenerationEvent>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'generation', subBuilder: GenerationEvent.create)
    ..aOM<ModelEvent>(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'model', subBuilder: ModelEvent.create)
    ..aOM<PerformanceEvent>(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'performance', subBuilder: PerformanceEvent.create)
    ..aOM<NetworkEvent>(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'network', subBuilder: NetworkEvent.create)
    ..aOM<StorageEvent>(9, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'storage', subBuilder: StorageEvent.create)
    ..aOM<FrameworkEvent>(10, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'framework', subBuilder: FrameworkEvent.create)
    ..aOM<DeviceEvent>(11, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'device', subBuilder: DeviceEvent.create)
    ..aOM<ComponentInitializationEvent>(12, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'componentInit', subBuilder: ComponentInitializationEvent.create)
    ..aOS(13, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'id')
    ..aOS(14, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sessionId')
    ..e<EventDestination>(15, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'destination', $pb.PbFieldType.OE, defaultOrMaker: EventDestination.EVENT_DESTINATION_UNSPECIFIED, valueOf: EventDestination.valueOf, enumValues: EventDestination.values)
    ..m<$core.String, $core.String>(16, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'properties', entryClassName: 'SDKEvent.PropertiesEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('runanywhere.v1'))
    ..aOM<VoiceLifecycleEvent>(17, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'voice', subBuilder: VoiceLifecycleEvent.create)
    ..aOM<$0.VoiceEvent>(18, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'voicePipeline', subBuilder: $0.VoiceEvent.create)
    ..hasRequiredFields = false
  ;

  SDKEvent._() : super();
  factory SDKEvent({
    $fixnum.Int64? timestampMs,
    EventSeverity? severity,
    InitializationEvent? initialization,
    ConfigurationEvent? configuration,
    GenerationEvent? generation,
    ModelEvent? model,
    PerformanceEvent? performance,
    NetworkEvent? network,
    StorageEvent? storage,
    FrameworkEvent? framework,
    DeviceEvent? device,
    ComponentInitializationEvent? componentInit,
    $core.String? id,
    $core.String? sessionId,
    EventDestination? destination,
    $core.Map<$core.String, $core.String>? properties,
    VoiceLifecycleEvent? voice,
    $0.VoiceEvent? voicePipeline,
  }) {
    final _result = create();
    if (timestampMs != null) {
      _result.timestampMs = timestampMs;
    }
    if (severity != null) {
      _result.severity = severity;
    }
    if (initialization != null) {
      _result.initialization = initialization;
    }
    if (configuration != null) {
      _result.configuration = configuration;
    }
    if (generation != null) {
      _result.generation = generation;
    }
    if (model != null) {
      _result.model = model;
    }
    if (performance != null) {
      _result.performance = performance;
    }
    if (network != null) {
      _result.network = network;
    }
    if (storage != null) {
      _result.storage = storage;
    }
    if (framework != null) {
      _result.framework = framework;
    }
    if (device != null) {
      _result.device = device;
    }
    if (componentInit != null) {
      _result.componentInit = componentInit;
    }
    if (id != null) {
      _result.id = id;
    }
    if (sessionId != null) {
      _result.sessionId = sessionId;
    }
    if (destination != null) {
      _result.destination = destination;
    }
    if (properties != null) {
      _result.properties.addAll(properties);
    }
    if (voice != null) {
      _result.voice = voice;
    }
    if (voicePipeline != null) {
      _result.voicePipeline = voicePipeline;
    }
    return _result;
  }
  factory SDKEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SDKEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SDKEvent clone() => SDKEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SDKEvent copyWith(void Function(SDKEvent) updates) => super.copyWith((message) => updates(message as SDKEvent)) as SDKEvent; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static SDKEvent create() => SDKEvent._();
  SDKEvent createEmptyInstance() => create();
  static $pb.PbList<SDKEvent> createRepeated() => $pb.PbList<SDKEvent>();
  @$core.pragma('dart2js:noInline')
  static SDKEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SDKEvent>(create);
  static SDKEvent? _defaultInstance;

  SDKEvent_Event whichEvent() => _SDKEvent_EventByTag[$_whichOneof(0)]!;
  void clearEvent() => clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $fixnum.Int64 get timestampMs => $_getI64(0);
  @$pb.TagNumber(1)
  set timestampMs($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTimestampMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearTimestampMs() => clearField(1);

  @$pb.TagNumber(2)
  EventSeverity get severity => $_getN(1);
  @$pb.TagNumber(2)
  set severity(EventSeverity v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasSeverity() => $_has(1);
  @$pb.TagNumber(2)
  void clearSeverity() => clearField(2);

  @$pb.TagNumber(3)
  InitializationEvent get initialization => $_getN(2);
  @$pb.TagNumber(3)
  set initialization(InitializationEvent v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasInitialization() => $_has(2);
  @$pb.TagNumber(3)
  void clearInitialization() => clearField(3);
  @$pb.TagNumber(3)
  InitializationEvent ensureInitialization() => $_ensure(2);

  @$pb.TagNumber(4)
  ConfigurationEvent get configuration => $_getN(3);
  @$pb.TagNumber(4)
  set configuration(ConfigurationEvent v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasConfiguration() => $_has(3);
  @$pb.TagNumber(4)
  void clearConfiguration() => clearField(4);
  @$pb.TagNumber(4)
  ConfigurationEvent ensureConfiguration() => $_ensure(3);

  @$pb.TagNumber(5)
  GenerationEvent get generation => $_getN(4);
  @$pb.TagNumber(5)
  set generation(GenerationEvent v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasGeneration() => $_has(4);
  @$pb.TagNumber(5)
  void clearGeneration() => clearField(5);
  @$pb.TagNumber(5)
  GenerationEvent ensureGeneration() => $_ensure(4);

  @$pb.TagNumber(6)
  ModelEvent get model => $_getN(5);
  @$pb.TagNumber(6)
  set model(ModelEvent v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasModel() => $_has(5);
  @$pb.TagNumber(6)
  void clearModel() => clearField(6);
  @$pb.TagNumber(6)
  ModelEvent ensureModel() => $_ensure(5);

  @$pb.TagNumber(7)
  PerformanceEvent get performance => $_getN(6);
  @$pb.TagNumber(7)
  set performance(PerformanceEvent v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasPerformance() => $_has(6);
  @$pb.TagNumber(7)
  void clearPerformance() => clearField(7);
  @$pb.TagNumber(7)
  PerformanceEvent ensurePerformance() => $_ensure(6);

  @$pb.TagNumber(8)
  NetworkEvent get network => $_getN(7);
  @$pb.TagNumber(8)
  set network(NetworkEvent v) { setField(8, v); }
  @$pb.TagNumber(8)
  $core.bool hasNetwork() => $_has(7);
  @$pb.TagNumber(8)
  void clearNetwork() => clearField(8);
  @$pb.TagNumber(8)
  NetworkEvent ensureNetwork() => $_ensure(7);

  @$pb.TagNumber(9)
  StorageEvent get storage => $_getN(8);
  @$pb.TagNumber(9)
  set storage(StorageEvent v) { setField(9, v); }
  @$pb.TagNumber(9)
  $core.bool hasStorage() => $_has(8);
  @$pb.TagNumber(9)
  void clearStorage() => clearField(9);
  @$pb.TagNumber(9)
  StorageEvent ensureStorage() => $_ensure(8);

  @$pb.TagNumber(10)
  FrameworkEvent get framework => $_getN(9);
  @$pb.TagNumber(10)
  set framework(FrameworkEvent v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasFramework() => $_has(9);
  @$pb.TagNumber(10)
  void clearFramework() => clearField(10);
  @$pb.TagNumber(10)
  FrameworkEvent ensureFramework() => $_ensure(9);

  @$pb.TagNumber(11)
  DeviceEvent get device => $_getN(10);
  @$pb.TagNumber(11)
  set device(DeviceEvent v) { setField(11, v); }
  @$pb.TagNumber(11)
  $core.bool hasDevice() => $_has(10);
  @$pb.TagNumber(11)
  void clearDevice() => clearField(11);
  @$pb.TagNumber(11)
  DeviceEvent ensureDevice() => $_ensure(10);

  @$pb.TagNumber(12)
  ComponentInitializationEvent get componentInit => $_getN(11);
  @$pb.TagNumber(12)
  set componentInit(ComponentInitializationEvent v) { setField(12, v); }
  @$pb.TagNumber(12)
  $core.bool hasComponentInit() => $_has(11);
  @$pb.TagNumber(12)
  void clearComponentInit() => clearField(12);
  @$pb.TagNumber(12)
  ComponentInitializationEvent ensureComponentInit() => $_ensure(11);

  @$pb.TagNumber(13)
  $core.String get id => $_getSZ(12);
  @$pb.TagNumber(13)
  set id($core.String v) { $_setString(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasId() => $_has(12);
  @$pb.TagNumber(13)
  void clearId() => clearField(13);

  @$pb.TagNumber(14)
  $core.String get sessionId => $_getSZ(13);
  @$pb.TagNumber(14)
  set sessionId($core.String v) { $_setString(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasSessionId() => $_has(13);
  @$pb.TagNumber(14)
  void clearSessionId() => clearField(14);

  @$pb.TagNumber(15)
  EventDestination get destination => $_getN(14);
  @$pb.TagNumber(15)
  set destination(EventDestination v) { setField(15, v); }
  @$pb.TagNumber(15)
  $core.bool hasDestination() => $_has(14);
  @$pb.TagNumber(15)
  void clearDestination() => clearField(15);

  @$pb.TagNumber(16)
  $core.Map<$core.String, $core.String> get properties => $_getMap(15);

  @$pb.TagNumber(17)
  VoiceLifecycleEvent get voice => $_getN(16);
  @$pb.TagNumber(17)
  set voice(VoiceLifecycleEvent v) { setField(17, v); }
  @$pb.TagNumber(17)
  $core.bool hasVoice() => $_has(16);
  @$pb.TagNumber(17)
  void clearVoice() => clearField(17);
  @$pb.TagNumber(17)
  VoiceLifecycleEvent ensureVoice() => $_ensure(16);

  @$pb.TagNumber(18)
  $0.VoiceEvent get voicePipeline => $_getN(17);
  @$pb.TagNumber(18)
  set voicePipeline($0.VoiceEvent v) { setField(18, v); }
  @$pb.TagNumber(18)
  $core.bool hasVoicePipeline() => $_has(17);
  @$pb.TagNumber(18)
  void clearVoicePipeline() => clearField(18);
  @$pb.TagNumber(18)
  $0.VoiceEvent ensureVoicePipeline() => $_ensure(17);
}

