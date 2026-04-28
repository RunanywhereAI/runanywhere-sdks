///
//  Generated code. Do not modify.
//  source: model_types.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'model_types.pbenum.dart';

export 'model_types.pbenum.dart';

enum ModelInfo_Artifact {
  singleFile, 
  archive, 
  multiFile, 
  customStrategyId, 
  builtIn, 
  notSet
}

class ModelInfo extends $pb.GeneratedMessage {
  static const $core.Map<$core.int, ModelInfo_Artifact> _ModelInfo_ArtifactByTag = {
    20 : ModelInfo_Artifact.singleFile,
    21 : ModelInfo_Artifact.archive,
    22 : ModelInfo_Artifact.multiFile,
    23 : ModelInfo_Artifact.customStrategyId,
    24 : ModelInfo_Artifact.builtIn,
    0 : ModelInfo_Artifact.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ModelInfo', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..oo(0, [20, 21, 22, 23, 24])
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'id')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'name')
    ..e<ModelCategory>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'category', $pb.PbFieldType.OE, defaultOrMaker: ModelCategory.MODEL_CATEGORY_UNSPECIFIED, valueOf: ModelCategory.valueOf, enumValues: ModelCategory.values)
    ..e<ModelFormat>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'format', $pb.PbFieldType.OE, defaultOrMaker: ModelFormat.MODEL_FORMAT_UNSPECIFIED, valueOf: ModelFormat.valueOf, enumValues: ModelFormat.values)
    ..e<InferenceFramework>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'framework', $pb.PbFieldType.OE, defaultOrMaker: InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED, valueOf: InferenceFramework.valueOf, enumValues: InferenceFramework.values)
    ..aOS(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'downloadUrl')
    ..aOS(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'localPath')
    ..aInt64(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'downloadSizeBytes')
    ..a<$core.int>(9, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'contextLength', $pb.PbFieldType.O3)
    ..aOB(10, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'supportsThinking')
    ..aOB(11, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'supportsLora')
    ..aOS(12, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'description')
    ..e<ModelSource>(13, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'source', $pb.PbFieldType.OE, defaultOrMaker: ModelSource.MODEL_SOURCE_UNSPECIFIED, valueOf: ModelSource.valueOf, enumValues: ModelSource.values)
    ..aInt64(14, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'createdAtUnixMs')
    ..aInt64(15, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'updatedAtUnixMs')
    ..aOM<SingleFileArtifact>(20, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'singleFile', subBuilder: SingleFileArtifact.create)
    ..aOM<ArchiveArtifact>(21, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'archive', subBuilder: ArchiveArtifact.create)
    ..aOM<MultiFileArtifact>(22, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'multiFile', subBuilder: MultiFileArtifact.create)
    ..aOS(23, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'customStrategyId')
    ..aOB(24, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'builtIn')
    ..e<ModelArtifactType>(25, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'artifactType', $pb.PbFieldType.OE, defaultOrMaker: ModelArtifactType.MODEL_ARTIFACT_TYPE_UNSPECIFIED, valueOf: ModelArtifactType.valueOf, enumValues: ModelArtifactType.values)
    ..aOM<ExpectedModelFiles>(26, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'expectedFiles', subBuilder: ExpectedModelFiles.create)
    ..e<AccelerationPreference>(27, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'accelerationPreference', $pb.PbFieldType.OE, defaultOrMaker: AccelerationPreference.ACCELERATION_PREFERENCE_UNSPECIFIED, valueOf: AccelerationPreference.valueOf, enumValues: AccelerationPreference.values)
    ..e<RoutingPolicy>(28, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'routingPolicy', $pb.PbFieldType.OE, defaultOrMaker: RoutingPolicy.ROUTING_POLICY_UNSPECIFIED, valueOf: RoutingPolicy.valueOf, enumValues: RoutingPolicy.values)
    ..hasRequiredFields = false
  ;

  ModelInfo._() : super();
  factory ModelInfo({
    $core.String? id,
    $core.String? name,
    ModelCategory? category,
    ModelFormat? format,
    InferenceFramework? framework,
    $core.String? downloadUrl,
    $core.String? localPath,
    $fixnum.Int64? downloadSizeBytes,
    $core.int? contextLength,
    $core.bool? supportsThinking,
    $core.bool? supportsLora,
    $core.String? description,
    ModelSource? source,
    $fixnum.Int64? createdAtUnixMs,
    $fixnum.Int64? updatedAtUnixMs,
    SingleFileArtifact? singleFile,
    ArchiveArtifact? archive,
    MultiFileArtifact? multiFile,
    $core.String? customStrategyId,
    $core.bool? builtIn,
    ModelArtifactType? artifactType,
    ExpectedModelFiles? expectedFiles,
    AccelerationPreference? accelerationPreference,
    RoutingPolicy? routingPolicy,
  }) {
    final _result = create();
    if (id != null) {
      _result.id = id;
    }
    if (name != null) {
      _result.name = name;
    }
    if (category != null) {
      _result.category = category;
    }
    if (format != null) {
      _result.format = format;
    }
    if (framework != null) {
      _result.framework = framework;
    }
    if (downloadUrl != null) {
      _result.downloadUrl = downloadUrl;
    }
    if (localPath != null) {
      _result.localPath = localPath;
    }
    if (downloadSizeBytes != null) {
      _result.downloadSizeBytes = downloadSizeBytes;
    }
    if (contextLength != null) {
      _result.contextLength = contextLength;
    }
    if (supportsThinking != null) {
      _result.supportsThinking = supportsThinking;
    }
    if (supportsLora != null) {
      _result.supportsLora = supportsLora;
    }
    if (description != null) {
      _result.description = description;
    }
    if (source != null) {
      _result.source = source;
    }
    if (createdAtUnixMs != null) {
      _result.createdAtUnixMs = createdAtUnixMs;
    }
    if (updatedAtUnixMs != null) {
      _result.updatedAtUnixMs = updatedAtUnixMs;
    }
    if (singleFile != null) {
      _result.singleFile = singleFile;
    }
    if (archive != null) {
      _result.archive = archive;
    }
    if (multiFile != null) {
      _result.multiFile = multiFile;
    }
    if (customStrategyId != null) {
      _result.customStrategyId = customStrategyId;
    }
    if (builtIn != null) {
      _result.builtIn = builtIn;
    }
    if (artifactType != null) {
      _result.artifactType = artifactType;
    }
    if (expectedFiles != null) {
      _result.expectedFiles = expectedFiles;
    }
    if (accelerationPreference != null) {
      _result.accelerationPreference = accelerationPreference;
    }
    if (routingPolicy != null) {
      _result.routingPolicy = routingPolicy;
    }
    return _result;
  }
  factory ModelInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelInfo clone() => ModelInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelInfo copyWith(void Function(ModelInfo) updates) => super.copyWith((message) => updates(message as ModelInfo)) as ModelInfo; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ModelInfo create() => ModelInfo._();
  ModelInfo createEmptyInstance() => create();
  static $pb.PbList<ModelInfo> createRepeated() => $pb.PbList<ModelInfo>();
  @$core.pragma('dart2js:noInline')
  static ModelInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelInfo>(create);
  static ModelInfo? _defaultInstance;

  ModelInfo_Artifact whichArtifact() => _ModelInfo_ArtifactByTag[$_whichOneof(0)]!;
  void clearArtifact() => clearField($_whichOneof(0));

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
  ModelCategory get category => $_getN(2);
  @$pb.TagNumber(3)
  set category(ModelCategory v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasCategory() => $_has(2);
  @$pb.TagNumber(3)
  void clearCategory() => clearField(3);

  @$pb.TagNumber(4)
  ModelFormat get format => $_getN(3);
  @$pb.TagNumber(4)
  set format(ModelFormat v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasFormat() => $_has(3);
  @$pb.TagNumber(4)
  void clearFormat() => clearField(4);

  @$pb.TagNumber(5)
  InferenceFramework get framework => $_getN(4);
  @$pb.TagNumber(5)
  set framework(InferenceFramework v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasFramework() => $_has(4);
  @$pb.TagNumber(5)
  void clearFramework() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get downloadUrl => $_getSZ(5);
  @$pb.TagNumber(6)
  set downloadUrl($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasDownloadUrl() => $_has(5);
  @$pb.TagNumber(6)
  void clearDownloadUrl() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get localPath => $_getSZ(6);
  @$pb.TagNumber(7)
  set localPath($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasLocalPath() => $_has(6);
  @$pb.TagNumber(7)
  void clearLocalPath() => clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get downloadSizeBytes => $_getI64(7);
  @$pb.TagNumber(8)
  set downloadSizeBytes($fixnum.Int64 v) { $_setInt64(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasDownloadSizeBytes() => $_has(7);
  @$pb.TagNumber(8)
  void clearDownloadSizeBytes() => clearField(8);

  @$pb.TagNumber(9)
  $core.int get contextLength => $_getIZ(8);
  @$pb.TagNumber(9)
  set contextLength($core.int v) { $_setSignedInt32(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasContextLength() => $_has(8);
  @$pb.TagNumber(9)
  void clearContextLength() => clearField(9);

  @$pb.TagNumber(10)
  $core.bool get supportsThinking => $_getBF(9);
  @$pb.TagNumber(10)
  set supportsThinking($core.bool v) { $_setBool(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasSupportsThinking() => $_has(9);
  @$pb.TagNumber(10)
  void clearSupportsThinking() => clearField(10);

  @$pb.TagNumber(11)
  $core.bool get supportsLora => $_getBF(10);
  @$pb.TagNumber(11)
  set supportsLora($core.bool v) { $_setBool(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasSupportsLora() => $_has(10);
  @$pb.TagNumber(11)
  void clearSupportsLora() => clearField(11);

  @$pb.TagNumber(12)
  $core.String get description => $_getSZ(11);
  @$pb.TagNumber(12)
  set description($core.String v) { $_setString(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasDescription() => $_has(11);
  @$pb.TagNumber(12)
  void clearDescription() => clearField(12);

  @$pb.TagNumber(13)
  ModelSource get source => $_getN(12);
  @$pb.TagNumber(13)
  set source(ModelSource v) { setField(13, v); }
  @$pb.TagNumber(13)
  $core.bool hasSource() => $_has(12);
  @$pb.TagNumber(13)
  void clearSource() => clearField(13);

  @$pb.TagNumber(14)
  $fixnum.Int64 get createdAtUnixMs => $_getI64(13);
  @$pb.TagNumber(14)
  set createdAtUnixMs($fixnum.Int64 v) { $_setInt64(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasCreatedAtUnixMs() => $_has(13);
  @$pb.TagNumber(14)
  void clearCreatedAtUnixMs() => clearField(14);

  @$pb.TagNumber(15)
  $fixnum.Int64 get updatedAtUnixMs => $_getI64(14);
  @$pb.TagNumber(15)
  set updatedAtUnixMs($fixnum.Int64 v) { $_setInt64(14, v); }
  @$pb.TagNumber(15)
  $core.bool hasUpdatedAtUnixMs() => $_has(14);
  @$pb.TagNumber(15)
  void clearUpdatedAtUnixMs() => clearField(15);

  @$pb.TagNumber(20)
  SingleFileArtifact get singleFile => $_getN(15);
  @$pb.TagNumber(20)
  set singleFile(SingleFileArtifact v) { setField(20, v); }
  @$pb.TagNumber(20)
  $core.bool hasSingleFile() => $_has(15);
  @$pb.TagNumber(20)
  void clearSingleFile() => clearField(20);
  @$pb.TagNumber(20)
  SingleFileArtifact ensureSingleFile() => $_ensure(15);

  @$pb.TagNumber(21)
  ArchiveArtifact get archive => $_getN(16);
  @$pb.TagNumber(21)
  set archive(ArchiveArtifact v) { setField(21, v); }
  @$pb.TagNumber(21)
  $core.bool hasArchive() => $_has(16);
  @$pb.TagNumber(21)
  void clearArchive() => clearField(21);
  @$pb.TagNumber(21)
  ArchiveArtifact ensureArchive() => $_ensure(16);

  @$pb.TagNumber(22)
  MultiFileArtifact get multiFile => $_getN(17);
  @$pb.TagNumber(22)
  set multiFile(MultiFileArtifact v) { setField(22, v); }
  @$pb.TagNumber(22)
  $core.bool hasMultiFile() => $_has(17);
  @$pb.TagNumber(22)
  void clearMultiFile() => clearField(22);
  @$pb.TagNumber(22)
  MultiFileArtifact ensureMultiFile() => $_ensure(17);

  @$pb.TagNumber(23)
  $core.String get customStrategyId => $_getSZ(18);
  @$pb.TagNumber(23)
  set customStrategyId($core.String v) { $_setString(18, v); }
  @$pb.TagNumber(23)
  $core.bool hasCustomStrategyId() => $_has(18);
  @$pb.TagNumber(23)
  void clearCustomStrategyId() => clearField(23);

  @$pb.TagNumber(24)
  $core.bool get builtIn => $_getBF(19);
  @$pb.TagNumber(24)
  set builtIn($core.bool v) { $_setBool(19, v); }
  @$pb.TagNumber(24)
  $core.bool hasBuiltIn() => $_has(19);
  @$pb.TagNumber(24)
  void clearBuiltIn() => clearField(24);

  @$pb.TagNumber(25)
  ModelArtifactType get artifactType => $_getN(20);
  @$pb.TagNumber(25)
  set artifactType(ModelArtifactType v) { setField(25, v); }
  @$pb.TagNumber(25)
  $core.bool hasArtifactType() => $_has(20);
  @$pb.TagNumber(25)
  void clearArtifactType() => clearField(25);

  @$pb.TagNumber(26)
  ExpectedModelFiles get expectedFiles => $_getN(21);
  @$pb.TagNumber(26)
  set expectedFiles(ExpectedModelFiles v) { setField(26, v); }
  @$pb.TagNumber(26)
  $core.bool hasExpectedFiles() => $_has(21);
  @$pb.TagNumber(26)
  void clearExpectedFiles() => clearField(26);
  @$pb.TagNumber(26)
  ExpectedModelFiles ensureExpectedFiles() => $_ensure(21);

  @$pb.TagNumber(27)
  AccelerationPreference get accelerationPreference => $_getN(22);
  @$pb.TagNumber(27)
  set accelerationPreference(AccelerationPreference v) { setField(27, v); }
  @$pb.TagNumber(27)
  $core.bool hasAccelerationPreference() => $_has(22);
  @$pb.TagNumber(27)
  void clearAccelerationPreference() => clearField(27);

  @$pb.TagNumber(28)
  RoutingPolicy get routingPolicy => $_getN(23);
  @$pb.TagNumber(28)
  set routingPolicy(RoutingPolicy v) { setField(28, v); }
  @$pb.TagNumber(28)
  $core.bool hasRoutingPolicy() => $_has(23);
  @$pb.TagNumber(28)
  void clearRoutingPolicy() => clearField(28);
}

class SingleFileArtifact extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'SingleFileArtifact', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pPS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'requiredPatterns')
    ..pPS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'optionalPatterns')
    ..hasRequiredFields = false
  ;

  SingleFileArtifact._() : super();
  factory SingleFileArtifact({
    $core.Iterable<$core.String>? requiredPatterns,
    $core.Iterable<$core.String>? optionalPatterns,
  }) {
    final _result = create();
    if (requiredPatterns != null) {
      _result.requiredPatterns.addAll(requiredPatterns);
    }
    if (optionalPatterns != null) {
      _result.optionalPatterns.addAll(optionalPatterns);
    }
    return _result;
  }
  factory SingleFileArtifact.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SingleFileArtifact.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SingleFileArtifact clone() => SingleFileArtifact()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SingleFileArtifact copyWith(void Function(SingleFileArtifact) updates) => super.copyWith((message) => updates(message as SingleFileArtifact)) as SingleFileArtifact; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static SingleFileArtifact create() => SingleFileArtifact._();
  SingleFileArtifact createEmptyInstance() => create();
  static $pb.PbList<SingleFileArtifact> createRepeated() => $pb.PbList<SingleFileArtifact>();
  @$core.pragma('dart2js:noInline')
  static SingleFileArtifact getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SingleFileArtifact>(create);
  static SingleFileArtifact? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.String> get requiredPatterns => $_getList(0);

  @$pb.TagNumber(2)
  $core.List<$core.String> get optionalPatterns => $_getList(1);
}

class ArchiveArtifact extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ArchiveArtifact', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<ArchiveType>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'type', $pb.PbFieldType.OE, defaultOrMaker: ArchiveType.ARCHIVE_TYPE_UNSPECIFIED, valueOf: ArchiveType.valueOf, enumValues: ArchiveType.values)
    ..e<ArchiveStructure>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'structure', $pb.PbFieldType.OE, defaultOrMaker: ArchiveStructure.ARCHIVE_STRUCTURE_UNSPECIFIED, valueOf: ArchiveStructure.valueOf, enumValues: ArchiveStructure.values)
    ..pPS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'requiredPatterns')
    ..pPS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'optionalPatterns')
    ..hasRequiredFields = false
  ;

  ArchiveArtifact._() : super();
  factory ArchiveArtifact({
    ArchiveType? type,
    ArchiveStructure? structure,
    $core.Iterable<$core.String>? requiredPatterns,
    $core.Iterable<$core.String>? optionalPatterns,
  }) {
    final _result = create();
    if (type != null) {
      _result.type = type;
    }
    if (structure != null) {
      _result.structure = structure;
    }
    if (requiredPatterns != null) {
      _result.requiredPatterns.addAll(requiredPatterns);
    }
    if (optionalPatterns != null) {
      _result.optionalPatterns.addAll(optionalPatterns);
    }
    return _result;
  }
  factory ArchiveArtifact.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ArchiveArtifact.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ArchiveArtifact clone() => ArchiveArtifact()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ArchiveArtifact copyWith(void Function(ArchiveArtifact) updates) => super.copyWith((message) => updates(message as ArchiveArtifact)) as ArchiveArtifact; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ArchiveArtifact create() => ArchiveArtifact._();
  ArchiveArtifact createEmptyInstance() => create();
  static $pb.PbList<ArchiveArtifact> createRepeated() => $pb.PbList<ArchiveArtifact>();
  @$core.pragma('dart2js:noInline')
  static ArchiveArtifact getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ArchiveArtifact>(create);
  static ArchiveArtifact? _defaultInstance;

  @$pb.TagNumber(1)
  ArchiveType get type => $_getN(0);
  @$pb.TagNumber(1)
  set type(ArchiveType v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => clearField(1);

  @$pb.TagNumber(2)
  ArchiveStructure get structure => $_getN(1);
  @$pb.TagNumber(2)
  set structure(ArchiveStructure v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasStructure() => $_has(1);
  @$pb.TagNumber(2)
  void clearStructure() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.String> get requiredPatterns => $_getList(2);

  @$pb.TagNumber(4)
  $core.List<$core.String> get optionalPatterns => $_getList(3);
}

class ModelFileDescriptor extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ModelFileDescriptor', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'url')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'filename')
    ..aOB(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'isRequired')
    ..aInt64(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sizeBytes')
    ..aOS(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'checksum')
    ..hasRequiredFields = false
  ;

  ModelFileDescriptor._() : super();
  factory ModelFileDescriptor({
    $core.String? url,
    $core.String? filename,
    $core.bool? isRequired,
    $fixnum.Int64? sizeBytes,
    $core.String? checksum,
  }) {
    final _result = create();
    if (url != null) {
      _result.url = url;
    }
    if (filename != null) {
      _result.filename = filename;
    }
    if (isRequired != null) {
      _result.isRequired = isRequired;
    }
    if (sizeBytes != null) {
      _result.sizeBytes = sizeBytes;
    }
    if (checksum != null) {
      _result.checksum = checksum;
    }
    return _result;
  }
  factory ModelFileDescriptor.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelFileDescriptor.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelFileDescriptor clone() => ModelFileDescriptor()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelFileDescriptor copyWith(void Function(ModelFileDescriptor) updates) => super.copyWith((message) => updates(message as ModelFileDescriptor)) as ModelFileDescriptor; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ModelFileDescriptor create() => ModelFileDescriptor._();
  ModelFileDescriptor createEmptyInstance() => create();
  static $pb.PbList<ModelFileDescriptor> createRepeated() => $pb.PbList<ModelFileDescriptor>();
  @$core.pragma('dart2js:noInline')
  static ModelFileDescriptor getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelFileDescriptor>(create);
  static ModelFileDescriptor? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get url => $_getSZ(0);
  @$pb.TagNumber(1)
  set url($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUrl() => $_has(0);
  @$pb.TagNumber(1)
  void clearUrl() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get filename => $_getSZ(1);
  @$pb.TagNumber(2)
  set filename($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasFilename() => $_has(1);
  @$pb.TagNumber(2)
  void clearFilename() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get isRequired => $_getBF(2);
  @$pb.TagNumber(3)
  set isRequired($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasIsRequired() => $_has(2);
  @$pb.TagNumber(3)
  void clearIsRequired() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get sizeBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set sizeBytes($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSizeBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearSizeBytes() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get checksum => $_getSZ(4);
  @$pb.TagNumber(5)
  set checksum($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasChecksum() => $_has(4);
  @$pb.TagNumber(5)
  void clearChecksum() => clearField(5);
}

class MultiFileArtifact extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'MultiFileArtifact', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pc<ModelFileDescriptor>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'files', $pb.PbFieldType.PM, subBuilder: ModelFileDescriptor.create)
    ..hasRequiredFields = false
  ;

  MultiFileArtifact._() : super();
  factory MultiFileArtifact({
    $core.Iterable<ModelFileDescriptor>? files,
  }) {
    final _result = create();
    if (files != null) {
      _result.files.addAll(files);
    }
    return _result;
  }
  factory MultiFileArtifact.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MultiFileArtifact.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MultiFileArtifact clone() => MultiFileArtifact()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MultiFileArtifact copyWith(void Function(MultiFileArtifact) updates) => super.copyWith((message) => updates(message as MultiFileArtifact)) as MultiFileArtifact; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static MultiFileArtifact create() => MultiFileArtifact._();
  MultiFileArtifact createEmptyInstance() => create();
  static $pb.PbList<MultiFileArtifact> createRepeated() => $pb.PbList<MultiFileArtifact>();
  @$core.pragma('dart2js:noInline')
  static MultiFileArtifact getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MultiFileArtifact>(create);
  static MultiFileArtifact? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<ModelFileDescriptor> get files => $_getList(0);
}

class ExpectedModelFiles extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ExpectedModelFiles', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pc<ModelFileDescriptor>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'files', $pb.PbFieldType.PM, subBuilder: ModelFileDescriptor.create)
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'rootDirectory')
    ..hasRequiredFields = false
  ;

  ExpectedModelFiles._() : super();
  factory ExpectedModelFiles({
    $core.Iterable<ModelFileDescriptor>? files,
    $core.String? rootDirectory,
  }) {
    final _result = create();
    if (files != null) {
      _result.files.addAll(files);
    }
    if (rootDirectory != null) {
      _result.rootDirectory = rootDirectory;
    }
    return _result;
  }
  factory ExpectedModelFiles.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ExpectedModelFiles.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ExpectedModelFiles clone() => ExpectedModelFiles()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ExpectedModelFiles copyWith(void Function(ExpectedModelFiles) updates) => super.copyWith((message) => updates(message as ExpectedModelFiles)) as ExpectedModelFiles; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ExpectedModelFiles create() => ExpectedModelFiles._();
  ExpectedModelFiles createEmptyInstance() => create();
  static $pb.PbList<ExpectedModelFiles> createRepeated() => $pb.PbList<ExpectedModelFiles>();
  @$core.pragma('dart2js:noInline')
  static ExpectedModelFiles getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ExpectedModelFiles>(create);
  static ExpectedModelFiles? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<ModelFileDescriptor> get files => $_getList(0);

  @$pb.TagNumber(2)
  $core.String get rootDirectory => $_getSZ(1);
  @$pb.TagNumber(2)
  set rootDirectory($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasRootDirectory() => $_has(1);
  @$pb.TagNumber(2)
  void clearRootDirectory() => clearField(2);
}

