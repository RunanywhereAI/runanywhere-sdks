///
//  Generated code. Do not modify.
//  source: vlm_options.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'vlm_options.pbenum.dart';

export 'vlm_options.pbenum.dart';

enum VLMImage_Source {
  filePath, 
  encoded, 
  rawRgb, 
  base64, 
  notSet
}

class VLMImage extends $pb.GeneratedMessage {
  static const $core.Map<$core.int, VLMImage_Source> _VLMImage_SourceByTag = {
    1 : VLMImage_Source.filePath,
    2 : VLMImage_Source.encoded,
    3 : VLMImage_Source.rawRgb,
    4 : VLMImage_Source.base64,
    0 : VLMImage_Source.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'VLMImage', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..oo(0, [1, 2, 3, 4])
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'filePath')
    ..a<$core.List<$core.int>>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'encoded', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'rawRgb', $pb.PbFieldType.OY)
    ..aOS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'base64')
    ..a<$core.int>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'width', $pb.PbFieldType.O3)
    ..a<$core.int>(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'height', $pb.PbFieldType.O3)
    ..e<VLMImageFormat>(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'format', $pb.PbFieldType.OE, defaultOrMaker: VLMImageFormat.VLM_IMAGE_FORMAT_UNSPECIFIED, valueOf: VLMImageFormat.valueOf, enumValues: VLMImageFormat.values)
    ..hasRequiredFields = false
  ;

  VLMImage._() : super();
  factory VLMImage({
    $core.String? filePath,
    $core.List<$core.int>? encoded,
    $core.List<$core.int>? rawRgb,
    $core.String? base64,
    $core.int? width,
    $core.int? height,
    VLMImageFormat? format,
  }) {
    final _result = create();
    if (filePath != null) {
      _result.filePath = filePath;
    }
    if (encoded != null) {
      _result.encoded = encoded;
    }
    if (rawRgb != null) {
      _result.rawRgb = rawRgb;
    }
    if (base64 != null) {
      _result.base64 = base64;
    }
    if (width != null) {
      _result.width = width;
    }
    if (height != null) {
      _result.height = height;
    }
    if (format != null) {
      _result.format = format;
    }
    return _result;
  }
  factory VLMImage.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VLMImage.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VLMImage clone() => VLMImage()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VLMImage copyWith(void Function(VLMImage) updates) => super.copyWith((message) => updates(message as VLMImage)) as VLMImage; // ignore: deprecated_member_use
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

class VLMConfiguration extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'VLMConfiguration', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'modelId')
    ..a<$core.int>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'maxImageSizePx', $pb.PbFieldType.O3)
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'maxTokens', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  VLMConfiguration._() : super();
  factory VLMConfiguration({
    $core.String? modelId,
    $core.int? maxImageSizePx,
    $core.int? maxTokens,
  }) {
    final _result = create();
    if (modelId != null) {
      _result.modelId = modelId;
    }
    if (maxImageSizePx != null) {
      _result.maxImageSizePx = maxImageSizePx;
    }
    if (maxTokens != null) {
      _result.maxTokens = maxTokens;
    }
    return _result;
  }
  factory VLMConfiguration.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VLMConfiguration.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VLMConfiguration clone() => VLMConfiguration()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VLMConfiguration copyWith(void Function(VLMConfiguration) updates) => super.copyWith((message) => updates(message as VLMConfiguration)) as VLMConfiguration; // ignore: deprecated_member_use
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

  @$pb.TagNumber(3)
  $core.int get maxTokens => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxTokens($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMaxTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxTokens() => clearField(3);
}

class VLMGenerationOptions extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'VLMGenerationOptions', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'prompt')
    ..a<$core.int>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'maxTokens', $pb.PbFieldType.O3)
    ..a<$core.double>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'temperature', $pb.PbFieldType.OF)
    ..a<$core.double>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'topP', $pb.PbFieldType.OF)
    ..a<$core.int>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'topK', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  VLMGenerationOptions._() : super();
  factory VLMGenerationOptions({
    $core.String? prompt,
    $core.int? maxTokens,
    $core.double? temperature,
    $core.double? topP,
    $core.int? topK,
  }) {
    final _result = create();
    if (prompt != null) {
      _result.prompt = prompt;
    }
    if (maxTokens != null) {
      _result.maxTokens = maxTokens;
    }
    if (temperature != null) {
      _result.temperature = temperature;
    }
    if (topP != null) {
      _result.topP = topP;
    }
    if (topK != null) {
      _result.topK = topK;
    }
    return _result;
  }
  factory VLMGenerationOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VLMGenerationOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VLMGenerationOptions clone() => VLMGenerationOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VLMGenerationOptions copyWith(void Function(VLMGenerationOptions) updates) => super.copyWith((message) => updates(message as VLMGenerationOptions)) as VLMGenerationOptions; // ignore: deprecated_member_use
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
}

class VLMResult extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'VLMResult', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'text')
    ..a<$core.int>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'promptTokens', $pb.PbFieldType.O3)
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'completionTokens', $pb.PbFieldType.O3)
    ..aInt64(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'totalTokens')
    ..aInt64(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'processingTimeMs')
    ..a<$core.double>(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'tokensPerSecond', $pb.PbFieldType.OF)
    ..hasRequiredFields = false
  ;

  VLMResult._() : super();
  factory VLMResult({
    $core.String? text,
    $core.int? promptTokens,
    $core.int? completionTokens,
    $fixnum.Int64? totalTokens,
    $fixnum.Int64? processingTimeMs,
    $core.double? tokensPerSecond,
  }) {
    final _result = create();
    if (text != null) {
      _result.text = text;
    }
    if (promptTokens != null) {
      _result.promptTokens = promptTokens;
    }
    if (completionTokens != null) {
      _result.completionTokens = completionTokens;
    }
    if (totalTokens != null) {
      _result.totalTokens = totalTokens;
    }
    if (processingTimeMs != null) {
      _result.processingTimeMs = processingTimeMs;
    }
    if (tokensPerSecond != null) {
      _result.tokensPerSecond = tokensPerSecond;
    }
    return _result;
  }
  factory VLMResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VLMResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VLMResult clone() => VLMResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VLMResult copyWith(void Function(VLMResult) updates) => super.copyWith((message) => updates(message as VLMResult)) as VLMResult; // ignore: deprecated_member_use
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

  @$pb.TagNumber(6)
  $core.double get tokensPerSecond => $_getN(5);
  @$pb.TagNumber(6)
  set tokensPerSecond($core.double v) { $_setFloat(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTokensPerSecond() => $_has(5);
  @$pb.TagNumber(6)
  void clearTokensPerSecond() => clearField(6);
}

