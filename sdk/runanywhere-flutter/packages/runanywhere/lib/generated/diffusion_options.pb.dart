// This is a generated file - do not edit.
//
// Generated from diffusion_options.proto.

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

import 'diffusion_options.pbenum.dart';
import 'model_types.pbenum.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'diffusion_options.pbenum.dart';

/// ---------------------------------------------------------------------------
/// Tokenizer source descriptor. `kind` is the preset; `custom_path` is only
/// meaningful when kind == CUSTOM and points at a directory URL containing
/// vocab.json + merges.txt (the SDK appends those filenames itself).
/// ---------------------------------------------------------------------------
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

  /// Only set when kind == DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM. Empty /
  /// unset for the bundled presets.
  @$pb.TagNumber(2)
  $core.String get customPath => $_getSZ(1);
  @$pb.TagNumber(2)
  set customPath($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCustomPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearCustomPath() => $_clearField(2);

  /// Automatically download missing tokenizer files. Defaults to backend
  /// policy when unset/false.
  @$pb.TagNumber(3)
  $core.bool get autoDownload => $_getBF(2);
  @$pb.TagNumber(3)
  set autoDownload($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAutoDownload() => $_has(2);
  @$pb.TagNumber(3)
  void clearAutoDownload() => $_clearField(3);
}

/// ---------------------------------------------------------------------------
/// Diffusion component configuration — the static, lifetime-of-component
/// settings handed to the diffusion service at initialize() time.
/// Sources pre-IDL:
///   Swift  DiffusionTypes.swift:279    (DiffusionConfiguration)
///   Kotlin DiffusionTypes.kt:204       (DiffusionConfiguration)
///   RN     DiffusionTypes.ts:86        (DiffusionConfiguration)
///   Web    — n/a (config is implicit in the llamacpp service ctor)
///   C ABI  rac_diffusion_types.h:144   (rac_diffusion_config_t)
///
/// Drift note: Swift/Kotlin/RN also carry `model_id`, `preferred_framework`,
/// and `reduce_memory` fields. Those belong on the more general component
/// configuration carried by ModelInfo / framework selection elsewhere in
/// this IDL package; this message intentionally narrows to the four
/// diffusion-specific knobs called out by the v1 spec.
/// `max_memory_mb` here is the new generalization of pre-IDL `reduce_memory`
/// (a bool) — backends interpret 0 as "no cap / engine default" and any
/// positive value as a hard MB ceiling. SDKs translating pre-IDL
/// `reduceMemory == true` should set this to the backend's documented
/// reduced-memory threshold; `reduceMemory == false` ⇒ 0.
/// ---------------------------------------------------------------------------
class DiffusionConfiguration extends $pb.GeneratedMessage {
  factory DiffusionConfiguration({
    DiffusionModelVariant? modelVariant,
    DiffusionTokenizerSource? tokenizerSource,
    $core.bool? enableSafetyChecker,
    $core.int? maxMemoryMb,
    $core.String? modelId,
    $0.InferenceFramework? preferredFramework,
    $core.bool? reduceMemory,
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
    if (reduceMemory != null) result.reduceMemory = reduceMemory;
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
    ..aE<$0.InferenceFramework>(6, _omitFieldNames ? '' : 'preferredFramework',
        enumValues: $0.InferenceFramework.values)
    ..aOB(7, _omitFieldNames ? '' : 'reduceMemory')
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

  /// Stable Diffusion model variant (selects the default resolution, step
  /// count, guidance scale, and tokenizer preset).
  @$pb.TagNumber(1)
  DiffusionModelVariant get modelVariant => $_getN(0);
  @$pb.TagNumber(1)
  set modelVariant(DiffusionModelVariant value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasModelVariant() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelVariant() => $_clearField(1);

  /// Tokenizer download source (CoreML SD models don't bundle the
  /// tokenizer files — the runtime must fetch vocab.json + merges.txt).
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

  /// Run NSFW safety checker on the decoded latent before returning the
  /// image. Default in every SDK is true.
  @$pb.TagNumber(3)
  $core.bool get enableSafetyChecker => $_getBF(2);
  @$pb.TagNumber(3)
  set enableSafetyChecker($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEnableSafetyChecker() => $_has(2);
  @$pb.TagNumber(3)
  void clearEnableSafetyChecker() => $_clearField(3);

  /// Maximum working-set memory the diffusion runtime is allowed to use,
  /// in MiB. 0 = no cap (engine default). Generalizes the pre-IDL
  /// `reduceMemory` bool flag.
  @$pb.TagNumber(4)
  $core.int get maxMemoryMb => $_getIZ(3);
  @$pb.TagNumber(4)
  set maxMemoryMb($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMaxMemoryMb() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxMemoryMb() => $_clearField(4);

  /// C ABI / SDK component fields that identify and route the component.
  @$pb.TagNumber(5)
  $core.String get modelId => $_getSZ(4);
  @$pb.TagNumber(5)
  set modelId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasModelId() => $_has(4);
  @$pb.TagNumber(5)
  void clearModelId() => $_clearField(5);

  @$pb.TagNumber(6)
  $0.InferenceFramework get preferredFramework => $_getN(5);
  @$pb.TagNumber(6)
  set preferredFramework($0.InferenceFramework value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasPreferredFramework() => $_has(5);
  @$pb.TagNumber(6)
  void clearPreferredFramework() => $_clearField(6);

  /// Legacy low-memory boolean. Backends may translate true to an internal
  /// memory cap when max_memory_mb is unset.
  @$pb.TagNumber(7)
  $core.bool get reduceMemory => $_getBF(6);
  @$pb.TagNumber(7)
  set reduceMemory($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasReduceMemory() => $_has(6);
  @$pb.TagNumber(7)
  void clearReduceMemory() => $_clearField(7);
}

/// ---------------------------------------------------------------------------
/// Canonical load-model wrapper used by SDKs that require a single argument
/// for diffusion model lifecycle calls.
/// ---------------------------------------------------------------------------
class DiffusionConfig extends $pb.GeneratedMessage {
  factory DiffusionConfig({
    $core.String? modelPath,
    $core.String? modelId,
    $core.String? modelName,
    DiffusionConfiguration? configuration,
  }) {
    final result = create();
    if (modelPath != null) result.modelPath = modelPath;
    if (modelId != null) result.modelId = modelId;
    if (modelName != null) result.modelName = modelName;
    if (configuration != null) result.configuration = configuration;
    return result;
  }

  DiffusionConfig._();

  factory DiffusionConfig.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DiffusionConfig.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DiffusionConfig',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelPath')
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..aOS(3, _omitFieldNames ? '' : 'modelName')
    ..aOM<DiffusionConfiguration>(4, _omitFieldNames ? '' : 'configuration',
        subBuilder: DiffusionConfiguration.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiffusionConfig clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiffusionConfig copyWith(void Function(DiffusionConfig) updates) =>
      super.copyWith((message) => updates(message as DiffusionConfig))
          as DiffusionConfig;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiffusionConfig create() => DiffusionConfig._();
  @$core.override
  DiffusionConfig createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DiffusionConfig getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DiffusionConfig>(create);
  static DiffusionConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelPath => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelPath($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelPath() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get modelName => $_getSZ(2);
  @$pb.TagNumber(3)
  set modelName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasModelName() => $_has(2);
  @$pb.TagNumber(3)
  void clearModelName() => $_clearField(3);

  @$pb.TagNumber(4)
  DiffusionConfiguration get configuration => $_getN(3);
  @$pb.TagNumber(4)
  set configuration(DiffusionConfiguration value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasConfiguration() => $_has(3);
  @$pb.TagNumber(4)
  void clearConfiguration() => $_clearField(4);
  @$pb.TagNumber(4)
  DiffusionConfiguration ensureConfiguration() => $_ensure(3);
}

/// ---------------------------------------------------------------------------
/// Per-call generation options. Sources pre-IDL:
///   Swift  DiffusionTypes.swift:341    (DiffusionGenerationOptions)
///   Kotlin DiffusionTypes.kt:230       (DiffusionGenerationOptions)
///   RN     DiffusionTypes.ts:114       (DiffusionGenerationOptions)
///   Web    DiffusionTypes.ts:29        (DiffusionGenerationOptions)
///   C ABI  rac_diffusion_types.h:187   (rac_diffusion_options_t)
///
/// Drift note: pre-IDL Swift/Kotlin/RN carry additional fields that the v1
/// IDL deliberately drops from this message in favor of more general /
/// future carriers:
///   - input_image / mask_image (bytes)         → flows through a separate
///                                                input artifact message in
///                                                the service IDL
///   - denoise_strength (float)                 → deferred (img2img-only,
///                                                not in spec)
///   - report_intermediate_images / progress_stride → covered by
///                                                DiffusionProgress
///                                                streaming semantics
/// ---------------------------------------------------------------------------
class DiffusionGenerationOptions extends $pb.GeneratedMessage {
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
    if (numInferenceSteps != null) result.numInferenceSteps = numInferenceSteps;
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
    ..aI(5, _omitFieldNames ? '' : 'numInferenceSteps')
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

  /// Text prompt describing the desired image. Required.
  @$pb.TagNumber(1)
  $core.String get prompt => $_getSZ(0);
  @$pb.TagNumber(1)
  set prompt($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPrompt() => $_has(0);
  @$pb.TagNumber(1)
  void clearPrompt() => $_clearField(1);

  /// Things to avoid in the image. Empty = no negative prompt.
  @$pb.TagNumber(2)
  $core.String get negativePrompt => $_getSZ(1);
  @$pb.TagNumber(2)
  set negativePrompt($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNegativePrompt() => $_has(1);
  @$pb.TagNumber(2)
  void clearNegativePrompt() => $_clearField(2);

  /// Output image width  in pixels.  0 = use variant default
  /// (512 for SD 1.5 / SDXS / LCM, 768 for SD 2.1, 1024 for SDXL / Turbo).
  @$pb.TagNumber(3)
  $core.int get width => $_getIZ(2);
  @$pb.TagNumber(3)
  set width($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasWidth() => $_has(2);
  @$pb.TagNumber(3)
  void clearWidth() => $_clearField(3);

  /// Output image height in pixels.  0 = use variant default.
  @$pb.TagNumber(4)
  $core.int get height => $_getIZ(3);
  @$pb.TagNumber(4)
  set height($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasHeight() => $_has(3);
  @$pb.TagNumber(4)
  void clearHeight() => $_clearField(4);

  /// Number of denoising steps. Range 1–50 (variant-dependent: SDXS=1,
  /// SDXL_Turbo / LCM=4, SD*=20–28). 0 = use variant default.
  @$pb.TagNumber(5)
  $core.int get numInferenceSteps => $_getIZ(4);
  @$pb.TagNumber(5)
  set numInferenceSteps($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasNumInferenceSteps() => $_has(4);
  @$pb.TagNumber(5)
  void clearNumInferenceSteps() => $_clearField(5);

  /// Classifier-free guidance scale. 0.0 = no CFG (required for SDXS /
  /// SDXL_Turbo). Typical SD range 1.0–20.0; default 7.5.
  @$pb.TagNumber(6)
  $core.double get guidanceScale => $_getN(5);
  @$pb.TagNumber(6)
  set guidanceScale($core.double value) => $_setFloat(5, value);
  @$pb.TagNumber(6)
  $core.bool hasGuidanceScale() => $_has(5);
  @$pb.TagNumber(6)
  void clearGuidanceScale() => $_clearField(6);

  /// RNG seed for reproducibility. -1 = pick a random seed.
  @$pb.TagNumber(7)
  $fixnum.Int64 get seed => $_getI64(6);
  @$pb.TagNumber(7)
  set seed($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSeed() => $_has(6);
  @$pb.TagNumber(7)
  void clearSeed() => $_clearField(7);

  /// Sampler algorithm. UNSPECIFIED = backend picks (recommended:
  /// DPMPP_2M_KARRAS).
  @$pb.TagNumber(8)
  DiffusionScheduler get scheduler => $_getN(7);
  @$pb.TagNumber(8)
  set scheduler(DiffusionScheduler value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasScheduler() => $_has(7);
  @$pb.TagNumber(8)
  void clearScheduler() => $_clearField(8);

  /// Generation mode (txt2img / img2img / inpainting). UNSPECIFIED =
  /// TEXT_TO_IMAGE.
  @$pb.TagNumber(9)
  DiffusionMode get mode => $_getN(8);
  @$pb.TagNumber(9)
  set mode(DiffusionMode value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasMode() => $_has(8);
  @$pb.TagNumber(9)
  void clearMode() => $_clearField(9);

  /// Image-to-image / inpainting payloads from rac_diffusion_options_t.
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

  /// Progress reporting controls.
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

  /// Dimensions for raw input_image payloads when the backend cannot infer
  /// them from an encoded container.
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

  /// Input image/mask media hints. Empty = backend infer/default.
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

/// ---------------------------------------------------------------------------
/// Streamed progress event. Sources pre-IDL:
///   Swift  DiffusionTypes.swift:511    (DiffusionProgress)
///   Kotlin DiffusionTypes.kt:337       (DiffusionProgress)
///   RN     DiffusionTypes.ts:163       (DiffusionProgress)
///   Web    DiffusionTypes.ts:69        (callback signature, not a struct)
///   C ABI  rac_diffusion_types.h:279   (rac_diffusion_progress_t)
/// ---------------------------------------------------------------------------
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

  /// Fraction of denoising completed in [0.0, 1.0].
  @$pb.TagNumber(1)
  $core.double get progressPercent => $_getN(0);
  @$pb.TagNumber(1)
  set progressPercent($core.double value) => $_setFloat(0, value);
  @$pb.TagNumber(1)
  $core.bool hasProgressPercent() => $_has(0);
  @$pb.TagNumber(1)
  void clearProgressPercent() => $_clearField(1);

  /// 1-based current step number.
  @$pb.TagNumber(2)
  $core.int get currentStep => $_getIZ(1);
  @$pb.TagNumber(2)
  set currentStep($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCurrentStep() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrentStep() => $_clearField(2);

  /// Total number of steps the engine plans to execute.
  @$pb.TagNumber(3)
  $core.int get totalSteps => $_getIZ(2);
  @$pb.TagNumber(3)
  set totalSteps($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTotalSteps() => $_has(2);
  @$pb.TagNumber(3)
  void clearTotalSteps() => $_clearField(3);

  /// Free-form stage name ("Encoding", "Denoising", "Decoding", …).
  @$pb.TagNumber(4)
  $core.String get stage => $_getSZ(3);
  @$pb.TagNumber(4)
  set stage($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasStage() => $_has(3);
  @$pb.TagNumber(4)
  void clearStage() => $_clearField(4);

  /// Optional intermediate image bytes (PNG when surfaced by
  /// Swift/Kotlin/RN; raw RGBA when surfaced by the C ABI). Present only
  /// when the caller requested intermediate-image reporting and the
  /// engine has produced one for this step.
  @$pb.TagNumber(5)
  $core.List<$core.int> get intermediateImageData => $_getN(4);
  @$pb.TagNumber(5)
  set intermediateImageData($core.List<$core.int> value) =>
      $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasIntermediateImageData() => $_has(4);
  @$pb.TagNumber(5)
  void clearIntermediateImageData() => $_clearField(5);

  /// Dimensions for intermediate_image_data when it is raw pixel data.
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

/// ---------------------------------------------------------------------------
/// Final generation result. Sources pre-IDL:
///   Swift  DiffusionTypes.swift:560    (DiffusionResult)
///   Kotlin DiffusionTypes.kt:355       (DiffusionResult)
///   RN     DiffusionTypes.ts:185       (DiffusionResult)
///   Web    DiffusionTypes.ts:54        (DiffusionGenerationResult)
///   C ABI  rac_diffusion_types.h:314   (rac_diffusion_result_t)
///
/// Drift note: pre-IDL Swift/Kotlin/RN/Web all name the wall-clock field
/// `generation_time_ms`. The v1 IDL renames it to `total_time_ms` per the
/// spec — round-trip is a pure rename. `used_scheduler` is *new* in the IDL
/// (no pre-IDL surface echoes back which scheduler actually ran when the
/// caller sent UNSPECIFIED); it lets clients log which sampler the engine
/// chose.
/// ---------------------------------------------------------------------------
class DiffusionResult extends $pb.GeneratedMessage {
  factory DiffusionResult({
    $core.List<$core.int>? imageData,
    $core.int? width,
    $core.int? height,
    $fixnum.Int64? seedUsed,
    $fixnum.Int64? totalTimeMs,
    $core.bool? safetyFlag,
    DiffusionScheduler? usedScheduler,
    $core.String? errorMessage,
    $core.int? errorCode,
    $core.String? imageMediaType,
    $core.Iterable<$core.List<$core.int>>? batchImages,
    $core.int? imagesGenerated,
  }) {
    final result = create();
    if (imageData != null) result.imageData = imageData;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (seedUsed != null) result.seedUsed = seedUsed;
    if (totalTimeMs != null) result.totalTimeMs = totalTimeMs;
    if (safetyFlag != null) result.safetyFlag = safetyFlag;
    if (usedScheduler != null) result.usedScheduler = usedScheduler;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    if (imageMediaType != null) result.imageMediaType = imageMediaType;
    if (batchImages != null) result.batchImages.addAll(batchImages);
    if (imagesGenerated != null) result.imagesGenerated = imagesGenerated;
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
    ..aOS(8, _omitFieldNames ? '' : 'errorMessage')
    ..aI(9, _omitFieldNames ? '' : 'errorCode')
    ..aOS(10, _omitFieldNames ? '' : 'imageMediaType')
    ..p<$core.List<$core.int>>(
        11, _omitFieldNames ? '' : 'batchImages', $pb.PbFieldType.PY)
    ..aI(12, _omitFieldNames ? '' : 'imagesGenerated')
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

  /// Encoded image. PNG bytes on Swift/Kotlin/RN; raw RGBA bytes on the
  /// C ABI / Web llamacpp surface. (Encoding is a property of the
  /// backend's vtable, not of this message.)
  @$pb.TagNumber(1)
  $core.List<$core.int> get imageData => $_getN(0);
  @$pb.TagNumber(1)
  set imageData($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasImageData() => $_has(0);
  @$pb.TagNumber(1)
  void clearImageData() => $_clearField(1);

  /// Final image width  in pixels.
  @$pb.TagNumber(2)
  $core.int get width => $_getIZ(1);
  @$pb.TagNumber(2)
  set width($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasWidth() => $_has(1);
  @$pb.TagNumber(2)
  void clearWidth() => $_clearField(2);

  /// Final image height in pixels.
  @$pb.TagNumber(3)
  $core.int get height => $_getIZ(2);
  @$pb.TagNumber(3)
  set height($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasHeight() => $_has(2);
  @$pb.TagNumber(3)
  void clearHeight() => $_clearField(3);

  /// Seed actually used (resolved if the caller passed -1 for random).
  @$pb.TagNumber(4)
  $fixnum.Int64 get seedUsed => $_getI64(3);
  @$pb.TagNumber(4)
  set seedUsed($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSeedUsed() => $_has(3);
  @$pb.TagNumber(4)
  void clearSeedUsed() => $_clearField(4);

  /// Total wall-clock generation time in milliseconds (renamed from
  /// pre-IDL `generation_time_ms`).
  @$pb.TagNumber(5)
  $fixnum.Int64 get totalTimeMs => $_getI64(4);
  @$pb.TagNumber(5)
  set totalTimeMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTotalTimeMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearTotalTimeMs() => $_clearField(5);

  /// Whether the safety checker flagged the image as NSFW. False if the
  /// checker was disabled in DiffusionConfiguration.
  @$pb.TagNumber(6)
  $core.bool get safetyFlag => $_getBF(5);
  @$pb.TagNumber(6)
  set safetyFlag($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSafetyFlag() => $_has(5);
  @$pb.TagNumber(6)
  void clearSafetyFlag() => $_clearField(6);

  /// Scheduler the engine actually ran. Useful when the caller passed
  /// DIFFUSION_SCHEDULER_UNSPECIFIED.
  @$pb.TagNumber(7)
  DiffusionScheduler get usedScheduler => $_getN(6);
  @$pb.TagNumber(7)
  set usedScheduler(DiffusionScheduler value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasUsedScheduler() => $_has(6);
  @$pb.TagNumber(7)
  void clearUsedScheduler() => $_clearField(7);

  /// Failure details for result-envelope APIs.
  @$pb.TagNumber(8)
  $core.String get errorMessage => $_getSZ(7);
  @$pb.TagNumber(8)
  set errorMessage($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasErrorMessage() => $_has(7);
  @$pb.TagNumber(8)
  void clearErrorMessage() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get errorCode => $_getIZ(8);
  @$pb.TagNumber(9)
  set errorCode($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasErrorCode() => $_has(8);
  @$pb.TagNumber(9)
  void clearErrorCode() => $_clearField(9);

  /// Output image media type, e.g. "image/png" or "image/raw-rgba".
  @$pb.TagNumber(10)
  $core.String get imageMediaType => $_getSZ(9);
  @$pb.TagNumber(10)
  set imageMediaType($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasImageMediaType() => $_has(9);
  @$pb.TagNumber(10)
  void clearImageMediaType() => $_clearField(10);

  @$pb.TagNumber(11)
  $pb.PbList<$core.List<$core.int>> get batchImages => $_getList(10);

  @$pb.TagNumber(12)
  $core.int get imagesGenerated => $_getIZ(11);
  @$pb.TagNumber(12)
  set imagesGenerated($core.int value) => $_setSignedInt32(11, value);
  @$pb.TagNumber(12)
  $core.bool hasImagesGenerated() => $_has(11);
  @$pb.TagNumber(12)
  void clearImagesGenerated() => $_clearField(12);
}

/// ---------------------------------------------------------------------------
/// Capability descriptor for the loaded diffusion backend / model. Sources
/// pre-IDL:
///   Swift  DiffusionCapabilities (OptionSet bit flags — supportsTextToImage,
///          supportsImageToImage, supportsInpainting, supportsIntermediateImages,
///          supportsSafetyChecker)
///   Kotlin DiffusionTypes.kt:378       (DiffusionCapabilities, mirror of Swift)
///   RN     DiffusionTypes.ts:210       (interface with supportedVariants /
///          supportedSchedulers / supportedModes / maxWidth / maxHeight /
///          supportsIntermediateImages)
///   Web    — n/a
///   C ABI  rac_diffusion_types.h:352   (rac_diffusion_info_t — flags +
///          max_width / max_height)
///
/// The IDL takes the RN-style "what can the backend do?" shape (lists of
/// supported enums + a single max-resolution scalar) since it carries the
/// most information; SDKs whose pre-IDL surface is a bit-flag set must map
/// each flag to populating / leaving the corresponding repeated field.
/// `max_resolution_px` represents the larger of width/height the backend can
/// produce in a single call (RN/C-ABI carry width and height separately —
/// for square SD models they're equal; for the IDL we fold them to the
/// shared cap and document that asymmetric caps would need a future
/// `max_width_px` / `max_height_px` split).
/// ---------------------------------------------------------------------------
class DiffusionCapabilities extends $pb.GeneratedMessage {
  factory DiffusionCapabilities({
    $core.Iterable<DiffusionModelVariant>? supportedVariants,
    $core.Iterable<DiffusionScheduler>? supportedSchedulers,
    $core.int? maxResolutionPx,
    $core.Iterable<DiffusionMode>? supportedModes,
    $core.int? maxWidthPx,
    $core.int? maxHeightPx,
    $core.bool? supportsIntermediateImages,
    $core.bool? supportsSafetyChecker,
    $core.bool? isReady,
    $core.String? currentModel,
    $core.bool? safetyCheckerEnabled,
    $core.bool? supportsBatchGeneration,
    $core.Iterable<$core.String>? supportedOutputMediaTypes,
  }) {
    final result = create();
    if (supportedVariants != null)
      result.supportedVariants.addAll(supportedVariants);
    if (supportedSchedulers != null)
      result.supportedSchedulers.addAll(supportedSchedulers);
    if (maxResolutionPx != null) result.maxResolutionPx = maxResolutionPx;
    if (supportedModes != null) result.supportedModes.addAll(supportedModes);
    if (maxWidthPx != null) result.maxWidthPx = maxWidthPx;
    if (maxHeightPx != null) result.maxHeightPx = maxHeightPx;
    if (supportsIntermediateImages != null)
      result.supportsIntermediateImages = supportsIntermediateImages;
    if (supportsSafetyChecker != null)
      result.supportsSafetyChecker = supportsSafetyChecker;
    if (isReady != null) result.isReady = isReady;
    if (currentModel != null) result.currentModel = currentModel;
    if (safetyCheckerEnabled != null)
      result.safetyCheckerEnabled = safetyCheckerEnabled;
    if (supportsBatchGeneration != null)
      result.supportsBatchGeneration = supportsBatchGeneration;
    if (supportedOutputMediaTypes != null)
      result.supportedOutputMediaTypes.addAll(supportedOutputMediaTypes);
    return result;
  }

  DiffusionCapabilities._();

  factory DiffusionCapabilities.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DiffusionCapabilities.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DiffusionCapabilities',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pc<DiffusionModelVariant>(
        1, _omitFieldNames ? '' : 'supportedVariants', $pb.PbFieldType.KE,
        valueOf: DiffusionModelVariant.valueOf,
        enumValues: DiffusionModelVariant.values,
        defaultEnumValue:
            DiffusionModelVariant.DIFFUSION_MODEL_VARIANT_UNSPECIFIED)
    ..pc<DiffusionScheduler>(
        2, _omitFieldNames ? '' : 'supportedSchedulers', $pb.PbFieldType.KE,
        valueOf: DiffusionScheduler.valueOf,
        enumValues: DiffusionScheduler.values,
        defaultEnumValue: DiffusionScheduler.DIFFUSION_SCHEDULER_UNSPECIFIED)
    ..aI(3, _omitFieldNames ? '' : 'maxResolutionPx')
    ..pc<DiffusionMode>(
        4, _omitFieldNames ? '' : 'supportedModes', $pb.PbFieldType.KE,
        valueOf: DiffusionMode.valueOf,
        enumValues: DiffusionMode.values,
        defaultEnumValue: DiffusionMode.DIFFUSION_MODE_UNSPECIFIED)
    ..aI(5, _omitFieldNames ? '' : 'maxWidthPx')
    ..aI(6, _omitFieldNames ? '' : 'maxHeightPx')
    ..aOB(7, _omitFieldNames ? '' : 'supportsIntermediateImages')
    ..aOB(8, _omitFieldNames ? '' : 'supportsSafetyChecker')
    ..aOB(9, _omitFieldNames ? '' : 'isReady')
    ..aOS(10, _omitFieldNames ? '' : 'currentModel')
    ..aOB(11, _omitFieldNames ? '' : 'safetyCheckerEnabled')
    ..aOB(12, _omitFieldNames ? '' : 'supportsBatchGeneration')
    ..pPS(13, _omitFieldNames ? '' : 'supportedOutputMediaTypes')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiffusionCapabilities clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiffusionCapabilities copyWith(
          void Function(DiffusionCapabilities) updates) =>
      super.copyWith((message) => updates(message as DiffusionCapabilities))
          as DiffusionCapabilities;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiffusionCapabilities create() => DiffusionCapabilities._();
  @$core.override
  DiffusionCapabilities createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DiffusionCapabilities getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DiffusionCapabilities>(create);
  static DiffusionCapabilities? _defaultInstance;

  /// Stable Diffusion model variants this backend can load.
  @$pb.TagNumber(1)
  $pb.PbList<DiffusionModelVariant> get supportedVariants => $_getList(0);

  /// Sampler algorithms this backend implements.
  @$pb.TagNumber(2)
  $pb.PbList<DiffusionScheduler> get supportedSchedulers => $_getList(1);

  /// Largest image edge (in pixels) the backend can produce in a single
  /// generation. 0 = unknown / not advertised.
  @$pb.TagNumber(3)
  $core.int get maxResolutionPx => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxResolutionPx($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMaxResolutionPx() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxResolutionPx() => $_clearField(3);

  /// Generation modes this backend supports.
  @$pb.TagNumber(4)
  $pb.PbList<DiffusionMode> get supportedModes => $_getList(3);

  /// Asymmetric maximum dimensions when known. 0 = unknown.
  @$pb.TagNumber(5)
  $core.int get maxWidthPx => $_getIZ(4);
  @$pb.TagNumber(5)
  set maxWidthPx($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMaxWidthPx() => $_has(4);
  @$pb.TagNumber(5)
  void clearMaxWidthPx() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get maxHeightPx => $_getIZ(5);
  @$pb.TagNumber(6)
  set maxHeightPx($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMaxHeightPx() => $_has(5);
  @$pb.TagNumber(6)
  void clearMaxHeightPx() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get supportsIntermediateImages => $_getBF(6);
  @$pb.TagNumber(7)
  set supportsIntermediateImages($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSupportsIntermediateImages() => $_has(6);
  @$pb.TagNumber(7)
  void clearSupportsIntermediateImages() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get supportsSafetyChecker => $_getBF(7);
  @$pb.TagNumber(8)
  set supportsSafetyChecker($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasSupportsSafetyChecker() => $_has(7);
  @$pb.TagNumber(8)
  void clearSupportsSafetyChecker() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.bool get isReady => $_getBF(8);
  @$pb.TagNumber(9)
  set isReady($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasIsReady() => $_has(8);
  @$pb.TagNumber(9)
  void clearIsReady() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get currentModel => $_getSZ(9);
  @$pb.TagNumber(10)
  set currentModel($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasCurrentModel() => $_has(9);
  @$pb.TagNumber(10)
  void clearCurrentModel() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.bool get safetyCheckerEnabled => $_getBF(10);
  @$pb.TagNumber(11)
  set safetyCheckerEnabled($core.bool value) => $_setBool(10, value);
  @$pb.TagNumber(11)
  $core.bool hasSafetyCheckerEnabled() => $_has(10);
  @$pb.TagNumber(11)
  void clearSafetyCheckerEnabled() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.bool get supportsBatchGeneration => $_getBF(11);
  @$pb.TagNumber(12)
  set supportsBatchGeneration($core.bool value) => $_setBool(11, value);
  @$pb.TagNumber(12)
  $core.bool hasSupportsBatchGeneration() => $_has(11);
  @$pb.TagNumber(12)
  void clearSupportsBatchGeneration() => $_clearField(12);

  @$pb.TagNumber(13)
  $pb.PbList<$core.String> get supportedOutputMediaTypes => $_getList(12);
}

class DiffusionStreamEvent extends $pb.GeneratedMessage {
  factory DiffusionStreamEvent({
    $fixnum.Int64? seq,
    $fixnum.Int64? timestampUs,
    $core.String? requestId,
    DiffusionStreamEventKind? kind,
    DiffusionProgress? progress,
    DiffusionResult? result,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final result$ = create();
    if (seq != null) result$.seq = seq;
    if (timestampUs != null) result$.timestampUs = timestampUs;
    if (requestId != null) result$.requestId = requestId;
    if (kind != null) result$.kind = kind;
    if (progress != null) result$.progress = progress;
    if (result != null) result$.result = result;
    if (errorMessage != null) result$.errorMessage = errorMessage;
    if (errorCode != null) result$.errorCode = errorCode;
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
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(3, _omitFieldNames ? '' : 'requestId')
    ..aE<DiffusionStreamEventKind>(4, _omitFieldNames ? '' : 'kind',
        enumValues: DiffusionStreamEventKind.values)
    ..aOM<DiffusionProgress>(5, _omitFieldNames ? '' : 'progress',
        subBuilder: DiffusionProgress.create)
    ..aOM<DiffusionResult>(6, _omitFieldNames ? '' : 'result',
        subBuilder: DiffusionResult.create)
    ..aOS(7, _omitFieldNames ? '' : 'errorMessage')
    ..aI(8, _omitFieldNames ? '' : 'errorCode')
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

  @$pb.TagNumber(1)
  $fixnum.Int64 get seq => $_getI64(0);
  @$pb.TagNumber(1)
  set seq($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampUs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampUs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestampUs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampUs() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get requestId => $_getSZ(2);
  @$pb.TagNumber(3)
  set requestId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRequestId() => $_has(2);
  @$pb.TagNumber(3)
  void clearRequestId() => $_clearField(3);

  @$pb.TagNumber(4)
  DiffusionStreamEventKind get kind => $_getN(3);
  @$pb.TagNumber(4)
  set kind(DiffusionStreamEventKind value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasKind() => $_has(3);
  @$pb.TagNumber(4)
  void clearKind() => $_clearField(4);

  @$pb.TagNumber(5)
  DiffusionProgress get progress => $_getN(4);
  @$pb.TagNumber(5)
  set progress(DiffusionProgress value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasProgress() => $_has(4);
  @$pb.TagNumber(5)
  void clearProgress() => $_clearField(5);
  @$pb.TagNumber(5)
  DiffusionProgress ensureProgress() => $_ensure(4);

  @$pb.TagNumber(6)
  DiffusionResult get result => $_getN(5);
  @$pb.TagNumber(6)
  set result(DiffusionResult value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasResult() => $_has(5);
  @$pb.TagNumber(6)
  void clearResult() => $_clearField(6);
  @$pb.TagNumber(6)
  DiffusionResult ensureResult() => $_ensure(5);

  @$pb.TagNumber(7)
  $core.String get errorMessage => $_getSZ(6);
  @$pb.TagNumber(7)
  set errorMessage($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasErrorMessage() => $_has(6);
  @$pb.TagNumber(7)
  void clearErrorMessage() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get errorCode => $_getIZ(7);
  @$pb.TagNumber(8)
  set errorCode($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasErrorCode() => $_has(7);
  @$pb.TagNumber(8)
  void clearErrorCode() => $_clearField(8);
}

class DiffusionServiceState extends $pb.GeneratedMessage {
  factory DiffusionServiceState({
    $core.bool? isReady,
    $core.String? currentModel,
    DiffusionCapabilities? capabilities,
    $core.bool? isGenerating,
    $core.String? activeRequestId,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final result = create();
    if (isReady != null) result.isReady = isReady;
    if (currentModel != null) result.currentModel = currentModel;
    if (capabilities != null) result.capabilities = capabilities;
    if (isGenerating != null) result.isGenerating = isGenerating;
    if (activeRequestId != null) result.activeRequestId = activeRequestId;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    return result;
  }

  DiffusionServiceState._();

  factory DiffusionServiceState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DiffusionServiceState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DiffusionServiceState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isReady')
    ..aOS(2, _omitFieldNames ? '' : 'currentModel')
    ..aOM<DiffusionCapabilities>(3, _omitFieldNames ? '' : 'capabilities',
        subBuilder: DiffusionCapabilities.create)
    ..aOB(4, _omitFieldNames ? '' : 'isGenerating')
    ..aOS(5, _omitFieldNames ? '' : 'activeRequestId')
    ..aOS(6, _omitFieldNames ? '' : 'errorMessage')
    ..aI(7, _omitFieldNames ? '' : 'errorCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiffusionServiceState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiffusionServiceState copyWith(
          void Function(DiffusionServiceState) updates) =>
      super.copyWith((message) => updates(message as DiffusionServiceState))
          as DiffusionServiceState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiffusionServiceState create() => DiffusionServiceState._();
  @$core.override
  DiffusionServiceState createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DiffusionServiceState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DiffusionServiceState>(create);
  static DiffusionServiceState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get isReady => $_getBF(0);
  @$pb.TagNumber(1)
  set isReady($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIsReady() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsReady() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get currentModel => $_getSZ(1);
  @$pb.TagNumber(2)
  set currentModel($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCurrentModel() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrentModel() => $_clearField(2);

  @$pb.TagNumber(3)
  DiffusionCapabilities get capabilities => $_getN(2);
  @$pb.TagNumber(3)
  set capabilities(DiffusionCapabilities value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasCapabilities() => $_has(2);
  @$pb.TagNumber(3)
  void clearCapabilities() => $_clearField(3);
  @$pb.TagNumber(3)
  DiffusionCapabilities ensureCapabilities() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.bool get isGenerating => $_getBF(3);
  @$pb.TagNumber(4)
  set isGenerating($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasIsGenerating() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsGenerating() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get activeRequestId => $_getSZ(4);
  @$pb.TagNumber(5)
  set activeRequestId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasActiveRequestId() => $_has(4);
  @$pb.TagNumber(5)
  void clearActiveRequestId() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get errorMessage => $_getSZ(5);
  @$pb.TagNumber(6)
  set errorMessage($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasErrorMessage() => $_has(5);
  @$pb.TagNumber(6)
  void clearErrorMessage() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get errorCode => $_getIZ(6);
  @$pb.TagNumber(7)
  set errorCode($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasErrorCode() => $_has(6);
  @$pb.TagNumber(7)
  void clearErrorCode() => $_clearField(7);
}

/// Logical Diffusion service contract. Native photo-library/camera/file
/// acquisition, OS-visible image operations, and platform-specific backend
/// execution remain adapter-owned; C++ consumes only serialized
/// request/result/event messages.
class DiffusionApi {
  final $pb.RpcClient _client;

  DiffusionApi(this._client);

  /// One-shot image generation returning the final image result envelope.
  $async.Future<DiffusionResult> generate(
          $pb.ClientContext? ctx, DiffusionGenerationRequest request) =>
      _client.invoke<DiffusionResult>(
          ctx, 'Diffusion', 'Generate', request, DiffusionResult());

  /// Server-streaming generation events: start, denoising progress,
  /// intermediate images, terminal completion, and errors.
  $async.Future<DiffusionStreamEvent> stream(
          $pb.ClientContext? ctx, DiffusionGenerationRequest request) =>
      _client.invoke<DiffusionStreamEvent>(
          ctx, 'Diffusion', 'Stream', request, DiffusionStreamEvent());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
