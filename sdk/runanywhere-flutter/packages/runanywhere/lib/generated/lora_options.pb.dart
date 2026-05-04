//
//  Generated code. Do not modify.
//  source: lora_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

///  ---------------------------------------------------------------------------
///  Configuration for loading a LoRA adapter.
///
///  `adapter_path` is a path on disk to a LoRA GGUF file. `scale` controls the
///  adapter's effect strength (default 1.0; e.g. 0.3 for F16 adapters on
///  quantized bases). `adapter_id` is optional and, when present, links the
///  runtime config back to a `LoraAdapterCatalogEntry.id` — none of the current
///  SDK shapes carry it, so it is encoded as a `proto3 optional` field.
///  ---------------------------------------------------------------------------
class LoRAAdapterConfig extends $pb.GeneratedMessage {
  factory LoRAAdapterConfig({
    $core.String? adapterPath,
    $core.double? scale,
    $core.String? adapterId,
  }) {
    final $result = create();
    if (adapterPath != null) {
      $result.adapterPath = adapterPath;
    }
    if (scale != null) {
      $result.scale = scale;
    }
    if (adapterId != null) {
      $result.adapterId = adapterId;
    }
    return $result;
  }
  LoRAAdapterConfig._() : super();
  factory LoRAAdapterConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoRAAdapterConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LoRAAdapterConfig', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'adapterPath')
    ..a<$core.double>(2, _omitFieldNames ? '' : 'scale', $pb.PbFieldType.OF)
    ..aOS(3, _omitFieldNames ? '' : 'adapterId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoRAAdapterConfig clone() => LoRAAdapterConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoRAAdapterConfig copyWith(void Function(LoRAAdapterConfig) updates) => super.copyWith((message) => updates(message as LoRAAdapterConfig)) as LoRAAdapterConfig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoRAAdapterConfig create() => LoRAAdapterConfig._();
  LoRAAdapterConfig createEmptyInstance() => create();
  static $pb.PbList<LoRAAdapterConfig> createRepeated() => $pb.PbList<LoRAAdapterConfig>();
  @$core.pragma('dart2js:noInline')
  static LoRAAdapterConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoRAAdapterConfig>(create);
  static LoRAAdapterConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get adapterPath => $_getSZ(0);
  @$pb.TagNumber(1)
  set adapterPath($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAdapterPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearAdapterPath() => clearField(1);

  @$pb.TagNumber(2)
  $core.double get scale => $_getN(1);
  @$pb.TagNumber(2)
  set scale($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasScale() => $_has(1);
  @$pb.TagNumber(2)
  void clearScale() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get adapterId => $_getSZ(2);
  @$pb.TagNumber(3)
  set adapterId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAdapterId() => $_has(2);
  @$pb.TagNumber(3)
  void clearAdapterId() => clearField(3);
}

///  ---------------------------------------------------------------------------
///  Info about a currently-loaded LoRA adapter (read-only snapshot).
///
///  `adapter_id` and `error_message` are not present in any current SDK shape;
///  they are encoded as `proto3 optional` so the existing fields (path, scale,
///  applied) round-trip exactly while reserving room for richer status reports.
///  ---------------------------------------------------------------------------
class LoRAAdapterInfo extends $pb.GeneratedMessage {
  factory LoRAAdapterInfo({
    $core.String? adapterId,
    $core.String? adapterPath,
    $core.double? scale,
    $core.bool? applied,
    $core.String? errorMessage,
  }) {
    final $result = create();
    if (adapterId != null) {
      $result.adapterId = adapterId;
    }
    if (adapterPath != null) {
      $result.adapterPath = adapterPath;
    }
    if (scale != null) {
      $result.scale = scale;
    }
    if (applied != null) {
      $result.applied = applied;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    return $result;
  }
  LoRAAdapterInfo._() : super();
  factory LoRAAdapterInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoRAAdapterInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LoRAAdapterInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'adapterId')
    ..aOS(2, _omitFieldNames ? '' : 'adapterPath')
    ..a<$core.double>(3, _omitFieldNames ? '' : 'scale', $pb.PbFieldType.OF)
    ..aOB(4, _omitFieldNames ? '' : 'applied')
    ..aOS(5, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoRAAdapterInfo clone() => LoRAAdapterInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoRAAdapterInfo copyWith(void Function(LoRAAdapterInfo) updates) => super.copyWith((message) => updates(message as LoRAAdapterInfo)) as LoRAAdapterInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoRAAdapterInfo create() => LoRAAdapterInfo._();
  LoRAAdapterInfo createEmptyInstance() => create();
  static $pb.PbList<LoRAAdapterInfo> createRepeated() => $pb.PbList<LoRAAdapterInfo>();
  @$core.pragma('dart2js:noInline')
  static LoRAAdapterInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoRAAdapterInfo>(create);
  static LoRAAdapterInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get adapterId => $_getSZ(0);
  @$pb.TagNumber(1)
  set adapterId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAdapterId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAdapterId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get adapterPath => $_getSZ(1);
  @$pb.TagNumber(2)
  set adapterPath($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAdapterPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearAdapterPath() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get scale => $_getN(2);
  @$pb.TagNumber(3)
  set scale($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasScale() => $_has(2);
  @$pb.TagNumber(3)
  void clearScale() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get applied => $_getBF(3);
  @$pb.TagNumber(4)
  set applied($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasApplied() => $_has(3);
  @$pb.TagNumber(4)
  void clearApplied() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get errorMessage => $_getSZ(4);
  @$pb.TagNumber(5)
  set errorMessage($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasErrorMessage() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorMessage() => clearField(5);
}

///  ---------------------------------------------------------------------------
///  Catalog entry for a LoRA adapter registered with the SDK.
///  Apps register entries at startup; SDKs query "which adapters work with this
///  model" without reinventing detection logic per platform.
///
///  `author` is not present in any current SDK shape (Swift, Kotlin, Dart, RN,
///  Web, C ABI) — it is encoded as `proto3 optional` so codegen produces a
///  nullable / has-bit-tracked field.
///  ---------------------------------------------------------------------------
class LoraAdapterCatalogEntry extends $pb.GeneratedMessage {
  factory LoraAdapterCatalogEntry({
    $core.String? id,
    $core.String? name,
    $core.String? description,
    $core.String? url,
    $core.String? filename,
    $core.Iterable<$core.String>? compatibleModels,
    $fixnum.Int64? sizeBytes,
    $core.String? author,
    $core.double? defaultScale,
    $core.String? checksumSha256,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (name != null) {
      $result.name = name;
    }
    if (description != null) {
      $result.description = description;
    }
    if (url != null) {
      $result.url = url;
    }
    if (filename != null) {
      $result.filename = filename;
    }
    if (compatibleModels != null) {
      $result.compatibleModels.addAll(compatibleModels);
    }
    if (sizeBytes != null) {
      $result.sizeBytes = sizeBytes;
    }
    if (author != null) {
      $result.author = author;
    }
    if (defaultScale != null) {
      $result.defaultScale = defaultScale;
    }
    if (checksumSha256 != null) {
      $result.checksumSha256 = checksumSha256;
    }
    return $result;
  }
  LoraAdapterCatalogEntry._() : super();
  factory LoraAdapterCatalogEntry.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoraAdapterCatalogEntry.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LoraAdapterCatalogEntry', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'description')
    ..aOS(4, _omitFieldNames ? '' : 'url')
    ..aOS(5, _omitFieldNames ? '' : 'filename')
    ..pPS(6, _omitFieldNames ? '' : 'compatibleModels')
    ..aInt64(7, _omitFieldNames ? '' : 'sizeBytes')
    ..aOS(8, _omitFieldNames ? '' : 'author')
    ..a<$core.double>(9, _omitFieldNames ? '' : 'defaultScale', $pb.PbFieldType.OF)
    ..aOS(10, _omitFieldNames ? '' : 'checksumSha256')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoraAdapterCatalogEntry clone() => LoraAdapterCatalogEntry()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoraAdapterCatalogEntry copyWith(void Function(LoraAdapterCatalogEntry) updates) => super.copyWith((message) => updates(message as LoraAdapterCatalogEntry)) as LoraAdapterCatalogEntry;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogEntry create() => LoraAdapterCatalogEntry._();
  LoraAdapterCatalogEntry createEmptyInstance() => create();
  static $pb.PbList<LoraAdapterCatalogEntry> createRepeated() => $pb.PbList<LoraAdapterCatalogEntry>();
  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogEntry getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoraAdapterCatalogEntry>(create);
  static LoraAdapterCatalogEntry? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get description => $_getSZ(2);
  @$pb.TagNumber(3)
  set description($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDescription() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescription() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get url => $_getSZ(3);
  @$pb.TagNumber(4)
  set url($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasUrl() => $_has(3);
  @$pb.TagNumber(4)
  void clearUrl() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get filename => $_getSZ(4);
  @$pb.TagNumber(5)
  set filename($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasFilename() => $_has(4);
  @$pb.TagNumber(5)
  void clearFilename() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.String> get compatibleModels => $_getList(5);

  @$pb.TagNumber(7)
  $fixnum.Int64 get sizeBytes => $_getI64(6);
  @$pb.TagNumber(7)
  set sizeBytes($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasSizeBytes() => $_has(6);
  @$pb.TagNumber(7)
  void clearSizeBytes() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get author => $_getSZ(7);
  @$pb.TagNumber(8)
  set author($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasAuthor() => $_has(7);
  @$pb.TagNumber(8)
  void clearAuthor() => clearField(8);

  @$pb.TagNumber(9)
  $core.double get defaultScale => $_getN(8);
  @$pb.TagNumber(9)
  set defaultScale($core.double v) { $_setFloat(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasDefaultScale() => $_has(8);
  @$pb.TagNumber(9)
  void clearDefaultScale() => clearField(9);

  @$pb.TagNumber(10)
  $core.String get checksumSha256 => $_getSZ(9);
  @$pb.TagNumber(10)
  set checksumSha256($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasChecksumSha256() => $_has(9);
  @$pb.TagNumber(10)
  void clearChecksumSha256() => clearField(10);
}

///  ---------------------------------------------------------------------------
///  Result of a LoRA compatibility pre-check.
///
///  `base_model_required` is not present in any current SDK shape — it is
///  encoded as `proto3 optional` so a future implementation can surface "this
///  adapter requires base model X" without breaking wire compatibility.
///  ---------------------------------------------------------------------------
class LoraCompatibilityResult extends $pb.GeneratedMessage {
  factory LoraCompatibilityResult({
    $core.bool? isCompatible,
    $core.String? errorMessage,
    $core.String? baseModelRequired,
  }) {
    final $result = create();
    if (isCompatible != null) {
      $result.isCompatible = isCompatible;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (baseModelRequired != null) {
      $result.baseModelRequired = baseModelRequired;
    }
    return $result;
  }
  LoraCompatibilityResult._() : super();
  factory LoraCompatibilityResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoraCompatibilityResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LoraCompatibilityResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isCompatible')
    ..aOS(2, _omitFieldNames ? '' : 'errorMessage')
    ..aOS(3, _omitFieldNames ? '' : 'baseModelRequired')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoraCompatibilityResult clone() => LoraCompatibilityResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoraCompatibilityResult copyWith(void Function(LoraCompatibilityResult) updates) => super.copyWith((message) => updates(message as LoraCompatibilityResult)) as LoraCompatibilityResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraCompatibilityResult create() => LoraCompatibilityResult._();
  LoraCompatibilityResult createEmptyInstance() => create();
  static $pb.PbList<LoraCompatibilityResult> createRepeated() => $pb.PbList<LoraCompatibilityResult>();
  @$core.pragma('dart2js:noInline')
  static LoraCompatibilityResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoraCompatibilityResult>(create);
  static LoraCompatibilityResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get isCompatible => $_getBF(0);
  @$pb.TagNumber(1)
  set isCompatible($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasIsCompatible() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsCompatible() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get errorMessage => $_getSZ(1);
  @$pb.TagNumber(2)
  set errorMessage($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasErrorMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearErrorMessage() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get baseModelRequired => $_getSZ(2);
  @$pb.TagNumber(3)
  set baseModelRequired($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasBaseModelRequired() => $_has(2);
  @$pb.TagNumber(3)
  void clearBaseModelRequired() => clearField(3);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
