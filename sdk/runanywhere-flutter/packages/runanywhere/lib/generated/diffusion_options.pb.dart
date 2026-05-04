//
//  Generated code. Do not modify.
//  source: diffusion_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'diffusion_options.pbenum.dart';
import 'model_types.pbenum.dart' as $0;

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
    final $result = create();
    if (kind != null) {
      $result.kind = kind;
    }
    if (customPath != null) {
      $result.customPath = customPath;
    }
    if (autoDownload != null) {
      $result.autoDownload = autoDownload;
    }
    return $result;
  }
  DiffusionTokenizerSource._() : super();
  factory DiffusionTokenizerSource.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DiffusionTokenizerSource.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DiffusionTokenizerSource', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<DiffusionTokenizerSourceKind>(1, _omitFieldNames ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: DiffusionTokenizerSourceKind.DIFFUSION_TOKENIZER_SOURCE_KIND_UNSPECIFIED, valueOf: DiffusionTokenizerSourceKind.valueOf, enumValues: DiffusionTokenizerSourceKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'customPath')
    ..aOB(3, _omitFieldNames ? '' : 'autoDownload')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DiffusionTokenizerSource clone() => DiffusionTokenizerSource()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DiffusionTokenizerSource copyWith(void Function(DiffusionTokenizerSource) updates) => super.copyWith((message) => updates(message as DiffusionTokenizerSource)) as DiffusionTokenizerSource;

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

  /// Only set when kind == DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM. Empty /
  /// unset for the bundled presets.
  @$pb.TagNumber(2)
  $core.String get customPath => $_getSZ(1);
  @$pb.TagNumber(2)
  set customPath($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCustomPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearCustomPath() => clearField(2);

  /// Automatically download missing tokenizer files. Defaults to backend
  /// policy when unset/false.
  @$pb.TagNumber(3)
  $core.bool get autoDownload => $_getBF(2);
  @$pb.TagNumber(3)
  set autoDownload($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAutoDownload() => $_has(2);
  @$pb.TagNumber(3)
  void clearAutoDownload() => clearField(3);
}

///  ---------------------------------------------------------------------------
///  Diffusion component configuration — the static, lifetime-of-component
///  settings handed to the diffusion service at initialize() time.
///  Sources pre-IDL:
///    Swift  DiffusionTypes.swift:279    (DiffusionConfiguration)
///    Kotlin DiffusionTypes.kt:204       (DiffusionConfiguration)
///    RN     DiffusionTypes.ts:86        (DiffusionConfiguration)
///    Web    — n/a (config is implicit in the llamacpp service ctor)
///    C ABI  rac_diffusion_types.h:144   (rac_diffusion_config_t)
///
///  Drift note: Swift/Kotlin/RN also carry `model_id`, `preferred_framework`,
///  and `reduce_memory` fields. Those belong on the more general component
///  configuration carried by ModelInfo / framework selection elsewhere in
///  this IDL package; this message intentionally narrows to the four
///  diffusion-specific knobs called out by the v1 spec.
///  `max_memory_mb` here is the new generalization of pre-IDL `reduce_memory`
///  (a bool) — backends interpret 0 as "no cap / engine default" and any
///  positive value as a hard MB ceiling. SDKs translating pre-IDL
///  `reduceMemory == true` should set this to the backend's documented
///  reduced-memory threshold; `reduceMemory == false` ⇒ 0.
///  ---------------------------------------------------------------------------
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
    final $result = create();
    if (modelVariant != null) {
      $result.modelVariant = modelVariant;
    }
    if (tokenizerSource != null) {
      $result.tokenizerSource = tokenizerSource;
    }
    if (enableSafetyChecker != null) {
      $result.enableSafetyChecker = enableSafetyChecker;
    }
    if (maxMemoryMb != null) {
      $result.maxMemoryMb = maxMemoryMb;
    }
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (preferredFramework != null) {
      $result.preferredFramework = preferredFramework;
    }
    if (reduceMemory != null) {
      $result.reduceMemory = reduceMemory;
    }
    return $result;
  }
  DiffusionConfiguration._() : super();
  factory DiffusionConfiguration.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DiffusionConfiguration.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DiffusionConfiguration', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<DiffusionModelVariant>(1, _omitFieldNames ? '' : 'modelVariant', $pb.PbFieldType.OE, defaultOrMaker: DiffusionModelVariant.DIFFUSION_MODEL_VARIANT_UNSPECIFIED, valueOf: DiffusionModelVariant.valueOf, enumValues: DiffusionModelVariant.values)
    ..aOM<DiffusionTokenizerSource>(2, _omitFieldNames ? '' : 'tokenizerSource', subBuilder: DiffusionTokenizerSource.create)
    ..aOB(3, _omitFieldNames ? '' : 'enableSafetyChecker')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'maxMemoryMb', $pb.PbFieldType.O3)
    ..aOS(5, _omitFieldNames ? '' : 'modelId')
    ..e<$0.InferenceFramework>(6, _omitFieldNames ? '' : 'preferredFramework', $pb.PbFieldType.OE, defaultOrMaker: $0.InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED, valueOf: $0.InferenceFramework.valueOf, enumValues: $0.InferenceFramework.values)
    ..aOB(7, _omitFieldNames ? '' : 'reduceMemory')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DiffusionConfiguration clone() => DiffusionConfiguration()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DiffusionConfiguration copyWith(void Function(DiffusionConfiguration) updates) => super.copyWith((message) => updates(message as DiffusionConfiguration)) as DiffusionConfiguration;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiffusionConfiguration create() => DiffusionConfiguration._();
  DiffusionConfiguration createEmptyInstance() => create();
  static $pb.PbList<DiffusionConfiguration> createRepeated() => $pb.PbList<DiffusionConfiguration>();
  @$core.pragma('dart2js:noInline')
  static DiffusionConfiguration getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DiffusionConfiguration>(create);
  static DiffusionConfiguration? _defaultInstance;

  /// Stable Diffusion model variant (selects the default resolution, step
  /// count, guidance scale, and tokenizer preset).
  @$pb.TagNumber(1)
  DiffusionModelVariant get modelVariant => $_getN(0);
  @$pb.TagNumber(1)
  set modelVariant(DiffusionModelVariant v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelVariant() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelVariant() => clearField(1);

  /// Tokenizer download source (CoreML SD models don't bundle the
  /// tokenizer files — the runtime must fetch vocab.json + merges.txt).
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

  /// Run NSFW safety checker on the decoded latent before returning the
  /// image. Default in every SDK is true.
  @$pb.TagNumber(3)
  $core.bool get enableSafetyChecker => $_getBF(2);
  @$pb.TagNumber(3)
  set enableSafetyChecker($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasEnableSafetyChecker() => $_has(2);
  @$pb.TagNumber(3)
  void clearEnableSafetyChecker() => clearField(3);

  /// Maximum working-set memory the diffusion runtime is allowed to use,
  /// in MiB. 0 = no cap (engine default). Generalizes the pre-IDL
  /// `reduceMemory` bool flag.
  @$pb.TagNumber(4)
  $core.int get maxMemoryMb => $_getIZ(3);
  @$pb.TagNumber(4)
  set maxMemoryMb($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasMaxMemoryMb() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxMemoryMb() => clearField(4);

  /// C ABI / SDK component fields that identify and route the component.
  @$pb.TagNumber(5)
  $core.String get modelId => $_getSZ(4);
  @$pb.TagNumber(5)
  set modelId($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasModelId() => $_has(4);
  @$pb.TagNumber(5)
  void clearModelId() => clearField(5);

  @$pb.TagNumber(6)
  $0.InferenceFramework get preferredFramework => $_getN(5);
  @$pb.TagNumber(6)
  set preferredFramework($0.InferenceFramework v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasPreferredFramework() => $_has(5);
  @$pb.TagNumber(6)
  void clearPreferredFramework() => clearField(6);

  /// Legacy low-memory boolean. Backends may translate true to an internal
  /// memory cap when max_memory_mb is unset.
  @$pb.TagNumber(7)
  $core.bool get reduceMemory => $_getBF(6);
  @$pb.TagNumber(7)
  set reduceMemory($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasReduceMemory() => $_has(6);
  @$pb.TagNumber(7)
  void clearReduceMemory() => clearField(7);
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
    final $result = create();
    if (modelPath != null) {
      $result.modelPath = modelPath;
    }
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (modelName != null) {
      $result.modelName = modelName;
    }
    if (configuration != null) {
      $result.configuration = configuration;
    }
    return $result;
  }
  DiffusionConfig._() : super();
  factory DiffusionConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DiffusionConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DiffusionConfig', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelPath')
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..aOS(3, _omitFieldNames ? '' : 'modelName')
    ..aOM<DiffusionConfiguration>(4, _omitFieldNames ? '' : 'configuration', subBuilder: DiffusionConfiguration.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DiffusionConfig clone() => DiffusionConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DiffusionConfig copyWith(void Function(DiffusionConfig) updates) => super.copyWith((message) => updates(message as DiffusionConfig)) as DiffusionConfig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiffusionConfig create() => DiffusionConfig._();
  DiffusionConfig createEmptyInstance() => create();
  static $pb.PbList<DiffusionConfig> createRepeated() => $pb.PbList<DiffusionConfig>();
  @$core.pragma('dart2js:noInline')
  static DiffusionConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DiffusionConfig>(create);
  static DiffusionConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelPath => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelPath($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelPath() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get modelName => $_getSZ(2);
  @$pb.TagNumber(3)
  set modelName($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasModelName() => $_has(2);
  @$pb.TagNumber(3)
  void clearModelName() => clearField(3);

  @$pb.TagNumber(4)
  DiffusionConfiguration get configuration => $_getN(3);
  @$pb.TagNumber(4)
  set configuration(DiffusionConfiguration v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasConfiguration() => $_has(3);
  @$pb.TagNumber(4)
  void clearConfiguration() => clearField(4);
  @$pb.TagNumber(4)
  DiffusionConfiguration ensureConfiguration() => $_ensure(3);
}

///  ---------------------------------------------------------------------------
///  Per-call generation options. Sources pre-IDL:
///    Swift  DiffusionTypes.swift:341    (DiffusionGenerationOptions)
///    Kotlin DiffusionTypes.kt:230       (DiffusionGenerationOptions)
///    RN     DiffusionTypes.ts:114       (DiffusionGenerationOptions)
///    Web    DiffusionTypes.ts:29        (DiffusionGenerationOptions)
///    C ABI  rac_diffusion_types.h:187   (rac_diffusion_options_t)
///
///  Drift note: pre-IDL Swift/Kotlin/RN carry additional fields that the v1
///  IDL deliberately drops from this message in favor of more general /
///  future carriers:
///    - input_image / mask_image (bytes)         → flows through a separate
///                                                 input artifact message in
///                                                 the service IDL
///    - denoise_strength (float)                 → deferred (img2img-only,
///                                                 not in spec)
///    - report_intermediate_images / progress_stride → covered by
///                                                 DiffusionProgress
///                                                 streaming semantics
///  ---------------------------------------------------------------------------
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
  }) {
    final $result = create();
    if (prompt != null) {
      $result.prompt = prompt;
    }
    if (negativePrompt != null) {
      $result.negativePrompt = negativePrompt;
    }
    if (width != null) {
      $result.width = width;
    }
    if (height != null) {
      $result.height = height;
    }
    if (numInferenceSteps != null) {
      $result.numInferenceSteps = numInferenceSteps;
    }
    if (guidanceScale != null) {
      $result.guidanceScale = guidanceScale;
    }
    if (seed != null) {
      $result.seed = seed;
    }
    if (scheduler != null) {
      $result.scheduler = scheduler;
    }
    if (mode != null) {
      $result.mode = mode;
    }
    if (inputImage != null) {
      $result.inputImage = inputImage;
    }
    if (maskImage != null) {
      $result.maskImage = maskImage;
    }
    if (denoiseStrength != null) {
      $result.denoiseStrength = denoiseStrength;
    }
    if (reportIntermediateImages != null) {
      $result.reportIntermediateImages = reportIntermediateImages;
    }
    if (progressStride != null) {
      $result.progressStride = progressStride;
    }
    if (inputImageWidth != null) {
      $result.inputImageWidth = inputImageWidth;
    }
    if (inputImageHeight != null) {
      $result.inputImageHeight = inputImageHeight;
    }
    return $result;
  }
  DiffusionGenerationOptions._() : super();
  factory DiffusionGenerationOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DiffusionGenerationOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DiffusionGenerationOptions', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'prompt')
    ..aOS(2, _omitFieldNames ? '' : 'negativePrompt')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'width', $pb.PbFieldType.O3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'height', $pb.PbFieldType.O3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'numInferenceSteps', $pb.PbFieldType.O3)
    ..a<$core.double>(6, _omitFieldNames ? '' : 'guidanceScale', $pb.PbFieldType.OF)
    ..aInt64(7, _omitFieldNames ? '' : 'seed')
    ..e<DiffusionScheduler>(8, _omitFieldNames ? '' : 'scheduler', $pb.PbFieldType.OE, defaultOrMaker: DiffusionScheduler.DIFFUSION_SCHEDULER_UNSPECIFIED, valueOf: DiffusionScheduler.valueOf, enumValues: DiffusionScheduler.values)
    ..e<DiffusionMode>(9, _omitFieldNames ? '' : 'mode', $pb.PbFieldType.OE, defaultOrMaker: DiffusionMode.DIFFUSION_MODE_UNSPECIFIED, valueOf: DiffusionMode.valueOf, enumValues: DiffusionMode.values)
    ..a<$core.List<$core.int>>(10, _omitFieldNames ? '' : 'inputImage', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(11, _omitFieldNames ? '' : 'maskImage', $pb.PbFieldType.OY)
    ..a<$core.double>(12, _omitFieldNames ? '' : 'denoiseStrength', $pb.PbFieldType.OF)
    ..aOB(13, _omitFieldNames ? '' : 'reportIntermediateImages')
    ..a<$core.int>(14, _omitFieldNames ? '' : 'progressStride', $pb.PbFieldType.O3)
    ..a<$core.int>(15, _omitFieldNames ? '' : 'inputImageWidth', $pb.PbFieldType.O3)
    ..a<$core.int>(16, _omitFieldNames ? '' : 'inputImageHeight', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DiffusionGenerationOptions clone() => DiffusionGenerationOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DiffusionGenerationOptions copyWith(void Function(DiffusionGenerationOptions) updates) => super.copyWith((message) => updates(message as DiffusionGenerationOptions)) as DiffusionGenerationOptions;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiffusionGenerationOptions create() => DiffusionGenerationOptions._();
  DiffusionGenerationOptions createEmptyInstance() => create();
  static $pb.PbList<DiffusionGenerationOptions> createRepeated() => $pb.PbList<DiffusionGenerationOptions>();
  @$core.pragma('dart2js:noInline')
  static DiffusionGenerationOptions getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DiffusionGenerationOptions>(create);
  static DiffusionGenerationOptions? _defaultInstance;

  /// Text prompt describing the desired image. Required.
  @$pb.TagNumber(1)
  $core.String get prompt => $_getSZ(0);
  @$pb.TagNumber(1)
  set prompt($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPrompt() => $_has(0);
  @$pb.TagNumber(1)
  void clearPrompt() => clearField(1);

  /// Things to avoid in the image. Empty = no negative prompt.
  @$pb.TagNumber(2)
  $core.String get negativePrompt => $_getSZ(1);
  @$pb.TagNumber(2)
  set negativePrompt($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasNegativePrompt() => $_has(1);
  @$pb.TagNumber(2)
  void clearNegativePrompt() => clearField(2);

  /// Output image width  in pixels.  0 = use variant default
  /// (512 for SD 1.5 / SDXS / LCM, 768 for SD 2.1, 1024 for SDXL / Turbo).
  @$pb.TagNumber(3)
  $core.int get width => $_getIZ(2);
  @$pb.TagNumber(3)
  set width($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasWidth() => $_has(2);
  @$pb.TagNumber(3)
  void clearWidth() => clearField(3);

  /// Output image height in pixels.  0 = use variant default.
  @$pb.TagNumber(4)
  $core.int get height => $_getIZ(3);
  @$pb.TagNumber(4)
  set height($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasHeight() => $_has(3);
  @$pb.TagNumber(4)
  void clearHeight() => clearField(4);

  /// Number of denoising steps. Range 1–50 (variant-dependent: SDXS=1,
  /// SDXL_Turbo / LCM=4, SD*=20–28). 0 = use variant default.
  @$pb.TagNumber(5)
  $core.int get numInferenceSteps => $_getIZ(4);
  @$pb.TagNumber(5)
  set numInferenceSteps($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasNumInferenceSteps() => $_has(4);
  @$pb.TagNumber(5)
  void clearNumInferenceSteps() => clearField(5);

  /// Classifier-free guidance scale. 0.0 = no CFG (required for SDXS /
  /// SDXL_Turbo). Typical SD range 1.0–20.0; default 7.5.
  @$pb.TagNumber(6)
  $core.double get guidanceScale => $_getN(5);
  @$pb.TagNumber(6)
  set guidanceScale($core.double v) { $_setFloat(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasGuidanceScale() => $_has(5);
  @$pb.TagNumber(6)
  void clearGuidanceScale() => clearField(6);

  /// RNG seed for reproducibility. -1 = pick a random seed.
  @$pb.TagNumber(7)
  $fixnum.Int64 get seed => $_getI64(6);
  @$pb.TagNumber(7)
  set seed($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasSeed() => $_has(6);
  @$pb.TagNumber(7)
  void clearSeed() => clearField(7);

  /// Sampler algorithm. UNSPECIFIED = backend picks (recommended:
  /// DPMPP_2M_KARRAS).
  @$pb.TagNumber(8)
  DiffusionScheduler get scheduler => $_getN(7);
  @$pb.TagNumber(8)
  set scheduler(DiffusionScheduler v) { setField(8, v); }
  @$pb.TagNumber(8)
  $core.bool hasScheduler() => $_has(7);
  @$pb.TagNumber(8)
  void clearScheduler() => clearField(8);

  /// Generation mode (txt2img / img2img / inpainting). UNSPECIFIED =
  /// TEXT_TO_IMAGE.
  @$pb.TagNumber(9)
  DiffusionMode get mode => $_getN(8);
  @$pb.TagNumber(9)
  set mode(DiffusionMode v) { setField(9, v); }
  @$pb.TagNumber(9)
  $core.bool hasMode() => $_has(8);
  @$pb.TagNumber(9)
  void clearMode() => clearField(9);

  /// Image-to-image / inpainting payloads from rac_diffusion_options_t.
  @$pb.TagNumber(10)
  $core.List<$core.int> get inputImage => $_getN(9);
  @$pb.TagNumber(10)
  set inputImage($core.List<$core.int> v) { $_setBytes(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasInputImage() => $_has(9);
  @$pb.TagNumber(10)
  void clearInputImage() => clearField(10);

  @$pb.TagNumber(11)
  $core.List<$core.int> get maskImage => $_getN(10);
  @$pb.TagNumber(11)
  set maskImage($core.List<$core.int> v) { $_setBytes(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasMaskImage() => $_has(10);
  @$pb.TagNumber(11)
  void clearMaskImage() => clearField(11);

  @$pb.TagNumber(12)
  $core.double get denoiseStrength => $_getN(11);
  @$pb.TagNumber(12)
  set denoiseStrength($core.double v) { $_setFloat(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasDenoiseStrength() => $_has(11);
  @$pb.TagNumber(12)
  void clearDenoiseStrength() => clearField(12);

  /// Progress reporting controls.
  @$pb.TagNumber(13)
  $core.bool get reportIntermediateImages => $_getBF(12);
  @$pb.TagNumber(13)
  set reportIntermediateImages($core.bool v) { $_setBool(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasReportIntermediateImages() => $_has(12);
  @$pb.TagNumber(13)
  void clearReportIntermediateImages() => clearField(13);

  @$pb.TagNumber(14)
  $core.int get progressStride => $_getIZ(13);
  @$pb.TagNumber(14)
  set progressStride($core.int v) { $_setSignedInt32(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasProgressStride() => $_has(13);
  @$pb.TagNumber(14)
  void clearProgressStride() => clearField(14);

  /// Dimensions for raw input_image payloads when the backend cannot infer
  /// them from an encoded container.
  @$pb.TagNumber(15)
  $core.int get inputImageWidth => $_getIZ(14);
  @$pb.TagNumber(15)
  set inputImageWidth($core.int v) { $_setSignedInt32(14, v); }
  @$pb.TagNumber(15)
  $core.bool hasInputImageWidth() => $_has(14);
  @$pb.TagNumber(15)
  void clearInputImageWidth() => clearField(15);

  @$pb.TagNumber(16)
  $core.int get inputImageHeight => $_getIZ(15);
  @$pb.TagNumber(16)
  set inputImageHeight($core.int v) { $_setSignedInt32(15, v); }
  @$pb.TagNumber(16)
  $core.bool hasInputImageHeight() => $_has(15);
  @$pb.TagNumber(16)
  void clearInputImageHeight() => clearField(16);
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
  }) {
    final $result = create();
    if (progressPercent != null) {
      $result.progressPercent = progressPercent;
    }
    if (currentStep != null) {
      $result.currentStep = currentStep;
    }
    if (totalSteps != null) {
      $result.totalSteps = totalSteps;
    }
    if (stage != null) {
      $result.stage = stage;
    }
    if (intermediateImageData != null) {
      $result.intermediateImageData = intermediateImageData;
    }
    if (intermediateImageWidth != null) {
      $result.intermediateImageWidth = intermediateImageWidth;
    }
    if (intermediateImageHeight != null) {
      $result.intermediateImageHeight = intermediateImageHeight;
    }
    return $result;
  }
  DiffusionProgress._() : super();
  factory DiffusionProgress.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DiffusionProgress.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DiffusionProgress', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.double>(1, _omitFieldNames ? '' : 'progressPercent', $pb.PbFieldType.OF)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'currentStep', $pb.PbFieldType.O3)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'totalSteps', $pb.PbFieldType.O3)
    ..aOS(4, _omitFieldNames ? '' : 'stage')
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'intermediateImageData', $pb.PbFieldType.OY)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'intermediateImageWidth', $pb.PbFieldType.O3)
    ..a<$core.int>(7, _omitFieldNames ? '' : 'intermediateImageHeight', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DiffusionProgress clone() => DiffusionProgress()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DiffusionProgress copyWith(void Function(DiffusionProgress) updates) => super.copyWith((message) => updates(message as DiffusionProgress)) as DiffusionProgress;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiffusionProgress create() => DiffusionProgress._();
  DiffusionProgress createEmptyInstance() => create();
  static $pb.PbList<DiffusionProgress> createRepeated() => $pb.PbList<DiffusionProgress>();
  @$core.pragma('dart2js:noInline')
  static DiffusionProgress getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DiffusionProgress>(create);
  static DiffusionProgress? _defaultInstance;

  /// Fraction of denoising completed in [0.0, 1.0].
  @$pb.TagNumber(1)
  $core.double get progressPercent => $_getN(0);
  @$pb.TagNumber(1)
  set progressPercent($core.double v) { $_setFloat(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasProgressPercent() => $_has(0);
  @$pb.TagNumber(1)
  void clearProgressPercent() => clearField(1);

  /// 1-based current step number.
  @$pb.TagNumber(2)
  $core.int get currentStep => $_getIZ(1);
  @$pb.TagNumber(2)
  set currentStep($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCurrentStep() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrentStep() => clearField(2);

  /// Total number of steps the engine plans to execute.
  @$pb.TagNumber(3)
  $core.int get totalSteps => $_getIZ(2);
  @$pb.TagNumber(3)
  set totalSteps($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTotalSteps() => $_has(2);
  @$pb.TagNumber(3)
  void clearTotalSteps() => clearField(3);

  /// Free-form stage name ("Encoding", "Denoising", "Decoding", …).
  @$pb.TagNumber(4)
  $core.String get stage => $_getSZ(3);
  @$pb.TagNumber(4)
  set stage($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasStage() => $_has(3);
  @$pb.TagNumber(4)
  void clearStage() => clearField(4);

  /// Optional intermediate image bytes (PNG when surfaced by
  /// Swift/Kotlin/RN; raw RGBA when surfaced by the C ABI). Present only
  /// when the caller requested intermediate-image reporting and the
  /// engine has produced one for this step.
  @$pb.TagNumber(5)
  $core.List<$core.int> get intermediateImageData => $_getN(4);
  @$pb.TagNumber(5)
  set intermediateImageData($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasIntermediateImageData() => $_has(4);
  @$pb.TagNumber(5)
  void clearIntermediateImageData() => clearField(5);

  /// Dimensions for intermediate_image_data when it is raw pixel data.
  @$pb.TagNumber(6)
  $core.int get intermediateImageWidth => $_getIZ(5);
  @$pb.TagNumber(6)
  set intermediateImageWidth($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasIntermediateImageWidth() => $_has(5);
  @$pb.TagNumber(6)
  void clearIntermediateImageWidth() => clearField(6);

  @$pb.TagNumber(7)
  $core.int get intermediateImageHeight => $_getIZ(6);
  @$pb.TagNumber(7)
  set intermediateImageHeight($core.int v) { $_setSignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasIntermediateImageHeight() => $_has(6);
  @$pb.TagNumber(7)
  void clearIntermediateImageHeight() => clearField(7);
}

///  ---------------------------------------------------------------------------
///  Final generation result. Sources pre-IDL:
///    Swift  DiffusionTypes.swift:560    (DiffusionResult)
///    Kotlin DiffusionTypes.kt:355       (DiffusionResult)
///    RN     DiffusionTypes.ts:185       (DiffusionResult)
///    Web    DiffusionTypes.ts:54        (DiffusionGenerationResult)
///    C ABI  rac_diffusion_types.h:314   (rac_diffusion_result_t)
///
///  Drift note: pre-IDL Swift/Kotlin/RN/Web all name the wall-clock field
///  `generation_time_ms`. The v1 IDL renames it to `total_time_ms` per the
///  spec — round-trip is a pure rename. `used_scheduler` is *new* in the IDL
///  (no pre-IDL surface echoes back which scheduler actually ran when the
///  caller sent UNSPECIFIED); it lets clients log which sampler the engine
///  chose.
///  ---------------------------------------------------------------------------
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
  }) {
    final $result = create();
    if (imageData != null) {
      $result.imageData = imageData;
    }
    if (width != null) {
      $result.width = width;
    }
    if (height != null) {
      $result.height = height;
    }
    if (seedUsed != null) {
      $result.seedUsed = seedUsed;
    }
    if (totalTimeMs != null) {
      $result.totalTimeMs = totalTimeMs;
    }
    if (safetyFlag != null) {
      $result.safetyFlag = safetyFlag;
    }
    if (usedScheduler != null) {
      $result.usedScheduler = usedScheduler;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    return $result;
  }
  DiffusionResult._() : super();
  factory DiffusionResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DiffusionResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DiffusionResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'imageData', $pb.PbFieldType.OY)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'width', $pb.PbFieldType.O3)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'height', $pb.PbFieldType.O3)
    ..aInt64(4, _omitFieldNames ? '' : 'seedUsed')
    ..aInt64(5, _omitFieldNames ? '' : 'totalTimeMs')
    ..aOB(6, _omitFieldNames ? '' : 'safetyFlag')
    ..e<DiffusionScheduler>(7, _omitFieldNames ? '' : 'usedScheduler', $pb.PbFieldType.OE, defaultOrMaker: DiffusionScheduler.DIFFUSION_SCHEDULER_UNSPECIFIED, valueOf: DiffusionScheduler.valueOf, enumValues: DiffusionScheduler.values)
    ..aOS(8, _omitFieldNames ? '' : 'errorMessage')
    ..a<$core.int>(9, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DiffusionResult clone() => DiffusionResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DiffusionResult copyWith(void Function(DiffusionResult) updates) => super.copyWith((message) => updates(message as DiffusionResult)) as DiffusionResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiffusionResult create() => DiffusionResult._();
  DiffusionResult createEmptyInstance() => create();
  static $pb.PbList<DiffusionResult> createRepeated() => $pb.PbList<DiffusionResult>();
  @$core.pragma('dart2js:noInline')
  static DiffusionResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DiffusionResult>(create);
  static DiffusionResult? _defaultInstance;

  /// Encoded image. PNG bytes on Swift/Kotlin/RN; raw RGBA bytes on the
  /// C ABI / Web llamacpp surface. (Encoding is a property of the
  /// backend's vtable, not of this message.)
  @$pb.TagNumber(1)
  $core.List<$core.int> get imageData => $_getN(0);
  @$pb.TagNumber(1)
  set imageData($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasImageData() => $_has(0);
  @$pb.TagNumber(1)
  void clearImageData() => clearField(1);

  /// Final image width  in pixels.
  @$pb.TagNumber(2)
  $core.int get width => $_getIZ(1);
  @$pb.TagNumber(2)
  set width($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasWidth() => $_has(1);
  @$pb.TagNumber(2)
  void clearWidth() => clearField(2);

  /// Final image height in pixels.
  @$pb.TagNumber(3)
  $core.int get height => $_getIZ(2);
  @$pb.TagNumber(3)
  set height($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasHeight() => $_has(2);
  @$pb.TagNumber(3)
  void clearHeight() => clearField(3);

  /// Seed actually used (resolved if the caller passed -1 for random).
  @$pb.TagNumber(4)
  $fixnum.Int64 get seedUsed => $_getI64(3);
  @$pb.TagNumber(4)
  set seedUsed($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSeedUsed() => $_has(3);
  @$pb.TagNumber(4)
  void clearSeedUsed() => clearField(4);

  /// Total wall-clock generation time in milliseconds (renamed from
  /// pre-IDL `generation_time_ms`).
  @$pb.TagNumber(5)
  $fixnum.Int64 get totalTimeMs => $_getI64(4);
  @$pb.TagNumber(5)
  set totalTimeMs($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasTotalTimeMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearTotalTimeMs() => clearField(5);

  /// Whether the safety checker flagged the image as NSFW. False if the
  /// checker was disabled in DiffusionConfiguration.
  @$pb.TagNumber(6)
  $core.bool get safetyFlag => $_getBF(5);
  @$pb.TagNumber(6)
  set safetyFlag($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasSafetyFlag() => $_has(5);
  @$pb.TagNumber(6)
  void clearSafetyFlag() => clearField(6);

  /// Scheduler the engine actually ran. Useful when the caller passed
  /// DIFFUSION_SCHEDULER_UNSPECIFIED.
  @$pb.TagNumber(7)
  DiffusionScheduler get usedScheduler => $_getN(6);
  @$pb.TagNumber(7)
  set usedScheduler(DiffusionScheduler v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasUsedScheduler() => $_has(6);
  @$pb.TagNumber(7)
  void clearUsedScheduler() => clearField(7);

  /// Failure details for result-envelope APIs.
  @$pb.TagNumber(8)
  $core.String get errorMessage => $_getSZ(7);
  @$pb.TagNumber(8)
  set errorMessage($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasErrorMessage() => $_has(7);
  @$pb.TagNumber(8)
  void clearErrorMessage() => clearField(8);

  @$pb.TagNumber(9)
  $core.int get errorCode => $_getIZ(8);
  @$pb.TagNumber(9)
  set errorCode($core.int v) { $_setSignedInt32(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasErrorCode() => $_has(8);
  @$pb.TagNumber(9)
  void clearErrorCode() => clearField(9);
}

///  ---------------------------------------------------------------------------
///  Capability descriptor for the loaded diffusion backend / model. Sources
///  pre-IDL:
///    Swift  DiffusionCapabilities (OptionSet bit flags — supportsTextToImage,
///           supportsImageToImage, supportsInpainting, supportsIntermediateImages,
///           supportsSafetyChecker)
///    Kotlin DiffusionTypes.kt:378       (DiffusionCapabilities, mirror of Swift)
///    RN     DiffusionTypes.ts:210       (interface with supportedVariants /
///           supportedSchedulers / supportedModes / maxWidth / maxHeight /
///           supportsIntermediateImages)
///    Web    — n/a
///    C ABI  rac_diffusion_types.h:352   (rac_diffusion_info_t — flags +
///           max_width / max_height)
///
///  The IDL takes the RN-style "what can the backend do?" shape (lists of
///  supported enums + a single max-resolution scalar) since it carries the
///  most information; SDKs whose pre-IDL surface is a bit-flag set must map
///  each flag to populating / leaving the corresponding repeated field.
///  `max_resolution_px` represents the larger of width/height the backend can
///  produce in a single call (RN/C-ABI carry width and height separately —
///  for square SD models they're equal; for the IDL we fold them to the
///  shared cap and document that asymmetric caps would need a future
///  `max_width_px` / `max_height_px` split).
///  ---------------------------------------------------------------------------
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
  }) {
    final $result = create();
    if (supportedVariants != null) {
      $result.supportedVariants.addAll(supportedVariants);
    }
    if (supportedSchedulers != null) {
      $result.supportedSchedulers.addAll(supportedSchedulers);
    }
    if (maxResolutionPx != null) {
      $result.maxResolutionPx = maxResolutionPx;
    }
    if (supportedModes != null) {
      $result.supportedModes.addAll(supportedModes);
    }
    if (maxWidthPx != null) {
      $result.maxWidthPx = maxWidthPx;
    }
    if (maxHeightPx != null) {
      $result.maxHeightPx = maxHeightPx;
    }
    if (supportsIntermediateImages != null) {
      $result.supportsIntermediateImages = supportsIntermediateImages;
    }
    if (supportsSafetyChecker != null) {
      $result.supportsSafetyChecker = supportsSafetyChecker;
    }
    if (isReady != null) {
      $result.isReady = isReady;
    }
    if (currentModel != null) {
      $result.currentModel = currentModel;
    }
    if (safetyCheckerEnabled != null) {
      $result.safetyCheckerEnabled = safetyCheckerEnabled;
    }
    return $result;
  }
  DiffusionCapabilities._() : super();
  factory DiffusionCapabilities.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DiffusionCapabilities.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DiffusionCapabilities', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pc<DiffusionModelVariant>(1, _omitFieldNames ? '' : 'supportedVariants', $pb.PbFieldType.KE, valueOf: DiffusionModelVariant.valueOf, enumValues: DiffusionModelVariant.values, defaultEnumValue: DiffusionModelVariant.DIFFUSION_MODEL_VARIANT_UNSPECIFIED)
    ..pc<DiffusionScheduler>(2, _omitFieldNames ? '' : 'supportedSchedulers', $pb.PbFieldType.KE, valueOf: DiffusionScheduler.valueOf, enumValues: DiffusionScheduler.values, defaultEnumValue: DiffusionScheduler.DIFFUSION_SCHEDULER_UNSPECIFIED)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'maxResolutionPx', $pb.PbFieldType.O3)
    ..pc<DiffusionMode>(4, _omitFieldNames ? '' : 'supportedModes', $pb.PbFieldType.KE, valueOf: DiffusionMode.valueOf, enumValues: DiffusionMode.values, defaultEnumValue: DiffusionMode.DIFFUSION_MODE_UNSPECIFIED)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'maxWidthPx', $pb.PbFieldType.O3)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'maxHeightPx', $pb.PbFieldType.O3)
    ..aOB(7, _omitFieldNames ? '' : 'supportsIntermediateImages')
    ..aOB(8, _omitFieldNames ? '' : 'supportsSafetyChecker')
    ..aOB(9, _omitFieldNames ? '' : 'isReady')
    ..aOS(10, _omitFieldNames ? '' : 'currentModel')
    ..aOB(11, _omitFieldNames ? '' : 'safetyCheckerEnabled')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DiffusionCapabilities clone() => DiffusionCapabilities()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DiffusionCapabilities copyWith(void Function(DiffusionCapabilities) updates) => super.copyWith((message) => updates(message as DiffusionCapabilities)) as DiffusionCapabilities;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiffusionCapabilities create() => DiffusionCapabilities._();
  DiffusionCapabilities createEmptyInstance() => create();
  static $pb.PbList<DiffusionCapabilities> createRepeated() => $pb.PbList<DiffusionCapabilities>();
  @$core.pragma('dart2js:noInline')
  static DiffusionCapabilities getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DiffusionCapabilities>(create);
  static DiffusionCapabilities? _defaultInstance;

  /// Stable Diffusion model variants this backend can load.
  @$pb.TagNumber(1)
  $core.List<DiffusionModelVariant> get supportedVariants => $_getList(0);

  /// Sampler algorithms this backend implements.
  @$pb.TagNumber(2)
  $core.List<DiffusionScheduler> get supportedSchedulers => $_getList(1);

  /// Largest image edge (in pixels) the backend can produce in a single
  /// generation. 0 = unknown / not advertised.
  @$pb.TagNumber(3)
  $core.int get maxResolutionPx => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxResolutionPx($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMaxResolutionPx() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxResolutionPx() => clearField(3);

  /// Generation modes this backend supports.
  @$pb.TagNumber(4)
  $core.List<DiffusionMode> get supportedModes => $_getList(3);

  /// Asymmetric maximum dimensions when known. 0 = unknown.
  @$pb.TagNumber(5)
  $core.int get maxWidthPx => $_getIZ(4);
  @$pb.TagNumber(5)
  set maxWidthPx($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasMaxWidthPx() => $_has(4);
  @$pb.TagNumber(5)
  void clearMaxWidthPx() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get maxHeightPx => $_getIZ(5);
  @$pb.TagNumber(6)
  set maxHeightPx($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasMaxHeightPx() => $_has(5);
  @$pb.TagNumber(6)
  void clearMaxHeightPx() => clearField(6);

  @$pb.TagNumber(7)
  $core.bool get supportsIntermediateImages => $_getBF(6);
  @$pb.TagNumber(7)
  set supportsIntermediateImages($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasSupportsIntermediateImages() => $_has(6);
  @$pb.TagNumber(7)
  void clearSupportsIntermediateImages() => clearField(7);

  @$pb.TagNumber(8)
  $core.bool get supportsSafetyChecker => $_getBF(7);
  @$pb.TagNumber(8)
  set supportsSafetyChecker($core.bool v) { $_setBool(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasSupportsSafetyChecker() => $_has(7);
  @$pb.TagNumber(8)
  void clearSupportsSafetyChecker() => clearField(8);

  @$pb.TagNumber(9)
  $core.bool get isReady => $_getBF(8);
  @$pb.TagNumber(9)
  set isReady($core.bool v) { $_setBool(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasIsReady() => $_has(8);
  @$pb.TagNumber(9)
  void clearIsReady() => clearField(9);

  @$pb.TagNumber(10)
  $core.String get currentModel => $_getSZ(9);
  @$pb.TagNumber(10)
  set currentModel($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasCurrentModel() => $_has(9);
  @$pb.TagNumber(10)
  void clearCurrentModel() => clearField(10);

  @$pb.TagNumber(11)
  $core.bool get safetyCheckerEnabled => $_getBF(10);
  @$pb.TagNumber(11)
  set safetyCheckerEnabled($core.bool v) { $_setBool(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasSafetyCheckerEnabled() => $_has(10);
  @$pb.TagNumber(11)
  void clearSafetyCheckerEnabled() => clearField(11);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
