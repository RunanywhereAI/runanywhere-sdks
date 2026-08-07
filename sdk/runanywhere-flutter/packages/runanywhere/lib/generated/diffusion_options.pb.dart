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

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'diffusion_options.pbenum.dart';

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
    $core.List<$core.int>? image,
    $core.List<$core.int>? maskImage,
    $core.double? strength,
    $core.String? imageMediaType,
    $core.String? maskImageMediaType,
    $core.int? n,
    DiffusionOutputFormat? outputFormat,
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
    if (image != null) result.image = image;
    if (maskImage != null) result.maskImage = maskImage;
    if (strength != null) result.strength = strength;
    if (imageMediaType != null) result.imageMediaType = imageMediaType;
    if (maskImageMediaType != null)
      result.maskImageMediaType = maskImageMediaType;
    if (n != null) result.n = n;
    if (outputFormat != null) result.outputFormat = outputFormat;
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
    ..a<$core.List<$core.int>>(
        9, _omitFieldNames ? '' : 'image', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        10, _omitFieldNames ? '' : 'maskImage', $pb.PbFieldType.OY)
    ..aD(11, _omitFieldNames ? '' : 'strength', fieldType: $pb.PbFieldType.OF)
    ..aOS(12, _omitFieldNames ? '' : 'imageMediaType')
    ..aOS(13, _omitFieldNames ? '' : 'maskImageMediaType')
    ..aI(14, _omitFieldNames ? '' : 'n')
    ..aE<DiffusionOutputFormat>(15, _omitFieldNames ? '' : 'outputFormat',
        enumValues: DiffusionOutputFormat.values)
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

  /// Absent = pick a fresh random seed. Any present value is literal,
  /// including 0. The seed actually used comes back on each result image.
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

  /// Source picture. Its presence promotes the request to image-to-image;
  /// adding `mask_image` promotes it to inpainting. Must be an encoded
  /// PNG or JPEG container.
  @$pb.TagNumber(9)
  $core.List<$core.int> get image => $_getN(8);
  @$pb.TagNumber(9)
  set image($core.List<$core.int> value) => $_setBytes(8, value);
  @$pb.TagNumber(9)
  $core.bool hasImage() => $_has(8);
  @$pb.TagNumber(9)
  void clearImage() => $_clearField(9);

  /// White = repaint. Same dimensions as `image`.
  @$pb.TagNumber(10)
  $core.List<$core.int> get maskImage => $_getN(9);
  @$pb.TagNumber(10)
  set maskImage($core.List<$core.int> value) => $_setBytes(9, value);
  @$pb.TagNumber(10)
  $core.bool hasMaskImage() => $_has(9);
  @$pb.TagNumber(10)
  void clearMaskImage() => $_clearField(10);

  /// How far from the source image to travel. Only meaningful with `image`.
  /// Effective steps = ceil(steps * strength), so a low value is
  /// proportionally cheaper -- on device that is battery.
  @$pb.TagNumber(11)
  $core.double get strength => $_getN(10);
  @$pb.TagNumber(11)
  set strength($core.double value) => $_setFloat(10, value);
  @$pb.TagNumber(11)
  $core.bool hasStrength() => $_has(10);
  @$pb.TagNumber(11)
  void clearStrength() => $_clearField(11);

  /// Container of the bytes above, as supplied by the caller. Request-side;
  /// the result carries its own media type per image.
  @$pb.TagNumber(12)
  $core.String get imageMediaType => $_getSZ(11);
  @$pb.TagNumber(12)
  set imageMediaType($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasImageMediaType() => $_has(11);
  @$pb.TagNumber(12)
  void clearImageMediaType() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get maskImageMediaType => $_getSZ(12);
  @$pb.TagNumber(13)
  set maskImageMediaType($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasMaskImageMediaType() => $_has(12);
  @$pb.TagNumber(13)
  void clearMaskImageMediaType() => $_clearField(13);

  /// How many images to generate for this prompt. Absent = 1.
  @$pb.TagNumber(14)
  $core.int get n => $_getIZ(13);
  @$pb.TagNumber(14)
  set n($core.int value) => $_setSignedInt32(13, value);
  @$pb.TagNumber(14)
  $core.bool hasN() => $_has(13);
  @$pb.TagNumber(14)
  void clearN() => $_clearField(14);

  /// Encoding of the returned image bytes.
  @$pb.TagNumber(15)
  DiffusionOutputFormat get outputFormat => $_getN(14);
  @$pb.TagNumber(15)
  set outputFormat(DiffusionOutputFormat value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasOutputFormat() => $_has(14);
  @$pb.TagNumber(15)
  void clearOutputFormat() => $_clearField(15);
}

class DiffusionGenerationRequest extends $pb.GeneratedMessage {
  factory DiffusionGenerationRequest({
    DiffusionGenerationOptions? options,
    $core.String? modelId,
  }) {
    final result = create();
    if (options != null) result.options = options;
    if (modelId != null) result.modelId = modelId;
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
    ..aOM<DiffusionGenerationOptions>(1, _omitFieldNames ? '' : 'options',
        subBuilder: DiffusionGenerationOptions.create)
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
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
  DiffusionGenerationOptions get options => $_getN(0);
  @$pb.TagNumber(1)
  set options(DiffusionGenerationOptions value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasOptions() => $_has(0);
  @$pb.TagNumber(1)
  void clearOptions() => $_clearField(1);
  @$pb.TagNumber(1)
  DiffusionGenerationOptions ensureOptions() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => $_clearField(2);
}

class DiffusionProgress extends $pb.GeneratedMessage {
  factory DiffusionProgress({
    $core.int? currentStep,
    $core.int? totalSteps,
    $core.List<$core.int>? intermediateImageData,
  }) {
    final result = create();
    if (currentStep != null) result.currentStep = currentStep;
    if (totalSteps != null) result.totalSteps = totalSteps;
    if (intermediateImageData != null)
      result.intermediateImageData = intermediateImageData;
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
    ..aI(1, _omitFieldNames ? '' : 'currentStep')
    ..aI(2, _omitFieldNames ? '' : 'totalSteps')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'intermediateImageData', $pb.PbFieldType.OY)
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
  $core.int get currentStep => $_getIZ(0);
  @$pb.TagNumber(1)
  set currentStep($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCurrentStep() => $_has(0);
  @$pb.TagNumber(1)
  void clearCurrentStep() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get totalSteps => $_getIZ(1);
  @$pb.TagNumber(2)
  set totalSteps($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTotalSteps() => $_has(1);
  @$pb.TagNumber(2)
  void clearTotalSteps() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get intermediateImageData => $_getN(2);
  @$pb.TagNumber(3)
  set intermediateImageData($core.List<$core.int> value) =>
      $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIntermediateImageData() => $_has(2);
  @$pb.TagNumber(3)
  void clearIntermediateImageData() => $_clearField(3);
}

/// One generated image. Per-image, because with n > 1 each image has its
/// own seed and its own safety verdict (Stability `seeds`/`finish_reasons`,
/// Diffusers `nsfw_content_detected`).
class DiffusionImage extends $pb.GeneratedMessage {
  factory DiffusionImage({
    $core.List<$core.int>? data,
    $core.int? width,
    $core.int? height,
    $fixnum.Int64? seedUsed,
    $core.bool? safetyFlag,
    $core.String? mediaType,
  }) {
    final result = create();
    if (data != null) result.data = data;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (seedUsed != null) result.seedUsed = seedUsed;
    if (safetyFlag != null) result.safetyFlag = safetyFlag;
    if (mediaType != null) result.mediaType = mediaType;
    return result;
  }

  DiffusionImage._();

  factory DiffusionImage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DiffusionImage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DiffusionImage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'width')
    ..aI(3, _omitFieldNames ? '' : 'height')
    ..aInt64(4, _omitFieldNames ? '' : 'seedUsed')
    ..aOB(5, _omitFieldNames ? '' : 'safetyFlag')
    ..aOS(6, _omitFieldNames ? '' : 'mediaType')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiffusionImage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiffusionImage copyWith(void Function(DiffusionImage) updates) =>
      super.copyWith((message) => updates(message as DiffusionImage))
          as DiffusionImage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiffusionImage create() => DiffusionImage._();
  @$core.override
  DiffusionImage createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DiffusionImage getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DiffusionImage>(create);
  static DiffusionImage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);

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

  @$pb.TagNumber(4)
  $fixnum.Int64 get seedUsed => $_getI64(3);
  @$pb.TagNumber(4)
  set seedUsed($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSeedUsed() => $_has(3);
  @$pb.TagNumber(4)
  void clearSeedUsed() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get safetyFlag => $_getBF(4);
  @$pb.TagNumber(5)
  set safetyFlag($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSafetyFlag() => $_has(4);
  @$pb.TagNumber(5)
  void clearSafetyFlag() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get mediaType => $_getSZ(5);
  @$pb.TagNumber(6)
  set mediaType($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMediaType() => $_has(5);
  @$pb.TagNumber(6)
  void clearMediaType() => $_clearField(6);
}

class DiffusionResult extends $pb.GeneratedMessage {
  factory DiffusionResult({
    $core.Iterable<DiffusionImage>? images,
    $fixnum.Int64? totalTimeMs,
  }) {
    final result = create();
    if (images != null) result.images.addAll(images);
    if (totalTimeMs != null) result.totalTimeMs = totalTimeMs;
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
    ..pPM<DiffusionImage>(1, _omitFieldNames ? '' : 'images',
        subBuilder: DiffusionImage.create)
    ..aInt64(2, _omitFieldNames ? '' : 'totalTimeMs')
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

  /// One entry per requested image, in request order. commons emits exactly
  /// one entry until the C ABI grows a list: rac_diffusion_result_t is a
  /// single-image struct with one image_data/image_size pair.
  @$pb.TagNumber(1)
  $pb.PbList<DiffusionImage> get images => $_getList(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get totalTimeMs => $_getI64(1);
  @$pb.TagNumber(2)
  set totalTimeMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTotalTimeMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTotalTimeMs() => $_clearField(2);
}

class DiffusionStreamEvent extends $pb.GeneratedMessage {
  factory DiffusionStreamEvent({
    $fixnum.Int64? timestampUs,
    DiffusionStreamEventKind? kind,
    DiffusionProgress? progress,
    DiffusionResult? result,
    $0.SDKError? error,
  }) {
    final result$ = create();
    if (timestampUs != null) result$.timestampUs = timestampUs;
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
    ..aInt64(1, _omitFieldNames ? '' : 'timestampUs')
    ..aE<DiffusionStreamEventKind>(2, _omitFieldNames ? '' : 'kind',
        enumValues: DiffusionStreamEventKind.values)
    ..aOM<DiffusionProgress>(3, _omitFieldNames ? '' : 'progress',
        subBuilder: DiffusionProgress.create)
    ..aOM<DiffusionResult>(4, _omitFieldNames ? '' : 'result',
        subBuilder: DiffusionResult.create)
    ..aOM<$0.SDKError>(5, _omitFieldNames ? '' : 'error',
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

  /// Generation is single-flight, so the stream itself is the correlation.
  @$pb.TagNumber(1)
  $fixnum.Int64 get timestampUs => $_getI64(0);
  @$pb.TagNumber(1)
  set timestampUs($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTimestampUs() => $_has(0);
  @$pb.TagNumber(1)
  void clearTimestampUs() => $_clearField(1);

  @$pb.TagNumber(2)
  DiffusionStreamEventKind get kind => $_getN(1);
  @$pb.TagNumber(2)
  set kind(DiffusionStreamEventKind value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasKind() => $_has(1);
  @$pb.TagNumber(2)
  void clearKind() => $_clearField(2);

  @$pb.TagNumber(3)
  DiffusionProgress get progress => $_getN(2);
  @$pb.TagNumber(3)
  set progress(DiffusionProgress value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasProgress() => $_has(2);
  @$pb.TagNumber(3)
  void clearProgress() => $_clearField(3);
  @$pb.TagNumber(3)
  DiffusionProgress ensureProgress() => $_ensure(2);

  @$pb.TagNumber(4)
  DiffusionResult get result => $_getN(3);
  @$pb.TagNumber(4)
  set result(DiffusionResult value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasResult() => $_has(3);
  @$pb.TagNumber(4)
  void clearResult() => $_clearField(4);
  @$pb.TagNumber(4)
  DiffusionResult ensureResult() => $_ensure(3);

  @$pb.TagNumber(5)
  $0.SDKError get error => $_getN(4);
  @$pb.TagNumber(5)
  set error($0.SDKError value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasError() => $_has(4);
  @$pb.TagNumber(5)
  void clearError() => $_clearField(5);
  @$pb.TagNumber(5)
  $0.SDKError ensureError() => $_ensure(4);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
