///
//  Generated code. Do not modify.
//  source: lora_options.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

class LoRAAdapterConfig extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'LoRAAdapterConfig', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'adapterPath')
    ..a<$core.double>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'scale', $pb.PbFieldType.OF)
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'adapterId')
    ..hasRequiredFields = false
  ;

  LoRAAdapterConfig._() : super();
  factory LoRAAdapterConfig({
    $core.String? adapterPath,
    $core.double? scale,
    $core.String? adapterId,
  }) {
    final _result = create();
    if (adapterPath != null) {
      _result.adapterPath = adapterPath;
    }
    if (scale != null) {
      _result.scale = scale;
    }
    if (adapterId != null) {
      _result.adapterId = adapterId;
    }
    return _result;
  }
  factory LoRAAdapterConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoRAAdapterConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoRAAdapterConfig clone() => LoRAAdapterConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoRAAdapterConfig copyWith(void Function(LoRAAdapterConfig) updates) => super.copyWith((message) => updates(message as LoRAAdapterConfig)) as LoRAAdapterConfig; // ignore: deprecated_member_use
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

class LoRAAdapterInfo extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'LoRAAdapterInfo', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'adapterId')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'adapterPath')
    ..a<$core.double>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'scale', $pb.PbFieldType.OF)
    ..aOB(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'applied')
    ..aOS(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  LoRAAdapterInfo._() : super();
  factory LoRAAdapterInfo({
    $core.String? adapterId,
    $core.String? adapterPath,
    $core.double? scale,
    $core.bool? applied,
    $core.String? errorMessage,
  }) {
    final _result = create();
    if (adapterId != null) {
      _result.adapterId = adapterId;
    }
    if (adapterPath != null) {
      _result.adapterPath = adapterPath;
    }
    if (scale != null) {
      _result.scale = scale;
    }
    if (applied != null) {
      _result.applied = applied;
    }
    if (errorMessage != null) {
      _result.errorMessage = errorMessage;
    }
    return _result;
  }
  factory LoRAAdapterInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoRAAdapterInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoRAAdapterInfo clone() => LoRAAdapterInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoRAAdapterInfo copyWith(void Function(LoRAAdapterInfo) updates) => super.copyWith((message) => updates(message as LoRAAdapterInfo)) as LoRAAdapterInfo; // ignore: deprecated_member_use
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

class LoraAdapterCatalogEntry extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'LoraAdapterCatalogEntry', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'id')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'name')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'description')
    ..aOS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'url')
    ..aOS(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'filename')
    ..pPS(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'compatibleModels')
    ..aInt64(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sizeBytes')
    ..aOS(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'author')
    ..hasRequiredFields = false
  ;

  LoraAdapterCatalogEntry._() : super();
  factory LoraAdapterCatalogEntry({
    $core.String? id,
    $core.String? name,
    $core.String? description,
    $core.String? url,
    $core.String? filename,
    $core.Iterable<$core.String>? compatibleModels,
    $fixnum.Int64? sizeBytes,
    $core.String? author,
  }) {
    final _result = create();
    if (id != null) {
      _result.id = id;
    }
    if (name != null) {
      _result.name = name;
    }
    if (description != null) {
      _result.description = description;
    }
    if (url != null) {
      _result.url = url;
    }
    if (filename != null) {
      _result.filename = filename;
    }
    if (compatibleModels != null) {
      _result.compatibleModels.addAll(compatibleModels);
    }
    if (sizeBytes != null) {
      _result.sizeBytes = sizeBytes;
    }
    if (author != null) {
      _result.author = author;
    }
    return _result;
  }
  factory LoraAdapterCatalogEntry.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoraAdapterCatalogEntry.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoraAdapterCatalogEntry clone() => LoraAdapterCatalogEntry()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoraAdapterCatalogEntry copyWith(void Function(LoraAdapterCatalogEntry) updates) => super.copyWith((message) => updates(message as LoraAdapterCatalogEntry)) as LoraAdapterCatalogEntry; // ignore: deprecated_member_use
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
}

class LoraCompatibilityResult extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'LoraCompatibilityResult', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'isCompatible')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'errorMessage')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'baseModelRequired')
    ..hasRequiredFields = false
  ;

  LoraCompatibilityResult._() : super();
  factory LoraCompatibilityResult({
    $core.bool? isCompatible,
    $core.String? errorMessage,
    $core.String? baseModelRequired,
  }) {
    final _result = create();
    if (isCompatible != null) {
      _result.isCompatible = isCompatible;
    }
    if (errorMessage != null) {
      _result.errorMessage = errorMessage;
    }
    if (baseModelRequired != null) {
      _result.baseModelRequired = baseModelRequired;
    }
    return _result;
  }
  factory LoraCompatibilityResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoraCompatibilityResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoraCompatibilityResult clone() => LoraCompatibilityResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoraCompatibilityResult copyWith(void Function(LoraCompatibilityResult) updates) => super.copyWith((message) => updates(message as LoraCompatibilityResult)) as LoraCompatibilityResult; // ignore: deprecated_member_use
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

