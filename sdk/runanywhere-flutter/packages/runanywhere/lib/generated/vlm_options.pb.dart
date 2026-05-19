// This is a generated file - do not edit.
//
// Generated from vlm_options.proto.

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

import 'model_types.pbenum.dart' as $0;
import 'vlm_options.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

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
    final result = create();
    if (templateText != null) result.templateText = templateText;
    if (imageMarker != null) result.imageMarker = imageMarker;
    if (defaultSystemPrompt != null)
      result.defaultSystemPrompt = defaultSystemPrompt;
    return result;
  }

  VLMChatTemplate._();

  factory VLMChatTemplate.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VLMChatTemplate.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VLMChatTemplate',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'templateText')
    ..aOS(2, _omitFieldNames ? '' : 'imageMarker')
    ..aOS(3, _omitFieldNames ? '' : 'defaultSystemPrompt')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VLMChatTemplate clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VLMChatTemplate copyWith(void Function(VLMChatTemplate) updates) =>
      super.copyWith((message) => updates(message as VLMChatTemplate))
          as VLMChatTemplate;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VLMChatTemplate create() => VLMChatTemplate._();
  @$core.override
  VLMChatTemplate createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VLMChatTemplate getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VLMChatTemplate>(create);
  static VLMChatTemplate? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get templateText => $_getSZ(0);
  @$pb.TagNumber(1)
  set templateText($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTemplateText() => $_has(0);
  @$pb.TagNumber(1)
  void clearTemplateText() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get imageMarker => $_getSZ(1);
  @$pb.TagNumber(2)
  set imageMarker($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasImageMarker() => $_has(1);
  @$pb.TagNumber(2)
  void clearImageMarker() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get defaultSystemPrompt => $_getSZ(2);
  @$pb.TagNumber(3)
  set defaultSystemPrompt($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDefaultSystemPrompt() => $_has(2);
  @$pb.TagNumber(3)
  void clearDefaultSystemPrompt() => $_clearField(3);
}

enum VLMImage_Source { filePath, encoded, rawRgb, base64, notSet }

/// ---------------------------------------------------------------------------
/// VLM image input.
///
/// `source` is a oneof so that exactly one of {file_path, encoded, raw_rgb,
/// base64} can be supplied per request. `width` / `height` are required for
/// non-encoded formats (raw_rgb, raw_rgba) where the consumer cannot infer
/// dimensions from a container header. `format` disambiguates encoded `bytes`
/// payloads (JPEG / PNG / WEBP) and explicitly tags raw / file-path / base64
/// sources.
/// ---------------------------------------------------------------------------
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
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
  }) {
    final result = create();
    if (filePath != null) result.filePath = filePath;
    if (encoded != null) result.encoded = encoded;
    if (rawRgb != null) result.rawRgb = rawRgb;
    if (base64 != null) result.base64 = base64;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (format != null) result.format = format;
    if (mediaType != null) result.mediaType = mediaType;
    if (name != null) result.name = name;
    if (sizeBytes != null) result.sizeBytes = sizeBytes;
    if (metadata != null) result.metadata.addEntries(metadata);
    return result;
  }

  VLMImage._();

  factory VLMImage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VLMImage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, VLMImage_Source> _VLMImage_SourceByTag = {
    1: VLMImage_Source.filePath,
    2: VLMImage_Source.encoded,
    3: VLMImage_Source.rawRgb,
    4: VLMImage_Source.base64,
    0: VLMImage_Source.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VLMImage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..oo(0, [1, 2, 3, 4])
    ..aOS(1, _omitFieldNames ? '' : 'filePath')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'encoded', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'rawRgb', $pb.PbFieldType.OY)
    ..aOS(4, _omitFieldNames ? '' : 'base64')
    ..aI(5, _omitFieldNames ? '' : 'width')
    ..aI(6, _omitFieldNames ? '' : 'height')
    ..aE<VLMImageFormat>(7, _omitFieldNames ? '' : 'format',
        enumValues: VLMImageFormat.values)
    ..aOS(8, _omitFieldNames ? '' : 'mediaType')
    ..aOS(9, _omitFieldNames ? '' : 'name')
    ..aInt64(10, _omitFieldNames ? '' : 'sizeBytes')
    ..m<$core.String, $core.String>(11, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'VLMImage.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VLMImage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VLMImage copyWith(void Function(VLMImage) updates) =>
      super.copyWith((message) => updates(message as VLMImage)) as VLMImage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VLMImage create() => VLMImage._();
  @$core.override
  VLMImage createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VLMImage getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VLMImage>(create);
  static VLMImage? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  VLMImage_Source whichSource() => _VLMImage_SourceByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  void clearSource() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get filePath => $_getSZ(0);
  @$pb.TagNumber(1)
  set filePath($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFilePath() => $_has(0);
  @$pb.TagNumber(1)
  void clearFilePath() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get encoded => $_getN(1);
  @$pb.TagNumber(2)
  set encoded($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEncoded() => $_has(1);
  @$pb.TagNumber(2)
  void clearEncoded() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get rawRgb => $_getN(2);
  @$pb.TagNumber(3)
  set rawRgb($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRawRgb() => $_has(2);
  @$pb.TagNumber(3)
  void clearRawRgb() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get base64 => $_getSZ(3);
  @$pb.TagNumber(4)
  set base64($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBase64() => $_has(3);
  @$pb.TagNumber(4)
  void clearBase64() => $_clearField(4);

  /// Required for VLM_IMAGE_FORMAT_RAW_RGB and VLM_IMAGE_FORMAT_RAW_RGBA
  /// (consumers cannot infer dimensions for raw pixel buffers). Optional
  /// for encoded / file_path / base64 sources where the decoder reads
  /// dimensions from the container.
  @$pb.TagNumber(5)
  $core.int get width => $_getIZ(4);
  @$pb.TagNumber(5)
  set width($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasWidth() => $_has(4);
  @$pb.TagNumber(5)
  void clearWidth() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get height => $_getIZ(5);
  @$pb.TagNumber(6)
  set height($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasHeight() => $_has(5);
  @$pb.TagNumber(6)
  void clearHeight() => $_clearField(6);

  @$pb.TagNumber(7)
  VLMImageFormat get format => $_getN(6);
  @$pb.TagNumber(7)
  set format(VLMImageFormat value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasFormat() => $_has(6);
  @$pb.TagNumber(7)
  void clearFormat() => $_clearField(7);

  /// Optional source metadata. Adapters may populate this after camera/file
  /// picker capture without exposing native APIs to core.
  @$pb.TagNumber(8)
  $core.String get mediaType => $_getSZ(7);
  @$pb.TagNumber(8)
  set mediaType($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasMediaType() => $_has(7);
  @$pb.TagNumber(8)
  void clearMediaType() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get name => $_getSZ(8);
  @$pb.TagNumber(9)
  set name($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasName() => $_has(8);
  @$pb.TagNumber(9)
  void clearName() => $_clearField(9);

  @$pb.TagNumber(10)
  $fixnum.Int64 get sizeBytes => $_getI64(9);
  @$pb.TagNumber(10)
  set sizeBytes($fixnum.Int64 value) => $_setInt64(9, value);
  @$pb.TagNumber(10)
  $core.bool hasSizeBytes() => $_has(9);
  @$pb.TagNumber(10)
  void clearSizeBytes() => $_clearField(10);

  @$pb.TagNumber(11)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(10);
}

/// ---------------------------------------------------------------------------
/// VLM component configuration.
/// Sources pre-IDL:
///   Kotlin VLMTypes.kt:163        (modelId, contextLength, temperature,
///                                  maxTokens, systemPrompt, streamingEnabled,
///                                  preferredFramework)
///   C ABI  rac_vlm_types.h:224    (model_id, preferred_framework,
///                                  context_length, temperature, max_tokens,
///                                  system_prompt, streaming_enabled)
///
/// Per the canonicalization brief, only the load-bearing identification +
/// limits cross the IDL boundary here: model_id, max_image_size_px, max_tokens.
/// Per-request sampling parameters live on VLMGenerationOptions; runtime
/// streaming toggles and chat-template selection stay backend-private.
/// ---------------------------------------------------------------------------
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
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (maxImageSizePx != null) result.maxImageSizePx = maxImageSizePx;
    if (maxTokens != null) result.maxTokens = maxTokens;
    if (contextLength != null) result.contextLength = contextLength;
    if (temperature != null) result.temperature = temperature;
    if (systemPrompt != null) result.systemPrompt = systemPrompt;
    if (streamingEnabled != null) result.streamingEnabled = streamingEnabled;
    if (preferredFramework != null)
      result.preferredFramework = preferredFramework;
    return result;
  }

  VLMConfiguration._();

  factory VLMConfiguration.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VLMConfiguration.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VLMConfiguration',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aI(2, _omitFieldNames ? '' : 'maxImageSizePx')
    ..aI(3, _omitFieldNames ? '' : 'maxTokens')
    ..aI(4, _omitFieldNames ? '' : 'contextLength')
    ..aD(5, _omitFieldNames ? '' : 'temperature', fieldType: $pb.PbFieldType.OF)
    ..aOS(6, _omitFieldNames ? '' : 'systemPrompt')
    ..aOB(7, _omitFieldNames ? '' : 'streamingEnabled')
    ..aE<$0.InferenceFramework>(8, _omitFieldNames ? '' : 'preferredFramework',
        enumValues: $0.InferenceFramework.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VLMConfiguration clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VLMConfiguration copyWith(void Function(VLMConfiguration) updates) =>
      super.copyWith((message) => updates(message as VLMConfiguration))
          as VLMConfiguration;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VLMConfiguration create() => VLMConfiguration._();
  @$core.override
  VLMConfiguration createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VLMConfiguration getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VLMConfiguration>(create);
  static VLMConfiguration? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get maxImageSizePx => $_getIZ(1);
  @$pb.TagNumber(2)
  set maxImageSizePx($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMaxImageSizePx() => $_has(1);
  @$pb.TagNumber(2)
  void clearMaxImageSizePx() => $_clearField(2);

  /// (0 = backend default)
  @$pb.TagNumber(3)
  $core.int get maxTokens => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxTokens($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMaxTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxTokens() => $_clearField(3);

  /// Additional component-level fields from rac_vlm_config_t.
  @$pb.TagNumber(4)
  $core.int get contextLength => $_getIZ(3);
  @$pb.TagNumber(4)
  set contextLength($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasContextLength() => $_has(3);
  @$pb.TagNumber(4)
  void clearContextLength() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get temperature => $_getN(4);
  @$pb.TagNumber(5)
  set temperature($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTemperature() => $_has(4);
  @$pb.TagNumber(5)
  void clearTemperature() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get systemPrompt => $_getSZ(5);
  @$pb.TagNumber(6)
  set systemPrompt($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSystemPrompt() => $_has(5);
  @$pb.TagNumber(6)
  void clearSystemPrompt() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get streamingEnabled => $_getBF(6);
  @$pb.TagNumber(7)
  set streamingEnabled($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasStreamingEnabled() => $_has(6);
  @$pb.TagNumber(7)
  void clearStreamingEnabled() => $_clearField(7);

  @$pb.TagNumber(8)
  $0.InferenceFramework get preferredFramework => $_getN(7);
  @$pb.TagNumber(8)
  set preferredFramework($0.InferenceFramework value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasPreferredFramework() => $_has(7);
  @$pb.TagNumber(8)
  void clearPreferredFramework() => $_clearField(8);
}

/// ---------------------------------------------------------------------------
/// VLM generation options — per-request sampling + prompt parameters.
/// Sources pre-IDL:
///   Kotlin VLMTypes.kt:103        (maxTokens, temperature, topP, systemPrompt,
///                                  maxImageSize, nThreads, useGpu)
///   Dart   vlm_types.dart:127     (maxTokens, temperature, topP, systemPrompt,
///                                  maxImageSize, nThreads, useGpu)
///   RN     VLMTypes.ts:21         (maxTokens, temperature, topP)
///   Web    VLMTypes.ts:28         (maxTokens, temperature, topP, systemPrompt,
///                                  modelFamily, streaming)
///   C ABI  rac_vlm_types.h:143    (max_tokens, temperature, top_p,
///                                  stop_sequences, num_stop_sequences,
///                                  streaming_enabled, system_prompt,
///                                  max_image_size, n_threads, use_gpu,
///                                  model_family, custom_chat_template,
///                                  image_marker_override)
///
/// top_k is included to align with the other text generation services
/// (LLM / chat) even though no current VLM SDK exposes it; the C ABI's
/// llama.cpp backend already supports top_k internally.
/// ---------------------------------------------------------------------------
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
    final result = create();
    if (prompt != null) result.prompt = prompt;
    if (maxTokens != null) result.maxTokens = maxTokens;
    if (temperature != null) result.temperature = temperature;
    if (topP != null) result.topP = topP;
    if (topK != null) result.topK = topK;
    if (stopSequences != null) result.stopSequences.addAll(stopSequences);
    if (streamingEnabled != null) result.streamingEnabled = streamingEnabled;
    if (systemPrompt != null) result.systemPrompt = systemPrompt;
    if (maxImageSize != null) result.maxImageSize = maxImageSize;
    if (nThreads != null) result.nThreads = nThreads;
    if (useGpu != null) result.useGpu = useGpu;
    if (modelFamily != null) result.modelFamily = modelFamily;
    if (customChatTemplate != null)
      result.customChatTemplate = customChatTemplate;
    if (imageMarkerOverride != null)
      result.imageMarkerOverride = imageMarkerOverride;
    if (seed != null) result.seed = seed;
    if (repetitionPenalty != null) result.repetitionPenalty = repetitionPenalty;
    if (minP != null) result.minP = minP;
    if (emitImageEmbeddings != null)
      result.emitImageEmbeddings = emitImageEmbeddings;
    return result;
  }

  VLMGenerationOptions._();

  factory VLMGenerationOptions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VLMGenerationOptions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VLMGenerationOptions',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'prompt')
    ..aI(2, _omitFieldNames ? '' : 'maxTokens')
    ..aD(3, _omitFieldNames ? '' : 'temperature', fieldType: $pb.PbFieldType.OF)
    ..aD(4, _omitFieldNames ? '' : 'topP', fieldType: $pb.PbFieldType.OF)
    ..aI(5, _omitFieldNames ? '' : 'topK')
    ..pPS(6, _omitFieldNames ? '' : 'stopSequences')
    ..aOB(7, _omitFieldNames ? '' : 'streamingEnabled')
    ..aOS(8, _omitFieldNames ? '' : 'systemPrompt')
    ..aI(9, _omitFieldNames ? '' : 'maxImageSize')
    ..aI(10, _omitFieldNames ? '' : 'nThreads')
    ..aOB(11, _omitFieldNames ? '' : 'useGpu')
    ..aE<VLMModelFamily>(12, _omitFieldNames ? '' : 'modelFamily',
        enumValues: VLMModelFamily.values)
    ..aOM<VLMChatTemplate>(13, _omitFieldNames ? '' : 'customChatTemplate',
        subBuilder: VLMChatTemplate.create)
    ..aOS(14, _omitFieldNames ? '' : 'imageMarkerOverride')
    ..aInt64(15, _omitFieldNames ? '' : 'seed')
    ..aD(16, _omitFieldNames ? '' : 'repetitionPenalty',
        fieldType: $pb.PbFieldType.OF)
    ..aD(17, _omitFieldNames ? '' : 'minP', fieldType: $pb.PbFieldType.OF)
    ..aOB(18, _omitFieldNames ? '' : 'emitImageEmbeddings')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VLMGenerationOptions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VLMGenerationOptions copyWith(void Function(VLMGenerationOptions) updates) =>
      super.copyWith((message) => updates(message as VLMGenerationOptions))
          as VLMGenerationOptions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VLMGenerationOptions create() => VLMGenerationOptions._();
  @$core.override
  VLMGenerationOptions createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VLMGenerationOptions getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VLMGenerationOptions>(create);
  static VLMGenerationOptions? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get prompt => $_getSZ(0);
  @$pb.TagNumber(1)
  set prompt($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPrompt() => $_has(0);
  @$pb.TagNumber(1)
  void clearPrompt() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get maxTokens => $_getIZ(1);
  @$pb.TagNumber(2)
  set maxTokens($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMaxTokens() => $_has(1);
  @$pb.TagNumber(2)
  void clearMaxTokens() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get temperature => $_getN(2);
  @$pb.TagNumber(3)
  set temperature($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTemperature() => $_has(2);
  @$pb.TagNumber(3)
  void clearTemperature() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get topP => $_getN(3);
  @$pb.TagNumber(4)
  set topP($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTopP() => $_has(3);
  @$pb.TagNumber(4)
  void clearTopP() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get topK => $_getIZ(4);
  @$pb.TagNumber(5)
  set topK($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTopK() => $_has(4);
  @$pb.TagNumber(5)
  void clearTopK() => $_clearField(5);

  /// Full rac_vlm_options_t coverage.
  @$pb.TagNumber(6)
  $pb.PbList<$core.String> get stopSequences => $_getList(5);

  @$pb.TagNumber(7)
  $core.bool get streamingEnabled => $_getBF(6);
  @$pb.TagNumber(7)
  set streamingEnabled($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasStreamingEnabled() => $_has(6);
  @$pb.TagNumber(7)
  void clearStreamingEnabled() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get systemPrompt => $_getSZ(7);
  @$pb.TagNumber(8)
  set systemPrompt($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasSystemPrompt() => $_has(7);
  @$pb.TagNumber(8)
  void clearSystemPrompt() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get maxImageSize => $_getIZ(8);
  @$pb.TagNumber(9)
  set maxImageSize($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasMaxImageSize() => $_has(8);
  @$pb.TagNumber(9)
  void clearMaxImageSize() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get nThreads => $_getIZ(9);
  @$pb.TagNumber(10)
  set nThreads($core.int value) => $_setSignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasNThreads() => $_has(9);
  @$pb.TagNumber(10)
  void clearNThreads() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.bool get useGpu => $_getBF(10);
  @$pb.TagNumber(11)
  set useGpu($core.bool value) => $_setBool(10, value);
  @$pb.TagNumber(11)
  $core.bool hasUseGpu() => $_has(10);
  @$pb.TagNumber(11)
  void clearUseGpu() => $_clearField(11);

  @$pb.TagNumber(12)
  VLMModelFamily get modelFamily => $_getN(11);
  @$pb.TagNumber(12)
  set modelFamily(VLMModelFamily value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasModelFamily() => $_has(11);
  @$pb.TagNumber(12)
  void clearModelFamily() => $_clearField(12);

  @$pb.TagNumber(13)
  VLMChatTemplate get customChatTemplate => $_getN(12);
  @$pb.TagNumber(13)
  set customChatTemplate(VLMChatTemplate value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasCustomChatTemplate() => $_has(12);
  @$pb.TagNumber(13)
  void clearCustomChatTemplate() => $_clearField(13);
  @$pb.TagNumber(13)
  VLMChatTemplate ensureCustomChatTemplate() => $_ensure(12);

  @$pb.TagNumber(14)
  $core.String get imageMarkerOverride => $_getSZ(13);
  @$pb.TagNumber(14)
  set imageMarkerOverride($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasImageMarkerOverride() => $_has(13);
  @$pb.TagNumber(14)
  void clearImageMarkerOverride() => $_clearField(14);

  /// Additional llama.cpp sampling knobs and result controls.
  @$pb.TagNumber(15)
  $fixnum.Int64 get seed => $_getI64(14);
  @$pb.TagNumber(15)
  set seed($fixnum.Int64 value) => $_setInt64(14, value);
  @$pb.TagNumber(15)
  $core.bool hasSeed() => $_has(14);
  @$pb.TagNumber(15)
  void clearSeed() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.double get repetitionPenalty => $_getN(15);
  @$pb.TagNumber(16)
  set repetitionPenalty($core.double value) => $_setFloat(15, value);
  @$pb.TagNumber(16)
  $core.bool hasRepetitionPenalty() => $_has(15);
  @$pb.TagNumber(16)
  void clearRepetitionPenalty() => $_clearField(16);

  @$pb.TagNumber(17)
  $core.double get minP => $_getN(16);
  @$pb.TagNumber(17)
  set minP($core.double value) => $_setFloat(16, value);
  @$pb.TagNumber(17)
  $core.bool hasMinP() => $_has(16);
  @$pb.TagNumber(17)
  void clearMinP() => $_clearField(17);

  @$pb.TagNumber(18)
  $core.bool get emitImageEmbeddings => $_getBF(17);
  @$pb.TagNumber(18)
  set emitImageEmbeddings($core.bool value) => $_setBool(17, value);
  @$pb.TagNumber(18)
  $core.bool hasEmitImageEmbeddings() => $_has(17);
  @$pb.TagNumber(18)
  void clearEmitImageEmbeddings() => $_clearField(18);
}

class VLMGenerationRequest extends $pb.GeneratedMessage {
  factory VLMGenerationRequest({
    $core.String? requestId,
    $core.Iterable<VLMImage>? images,
    VLMGenerationOptions? options,
    $core.String? modelId,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (images != null) result.images.addAll(images);
    if (options != null) result.options = options;
    if (modelId != null) result.modelId = modelId;
    if (metadata != null) result.metadata.addEntries(metadata);
    return result;
  }

  VLMGenerationRequest._();

  factory VLMGenerationRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VLMGenerationRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VLMGenerationRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..pPM<VLMImage>(2, _omitFieldNames ? '' : 'images',
        subBuilder: VLMImage.create)
    ..aOM<VLMGenerationOptions>(3, _omitFieldNames ? '' : 'options',
        subBuilder: VLMGenerationOptions.create)
    ..aOS(4, _omitFieldNames ? '' : 'modelId')
    ..m<$core.String, $core.String>(5, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'VLMGenerationRequest.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VLMGenerationRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VLMGenerationRequest copyWith(void Function(VLMGenerationRequest) updates) =>
      super.copyWith((message) => updates(message as VLMGenerationRequest))
          as VLMGenerationRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VLMGenerationRequest create() => VLMGenerationRequest._();
  @$core.override
  VLMGenerationRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VLMGenerationRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VLMGenerationRequest>(create);
  static VLMGenerationRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<VLMImage> get images => $_getList(1);

  @$pb.TagNumber(3)
  VLMGenerationOptions get options => $_getN(2);
  @$pb.TagNumber(3)
  set options(VLMGenerationOptions value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasOptions() => $_has(2);
  @$pb.TagNumber(3)
  void clearOptions() => $_clearField(3);
  @$pb.TagNumber(3)
  VLMGenerationOptions ensureOptions() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.String get modelId => $_getSZ(3);
  @$pb.TagNumber(4)
  set modelId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasModelId() => $_has(3);
  @$pb.TagNumber(4)
  void clearModelId() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(4);
}

/// ---------------------------------------------------------------------------
/// VLM generation result.
/// Sources pre-IDL:
///   Swift  VLMTypes.swift:208     (text, promptTokens, completionTokens,
///                                  totalTimeMs as Double, tokensPerSecond)
///   Kotlin VLMTypes.kt:120        (text, promptTokens, imageTokens,
///                                  completionTokens, totalTokens,
///                                  timeToFirstTokenMs, imageEncodeTimeMs,
///                                  totalTimeMs, tokensPerSecond)
///   Dart   vlm_types.dart:68      (text, promptTokens, completionTokens,
///                                  totalTimeMs, tokensPerSecond)
///   RN     VLMTypes.ts:28         (text, promptTokens, completionTokens,
///                                  totalTimeMs, tokensPerSecond)
///   Web    VLMTypes.ts:38         (VLMGenerationResult: text, promptTokens,
///                                  imageTokens, completionTokens, totalTokens,
///                                  timeToFirstTokenMs, imageEncodeTimeMs,
///                                  totalTimeMs, tokensPerSecond, hardwareUsed)
///   C ABI  rac_vlm_types.h:268    (text, prompt_tokens, image_tokens,
///                                  completion_tokens, total_tokens,
///                                  time_to_first_token_ms,
///                                  image_encode_time_ms, total_time_ms,
///                                  tokens_per_second)
///
/// Streaming note: the VLM service emits VLMStreamEvent messages for
/// per-token deltas and terminal results; this aggregate result is carried on
/// the unary Generate RPC and on terminal stream events.
/// ---------------------------------------------------------------------------
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
    final result = create();
    if (text != null) result.text = text;
    if (promptTokens != null) result.promptTokens = promptTokens;
    if (completionTokens != null) result.completionTokens = completionTokens;
    if (totalTokens != null) result.totalTokens = totalTokens;
    if (processingTimeMs != null) result.processingTimeMs = processingTimeMs;
    if (tokensPerSecond != null) result.tokensPerSecond = tokensPerSecond;
    if (imageTokens != null) result.imageTokens = imageTokens;
    if (timeToFirstTokenMs != null)
      result.timeToFirstTokenMs = timeToFirstTokenMs;
    if (imageEncodeTimeMs != null) result.imageEncodeTimeMs = imageEncodeTimeMs;
    if (hardwareUsed != null) result.hardwareUsed = hardwareUsed;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    if (finishReason != null) result.finishReason = finishReason;
    if (imagesProcessed != null) result.imagesProcessed = imagesProcessed;
    return result;
  }

  VLMResult._();

  factory VLMResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VLMResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VLMResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aI(2, _omitFieldNames ? '' : 'promptTokens')
    ..aI(3, _omitFieldNames ? '' : 'completionTokens')
    ..aInt64(4, _omitFieldNames ? '' : 'totalTokens')
    ..aInt64(5, _omitFieldNames ? '' : 'processingTimeMs')
    ..aD(6, _omitFieldNames ? '' : 'tokensPerSecond',
        fieldType: $pb.PbFieldType.OF)
    ..aI(7, _omitFieldNames ? '' : 'imageTokens')
    ..aInt64(8, _omitFieldNames ? '' : 'timeToFirstTokenMs')
    ..aInt64(9, _omitFieldNames ? '' : 'imageEncodeTimeMs')
    ..aOS(10, _omitFieldNames ? '' : 'hardwareUsed')
    ..aOS(11, _omitFieldNames ? '' : 'errorMessage')
    ..aI(12, _omitFieldNames ? '' : 'errorCode')
    ..aOS(13, _omitFieldNames ? '' : 'finishReason')
    ..aI(14, _omitFieldNames ? '' : 'imagesProcessed')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VLMResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VLMResult copyWith(void Function(VLMResult) updates) =>
      super.copyWith((message) => updates(message as VLMResult)) as VLMResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VLMResult create() => VLMResult._();
  @$core.override
  VLMResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VLMResult getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VLMResult>(create);
  static VLMResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get promptTokens => $_getIZ(1);
  @$pb.TagNumber(2)
  set promptTokens($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPromptTokens() => $_has(1);
  @$pb.TagNumber(2)
  void clearPromptTokens() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get completionTokens => $_getIZ(2);
  @$pb.TagNumber(3)
  set completionTokens($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCompletionTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearCompletionTokens() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get totalTokens => $_getI64(3);
  @$pb.TagNumber(4)
  set totalTokens($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTotalTokens() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalTokens() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get processingTimeMs => $_getI64(4);
  @$pb.TagNumber(5)
  set processingTimeMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasProcessingTimeMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearProcessingTimeMs() => $_clearField(5);

  /// Swift VLMResult totalTimeMs (Double ms).
  @$pb.TagNumber(6)
  $core.double get tokensPerSecond => $_getN(5);
  @$pb.TagNumber(6)
  set tokensPerSecond($core.double value) => $_setFloat(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTokensPerSecond() => $_has(5);
  @$pb.TagNumber(6)
  void clearTokensPerSecond() => $_clearField(6);

  /// Detailed VLM metrics from Kotlin/Web/C ABI.
  @$pb.TagNumber(7)
  $core.int get imageTokens => $_getIZ(6);
  @$pb.TagNumber(7)
  set imageTokens($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasImageTokens() => $_has(6);
  @$pb.TagNumber(7)
  void clearImageTokens() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get timeToFirstTokenMs => $_getI64(7);
  @$pb.TagNumber(8)
  set timeToFirstTokenMs($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasTimeToFirstTokenMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearTimeToFirstTokenMs() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get imageEncodeTimeMs => $_getI64(8);
  @$pb.TagNumber(9)
  set imageEncodeTimeMs($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasImageEncodeTimeMs() => $_has(8);
  @$pb.TagNumber(9)
  void clearImageEncodeTimeMs() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get hardwareUsed => $_getSZ(9);
  @$pb.TagNumber(10)
  set hardwareUsed($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasHardwareUsed() => $_has(9);
  @$pb.TagNumber(10)
  void clearHardwareUsed() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get errorMessage => $_getSZ(10);
  @$pb.TagNumber(11)
  set errorMessage($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasErrorMessage() => $_has(10);
  @$pb.TagNumber(11)
  void clearErrorMessage() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.int get errorCode => $_getIZ(11);
  @$pb.TagNumber(12)
  set errorCode($core.int value) => $_setSignedInt32(11, value);
  @$pb.TagNumber(12)
  $core.bool hasErrorCode() => $_has(11);
  @$pb.TagNumber(12)
  void clearErrorCode() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get finishReason => $_getSZ(12);
  @$pb.TagNumber(13)
  set finishReason($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasFinishReason() => $_has(12);
  @$pb.TagNumber(13)
  void clearFinishReason() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.int get imagesProcessed => $_getIZ(13);
  @$pb.TagNumber(14)
  set imagesProcessed($core.int value) => $_setSignedInt32(13, value);
  @$pb.TagNumber(14)
  $core.bool hasImagesProcessed() => $_has(13);
  @$pb.TagNumber(14)
  void clearImagesProcessed() => $_clearField(14);
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
    final result$ = create();
    if (seq != null) result$.seq = seq;
    if (timestampUs != null) result$.timestampUs = timestampUs;
    if (requestId != null) result$.requestId = requestId;
    if (kind != null) result$.kind = kind;
    if (token != null) result$.token = token;
    if (tokenIndex != null) result$.tokenIndex = tokenIndex;
    if (isFinal != null) result$.isFinal = isFinal;
    if (tokensPerSecond != null) result$.tokensPerSecond = tokensPerSecond;
    if (result != null) result$.result = result;
    if (errorMessage != null) result$.errorMessage = errorMessage;
    if (errorCode != null) result$.errorCode = errorCode;
    return result$;
  }

  VLMStreamEvent._();

  factory VLMStreamEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VLMStreamEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VLMStreamEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(3, _omitFieldNames ? '' : 'requestId')
    ..aE<VLMStreamEventKind>(4, _omitFieldNames ? '' : 'kind',
        enumValues: VLMStreamEventKind.values)
    ..aOS(5, _omitFieldNames ? '' : 'token')
    ..aI(6, _omitFieldNames ? '' : 'tokenIndex')
    ..aOB(7, _omitFieldNames ? '' : 'isFinal')
    ..aD(8, _omitFieldNames ? '' : 'tokensPerSecond',
        fieldType: $pb.PbFieldType.OF)
    ..aOM<VLMResult>(9, _omitFieldNames ? '' : 'result',
        subBuilder: VLMResult.create)
    ..aOS(10, _omitFieldNames ? '' : 'errorMessage')
    ..aI(11, _omitFieldNames ? '' : 'errorCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VLMStreamEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VLMStreamEvent copyWith(void Function(VLMStreamEvent) updates) =>
      super.copyWith((message) => updates(message as VLMStreamEvent))
          as VLMStreamEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VLMStreamEvent create() => VLMStreamEvent._();
  @$core.override
  VLMStreamEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VLMStreamEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VLMStreamEvent>(create);
  static VLMStreamEvent? _defaultInstance;

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
  VLMStreamEventKind get kind => $_getN(3);
  @$pb.TagNumber(4)
  set kind(VLMStreamEventKind value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasKind() => $_has(3);
  @$pb.TagNumber(4)
  void clearKind() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get token => $_getSZ(4);
  @$pb.TagNumber(5)
  set token($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasToken() => $_has(4);
  @$pb.TagNumber(5)
  void clearToken() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get tokenIndex => $_getIZ(5);
  @$pb.TagNumber(6)
  set tokenIndex($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTokenIndex() => $_has(5);
  @$pb.TagNumber(6)
  void clearTokenIndex() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get isFinal => $_getBF(6);
  @$pb.TagNumber(7)
  set isFinal($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasIsFinal() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsFinal() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.double get tokensPerSecond => $_getN(7);
  @$pb.TagNumber(8)
  set tokensPerSecond($core.double value) => $_setFloat(7, value);
  @$pb.TagNumber(8)
  $core.bool hasTokensPerSecond() => $_has(7);
  @$pb.TagNumber(8)
  void clearTokensPerSecond() => $_clearField(8);

  @$pb.TagNumber(9)
  VLMResult get result => $_getN(8);
  @$pb.TagNumber(9)
  set result(VLMResult value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasResult() => $_has(8);
  @$pb.TagNumber(9)
  void clearResult() => $_clearField(9);
  @$pb.TagNumber(9)
  VLMResult ensureResult() => $_ensure(8);

  @$pb.TagNumber(10)
  $core.String get errorMessage => $_getSZ(9);
  @$pb.TagNumber(10)
  set errorMessage($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasErrorMessage() => $_has(9);
  @$pb.TagNumber(10)
  void clearErrorMessage() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.int get errorCode => $_getIZ(10);
  @$pb.TagNumber(11)
  set errorCode($core.int value) => $_setSignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasErrorCode() => $_has(10);
  @$pb.TagNumber(11)
  void clearErrorCode() => $_clearField(11);
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
    final result = create();
    if (isReady != null) result.isReady = isReady;
    if (currentModel != null) result.currentModel = currentModel;
    if (contextLength != null) result.contextLength = contextLength;
    if (supportsStreaming != null) result.supportsStreaming = supportsStreaming;
    if (supportsMultipleImages != null)
      result.supportsMultipleImages = supportsMultipleImages;
    if (visionEncoderType != null) result.visionEncoderType = visionEncoderType;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    return result;
  }

  VLMServiceState._();

  factory VLMServiceState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VLMServiceState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VLMServiceState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isReady')
    ..aOS(2, _omitFieldNames ? '' : 'currentModel')
    ..aI(3, _omitFieldNames ? '' : 'contextLength')
    ..aOB(4, _omitFieldNames ? '' : 'supportsStreaming')
    ..aOB(5, _omitFieldNames ? '' : 'supportsMultipleImages')
    ..aOS(6, _omitFieldNames ? '' : 'visionEncoderType')
    ..aOS(7, _omitFieldNames ? '' : 'errorMessage')
    ..aI(8, _omitFieldNames ? '' : 'errorCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VLMServiceState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VLMServiceState copyWith(void Function(VLMServiceState) updates) =>
      super.copyWith((message) => updates(message as VLMServiceState))
          as VLMServiceState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VLMServiceState create() => VLMServiceState._();
  @$core.override
  VLMServiceState createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VLMServiceState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VLMServiceState>(create);
  static VLMServiceState? _defaultInstance;

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
  $core.int get contextLength => $_getIZ(2);
  @$pb.TagNumber(3)
  set contextLength($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasContextLength() => $_has(2);
  @$pb.TagNumber(3)
  void clearContextLength() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get supportsStreaming => $_getBF(3);
  @$pb.TagNumber(4)
  set supportsStreaming($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSupportsStreaming() => $_has(3);
  @$pb.TagNumber(4)
  void clearSupportsStreaming() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get supportsMultipleImages => $_getBF(4);
  @$pb.TagNumber(5)
  set supportsMultipleImages($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSupportsMultipleImages() => $_has(4);
  @$pb.TagNumber(5)
  void clearSupportsMultipleImages() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get visionEncoderType => $_getSZ(5);
  @$pb.TagNumber(6)
  set visionEncoderType($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasVisionEncoderType() => $_has(5);
  @$pb.TagNumber(6)
  void clearVisionEncoderType() => $_clearField(6);

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

/// ---------------------------------------------------------------------------
/// VLM load-resolved-artifacts request / response.
///
/// Replaces the legacy trio `rac_vlm_create` + `rac_vlm_initialize` +
/// `rac_vlm_destroy` (on error) with a single proto-backed call. Consumers
/// pass the already-resolved model paths (primary model + optional mmproj
/// vision projector) together with an optional model_id for telemetry. The
/// response carries the resulting native handle as an opaque uint64; callers
/// store the handle and use it for subsequent process/cancel/destroy calls.
/// ---------------------------------------------------------------------------
class VLMLoadResolvedArtifactsRequest extends $pb.GeneratedMessage {
  factory VLMLoadResolvedArtifactsRequest({
    $core.String? modelId,
    $core.String? primaryModelPath,
    $core.String? mmprojPath,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (primaryModelPath != null) result.primaryModelPath = primaryModelPath;
    if (mmprojPath != null) result.mmprojPath = mmprojPath;
    return result;
  }

  VLMLoadResolvedArtifactsRequest._();

  factory VLMLoadResolvedArtifactsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VLMLoadResolvedArtifactsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VLMLoadResolvedArtifactsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aOS(2, _omitFieldNames ? '' : 'primaryModelPath')
    ..aOS(3, _omitFieldNames ? '' : 'mmprojPath')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VLMLoadResolvedArtifactsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VLMLoadResolvedArtifactsRequest copyWith(
          void Function(VLMLoadResolvedArtifactsRequest) updates) =>
      super.copyWith(
              (message) => updates(message as VLMLoadResolvedArtifactsRequest))
          as VLMLoadResolvedArtifactsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VLMLoadResolvedArtifactsRequest create() =>
      VLMLoadResolvedArtifactsRequest._();
  @$core.override
  VLMLoadResolvedArtifactsRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VLMLoadResolvedArtifactsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VLMLoadResolvedArtifactsRequest>(
          create);
  static VLMLoadResolvedArtifactsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get primaryModelPath => $_getSZ(1);
  @$pb.TagNumber(2)
  set primaryModelPath($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPrimaryModelPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearPrimaryModelPath() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get mmprojPath => $_getSZ(2);
  @$pb.TagNumber(3)
  set mmprojPath($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMmprojPath() => $_has(2);
  @$pb.TagNumber(3)
  void clearMmprojPath() => $_clearField(3);
}

class VLMLoadResolvedArtifactsResponse extends $pb.GeneratedMessage {
  factory VLMLoadResolvedArtifactsResponse({
    $fixnum.Int64? handle,
    $core.int? resultCode,
    $core.String? errorMessage,
  }) {
    final result = create();
    if (handle != null) result.handle = handle;
    if (resultCode != null) result.resultCode = resultCode;
    if (errorMessage != null) result.errorMessage = errorMessage;
    return result;
  }

  VLMLoadResolvedArtifactsResponse._();

  factory VLMLoadResolvedArtifactsResponse.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VLMLoadResolvedArtifactsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VLMLoadResolvedArtifactsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'handle', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(2, _omitFieldNames ? '' : 'resultCode')
    ..aOS(3, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VLMLoadResolvedArtifactsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VLMLoadResolvedArtifactsResponse copyWith(
          void Function(VLMLoadResolvedArtifactsResponse) updates) =>
      super.copyWith(
              (message) => updates(message as VLMLoadResolvedArtifactsResponse))
          as VLMLoadResolvedArtifactsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VLMLoadResolvedArtifactsResponse create() =>
      VLMLoadResolvedArtifactsResponse._();
  @$core.override
  VLMLoadResolvedArtifactsResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VLMLoadResolvedArtifactsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VLMLoadResolvedArtifactsResponse>(
          create);
  static VLMLoadResolvedArtifactsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get handle => $_getI64(0);
  @$pb.TagNumber(1)
  set handle($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHandle() => $_has(0);
  @$pb.TagNumber(1)
  void clearHandle() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get resultCode => $_getIZ(1);
  @$pb.TagNumber(2)
  set resultCode($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasResultCode() => $_has(1);
  @$pb.TagNumber(2)
  void clearResultCode() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get errorMessage => $_getSZ(2);
  @$pb.TagNumber(3)
  set errorMessage($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasErrorMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearErrorMessage() => $_clearField(3);
}

/// Logical VLM service contract. Native camera capture, file picking, image
/// decoding performed by OS media APIs, and backend execution remain
/// adapter-owned; C++ consumes only serialized request/result/event messages.
class VLMApi {
  final $pb.RpcClient _client;

  VLMApi(this._client);

  /// One-shot multimodal generation returning aggregate text and metrics.
  $async.Future<VLMResult> generate(
          $pb.ClientContext? ctx, VLMGenerationRequest request) =>
      _client.invoke<VLMResult>(ctx, 'VLM', 'Generate', request, VLMResult());

  /// Server-streaming generation events: start, image preprocessing,
  /// per-token text deltas, terminal completion, and errors.
  $async.Future<VLMStreamEvent> stream(
          $pb.ClientContext? ctx, VLMGenerationRequest request) =>
      _client.invoke<VLMStreamEvent>(
          ctx, 'VLM', 'Stream', request, VLMStreamEvent());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
