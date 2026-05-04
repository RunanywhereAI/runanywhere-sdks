//
//  Generated code. Do not modify.
//  source: model_types.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'model_types.pbenum.dart';

export 'model_types.pbenum.dart';

/// Model-level thinking tag metadata. This intentionally uses a model-specific
/// message name because llm_options.proto already owns the generation-options
/// ThinkingTagPattern message in this proto package.
class ModelThinkingTagPattern extends $pb.GeneratedMessage {
  factory ModelThinkingTagPattern({
    $core.String? openTag,
    $core.String? closeTag,
  }) {
    final $result = create();
    if (openTag != null) {
      $result.openTag = openTag;
    }
    if (closeTag != null) {
      $result.closeTag = closeTag;
    }
    return $result;
  }
  ModelThinkingTagPattern._() : super();
  factory ModelThinkingTagPattern.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelThinkingTagPattern.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelThinkingTagPattern', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'openTag')
    ..aOS(2, _omitFieldNames ? '' : 'closeTag')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelThinkingTagPattern clone() => ModelThinkingTagPattern()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelThinkingTagPattern copyWith(void Function(ModelThinkingTagPattern) updates) => super.copyWith((message) => updates(message as ModelThinkingTagPattern)) as ModelThinkingTagPattern;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelThinkingTagPattern create() => ModelThinkingTagPattern._();
  ModelThinkingTagPattern createEmptyInstance() => create();
  static $pb.PbList<ModelThinkingTagPattern> createRepeated() => $pb.PbList<ModelThinkingTagPattern>();
  @$core.pragma('dart2js:noInline')
  static ModelThinkingTagPattern getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelThinkingTagPattern>(create);
  static ModelThinkingTagPattern? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get openTag => $_getSZ(0);
  @$pb.TagNumber(1)
  set openTag($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasOpenTag() => $_has(0);
  @$pb.TagNumber(1)
  void clearOpenTag() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get closeTag => $_getSZ(1);
  @$pb.TagNumber(2)
  set closeTag($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCloseTag() => $_has(1);
  @$pb.TagNumber(2)
  void clearCloseTag() => clearField(2);
}

class ModelInfoMetadata extends $pb.GeneratedMessage {
  factory ModelInfoMetadata({
    $core.String? description,
    $core.String? author,
    $core.String? license,
    $core.Iterable<$core.String>? tags,
    $core.String? version,
  }) {
    final $result = create();
    if (description != null) {
      $result.description = description;
    }
    if (author != null) {
      $result.author = author;
    }
    if (license != null) {
      $result.license = license;
    }
    if (tags != null) {
      $result.tags.addAll(tags);
    }
    if (version != null) {
      $result.version = version;
    }
    return $result;
  }
  ModelInfoMetadata._() : super();
  factory ModelInfoMetadata.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelInfoMetadata.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelInfoMetadata', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'description')
    ..aOS(2, _omitFieldNames ? '' : 'author')
    ..aOS(3, _omitFieldNames ? '' : 'license')
    ..pPS(4, _omitFieldNames ? '' : 'tags')
    ..aOS(5, _omitFieldNames ? '' : 'version')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelInfoMetadata clone() => ModelInfoMetadata()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelInfoMetadata copyWith(void Function(ModelInfoMetadata) updates) => super.copyWith((message) => updates(message as ModelInfoMetadata)) as ModelInfoMetadata;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelInfoMetadata create() => ModelInfoMetadata._();
  ModelInfoMetadata createEmptyInstance() => create();
  static $pb.PbList<ModelInfoMetadata> createRepeated() => $pb.PbList<ModelInfoMetadata>();
  @$core.pragma('dart2js:noInline')
  static ModelInfoMetadata getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelInfoMetadata>(create);
  static ModelInfoMetadata? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get description => $_getSZ(0);
  @$pb.TagNumber(1)
  set description($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDescription() => $_has(0);
  @$pb.TagNumber(1)
  void clearDescription() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get author => $_getSZ(1);
  @$pb.TagNumber(2)
  set author($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAuthor() => $_has(1);
  @$pb.TagNumber(2)
  void clearAuthor() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get license => $_getSZ(2);
  @$pb.TagNumber(3)
  set license($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasLicense() => $_has(2);
  @$pb.TagNumber(3)
  void clearLicense() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.String> get tags => $_getList(3);

  @$pb.TagNumber(5)
  $core.String get version => $_getSZ(4);
  @$pb.TagNumber(5)
  set version($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasVersion() => $_has(4);
  @$pb.TagNumber(5)
  void clearVersion() => clearField(5);
}

class ModelRuntimeCompatibility extends $pb.GeneratedMessage {
  factory ModelRuntimeCompatibility({
    $core.Iterable<InferenceFramework>? compatibleFrameworks,
    $core.Iterable<ModelFormat>? compatibleFormats,
  }) {
    final $result = create();
    if (compatibleFrameworks != null) {
      $result.compatibleFrameworks.addAll(compatibleFrameworks);
    }
    if (compatibleFormats != null) {
      $result.compatibleFormats.addAll(compatibleFormats);
    }
    return $result;
  }
  ModelRuntimeCompatibility._() : super();
  factory ModelRuntimeCompatibility.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelRuntimeCompatibility.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelRuntimeCompatibility', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pc<InferenceFramework>(1, _omitFieldNames ? '' : 'compatibleFrameworks', $pb.PbFieldType.KE, valueOf: InferenceFramework.valueOf, enumValues: InferenceFramework.values, defaultEnumValue: InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED)
    ..pc<ModelFormat>(2, _omitFieldNames ? '' : 'compatibleFormats', $pb.PbFieldType.KE, valueOf: ModelFormat.valueOf, enumValues: ModelFormat.values, defaultEnumValue: ModelFormat.MODEL_FORMAT_UNSPECIFIED)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelRuntimeCompatibility clone() => ModelRuntimeCompatibility()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelRuntimeCompatibility copyWith(void Function(ModelRuntimeCompatibility) updates) => super.copyWith((message) => updates(message as ModelRuntimeCompatibility)) as ModelRuntimeCompatibility;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelRuntimeCompatibility create() => ModelRuntimeCompatibility._();
  ModelRuntimeCompatibility createEmptyInstance() => create();
  static $pb.PbList<ModelRuntimeCompatibility> createRepeated() => $pb.PbList<ModelRuntimeCompatibility>();
  @$core.pragma('dart2js:noInline')
  static ModelRuntimeCompatibility getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelRuntimeCompatibility>(create);
  static ModelRuntimeCompatibility? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<InferenceFramework> get compatibleFrameworks => $_getList(0);

  @$pb.TagNumber(2)
  $core.List<ModelFormat> get compatibleFormats => $_getList(1);
}

enum ModelInfo_Artifact {
  singleFile, 
  archive, 
  multiFile, 
  customStrategyId, 
  builtIn, 
  notSet
}

/// ---------------------------------------------------------------------------
/// Core metadata for a model entry.
/// Sources pre-IDL:
///   Swift  ModelTypes.swift:393       (16 fields)
///   Kotlin ModelTypes.kt:332          (16 fields, Long vs Int drift on download size)
///   Dart   model_types.dart:335       (similar shape, nullable divergences)
///   RN     HybridRunAnywhereCore.cpp:995-1010 (13 fields, string-typed category/format)
/// ---------------------------------------------------------------------------
class ModelInfo extends $pb.GeneratedMessage {
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
    $fixnum.Int64? memoryRequiredBytes,
    $core.String? checksumSha256,
    ModelThinkingTagPattern? thinkingPattern,
    ModelInfoMetadata? metadata,
    SingleFileArtifact? singleFile,
    ArchiveArtifact? archive,
    MultiFileArtifact? multiFile,
    $core.String? customStrategyId,
    $core.bool? builtIn,
    ModelArtifactType? artifactType,
    ExpectedModelFiles? expectedFiles,
    AccelerationPreference? accelerationPreference,
    RoutingPolicy? routingPolicy,
    ModelRuntimeCompatibility? compatibility,
    InferenceFramework? preferredFramework,
    ModelRegistryStatus? registryStatus,
    $core.bool? isDownloaded,
    $core.bool? isAvailable,
    $fixnum.Int64? lastUsedAtUnixMs,
    $core.int? usageCount,
    $core.bool? syncPending,
    $core.String? statusMessage,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (name != null) {
      $result.name = name;
    }
    if (category != null) {
      $result.category = category;
    }
    if (format != null) {
      $result.format = format;
    }
    if (framework != null) {
      $result.framework = framework;
    }
    if (downloadUrl != null) {
      $result.downloadUrl = downloadUrl;
    }
    if (localPath != null) {
      $result.localPath = localPath;
    }
    if (downloadSizeBytes != null) {
      $result.downloadSizeBytes = downloadSizeBytes;
    }
    if (contextLength != null) {
      $result.contextLength = contextLength;
    }
    if (supportsThinking != null) {
      $result.supportsThinking = supportsThinking;
    }
    if (supportsLora != null) {
      $result.supportsLora = supportsLora;
    }
    if (description != null) {
      $result.description = description;
    }
    if (source != null) {
      $result.source = source;
    }
    if (createdAtUnixMs != null) {
      $result.createdAtUnixMs = createdAtUnixMs;
    }
    if (updatedAtUnixMs != null) {
      $result.updatedAtUnixMs = updatedAtUnixMs;
    }
    if (memoryRequiredBytes != null) {
      $result.memoryRequiredBytes = memoryRequiredBytes;
    }
    if (checksumSha256 != null) {
      $result.checksumSha256 = checksumSha256;
    }
    if (thinkingPattern != null) {
      $result.thinkingPattern = thinkingPattern;
    }
    if (metadata != null) {
      $result.metadata = metadata;
    }
    if (singleFile != null) {
      $result.singleFile = singleFile;
    }
    if (archive != null) {
      $result.archive = archive;
    }
    if (multiFile != null) {
      $result.multiFile = multiFile;
    }
    if (customStrategyId != null) {
      $result.customStrategyId = customStrategyId;
    }
    if (builtIn != null) {
      $result.builtIn = builtIn;
    }
    if (artifactType != null) {
      $result.artifactType = artifactType;
    }
    if (expectedFiles != null) {
      $result.expectedFiles = expectedFiles;
    }
    if (accelerationPreference != null) {
      $result.accelerationPreference = accelerationPreference;
    }
    if (routingPolicy != null) {
      $result.routingPolicy = routingPolicy;
    }
    if (compatibility != null) {
      $result.compatibility = compatibility;
    }
    if (preferredFramework != null) {
      $result.preferredFramework = preferredFramework;
    }
    if (registryStatus != null) {
      $result.registryStatus = registryStatus;
    }
    if (isDownloaded != null) {
      $result.isDownloaded = isDownloaded;
    }
    if (isAvailable != null) {
      $result.isAvailable = isAvailable;
    }
    if (lastUsedAtUnixMs != null) {
      $result.lastUsedAtUnixMs = lastUsedAtUnixMs;
    }
    if (usageCount != null) {
      $result.usageCount = usageCount;
    }
    if (syncPending != null) {
      $result.syncPending = syncPending;
    }
    if (statusMessage != null) {
      $result.statusMessage = statusMessage;
    }
    return $result;
  }
  ModelInfo._() : super();
  factory ModelInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, ModelInfo_Artifact> _ModelInfo_ArtifactByTag = {
    20 : ModelInfo_Artifact.singleFile,
    21 : ModelInfo_Artifact.archive,
    22 : ModelInfo_Artifact.multiFile,
    23 : ModelInfo_Artifact.customStrategyId,
    24 : ModelInfo_Artifact.builtIn,
    0 : ModelInfo_Artifact.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..oo(0, [20, 21, 22, 23, 24])
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..e<ModelCategory>(3, _omitFieldNames ? '' : 'category', $pb.PbFieldType.OE, defaultOrMaker: ModelCategory.MODEL_CATEGORY_UNSPECIFIED, valueOf: ModelCategory.valueOf, enumValues: ModelCategory.values)
    ..e<ModelFormat>(4, _omitFieldNames ? '' : 'format', $pb.PbFieldType.OE, defaultOrMaker: ModelFormat.MODEL_FORMAT_UNSPECIFIED, valueOf: ModelFormat.valueOf, enumValues: ModelFormat.values)
    ..e<InferenceFramework>(5, _omitFieldNames ? '' : 'framework', $pb.PbFieldType.OE, defaultOrMaker: InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED, valueOf: InferenceFramework.valueOf, enumValues: InferenceFramework.values)
    ..aOS(6, _omitFieldNames ? '' : 'downloadUrl')
    ..aOS(7, _omitFieldNames ? '' : 'localPath')
    ..aInt64(8, _omitFieldNames ? '' : 'downloadSizeBytes')
    ..a<$core.int>(9, _omitFieldNames ? '' : 'contextLength', $pb.PbFieldType.O3)
    ..aOB(10, _omitFieldNames ? '' : 'supportsThinking')
    ..aOB(11, _omitFieldNames ? '' : 'supportsLora')
    ..aOS(12, _omitFieldNames ? '' : 'description')
    ..e<ModelSource>(13, _omitFieldNames ? '' : 'source', $pb.PbFieldType.OE, defaultOrMaker: ModelSource.MODEL_SOURCE_UNSPECIFIED, valueOf: ModelSource.valueOf, enumValues: ModelSource.values)
    ..aInt64(14, _omitFieldNames ? '' : 'createdAtUnixMs')
    ..aInt64(15, _omitFieldNames ? '' : 'updatedAtUnixMs')
    ..aInt64(16, _omitFieldNames ? '' : 'memoryRequiredBytes')
    ..aOS(17, _omitFieldNames ? '' : 'checksumSha256')
    ..aOM<ModelThinkingTagPattern>(18, _omitFieldNames ? '' : 'thinkingPattern', subBuilder: ModelThinkingTagPattern.create)
    ..aOM<ModelInfoMetadata>(19, _omitFieldNames ? '' : 'metadata', subBuilder: ModelInfoMetadata.create)
    ..aOM<SingleFileArtifact>(20, _omitFieldNames ? '' : 'singleFile', subBuilder: SingleFileArtifact.create)
    ..aOM<ArchiveArtifact>(21, _omitFieldNames ? '' : 'archive', subBuilder: ArchiveArtifact.create)
    ..aOM<MultiFileArtifact>(22, _omitFieldNames ? '' : 'multiFile', subBuilder: MultiFileArtifact.create)
    ..aOS(23, _omitFieldNames ? '' : 'customStrategyId')
    ..aOB(24, _omitFieldNames ? '' : 'builtIn')
    ..e<ModelArtifactType>(25, _omitFieldNames ? '' : 'artifactType', $pb.PbFieldType.OE, defaultOrMaker: ModelArtifactType.MODEL_ARTIFACT_TYPE_UNSPECIFIED, valueOf: ModelArtifactType.valueOf, enumValues: ModelArtifactType.values)
    ..aOM<ExpectedModelFiles>(26, _omitFieldNames ? '' : 'expectedFiles', subBuilder: ExpectedModelFiles.create)
    ..e<AccelerationPreference>(27, _omitFieldNames ? '' : 'accelerationPreference', $pb.PbFieldType.OE, defaultOrMaker: AccelerationPreference.ACCELERATION_PREFERENCE_UNSPECIFIED, valueOf: AccelerationPreference.valueOf, enumValues: AccelerationPreference.values)
    ..e<RoutingPolicy>(28, _omitFieldNames ? '' : 'routingPolicy', $pb.PbFieldType.OE, defaultOrMaker: RoutingPolicy.ROUTING_POLICY_UNSPECIFIED, valueOf: RoutingPolicy.valueOf, enumValues: RoutingPolicy.values)
    ..aOM<ModelRuntimeCompatibility>(29, _omitFieldNames ? '' : 'compatibility', subBuilder: ModelRuntimeCompatibility.create)
    ..e<InferenceFramework>(30, _omitFieldNames ? '' : 'preferredFramework', $pb.PbFieldType.OE, defaultOrMaker: InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED, valueOf: InferenceFramework.valueOf, enumValues: InferenceFramework.values)
    ..e<ModelRegistryStatus>(31, _omitFieldNames ? '' : 'registryStatus', $pb.PbFieldType.OE, defaultOrMaker: ModelRegistryStatus.MODEL_REGISTRY_STATUS_UNSPECIFIED, valueOf: ModelRegistryStatus.valueOf, enumValues: ModelRegistryStatus.values)
    ..aOB(32, _omitFieldNames ? '' : 'isDownloaded')
    ..aOB(33, _omitFieldNames ? '' : 'isAvailable')
    ..aInt64(34, _omitFieldNames ? '' : 'lastUsedAtUnixMs')
    ..a<$core.int>(35, _omitFieldNames ? '' : 'usageCount', $pb.PbFieldType.O3)
    ..aOB(36, _omitFieldNames ? '' : 'syncPending')
    ..aOS(37, _omitFieldNames ? '' : 'statusMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelInfo clone() => ModelInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelInfo copyWith(void Function(ModelInfo) updates) => super.copyWith((message) => updates(message as ModelInfo)) as ModelInfo;

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

  /// Separate from download_size_bytes: this is the estimated runtime RAM
  /// requirement used by compatibility checks and model selection UIs.
  @$pb.TagNumber(16)
  $fixnum.Int64 get memoryRequiredBytes => $_getI64(15);
  @$pb.TagNumber(16)
  set memoryRequiredBytes($fixnum.Int64 v) { $_setInt64(15, v); }
  @$pb.TagNumber(16)
  $core.bool hasMemoryRequiredBytes() => $_has(15);
  @$pb.TagNumber(16)
  void clearMemoryRequiredBytes() => clearField(16);

  /// Lowercase hex SHA-256 checksum for the primary artifact. Per-file
  /// checksums for multi-file artifacts live on ModelFileDescriptor.
  @$pb.TagNumber(17)
  $core.String get checksumSha256 => $_getSZ(16);
  @$pb.TagNumber(17)
  set checksumSha256($core.String v) { $_setString(16, v); }
  @$pb.TagNumber(17)
  $core.bool hasChecksumSha256() => $_has(16);
  @$pb.TagNumber(17)
  void clearChecksumSha256() => clearField(17);

  /// Thinking/reasoning metadata. `supports_thinking` remains the boolean
  /// capability flag; this optional pattern declares model-specific tags.
  @$pb.TagNumber(18)
  ModelThinkingTagPattern get thinkingPattern => $_getN(17);
  @$pb.TagNumber(18)
  set thinkingPattern(ModelThinkingTagPattern v) { setField(18, v); }
  @$pb.TagNumber(18)
  $core.bool hasThinkingPattern() => $_has(17);
  @$pb.TagNumber(18)
  void clearThinkingPattern() => clearField(18);
  @$pb.TagNumber(18)
  ModelThinkingTagPattern ensureThinkingPattern() => $_ensure(17);

  /// Structured public catalog metadata. `description` (field 12) is kept for
  /// backward compatibility and should mirror metadata.description when both
  /// are populated.
  @$pb.TagNumber(19)
  ModelInfoMetadata get metadata => $_getN(18);
  @$pb.TagNumber(19)
  set metadata(ModelInfoMetadata v) { setField(19, v); }
  @$pb.TagNumber(19)
  $core.bool hasMetadata() => $_has(18);
  @$pb.TagNumber(19)
  void clearMetadata() => clearField(19);
  @$pb.TagNumber(19)
  ModelInfoMetadata ensureMetadata() => $_ensure(18);

  @$pb.TagNumber(20)
  SingleFileArtifact get singleFile => $_getN(19);
  @$pb.TagNumber(20)
  set singleFile(SingleFileArtifact v) { setField(20, v); }
  @$pb.TagNumber(20)
  $core.bool hasSingleFile() => $_has(19);
  @$pb.TagNumber(20)
  void clearSingleFile() => clearField(20);
  @$pb.TagNumber(20)
  SingleFileArtifact ensureSingleFile() => $_ensure(19);

  @$pb.TagNumber(21)
  ArchiveArtifact get archive => $_getN(20);
  @$pb.TagNumber(21)
  set archive(ArchiveArtifact v) { setField(21, v); }
  @$pb.TagNumber(21)
  $core.bool hasArchive() => $_has(20);
  @$pb.TagNumber(21)
  void clearArchive() => clearField(21);
  @$pb.TagNumber(21)
  ArchiveArtifact ensureArchive() => $_ensure(20);

  @$pb.TagNumber(22)
  MultiFileArtifact get multiFile => $_getN(21);
  @$pb.TagNumber(22)
  set multiFile(MultiFileArtifact v) { setField(22, v); }
  @$pb.TagNumber(22)
  $core.bool hasMultiFile() => $_has(21);
  @$pb.TagNumber(22)
  void clearMultiFile() => clearField(22);
  @$pb.TagNumber(22)
  MultiFileArtifact ensureMultiFile() => $_ensure(21);

  @$pb.TagNumber(23)
  $core.String get customStrategyId => $_getSZ(22);
  @$pb.TagNumber(23)
  set customStrategyId($core.String v) { $_setString(22, v); }
  @$pb.TagNumber(23)
  $core.bool hasCustomStrategyId() => $_has(22);
  @$pb.TagNumber(23)
  void clearCustomStrategyId() => clearField(23);

  @$pb.TagNumber(24)
  $core.bool get builtIn => $_getBF(23);
  @$pb.TagNumber(24)
  set builtIn($core.bool v) { $_setBool(23, v); }
  @$pb.TagNumber(24)
  $core.bool hasBuiltIn() => $_has(23);
  @$pb.TagNumber(24)
  void clearBuiltIn() => clearField(24);

  /// High-level artifact classification, complementary to the `artifact`
  /// oneof above. Allows catalog entries to carry a coarse type tag without
  /// resolving the full strategy variant.
  @$pb.TagNumber(25)
  ModelArtifactType get artifactType => $_getN(24);
  @$pb.TagNumber(25)
  set artifactType(ModelArtifactType v) { setField(25, v); }
  @$pb.TagNumber(25)
  $core.bool hasArtifactType() => $_has(24);
  @$pb.TagNumber(25)
  void clearArtifactType() => clearField(25);

  /// Manifest of files that are expected on disk after fetch/extraction.
  @$pb.TagNumber(26)
  ExpectedModelFiles get expectedFiles => $_getN(25);
  @$pb.TagNumber(26)
  set expectedFiles(ExpectedModelFiles v) { setField(26, v); }
  @$pb.TagNumber(26)
  $core.bool hasExpectedFiles() => $_has(25);
  @$pb.TagNumber(26)
  void clearExpectedFiles() => clearField(26);
  @$pb.TagNumber(26)
  ExpectedModelFiles ensureExpectedFiles() => $_ensure(25);

  /// Preferred hardware acceleration backend for this model.
  @$pb.TagNumber(27)
  AccelerationPreference get accelerationPreference => $_getN(26);
  @$pb.TagNumber(27)
  set accelerationPreference(AccelerationPreference v) { setField(27, v); }
  @$pb.TagNumber(27)
  $core.bool hasAccelerationPreference() => $_has(26);
  @$pb.TagNumber(27)
  void clearAccelerationPreference() => clearField(27);

  /// Hybrid (on-device vs cloud) routing policy for this entry.
  @$pb.TagNumber(28)
  RoutingPolicy get routingPolicy => $_getN(27);
  @$pb.TagNumber(28)
  set routingPolicy(RoutingPolicy v) { setField(28, v); }
  @$pb.TagNumber(28)
  $core.bool hasRoutingPolicy() => $_has(27);
  @$pb.TagNumber(28)
  void clearRoutingPolicy() => clearField(28);

  /// Framework/format compatibility declarations. `framework` (field 5) is
  /// the canonical/preferred runtime when no explicit preferred_framework is set.
  @$pb.TagNumber(29)
  ModelRuntimeCompatibility get compatibility => $_getN(28);
  @$pb.TagNumber(29)
  set compatibility(ModelRuntimeCompatibility v) { setField(29, v); }
  @$pb.TagNumber(29)
  $core.bool hasCompatibility() => $_has(28);
  @$pb.TagNumber(29)
  void clearCompatibility() => clearField(29);
  @$pb.TagNumber(29)
  ModelRuntimeCompatibility ensureCompatibility() => $_ensure(28);

  @$pb.TagNumber(30)
  InferenceFramework get preferredFramework => $_getN(29);
  @$pb.TagNumber(30)
  set preferredFramework(InferenceFramework v) { setField(30, v); }
  @$pb.TagNumber(30)
  $core.bool hasPreferredFramework() => $_has(29);
  @$pb.TagNumber(30)
  void clearPreferredFramework() => clearField(30);

  /// Durable registry state. Live byte progress belongs to
  /// download_service.DownloadProgress, not ModelInfo.
  @$pb.TagNumber(31)
  ModelRegistryStatus get registryStatus => $_getN(30);
  @$pb.TagNumber(31)
  set registryStatus(ModelRegistryStatus v) { setField(31, v); }
  @$pb.TagNumber(31)
  $core.bool hasRegistryStatus() => $_has(30);
  @$pb.TagNumber(31)
  void clearRegistryStatus() => clearField(31);

  @$pb.TagNumber(32)
  $core.bool get isDownloaded => $_getBF(31);
  @$pb.TagNumber(32)
  set isDownloaded($core.bool v) { $_setBool(31, v); }
  @$pb.TagNumber(32)
  $core.bool hasIsDownloaded() => $_has(31);
  @$pb.TagNumber(32)
  void clearIsDownloaded() => clearField(32);

  @$pb.TagNumber(33)
  $core.bool get isAvailable => $_getBF(32);
  @$pb.TagNumber(33)
  set isAvailable($core.bool v) { $_setBool(32, v); }
  @$pb.TagNumber(33)
  $core.bool hasIsAvailable() => $_has(32);
  @$pb.TagNumber(33)
  void clearIsAvailable() => clearField(33);

  @$pb.TagNumber(34)
  $fixnum.Int64 get lastUsedAtUnixMs => $_getI64(33);
  @$pb.TagNumber(34)
  set lastUsedAtUnixMs($fixnum.Int64 v) { $_setInt64(33, v); }
  @$pb.TagNumber(34)
  $core.bool hasLastUsedAtUnixMs() => $_has(33);
  @$pb.TagNumber(34)
  void clearLastUsedAtUnixMs() => clearField(34);

  @$pb.TagNumber(35)
  $core.int get usageCount => $_getIZ(34);
  @$pb.TagNumber(35)
  set usageCount($core.int v) { $_setSignedInt32(34, v); }
  @$pb.TagNumber(35)
  $core.bool hasUsageCount() => $_has(34);
  @$pb.TagNumber(35)
  void clearUsageCount() => clearField(35);

  @$pb.TagNumber(36)
  $core.bool get syncPending => $_getBF(35);
  @$pb.TagNumber(36)
  set syncPending($core.bool v) { $_setBool(35, v); }
  @$pb.TagNumber(36)
  $core.bool hasSyncPending() => $_has(35);
  @$pb.TagNumber(36)
  void clearSyncPending() => clearField(36);

  @$pb.TagNumber(37)
  $core.String get statusMessage => $_getSZ(36);
  @$pb.TagNumber(37)
  set statusMessage($core.String v) { $_setString(36, v); }
  @$pb.TagNumber(37)
  $core.bool hasStatusMessage() => $_has(36);
  @$pb.TagNumber(37)
  void clearStatusMessage() => clearField(37);
}

/// Repeated model registry responses use this wrapper because protobuf cannot
/// serialize a bare repeated field as a top-level message.
class ModelInfoList extends $pb.GeneratedMessage {
  factory ModelInfoList({
    $core.Iterable<ModelInfo>? models,
  }) {
    final $result = create();
    if (models != null) {
      $result.models.addAll(models);
    }
    return $result;
  }
  ModelInfoList._() : super();
  factory ModelInfoList.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelInfoList.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelInfoList', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pc<ModelInfo>(1, _omitFieldNames ? '' : 'models', $pb.PbFieldType.PM, subBuilder: ModelInfo.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelInfoList clone() => ModelInfoList()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelInfoList copyWith(void Function(ModelInfoList) updates) => super.copyWith((message) => updates(message as ModelInfoList)) as ModelInfoList;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelInfoList create() => ModelInfoList._();
  ModelInfoList createEmptyInstance() => create();
  static $pb.PbList<ModelInfoList> createRepeated() => $pb.PbList<ModelInfoList>();
  @$core.pragma('dart2js:noInline')
  static ModelInfoList getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelInfoList>(create);
  static ModelInfoList? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<ModelInfo> get models => $_getList(0);
}

class SingleFileArtifact extends $pb.GeneratedMessage {
  factory SingleFileArtifact({
    $core.Iterable<$core.String>? requiredPatterns,
    $core.Iterable<$core.String>? optionalPatterns,
  }) {
    final $result = create();
    if (requiredPatterns != null) {
      $result.requiredPatterns.addAll(requiredPatterns);
    }
    if (optionalPatterns != null) {
      $result.optionalPatterns.addAll(optionalPatterns);
    }
    return $result;
  }
  SingleFileArtifact._() : super();
  factory SingleFileArtifact.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SingleFileArtifact.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SingleFileArtifact', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'requiredPatterns')
    ..pPS(2, _omitFieldNames ? '' : 'optionalPatterns')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SingleFileArtifact clone() => SingleFileArtifact()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SingleFileArtifact copyWith(void Function(SingleFileArtifact) updates) => super.copyWith((message) => updates(message as SingleFileArtifact)) as SingleFileArtifact;

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
  factory ArchiveArtifact({
    ArchiveType? type,
    ArchiveStructure? structure,
    $core.Iterable<$core.String>? requiredPatterns,
    $core.Iterable<$core.String>? optionalPatterns,
  }) {
    final $result = create();
    if (type != null) {
      $result.type = type;
    }
    if (structure != null) {
      $result.structure = structure;
    }
    if (requiredPatterns != null) {
      $result.requiredPatterns.addAll(requiredPatterns);
    }
    if (optionalPatterns != null) {
      $result.optionalPatterns.addAll(optionalPatterns);
    }
    return $result;
  }
  ArchiveArtifact._() : super();
  factory ArchiveArtifact.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ArchiveArtifact.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ArchiveArtifact', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<ArchiveType>(1, _omitFieldNames ? '' : 'type', $pb.PbFieldType.OE, defaultOrMaker: ArchiveType.ARCHIVE_TYPE_UNSPECIFIED, valueOf: ArchiveType.valueOf, enumValues: ArchiveType.values)
    ..e<ArchiveStructure>(2, _omitFieldNames ? '' : 'structure', $pb.PbFieldType.OE, defaultOrMaker: ArchiveStructure.ARCHIVE_STRUCTURE_UNSPECIFIED, valueOf: ArchiveStructure.valueOf, enumValues: ArchiveStructure.values)
    ..pPS(3, _omitFieldNames ? '' : 'requiredPatterns')
    ..pPS(4, _omitFieldNames ? '' : 'optionalPatterns')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ArchiveArtifact clone() => ArchiveArtifact()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ArchiveArtifact copyWith(void Function(ArchiveArtifact) updates) => super.copyWith((message) => updates(message as ArchiveArtifact)) as ArchiveArtifact;

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
  factory ModelFileDescriptor({
    $core.String? url,
    $core.String? filename,
    $core.bool? isRequired,
    $fixnum.Int64? sizeBytes,
    $core.String? checksum,
    $core.String? relativePath,
    $core.String? destinationPath,
    ModelFileRole? role,
    $core.String? localPath,
  }) {
    final $result = create();
    if (url != null) {
      $result.url = url;
    }
    if (filename != null) {
      $result.filename = filename;
    }
    if (isRequired != null) {
      $result.isRequired = isRequired;
    }
    if (sizeBytes != null) {
      $result.sizeBytes = sizeBytes;
    }
    if (checksum != null) {
      $result.checksum = checksum;
    }
    if (relativePath != null) {
      $result.relativePath = relativePath;
    }
    if (destinationPath != null) {
      $result.destinationPath = destinationPath;
    }
    if (role != null) {
      $result.role = role;
    }
    if (localPath != null) {
      $result.localPath = localPath;
    }
    return $result;
  }
  ModelFileDescriptor._() : super();
  factory ModelFileDescriptor.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelFileDescriptor.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelFileDescriptor', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'url')
    ..aOS(2, _omitFieldNames ? '' : 'filename')
    ..aOB(3, _omitFieldNames ? '' : 'isRequired')
    ..aInt64(4, _omitFieldNames ? '' : 'sizeBytes')
    ..aOS(5, _omitFieldNames ? '' : 'checksum')
    ..aOS(6, _omitFieldNames ? '' : 'relativePath')
    ..aOS(7, _omitFieldNames ? '' : 'destinationPath')
    ..e<ModelFileRole>(8, _omitFieldNames ? '' : 'role', $pb.PbFieldType.OE, defaultOrMaker: ModelFileRole.MODEL_FILE_ROLE_UNSPECIFIED, valueOf: ModelFileRole.valueOf, enumValues: ModelFileRole.values)
    ..aOS(9, _omitFieldNames ? '' : 'localPath')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelFileDescriptor clone() => ModelFileDescriptor()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelFileDescriptor copyWith(void Function(ModelFileDescriptor) updates) => super.copyWith((message) => updates(message as ModelFileDescriptor)) as ModelFileDescriptor;

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

  /// Extended descriptor fields (Flutter model_types.dart:~350,
  /// Swift ModelTypes.swift:~350). `is_required` (field 3) remains the
  /// canonical "required" flag — the documented `required` boolean from
  /// newer SDK sources maps onto it (default true, mirrored in Swift).
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

  /// Path fields used by SDK-local wrappers/catalogs. `filename` is the
  /// storage name for simple cases; relative_path/destination_path preserve
  /// directory layouts for archive and multi-file artifacts.
  @$pb.TagNumber(6)
  $core.String get relativePath => $_getSZ(5);
  @$pb.TagNumber(6)
  set relativePath($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasRelativePath() => $_has(5);
  @$pb.TagNumber(6)
  void clearRelativePath() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get destinationPath => $_getSZ(6);
  @$pb.TagNumber(7)
  set destinationPath($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasDestinationPath() => $_has(6);
  @$pb.TagNumber(7)
  void clearDestinationPath() => clearField(7);

  @$pb.TagNumber(8)
  ModelFileRole get role => $_getN(7);
  @$pb.TagNumber(8)
  set role(ModelFileRole v) { setField(8, v); }
  @$pb.TagNumber(8)
  $core.bool hasRole() => $_has(7);
  @$pb.TagNumber(8)
  void clearRole() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get localPath => $_getSZ(8);
  @$pb.TagNumber(9)
  set localPath($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasLocalPath() => $_has(8);
  @$pb.TagNumber(9)
  void clearLocalPath() => clearField(9);
}

class MultiFileArtifact extends $pb.GeneratedMessage {
  factory MultiFileArtifact({
    $core.Iterable<ModelFileDescriptor>? files,
  }) {
    final $result = create();
    if (files != null) {
      $result.files.addAll(files);
    }
    return $result;
  }
  MultiFileArtifact._() : super();
  factory MultiFileArtifact.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MultiFileArtifact.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MultiFileArtifact', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pc<ModelFileDescriptor>(1, _omitFieldNames ? '' : 'files', $pb.PbFieldType.PM, subBuilder: ModelFileDescriptor.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MultiFileArtifact clone() => MultiFileArtifact()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MultiFileArtifact copyWith(void Function(MultiFileArtifact) updates) => super.copyWith((message) => updates(message as MultiFileArtifact)) as MultiFileArtifact;

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

/// ---------------------------------------------------------------------------
/// Declarative manifest of files a multi-file / directory model is expected
/// to contain on disk after download/extraction. Used for verification before
/// hand-off to the inference framework. Sources pre-IDL:
///   Flutter core/types/model_types.dart:420
///   Swift   ModelTypes.swift:~300
/// ---------------------------------------------------------------------------
class ExpectedModelFiles extends $pb.GeneratedMessage {
  factory ExpectedModelFiles({
    $core.Iterable<ModelFileDescriptor>? files,
    $core.String? rootDirectory,
    $core.Iterable<$core.String>? requiredPatterns,
    $core.Iterable<$core.String>? optionalPatterns,
    $core.String? description,
  }) {
    final $result = create();
    if (files != null) {
      $result.files.addAll(files);
    }
    if (rootDirectory != null) {
      $result.rootDirectory = rootDirectory;
    }
    if (requiredPatterns != null) {
      $result.requiredPatterns.addAll(requiredPatterns);
    }
    if (optionalPatterns != null) {
      $result.optionalPatterns.addAll(optionalPatterns);
    }
    if (description != null) {
      $result.description = description;
    }
    return $result;
  }
  ExpectedModelFiles._() : super();
  factory ExpectedModelFiles.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ExpectedModelFiles.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ExpectedModelFiles', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pc<ModelFileDescriptor>(1, _omitFieldNames ? '' : 'files', $pb.PbFieldType.PM, subBuilder: ModelFileDescriptor.create)
    ..aOS(2, _omitFieldNames ? '' : 'rootDirectory')
    ..pPS(3, _omitFieldNames ? '' : 'requiredPatterns')
    ..pPS(4, _omitFieldNames ? '' : 'optionalPatterns')
    ..aOS(5, _omitFieldNames ? '' : 'description')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ExpectedModelFiles clone() => ExpectedModelFiles()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ExpectedModelFiles copyWith(void Function(ExpectedModelFiles) updates) => super.copyWith((message) => updates(message as ExpectedModelFiles)) as ExpectedModelFiles;

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

  @$pb.TagNumber(3)
  $core.List<$core.String> get requiredPatterns => $_getList(2);

  @$pb.TagNumber(4)
  $core.List<$core.String> get optionalPatterns => $_getList(3);

  @$pb.TagNumber(5)
  $core.String get description => $_getSZ(4);
  @$pb.TagNumber(5)
  set description($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasDescription() => $_has(4);
  @$pb.TagNumber(5)
  void clearDescription() => clearField(5);
}

/// Registry/query filters shared by SDK model-management APIs. UI-only
/// presentation state and platform filesystem handles are intentionally not
/// represented here.
class ModelQuery extends $pb.GeneratedMessage {
  factory ModelQuery({
    InferenceFramework? framework,
    ModelCategory? category,
    ModelFormat? format,
    $core.bool? downloadedOnly,
    $core.bool? availableOnly,
    $fixnum.Int64? maxSizeBytes,
    $core.String? searchQuery,
    ModelSource? source,
    ModelQuerySortField? sortField,
    ModelQuerySortOrder? sortOrder,
  }) {
    final $result = create();
    if (framework != null) {
      $result.framework = framework;
    }
    if (category != null) {
      $result.category = category;
    }
    if (format != null) {
      $result.format = format;
    }
    if (downloadedOnly != null) {
      $result.downloadedOnly = downloadedOnly;
    }
    if (availableOnly != null) {
      $result.availableOnly = availableOnly;
    }
    if (maxSizeBytes != null) {
      $result.maxSizeBytes = maxSizeBytes;
    }
    if (searchQuery != null) {
      $result.searchQuery = searchQuery;
    }
    if (source != null) {
      $result.source = source;
    }
    if (sortField != null) {
      $result.sortField = sortField;
    }
    if (sortOrder != null) {
      $result.sortOrder = sortOrder;
    }
    return $result;
  }
  ModelQuery._() : super();
  factory ModelQuery.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelQuery.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelQuery', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<InferenceFramework>(1, _omitFieldNames ? '' : 'framework', $pb.PbFieldType.OE, defaultOrMaker: InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED, valueOf: InferenceFramework.valueOf, enumValues: InferenceFramework.values)
    ..e<ModelCategory>(2, _omitFieldNames ? '' : 'category', $pb.PbFieldType.OE, defaultOrMaker: ModelCategory.MODEL_CATEGORY_UNSPECIFIED, valueOf: ModelCategory.valueOf, enumValues: ModelCategory.values)
    ..e<ModelFormat>(3, _omitFieldNames ? '' : 'format', $pb.PbFieldType.OE, defaultOrMaker: ModelFormat.MODEL_FORMAT_UNSPECIFIED, valueOf: ModelFormat.valueOf, enumValues: ModelFormat.values)
    ..aOB(4, _omitFieldNames ? '' : 'downloadedOnly')
    ..aOB(5, _omitFieldNames ? '' : 'availableOnly')
    ..aInt64(6, _omitFieldNames ? '' : 'maxSizeBytes')
    ..aOS(7, _omitFieldNames ? '' : 'searchQuery')
    ..e<ModelSource>(8, _omitFieldNames ? '' : 'source', $pb.PbFieldType.OE, defaultOrMaker: ModelSource.MODEL_SOURCE_UNSPECIFIED, valueOf: ModelSource.valueOf, enumValues: ModelSource.values)
    ..e<ModelQuerySortField>(9, _omitFieldNames ? '' : 'sortField', $pb.PbFieldType.OE, defaultOrMaker: ModelQuerySortField.MODEL_QUERY_SORT_FIELD_UNSPECIFIED, valueOf: ModelQuerySortField.valueOf, enumValues: ModelQuerySortField.values)
    ..e<ModelQuerySortOrder>(10, _omitFieldNames ? '' : 'sortOrder', $pb.PbFieldType.OE, defaultOrMaker: ModelQuerySortOrder.MODEL_QUERY_SORT_ORDER_UNSPECIFIED, valueOf: ModelQuerySortOrder.valueOf, enumValues: ModelQuerySortOrder.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelQuery clone() => ModelQuery()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelQuery copyWith(void Function(ModelQuery) updates) => super.copyWith((message) => updates(message as ModelQuery)) as ModelQuery;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelQuery create() => ModelQuery._();
  ModelQuery createEmptyInstance() => create();
  static $pb.PbList<ModelQuery> createRepeated() => $pb.PbList<ModelQuery>();
  @$core.pragma('dart2js:noInline')
  static ModelQuery getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelQuery>(create);
  static ModelQuery? _defaultInstance;

  @$pb.TagNumber(1)
  InferenceFramework get framework => $_getN(0);
  @$pb.TagNumber(1)
  set framework(InferenceFramework v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasFramework() => $_has(0);
  @$pb.TagNumber(1)
  void clearFramework() => clearField(1);

  @$pb.TagNumber(2)
  ModelCategory get category => $_getN(1);
  @$pb.TagNumber(2)
  set category(ModelCategory v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasCategory() => $_has(1);
  @$pb.TagNumber(2)
  void clearCategory() => clearField(2);

  @$pb.TagNumber(3)
  ModelFormat get format => $_getN(2);
  @$pb.TagNumber(3)
  set format(ModelFormat v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasFormat() => $_has(2);
  @$pb.TagNumber(3)
  void clearFormat() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get downloadedOnly => $_getBF(3);
  @$pb.TagNumber(4)
  set downloadedOnly($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasDownloadedOnly() => $_has(3);
  @$pb.TagNumber(4)
  void clearDownloadedOnly() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get availableOnly => $_getBF(4);
  @$pb.TagNumber(5)
  set availableOnly($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAvailableOnly() => $_has(4);
  @$pb.TagNumber(5)
  void clearAvailableOnly() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get maxSizeBytes => $_getI64(5);
  @$pb.TagNumber(6)
  set maxSizeBytes($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasMaxSizeBytes() => $_has(5);
  @$pb.TagNumber(6)
  void clearMaxSizeBytes() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get searchQuery => $_getSZ(6);
  @$pb.TagNumber(7)
  set searchQuery($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasSearchQuery() => $_has(6);
  @$pb.TagNumber(7)
  void clearSearchQuery() => clearField(7);

  @$pb.TagNumber(8)
  ModelSource get source => $_getN(7);
  @$pb.TagNumber(8)
  set source(ModelSource v) { setField(8, v); }
  @$pb.TagNumber(8)
  $core.bool hasSource() => $_has(7);
  @$pb.TagNumber(8)
  void clearSource() => clearField(8);

  @$pb.TagNumber(9)
  ModelQuerySortField get sortField => $_getN(8);
  @$pb.TagNumber(9)
  set sortField(ModelQuerySortField v) { setField(9, v); }
  @$pb.TagNumber(9)
  $core.bool hasSortField() => $_has(8);
  @$pb.TagNumber(9)
  void clearSortField() => clearField(9);

  @$pb.TagNumber(10)
  ModelQuerySortOrder get sortOrder => $_getN(9);
  @$pb.TagNumber(10)
  set sortOrder(ModelQuerySortOrder v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasSortOrder() => $_has(9);
  @$pb.TagNumber(10)
  void clearSortOrder() => clearField(10);
}

class ModelCompatibilityResult extends $pb.GeneratedMessage {
  factory ModelCompatibilityResult({
    $core.bool? isCompatible,
    $core.bool? canRun,
    $core.bool? canFit,
    $fixnum.Int64? requiredMemoryBytes,
    $fixnum.Int64? availableMemoryBytes,
    $fixnum.Int64? requiredStorageBytes,
    $fixnum.Int64? availableStorageBytes,
    $core.Iterable<$core.String>? reasons,
  }) {
    final $result = create();
    if (isCompatible != null) {
      $result.isCompatible = isCompatible;
    }
    if (canRun != null) {
      $result.canRun = canRun;
    }
    if (canFit != null) {
      $result.canFit = canFit;
    }
    if (requiredMemoryBytes != null) {
      $result.requiredMemoryBytes = requiredMemoryBytes;
    }
    if (availableMemoryBytes != null) {
      $result.availableMemoryBytes = availableMemoryBytes;
    }
    if (requiredStorageBytes != null) {
      $result.requiredStorageBytes = requiredStorageBytes;
    }
    if (availableStorageBytes != null) {
      $result.availableStorageBytes = availableStorageBytes;
    }
    if (reasons != null) {
      $result.reasons.addAll(reasons);
    }
    return $result;
  }
  ModelCompatibilityResult._() : super();
  factory ModelCompatibilityResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelCompatibilityResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelCompatibilityResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isCompatible')
    ..aOB(2, _omitFieldNames ? '' : 'canRun')
    ..aOB(3, _omitFieldNames ? '' : 'canFit')
    ..aInt64(4, _omitFieldNames ? '' : 'requiredMemoryBytes')
    ..aInt64(5, _omitFieldNames ? '' : 'availableMemoryBytes')
    ..aInt64(6, _omitFieldNames ? '' : 'requiredStorageBytes')
    ..aInt64(7, _omitFieldNames ? '' : 'availableStorageBytes')
    ..pPS(8, _omitFieldNames ? '' : 'reasons')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelCompatibilityResult clone() => ModelCompatibilityResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelCompatibilityResult copyWith(void Function(ModelCompatibilityResult) updates) => super.copyWith((message) => updates(message as ModelCompatibilityResult)) as ModelCompatibilityResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelCompatibilityResult create() => ModelCompatibilityResult._();
  ModelCompatibilityResult createEmptyInstance() => create();
  static $pb.PbList<ModelCompatibilityResult> createRepeated() => $pb.PbList<ModelCompatibilityResult>();
  @$core.pragma('dart2js:noInline')
  static ModelCompatibilityResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelCompatibilityResult>(create);
  static ModelCompatibilityResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get isCompatible => $_getBF(0);
  @$pb.TagNumber(1)
  set isCompatible($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasIsCompatible() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsCompatible() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get canRun => $_getBF(1);
  @$pb.TagNumber(2)
  set canRun($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCanRun() => $_has(1);
  @$pb.TagNumber(2)
  void clearCanRun() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get canFit => $_getBF(2);
  @$pb.TagNumber(3)
  set canFit($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasCanFit() => $_has(2);
  @$pb.TagNumber(3)
  void clearCanFit() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get requiredMemoryBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set requiredMemoryBytes($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasRequiredMemoryBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearRequiredMemoryBytes() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get availableMemoryBytes => $_getI64(4);
  @$pb.TagNumber(5)
  set availableMemoryBytes($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAvailableMemoryBytes() => $_has(4);
  @$pb.TagNumber(5)
  void clearAvailableMemoryBytes() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get requiredStorageBytes => $_getI64(5);
  @$pb.TagNumber(6)
  set requiredStorageBytes($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasRequiredStorageBytes() => $_has(5);
  @$pb.TagNumber(6)
  void clearRequiredStorageBytes() => clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get availableStorageBytes => $_getI64(6);
  @$pb.TagNumber(7)
  set availableStorageBytes($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasAvailableStorageBytes() => $_has(6);
  @$pb.TagNumber(7)
  void clearAvailableStorageBytes() => clearField(7);

  @$pb.TagNumber(8)
  $core.List<$core.String> get reasons => $_getList(7);
}

class ModelRegistryRefreshRequest extends $pb.GeneratedMessage {
  factory ModelRegistryRefreshRequest({
    $core.bool? includeRemoteCatalog,
    $core.bool? rescanLocal,
    $core.bool? pruneOrphans,
    ModelQuery? query,
  }) {
    final $result = create();
    if (includeRemoteCatalog != null) {
      $result.includeRemoteCatalog = includeRemoteCatalog;
    }
    if (rescanLocal != null) {
      $result.rescanLocal = rescanLocal;
    }
    if (pruneOrphans != null) {
      $result.pruneOrphans = pruneOrphans;
    }
    if (query != null) {
      $result.query = query;
    }
    return $result;
  }
  ModelRegistryRefreshRequest._() : super();
  factory ModelRegistryRefreshRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelRegistryRefreshRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelRegistryRefreshRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'includeRemoteCatalog')
    ..aOB(2, _omitFieldNames ? '' : 'rescanLocal')
    ..aOB(3, _omitFieldNames ? '' : 'pruneOrphans')
    ..aOM<ModelQuery>(4, _omitFieldNames ? '' : 'query', subBuilder: ModelQuery.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelRegistryRefreshRequest clone() => ModelRegistryRefreshRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelRegistryRefreshRequest copyWith(void Function(ModelRegistryRefreshRequest) updates) => super.copyWith((message) => updates(message as ModelRegistryRefreshRequest)) as ModelRegistryRefreshRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelRegistryRefreshRequest create() => ModelRegistryRefreshRequest._();
  ModelRegistryRefreshRequest createEmptyInstance() => create();
  static $pb.PbList<ModelRegistryRefreshRequest> createRepeated() => $pb.PbList<ModelRegistryRefreshRequest>();
  @$core.pragma('dart2js:noInline')
  static ModelRegistryRefreshRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelRegistryRefreshRequest>(create);
  static ModelRegistryRefreshRequest? _defaultInstance;

  /// Fetch or merge a remote catalog through the platform/network adapter.
  @$pb.TagNumber(1)
  $core.bool get includeRemoteCatalog => $_getBF(0);
  @$pb.TagNumber(1)
  set includeRemoteCatalog($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasIncludeRemoteCatalog() => $_has(0);
  @$pb.TagNumber(1)
  void clearIncludeRemoteCatalog() => clearField(1);

  /// Scan managed model directories and link valid on-disk artifacts.
  @$pb.TagNumber(2)
  $core.bool get rescanLocal => $_getBF(1);
  @$pb.TagNumber(2)
  set rescanLocal($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasRescanLocal() => $_has(1);
  @$pb.TagNumber(2)
  void clearRescanLocal() => clearField(2);

  /// Clear downloaded/available state for registry rows whose files vanished.
  @$pb.TagNumber(3)
  $core.bool get pruneOrphans => $_getBF(2);
  @$pb.TagNumber(3)
  set pruneOrphans($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPruneOrphans() => $_has(2);
  @$pb.TagNumber(3)
  void clearPruneOrphans() => clearField(3);

  /// Optional post-refresh filter for the returned model list.
  @$pb.TagNumber(4)
  ModelQuery get query => $_getN(3);
  @$pb.TagNumber(4)
  set query(ModelQuery v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasQuery() => $_has(3);
  @$pb.TagNumber(4)
  void clearQuery() => clearField(4);
  @$pb.TagNumber(4)
  ModelQuery ensureQuery() => $_ensure(3);
}

class ModelRegistryRefreshResult extends $pb.GeneratedMessage {
  factory ModelRegistryRefreshResult({
    $core.bool? success,
    ModelInfoList? models,
    $core.int? registeredCount,
    $core.int? updatedCount,
    $core.int? discoveredCount,
    $core.int? prunedCount,
    $fixnum.Int64? refreshedAtUnixMs,
    $core.Iterable<$core.String>? warnings,
    $core.String? errorMessage,
  }) {
    final $result = create();
    if (success != null) {
      $result.success = success;
    }
    if (models != null) {
      $result.models = models;
    }
    if (registeredCount != null) {
      $result.registeredCount = registeredCount;
    }
    if (updatedCount != null) {
      $result.updatedCount = updatedCount;
    }
    if (discoveredCount != null) {
      $result.discoveredCount = discoveredCount;
    }
    if (prunedCount != null) {
      $result.prunedCount = prunedCount;
    }
    if (refreshedAtUnixMs != null) {
      $result.refreshedAtUnixMs = refreshedAtUnixMs;
    }
    if (warnings != null) {
      $result.warnings.addAll(warnings);
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    return $result;
  }
  ModelRegistryRefreshResult._() : super();
  factory ModelRegistryRefreshResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelRegistryRefreshResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelRegistryRefreshResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aOM<ModelInfoList>(2, _omitFieldNames ? '' : 'models', subBuilder: ModelInfoList.create)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'registeredCount', $pb.PbFieldType.O3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'updatedCount', $pb.PbFieldType.O3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'discoveredCount', $pb.PbFieldType.O3)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'prunedCount', $pb.PbFieldType.O3)
    ..aInt64(7, _omitFieldNames ? '' : 'refreshedAtUnixMs')
    ..pPS(8, _omitFieldNames ? '' : 'warnings')
    ..aOS(9, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelRegistryRefreshResult clone() => ModelRegistryRefreshResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelRegistryRefreshResult copyWith(void Function(ModelRegistryRefreshResult) updates) => super.copyWith((message) => updates(message as ModelRegistryRefreshResult)) as ModelRegistryRefreshResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelRegistryRefreshResult create() => ModelRegistryRefreshResult._();
  ModelRegistryRefreshResult createEmptyInstance() => create();
  static $pb.PbList<ModelRegistryRefreshResult> createRepeated() => $pb.PbList<ModelRegistryRefreshResult>();
  @$core.pragma('dart2js:noInline')
  static ModelRegistryRefreshResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelRegistryRefreshResult>(create);
  static ModelRegistryRefreshResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => clearField(1);

  @$pb.TagNumber(2)
  ModelInfoList get models => $_getN(1);
  @$pb.TagNumber(2)
  set models(ModelInfoList v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasModels() => $_has(1);
  @$pb.TagNumber(2)
  void clearModels() => clearField(2);
  @$pb.TagNumber(2)
  ModelInfoList ensureModels() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.int get registeredCount => $_getIZ(2);
  @$pb.TagNumber(3)
  set registeredCount($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRegisteredCount() => $_has(2);
  @$pb.TagNumber(3)
  void clearRegisteredCount() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get updatedCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set updatedCount($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasUpdatedCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearUpdatedCount() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get discoveredCount => $_getIZ(4);
  @$pb.TagNumber(5)
  set discoveredCount($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasDiscoveredCount() => $_has(4);
  @$pb.TagNumber(5)
  void clearDiscoveredCount() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get prunedCount => $_getIZ(5);
  @$pb.TagNumber(6)
  set prunedCount($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasPrunedCount() => $_has(5);
  @$pb.TagNumber(6)
  void clearPrunedCount() => clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get refreshedAtUnixMs => $_getI64(6);
  @$pb.TagNumber(7)
  set refreshedAtUnixMs($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasRefreshedAtUnixMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearRefreshedAtUnixMs() => clearField(7);

  @$pb.TagNumber(8)
  $core.List<$core.String> get warnings => $_getList(7);

  @$pb.TagNumber(9)
  $core.String get errorMessage => $_getSZ(8);
  @$pb.TagNumber(9)
  set errorMessage($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasErrorMessage() => $_has(8);
  @$pb.TagNumber(9)
  void clearErrorMessage() => clearField(9);
}

class ModelListRequest extends $pb.GeneratedMessage {
  factory ModelListRequest({
    ModelQuery? query,
  }) {
    final $result = create();
    if (query != null) {
      $result.query = query;
    }
    return $result;
  }
  ModelListRequest._() : super();
  factory ModelListRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelListRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelListRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOM<ModelQuery>(1, _omitFieldNames ? '' : 'query', subBuilder: ModelQuery.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelListRequest clone() => ModelListRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelListRequest copyWith(void Function(ModelListRequest) updates) => super.copyWith((message) => updates(message as ModelListRequest)) as ModelListRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelListRequest create() => ModelListRequest._();
  ModelListRequest createEmptyInstance() => create();
  static $pb.PbList<ModelListRequest> createRepeated() => $pb.PbList<ModelListRequest>();
  @$core.pragma('dart2js:noInline')
  static ModelListRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelListRequest>(create);
  static ModelListRequest? _defaultInstance;

  /// Set query.downloaded_only for downloaded-only lists.
  @$pb.TagNumber(1)
  ModelQuery get query => $_getN(0);
  @$pb.TagNumber(1)
  set query(ModelQuery v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasQuery() => $_has(0);
  @$pb.TagNumber(1)
  void clearQuery() => clearField(1);
  @$pb.TagNumber(1)
  ModelQuery ensureQuery() => $_ensure(0);
}

class ModelListResult extends $pb.GeneratedMessage {
  factory ModelListResult({
    $core.bool? success,
    ModelInfoList? models,
    $core.String? errorMessage,
  }) {
    final $result = create();
    if (success != null) {
      $result.success = success;
    }
    if (models != null) {
      $result.models = models;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    return $result;
  }
  ModelListResult._() : super();
  factory ModelListResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelListResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelListResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aOM<ModelInfoList>(2, _omitFieldNames ? '' : 'models', subBuilder: ModelInfoList.create)
    ..aOS(3, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelListResult clone() => ModelListResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelListResult copyWith(void Function(ModelListResult) updates) => super.copyWith((message) => updates(message as ModelListResult)) as ModelListResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelListResult create() => ModelListResult._();
  ModelListResult createEmptyInstance() => create();
  static $pb.PbList<ModelListResult> createRepeated() => $pb.PbList<ModelListResult>();
  @$core.pragma('dart2js:noInline')
  static ModelListResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelListResult>(create);
  static ModelListResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => clearField(1);

  @$pb.TagNumber(2)
  ModelInfoList get models => $_getN(1);
  @$pb.TagNumber(2)
  set models(ModelInfoList v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasModels() => $_has(1);
  @$pb.TagNumber(2)
  void clearModels() => clearField(2);
  @$pb.TagNumber(2)
  ModelInfoList ensureModels() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.String get errorMessage => $_getSZ(2);
  @$pb.TagNumber(3)
  set errorMessage($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasErrorMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearErrorMessage() => clearField(3);
}

class ModelGetRequest extends $pb.GeneratedMessage {
  factory ModelGetRequest({
    $core.String? modelId,
  }) {
    final $result = create();
    if (modelId != null) {
      $result.modelId = modelId;
    }
    return $result;
  }
  ModelGetRequest._() : super();
  factory ModelGetRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelGetRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelGetRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelGetRequest clone() => ModelGetRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelGetRequest copyWith(void Function(ModelGetRequest) updates) => super.copyWith((message) => updates(message as ModelGetRequest)) as ModelGetRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelGetRequest create() => ModelGetRequest._();
  ModelGetRequest createEmptyInstance() => create();
  static $pb.PbList<ModelGetRequest> createRepeated() => $pb.PbList<ModelGetRequest>();
  @$core.pragma('dart2js:noInline')
  static ModelGetRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelGetRequest>(create);
  static ModelGetRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => clearField(1);
}

class ModelGetResult extends $pb.GeneratedMessage {
  factory ModelGetResult({
    $core.bool? found,
    ModelInfo? model,
    $core.String? errorMessage,
  }) {
    final $result = create();
    if (found != null) {
      $result.found = found;
    }
    if (model != null) {
      $result.model = model;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    return $result;
  }
  ModelGetResult._() : super();
  factory ModelGetResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelGetResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelGetResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'found')
    ..aOM<ModelInfo>(2, _omitFieldNames ? '' : 'model', subBuilder: ModelInfo.create)
    ..aOS(3, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelGetResult clone() => ModelGetResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelGetResult copyWith(void Function(ModelGetResult) updates) => super.copyWith((message) => updates(message as ModelGetResult)) as ModelGetResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelGetResult create() => ModelGetResult._();
  ModelGetResult createEmptyInstance() => create();
  static $pb.PbList<ModelGetResult> createRepeated() => $pb.PbList<ModelGetResult>();
  @$core.pragma('dart2js:noInline')
  static ModelGetResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelGetResult>(create);
  static ModelGetResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get found => $_getBF(0);
  @$pb.TagNumber(1)
  set found($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasFound() => $_has(0);
  @$pb.TagNumber(1)
  void clearFound() => clearField(1);

  @$pb.TagNumber(2)
  ModelInfo get model => $_getN(1);
  @$pb.TagNumber(2)
  set model(ModelInfo v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasModel() => $_has(1);
  @$pb.TagNumber(2)
  void clearModel() => clearField(2);
  @$pb.TagNumber(2)
  ModelInfo ensureModel() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.String get errorMessage => $_getSZ(2);
  @$pb.TagNumber(3)
  set errorMessage($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasErrorMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearErrorMessage() => clearField(3);
}

class ModelImportRequest extends $pb.GeneratedMessage {
  factory ModelImportRequest({
    ModelInfo? model,
    $core.String? sourcePath,
    $core.bool? copyIntoManagedStorage,
    $core.bool? overwriteExisting,
    $core.Iterable<ModelFileDescriptor>? files,
  }) {
    final $result = create();
    if (model != null) {
      $result.model = model;
    }
    if (sourcePath != null) {
      $result.sourcePath = sourcePath;
    }
    if (copyIntoManagedStorage != null) {
      $result.copyIntoManagedStorage = copyIntoManagedStorage;
    }
    if (overwriteExisting != null) {
      $result.overwriteExisting = overwriteExisting;
    }
    if (files != null) {
      $result.files.addAll(files);
    }
    return $result;
  }
  ModelImportRequest._() : super();
  factory ModelImportRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelImportRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelImportRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOM<ModelInfo>(1, _omitFieldNames ? '' : 'model', subBuilder: ModelInfo.create)
    ..aOS(2, _omitFieldNames ? '' : 'sourcePath')
    ..aOB(3, _omitFieldNames ? '' : 'copyIntoManagedStorage')
    ..aOB(4, _omitFieldNames ? '' : 'overwriteExisting')
    ..pc<ModelFileDescriptor>(5, _omitFieldNames ? '' : 'files', $pb.PbFieldType.PM, subBuilder: ModelFileDescriptor.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelImportRequest clone() => ModelImportRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelImportRequest copyWith(void Function(ModelImportRequest) updates) => super.copyWith((message) => updates(message as ModelImportRequest)) as ModelImportRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelImportRequest create() => ModelImportRequest._();
  ModelImportRequest createEmptyInstance() => create();
  static $pb.PbList<ModelImportRequest> createRepeated() => $pb.PbList<ModelImportRequest>();
  @$core.pragma('dart2js:noInline')
  static ModelImportRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelImportRequest>(create);
  static ModelImportRequest? _defaultInstance;

  /// Catalog metadata to register or merge. If absent, discovery may infer a
  /// minimal ModelInfo from the file name and detected format.
  @$pb.TagNumber(1)
  ModelInfo get model => $_getN(0);
  @$pb.TagNumber(1)
  set model(ModelInfo v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasModel() => $_has(0);
  @$pb.TagNumber(1)
  void clearModel() => clearField(1);
  @$pb.TagNumber(1)
  ModelInfo ensureModel() => $_ensure(0);

  /// Normalized path under platform control. Do not place transient OS file
  /// picker handles in this field; adapters should first copy/link/authorize
  /// them and provide a stable path visible to the C++ workflow.
  @$pb.TagNumber(2)
  $core.String get sourcePath => $_getSZ(1);
  @$pb.TagNumber(2)
  set sourcePath($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSourcePath() => $_has(1);
  @$pb.TagNumber(2)
  void clearSourcePath() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get copyIntoManagedStorage => $_getBF(2);
  @$pb.TagNumber(3)
  set copyIntoManagedStorage($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasCopyIntoManagedStorage() => $_has(2);
  @$pb.TagNumber(3)
  void clearCopyIntoManagedStorage() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get overwriteExisting => $_getBF(3);
  @$pb.TagNumber(4)
  set overwriteExisting($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasOverwriteExisting() => $_has(3);
  @$pb.TagNumber(4)
  void clearOverwriteExisting() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<ModelFileDescriptor> get files => $_getList(4);
}

class ModelImportResult extends $pb.GeneratedMessage {
  factory ModelImportResult({
    $core.bool? success,
    ModelInfo? model,
    $core.String? localPath,
    $fixnum.Int64? importedBytes,
    $core.Iterable<$core.String>? warnings,
    $core.String? errorMessage,
  }) {
    final $result = create();
    if (success != null) {
      $result.success = success;
    }
    if (model != null) {
      $result.model = model;
    }
    if (localPath != null) {
      $result.localPath = localPath;
    }
    if (importedBytes != null) {
      $result.importedBytes = importedBytes;
    }
    if (warnings != null) {
      $result.warnings.addAll(warnings);
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    return $result;
  }
  ModelImportResult._() : super();
  factory ModelImportResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelImportResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelImportResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aOM<ModelInfo>(2, _omitFieldNames ? '' : 'model', subBuilder: ModelInfo.create)
    ..aOS(3, _omitFieldNames ? '' : 'localPath')
    ..aInt64(4, _omitFieldNames ? '' : 'importedBytes')
    ..pPS(5, _omitFieldNames ? '' : 'warnings')
    ..aOS(6, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelImportResult clone() => ModelImportResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelImportResult copyWith(void Function(ModelImportResult) updates) => super.copyWith((message) => updates(message as ModelImportResult)) as ModelImportResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelImportResult create() => ModelImportResult._();
  ModelImportResult createEmptyInstance() => create();
  static $pb.PbList<ModelImportResult> createRepeated() => $pb.PbList<ModelImportResult>();
  @$core.pragma('dart2js:noInline')
  static ModelImportResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelImportResult>(create);
  static ModelImportResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => clearField(1);

  @$pb.TagNumber(2)
  ModelInfo get model => $_getN(1);
  @$pb.TagNumber(2)
  set model(ModelInfo v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasModel() => $_has(1);
  @$pb.TagNumber(2)
  void clearModel() => clearField(2);
  @$pb.TagNumber(2)
  ModelInfo ensureModel() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.String get localPath => $_getSZ(2);
  @$pb.TagNumber(3)
  set localPath($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasLocalPath() => $_has(2);
  @$pb.TagNumber(3)
  void clearLocalPath() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get importedBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set importedBytes($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasImportedBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearImportedBytes() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.String> get warnings => $_getList(4);

  @$pb.TagNumber(6)
  $core.String get errorMessage => $_getSZ(5);
  @$pb.TagNumber(6)
  set errorMessage($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasErrorMessage() => $_has(5);
  @$pb.TagNumber(6)
  void clearErrorMessage() => clearField(6);
}

class ModelDiscoveryRequest extends $pb.GeneratedMessage {
  factory ModelDiscoveryRequest({
    $core.Iterable<$core.String>? searchRoots,
    $core.bool? recursive,
    $core.bool? linkDownloaded,
    $core.bool? purgeInvalid,
    ModelQuery? query,
  }) {
    final $result = create();
    if (searchRoots != null) {
      $result.searchRoots.addAll(searchRoots);
    }
    if (recursive != null) {
      $result.recursive = recursive;
    }
    if (linkDownloaded != null) {
      $result.linkDownloaded = linkDownloaded;
    }
    if (purgeInvalid != null) {
      $result.purgeInvalid = purgeInvalid;
    }
    if (query != null) {
      $result.query = query;
    }
    return $result;
  }
  ModelDiscoveryRequest._() : super();
  factory ModelDiscoveryRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelDiscoveryRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelDiscoveryRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'searchRoots')
    ..aOB(2, _omitFieldNames ? '' : 'recursive')
    ..aOB(3, _omitFieldNames ? '' : 'linkDownloaded')
    ..aOB(4, _omitFieldNames ? '' : 'purgeInvalid')
    ..aOM<ModelQuery>(5, _omitFieldNames ? '' : 'query', subBuilder: ModelQuery.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelDiscoveryRequest clone() => ModelDiscoveryRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelDiscoveryRequest copyWith(void Function(ModelDiscoveryRequest) updates) => super.copyWith((message) => updates(message as ModelDiscoveryRequest)) as ModelDiscoveryRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelDiscoveryRequest create() => ModelDiscoveryRequest._();
  ModelDiscoveryRequest createEmptyInstance() => create();
  static $pb.PbList<ModelDiscoveryRequest> createRepeated() => $pb.PbList<ModelDiscoveryRequest>();
  @$core.pragma('dart2js:noInline')
  static ModelDiscoveryRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelDiscoveryRequest>(create);
  static ModelDiscoveryRequest? _defaultInstance;

  /// Platform adapters own permission and sandbox traversal. These are stable
  /// roots that C++ may inspect using registered filesystem callbacks.
  @$pb.TagNumber(1)
  $core.List<$core.String> get searchRoots => $_getList(0);

  @$pb.TagNumber(2)
  $core.bool get recursive => $_getBF(1);
  @$pb.TagNumber(2)
  set recursive($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasRecursive() => $_has(1);
  @$pb.TagNumber(2)
  void clearRecursive() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get linkDownloaded => $_getBF(2);
  @$pb.TagNumber(3)
  set linkDownloaded($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasLinkDownloaded() => $_has(2);
  @$pb.TagNumber(3)
  void clearLinkDownloaded() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get purgeInvalid => $_getBF(3);
  @$pb.TagNumber(4)
  set purgeInvalid($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasPurgeInvalid() => $_has(3);
  @$pb.TagNumber(4)
  void clearPurgeInvalid() => clearField(4);

  @$pb.TagNumber(5)
  ModelQuery get query => $_getN(4);
  @$pb.TagNumber(5)
  set query(ModelQuery v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasQuery() => $_has(4);
  @$pb.TagNumber(5)
  void clearQuery() => clearField(5);
  @$pb.TagNumber(5)
  ModelQuery ensureQuery() => $_ensure(4);
}

class DiscoveredModel extends $pb.GeneratedMessage {
  factory DiscoveredModel({
    $core.String? modelId,
    $core.String? localPath,
    $core.bool? matchedRegistry,
    ModelInfo? model,
    $fixnum.Int64? sizeBytes,
    $core.Iterable<$core.String>? warnings,
  }) {
    final $result = create();
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (localPath != null) {
      $result.localPath = localPath;
    }
    if (matchedRegistry != null) {
      $result.matchedRegistry = matchedRegistry;
    }
    if (model != null) {
      $result.model = model;
    }
    if (sizeBytes != null) {
      $result.sizeBytes = sizeBytes;
    }
    if (warnings != null) {
      $result.warnings.addAll(warnings);
    }
    return $result;
  }
  DiscoveredModel._() : super();
  factory DiscoveredModel.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DiscoveredModel.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DiscoveredModel', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aOS(2, _omitFieldNames ? '' : 'localPath')
    ..aOB(3, _omitFieldNames ? '' : 'matchedRegistry')
    ..aOM<ModelInfo>(4, _omitFieldNames ? '' : 'model', subBuilder: ModelInfo.create)
    ..aInt64(5, _omitFieldNames ? '' : 'sizeBytes')
    ..pPS(6, _omitFieldNames ? '' : 'warnings')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DiscoveredModel clone() => DiscoveredModel()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DiscoveredModel copyWith(void Function(DiscoveredModel) updates) => super.copyWith((message) => updates(message as DiscoveredModel)) as DiscoveredModel;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiscoveredModel create() => DiscoveredModel._();
  DiscoveredModel createEmptyInstance() => create();
  static $pb.PbList<DiscoveredModel> createRepeated() => $pb.PbList<DiscoveredModel>();
  @$core.pragma('dart2js:noInline')
  static DiscoveredModel getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DiscoveredModel>(create);
  static DiscoveredModel? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get localPath => $_getSZ(1);
  @$pb.TagNumber(2)
  set localPath($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasLocalPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearLocalPath() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get matchedRegistry => $_getBF(2);
  @$pb.TagNumber(3)
  set matchedRegistry($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMatchedRegistry() => $_has(2);
  @$pb.TagNumber(3)
  void clearMatchedRegistry() => clearField(3);

  @$pb.TagNumber(4)
  ModelInfo get model => $_getN(3);
  @$pb.TagNumber(4)
  set model(ModelInfo v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasModel() => $_has(3);
  @$pb.TagNumber(4)
  void clearModel() => clearField(4);
  @$pb.TagNumber(4)
  ModelInfo ensureModel() => $_ensure(3);

  @$pb.TagNumber(5)
  $fixnum.Int64 get sizeBytes => $_getI64(4);
  @$pb.TagNumber(5)
  set sizeBytes($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSizeBytes() => $_has(4);
  @$pb.TagNumber(5)
  void clearSizeBytes() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.String> get warnings => $_getList(5);
}

class ModelDiscoveryResult extends $pb.GeneratedMessage {
  factory ModelDiscoveryResult({
    $core.bool? success,
    $core.Iterable<DiscoveredModel>? discoveredModels,
    $core.int? linkedCount,
    $core.int? purgedCount,
    $core.Iterable<$core.String>? warnings,
    $core.String? errorMessage,
  }) {
    final $result = create();
    if (success != null) {
      $result.success = success;
    }
    if (discoveredModels != null) {
      $result.discoveredModels.addAll(discoveredModels);
    }
    if (linkedCount != null) {
      $result.linkedCount = linkedCount;
    }
    if (purgedCount != null) {
      $result.purgedCount = purgedCount;
    }
    if (warnings != null) {
      $result.warnings.addAll(warnings);
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    return $result;
  }
  ModelDiscoveryResult._() : super();
  factory ModelDiscoveryResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelDiscoveryResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelDiscoveryResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..pc<DiscoveredModel>(2, _omitFieldNames ? '' : 'discoveredModels', $pb.PbFieldType.PM, subBuilder: DiscoveredModel.create)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'linkedCount', $pb.PbFieldType.O3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'purgedCount', $pb.PbFieldType.O3)
    ..pPS(5, _omitFieldNames ? '' : 'warnings')
    ..aOS(6, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelDiscoveryResult clone() => ModelDiscoveryResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelDiscoveryResult copyWith(void Function(ModelDiscoveryResult) updates) => super.copyWith((message) => updates(message as ModelDiscoveryResult)) as ModelDiscoveryResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelDiscoveryResult create() => ModelDiscoveryResult._();
  ModelDiscoveryResult createEmptyInstance() => create();
  static $pb.PbList<ModelDiscoveryResult> createRepeated() => $pb.PbList<ModelDiscoveryResult>();
  @$core.pragma('dart2js:noInline')
  static ModelDiscoveryResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelDiscoveryResult>(create);
  static ModelDiscoveryResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<DiscoveredModel> get discoveredModels => $_getList(1);

  @$pb.TagNumber(3)
  $core.int get linkedCount => $_getIZ(2);
  @$pb.TagNumber(3)
  set linkedCount($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasLinkedCount() => $_has(2);
  @$pb.TagNumber(3)
  void clearLinkedCount() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get purgedCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set purgedCount($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasPurgedCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearPurgedCount() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.String> get warnings => $_getList(4);

  @$pb.TagNumber(6)
  $core.String get errorMessage => $_getSZ(5);
  @$pb.TagNumber(6)
  set errorMessage($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasErrorMessage() => $_has(5);
  @$pb.TagNumber(6)
  void clearErrorMessage() => clearField(6);
}

class ModelLoadRequest extends $pb.GeneratedMessage {
  factory ModelLoadRequest({
    $core.String? modelId,
    ModelCategory? category,
    InferenceFramework? framework,
    $core.bool? forceReload,
  }) {
    final $result = create();
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (category != null) {
      $result.category = category;
    }
    if (framework != null) {
      $result.framework = framework;
    }
    if (forceReload != null) {
      $result.forceReload = forceReload;
    }
    return $result;
  }
  ModelLoadRequest._() : super();
  factory ModelLoadRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelLoadRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelLoadRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..e<ModelCategory>(2, _omitFieldNames ? '' : 'category', $pb.PbFieldType.OE, defaultOrMaker: ModelCategory.MODEL_CATEGORY_UNSPECIFIED, valueOf: ModelCategory.valueOf, enumValues: ModelCategory.values)
    ..e<InferenceFramework>(3, _omitFieldNames ? '' : 'framework', $pb.PbFieldType.OE, defaultOrMaker: InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED, valueOf: InferenceFramework.valueOf, enumValues: InferenceFramework.values)
    ..aOB(4, _omitFieldNames ? '' : 'forceReload')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelLoadRequest clone() => ModelLoadRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelLoadRequest copyWith(void Function(ModelLoadRequest) updates) => super.copyWith((message) => updates(message as ModelLoadRequest)) as ModelLoadRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelLoadRequest create() => ModelLoadRequest._();
  ModelLoadRequest createEmptyInstance() => create();
  static $pb.PbList<ModelLoadRequest> createRepeated() => $pb.PbList<ModelLoadRequest>();
  @$core.pragma('dart2js:noInline')
  static ModelLoadRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelLoadRequest>(create);
  static ModelLoadRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => clearField(1);

  @$pb.TagNumber(2)
  ModelCategory get category => $_getN(1);
  @$pb.TagNumber(2)
  set category(ModelCategory v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasCategory() => $_has(1);
  @$pb.TagNumber(2)
  void clearCategory() => clearField(2);

  @$pb.TagNumber(3)
  InferenceFramework get framework => $_getN(2);
  @$pb.TagNumber(3)
  set framework(InferenceFramework v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasFramework() => $_has(2);
  @$pb.TagNumber(3)
  void clearFramework() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get forceReload => $_getBF(3);
  @$pb.TagNumber(4)
  set forceReload($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasForceReload() => $_has(3);
  @$pb.TagNumber(4)
  void clearForceReload() => clearField(4);
}

class ModelLoadResult extends $pb.GeneratedMessage {
  factory ModelLoadResult({
    $core.bool? success,
    $core.String? modelId,
    ModelCategory? category,
    InferenceFramework? framework,
    $core.String? resolvedPath,
    $fixnum.Int64? loadedAtUnixMs,
    $core.String? errorMessage,
  }) {
    final $result = create();
    if (success != null) {
      $result.success = success;
    }
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (category != null) {
      $result.category = category;
    }
    if (framework != null) {
      $result.framework = framework;
    }
    if (resolvedPath != null) {
      $result.resolvedPath = resolvedPath;
    }
    if (loadedAtUnixMs != null) {
      $result.loadedAtUnixMs = loadedAtUnixMs;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    return $result;
  }
  ModelLoadResult._() : super();
  factory ModelLoadResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelLoadResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelLoadResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..e<ModelCategory>(3, _omitFieldNames ? '' : 'category', $pb.PbFieldType.OE, defaultOrMaker: ModelCategory.MODEL_CATEGORY_UNSPECIFIED, valueOf: ModelCategory.valueOf, enumValues: ModelCategory.values)
    ..e<InferenceFramework>(4, _omitFieldNames ? '' : 'framework', $pb.PbFieldType.OE, defaultOrMaker: InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED, valueOf: InferenceFramework.valueOf, enumValues: InferenceFramework.values)
    ..aOS(5, _omitFieldNames ? '' : 'resolvedPath')
    ..aInt64(6, _omitFieldNames ? '' : 'loadedAtUnixMs')
    ..aOS(7, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelLoadResult clone() => ModelLoadResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelLoadResult copyWith(void Function(ModelLoadResult) updates) => super.copyWith((message) => updates(message as ModelLoadResult)) as ModelLoadResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelLoadResult create() => ModelLoadResult._();
  ModelLoadResult createEmptyInstance() => create();
  static $pb.PbList<ModelLoadResult> createRepeated() => $pb.PbList<ModelLoadResult>();
  @$core.pragma('dart2js:noInline')
  static ModelLoadResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelLoadResult>(create);
  static ModelLoadResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => clearField(2);

  @$pb.TagNumber(3)
  ModelCategory get category => $_getN(2);
  @$pb.TagNumber(3)
  set category(ModelCategory v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasCategory() => $_has(2);
  @$pb.TagNumber(3)
  void clearCategory() => clearField(3);

  @$pb.TagNumber(4)
  InferenceFramework get framework => $_getN(3);
  @$pb.TagNumber(4)
  set framework(InferenceFramework v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasFramework() => $_has(3);
  @$pb.TagNumber(4)
  void clearFramework() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get resolvedPath => $_getSZ(4);
  @$pb.TagNumber(5)
  set resolvedPath($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasResolvedPath() => $_has(4);
  @$pb.TagNumber(5)
  void clearResolvedPath() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get loadedAtUnixMs => $_getI64(5);
  @$pb.TagNumber(6)
  set loadedAtUnixMs($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasLoadedAtUnixMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearLoadedAtUnixMs() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get errorMessage => $_getSZ(6);
  @$pb.TagNumber(7)
  set errorMessage($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasErrorMessage() => $_has(6);
  @$pb.TagNumber(7)
  void clearErrorMessage() => clearField(7);
}

class ModelUnloadRequest extends $pb.GeneratedMessage {
  factory ModelUnloadRequest({
    $core.String? modelId,
    ModelCategory? category,
    $core.bool? unloadAll,
  }) {
    final $result = create();
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (category != null) {
      $result.category = category;
    }
    if (unloadAll != null) {
      $result.unloadAll = unloadAll;
    }
    return $result;
  }
  ModelUnloadRequest._() : super();
  factory ModelUnloadRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelUnloadRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelUnloadRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..e<ModelCategory>(2, _omitFieldNames ? '' : 'category', $pb.PbFieldType.OE, defaultOrMaker: ModelCategory.MODEL_CATEGORY_UNSPECIFIED, valueOf: ModelCategory.valueOf, enumValues: ModelCategory.values)
    ..aOB(3, _omitFieldNames ? '' : 'unloadAll')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelUnloadRequest clone() => ModelUnloadRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelUnloadRequest copyWith(void Function(ModelUnloadRequest) updates) => super.copyWith((message) => updates(message as ModelUnloadRequest)) as ModelUnloadRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelUnloadRequest create() => ModelUnloadRequest._();
  ModelUnloadRequest createEmptyInstance() => create();
  static $pb.PbList<ModelUnloadRequest> createRepeated() => $pb.PbList<ModelUnloadRequest>();
  @$core.pragma('dart2js:noInline')
  static ModelUnloadRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelUnloadRequest>(create);
  static ModelUnloadRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => clearField(1);

  @$pb.TagNumber(2)
  ModelCategory get category => $_getN(1);
  @$pb.TagNumber(2)
  set category(ModelCategory v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasCategory() => $_has(1);
  @$pb.TagNumber(2)
  void clearCategory() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get unloadAll => $_getBF(2);
  @$pb.TagNumber(3)
  set unloadAll($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasUnloadAll() => $_has(2);
  @$pb.TagNumber(3)
  void clearUnloadAll() => clearField(3);
}

class ModelUnloadResult extends $pb.GeneratedMessage {
  factory ModelUnloadResult({
    $core.bool? success,
    $core.Iterable<$core.String>? unloadedModelIds,
    $core.String? errorMessage,
  }) {
    final $result = create();
    if (success != null) {
      $result.success = success;
    }
    if (unloadedModelIds != null) {
      $result.unloadedModelIds.addAll(unloadedModelIds);
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    return $result;
  }
  ModelUnloadResult._() : super();
  factory ModelUnloadResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelUnloadResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelUnloadResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..pPS(2, _omitFieldNames ? '' : 'unloadedModelIds')
    ..aOS(3, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelUnloadResult clone() => ModelUnloadResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelUnloadResult copyWith(void Function(ModelUnloadResult) updates) => super.copyWith((message) => updates(message as ModelUnloadResult)) as ModelUnloadResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelUnloadResult create() => ModelUnloadResult._();
  ModelUnloadResult createEmptyInstance() => create();
  static $pb.PbList<ModelUnloadResult> createRepeated() => $pb.PbList<ModelUnloadResult>();
  @$core.pragma('dart2js:noInline')
  static ModelUnloadResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelUnloadResult>(create);
  static ModelUnloadResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.String> get unloadedModelIds => $_getList(1);

  @$pb.TagNumber(3)
  $core.String get errorMessage => $_getSZ(2);
  @$pb.TagNumber(3)
  set errorMessage($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasErrorMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearErrorMessage() => clearField(3);
}

class CurrentModelRequest extends $pb.GeneratedMessage {
  factory CurrentModelRequest({
    ModelCategory? category,
    InferenceFramework? framework,
  }) {
    final $result = create();
    if (category != null) {
      $result.category = category;
    }
    if (framework != null) {
      $result.framework = framework;
    }
    return $result;
  }
  CurrentModelRequest._() : super();
  factory CurrentModelRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CurrentModelRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CurrentModelRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<ModelCategory>(1, _omitFieldNames ? '' : 'category', $pb.PbFieldType.OE, defaultOrMaker: ModelCategory.MODEL_CATEGORY_UNSPECIFIED, valueOf: ModelCategory.valueOf, enumValues: ModelCategory.values)
    ..e<InferenceFramework>(2, _omitFieldNames ? '' : 'framework', $pb.PbFieldType.OE, defaultOrMaker: InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED, valueOf: InferenceFramework.valueOf, enumValues: InferenceFramework.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CurrentModelRequest clone() => CurrentModelRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CurrentModelRequest copyWith(void Function(CurrentModelRequest) updates) => super.copyWith((message) => updates(message as CurrentModelRequest)) as CurrentModelRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CurrentModelRequest create() => CurrentModelRequest._();
  CurrentModelRequest createEmptyInstance() => create();
  static $pb.PbList<CurrentModelRequest> createRepeated() => $pb.PbList<CurrentModelRequest>();
  @$core.pragma('dart2js:noInline')
  static CurrentModelRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CurrentModelRequest>(create);
  static CurrentModelRequest? _defaultInstance;

  @$pb.TagNumber(1)
  ModelCategory get category => $_getN(0);
  @$pb.TagNumber(1)
  set category(ModelCategory v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasCategory() => $_has(0);
  @$pb.TagNumber(1)
  void clearCategory() => clearField(1);

  @$pb.TagNumber(2)
  InferenceFramework get framework => $_getN(1);
  @$pb.TagNumber(2)
  set framework(InferenceFramework v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasFramework() => $_has(1);
  @$pb.TagNumber(2)
  void clearFramework() => clearField(2);
}

class CurrentModelResult extends $pb.GeneratedMessage {
  factory CurrentModelResult({
    $core.String? modelId,
    ModelInfo? model,
    $fixnum.Int64? loadedAtUnixMs,
  }) {
    final $result = create();
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (model != null) {
      $result.model = model;
    }
    if (loadedAtUnixMs != null) {
      $result.loadedAtUnixMs = loadedAtUnixMs;
    }
    return $result;
  }
  CurrentModelResult._() : super();
  factory CurrentModelResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CurrentModelResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CurrentModelResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..aOM<ModelInfo>(3, _omitFieldNames ? '' : 'model', subBuilder: ModelInfo.create)
    ..aInt64(4, _omitFieldNames ? '' : 'loadedAtUnixMs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CurrentModelResult clone() => CurrentModelResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CurrentModelResult copyWith(void Function(CurrentModelResult) updates) => super.copyWith((message) => updates(message as CurrentModelResult)) as CurrentModelResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CurrentModelResult create() => CurrentModelResult._();
  CurrentModelResult createEmptyInstance() => create();
  static $pb.PbList<CurrentModelResult> createRepeated() => $pb.PbList<CurrentModelResult>();
  @$core.pragma('dart2js:noInline')
  static CurrentModelResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CurrentModelResult>(create);
  static CurrentModelResult? _defaultInstance;

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(2)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(2)
  void clearModelId() => clearField(2);

  @$pb.TagNumber(3)
  ModelInfo get model => $_getN(1);
  @$pb.TagNumber(3)
  set model(ModelInfo v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasModel() => $_has(1);
  @$pb.TagNumber(3)
  void clearModel() => clearField(3);
  @$pb.TagNumber(3)
  ModelInfo ensureModel() => $_ensure(1);

  @$pb.TagNumber(4)
  $fixnum.Int64 get loadedAtUnixMs => $_getI64(2);
  @$pb.TagNumber(4)
  set loadedAtUnixMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(4)
  $core.bool hasLoadedAtUnixMs() => $_has(2);
  @$pb.TagNumber(4)
  void clearLoadedAtUnixMs() => clearField(4);
}

class ModelDeleteRequest extends $pb.GeneratedMessage {
  factory ModelDeleteRequest({
    $core.String? modelId,
    $core.bool? deleteFiles,
    $core.bool? unregister,
    $core.bool? unloadIfLoaded,
  }) {
    final $result = create();
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (deleteFiles != null) {
      $result.deleteFiles = deleteFiles;
    }
    if (unregister != null) {
      $result.unregister = unregister;
    }
    if (unloadIfLoaded != null) {
      $result.unloadIfLoaded = unloadIfLoaded;
    }
    return $result;
  }
  ModelDeleteRequest._() : super();
  factory ModelDeleteRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelDeleteRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelDeleteRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aOB(2, _omitFieldNames ? '' : 'deleteFiles')
    ..aOB(3, _omitFieldNames ? '' : 'unregister')
    ..aOB(4, _omitFieldNames ? '' : 'unloadIfLoaded')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelDeleteRequest clone() => ModelDeleteRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelDeleteRequest copyWith(void Function(ModelDeleteRequest) updates) => super.copyWith((message) => updates(message as ModelDeleteRequest)) as ModelDeleteRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelDeleteRequest create() => ModelDeleteRequest._();
  ModelDeleteRequest createEmptyInstance() => create();
  static $pb.PbList<ModelDeleteRequest> createRepeated() => $pb.PbList<ModelDeleteRequest>();
  @$core.pragma('dart2js:noInline')
  static ModelDeleteRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelDeleteRequest>(create);
  static ModelDeleteRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get deleteFiles => $_getBF(1);
  @$pb.TagNumber(2)
  set deleteFiles($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeleteFiles() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeleteFiles() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get unregister => $_getBF(2);
  @$pb.TagNumber(3)
  set unregister($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasUnregister() => $_has(2);
  @$pb.TagNumber(3)
  void clearUnregister() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get unloadIfLoaded => $_getBF(3);
  @$pb.TagNumber(4)
  set unloadIfLoaded($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasUnloadIfLoaded() => $_has(3);
  @$pb.TagNumber(4)
  void clearUnloadIfLoaded() => clearField(4);
}

class ModelDeleteResult extends $pb.GeneratedMessage {
  factory ModelDeleteResult({
    $core.bool? success,
    $core.String? modelId,
    $fixnum.Int64? deletedBytes,
    $core.bool? filesDeleted,
    $core.bool? registryUpdated,
    $core.bool? wasLoaded,
    $core.String? errorMessage,
  }) {
    final $result = create();
    if (success != null) {
      $result.success = success;
    }
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (deletedBytes != null) {
      $result.deletedBytes = deletedBytes;
    }
    if (filesDeleted != null) {
      $result.filesDeleted = filesDeleted;
    }
    if (registryUpdated != null) {
      $result.registryUpdated = registryUpdated;
    }
    if (wasLoaded != null) {
      $result.wasLoaded = wasLoaded;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    return $result;
  }
  ModelDeleteResult._() : super();
  factory ModelDeleteResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelDeleteResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelDeleteResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..aInt64(3, _omitFieldNames ? '' : 'deletedBytes')
    ..aOB(4, _omitFieldNames ? '' : 'filesDeleted')
    ..aOB(5, _omitFieldNames ? '' : 'registryUpdated')
    ..aOB(6, _omitFieldNames ? '' : 'wasLoaded')
    ..aOS(7, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelDeleteResult clone() => ModelDeleteResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelDeleteResult copyWith(void Function(ModelDeleteResult) updates) => super.copyWith((message) => updates(message as ModelDeleteResult)) as ModelDeleteResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelDeleteResult create() => ModelDeleteResult._();
  ModelDeleteResult createEmptyInstance() => create();
  static $pb.PbList<ModelDeleteResult> createRepeated() => $pb.PbList<ModelDeleteResult>();
  @$core.pragma('dart2js:noInline')
  static ModelDeleteResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelDeleteResult>(create);
  static ModelDeleteResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get deletedBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set deletedBytes($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDeletedBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearDeletedBytes() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get filesDeleted => $_getBF(3);
  @$pb.TagNumber(4)
  set filesDeleted($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasFilesDeleted() => $_has(3);
  @$pb.TagNumber(4)
  void clearFilesDeleted() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get registryUpdated => $_getBF(4);
  @$pb.TagNumber(5)
  set registryUpdated($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasRegistryUpdated() => $_has(4);
  @$pb.TagNumber(5)
  void clearRegistryUpdated() => clearField(5);

  @$pb.TagNumber(6)
  $core.bool get wasLoaded => $_getBF(5);
  @$pb.TagNumber(6)
  set wasLoaded($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasWasLoaded() => $_has(5);
  @$pb.TagNumber(6)
  void clearWasLoaded() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get errorMessage => $_getSZ(6);
  @$pb.TagNumber(7)
  set errorMessage($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasErrorMessage() => $_has(6);
  @$pb.TagNumber(7)
  void clearErrorMessage() => clearField(7);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
