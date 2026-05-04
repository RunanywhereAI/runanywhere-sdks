//
//  Generated code. Do not modify.
//  source: vlm_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'model_types.pbenum.dart' as $0;
import 'vlm_options.pbenum.dart';

export 'vlm_options.pbenum.dart';

/// ---------------------------------------------------------------------------
/// Custom VLM chat template.
/// Mirrors rac_vlm_chat_template_t.
/// ---------------------------------------------------------------------------
class VLMChatTemplate extends $pb.GeneratedMessage {
  factory VLMChatTemplate({
    $core.String? templateText,
    $core.String? imageMarker,
    $core.String? defaultSystemPrompt,
  }) {
    final $result = create();
    if (templateText != null) {
      $result.templateText = templateText;
    }
    if (imageMarker != null) {
      $result.imageMarker = imageMarker;
    }
    if (defaultSystemPrompt != null) {
      $result.defaultSystemPrompt = defaultSystemPrompt;
    }
    return $result;
  }
  VLMChatTemplate._() : super();
  factory VLMChatTemplate.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VLMChatTemplate.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VLMChatTemplate', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'templateText')
    ..aOS(2, _omitFieldNames ? '' : 'imageMarker')
    ..aOS(3, _omitFieldNames ? '' : 'defaultSystemPrompt')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VLMChatTemplate clone() => VLMChatTemplate()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VLMChatTemplate copyWith(void Function(VLMChatTemplate) updates) => super.copyWith((message) => updates(message as VLMChatTemplate)) as VLMChatTemplate;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VLMChatTemplate create() => VLMChatTemplate._();
  VLMChatTemplate createEmptyInstance() => create();
  static $pb.PbList<VLMChatTemplate> createRepeated() => $pb.PbList<VLMChatTemplate>();
  @$core.pragma('dart2js:noInline')
  static VLMChatTemplate getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VLMChatTemplate>(create);
  static VLMChatTemplate? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get templateText => $_getSZ(0);
  @$pb.TagNumber(1)
  set templateText($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTemplateText() => $_has(0);
  @$pb.TagNumber(1)
  void clearTemplateText() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get imageMarker => $_getSZ(1);
  @$pb.TagNumber(2)
  set imageMarker($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasImageMarker() => $_has(1);
  @$pb.TagNumber(2)
  void clearImageMarker() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get defaultSystemPrompt => $_getSZ(2);
  @$pb.TagNumber(3)
  set defaultSystemPrompt($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDefaultSystemPrompt() => $_has(2);
  @$pb.TagNumber(3)
  void clearDefaultSystemPrompt() => clearField(3);
}

enum VLMImage_Source {
  filePath, 
  encoded, 
  rawRgb, 
  base64, 
  notSet
}

///  ---------------------------------------------------------------------------
///  VLM image input.
///
///  `source` is a oneof so that exactly one of {file_path, encoded, raw_rgb,
///  base64} can be supplied per request. `width` / `height` are required for
///  non-encoded formats (raw_rgb, raw_rgba) where the consumer cannot infer
///  dimensions from a container header. `format` disambiguates encoded `bytes`
///  payloads (JPEG / PNG / WEBP) and explicitly tags raw / file-path / base64
///  sources.
///  ---------------------------------------------------------------------------
class VLMImage extends $pb.GeneratedMessage {
  factory VLMImage({
    $core.String? filePath,
    $core.List<$core.int>? encoded,
    $core.List<$core.int>? rawRgb,
    $core.String? base64,
    $core.int? width,
    $core.int? height,
    VLMImageFormat? format,
  }) {
    final $result = create();
    if (filePath != null) {
      $result.filePath = filePath;
    }
    if (encoded != null) {
      $result.encoded = encoded;
    }
    if (rawRgb != null) {
      $result.rawRgb = rawRgb;
    }
    if (base64 != null) {
      $result.base64 = base64;
    }
    if (width != null) {
      $result.width = width;
    }
    if (height != null) {
      $result.height = height;
    }
    if (format != null) {
      $result.format = format;
    }
    return $result;
  }
  VLMImage._() : super();
  factory VLMImage.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VLMImage.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, VLMImage_Source> _VLMImage_SourceByTag = {
    1 : VLMImage_Source.filePath,
    2 : VLMImage_Source.encoded,
    3 : VLMImage_Source.rawRgb,
    4 : VLMImage_Source.base64,
    0 : VLMImage_Source.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VLMImage', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..oo(0, [1, 2, 3, 4])
    ..aOS(1, _omitFieldNames ? '' : 'filePath')
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'encoded', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'rawRgb', $pb.PbFieldType.OY)
    ..aOS(4, _omitFieldNames ? '' : 'base64')
    ..a<$core.int>(5, _omitFieldNames ? '' : 'width', $pb.PbFieldType.O3)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'height', $pb.PbFieldType.O3)
    ..e<VLMImageFormat>(7, _omitFieldNames ? '' : 'format', $pb.PbFieldType.OE, defaultOrMaker: VLMImageFormat.VLM_IMAGE_FORMAT_UNSPECIFIED, valueOf: VLMImageFormat.valueOf, enumValues: VLMImageFormat.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VLMImage clone() => VLMImage()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VLMImage copyWith(void Function(VLMImage) updates) => super.copyWith((message) => updates(message as VLMImage)) as VLMImage;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VLMImage create() => VLMImage._();
  VLMImage createEmptyInstance() => create();
  static $pb.PbList<VLMImage> createRepeated() => $pb.PbList<VLMImage>();
  @$core.pragma('dart2js:noInline')
  static VLMImage getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VLMImage>(create);
  static VLMImage? _defaultInstance;

  VLMImage_Source whichSource() => _VLMImage_SourceByTag[$_whichOneof(0)]!;
  void clearSource() => clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get filePath => $_getSZ(0);
  @$pb.TagNumber(1)
  set filePath($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasFilePath() => $_has(0);
  @$pb.TagNumber(1)
  void clearFilePath() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get encoded => $_getN(1);
  @$pb.TagNumber(2)
  set encoded($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasEncoded() => $_has(1);
  @$pb.TagNumber(2)
  void clearEncoded() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get rawRgb => $_getN(2);
  @$pb.TagNumber(3)
  set rawRgb($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRawRgb() => $_has(2);
  @$pb.TagNumber(3)
  void clearRawRgb() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get base64 => $_getSZ(3);
  @$pb.TagNumber(4)
  set base64($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasBase64() => $_has(3);
  @$pb.TagNumber(4)
  void clearBase64() => clearField(4);

  /// Required for VLM_IMAGE_FORMAT_RAW_RGB and VLM_IMAGE_FORMAT_RAW_RGBA
  /// (consumers cannot infer dimensions for raw pixel buffers). Optional
  /// for encoded / file_path / base64 sources where the decoder reads
  /// dimensions from the container.
  @$pb.TagNumber(5)
  $core.int get width => $_getIZ(4);
  @$pb.TagNumber(5)
  set width($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasWidth() => $_has(4);
  @$pb.TagNumber(5)
  void clearWidth() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get height => $_getIZ(5);
  @$pb.TagNumber(6)
  set height($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasHeight() => $_has(5);
  @$pb.TagNumber(6)
  void clearHeight() => clearField(6);

  @$pb.TagNumber(7)
  VLMImageFormat get format => $_getN(6);
  @$pb.TagNumber(7)
  set format(VLMImageFormat v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasFormat() => $_has(6);
  @$pb.TagNumber(7)
  void clearFormat() => clearField(7);
}

///  ---------------------------------------------------------------------------
///  VLM component configuration.
///  Sources pre-IDL:
///    Kotlin VLMTypes.kt:163        (modelId, contextLength, temperature,
///                                   maxTokens, systemPrompt, streamingEnabled,
///                                   preferredFramework)
///    C ABI  rac_vlm_types.h:224    (model_id, preferred_framework,
///                                   context_length, temperature, max_tokens,
///                                   system_prompt, streaming_enabled)
///
///  Per the canonicalization brief, only the load-bearing identification +
///  limits cross the IDL boundary here: model_id, max_image_size_px, max_tokens.
///  Per-request sampling parameters live on VLMGenerationOptions; runtime
///  streaming toggles and chat-template selection stay backend-private.
///  ---------------------------------------------------------------------------
class VLMConfiguration extends $pb.GeneratedMessage {
  factory VLMConfiguration({
    $core.String? modelId,
    $core.int? maxImageSizePx,
    $core.int? maxTokens,
    $core.int? contextLength,
    $core.double? temperature,
    $core.String? systemPrompt,
    $core.bool? streamingEnabled,
    $0.InferenceFramework? preferredFramework,
  }) {
    final $result = create();
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (maxImageSizePx != null) {
      $result.maxImageSizePx = maxImageSizePx;
    }
    if (maxTokens != null) {
      $result.maxTokens = maxTokens;
    }
    if (contextLength != null) {
      $result.contextLength = contextLength;
    }
    if (temperature != null) {
      $result.temperature = temperature;
    }
    if (systemPrompt != null) {
      $result.systemPrompt = systemPrompt;
    }
    if (streamingEnabled != null) {
      $result.streamingEnabled = streamingEnabled;
    }
    if (preferredFramework != null) {
      $result.preferredFramework = preferredFramework;
    }
    return $result;
  }
  VLMConfiguration._() : super();
  factory VLMConfiguration.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VLMConfiguration.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VLMConfiguration', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..a<$core.int>(2, _omitFieldNames ? '' : 'maxImageSizePx', $pb.PbFieldType.O3)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'maxTokens', $pb.PbFieldType.O3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'contextLength', $pb.PbFieldType.O3)
    ..a<$core.double>(5, _omitFieldNames ? '' : 'temperature', $pb.PbFieldType.OF)
    ..aOS(6, _omitFieldNames ? '' : 'systemPrompt')
    ..aOB(7, _omitFieldNames ? '' : 'streamingEnabled')
    ..e<$0.InferenceFramework>(8, _omitFieldNames ? '' : 'preferredFramework', $pb.PbFieldType.OE, defaultOrMaker: $0.InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED, valueOf: $0.InferenceFramework.valueOf, enumValues: $0.InferenceFramework.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VLMConfiguration clone() => VLMConfiguration()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VLMConfiguration copyWith(void Function(VLMConfiguration) updates) => super.copyWith((message) => updates(message as VLMConfiguration)) as VLMConfiguration;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VLMConfiguration create() => VLMConfiguration._();
  VLMConfiguration createEmptyInstance() => create();
  static $pb.PbList<VLMConfiguration> createRepeated() => $pb.PbList<VLMConfiguration>();
  @$core.pragma('dart2js:noInline')
  static VLMConfiguration getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VLMConfiguration>(create);
  static VLMConfiguration? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get maxImageSizePx => $_getIZ(1);
  @$pb.TagNumber(2)
  set maxImageSizePx($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMaxImageSizePx() => $_has(1);
  @$pb.TagNumber(2)
  void clearMaxImageSizePx() => clearField(2);

  /// (0 = backend default)
  @$pb.TagNumber(3)
  $core.int get maxTokens => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxTokens($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMaxTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxTokens() => clearField(3);

  /// Additional component-level fields from rac_vlm_config_t.
  @$pb.TagNumber(4)
  $core.int get contextLength => $_getIZ(3);
  @$pb.TagNumber(4)
  set contextLength($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasContextLength() => $_has(3);
  @$pb.TagNumber(4)
  void clearContextLength() => clearField(4);

  @$pb.TagNumber(5)
  $core.double get temperature => $_getN(4);
  @$pb.TagNumber(5)
  set temperature($core.double v) { $_setFloat(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasTemperature() => $_has(4);
  @$pb.TagNumber(5)
  void clearTemperature() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get systemPrompt => $_getSZ(5);
  @$pb.TagNumber(6)
  set systemPrompt($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasSystemPrompt() => $_has(5);
  @$pb.TagNumber(6)
  void clearSystemPrompt() => clearField(6);

  @$pb.TagNumber(7)
  $core.bool get streamingEnabled => $_getBF(6);
  @$pb.TagNumber(7)
  set streamingEnabled($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasStreamingEnabled() => $_has(6);
  @$pb.TagNumber(7)
  void clearStreamingEnabled() => clearField(7);

  @$pb.TagNumber(8)
  $0.InferenceFramework get preferredFramework => $_getN(7);
  @$pb.TagNumber(8)
  set preferredFramework($0.InferenceFramework v) { setField(8, v); }
  @$pb.TagNumber(8)
  $core.bool hasPreferredFramework() => $_has(7);
  @$pb.TagNumber(8)
  void clearPreferredFramework() => clearField(8);
}

///  ---------------------------------------------------------------------------
///  VLM generation options — per-request sampling + prompt parameters.
///  Sources pre-IDL:
///    Kotlin VLMTypes.kt:103        (maxTokens, temperature, topP, systemPrompt,
///                                   maxImageSize, nThreads, useGpu)
///    Dart   vlm_types.dart:127     (maxTokens, temperature, topP, systemPrompt,
///                                   maxImageSize, nThreads, useGpu)
///    RN     VLMTypes.ts:21         (maxTokens, temperature, topP)
///    Web    VLMTypes.ts:28         (maxTokens, temperature, topP, systemPrompt,
///                                   modelFamily, streaming)
///    C ABI  rac_vlm_types.h:143    (max_tokens, temperature, top_p,
///                                   stop_sequences, num_stop_sequences,
///                                   streaming_enabled, system_prompt,
///                                   max_image_size, n_threads, use_gpu,
///                                   model_family, custom_chat_template,
///                                   image_marker_override)
///
///  top_k is included to align with the other text generation services
///  (LLM / chat) even though no current VLM SDK exposes it; the C ABI's
///  llama.cpp backend already supports top_k internally.
///  ---------------------------------------------------------------------------
class VLMGenerationOptions extends $pb.GeneratedMessage {
  factory VLMGenerationOptions({
    $core.String? prompt,
    $core.int? maxTokens,
    $core.double? temperature,
    $core.double? topP,
    $core.int? topK,
    $core.Iterable<$core.String>? stopSequences,
    $core.bool? streamingEnabled,
    $core.String? systemPrompt,
    $core.int? maxImageSize,
    $core.int? nThreads,
    $core.bool? useGpu,
    VLMModelFamily? modelFamily,
    VLMChatTemplate? customChatTemplate,
    $core.String? imageMarkerOverride,
  }) {
    final $result = create();
    if (prompt != null) {
      $result.prompt = prompt;
    }
    if (maxTokens != null) {
      $result.maxTokens = maxTokens;
    }
    if (temperature != null) {
      $result.temperature = temperature;
    }
    if (topP != null) {
      $result.topP = topP;
    }
    if (topK != null) {
      $result.topK = topK;
    }
    if (stopSequences != null) {
      $result.stopSequences.addAll(stopSequences);
    }
    if (streamingEnabled != null) {
      $result.streamingEnabled = streamingEnabled;
    }
    if (systemPrompt != null) {
      $result.systemPrompt = systemPrompt;
    }
    if (maxImageSize != null) {
      $result.maxImageSize = maxImageSize;
    }
    if (nThreads != null) {
      $result.nThreads = nThreads;
    }
    if (useGpu != null) {
      $result.useGpu = useGpu;
    }
    if (modelFamily != null) {
      $result.modelFamily = modelFamily;
    }
    if (customChatTemplate != null) {
      $result.customChatTemplate = customChatTemplate;
    }
    if (imageMarkerOverride != null) {
      $result.imageMarkerOverride = imageMarkerOverride;
    }
    return $result;
  }
  VLMGenerationOptions._() : super();
  factory VLMGenerationOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VLMGenerationOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VLMGenerationOptions', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'prompt')
    ..a<$core.int>(2, _omitFieldNames ? '' : 'maxTokens', $pb.PbFieldType.O3)
    ..a<$core.double>(3, _omitFieldNames ? '' : 'temperature', $pb.PbFieldType.OF)
    ..a<$core.double>(4, _omitFieldNames ? '' : 'topP', $pb.PbFieldType.OF)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'topK', $pb.PbFieldType.O3)
    ..pPS(6, _omitFieldNames ? '' : 'stopSequences')
    ..aOB(7, _omitFieldNames ? '' : 'streamingEnabled')
    ..aOS(8, _omitFieldNames ? '' : 'systemPrompt')
    ..a<$core.int>(9, _omitFieldNames ? '' : 'maxImageSize', $pb.PbFieldType.O3)
    ..a<$core.int>(10, _omitFieldNames ? '' : 'nThreads', $pb.PbFieldType.O3)
    ..aOB(11, _omitFieldNames ? '' : 'useGpu')
    ..e<VLMModelFamily>(12, _omitFieldNames ? '' : 'modelFamily', $pb.PbFieldType.OE, defaultOrMaker: VLMModelFamily.VLM_MODEL_FAMILY_UNSPECIFIED, valueOf: VLMModelFamily.valueOf, enumValues: VLMModelFamily.values)
    ..aOM<VLMChatTemplate>(13, _omitFieldNames ? '' : 'customChatTemplate', subBuilder: VLMChatTemplate.create)
    ..aOS(14, _omitFieldNames ? '' : 'imageMarkerOverride')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VLMGenerationOptions clone() => VLMGenerationOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VLMGenerationOptions copyWith(void Function(VLMGenerationOptions) updates) => super.copyWith((message) => updates(message as VLMGenerationOptions)) as VLMGenerationOptions;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VLMGenerationOptions create() => VLMGenerationOptions._();
  VLMGenerationOptions createEmptyInstance() => create();
  static $pb.PbList<VLMGenerationOptions> createRepeated() => $pb.PbList<VLMGenerationOptions>();
  @$core.pragma('dart2js:noInline')
  static VLMGenerationOptions getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VLMGenerationOptions>(create);
  static VLMGenerationOptions? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get prompt => $_getSZ(0);
  @$pb.TagNumber(1)
  set prompt($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPrompt() => $_has(0);
  @$pb.TagNumber(1)
  void clearPrompt() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get maxTokens => $_getIZ(1);
  @$pb.TagNumber(2)
  set maxTokens($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMaxTokens() => $_has(1);
  @$pb.TagNumber(2)
  void clearMaxTokens() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get temperature => $_getN(2);
  @$pb.TagNumber(3)
  set temperature($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTemperature() => $_has(2);
  @$pb.TagNumber(3)
  void clearTemperature() => clearField(3);

  @$pb.TagNumber(4)
  $core.double get topP => $_getN(3);
  @$pb.TagNumber(4)
  set topP($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTopP() => $_has(3);
  @$pb.TagNumber(4)
  void clearTopP() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get topK => $_getIZ(4);
  @$pb.TagNumber(5)
  set topK($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasTopK() => $_has(4);
  @$pb.TagNumber(5)
  void clearTopK() => clearField(5);

  /// Full rac_vlm_options_t coverage.
  @$pb.TagNumber(6)
  $core.List<$core.String> get stopSequences => $_getList(5);

  @$pb.TagNumber(7)
  $core.bool get streamingEnabled => $_getBF(6);
  @$pb.TagNumber(7)
  set streamingEnabled($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasStreamingEnabled() => $_has(6);
  @$pb.TagNumber(7)
  void clearStreamingEnabled() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get systemPrompt => $_getSZ(7);
  @$pb.TagNumber(8)
  set systemPrompt($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasSystemPrompt() => $_has(7);
  @$pb.TagNumber(8)
  void clearSystemPrompt() => clearField(8);

  @$pb.TagNumber(9)
  $core.int get maxImageSize => $_getIZ(8);
  @$pb.TagNumber(9)
  set maxImageSize($core.int v) { $_setSignedInt32(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasMaxImageSize() => $_has(8);
  @$pb.TagNumber(9)
  void clearMaxImageSize() => clearField(9);

  @$pb.TagNumber(10)
  $core.int get nThreads => $_getIZ(9);
  @$pb.TagNumber(10)
  set nThreads($core.int v) { $_setSignedInt32(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasNThreads() => $_has(9);
  @$pb.TagNumber(10)
  void clearNThreads() => clearField(10);

  @$pb.TagNumber(11)
  $core.bool get useGpu => $_getBF(10);
  @$pb.TagNumber(11)
  set useGpu($core.bool v) { $_setBool(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasUseGpu() => $_has(10);
  @$pb.TagNumber(11)
  void clearUseGpu() => clearField(11);

  @$pb.TagNumber(12)
  VLMModelFamily get modelFamily => $_getN(11);
  @$pb.TagNumber(12)
  set modelFamily(VLMModelFamily v) { setField(12, v); }
  @$pb.TagNumber(12)
  $core.bool hasModelFamily() => $_has(11);
  @$pb.TagNumber(12)
  void clearModelFamily() => clearField(12);

  @$pb.TagNumber(13)
  VLMChatTemplate get customChatTemplate => $_getN(12);
  @$pb.TagNumber(13)
  set customChatTemplate(VLMChatTemplate v) { setField(13, v); }
  @$pb.TagNumber(13)
  $core.bool hasCustomChatTemplate() => $_has(12);
  @$pb.TagNumber(13)
  void clearCustomChatTemplate() => clearField(13);
  @$pb.TagNumber(13)
  VLMChatTemplate ensureCustomChatTemplate() => $_ensure(12);

  @$pb.TagNumber(14)
  $core.String get imageMarkerOverride => $_getSZ(13);
  @$pb.TagNumber(14)
  set imageMarkerOverride($core.String v) { $_setString(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasImageMarkerOverride() => $_has(13);
  @$pb.TagNumber(14)
  void clearImageMarkerOverride() => clearField(14);
}

///  ---------------------------------------------------------------------------
///  VLM generation result.
///  Sources pre-IDL:
///    Swift  VLMTypes.swift:208     (text, promptTokens, completionTokens,
///                                   totalTimeMs as Double, tokensPerSecond)
///    Kotlin VLMTypes.kt:120        (text, promptTokens, imageTokens,
///                                   completionTokens, totalTokens,
///                                   timeToFirstTokenMs, imageEncodeTimeMs,
///                                   totalTimeMs, tokensPerSecond)
///    Dart   vlm_types.dart:68      (text, promptTokens, completionTokens,
///                                   totalTimeMs, tokensPerSecond)
///    RN     VLMTypes.ts:28         (text, promptTokens, completionTokens,
///                                   totalTimeMs, tokensPerSecond)
///    Web    VLMTypes.ts:38         (VLMGenerationResult: text, promptTokens,
///                                   imageTokens, completionTokens, totalTokens,
///                                   timeToFirstTokenMs, imageEncodeTimeMs,
///                                   totalTimeMs, tokensPerSecond, hardwareUsed)
///    C ABI  rac_vlm_types.h:268    (text, prompt_tokens, image_tokens,
///                                   completion_tokens, total_tokens,
///                                   time_to_first_token_ms,
///                                   image_encode_time_ms, total_time_ms,
///                                   tokens_per_second)
///
///  Streaming note: streaming results reuse this VLMResult message; per-token
///  text deltas are emitted on the existing LLM stream channel
///  (llm_service.proto streaming surface). No VLM-specific stream-event message
///  is introduced here.
///  ---------------------------------------------------------------------------
class VLMResult extends $pb.GeneratedMessage {
  factory VLMResult({
    $core.String? text,
    $core.int? promptTokens,
    $core.int? completionTokens,
    $fixnum.Int64? totalTokens,
    $fixnum.Int64? processingTimeMs,
    $core.double? tokensPerSecond,
    $core.int? imageTokens,
    $fixnum.Int64? timeToFirstTokenMs,
    $fixnum.Int64? imageEncodeTimeMs,
    $core.String? hardwareUsed,
  }) {
    final $result = create();
    if (text != null) {
      $result.text = text;
    }
    if (promptTokens != null) {
      $result.promptTokens = promptTokens;
    }
    if (completionTokens != null) {
      $result.completionTokens = completionTokens;
    }
    if (totalTokens != null) {
      $result.totalTokens = totalTokens;
    }
    if (processingTimeMs != null) {
      $result.processingTimeMs = processingTimeMs;
    }
    if (tokensPerSecond != null) {
      $result.tokensPerSecond = tokensPerSecond;
    }
    if (imageTokens != null) {
      $result.imageTokens = imageTokens;
    }
    if (timeToFirstTokenMs != null) {
      $result.timeToFirstTokenMs = timeToFirstTokenMs;
    }
    if (imageEncodeTimeMs != null) {
      $result.imageEncodeTimeMs = imageEncodeTimeMs;
    }
    if (hardwareUsed != null) {
      $result.hardwareUsed = hardwareUsed;
    }
    return $result;
  }
  VLMResult._() : super();
  factory VLMResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VLMResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VLMResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..a<$core.int>(2, _omitFieldNames ? '' : 'promptTokens', $pb.PbFieldType.O3)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'completionTokens', $pb.PbFieldType.O3)
    ..aInt64(4, _omitFieldNames ? '' : 'totalTokens')
    ..aInt64(5, _omitFieldNames ? '' : 'processingTimeMs')
    ..a<$core.double>(6, _omitFieldNames ? '' : 'tokensPerSecond', $pb.PbFieldType.OF)
    ..a<$core.int>(7, _omitFieldNames ? '' : 'imageTokens', $pb.PbFieldType.O3)
    ..aInt64(8, _omitFieldNames ? '' : 'timeToFirstTokenMs')
    ..aInt64(9, _omitFieldNames ? '' : 'imageEncodeTimeMs')
    ..aOS(10, _omitFieldNames ? '' : 'hardwareUsed')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VLMResult clone() => VLMResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VLMResult copyWith(void Function(VLMResult) updates) => super.copyWith((message) => updates(message as VLMResult)) as VLMResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VLMResult create() => VLMResult._();
  VLMResult createEmptyInstance() => create();
  static $pb.PbList<VLMResult> createRepeated() => $pb.PbList<VLMResult>();
  @$core.pragma('dart2js:noInline')
  static VLMResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VLMResult>(create);
  static VLMResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get promptTokens => $_getIZ(1);
  @$pb.TagNumber(2)
  set promptTokens($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasPromptTokens() => $_has(1);
  @$pb.TagNumber(2)
  void clearPromptTokens() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get completionTokens => $_getIZ(2);
  @$pb.TagNumber(3)
  set completionTokens($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasCompletionTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearCompletionTokens() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get totalTokens => $_getI64(3);
  @$pb.TagNumber(4)
  set totalTokens($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTotalTokens() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalTokens() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get processingTimeMs => $_getI64(4);
  @$pb.TagNumber(5)
  set processingTimeMs($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasProcessingTimeMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearProcessingTimeMs() => clearField(5);

  /// Swift VLMResult totalTimeMs (Double ms).
  @$pb.TagNumber(6)
  $core.double get tokensPerSecond => $_getN(5);
  @$pb.TagNumber(6)
  set tokensPerSecond($core.double v) { $_setFloat(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTokensPerSecond() => $_has(5);
  @$pb.TagNumber(6)
  void clearTokensPerSecond() => clearField(6);

  /// Detailed VLM metrics from Kotlin/Web/C ABI.
  @$pb.TagNumber(7)
  $core.int get imageTokens => $_getIZ(6);
  @$pb.TagNumber(7)
  set imageTokens($core.int v) { $_setSignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasImageTokens() => $_has(6);
  @$pb.TagNumber(7)
  void clearImageTokens() => clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get timeToFirstTokenMs => $_getI64(7);
  @$pb.TagNumber(8)
  set timeToFirstTokenMs($fixnum.Int64 v) { $_setInt64(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasTimeToFirstTokenMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearTimeToFirstTokenMs() => clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get imageEncodeTimeMs => $_getI64(8);
  @$pb.TagNumber(9)
  set imageEncodeTimeMs($fixnum.Int64 v) { $_setInt64(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasImageEncodeTimeMs() => $_has(8);
  @$pb.TagNumber(9)
  void clearImageEncodeTimeMs() => clearField(9);

  @$pb.TagNumber(10)
  $core.String get hardwareUsed => $_getSZ(9);
  @$pb.TagNumber(10)
  set hardwareUsed($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasHardwareUsed() => $_has(9);
  @$pb.TagNumber(10)
  void clearHardwareUsed() => clearField(10);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
