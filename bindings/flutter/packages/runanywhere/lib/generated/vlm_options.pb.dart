// This is a generated file - do not edit.
//
// Generated from vlm_options.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'chat.pb.dart' as $0;
import 'errors.pb.dart' as $3;
import 'llm_options.pb.dart' as $1;
import 'token_usage.pb.dart' as $2;
import 'vlm_options.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'vlm_options.pbenum.dart';

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

enum VLMImage_Source { filePath, data, rawRgb, base64, rawRgba, notSet }

/// Pixel buffers are tightly packed with NO row padding: RGB is 3 bytes/px,
/// RGBA is 4, and width * height * channels MUST equal the buffer length or
/// the request is rejected. raw_rgba drops alpha at the boundary.
class VLMImage extends $pb.GeneratedMessage {
  factory VLMImage({
    $core.String? filePath,
    $core.List<$core.int>? data,
    $core.List<$core.int>? rawRgb,
    $core.String? base64,
    $core.int? width,
    $core.int? height,
    $core.String? mediaType,
    $core.List<$core.int>? rawRgba,
  }) {
    final result = create();
    if (filePath != null) result.filePath = filePath;
    if (data != null) result.data = data;
    if (rawRgb != null) result.rawRgb = rawRgb;
    if (base64 != null) result.base64 = base64;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (mediaType != null) result.mediaType = mediaType;
    if (rawRgba != null) result.rawRgba = rawRgba;
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
    2: VLMImage_Source.data,
    3: VLMImage_Source.rawRgb,
    4: VLMImage_Source.base64,
    12: VLMImage_Source.rawRgba,
    0: VLMImage_Source.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VLMImage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..oo(0, [1, 2, 3, 4, 12])
    ..aOS(1, _omitFieldNames ? '' : 'filePath')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'rawRgb', $pb.PbFieldType.OY)
    ..aOS(4, _omitFieldNames ? '' : 'base64')
    ..aI(5, _omitFieldNames ? '' : 'width')
    ..aI(6, _omitFieldNames ? '' : 'height')
    ..aOS(8, _omitFieldNames ? '' : 'mediaType')
    ..a<$core.List<$core.int>>(
        12, _omitFieldNames ? '' : 'rawRgba', $pb.PbFieldType.OY)
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
  @$pb.TagNumber(12)
  VLMImage_Source whichSource() => _VLMImage_SourceByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(12)
  void clearSource() => $_clearField($_whichOneof(0));

  /// Local file. The on-device analogue of a cloud Files-API file_id.
  @$pb.TagNumber(1)
  $core.String get filePath => $_getSZ(0);
  @$pb.TagNumber(1)
  set filePath($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFilePath() => $_has(0);
  @$pb.TagNumber(1)
  void clearFilePath() => $_clearField(1);

  /// Compressed container bytes -- image/jpeg, image/png, image/webp.
  /// Decoded by commons. Set media_type alongside. Same slot name and
  /// meaning as ChatAttachment.data and Anthropic source.data.
  @$pb.TagNumber(2)
  $core.List<$core.int> get data => $_getN(1);
  @$pb.TagNumber(2)
  set data($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasData() => $_has(1);
  @$pb.TagNumber(2)
  void clearData() => $_clearField(2);

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

  /// MIME type of `data`/`base64`. Required when either is set. An open
  /// string, as everywhere in the industry, so adding HEIC is not a proto
  /// change.
  @$pb.TagNumber(8)
  $core.String get mediaType => $_getSZ(6);
  @$pb.TagNumber(8)
  set mediaType($core.String value) => $_setString(6, value);
  @$pb.TagNumber(8)
  $core.bool hasMediaType() => $_has(6);
  @$pb.TagNumber(8)
  void clearMediaType() => $_clearField(8);

  @$pb.TagNumber(12)
  $core.List<$core.int> get rawRgba => $_getN(7);
  @$pb.TagNumber(12)
  set rawRgba($core.List<$core.int> value) => $_setBytes(7, value);
  @$pb.TagNumber(12)
  $core.bool hasRawRgba() => $_has(7);
  @$pb.TagNumber(12)
  void clearRawRgba() => $_clearField(12);
}

class VLMGenerationRequest extends $pb.GeneratedMessage {
  factory VLMGenerationRequest({
    $core.String? requestId,
    $core.Iterable<VLMImage>? images,
    $core.String? modelId,
    $core.String? prompt,
    VLMVisionOptions? vision,
    $core.Iterable<$0.ChatMessage>? messages,
    $1.LLMGenerationOptions? options,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (images != null) result.images.addAll(images);
    if (modelId != null) result.modelId = modelId;
    if (prompt != null) result.prompt = prompt;
    if (vision != null) result.vision = vision;
    if (messages != null) result.messages.addAll(messages);
    if (options != null) result.options = options;
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
    ..aOS(4, _omitFieldNames ? '' : 'modelId')
    ..aOS(6, _omitFieldNames ? '' : 'prompt')
    ..aOM<VLMVisionOptions>(7, _omitFieldNames ? '' : 'vision',
        subBuilder: VLMVisionOptions.create)
    ..pPM<$0.ChatMessage>(8, _omitFieldNames ? '' : 'messages',
        subBuilder: $0.ChatMessage.create)
    ..aOM<$1.LLMGenerationOptions>(9, _omitFieldNames ? '' : 'options',
        subBuilder: $1.LLMGenerationOptions.create)
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

  @$pb.TagNumber(4)
  $core.String get modelId => $_getSZ(2);
  @$pb.TagNumber(4)
  set modelId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(4)
  $core.bool hasModelId() => $_has(2);
  @$pb.TagNumber(4)
  void clearModelId() => $_clearField(4);

  /// The question about the image, for the single-turn quickstart path.
  @$pb.TagNumber(6)
  $core.String get prompt => $_getSZ(3);
  @$pb.TagNumber(6)
  set prompt($core.String value) => $_setString(3, value);
  @$pb.TagNumber(6)
  $core.bool hasPrompt() => $_has(3);
  @$pb.TagNumber(6)
  void clearPrompt() => $_clearField(6);

  /// Only the knobs that have no text-generation meaning.
  @$pb.TagNumber(7)
  VLMVisionOptions get vision => $_getN(4);
  @$pb.TagNumber(7)
  set vision(VLMVisionOptions value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasVision() => $_has(4);
  @$pb.TagNumber(7)
  void clearVision() => $_clearField(7);
  @$pb.TagNumber(7)
  VLMVisionOptions ensureVision() => $_ensure(4);

  /// Ordered conversation. A follow-up question about the same picture is
  /// just another turn; images ride as ChatMessage.attachments.
  @$pb.TagNumber(8)
  $pb.PbList<$0.ChatMessage> get messages => $_getList(5);

  /// One options set for all text generation, image or not -- same names,
  /// same defaults, same validation as the text API. Carries
  /// structured_output, which is how OCR / field extraction / bounding
  /// boxes are expressed (deliberately no ocr() or detect() verb).
  @$pb.TagNumber(9)
  $1.LLMGenerationOptions get options => $_getN(6);
  @$pb.TagNumber(9)
  set options($1.LLMGenerationOptions value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasOptions() => $_has(6);
  @$pb.TagNumber(9)
  void clearOptions() => $_clearField(9);
  @$pb.TagNumber(9)
  $1.LLMGenerationOptions ensureOptions() => $_ensure(6);
}

/// The four genuinely vision-specific knobs. Everything else in the old
/// VLMGenerationOptions was either a copy of LLMGenerationOptions or dead.
class VLMVisionOptions extends $pb.GeneratedMessage {
  factory VLMVisionOptions({
    VLMModelFamily? modelFamily,
    VLMChatTemplate? customChatTemplate,
    $core.String? imageMarkerOverride,
    $core.int? maxImageTokens,
  }) {
    final result = create();
    if (modelFamily != null) result.modelFamily = modelFamily;
    if (customChatTemplate != null)
      result.customChatTemplate = customChatTemplate;
    if (imageMarkerOverride != null)
      result.imageMarkerOverride = imageMarkerOverride;
    if (maxImageTokens != null) result.maxImageTokens = maxImageTokens;
    return result;
  }

  VLMVisionOptions._();

  factory VLMVisionOptions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VLMVisionOptions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VLMVisionOptions',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<VLMModelFamily>(1, _omitFieldNames ? '' : 'modelFamily',
        enumValues: VLMModelFamily.values)
    ..aOM<VLMChatTemplate>(2, _omitFieldNames ? '' : 'customChatTemplate',
        subBuilder: VLMChatTemplate.create)
    ..aOS(3, _omitFieldNames ? '' : 'imageMarkerOverride')
    ..aI(4, _omitFieldNames ? '' : 'maxImageTokens')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VLMVisionOptions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VLMVisionOptions copyWith(void Function(VLMVisionOptions) updates) =>
      super.copyWith((message) => updates(message as VLMVisionOptions))
          as VLMVisionOptions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VLMVisionOptions create() => VLMVisionOptions._();
  @$core.override
  VLMVisionOptions createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VLMVisionOptions getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VLMVisionOptions>(create);
  static VLMVisionOptions? _defaultInstance;

  @$pb.TagNumber(1)
  VLMModelFamily get modelFamily => $_getN(0);
  @$pb.TagNumber(1)
  set modelFamily(VLMModelFamily value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasModelFamily() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelFamily() => $_clearField(1);

  /// Live end-to-end (commons converts it, llama.cpp applies it); it is
  /// simply not surfaced by the v3 facades yet.
  @$pb.TagNumber(2)
  VLMChatTemplate get customChatTemplate => $_getN(1);
  @$pb.TagNumber(2)
  set customChatTemplate(VLMChatTemplate value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasCustomChatTemplate() => $_has(1);
  @$pb.TagNumber(2)
  void clearCustomChatTemplate() => $_clearField(2);
  @$pb.TagNumber(2)
  VLMChatTemplate ensureCustomChatTemplate() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.String get imageMarkerOverride => $_getSZ(2);
  @$pb.TagNumber(3)
  set imageMarkerOverride($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasImageMarkerOverride() => $_has(2);
  @$pb.TagNumber(3)
  void clearImageMarkerOverride() => $_clearField(3);

  /// Per-image vision-token budget -- the unit that actually drives
  /// prefill (cf. llama.cpp --image-max-tokens, Gemini media_resolution).
  /// 0 = the bundle's compiled default. The value actually used is
  /// reported back as VLMResult.image_tokens.
  @$pb.TagNumber(4)
  $core.int get maxImageTokens => $_getIZ(3);
  @$pb.TagNumber(4)
  set maxImageTokens($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMaxImageTokens() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxImageTokens() => $_clearField(4);
}

class VLMResult extends $pb.GeneratedMessage {
  factory VLMResult({
    $core.String? text,
    $fixnum.Int64? totalTimeMs,
    $core.int? imageTokens,
    $fixnum.Int64? imageEncodeTimeMs,
    $core.String? finishReason,
    $2.TokenUsage? usage,
    $3.SDKError? error,
  }) {
    final result = create();
    if (text != null) result.text = text;
    if (totalTimeMs != null) result.totalTimeMs = totalTimeMs;
    if (imageTokens != null) result.imageTokens = imageTokens;
    if (imageEncodeTimeMs != null) result.imageEncodeTimeMs = imageEncodeTimeMs;
    if (finishReason != null) result.finishReason = finishReason;
    if (usage != null) result.usage = usage;
    if (error != null) result.error = error;
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
    ..aInt64(5, _omitFieldNames ? '' : 'totalTimeMs')
    ..aI(7, _omitFieldNames ? '' : 'imageTokens')
    ..aInt64(9, _omitFieldNames ? '' : 'imageEncodeTimeMs')
    ..aOS(13, _omitFieldNames ? '' : 'finishReason')
    ..aOM<$2.TokenUsage>(15, _omitFieldNames ? '' : 'usage',
        subBuilder: $2.TokenUsage.create)
    ..aOM<$3.SDKError>(16, _omitFieldNames ? '' : 'error',
        subBuilder: $3.SDKError.create)
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

  /// Wall-clock for the whole call, image encode included. int64 ms is the
  /// unit for every duration on this surface; the _ms suffix stays explicit.
  @$pb.TagNumber(5)
  $fixnum.Int64 get totalTimeMs => $_getI64(1);
  @$pb.TagNumber(5)
  set totalTimeMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(5)
  $core.bool hasTotalTimeMs() => $_has(1);
  @$pb.TagNumber(5)
  void clearTotalTimeMs() => $_clearField(5);

  @$pb.TagNumber(7)
  $core.int get imageTokens => $_getIZ(2);
  @$pb.TagNumber(7)
  set imageTokens($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(7)
  $core.bool hasImageTokens() => $_has(2);
  @$pb.TagNumber(7)
  void clearImageTokens() => $_clearField(7);

  /// canonical spelling (usage = 15)
  @$pb.TagNumber(9)
  $fixnum.Int64 get imageEncodeTimeMs => $_getI64(3);
  @$pb.TagNumber(9)
  set imageEncodeTimeMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(9)
  $core.bool hasImageEncodeTimeMs() => $_has(3);
  @$pb.TagNumber(9)
  void clearImageEncodeTimeMs() => $_clearField(9);

  /// Produced by commons on both the one-shot and the streaming path, with
  /// the LLM domain's vocabulary: "stop" | "length" | "stop_sequence".
  @$pb.TagNumber(13)
  $core.String get finishReason => $_getSZ(4);
  @$pb.TagNumber(13)
  set finishReason($core.String value) => $_setString(4, value);
  @$pb.TagNumber(13)
  $core.bool hasFinishReason() => $_has(4);
  @$pb.TagNumber(13)
  void clearFinishReason() => $_clearField(13);

  @$pb.TagNumber(15)
  $2.TokenUsage get usage => $_getN(5);
  @$pb.TagNumber(15)
  set usage($2.TokenUsage value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasUsage() => $_has(5);
  @$pb.TagNumber(15)
  void clearUsage() => $_clearField(15);
  @$pb.TagNumber(15)
  $2.TokenUsage ensureUsage() => $_ensure(5);

  @$pb.TagNumber(16)
  $3.SDKError get error => $_getN(6);
  @$pb.TagNumber(16)
  set error($3.SDKError value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasError() => $_has(6);
  @$pb.TagNumber(16)
  void clearError() => $_clearField(16);
  @$pb.TagNumber(16)
  $3.SDKError ensureError() => $_ensure(6);
}

class VLMStreamEvent extends $pb.GeneratedMessage {
  factory VLMStreamEvent({
    $fixnum.Int64? timestampUs,
    $core.String? requestId,
    VLMStreamEventKind? kind,
    $core.String? token,
    $core.int? tokenIndex,
    VLMResult? result,
    $3.SDKError? error,
  }) {
    final result$ = create();
    if (timestampUs != null) result$.timestampUs = timestampUs;
    if (requestId != null) result$.requestId = requestId;
    if (kind != null) result$.kind = kind;
    if (token != null) result$.token = token;
    if (tokenIndex != null) result$.tokenIndex = tokenIndex;
    if (result != null) result$.result = result;
    if (error != null) result$.error = error;
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
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(3, _omitFieldNames ? '' : 'requestId')
    ..aE<VLMStreamEventKind>(4, _omitFieldNames ? '' : 'kind',
        enumValues: VLMStreamEventKind.values)
    ..aOS(5, _omitFieldNames ? '' : 'token')
    ..aI(6, _omitFieldNames ? '' : 'tokenIndex')
    ..aOM<VLMResult>(9, _omitFieldNames ? '' : 'result',
        subBuilder: VLMResult.create)
    ..aOM<$3.SDKError>(12, _omitFieldNames ? '' : 'error',
        subBuilder: $3.SDKError.create)
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

  /// The single terminal discriminator: COMPLETED or ERROR ends the stream.
  @$pb.TagNumber(4)
  VLMStreamEventKind get kind => $_getN(2);
  @$pb.TagNumber(4)
  set kind(VLMStreamEventKind value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasKind() => $_has(2);
  @$pb.TagNumber(4)
  void clearKind() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get token => $_getSZ(3);
  @$pb.TagNumber(5)
  set token($core.String value) => $_setString(3, value);
  @$pb.TagNumber(5)
  $core.bool hasToken() => $_has(3);
  @$pb.TagNumber(5)
  void clearToken() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get tokenIndex => $_getIZ(4);
  @$pb.TagNumber(6)
  set tokenIndex($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(6)
  $core.bool hasTokenIndex() => $_has(4);
  @$pb.TagNumber(6)
  void clearTokenIndex() => $_clearField(6);

  /// Rate comes from result.usage.tokens_per_second on the terminal event,
  /// in TokenUsage's own type. No second copy, no second scalar type.
  @$pb.TagNumber(9)
  VLMResult get result => $_getN(5);
  @$pb.TagNumber(9)
  set result(VLMResult value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasResult() => $_has(5);
  @$pb.TagNumber(9)
  void clearResult() => $_clearField(9);
  @$pb.TagNumber(9)
  VLMResult ensureResult() => $_ensure(5);

  @$pb.TagNumber(12)
  $3.SDKError get error => $_getN(6);
  @$pb.TagNumber(12)
  set error($3.SDKError value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasError() => $_has(6);
  @$pb.TagNumber(12)
  void clearError() => $_clearField(12);
  @$pb.TagNumber(12)
  $3.SDKError ensureError() => $_ensure(6);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
