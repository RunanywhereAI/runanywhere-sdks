//
//  Generated code. Do not modify.
//  source: vlm_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:async' as $async;
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
    $core.String? mediaType,
    $core.String? name,
    $fixnum.Int64? sizeBytes,
    $core.Map<$core.String, $core.String>? metadata,
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
    if (mediaType != null) {
      $result.mediaType = mediaType;
    }
    if (name != null) {
      $result.name = name;
    }
    if (sizeBytes != null) {
      $result.sizeBytes = sizeBytes;
    }
    if (metadata != null) {
      $result.metadata.addAll(metadata);
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
    ..aOS(8, _omitFieldNames ? '' : 'mediaType')
    ..aOS(9, _omitFieldNames ? '' : 'name')
    ..aInt64(10, _omitFieldNames ? '' : 'sizeBytes')
    ..m<$core.String, $core.String>(11, _omitFieldNames ? '' : 'metadata', entryClassName: 'VLMImage.MetadataEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('runanywhere.v1'))
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

  /// Optional source metadata. Adapters may populate this after camera/file
  /// picker capture without exposing native APIs to core.
  @$pb.TagNumber(8)
  $core.String get mediaType => $_getSZ(7);
  @$pb.TagNumber(8)
  set mediaType($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasMediaType() => $_has(7);
  @$pb.TagNumber(8)
  void clearMediaType() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get name => $_getSZ(8);
  @$pb.TagNumber(9)
  set name($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasName() => $_has(8);
  @$pb.TagNumber(9)
  void clearName() => clearField(9);

  @$pb.TagNumber(10)
  $fixnum.Int64 get sizeBytes => $_getI64(9);
  @$pb.TagNumber(10)
  set sizeBytes($fixnum.Int64 v) { $_setInt64(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasSizeBytes() => $_has(9);
  @$pb.TagNumber(10)
  void clearSizeBytes() => clearField(10);

  @$pb.TagNumber(11)
  $core.Map<$core.String, $core.String> get metadata => $_getMap(10);
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
    $fixnum.Int64? seed,
    $core.double? repetitionPenalty,
    $core.double? minP,
    $core.bool? emitImageEmbeddings,
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
    if (seed != null) {
      $result.seed = seed;
    }
    if (repetitionPenalty != null) {
      $result.repetitionPenalty = repetitionPenalty;
    }
    if (minP != null) {
      $result.minP = minP;
    }
    if (emitImageEmbeddings != null) {
      $result.emitImageEmbeddings = emitImageEmbeddings;
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
    ..aInt64(15, _omitFieldNames ? '' : 'seed')
    ..a<$core.double>(16, _omitFieldNames ? '' : 'repetitionPenalty', $pb.PbFieldType.OF)
    ..a<$core.double>(17, _omitFieldNames ? '' : 'minP', $pb.PbFieldType.OF)
    ..aOB(18, _omitFieldNames ? '' : 'emitImageEmbeddings')
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

  /// Additional llama.cpp sampling knobs and result controls.
  @$pb.TagNumber(15)
  $fixnum.Int64 get seed => $_getI64(14);
  @$pb.TagNumber(15)
  set seed($fixnum.Int64 v) { $_setInt64(14, v); }
  @$pb.TagNumber(15)
  $core.bool hasSeed() => $_has(14);
  @$pb.TagNumber(15)
  void clearSeed() => clearField(15);

  @$pb.TagNumber(16)
  $core.double get repetitionPenalty => $_getN(15);
  @$pb.TagNumber(16)
  set repetitionPenalty($core.double v) { $_setFloat(15, v); }
  @$pb.TagNumber(16)
  $core.bool hasRepetitionPenalty() => $_has(15);
  @$pb.TagNumber(16)
  void clearRepetitionPenalty() => clearField(16);

  @$pb.TagNumber(17)
  $core.double get minP => $_getN(16);
  @$pb.TagNumber(17)
  set minP($core.double v) { $_setFloat(16, v); }
  @$pb.TagNumber(17)
  $core.bool hasMinP() => $_has(16);
  @$pb.TagNumber(17)
  void clearMinP() => clearField(17);

  @$pb.TagNumber(18)
  $core.bool get emitImageEmbeddings => $_getBF(17);
  @$pb.TagNumber(18)
  set emitImageEmbeddings($core.bool v) { $_setBool(17, v); }
  @$pb.TagNumber(18)
  $core.bool hasEmitImageEmbeddings() => $_has(17);
  @$pb.TagNumber(18)
  void clearEmitImageEmbeddings() => clearField(18);
}

class VLMGenerationRequest extends $pb.GeneratedMessage {
  factory VLMGenerationRequest({
    $core.String? requestId,
    $core.Iterable<VLMImage>? images,
    VLMGenerationOptions? options,
    $core.String? modelId,
    $core.Map<$core.String, $core.String>? metadata,
  }) {
    final $result = create();
    if (requestId != null) {
      $result.requestId = requestId;
    }
    if (images != null) {
      $result.images.addAll(images);
    }
    if (options != null) {
      $result.options = options;
    }
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (metadata != null) {
      $result.metadata.addAll(metadata);
    }
    return $result;
  }
  VLMGenerationRequest._() : super();
  factory VLMGenerationRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VLMGenerationRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VLMGenerationRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..pc<VLMImage>(2, _omitFieldNames ? '' : 'images', $pb.PbFieldType.PM, subBuilder: VLMImage.create)
    ..aOM<VLMGenerationOptions>(3, _omitFieldNames ? '' : 'options', subBuilder: VLMGenerationOptions.create)
    ..aOS(4, _omitFieldNames ? '' : 'modelId')
    ..m<$core.String, $core.String>(5, _omitFieldNames ? '' : 'metadata', entryClassName: 'VLMGenerationRequest.MetadataEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VLMGenerationRequest clone() => VLMGenerationRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VLMGenerationRequest copyWith(void Function(VLMGenerationRequest) updates) => super.copyWith((message) => updates(message as VLMGenerationRequest)) as VLMGenerationRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VLMGenerationRequest create() => VLMGenerationRequest._();
  VLMGenerationRequest createEmptyInstance() => create();
  static $pb.PbList<VLMGenerationRequest> createRepeated() => $pb.PbList<VLMGenerationRequest>();
  @$core.pragma('dart2js:noInline')
  static VLMGenerationRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VLMGenerationRequest>(create);
  static VLMGenerationRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<VLMImage> get images => $_getList(1);

  @$pb.TagNumber(3)
  VLMGenerationOptions get options => $_getN(2);
  @$pb.TagNumber(3)
  set options(VLMGenerationOptions v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasOptions() => $_has(2);
  @$pb.TagNumber(3)
  void clearOptions() => clearField(3);
  @$pb.TagNumber(3)
  VLMGenerationOptions ensureOptions() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.String get modelId => $_getSZ(3);
  @$pb.TagNumber(4)
  set modelId($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasModelId() => $_has(3);
  @$pb.TagNumber(4)
  void clearModelId() => clearField(4);

  @$pb.TagNumber(5)
  $core.Map<$core.String, $core.String> get metadata => $_getMap(4);
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
///  Streaming note: the VLM service emits VLMStreamEvent messages for
///  per-token deltas and terminal results; this aggregate result is carried on
///  the unary Generate RPC and on terminal stream events.
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
    $core.String? errorMessage,
    $core.int? errorCode,
    $core.String? finishReason,
    $core.int? imagesProcessed,
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
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    if (finishReason != null) {
      $result.finishReason = finishReason;
    }
    if (imagesProcessed != null) {
      $result.imagesProcessed = imagesProcessed;
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
    ..aOS(11, _omitFieldNames ? '' : 'errorMessage')
    ..a<$core.int>(12, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..aOS(13, _omitFieldNames ? '' : 'finishReason')
    ..a<$core.int>(14, _omitFieldNames ? '' : 'imagesProcessed', $pb.PbFieldType.O3)
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

  @$pb.TagNumber(11)
  $core.String get errorMessage => $_getSZ(10);
  @$pb.TagNumber(11)
  set errorMessage($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasErrorMessage() => $_has(10);
  @$pb.TagNumber(11)
  void clearErrorMessage() => clearField(11);

  @$pb.TagNumber(12)
  $core.int get errorCode => $_getIZ(11);
  @$pb.TagNumber(12)
  set errorCode($core.int v) { $_setSignedInt32(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasErrorCode() => $_has(11);
  @$pb.TagNumber(12)
  void clearErrorCode() => clearField(12);

  @$pb.TagNumber(13)
  $core.String get finishReason => $_getSZ(12);
  @$pb.TagNumber(13)
  set finishReason($core.String v) { $_setString(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasFinishReason() => $_has(12);
  @$pb.TagNumber(13)
  void clearFinishReason() => clearField(13);

  @$pb.TagNumber(14)
  $core.int get imagesProcessed => $_getIZ(13);
  @$pb.TagNumber(14)
  set imagesProcessed($core.int v) { $_setSignedInt32(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasImagesProcessed() => $_has(13);
  @$pb.TagNumber(14)
  void clearImagesProcessed() => clearField(14);
}

class VLMStreamEvent extends $pb.GeneratedMessage {
  factory VLMStreamEvent({
    $fixnum.Int64? seq,
    $fixnum.Int64? timestampUs,
    $core.String? requestId,
    VLMStreamEventKind? kind,
    $core.String? token,
    $core.int? tokenIndex,
    $core.bool? isFinal,
    $core.double? tokensPerSecond,
    VLMResult? result,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final $result = create();
    if (seq != null) {
      $result.seq = seq;
    }
    if (timestampUs != null) {
      $result.timestampUs = timestampUs;
    }
    if (requestId != null) {
      $result.requestId = requestId;
    }
    if (kind != null) {
      $result.kind = kind;
    }
    if (token != null) {
      $result.token = token;
    }
    if (tokenIndex != null) {
      $result.tokenIndex = tokenIndex;
    }
    if (isFinal != null) {
      $result.isFinal = isFinal;
    }
    if (tokensPerSecond != null) {
      $result.tokensPerSecond = tokensPerSecond;
    }
    if (result != null) {
      $result.result = result;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    return $result;
  }
  VLMStreamEvent._() : super();
  factory VLMStreamEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VLMStreamEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VLMStreamEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(3, _omitFieldNames ? '' : 'requestId')
    ..e<VLMStreamEventKind>(4, _omitFieldNames ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: VLMStreamEventKind.VLM_STREAM_EVENT_KIND_UNSPECIFIED, valueOf: VLMStreamEventKind.valueOf, enumValues: VLMStreamEventKind.values)
    ..aOS(5, _omitFieldNames ? '' : 'token')
    ..a<$core.int>(6, _omitFieldNames ? '' : 'tokenIndex', $pb.PbFieldType.O3)
    ..aOB(7, _omitFieldNames ? '' : 'isFinal')
    ..a<$core.double>(8, _omitFieldNames ? '' : 'tokensPerSecond', $pb.PbFieldType.OF)
    ..aOM<VLMResult>(9, _omitFieldNames ? '' : 'result', subBuilder: VLMResult.create)
    ..aOS(10, _omitFieldNames ? '' : 'errorMessage')
    ..a<$core.int>(11, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VLMStreamEvent clone() => VLMStreamEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VLMStreamEvent copyWith(void Function(VLMStreamEvent) updates) => super.copyWith((message) => updates(message as VLMStreamEvent)) as VLMStreamEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VLMStreamEvent create() => VLMStreamEvent._();
  VLMStreamEvent createEmptyInstance() => create();
  static $pb.PbList<VLMStreamEvent> createRepeated() => $pb.PbList<VLMStreamEvent>();
  @$core.pragma('dart2js:noInline')
  static VLMStreamEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VLMStreamEvent>(create);
  static VLMStreamEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get seq => $_getI64(0);
  @$pb.TagNumber(1)
  set seq($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampUs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampUs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTimestampUs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampUs() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get requestId => $_getSZ(2);
  @$pb.TagNumber(3)
  set requestId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRequestId() => $_has(2);
  @$pb.TagNumber(3)
  void clearRequestId() => clearField(3);

  @$pb.TagNumber(4)
  VLMStreamEventKind get kind => $_getN(3);
  @$pb.TagNumber(4)
  set kind(VLMStreamEventKind v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasKind() => $_has(3);
  @$pb.TagNumber(4)
  void clearKind() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get token => $_getSZ(4);
  @$pb.TagNumber(5)
  set token($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasToken() => $_has(4);
  @$pb.TagNumber(5)
  void clearToken() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get tokenIndex => $_getIZ(5);
  @$pb.TagNumber(6)
  set tokenIndex($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTokenIndex() => $_has(5);
  @$pb.TagNumber(6)
  void clearTokenIndex() => clearField(6);

  @$pb.TagNumber(7)
  $core.bool get isFinal => $_getBF(6);
  @$pb.TagNumber(7)
  set isFinal($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasIsFinal() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsFinal() => clearField(7);

  @$pb.TagNumber(8)
  $core.double get tokensPerSecond => $_getN(7);
  @$pb.TagNumber(8)
  set tokensPerSecond($core.double v) { $_setFloat(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasTokensPerSecond() => $_has(7);
  @$pb.TagNumber(8)
  void clearTokensPerSecond() => clearField(8);

  @$pb.TagNumber(9)
  VLMResult get result => $_getN(8);
  @$pb.TagNumber(9)
  set result(VLMResult v) { setField(9, v); }
  @$pb.TagNumber(9)
  $core.bool hasResult() => $_has(8);
  @$pb.TagNumber(9)
  void clearResult() => clearField(9);
  @$pb.TagNumber(9)
  VLMResult ensureResult() => $_ensure(8);

  @$pb.TagNumber(10)
  $core.String get errorMessage => $_getSZ(9);
  @$pb.TagNumber(10)
  set errorMessage($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasErrorMessage() => $_has(9);
  @$pb.TagNumber(10)
  void clearErrorMessage() => clearField(10);

  @$pb.TagNumber(11)
  $core.int get errorCode => $_getIZ(10);
  @$pb.TagNumber(11)
  set errorCode($core.int v) { $_setSignedInt32(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasErrorCode() => $_has(10);
  @$pb.TagNumber(11)
  void clearErrorCode() => clearField(11);
}

class VLMServiceState extends $pb.GeneratedMessage {
  factory VLMServiceState({
    $core.bool? isReady,
    $core.String? currentModel,
    $core.int? contextLength,
    $core.bool? supportsStreaming,
    $core.bool? supportsMultipleImages,
    $core.String? visionEncoderType,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final $result = create();
    if (isReady != null) {
      $result.isReady = isReady;
    }
    if (currentModel != null) {
      $result.currentModel = currentModel;
    }
    if (contextLength != null) {
      $result.contextLength = contextLength;
    }
    if (supportsStreaming != null) {
      $result.supportsStreaming = supportsStreaming;
    }
    if (supportsMultipleImages != null) {
      $result.supportsMultipleImages = supportsMultipleImages;
    }
    if (visionEncoderType != null) {
      $result.visionEncoderType = visionEncoderType;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    return $result;
  }
  VLMServiceState._() : super();
  factory VLMServiceState.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VLMServiceState.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VLMServiceState', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isReady')
    ..aOS(2, _omitFieldNames ? '' : 'currentModel')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'contextLength', $pb.PbFieldType.O3)
    ..aOB(4, _omitFieldNames ? '' : 'supportsStreaming')
    ..aOB(5, _omitFieldNames ? '' : 'supportsMultipleImages')
    ..aOS(6, _omitFieldNames ? '' : 'visionEncoderType')
    ..aOS(7, _omitFieldNames ? '' : 'errorMessage')
    ..a<$core.int>(8, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VLMServiceState clone() => VLMServiceState()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VLMServiceState copyWith(void Function(VLMServiceState) updates) => super.copyWith((message) => updates(message as VLMServiceState)) as VLMServiceState;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VLMServiceState create() => VLMServiceState._();
  VLMServiceState createEmptyInstance() => create();
  static $pb.PbList<VLMServiceState> createRepeated() => $pb.PbList<VLMServiceState>();
  @$core.pragma('dart2js:noInline')
  static VLMServiceState getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VLMServiceState>(create);
  static VLMServiceState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get isReady => $_getBF(0);
  @$pb.TagNumber(1)
  set isReady($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasIsReady() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsReady() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get currentModel => $_getSZ(1);
  @$pb.TagNumber(2)
  set currentModel($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCurrentModel() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrentModel() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get contextLength => $_getIZ(2);
  @$pb.TagNumber(3)
  set contextLength($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasContextLength() => $_has(2);
  @$pb.TagNumber(3)
  void clearContextLength() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get supportsStreaming => $_getBF(3);
  @$pb.TagNumber(4)
  set supportsStreaming($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSupportsStreaming() => $_has(3);
  @$pb.TagNumber(4)
  void clearSupportsStreaming() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get supportsMultipleImages => $_getBF(4);
  @$pb.TagNumber(5)
  set supportsMultipleImages($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSupportsMultipleImages() => $_has(4);
  @$pb.TagNumber(5)
  void clearSupportsMultipleImages() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get visionEncoderType => $_getSZ(5);
  @$pb.TagNumber(6)
  set visionEncoderType($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasVisionEncoderType() => $_has(5);
  @$pb.TagNumber(6)
  void clearVisionEncoderType() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get errorMessage => $_getSZ(6);
  @$pb.TagNumber(7)
  set errorMessage($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasErrorMessage() => $_has(6);
  @$pb.TagNumber(7)
  void clearErrorMessage() => clearField(7);

  @$pb.TagNumber(8)
  $core.int get errorCode => $_getIZ(7);
  @$pb.TagNumber(8)
  set errorCode($core.int v) { $_setSignedInt32(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasErrorCode() => $_has(7);
  @$pb.TagNumber(8)
  void clearErrorCode() => clearField(8);
}

class VLMApi {
  $pb.RpcClient _client;
  VLMApi(this._client);

  $async.Future<VLMResult> generate($pb.ClientContext? ctx, VLMGenerationRequest request) =>
    _client.invoke<VLMResult>(ctx, 'VLM', 'Generate', request, VLMResult())
  ;
  $async.Future<VLMStreamEvent> stream($pb.ClientContext? ctx, VLMGenerationRequest request) =>
    _client.invoke<VLMStreamEvent>(ctx, 'VLM', 'Stream', request, VLMStreamEvent())
  ;
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
