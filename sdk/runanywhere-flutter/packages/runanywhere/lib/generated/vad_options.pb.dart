///
//  Generated code. Do not modify.
//  source: vad_options.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'vad_options.pbenum.dart';

export 'vad_options.pbenum.dart';

class VADConfiguration extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'VADConfiguration', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'modelId')
    ..a<$core.int>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sampleRate', $pb.PbFieldType.O3)
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'frameLengthMs', $pb.PbFieldType.O3)
    ..a<$core.double>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'threshold', $pb.PbFieldType.OF)
    ..aOB(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'enableAutoCalibration')
    ..hasRequiredFields = false
  ;

  VADConfiguration._() : super();
  factory VADConfiguration({
    $core.String? modelId,
    $core.int? sampleRate,
    $core.int? frameLengthMs,
    $core.double? threshold,
    $core.bool? enableAutoCalibration,
  }) {
    final _result = create();
    if (modelId != null) {
      _result.modelId = modelId;
    }
    if (sampleRate != null) {
      _result.sampleRate = sampleRate;
    }
    if (frameLengthMs != null) {
      _result.frameLengthMs = frameLengthMs;
    }
    if (threshold != null) {
      _result.threshold = threshold;
    }
    if (enableAutoCalibration != null) {
      _result.enableAutoCalibration = enableAutoCalibration;
    }
    return _result;
  }
  factory VADConfiguration.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VADConfiguration.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VADConfiguration clone() => VADConfiguration()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VADConfiguration copyWith(void Function(VADConfiguration) updates) => super.copyWith((message) => updates(message as VADConfiguration)) as VADConfiguration; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static VADConfiguration create() => VADConfiguration._();
  VADConfiguration createEmptyInstance() => create();
  static $pb.PbList<VADConfiguration> createRepeated() => $pb.PbList<VADConfiguration>();
  @$core.pragma('dart2js:noInline')
  static VADConfiguration getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VADConfiguration>(create);
  static VADConfiguration? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get sampleRate => $_getIZ(1);
  @$pb.TagNumber(2)
  set sampleRate($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSampleRate() => $_has(1);
  @$pb.TagNumber(2)
  void clearSampleRate() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get frameLengthMs => $_getIZ(2);
  @$pb.TagNumber(3)
  set frameLengthMs($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasFrameLengthMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearFrameLengthMs() => clearField(3);

  @$pb.TagNumber(4)
  $core.double get threshold => $_getN(3);
  @$pb.TagNumber(4)
  set threshold($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasThreshold() => $_has(3);
  @$pb.TagNumber(4)
  void clearThreshold() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get enableAutoCalibration => $_getBF(4);
  @$pb.TagNumber(5)
  set enableAutoCalibration($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasEnableAutoCalibration() => $_has(4);
  @$pb.TagNumber(5)
  void clearEnableAutoCalibration() => clearField(5);
}

class VADOptions extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'VADOptions', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.double>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'threshold', $pb.PbFieldType.OF)
    ..a<$core.int>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'minSpeechDurationMs', $pb.PbFieldType.O3)
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'minSilenceDurationMs', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  VADOptions._() : super();
  factory VADOptions({
    $core.double? threshold,
    $core.int? minSpeechDurationMs,
    $core.int? minSilenceDurationMs,
  }) {
    final _result = create();
    if (threshold != null) {
      _result.threshold = threshold;
    }
    if (minSpeechDurationMs != null) {
      _result.minSpeechDurationMs = minSpeechDurationMs;
    }
    if (minSilenceDurationMs != null) {
      _result.minSilenceDurationMs = minSilenceDurationMs;
    }
    return _result;
  }
  factory VADOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VADOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VADOptions clone() => VADOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VADOptions copyWith(void Function(VADOptions) updates) => super.copyWith((message) => updates(message as VADOptions)) as VADOptions; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static VADOptions create() => VADOptions._();
  VADOptions createEmptyInstance() => create();
  static $pb.PbList<VADOptions> createRepeated() => $pb.PbList<VADOptions>();
  @$core.pragma('dart2js:noInline')
  static VADOptions getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VADOptions>(create);
  static VADOptions? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get threshold => $_getN(0);
  @$pb.TagNumber(1)
  set threshold($core.double v) { $_setFloat(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasThreshold() => $_has(0);
  @$pb.TagNumber(1)
  void clearThreshold() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get minSpeechDurationMs => $_getIZ(1);
  @$pb.TagNumber(2)
  set minSpeechDurationMs($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMinSpeechDurationMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearMinSpeechDurationMs() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get minSilenceDurationMs => $_getIZ(2);
  @$pb.TagNumber(3)
  set minSilenceDurationMs($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMinSilenceDurationMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearMinSilenceDurationMs() => clearField(3);
}

class VADResult extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'VADResult', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'isSpeech')
    ..a<$core.double>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'confidence', $pb.PbFieldType.OF)
    ..a<$core.double>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'energy', $pb.PbFieldType.OF)
    ..a<$core.int>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'durationMs', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  VADResult._() : super();
  factory VADResult({
    $core.bool? isSpeech,
    $core.double? confidence,
    $core.double? energy,
    $core.int? durationMs,
  }) {
    final _result = create();
    if (isSpeech != null) {
      _result.isSpeech = isSpeech;
    }
    if (confidence != null) {
      _result.confidence = confidence;
    }
    if (energy != null) {
      _result.energy = energy;
    }
    if (durationMs != null) {
      _result.durationMs = durationMs;
    }
    return _result;
  }
  factory VADResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VADResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VADResult clone() => VADResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VADResult copyWith(void Function(VADResult) updates) => super.copyWith((message) => updates(message as VADResult)) as VADResult; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static VADResult create() => VADResult._();
  VADResult createEmptyInstance() => create();
  static $pb.PbList<VADResult> createRepeated() => $pb.PbList<VADResult>();
  @$core.pragma('dart2js:noInline')
  static VADResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VADResult>(create);
  static VADResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get isSpeech => $_getBF(0);
  @$pb.TagNumber(1)
  set isSpeech($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasIsSpeech() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsSpeech() => clearField(1);

  @$pb.TagNumber(2)
  $core.double get confidence => $_getN(1);
  @$pb.TagNumber(2)
  set confidence($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasConfidence() => $_has(1);
  @$pb.TagNumber(2)
  void clearConfidence() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get energy => $_getN(2);
  @$pb.TagNumber(3)
  set energy($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasEnergy() => $_has(2);
  @$pb.TagNumber(3)
  void clearEnergy() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get durationMs => $_getIZ(3);
  @$pb.TagNumber(4)
  set durationMs($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasDurationMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearDurationMs() => clearField(4);
}

class VADStatistics extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'VADStatistics', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.double>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'currentEnergy', $pb.PbFieldType.OF)
    ..a<$core.double>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'currentThreshold', $pb.PbFieldType.OF)
    ..a<$core.double>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'ambientLevel', $pb.PbFieldType.OF)
    ..a<$core.double>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'recentAvg', $pb.PbFieldType.OF)
    ..a<$core.double>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'recentMax', $pb.PbFieldType.OF)
    ..hasRequiredFields = false
  ;

  VADStatistics._() : super();
  factory VADStatistics({
    $core.double? currentEnergy,
    $core.double? currentThreshold,
    $core.double? ambientLevel,
    $core.double? recentAvg,
    $core.double? recentMax,
  }) {
    final _result = create();
    if (currentEnergy != null) {
      _result.currentEnergy = currentEnergy;
    }
    if (currentThreshold != null) {
      _result.currentThreshold = currentThreshold;
    }
    if (ambientLevel != null) {
      _result.ambientLevel = ambientLevel;
    }
    if (recentAvg != null) {
      _result.recentAvg = recentAvg;
    }
    if (recentMax != null) {
      _result.recentMax = recentMax;
    }
    return _result;
  }
  factory VADStatistics.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VADStatistics.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VADStatistics clone() => VADStatistics()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VADStatistics copyWith(void Function(VADStatistics) updates) => super.copyWith((message) => updates(message as VADStatistics)) as VADStatistics; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static VADStatistics create() => VADStatistics._();
  VADStatistics createEmptyInstance() => create();
  static $pb.PbList<VADStatistics> createRepeated() => $pb.PbList<VADStatistics>();
  @$core.pragma('dart2js:noInline')
  static VADStatistics getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VADStatistics>(create);
  static VADStatistics? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get currentEnergy => $_getN(0);
  @$pb.TagNumber(1)
  set currentEnergy($core.double v) { $_setFloat(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCurrentEnergy() => $_has(0);
  @$pb.TagNumber(1)
  void clearCurrentEnergy() => clearField(1);

  @$pb.TagNumber(2)
  $core.double get currentThreshold => $_getN(1);
  @$pb.TagNumber(2)
  set currentThreshold($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCurrentThreshold() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrentThreshold() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get ambientLevel => $_getN(2);
  @$pb.TagNumber(3)
  set ambientLevel($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAmbientLevel() => $_has(2);
  @$pb.TagNumber(3)
  void clearAmbientLevel() => clearField(3);

  @$pb.TagNumber(4)
  $core.double get recentAvg => $_getN(3);
  @$pb.TagNumber(4)
  set recentAvg($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasRecentAvg() => $_has(3);
  @$pb.TagNumber(4)
  void clearRecentAvg() => clearField(4);

  @$pb.TagNumber(5)
  $core.double get recentMax => $_getN(4);
  @$pb.TagNumber(5)
  set recentMax($core.double v) { $_setFloat(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasRecentMax() => $_has(4);
  @$pb.TagNumber(5)
  void clearRecentMax() => clearField(5);
}

class SpeechActivityEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'SpeechActivityEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<SpeechActivityKind>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'eventType', $pb.PbFieldType.OE, defaultOrMaker: SpeechActivityKind.SPEECH_ACTIVITY_KIND_UNSPECIFIED, valueOf: SpeechActivityKind.valueOf, enumValues: SpeechActivityKind.values)
    ..aInt64(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'timestampMs')
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'durationMs', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  SpeechActivityEvent._() : super();
  factory SpeechActivityEvent({
    SpeechActivityKind? eventType,
    $fixnum.Int64? timestampMs,
    $core.int? durationMs,
  }) {
    final _result = create();
    if (eventType != null) {
      _result.eventType = eventType;
    }
    if (timestampMs != null) {
      _result.timestampMs = timestampMs;
    }
    if (durationMs != null) {
      _result.durationMs = durationMs;
    }
    return _result;
  }
  factory SpeechActivityEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SpeechActivityEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SpeechActivityEvent clone() => SpeechActivityEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SpeechActivityEvent copyWith(void Function(SpeechActivityEvent) updates) => super.copyWith((message) => updates(message as SpeechActivityEvent)) as SpeechActivityEvent; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static SpeechActivityEvent create() => SpeechActivityEvent._();
  SpeechActivityEvent createEmptyInstance() => create();
  static $pb.PbList<SpeechActivityEvent> createRepeated() => $pb.PbList<SpeechActivityEvent>();
  @$core.pragma('dart2js:noInline')
  static SpeechActivityEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SpeechActivityEvent>(create);
  static SpeechActivityEvent? _defaultInstance;

  @$pb.TagNumber(1)
  SpeechActivityKind get eventType => $_getN(0);
  @$pb.TagNumber(1)
  set eventType(SpeechActivityKind v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasEventType() => $_has(0);
  @$pb.TagNumber(1)
  void clearEventType() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampMs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampMs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTimestampMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampMs() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get durationMs => $_getIZ(2);
  @$pb.TagNumber(3)
  set durationMs($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDurationMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearDurationMs() => clearField(3);
}

