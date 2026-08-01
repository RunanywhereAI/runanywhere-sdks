// This is a generated file - do not edit.
//
// Generated from diffusion_options.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'diffusion_options.pbenum.dart';
import 'errors.pb.dart' as $0;
import 'model_types.pbenum.dart' as $1;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'diffusion_options.pbenum.dart';

class DiffusionTokenizerSource extends $pb.GeneratedMessage {
  factory DiffusionTokenizerSource({
    DiffusionTokenizerSourceKind? kind,
    $core.String? customPath,
    $core.bool? autoDownload,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (customPath != null) result.customPath = customPath;
    if (autoDownload != null) result.autoDownload = autoDownload;
    return result;
  }

  DiffusionTokenizerSource._();

  factory DiffusionTokenizerSource.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DiffusionTokenizerSource.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DiffusionTokenizerSource',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<DiffusionTokenizerSourceKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: DiffusionTokenizerSourceKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'customPath')
    ..aOB(3, _omitFieldNames ? '' : 'autoDownload')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiffusionTokenizerSource clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiffusionTokenizerSource copyWith(
          void Function(DiffusionTokenizerSource) updates) =>
      super.copyWith((message) => updates(message as DiffusionTokenizerSource))
          as DiffusionTokenizerSource;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiffusionTokenizerSource create() => DiffusionTokenizerSource._();
  @$core.override
  DiffusionTokenizerSource createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DiffusionTokenizerSource getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DiffusionTokenizerSource>(create);
  static DiffusionTokenizerSource? _defaultInstance;

  @$pb.TagNumber(1)
  DiffusionTokenizerSourceKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(DiffusionTokenizerSourceKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get customPath => $_getSZ(1);
  @$pb.TagNumber(2)
  set customPath($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCustomPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearCustomPath() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get autoDownload => $_getBF(2);
  @$pb.TagNumber(3)
  set autoDownload($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAutoDownload() => $_has(2);
  @$pb.TagNumber(3)
  void clearAutoDownload() => $_clearField(3);
}

class DiffusionConfiguration extends $pb.GeneratedMessage {
  factory DiffusionConfiguration({
    DiffusionModelVariant? modelVariant,
    DiffusionTokenizerSource? tokenizerSource,
    $core.bool? enableSafetyChecker,
    $core.int? maxMemoryMb,
    $core.String? modelId,
    $1.InferenceFramework? preferredFramework,
  }) {
    final result = create();
    if (modelVariant != null) result.modelVariant = modelVariant;
    if (tokenizerSource != null) result.tokenizerSource = tokenizerSource;
    if (enableSafetyChecker != null)
      result.enableSafetyChecker = enableSafetyChecker;
    if (maxMemoryMb != null) result.maxMemoryMb = maxMemoryMb;
    if (modelId != null) result.modelId = modelId;
    if (preferredFramework != null)
      result.preferredFramework = preferredFramework;
    return result;
  }

  DiffusionConfiguration._();

  factory DiffusionConfiguration.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DiffusionConfiguration.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DiffusionConfiguration',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<DiffusionModelVariant>(1, _omitFieldNames ? '' : 'modelVariant',
        enumValues: DiffusionModelVariant.values)
    ..aOM<DiffusionTokenizerSource>(2, _omitFieldNames ? '' : 'tokenizerSource',
        subBuilder: DiffusionTokenizerSource.create)
    ..aOB(3, _omitFieldNames ? '' : 'enableSafetyChecker')
    ..aI(4, _omitFieldNames ? '' : 'maxMemoryMb')
    ..aOS(5, _omitFieldNames ? '' : 'modelId')
    ..aE<$1.InferenceFramework>(6, _omitFieldNames ? '' : 'preferredFramework',
        enumValues: $1.InferenceFramework.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiffusionConfiguration clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiffusionConfiguration copyWith(
          void Function(DiffusionConfiguration) updates) =>
      super.copyWith((message) => updates(message as DiffusionConfiguration))
          as DiffusionConfiguration;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiffusionConfiguration create() => DiffusionConfiguration._();
  @$core.override
  DiffusionConfiguration createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DiffusionConfiguration getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DiffusionConfiguration>(create);
  static DiffusionConfiguration? _defaultInstance;

  @$pb.TagNumber(1)
  DiffusionModelVariant get modelVariant => $_getN(0);
  @$pb.TagNumber(1)
  set modelVariant(DiffusionModelVariant value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasModelVariant() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelVariant() => $_clearField(1);

  @$pb.TagNumber(2)
  DiffusionTokenizerSource get tokenizerSource => $_getN(1);
  @$pb.TagNumber(2)
  set tokenizerSource(DiffusionTokenizerSource value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasTokenizerSource() => $_has(1);
  @$pb.TagNumber(2)
  void clearTokenizerSource() => $_clearField(2);
  @$pb.TagNumber(2)
  DiffusionTokenizerSource ensureTokenizerSource() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.bool get enableSafetyChecker => $_getBF(2);
  @$pb.TagNumber(3)
  set enableSafetyChecker($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEnableSafetyChecker() => $_has(2);
  @$pb.TagNumber(3)
  void clearEnableSafetyChecker() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get maxMemoryMb => $_getIZ(3);
  @$pb.TagNumber(4)
  set maxMemoryMb($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMaxMemoryMb() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxMemoryMb() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get modelId => $_getSZ(4);
  @$pb.TagNumber(5)
  set modelId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasModelId() => $_has(4);
  @$pb.TagNumber(5)
  void clearModelId() => $_clearField(5);

  @$pb.TagNumber(6)
  $1.InferenceFramework get preferredFramework => $_getN(5);
  @$pb.TagNumber(6)
  set preferredFramework($1.InferenceFramework value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasPreferredFramework() => $_has(5);
  @$pb.TagNumber(6)
  void clearPreferredFramework() => $_clearField(6);
}

class DiffusionGenerationOptions extends $pb.GeneratedMessage {
  factory DiffusionGenerationOptions({
    $core.String? prompt,
    $core.String? negativePrompt,
    $core.int? width,
    $core.int? height,
    $core.int? steps,
    $core.double? guidanceScale,
    $fixnum.Int64? seed,
    DiffusionScheduler? scheduler,
    DiffusionMode? mode,
    $core.List<$core.int>? inputImage,
    $core.List<$core.int>? maskImage,
    $core.double? denoiseStrength,
    $core.bool? reportIntermediateImages,
    $core.int? progressStride,
    $core.int? inputImageWidth,
    $core.int? inputImageHeight,
    $core.String? inputImageMediaType,
    $core.String? maskImageMediaType,
    $core.int? batchSize,
    $core.bool? returnLatents,
  }) {
    final result = create();
    if (prompt != null) result.prompt = prompt;
    if (negativePrompt != null) result.negativePrompt = negativePrompt;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (steps != null) result.steps = steps;
    if (guidanceScale != null) result.guidanceScale = guidanceScale;
    if (seed != null) result.seed = seed;
    if (scheduler != null) result.scheduler = scheduler;
    if (mode != null) result.mode = mode;
    if (inputImage != null) result.inputImage = inputImage;
    if (maskImage != null) result.maskImage = maskImage;
    if (denoiseStrength != null) result.denoiseStrength = denoiseStrength;
    if (reportIntermediateImages != null)
      result.reportIntermediateImages = reportIntermediateImages;
    if (progressStride != null) result.progressStride = progressStride;
    if (inputImageWidth != null) result.inputImageWidth = inputImageWidth;
    if (inputImageHeight != null) result.inputImageHeight = inputImageHeight;
    if (inputImageMediaType != null)
      result.inputImageMediaType = inputImageMediaType;
    if (maskImageMediaType != null)
      result.maskImageMediaType = maskImageMediaType;
    if (batchSize != null) result.batchSize = batchSize;
    if (returnLatents != null) result.returnLatents = returnLatents;
    return result;
  }

  DiffusionGenerationOptions._();

  factory DiffusionGenerationOptions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DiffusionGenerationOptions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DiffusionGenerationOptions',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'prompt')
    ..aOS(2, _omitFieldNames ? '' : 'negativePrompt')
    ..aI(3, _omitFieldNames ? '' : 'width')
    ..aI(4, _omitFieldNames ? '' : 'height')
    ..aI(5, _omitFieldNames ? '' : 'steps')
    ..aD(6, _omitFieldNames ? '' : 'guidanceScale',
        fieldType: $pb.PbFieldType.OF)
    ..aInt64(7, _omitFieldNames ? '' : 'seed')
    ..aE<DiffusionScheduler>(8, _omitFieldNames ? '' : 'scheduler',
        enumValues: DiffusionScheduler.values)
    ..aE<DiffusionMode>(9, _omitFieldNames ? '' : 'mode',
        enumValues: DiffusionMode.values)
    ..a<$core.List<$core.int>>(
        10, _omitFieldNames ? '' : 'inputImage', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        11, _omitFieldNames ? '' : 'maskImage', $pb.PbFieldType.OY)
    ..aD(12, _omitFieldNames ? '' : 'denoiseStrength',
        fieldType: $pb.PbFieldType.OF)
    ..aOB(13, _omitFieldNames ? '' : 'reportIntermediateImages')
    ..aI(14, _omitFieldNames ? '' : 'progressStride')
    ..aI(15, _omitFieldNames ? '' : 'inputImageWidth')
    ..aI(16, _omitFieldNames ? '' : 'inputImageHeight')
    ..aOS(17, _omitFieldNames ? '' : 'inputImageMediaType')
    ..aOS(18, _omitFieldNames ? '' : 'maskImageMediaType')
    ..aI(19, _omitFieldNames ? '' : 'batchSize')
    ..aOB(20, _omitFieldNames ? '' : 'returnLatents')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiffusionGenerationOptions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiffusionGenerationOptions copyWith(
          void Function(DiffusionGenerationOptions) updates) =>
      super.copyWith(
              (message) => updates(message as DiffusionGenerationOptions))
          as DiffusionGenerationOptions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiffusionGenerationOptions create() => DiffusionGenerationOptions._();
  @$core.override
  DiffusionGenerationOptions createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DiffusionGenerationOptions getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DiffusionGenerationOptions>(create);
  static DiffusionGenerationOptions? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get prompt => $_getSZ(0);
  @$pb.TagNumber(1)
  set prompt($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPrompt() => $_has(0);
  @$pb.TagNumber(1)
  void clearPrompt() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get negativePrompt => $_getSZ(1);
  @$pb.TagNumber(2)
  set negativePrompt($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNegativePrompt() => $_has(1);
  @$pb.TagNumber(2)
  void clearNegativePrompt() => $_clearField(2);

  /// 0 = backend default, for width, height, steps, and guidance_scale.
  @$pb.TagNumber(3)
  $core.int get width => $_getIZ(2);
  @$pb.TagNumber(3)
  set width($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasWidth() => $_has(2);
  @$pb.TagNumber(3)
  void clearWidth() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get height => $_getIZ(3);
  @$pb.TagNumber(4)
  set height($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasHeight() => $_has(3);
  @$pb.TagNumber(4)
  void clearHeight() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get steps => $_getIZ(4);
  @$pb.TagNumber(5)
  set steps($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSteps() => $_has(4);
  @$pb.TagNumber(5)
  void clearSteps() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.double get guidanceScale => $_getN(5);
  @$pb.TagNumber(6)
  set guidanceScale($core.double value) => $_setFloat(5, value);
  @$pb.TagNumber(6)
  $core.bool hasGuidanceScale() => $_has(5);
  @$pb.TagNumber(6)
  void clearGuidanceScale() => $_clearField(6);

  /// -1 = random.
  @$pb.TagNumber(7)
  $fixnum.Int64 get seed => $_getI64(6);
  @$pb.TagNumber(7)
  set seed($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSeed() => $_has(6);
  @$pb.TagNumber(7)
  void clearSeed() => $_clearField(7);

  @$pb.TagNumber(8)
  DiffusionScheduler get scheduler => $_getN(7);
  @$pb.TagNumber(8)
  set scheduler(DiffusionScheduler value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasScheduler() => $_has(7);
  @$pb.TagNumber(8)
  void clearScheduler() => $_clearField(8);

  @$pb.TagNumber(9)
  DiffusionMode get mode => $_getN(8);
  @$pb.TagNumber(9)
  set mode(DiffusionMode value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasMode() => $_has(8);
  @$pb.TagNumber(9)
  void clearMode() => $_clearField(9);

  /// For IMAGE_TO_IMAGE and INPAINTING.
  @$pb.TagNumber(10)
  $core.List<$core.int> get inputImage => $_getN(9);
  @$pb.TagNumber(10)
  set inputImage($core.List<$core.int> value) => $_setBytes(9, value);
  @$pb.TagNumber(10)
  $core.bool hasInputImage() => $_has(9);
  @$pb.TagNumber(10)
  void clearInputImage() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.List<$core.int> get maskImage => $_getN(10);
  @$pb.TagNumber(11)
  set maskImage($core.List<$core.int> value) => $_setBytes(10, value);
  @$pb.TagNumber(11)
  $core.bool hasMaskImage() => $_has(10);
  @$pb.TagNumber(11)
  void clearMaskImage() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.double get denoiseStrength => $_getN(11);
  @$pb.TagNumber(12)
  set denoiseStrength($core.double value) => $_setFloat(11, value);
  @$pb.TagNumber(12)
  $core.bool hasDenoiseStrength() => $_has(11);
  @$pb.TagNumber(12)
  void clearDenoiseStrength() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.bool get reportIntermediateImages => $_getBF(12);
  @$pb.TagNumber(13)
  set reportIntermediateImages($core.bool value) => $_setBool(12, value);
  @$pb.TagNumber(13)
  $core.bool hasReportIntermediateImages() => $_has(12);
  @$pb.TagNumber(13)
  void clearReportIntermediateImages() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.int get progressStride => $_getIZ(13);
  @$pb.TagNumber(14)
  set progressStride($core.int value) => $_setSignedInt32(13, value);
  @$pb.TagNumber(14)
  $core.bool hasProgressStride() => $_has(13);
  @$pb.TagNumber(14)
  void clearProgressStride() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.int get inputImageWidth => $_getIZ(14);
  @$pb.TagNumber(15)
  set inputImageWidth($core.int value) => $_setSignedInt32(14, value);
  @$pb.TagNumber(15)
  $core.bool hasInputImageWidth() => $_has(14);
  @$pb.TagNumber(15)
  void clearInputImageWidth() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.int get inputImageHeight => $_getIZ(15);
  @$pb.TagNumber(16)
  set inputImageHeight($core.int value) => $_setSignedInt32(15, value);
  @$pb.TagNumber(16)
  $core.bool hasInputImageHeight() => $_has(15);
  @$pb.TagNumber(16)
  void clearInputImageHeight() => $_clearField(16);

  @$pb.TagNumber(17)
  $core.String get inputImageMediaType => $_getSZ(16);
  @$pb.TagNumber(17)
  set inputImageMediaType($core.String value) => $_setString(16, value);
  @$pb.TagNumber(17)
  $core.bool hasInputImageMediaType() => $_has(16);
  @$pb.TagNumber(17)
  void clearInputImageMediaType() => $_clearField(17);

  @$pb.TagNumber(18)
  $core.String get maskImageMediaType => $_getSZ(17);
  @$pb.TagNumber(18)
  set maskImageMediaType($core.String value) => $_setString(17, value);
  @$pb.TagNumber(18)
  $core.bool hasMaskImageMediaType() => $_has(17);
  @$pb.TagNumber(18)
  void clearMaskImageMediaType() => $_clearField(18);

  /// 0 = one image.
  @$pb.TagNumber(19)
  $core.int get batchSize => $_getIZ(18);
  @$pb.TagNumber(19)
  set batchSize($core.int value) => $_setSignedInt32(18, value);
  @$pb.TagNumber(19)
  $core.bool hasBatchSize() => $_has(18);
  @$pb.TagNumber(19)
  void clearBatchSize() => $_clearField(19);

  @$pb.TagNumber(20)
  $core.bool get returnLatents => $_getBF(19);
  @$pb.TagNumber(20)
  set returnLatents($core.bool value) => $_setBool(19, value);
  @$pb.TagNumber(20)
  $core.bool hasReturnLatents() => $_has(19);
  @$pb.TagNumber(20)
  void clearReturnLatents() => $_clearField(20);
}

class DiffusionGenerationRequest extends $pb.GeneratedMessage {
  factory DiffusionGenerationRequest({
    $core.String? requestId,
    DiffusionGenerationOptions? options,
    $core.String? modelId,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (options != null) result.options = options;
    if (modelId != null) result.modelId = modelId;
    if (metadata != null) result.metadata.addEntries(metadata);
    return result;
  }

  DiffusionGenerationRequest._();

  factory DiffusionGenerationRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DiffusionGenerationRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DiffusionGenerationRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOM<DiffusionGenerationOptions>(2, _omitFieldNames ? '' : 'options',
        subBuilder: DiffusionGenerationOptions.create)
    ..aOS(3, _omitFieldNames ? '' : 'modelId')
    ..m<$core.String, $core.String>(4, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'DiffusionGenerationRequest.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiffusionGenerationRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiffusionGenerationRequest copyWith(
          void Function(DiffusionGenerationRequest) updates) =>
      super.copyWith(
              (message) => updates(message as DiffusionGenerationRequest))
          as DiffusionGenerationRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiffusionGenerationRequest create() => DiffusionGenerationRequest._();
  @$core.override
  DiffusionGenerationRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DiffusionGenerationRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DiffusionGenerationRequest>(create);
  static DiffusionGenerationRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  DiffusionGenerationOptions get options => $_getN(1);
  @$pb.TagNumber(2)
  set options(DiffusionGenerationOptions value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasOptions() => $_has(1);
  @$pb.TagNumber(2)
  void clearOptions() => $_clearField(2);
  @$pb.TagNumber(2)
  DiffusionGenerationOptions ensureOptions() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.String get modelId => $_getSZ(2);
  @$pb.TagNumber(3)
  set modelId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasModelId() => $_has(2);
  @$pb.TagNumber(3)
  void clearModelId() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(3);
}

class DiffusionProgress extends $pb.GeneratedMessage {
  factory DiffusionProgress({
    $core.double? progressPercent,
    $core.int? currentStep,
    $core.int? totalSteps,
    $core.String? stage,
    $core.List<$core.int>? intermediateImageData,
    $core.int? intermediateImageWidth,
    $core.int? intermediateImageHeight,
    $fixnum.Int64? timestampMs,
    $fixnum.Int64? etaMs,
    $core.String? intermediateImageMediaType,
  }) {
    final result = create();
    if (progressPercent != null) result.progressPercent = progressPercent;
    if (currentStep != null) result.currentStep = currentStep;
    if (totalSteps != null) result.totalSteps = totalSteps;
    if (stage != null) result.stage = stage;
    if (intermediateImageData != null)
      result.intermediateImageData = intermediateImageData;
    if (intermediateImageWidth != null)
      result.intermediateImageWidth = intermediateImageWidth;
    if (intermediateImageHeight != null)
      result.intermediateImageHeight = intermediateImageHeight;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (etaMs != null) result.etaMs = etaMs;
    if (intermediateImageMediaType != null)
      result.intermediateImageMediaType = intermediateImageMediaType;
    return result;
  }

  DiffusionProgress._();

  factory DiffusionProgress.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DiffusionProgress.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DiffusionProgress',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'progressPercent',
        fieldType: $pb.PbFieldType.OF)
    ..aI(2, _omitFieldNames ? '' : 'currentStep')
    ..aI(3, _omitFieldNames ? '' : 'totalSteps')
    ..aOS(4, _omitFieldNames ? '' : 'stage')
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'intermediateImageData', $pb.PbFieldType.OY)
    ..aI(6, _omitFieldNames ? '' : 'intermediateImageWidth')
    ..aI(7, _omitFieldNames ? '' : 'intermediateImageHeight')
    ..aInt64(8, _omitFieldNames ? '' : 'timestampMs')
    ..aInt64(9, _omitFieldNames ? '' : 'etaMs')
    ..aOS(10, _omitFieldNames ? '' : 'intermediateImageMediaType')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiffusionProgress clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiffusionProgress copyWith(void Function(DiffusionProgress) updates) =>
      super.copyWith((message) => updates(message as DiffusionProgress))
          as DiffusionProgress;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiffusionProgress create() => DiffusionProgress._();
  @$core.override
  DiffusionProgress createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DiffusionProgress getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DiffusionProgress>(create);
  static DiffusionProgress? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get progressPercent => $_getN(0);
  @$pb.TagNumber(1)
  set progressPercent($core.double value) => $_setFloat(0, value);
  @$pb.TagNumber(1)
  $core.bool hasProgressPercent() => $_has(0);
  @$pb.TagNumber(1)
  void clearProgressPercent() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get currentStep => $_getIZ(1);
  @$pb.TagNumber(2)
  set currentStep($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCurrentStep() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrentStep() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get totalSteps => $_getIZ(2);
  @$pb.TagNumber(3)
  set totalSteps($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTotalSteps() => $_has(2);
  @$pb.TagNumber(3)
  void clearTotalSteps() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get stage => $_getSZ(3);
  @$pb.TagNumber(4)
  set stage($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasStage() => $_has(3);
  @$pb.TagNumber(4)
  void clearStage() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get intermediateImageData => $_getN(4);
  @$pb.TagNumber(5)
  set intermediateImageData($core.List<$core.int> value) =>
      $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasIntermediateImageData() => $_has(4);
  @$pb.TagNumber(5)
  void clearIntermediateImageData() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get intermediateImageWidth => $_getIZ(5);
  @$pb.TagNumber(6)
  set intermediateImageWidth($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasIntermediateImageWidth() => $_has(5);
  @$pb.TagNumber(6)
  void clearIntermediateImageWidth() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get intermediateImageHeight => $_getIZ(6);
  @$pb.TagNumber(7)
  set intermediateImageHeight($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasIntermediateImageHeight() => $_has(6);
  @$pb.TagNumber(7)
  void clearIntermediateImageHeight() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get timestampMs => $_getI64(7);
  @$pb.TagNumber(8)
  set timestampMs($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasTimestampMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearTimestampMs() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get etaMs => $_getI64(8);
  @$pb.TagNumber(9)
  set etaMs($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasEtaMs() => $_has(8);
  @$pb.TagNumber(9)
  void clearEtaMs() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get intermediateImageMediaType => $_getSZ(9);
  @$pb.TagNumber(10)
  set intermediateImageMediaType($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasIntermediateImageMediaType() => $_has(9);
  @$pb.TagNumber(10)
  void clearIntermediateImageMediaType() => $_clearField(10);
}

class DiffusionResult extends $pb.GeneratedMessage {
  factory DiffusionResult({
    $core.List<$core.int>? imageData,
    $core.int? width,
    $core.int? height,
    $fixnum.Int64? seedUsed,
    $fixnum.Int64? totalTimeMs,
    $core.bool? safetyFlag,
    DiffusionScheduler? usedScheduler,
    $core.String? imageMediaType,
    $core.Iterable<$core.List<$core.int>>? batchImages,
    $core.int? imagesGenerated,
    $0.SDKError? error,
  }) {
    final result = create();
    if (imageData != null) result.imageData = imageData;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (seedUsed != null) result.seedUsed = seedUsed;
    if (totalTimeMs != null) result.totalTimeMs = totalTimeMs;
    if (safetyFlag != null) result.safetyFlag = safetyFlag;
    if (usedScheduler != null) result.usedScheduler = usedScheduler;
    if (imageMediaType != null) result.imageMediaType = imageMediaType;
    if (batchImages != null) result.batchImages.addAll(batchImages);
    if (imagesGenerated != null) result.imagesGenerated = imagesGenerated;
    if (error != null) result.error = error;
    return result;
  }

  DiffusionResult._();

  factory DiffusionResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DiffusionResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DiffusionResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'imageData', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'width')
    ..aI(3, _omitFieldNames ? '' : 'height')
    ..aInt64(4, _omitFieldNames ? '' : 'seedUsed')
    ..aInt64(5, _omitFieldNames ? '' : 'totalTimeMs')
    ..aOB(6, _omitFieldNames ? '' : 'safetyFlag')
    ..aE<DiffusionScheduler>(7, _omitFieldNames ? '' : 'usedScheduler',
        enumValues: DiffusionScheduler.values)
    ..aOS(10, _omitFieldNames ? '' : 'imageMediaType')
    ..p<$core.List<$core.int>>(
        11, _omitFieldNames ? '' : 'batchImages', $pb.PbFieldType.PY)
    ..aI(12, _omitFieldNames ? '' : 'imagesGenerated')
    ..aOM<$0.SDKError>(13, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiffusionResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiffusionResult copyWith(void Function(DiffusionResult) updates) =>
      super.copyWith((message) => updates(message as DiffusionResult))
          as DiffusionResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiffusionResult create() => DiffusionResult._();
  @$core.override
  DiffusionResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DiffusionResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DiffusionResult>(create);
  static DiffusionResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get imageData => $_getN(0);
  @$pb.TagNumber(1)
  set imageData($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasImageData() => $_has(0);
  @$pb.TagNumber(1)
  void clearImageData() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get width => $_getIZ(1);
  @$pb.TagNumber(2)
  set width($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasWidth() => $_has(1);
  @$pb.TagNumber(2)
  void clearWidth() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get height => $_getIZ(2);
  @$pb.TagNumber(3)
  set height($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasHeight() => $_has(2);
  @$pb.TagNumber(3)
  void clearHeight() => $_clearField(3);

  /// The resolved seed, so a run can be reproduced when seed was -1.
  @$pb.TagNumber(4)
  $fixnum.Int64 get seedUsed => $_getI64(3);
  @$pb.TagNumber(4)
  set seedUsed($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSeedUsed() => $_has(3);
  @$pb.TagNumber(4)
  void clearSeedUsed() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get totalTimeMs => $_getI64(4);
  @$pb.TagNumber(5)
  set totalTimeMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTotalTimeMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearTotalTimeMs() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get safetyFlag => $_getBF(5);
  @$pb.TagNumber(6)
  set safetyFlag($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSafetyFlag() => $_has(5);
  @$pb.TagNumber(6)
  void clearSafetyFlag() => $_clearField(6);

  @$pb.TagNumber(7)
  DiffusionScheduler get usedScheduler => $_getN(6);
  @$pb.TagNumber(7)
  set usedScheduler(DiffusionScheduler value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasUsedScheduler() => $_has(6);
  @$pb.TagNumber(7)
  void clearUsedScheduler() => $_clearField(7);

  @$pb.TagNumber(10)
  $core.String get imageMediaType => $_getSZ(7);
  @$pb.TagNumber(10)
  set imageMediaType($core.String value) => $_setString(7, value);
  @$pb.TagNumber(10)
  $core.bool hasImageMediaType() => $_has(7);
  @$pb.TagNumber(10)
  void clearImageMediaType() => $_clearField(10);

  @$pb.TagNumber(11)
  $pb.PbList<$core.List<$core.int>> get batchImages => $_getList(8);

  @$pb.TagNumber(12)
  $core.int get imagesGenerated => $_getIZ(9);
  @$pb.TagNumber(12)
  set imagesGenerated($core.int value) => $_setSignedInt32(9, value);
  @$pb.TagNumber(12)
  $core.bool hasImagesGenerated() => $_has(9);
  @$pb.TagNumber(12)
  void clearImagesGenerated() => $_clearField(12);

  @$pb.TagNumber(13)
  $0.SDKError get error => $_getN(10);
  @$pb.TagNumber(13)
  set error($0.SDKError value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasError() => $_has(10);
  @$pb.TagNumber(13)
  void clearError() => $_clearField(13);
  @$pb.TagNumber(13)
  $0.SDKError ensureError() => $_ensure(10);
}

class DiffusionStreamEvent extends $pb.GeneratedMessage {
  factory DiffusionStreamEvent({
    $fixnum.Int64? timestampUs,
    $core.String? requestId,
    DiffusionStreamEventKind? kind,
    DiffusionProgress? progress,
    DiffusionResult? result,
    $0.SDKError? error,
  }) {
    final result$ = create();
    if (timestampUs != null) result$.timestampUs = timestampUs;
    if (requestId != null) result$.requestId = requestId;
    if (kind != null) result$.kind = kind;
    if (progress != null) result$.progress = progress;
    if (result != null) result$.result = result;
    if (error != null) result$.error = error;
    return result$;
  }

  DiffusionStreamEvent._();

  factory DiffusionStreamEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DiffusionStreamEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DiffusionStreamEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(3, _omitFieldNames ? '' : 'requestId')
    ..aE<DiffusionStreamEventKind>(4, _omitFieldNames ? '' : 'kind',
        enumValues: DiffusionStreamEventKind.values)
    ..aOM<DiffusionProgress>(5, _omitFieldNames ? '' : 'progress',
        subBuilder: DiffusionProgress.create)
    ..aOM<DiffusionResult>(6, _omitFieldNames ? '' : 'result',
        subBuilder: DiffusionResult.create)
    ..aOM<$0.SDKError>(9, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiffusionStreamEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiffusionStreamEvent copyWith(void Function(DiffusionStreamEvent) updates) =>
      super.copyWith((message) => updates(message as DiffusionStreamEvent))
          as DiffusionStreamEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiffusionStreamEvent create() => DiffusionStreamEvent._();
  @$core.override
  DiffusionStreamEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DiffusionStreamEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DiffusionStreamEvent>(create);
  static DiffusionStreamEvent? _defaultInstance;

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampUs => $_getI64(0);
  @$pb.TagNumber(2)
  set timestampUs($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestampUs() => $_has(0);
  @$pb.TagNumber(2)
  void clearTimestampUs() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get requestId => $_getSZ(1);
  @$pb.TagNumber(3)
  set requestId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(3)
  $core.bool hasRequestId() => $_has(1);
  @$pb.TagNumber(3)
  void clearRequestId() => $_clearField(3);

  @$pb.TagNumber(4)
  DiffusionStreamEventKind get kind => $_getN(2);
  @$pb.TagNumber(4)
  set kind(DiffusionStreamEventKind value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasKind() => $_has(2);
  @$pb.TagNumber(4)
  void clearKind() => $_clearField(4);

  @$pb.TagNumber(5)
  DiffusionProgress get progress => $_getN(3);
  @$pb.TagNumber(5)
  set progress(DiffusionProgress value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasProgress() => $_has(3);
  @$pb.TagNumber(5)
  void clearProgress() => $_clearField(5);
  @$pb.TagNumber(5)
  DiffusionProgress ensureProgress() => $_ensure(3);

  @$pb.TagNumber(6)
  DiffusionResult get result => $_getN(4);
  @$pb.TagNumber(6)
  set result(DiffusionResult value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasResult() => $_has(4);
  @$pb.TagNumber(6)
  void clearResult() => $_clearField(6);
  @$pb.TagNumber(6)
  DiffusionResult ensureResult() => $_ensure(4);

  @$pb.TagNumber(9)
  $0.SDKError get error => $_getN(5);
  @$pb.TagNumber(9)
  set error($0.SDKError value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(9)
  void clearError() => $_clearField(9);
  @$pb.TagNumber(9)
  $0.SDKError ensureError() => $_ensure(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
