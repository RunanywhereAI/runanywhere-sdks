///
//  Generated code. Do not modify.
//  source: diffusion_options.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'diffusion_options.pbenum.dart';

export 'diffusion_options.pbenum.dart';

class DiffusionTokenizerSource extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'DiffusionTokenizerSource', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<DiffusionTokenizerSourceKind>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: DiffusionTokenizerSourceKind.DIFFUSION_TOKENIZER_SOURCE_KIND_UNSPECIFIED, valueOf: DiffusionTokenizerSourceKind.valueOf, enumValues: DiffusionTokenizerSourceKind.values)
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'customPath')
    ..hasRequiredFields = false
  ;

  DiffusionTokenizerSource._() : super();
  factory DiffusionTokenizerSource({
    DiffusionTokenizerSourceKind? kind,
    $core.String? customPath,
  }) {
    final _result = create();
    if (kind != null) {
      _result.kind = kind;
    }
    if (customPath != null) {
      _result.customPath = customPath;
    }
    return _result;
  }
  factory DiffusionTokenizerSource.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DiffusionTokenizerSource.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DiffusionTokenizerSource clone() => DiffusionTokenizerSource()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DiffusionTokenizerSource copyWith(void Function(DiffusionTokenizerSource) updates) => super.copyWith((message) => updates(message as DiffusionTokenizerSource)) as DiffusionTokenizerSource; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static DiffusionTokenizerSource create() => DiffusionTokenizerSource._();
  DiffusionTokenizerSource createEmptyInstance() => create();
  static $pb.PbList<DiffusionTokenizerSource> createRepeated() => $pb.PbList<DiffusionTokenizerSource>();
  @$core.pragma('dart2js:noInline')
  static DiffusionTokenizerSource getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DiffusionTokenizerSource>(create);
  static DiffusionTokenizerSource? _defaultInstance;

  @$pb.TagNumber(1)
  DiffusionTokenizerSourceKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(DiffusionTokenizerSourceKind v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get customPath => $_getSZ(1);
  @$pb.TagNumber(2)
  set customPath($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCustomPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearCustomPath() => clearField(2);
}

class DiffusionConfiguration extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'DiffusionConfiguration', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<DiffusionModelVariant>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'modelVariant', $pb.PbFieldType.OE, defaultOrMaker: DiffusionModelVariant.DIFFUSION_MODEL_VARIANT_UNSPECIFIED, valueOf: DiffusionModelVariant.valueOf, enumValues: DiffusionModelVariant.values)
    ..aOM<DiffusionTokenizerSource>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'tokenizerSource', subBuilder: DiffusionTokenizerSource.create)
    ..aOB(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'enableSafetyChecker')
    ..a<$core.int>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'maxMemoryMb', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  DiffusionConfiguration._() : super();
  factory DiffusionConfiguration({
    DiffusionModelVariant? modelVariant,
    DiffusionTokenizerSource? tokenizerSource,
    $core.bool? enableSafetyChecker,
    $core.int? maxMemoryMb,
  }) {
    final _result = create();
    if (modelVariant != null) {
      _result.modelVariant = modelVariant;
    }
    if (tokenizerSource != null) {
      _result.tokenizerSource = tokenizerSource;
    }
    if (enableSafetyChecker != null) {
      _result.enableSafetyChecker = enableSafetyChecker;
    }
    if (maxMemoryMb != null) {
      _result.maxMemoryMb = maxMemoryMb;
    }
    return _result;
  }
  factory DiffusionConfiguration.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DiffusionConfiguration.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DiffusionConfiguration clone() => DiffusionConfiguration()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DiffusionConfiguration copyWith(void Function(DiffusionConfiguration) updates) => super.copyWith((message) => updates(message as DiffusionConfiguration)) as DiffusionConfiguration; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static DiffusionConfiguration create() => DiffusionConfiguration._();
  DiffusionConfiguration createEmptyInstance() => create();
  static $pb.PbList<DiffusionConfiguration> createRepeated() => $pb.PbList<DiffusionConfiguration>();
  @$core.pragma('dart2js:noInline')
  static DiffusionConfiguration getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DiffusionConfiguration>(create);
  static DiffusionConfiguration? _defaultInstance;

  @$pb.TagNumber(1)
  DiffusionModelVariant get modelVariant => $_getN(0);
  @$pb.TagNumber(1)
  set modelVariant(DiffusionModelVariant v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelVariant() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelVariant() => clearField(1);

  @$pb.TagNumber(2)
  DiffusionTokenizerSource get tokenizerSource => $_getN(1);
  @$pb.TagNumber(2)
  set tokenizerSource(DiffusionTokenizerSource v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasTokenizerSource() => $_has(1);
  @$pb.TagNumber(2)
  void clearTokenizerSource() => clearField(2);
  @$pb.TagNumber(2)
  DiffusionTokenizerSource ensureTokenizerSource() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.bool get enableSafetyChecker => $_getBF(2);
  @$pb.TagNumber(3)
  set enableSafetyChecker($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasEnableSafetyChecker() => $_has(2);
  @$pb.TagNumber(3)
  void clearEnableSafetyChecker() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get maxMemoryMb => $_getIZ(3);
  @$pb.TagNumber(4)
  set maxMemoryMb($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasMaxMemoryMb() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxMemoryMb() => clearField(4);
}

class DiffusionGenerationOptions extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'DiffusionGenerationOptions', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'prompt')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'negativePrompt')
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'width', $pb.PbFieldType.O3)
    ..a<$core.int>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'height', $pb.PbFieldType.O3)
    ..a<$core.int>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'numInferenceSteps', $pb.PbFieldType.O3)
    ..a<$core.double>(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'guidanceScale', $pb.PbFieldType.OF)
    ..aInt64(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'seed')
    ..e<DiffusionScheduler>(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'scheduler', $pb.PbFieldType.OE, defaultOrMaker: DiffusionScheduler.DIFFUSION_SCHEDULER_UNSPECIFIED, valueOf: DiffusionScheduler.valueOf, enumValues: DiffusionScheduler.values)
    ..e<DiffusionMode>(9, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'mode', $pb.PbFieldType.OE, defaultOrMaker: DiffusionMode.DIFFUSION_MODE_UNSPECIFIED, valueOf: DiffusionMode.valueOf, enumValues: DiffusionMode.values)
    ..hasRequiredFields = false
  ;

  DiffusionGenerationOptions._() : super();
  factory DiffusionGenerationOptions({
    $core.String? prompt,
    $core.String? negativePrompt,
    $core.int? width,
    $core.int? height,
    $core.int? numInferenceSteps,
    $core.double? guidanceScale,
    $fixnum.Int64? seed,
    DiffusionScheduler? scheduler,
    DiffusionMode? mode,
  }) {
    final _result = create();
    if (prompt != null) {
      _result.prompt = prompt;
    }
    if (negativePrompt != null) {
      _result.negativePrompt = negativePrompt;
    }
    if (width != null) {
      _result.width = width;
    }
    if (height != null) {
      _result.height = height;
    }
    if (numInferenceSteps != null) {
      _result.numInferenceSteps = numInferenceSteps;
    }
    if (guidanceScale != null) {
      _result.guidanceScale = guidanceScale;
    }
    if (seed != null) {
      _result.seed = seed;
    }
    if (scheduler != null) {
      _result.scheduler = scheduler;
    }
    if (mode != null) {
      _result.mode = mode;
    }
    return _result;
  }
  factory DiffusionGenerationOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DiffusionGenerationOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DiffusionGenerationOptions clone() => DiffusionGenerationOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DiffusionGenerationOptions copyWith(void Function(DiffusionGenerationOptions) updates) => super.copyWith((message) => updates(message as DiffusionGenerationOptions)) as DiffusionGenerationOptions; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static DiffusionGenerationOptions create() => DiffusionGenerationOptions._();
  DiffusionGenerationOptions createEmptyInstance() => create();
  static $pb.PbList<DiffusionGenerationOptions> createRepeated() => $pb.PbList<DiffusionGenerationOptions>();
  @$core.pragma('dart2js:noInline')
  static DiffusionGenerationOptions getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DiffusionGenerationOptions>(create);
  static DiffusionGenerationOptions? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get prompt => $_getSZ(0);
  @$pb.TagNumber(1)
  set prompt($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPrompt() => $_has(0);
  @$pb.TagNumber(1)
  void clearPrompt() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get negativePrompt => $_getSZ(1);
  @$pb.TagNumber(2)
  set negativePrompt($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasNegativePrompt() => $_has(1);
  @$pb.TagNumber(2)
  void clearNegativePrompt() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get width => $_getIZ(2);
  @$pb.TagNumber(3)
  set width($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasWidth() => $_has(2);
  @$pb.TagNumber(3)
  void clearWidth() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get height => $_getIZ(3);
  @$pb.TagNumber(4)
  set height($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasHeight() => $_has(3);
  @$pb.TagNumber(4)
  void clearHeight() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get numInferenceSteps => $_getIZ(4);
  @$pb.TagNumber(5)
  set numInferenceSteps($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasNumInferenceSteps() => $_has(4);
  @$pb.TagNumber(5)
  void clearNumInferenceSteps() => clearField(5);

  @$pb.TagNumber(6)
  $core.double get guidanceScale => $_getN(5);
  @$pb.TagNumber(6)
  set guidanceScale($core.double v) { $_setFloat(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasGuidanceScale() => $_has(5);
  @$pb.TagNumber(6)
  void clearGuidanceScale() => clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get seed => $_getI64(6);
  @$pb.TagNumber(7)
  set seed($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasSeed() => $_has(6);
  @$pb.TagNumber(7)
  void clearSeed() => clearField(7);

  @$pb.TagNumber(8)
  DiffusionScheduler get scheduler => $_getN(7);
  @$pb.TagNumber(8)
  set scheduler(DiffusionScheduler v) { setField(8, v); }
  @$pb.TagNumber(8)
  $core.bool hasScheduler() => $_has(7);
  @$pb.TagNumber(8)
  void clearScheduler() => clearField(8);

  @$pb.TagNumber(9)
  DiffusionMode get mode => $_getN(8);
  @$pb.TagNumber(9)
  set mode(DiffusionMode v) { setField(9, v); }
  @$pb.TagNumber(9)
  $core.bool hasMode() => $_has(8);
  @$pb.TagNumber(9)
  void clearMode() => clearField(9);
}

class DiffusionProgress extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'DiffusionProgress', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.double>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'progressPercent', $pb.PbFieldType.OF)
    ..a<$core.int>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'currentStep', $pb.PbFieldType.O3)
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'totalSteps', $pb.PbFieldType.O3)
    ..aOS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'stage')
    ..a<$core.List<$core.int>>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'intermediateImageData', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  DiffusionProgress._() : super();
  factory DiffusionProgress({
    $core.double? progressPercent,
    $core.int? currentStep,
    $core.int? totalSteps,
    $core.String? stage,
    $core.List<$core.int>? intermediateImageData,
  }) {
    final _result = create();
    if (progressPercent != null) {
      _result.progressPercent = progressPercent;
    }
    if (currentStep != null) {
      _result.currentStep = currentStep;
    }
    if (totalSteps != null) {
      _result.totalSteps = totalSteps;
    }
    if (stage != null) {
      _result.stage = stage;
    }
    if (intermediateImageData != null) {
      _result.intermediateImageData = intermediateImageData;
    }
    return _result;
  }
  factory DiffusionProgress.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DiffusionProgress.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DiffusionProgress clone() => DiffusionProgress()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DiffusionProgress copyWith(void Function(DiffusionProgress) updates) => super.copyWith((message) => updates(message as DiffusionProgress)) as DiffusionProgress; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static DiffusionProgress create() => DiffusionProgress._();
  DiffusionProgress createEmptyInstance() => create();
  static $pb.PbList<DiffusionProgress> createRepeated() => $pb.PbList<DiffusionProgress>();
  @$core.pragma('dart2js:noInline')
  static DiffusionProgress getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DiffusionProgress>(create);
  static DiffusionProgress? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get progressPercent => $_getN(0);
  @$pb.TagNumber(1)
  set progressPercent($core.double v) { $_setFloat(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasProgressPercent() => $_has(0);
  @$pb.TagNumber(1)
  void clearProgressPercent() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get currentStep => $_getIZ(1);
  @$pb.TagNumber(2)
  set currentStep($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCurrentStep() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrentStep() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get totalSteps => $_getIZ(2);
  @$pb.TagNumber(3)
  set totalSteps($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTotalSteps() => $_has(2);
  @$pb.TagNumber(3)
  void clearTotalSteps() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get stage => $_getSZ(3);
  @$pb.TagNumber(4)
  set stage($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasStage() => $_has(3);
  @$pb.TagNumber(4)
  void clearStage() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get intermediateImageData => $_getN(4);
  @$pb.TagNumber(5)
  set intermediateImageData($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasIntermediateImageData() => $_has(4);
  @$pb.TagNumber(5)
  void clearIntermediateImageData() => clearField(5);
}

class DiffusionResult extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'DiffusionResult', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'imageData', $pb.PbFieldType.OY)
    ..a<$core.int>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'width', $pb.PbFieldType.O3)
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'height', $pb.PbFieldType.O3)
    ..aInt64(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'seedUsed')
    ..aInt64(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'totalTimeMs')
    ..aOB(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'safetyFlag')
    ..e<DiffusionScheduler>(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'usedScheduler', $pb.PbFieldType.OE, defaultOrMaker: DiffusionScheduler.DIFFUSION_SCHEDULER_UNSPECIFIED, valueOf: DiffusionScheduler.valueOf, enumValues: DiffusionScheduler.values)
    ..hasRequiredFields = false
  ;

  DiffusionResult._() : super();
  factory DiffusionResult({
    $core.List<$core.int>? imageData,
    $core.int? width,
    $core.int? height,
    $fixnum.Int64? seedUsed,
    $fixnum.Int64? totalTimeMs,
    $core.bool? safetyFlag,
    DiffusionScheduler? usedScheduler,
  }) {
    final _result = create();
    if (imageData != null) {
      _result.imageData = imageData;
    }
    if (width != null) {
      _result.width = width;
    }
    if (height != null) {
      _result.height = height;
    }
    if (seedUsed != null) {
      _result.seedUsed = seedUsed;
    }
    if (totalTimeMs != null) {
      _result.totalTimeMs = totalTimeMs;
    }
    if (safetyFlag != null) {
      _result.safetyFlag = safetyFlag;
    }
    if (usedScheduler != null) {
      _result.usedScheduler = usedScheduler;
    }
    return _result;
  }
  factory DiffusionResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DiffusionResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DiffusionResult clone() => DiffusionResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DiffusionResult copyWith(void Function(DiffusionResult) updates) => super.copyWith((message) => updates(message as DiffusionResult)) as DiffusionResult; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static DiffusionResult create() => DiffusionResult._();
  DiffusionResult createEmptyInstance() => create();
  static $pb.PbList<DiffusionResult> createRepeated() => $pb.PbList<DiffusionResult>();
  @$core.pragma('dart2js:noInline')
  static DiffusionResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DiffusionResult>(create);
  static DiffusionResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get imageData => $_getN(0);
  @$pb.TagNumber(1)
  set imageData($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasImageData() => $_has(0);
  @$pb.TagNumber(1)
  void clearImageData() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get width => $_getIZ(1);
  @$pb.TagNumber(2)
  set width($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasWidth() => $_has(1);
  @$pb.TagNumber(2)
  void clearWidth() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get height => $_getIZ(2);
  @$pb.TagNumber(3)
  set height($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasHeight() => $_has(2);
  @$pb.TagNumber(3)
  void clearHeight() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get seedUsed => $_getI64(3);
  @$pb.TagNumber(4)
  set seedUsed($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSeedUsed() => $_has(3);
  @$pb.TagNumber(4)
  void clearSeedUsed() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get totalTimeMs => $_getI64(4);
  @$pb.TagNumber(5)
  set totalTimeMs($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasTotalTimeMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearTotalTimeMs() => clearField(5);

  @$pb.TagNumber(6)
  $core.bool get safetyFlag => $_getBF(5);
  @$pb.TagNumber(6)
  set safetyFlag($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasSafetyFlag() => $_has(5);
  @$pb.TagNumber(6)
  void clearSafetyFlag() => clearField(6);

  @$pb.TagNumber(7)
  DiffusionScheduler get usedScheduler => $_getN(6);
  @$pb.TagNumber(7)
  set usedScheduler(DiffusionScheduler v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasUsedScheduler() => $_has(6);
  @$pb.TagNumber(7)
  void clearUsedScheduler() => clearField(7);
}

class DiffusionCapabilities extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'DiffusionCapabilities', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pc<DiffusionModelVariant>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'supportedVariants', $pb.PbFieldType.KE, valueOf: DiffusionModelVariant.valueOf, enumValues: DiffusionModelVariant.values, defaultEnumValue: DiffusionModelVariant.DIFFUSION_MODEL_VARIANT_UNSPECIFIED)
    ..pc<DiffusionScheduler>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'supportedSchedulers', $pb.PbFieldType.KE, valueOf: DiffusionScheduler.valueOf, enumValues: DiffusionScheduler.values, defaultEnumValue: DiffusionScheduler.DIFFUSION_SCHEDULER_UNSPECIFIED)
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'maxResolutionPx', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  DiffusionCapabilities._() : super();
  factory DiffusionCapabilities({
    $core.Iterable<DiffusionModelVariant>? supportedVariants,
    $core.Iterable<DiffusionScheduler>? supportedSchedulers,
    $core.int? maxResolutionPx,
  }) {
    final _result = create();
    if (supportedVariants != null) {
      _result.supportedVariants.addAll(supportedVariants);
    }
    if (supportedSchedulers != null) {
      _result.supportedSchedulers.addAll(supportedSchedulers);
    }
    if (maxResolutionPx != null) {
      _result.maxResolutionPx = maxResolutionPx;
    }
    return _result;
  }
  factory DiffusionCapabilities.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DiffusionCapabilities.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DiffusionCapabilities clone() => DiffusionCapabilities()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DiffusionCapabilities copyWith(void Function(DiffusionCapabilities) updates) => super.copyWith((message) => updates(message as DiffusionCapabilities)) as DiffusionCapabilities; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static DiffusionCapabilities create() => DiffusionCapabilities._();
  DiffusionCapabilities createEmptyInstance() => create();
  static $pb.PbList<DiffusionCapabilities> createRepeated() => $pb.PbList<DiffusionCapabilities>();
  @$core.pragma('dart2js:noInline')
  static DiffusionCapabilities getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DiffusionCapabilities>(create);
  static DiffusionCapabilities? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<DiffusionModelVariant> get supportedVariants => $_getList(0);

  @$pb.TagNumber(2)
  $core.List<DiffusionScheduler> get supportedSchedulers => $_getList(1);

  @$pb.TagNumber(3)
  $core.int get maxResolutionPx => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxResolutionPx($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMaxResolutionPx() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxResolutionPx() => clearField(3);
}

