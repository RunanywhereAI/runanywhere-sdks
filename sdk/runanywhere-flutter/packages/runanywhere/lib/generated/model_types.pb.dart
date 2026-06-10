// This is a generated file - do not edit.
//
// Generated from model_types.proto.

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

import 'hardware_profile.pb.dart' as $1;
import 'model_types.pbenum.dart';
import 'thinking_tag_pattern.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'model_types.pbenum.dart';

class ModelInfoMetadata extends $pb.GeneratedMessage {
  factory ModelInfoMetadata({
    $core.String? description,
    $core.String? author,
    $core.String? license,
    $core.Iterable<$core.String>? tags,
    $core.String? version,
  }) {
    final result = create();
    if (description != null) result.description = description;
    if (author != null) result.author = author;
    if (license != null) result.license = license;
    if (tags != null) result.tags.addAll(tags);
    if (version != null) result.version = version;
    return result;
  }

  ModelInfoMetadata._();

  factory ModelInfoMetadata.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelInfoMetadata.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelInfoMetadata',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'description')
    ..aOS(2, _omitFieldNames ? '' : 'author')
    ..aOS(3, _omitFieldNames ? '' : 'license')
    ..pPS(4, _omitFieldNames ? '' : 'tags')
    ..aOS(5, _omitFieldNames ? '' : 'version')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelInfoMetadata clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelInfoMetadata copyWith(void Function(ModelInfoMetadata) updates) =>
      super.copyWith((message) => updates(message as ModelInfoMetadata))
          as ModelInfoMetadata;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelInfoMetadata create() => ModelInfoMetadata._();
  @$core.override
  ModelInfoMetadata createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelInfoMetadata getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelInfoMetadata>(create);
  static ModelInfoMetadata? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get description => $_getSZ(0);
  @$pb.TagNumber(1)
  set description($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDescription() => $_has(0);
  @$pb.TagNumber(1)
  void clearDescription() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get author => $_getSZ(1);
  @$pb.TagNumber(2)
  set author($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAuthor() => $_has(1);
  @$pb.TagNumber(2)
  void clearAuthor() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get license => $_getSZ(2);
  @$pb.TagNumber(3)
  set license($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLicense() => $_has(2);
  @$pb.TagNumber(3)
  void clearLicense() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<$core.String> get tags => $_getList(3);

  @$pb.TagNumber(5)
  $core.String get version => $_getSZ(4);
  @$pb.TagNumber(5)
  set version($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasVersion() => $_has(4);
  @$pb.TagNumber(5)
  void clearVersion() => $_clearField(5);
}

class ModelRuntimeCompatibility extends $pb.GeneratedMessage {
  factory ModelRuntimeCompatibility({
    $core.Iterable<InferenceFramework>? compatibleFrameworks,
    $core.Iterable<ModelFormat>? compatibleFormats,
  }) {
    final result = create();
    if (compatibleFrameworks != null)
      result.compatibleFrameworks.addAll(compatibleFrameworks);
    if (compatibleFormats != null)
      result.compatibleFormats.addAll(compatibleFormats);
    return result;
  }

  ModelRuntimeCompatibility._();

  factory ModelRuntimeCompatibility.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelRuntimeCompatibility.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelRuntimeCompatibility',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pc<InferenceFramework>(
        1, _omitFieldNames ? '' : 'compatibleFrameworks', $pb.PbFieldType.KE,
        valueOf: InferenceFramework.valueOf,
        enumValues: InferenceFramework.values,
        defaultEnumValue: InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED)
    ..pc<ModelFormat>(
        2, _omitFieldNames ? '' : 'compatibleFormats', $pb.PbFieldType.KE,
        valueOf: ModelFormat.valueOf,
        enumValues: ModelFormat.values,
        defaultEnumValue: ModelFormat.MODEL_FORMAT_UNSPECIFIED)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelRuntimeCompatibility clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelRuntimeCompatibility copyWith(
          void Function(ModelRuntimeCompatibility) updates) =>
      super.copyWith((message) => updates(message as ModelRuntimeCompatibility))
          as ModelRuntimeCompatibility;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelRuntimeCompatibility create() => ModelRuntimeCompatibility._();
  @$core.override
  ModelRuntimeCompatibility createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelRuntimeCompatibility getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelRuntimeCompatibility>(create);
  static ModelRuntimeCompatibility? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<InferenceFramework> get compatibleFrameworks => $_getList(0);

  @$pb.TagNumber(2)
  $pb.PbList<ModelFormat> get compatibleFormats => $_getList(1);
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
    $0.ThinkingTagPattern? thinkingPattern,
    ModelInfoMetadata? metadata,
    SingleFileArtifact? singleFile,
    ArchiveArtifact? archive,
    MultiFileArtifact? multiFile,
    $core.String? customStrategyId,
    $core.bool? builtIn,
    ModelArtifactType? artifactType,
    ExpectedModelFiles? expectedFiles,
    $1.AccelerationPreference? accelerationPreference,
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
    final result = create();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (category != null) result.category = category;
    if (format != null) result.format = format;
    if (framework != null) result.framework = framework;
    if (downloadUrl != null) result.downloadUrl = downloadUrl;
    if (localPath != null) result.localPath = localPath;
    if (downloadSizeBytes != null) result.downloadSizeBytes = downloadSizeBytes;
    if (contextLength != null) result.contextLength = contextLength;
    if (supportsThinking != null) result.supportsThinking = supportsThinking;
    if (supportsLora != null) result.supportsLora = supportsLora;
    if (description != null) result.description = description;
    if (source != null) result.source = source;
    if (createdAtUnixMs != null) result.createdAtUnixMs = createdAtUnixMs;
    if (updatedAtUnixMs != null) result.updatedAtUnixMs = updatedAtUnixMs;
    if (memoryRequiredBytes != null)
      result.memoryRequiredBytes = memoryRequiredBytes;
    if (checksumSha256 != null) result.checksumSha256 = checksumSha256;
    if (thinkingPattern != null) result.thinkingPattern = thinkingPattern;
    if (metadata != null) result.metadata = metadata;
    if (singleFile != null) result.singleFile = singleFile;
    if (archive != null) result.archive = archive;
    if (multiFile != null) result.multiFile = multiFile;
    if (customStrategyId != null) result.customStrategyId = customStrategyId;
    if (builtIn != null) result.builtIn = builtIn;
    if (artifactType != null) result.artifactType = artifactType;
    if (expectedFiles != null) result.expectedFiles = expectedFiles;
    if (accelerationPreference != null)
      result.accelerationPreference = accelerationPreference;
    if (routingPolicy != null) result.routingPolicy = routingPolicy;
    if (compatibility != null) result.compatibility = compatibility;
    if (preferredFramework != null)
      result.preferredFramework = preferredFramework;
    if (registryStatus != null) result.registryStatus = registryStatus;
    if (isDownloaded != null) result.isDownloaded = isDownloaded;
    if (isAvailable != null) result.isAvailable = isAvailable;
    if (lastUsedAtUnixMs != null) result.lastUsedAtUnixMs = lastUsedAtUnixMs;
    if (usageCount != null) result.usageCount = usageCount;
    if (syncPending != null) result.syncPending = syncPending;
    if (statusMessage != null) result.statusMessage = statusMessage;
    return result;
  }

  ModelInfo._();

  factory ModelInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ModelInfo_Artifact>
      _ModelInfo_ArtifactByTag = {
    20: ModelInfo_Artifact.singleFile,
    21: ModelInfo_Artifact.archive,
    22: ModelInfo_Artifact.multiFile,
    23: ModelInfo_Artifact.customStrategyId,
    24: ModelInfo_Artifact.builtIn,
    0: ModelInfo_Artifact.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..oo(0, [20, 21, 22, 23, 24])
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aE<ModelCategory>(3, _omitFieldNames ? '' : 'category',
        enumValues: ModelCategory.values)
    ..aE<ModelFormat>(4, _omitFieldNames ? '' : 'format',
        enumValues: ModelFormat.values)
    ..aE<InferenceFramework>(5, _omitFieldNames ? '' : 'framework',
        enumValues: InferenceFramework.values)
    ..aOS(6, _omitFieldNames ? '' : 'downloadUrl')
    ..aOS(7, _omitFieldNames ? '' : 'localPath')
    ..aInt64(8, _omitFieldNames ? '' : 'downloadSizeBytes')
    ..aI(9, _omitFieldNames ? '' : 'contextLength')
    ..aOB(10, _omitFieldNames ? '' : 'supportsThinking')
    ..aOB(11, _omitFieldNames ? '' : 'supportsLora')
    ..aOS(12, _omitFieldNames ? '' : 'description')
    ..aE<ModelSource>(13, _omitFieldNames ? '' : 'source',
        enumValues: ModelSource.values)
    ..aInt64(14, _omitFieldNames ? '' : 'createdAtUnixMs')
    ..aInt64(15, _omitFieldNames ? '' : 'updatedAtUnixMs')
    ..aInt64(16, _omitFieldNames ? '' : 'memoryRequiredBytes')
    ..aOS(17, _omitFieldNames ? '' : 'checksumSha256')
    ..aOM<$0.ThinkingTagPattern>(18, _omitFieldNames ? '' : 'thinkingPattern',
        subBuilder: $0.ThinkingTagPattern.create)
    ..aOM<ModelInfoMetadata>(19, _omitFieldNames ? '' : 'metadata',
        subBuilder: ModelInfoMetadata.create)
    ..aOM<SingleFileArtifact>(20, _omitFieldNames ? '' : 'singleFile',
        subBuilder: SingleFileArtifact.create)
    ..aOM<ArchiveArtifact>(21, _omitFieldNames ? '' : 'archive',
        subBuilder: ArchiveArtifact.create)
    ..aOM<MultiFileArtifact>(22, _omitFieldNames ? '' : 'multiFile',
        subBuilder: MultiFileArtifact.create)
    ..aOS(23, _omitFieldNames ? '' : 'customStrategyId')
    ..aOB(24, _omitFieldNames ? '' : 'builtIn')
    ..aE<ModelArtifactType>(25, _omitFieldNames ? '' : 'artifactType',
        enumValues: ModelArtifactType.values)
    ..aOM<ExpectedModelFiles>(26, _omitFieldNames ? '' : 'expectedFiles',
        subBuilder: ExpectedModelFiles.create)
    ..aE<$1.AccelerationPreference>(
        27, _omitFieldNames ? '' : 'accelerationPreference',
        enumValues: $1.AccelerationPreference.values)
    ..aE<RoutingPolicy>(28, _omitFieldNames ? '' : 'routingPolicy',
        enumValues: RoutingPolicy.values)
    ..aOM<ModelRuntimeCompatibility>(29, _omitFieldNames ? '' : 'compatibility',
        subBuilder: ModelRuntimeCompatibility.create)
    ..aE<InferenceFramework>(30, _omitFieldNames ? '' : 'preferredFramework',
        enumValues: InferenceFramework.values)
    ..aE<ModelRegistryStatus>(31, _omitFieldNames ? '' : 'registryStatus',
        enumValues: ModelRegistryStatus.values)
    ..aOB(32, _omitFieldNames ? '' : 'isDownloaded')
    ..aOB(33, _omitFieldNames ? '' : 'isAvailable')
    ..aInt64(34, _omitFieldNames ? '' : 'lastUsedAtUnixMs')
    ..aI(35, _omitFieldNames ? '' : 'usageCount')
    ..aOB(36, _omitFieldNames ? '' : 'syncPending')
    ..aOS(37, _omitFieldNames ? '' : 'statusMessage')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelInfo copyWith(void Function(ModelInfo) updates) =>
      super.copyWith((message) => updates(message as ModelInfo)) as ModelInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelInfo create() => ModelInfo._();
  @$core.override
  ModelInfo createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelInfo getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelInfo>(create);
  static ModelInfo? _defaultInstance;

  @$pb.TagNumber(20)
  @$pb.TagNumber(21)
  @$pb.TagNumber(22)
  @$pb.TagNumber(23)
  @$pb.TagNumber(24)
  ModelInfo_Artifact whichArtifact() =>
      _ModelInfo_ArtifactByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(20)
  @$pb.TagNumber(21)
  @$pb.TagNumber(22)
  @$pb.TagNumber(23)
  @$pb.TagNumber(24)
  void clearArtifact() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  ModelCategory get category => $_getN(2);
  @$pb.TagNumber(3)
  set category(ModelCategory value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasCategory() => $_has(2);
  @$pb.TagNumber(3)
  void clearCategory() => $_clearField(3);

  @$pb.TagNumber(4)
  ModelFormat get format => $_getN(3);
  @$pb.TagNumber(4)
  set format(ModelFormat value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasFormat() => $_has(3);
  @$pb.TagNumber(4)
  void clearFormat() => $_clearField(4);

  @$pb.TagNumber(5)
  InferenceFramework get framework => $_getN(4);
  @$pb.TagNumber(5)
  set framework(InferenceFramework value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasFramework() => $_has(4);
  @$pb.TagNumber(5)
  void clearFramework() => $_clearField(5);

  /// Portable URL/URI string for catalog metadata and download planning.
  /// SDK/platform adapters own native HTTP execution, authentication/session
  /// state, browser fetch handles, URLSession/background-transfer objects,
  /// and permission prompts.
  @$pb.TagNumber(6)
  $core.String get downloadUrl => $_getSZ(5);
  @$pb.TagNumber(6)
  set downloadUrl($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDownloadUrl() => $_has(5);
  @$pb.TagNumber(6)
  void clearDownloadUrl() => $_clearField(6);

  /// Stable path or URI string after platform adapters have normalized native
  /// file handles. Do not place Android SAF/content URI permissions, iOS
  /// security-scoped bookmarks, browser FileSystemHandle objects, or other
  /// OS-governed capabilities in this C++-owned metadata field.
  @$pb.TagNumber(7)
  $core.String get localPath => $_getSZ(6);
  @$pb.TagNumber(7)
  set localPath($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasLocalPath() => $_has(6);
  @$pb.TagNumber(7)
  void clearLocalPath() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get downloadSizeBytes => $_getI64(7);
  @$pb.TagNumber(8)
  set downloadSizeBytes($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasDownloadSizeBytes() => $_has(7);
  @$pb.TagNumber(8)
  void clearDownloadSizeBytes() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get contextLength => $_getIZ(8);
  @$pb.TagNumber(9)
  set contextLength($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasContextLength() => $_has(8);
  @$pb.TagNumber(9)
  void clearContextLength() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.bool get supportsThinking => $_getBF(9);
  @$pb.TagNumber(10)
  set supportsThinking($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(10)
  $core.bool hasSupportsThinking() => $_has(9);
  @$pb.TagNumber(10)
  void clearSupportsThinking() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.bool get supportsLora => $_getBF(10);
  @$pb.TagNumber(11)
  set supportsLora($core.bool value) => $_setBool(10, value);
  @$pb.TagNumber(11)
  $core.bool hasSupportsLora() => $_has(10);
  @$pb.TagNumber(11)
  void clearSupportsLora() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get description => $_getSZ(11);
  @$pb.TagNumber(12)
  set description($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasDescription() => $_has(11);
  @$pb.TagNumber(12)
  void clearDescription() => $_clearField(12);

  @$pb.TagNumber(13)
  ModelSource get source => $_getN(12);
  @$pb.TagNumber(13)
  set source(ModelSource value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasSource() => $_has(12);
  @$pb.TagNumber(13)
  void clearSource() => $_clearField(13);

  @$pb.TagNumber(14)
  $fixnum.Int64 get createdAtUnixMs => $_getI64(13);
  @$pb.TagNumber(14)
  set createdAtUnixMs($fixnum.Int64 value) => $_setInt64(13, value);
  @$pb.TagNumber(14)
  $core.bool hasCreatedAtUnixMs() => $_has(13);
  @$pb.TagNumber(14)
  void clearCreatedAtUnixMs() => $_clearField(14);

  @$pb.TagNumber(15)
  $fixnum.Int64 get updatedAtUnixMs => $_getI64(14);
  @$pb.TagNumber(15)
  set updatedAtUnixMs($fixnum.Int64 value) => $_setInt64(14, value);
  @$pb.TagNumber(15)
  $core.bool hasUpdatedAtUnixMs() => $_has(14);
  @$pb.TagNumber(15)
  void clearUpdatedAtUnixMs() => $_clearField(15);

  /// Separate from download_size_bytes: this is the estimated runtime RAM
  /// requirement used by compatibility checks and model selection UIs.
  @$pb.TagNumber(16)
  $fixnum.Int64 get memoryRequiredBytes => $_getI64(15);
  @$pb.TagNumber(16)
  set memoryRequiredBytes($fixnum.Int64 value) => $_setInt64(15, value);
  @$pb.TagNumber(16)
  $core.bool hasMemoryRequiredBytes() => $_has(15);
  @$pb.TagNumber(16)
  void clearMemoryRequiredBytes() => $_clearField(16);

  /// Lowercase hex SHA-256 checksum for the primary artifact. Per-file
  /// checksums for multi-file artifacts live on ModelFileDescriptor.
  @$pb.TagNumber(17)
  $core.String get checksumSha256 => $_getSZ(16);
  @$pb.TagNumber(17)
  set checksumSha256($core.String value) => $_setString(16, value);
  @$pb.TagNumber(17)
  $core.bool hasChecksumSha256() => $_has(16);
  @$pb.TagNumber(17)
  void clearChecksumSha256() => $_clearField(17);

  /// Thinking/reasoning metadata. `supports_thinking` remains the boolean
  /// capability flag; this optional pattern declares model-specific tags.
  @$pb.TagNumber(18)
  $0.ThinkingTagPattern get thinkingPattern => $_getN(17);
  @$pb.TagNumber(18)
  set thinkingPattern($0.ThinkingTagPattern value) => $_setField(18, value);
  @$pb.TagNumber(18)
  $core.bool hasThinkingPattern() => $_has(17);
  @$pb.TagNumber(18)
  void clearThinkingPattern() => $_clearField(18);
  @$pb.TagNumber(18)
  $0.ThinkingTagPattern ensureThinkingPattern() => $_ensure(17);

  /// Structured public catalog metadata. `description` (field 12) is kept for
  /// backward compatibility and should mirror metadata.description when both
  /// are populated.
  @$pb.TagNumber(19)
  ModelInfoMetadata get metadata => $_getN(18);
  @$pb.TagNumber(19)
  set metadata(ModelInfoMetadata value) => $_setField(19, value);
  @$pb.TagNumber(19)
  $core.bool hasMetadata() => $_has(18);
  @$pb.TagNumber(19)
  void clearMetadata() => $_clearField(19);
  @$pb.TagNumber(19)
  ModelInfoMetadata ensureMetadata() => $_ensure(18);

  @$pb.TagNumber(20)
  SingleFileArtifact get singleFile => $_getN(19);
  @$pb.TagNumber(20)
  set singleFile(SingleFileArtifact value) => $_setField(20, value);
  @$pb.TagNumber(20)
  $core.bool hasSingleFile() => $_has(19);
  @$pb.TagNumber(20)
  void clearSingleFile() => $_clearField(20);
  @$pb.TagNumber(20)
  SingleFileArtifact ensureSingleFile() => $_ensure(19);

  @$pb.TagNumber(21)
  ArchiveArtifact get archive => $_getN(20);
  @$pb.TagNumber(21)
  set archive(ArchiveArtifact value) => $_setField(21, value);
  @$pb.TagNumber(21)
  $core.bool hasArchive() => $_has(20);
  @$pb.TagNumber(21)
  void clearArchive() => $_clearField(21);
  @$pb.TagNumber(21)
  ArchiveArtifact ensureArchive() => $_ensure(20);

  @$pb.TagNumber(22)
  MultiFileArtifact get multiFile => $_getN(21);
  @$pb.TagNumber(22)
  set multiFile(MultiFileArtifact value) => $_setField(22, value);
  @$pb.TagNumber(22)
  $core.bool hasMultiFile() => $_has(21);
  @$pb.TagNumber(22)
  void clearMultiFile() => $_clearField(22);
  @$pb.TagNumber(22)
  MultiFileArtifact ensureMultiFile() => $_ensure(21);

  @$pb.TagNumber(23)
  $core.String get customStrategyId => $_getSZ(22);
  @$pb.TagNumber(23)
  set customStrategyId($core.String value) => $_setString(22, value);
  @$pb.TagNumber(23)
  $core.bool hasCustomStrategyId() => $_has(22);
  @$pb.TagNumber(23)
  void clearCustomStrategyId() => $_clearField(23);

  @$pb.TagNumber(24)
  $core.bool get builtIn => $_getBF(23);
  @$pb.TagNumber(24)
  set builtIn($core.bool value) => $_setBool(23, value);
  @$pb.TagNumber(24)
  $core.bool hasBuiltIn() => $_has(23);
  @$pb.TagNumber(24)
  void clearBuiltIn() => $_clearField(24);

  /// High-level artifact classification, complementary to the `artifact`
  /// oneof above. Allows catalog entries to carry a coarse type tag without
  /// resolving the full strategy variant.
  @$pb.TagNumber(25)
  ModelArtifactType get artifactType => $_getN(24);
  @$pb.TagNumber(25)
  set artifactType(ModelArtifactType value) => $_setField(25, value);
  @$pb.TagNumber(25)
  $core.bool hasArtifactType() => $_has(24);
  @$pb.TagNumber(25)
  void clearArtifactType() => $_clearField(25);

  /// Manifest of files that are expected on disk after fetch/extraction.
  @$pb.TagNumber(26)
  ExpectedModelFiles get expectedFiles => $_getN(25);
  @$pb.TagNumber(26)
  set expectedFiles(ExpectedModelFiles value) => $_setField(26, value);
  @$pb.TagNumber(26)
  $core.bool hasExpectedFiles() => $_has(25);
  @$pb.TagNumber(26)
  void clearExpectedFiles() => $_clearField(26);
  @$pb.TagNumber(26)
  ExpectedModelFiles ensureExpectedFiles() => $_ensure(25);

  /// Preferred hardware acceleration backend for this model.
  @$pb.TagNumber(27)
  $1.AccelerationPreference get accelerationPreference => $_getN(26);
  @$pb.TagNumber(27)
  set accelerationPreference($1.AccelerationPreference value) =>
      $_setField(27, value);
  @$pb.TagNumber(27)
  $core.bool hasAccelerationPreference() => $_has(26);
  @$pb.TagNumber(27)
  void clearAccelerationPreference() => $_clearField(27);

  /// Hybrid (on-device vs cloud) routing policy for this entry.
  @$pb.TagNumber(28)
  RoutingPolicy get routingPolicy => $_getN(27);
  @$pb.TagNumber(28)
  set routingPolicy(RoutingPolicy value) => $_setField(28, value);
  @$pb.TagNumber(28)
  $core.bool hasRoutingPolicy() => $_has(27);
  @$pb.TagNumber(28)
  void clearRoutingPolicy() => $_clearField(28);

  /// Framework/format compatibility declarations. `framework` (field 5) is
  /// the canonical/preferred runtime when no explicit preferred_framework is set.
  @$pb.TagNumber(29)
  ModelRuntimeCompatibility get compatibility => $_getN(28);
  @$pb.TagNumber(29)
  set compatibility(ModelRuntimeCompatibility value) => $_setField(29, value);
  @$pb.TagNumber(29)
  $core.bool hasCompatibility() => $_has(28);
  @$pb.TagNumber(29)
  void clearCompatibility() => $_clearField(29);
  @$pb.TagNumber(29)
  ModelRuntimeCompatibility ensureCompatibility() => $_ensure(28);

  @$pb.TagNumber(30)
  InferenceFramework get preferredFramework => $_getN(29);
  @$pb.TagNumber(30)
  set preferredFramework(InferenceFramework value) => $_setField(30, value);
  @$pb.TagNumber(30)
  $core.bool hasPreferredFramework() => $_has(29);
  @$pb.TagNumber(30)
  void clearPreferredFramework() => $_clearField(30);

  /// Durable registry state. Live byte progress belongs to
  /// download_service.DownloadProgress, not ModelInfo.
  @$pb.TagNumber(31)
  ModelRegistryStatus get registryStatus => $_getN(30);
  @$pb.TagNumber(31)
  set registryStatus(ModelRegistryStatus value) => $_setField(31, value);
  @$pb.TagNumber(31)
  $core.bool hasRegistryStatus() => $_has(30);
  @$pb.TagNumber(31)
  void clearRegistryStatus() => $_clearField(31);

  @$pb.TagNumber(32)
  $core.bool get isDownloaded => $_getBF(31);
  @$pb.TagNumber(32)
  set isDownloaded($core.bool value) => $_setBool(31, value);
  @$pb.TagNumber(32)
  $core.bool hasIsDownloaded() => $_has(31);
  @$pb.TagNumber(32)
  void clearIsDownloaded() => $_clearField(32);

  @$pb.TagNumber(33)
  $core.bool get isAvailable => $_getBF(32);
  @$pb.TagNumber(33)
  set isAvailable($core.bool value) => $_setBool(32, value);
  @$pb.TagNumber(33)
  $core.bool hasIsAvailable() => $_has(32);
  @$pb.TagNumber(33)
  void clearIsAvailable() => $_clearField(33);

  @$pb.TagNumber(34)
  $fixnum.Int64 get lastUsedAtUnixMs => $_getI64(33);
  @$pb.TagNumber(34)
  set lastUsedAtUnixMs($fixnum.Int64 value) => $_setInt64(33, value);
  @$pb.TagNumber(34)
  $core.bool hasLastUsedAtUnixMs() => $_has(33);
  @$pb.TagNumber(34)
  void clearLastUsedAtUnixMs() => $_clearField(34);

  @$pb.TagNumber(35)
  $core.int get usageCount => $_getIZ(34);
  @$pb.TagNumber(35)
  set usageCount($core.int value) => $_setSignedInt32(34, value);
  @$pb.TagNumber(35)
  $core.bool hasUsageCount() => $_has(34);
  @$pb.TagNumber(35)
  void clearUsageCount() => $_clearField(35);

  @$pb.TagNumber(36)
  $core.bool get syncPending => $_getBF(35);
  @$pb.TagNumber(36)
  set syncPending($core.bool value) => $_setBool(35, value);
  @$pb.TagNumber(36)
  $core.bool hasSyncPending() => $_has(35);
  @$pb.TagNumber(36)
  void clearSyncPending() => $_clearField(36);

  @$pb.TagNumber(37)
  $core.String get statusMessage => $_getSZ(36);
  @$pb.TagNumber(37)
  set statusMessage($core.String value) => $_setString(36, value);
  @$pb.TagNumber(37)
  $core.bool hasStatusMessage() => $_has(36);
  @$pb.TagNumber(37)
  void clearStatusMessage() => $_clearField(37);
}

/// Repeated model registry responses use this wrapper because protobuf cannot
/// serialize a bare repeated field as a top-level message.
class ModelInfoList extends $pb.GeneratedMessage {
  factory ModelInfoList({
    $core.Iterable<ModelInfo>? models,
  }) {
    final result = create();
    if (models != null) result.models.addAll(models);
    return result;
  }

  ModelInfoList._();

  factory ModelInfoList.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelInfoList.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelInfoList',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPM<ModelInfo>(1, _omitFieldNames ? '' : 'models',
        subBuilder: ModelInfo.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelInfoList clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelInfoList copyWith(void Function(ModelInfoList) updates) =>
      super.copyWith((message) => updates(message as ModelInfoList))
          as ModelInfoList;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelInfoList create() => ModelInfoList._();
  @$core.override
  ModelInfoList createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelInfoList getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelInfoList>(create);
  static ModelInfoList? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<ModelInfo> get models => $_getList(0);
}

class SingleFileArtifact extends $pb.GeneratedMessage {
  factory SingleFileArtifact({
    $core.Iterable<$core.String>? requiredPatterns,
    $core.Iterable<$core.String>? optionalPatterns,
    ExpectedModelFiles? expectedFiles,
  }) {
    final result = create();
    if (requiredPatterns != null)
      result.requiredPatterns.addAll(requiredPatterns);
    if (optionalPatterns != null)
      result.optionalPatterns.addAll(optionalPatterns);
    if (expectedFiles != null) result.expectedFiles = expectedFiles;
    return result;
  }

  SingleFileArtifact._();

  factory SingleFileArtifact.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SingleFileArtifact.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SingleFileArtifact',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'requiredPatterns')
    ..pPS(2, _omitFieldNames ? '' : 'optionalPatterns')
    ..aOM<ExpectedModelFiles>(3, _omitFieldNames ? '' : 'expectedFiles',
        subBuilder: ExpectedModelFiles.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SingleFileArtifact clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SingleFileArtifact copyWith(void Function(SingleFileArtifact) updates) =>
      super.copyWith((message) => updates(message as SingleFileArtifact))
          as SingleFileArtifact;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SingleFileArtifact create() => SingleFileArtifact._();
  @$core.override
  SingleFileArtifact createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SingleFileArtifact getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SingleFileArtifact>(create);
  static SingleFileArtifact? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get requiredPatterns => $_getList(0);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get optionalPatterns => $_getList(1);

  /// Full manifest form for SDK-local wrappers that attach expected files to
  /// a single-file artifact. The pattern fields above remain for existing
  /// generated consumers.
  @$pb.TagNumber(3)
  ExpectedModelFiles get expectedFiles => $_getN(2);
  @$pb.TagNumber(3)
  set expectedFiles(ExpectedModelFiles value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasExpectedFiles() => $_has(2);
  @$pb.TagNumber(3)
  void clearExpectedFiles() => $_clearField(3);
  @$pb.TagNumber(3)
  ExpectedModelFiles ensureExpectedFiles() => $_ensure(2);
}

class ArchiveArtifact extends $pb.GeneratedMessage {
  factory ArchiveArtifact({
    ArchiveType? type,
    ArchiveStructure? structure,
    $core.Iterable<$core.String>? requiredPatterns,
    $core.Iterable<$core.String>? optionalPatterns,
    ExpectedModelFiles? expectedFiles,
  }) {
    final result = create();
    if (type != null) result.type = type;
    if (structure != null) result.structure = structure;
    if (requiredPatterns != null)
      result.requiredPatterns.addAll(requiredPatterns);
    if (optionalPatterns != null)
      result.optionalPatterns.addAll(optionalPatterns);
    if (expectedFiles != null) result.expectedFiles = expectedFiles;
    return result;
  }

  ArchiveArtifact._();

  factory ArchiveArtifact.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ArchiveArtifact.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ArchiveArtifact',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<ArchiveType>(1, _omitFieldNames ? '' : 'type',
        enumValues: ArchiveType.values)
    ..aE<ArchiveStructure>(2, _omitFieldNames ? '' : 'structure',
        enumValues: ArchiveStructure.values)
    ..pPS(3, _omitFieldNames ? '' : 'requiredPatterns')
    ..pPS(4, _omitFieldNames ? '' : 'optionalPatterns')
    ..aOM<ExpectedModelFiles>(5, _omitFieldNames ? '' : 'expectedFiles',
        subBuilder: ExpectedModelFiles.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ArchiveArtifact clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ArchiveArtifact copyWith(void Function(ArchiveArtifact) updates) =>
      super.copyWith((message) => updates(message as ArchiveArtifact))
          as ArchiveArtifact;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ArchiveArtifact create() => ArchiveArtifact._();
  @$core.override
  ArchiveArtifact createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ArchiveArtifact getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ArchiveArtifact>(create);
  static ArchiveArtifact? _defaultInstance;

  @$pb.TagNumber(1)
  ArchiveType get type => $_getN(0);
  @$pb.TagNumber(1)
  set type(ArchiveType value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => $_clearField(1);

  @$pb.TagNumber(2)
  ArchiveStructure get structure => $_getN(1);
  @$pb.TagNumber(2)
  set structure(ArchiveStructure value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasStructure() => $_has(1);
  @$pb.TagNumber(2)
  void clearStructure() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<$core.String> get requiredPatterns => $_getList(2);

  @$pb.TagNumber(4)
  $pb.PbList<$core.String> get optionalPatterns => $_getList(3);

  /// Full manifest form for archive artifacts after extraction. Archive
  /// extraction policy is portable; native filesystem permissions and handles
  /// remain adapter-owned.
  @$pb.TagNumber(5)
  ExpectedModelFiles get expectedFiles => $_getN(4);
  @$pb.TagNumber(5)
  set expectedFiles(ExpectedModelFiles value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasExpectedFiles() => $_has(4);
  @$pb.TagNumber(5)
  void clearExpectedFiles() => $_clearField(5);
  @$pb.TagNumber(5)
  ExpectedModelFiles ensureExpectedFiles() => $_ensure(4);
}

class ModelFileDescriptor extends $pb.GeneratedMessage {
  factory ModelFileDescriptor({
    $core.String? url,
    $core.String? filename,
    $core.bool? isRequired,
    $fixnum.Int64? sizeBytes,
    $core.String? relativePath,
    $core.String? destinationPath,
    ModelFileRole? role,
    $core.String? localPath,
    $core.String? checksumSha256,
  }) {
    final result = create();
    if (url != null) result.url = url;
    if (filename != null) result.filename = filename;
    if (isRequired != null) result.isRequired = isRequired;
    if (sizeBytes != null) result.sizeBytes = sizeBytes;
    if (relativePath != null) result.relativePath = relativePath;
    if (destinationPath != null) result.destinationPath = destinationPath;
    if (role != null) result.role = role;
    if (localPath != null) result.localPath = localPath;
    if (checksumSha256 != null) result.checksumSha256 = checksumSha256;
    return result;
  }

  ModelFileDescriptor._();

  factory ModelFileDescriptor.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelFileDescriptor.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelFileDescriptor',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'url')
    ..aOS(2, _omitFieldNames ? '' : 'filename')
    ..aOB(3, _omitFieldNames ? '' : 'isRequired')
    ..aInt64(4, _omitFieldNames ? '' : 'sizeBytes')
    ..aOS(6, _omitFieldNames ? '' : 'relativePath')
    ..aOS(7, _omitFieldNames ? '' : 'destinationPath')
    ..aE<ModelFileRole>(8, _omitFieldNames ? '' : 'role',
        enumValues: ModelFileRole.values)
    ..aOS(9, _omitFieldNames ? '' : 'localPath')
    ..aOS(10, _omitFieldNames ? '' : 'checksumSha256')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelFileDescriptor clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelFileDescriptor copyWith(void Function(ModelFileDescriptor) updates) =>
      super.copyWith((message) => updates(message as ModelFileDescriptor))
          as ModelFileDescriptor;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelFileDescriptor create() => ModelFileDescriptor._();
  @$core.override
  ModelFileDescriptor createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelFileDescriptor getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelFileDescriptor>(create);
  static ModelFileDescriptor? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get url => $_getSZ(0);
  @$pb.TagNumber(1)
  set url($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUrl() => $_has(0);
  @$pb.TagNumber(1)
  void clearUrl() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get filename => $_getSZ(1);
  @$pb.TagNumber(2)
  set filename($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFilename() => $_has(1);
  @$pb.TagNumber(2)
  void clearFilename() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get isRequired => $_getBF(2);
  @$pb.TagNumber(3)
  set isRequired($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIsRequired() => $_has(2);
  @$pb.TagNumber(3)
  void clearIsRequired() => $_clearField(3);

  /// Extended descriptor fields (Flutter model_types.dart:~350,
  /// Swift ModelTypes.swift:~350). `is_required` (field 3) remains the
  /// canonical "required" flag — the documented `required` boolean from
  /// newer SDK sources maps onto it (default true, mirrored in Swift).
  @$pb.TagNumber(4)
  $fixnum.Int64 get sizeBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set sizeBytes($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSizeBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearSizeBytes() => $_clearField(4);

  /// Path fields used by SDK-local wrappers/catalogs. `filename` is the
  /// storage name for simple cases; relative_path/destination_path preserve
  /// directory layouts for archive and multi-file artifacts.
  @$pb.TagNumber(6)
  $core.String get relativePath => $_getSZ(4);
  @$pb.TagNumber(6)
  set relativePath($core.String value) => $_setString(4, value);
  @$pb.TagNumber(6)
  $core.bool hasRelativePath() => $_has(4);
  @$pb.TagNumber(6)
  void clearRelativePath() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get destinationPath => $_getSZ(5);
  @$pb.TagNumber(7)
  set destinationPath($core.String value) => $_setString(5, value);
  @$pb.TagNumber(7)
  $core.bool hasDestinationPath() => $_has(5);
  @$pb.TagNumber(7)
  void clearDestinationPath() => $_clearField(7);

  @$pb.TagNumber(8)
  ModelFileRole get role => $_getN(6);
  @$pb.TagNumber(8)
  set role(ModelFileRole value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasRole() => $_has(6);
  @$pb.TagNumber(8)
  void clearRole() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get localPath => $_getSZ(7);
  @$pb.TagNumber(9)
  set localPath($core.String value) => $_setString(7, value);
  @$pb.TagNumber(9)
  $core.bool hasLocalPath() => $_has(7);
  @$pb.TagNumber(9)
  void clearLocalPath() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get checksumSha256 => $_getSZ(8);
  @$pb.TagNumber(10)
  set checksumSha256($core.String value) => $_setString(8, value);
  @$pb.TagNumber(10)
  $core.bool hasChecksumSha256() => $_has(8);
  @$pb.TagNumber(10)
  void clearChecksumSha256() => $_clearField(10);
}

class MultiFileArtifact extends $pb.GeneratedMessage {
  factory MultiFileArtifact({
    $core.Iterable<ModelFileDescriptor>? files,
  }) {
    final result = create();
    if (files != null) result.files.addAll(files);
    return result;
  }

  MultiFileArtifact._();

  factory MultiFileArtifact.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MultiFileArtifact.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MultiFileArtifact',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPM<ModelFileDescriptor>(1, _omitFieldNames ? '' : 'files',
        subBuilder: ModelFileDescriptor.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MultiFileArtifact clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MultiFileArtifact copyWith(void Function(MultiFileArtifact) updates) =>
      super.copyWith((message) => updates(message as MultiFileArtifact))
          as MultiFileArtifact;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MultiFileArtifact create() => MultiFileArtifact._();
  @$core.override
  MultiFileArtifact createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MultiFileArtifact getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MultiFileArtifact>(create);
  static MultiFileArtifact? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<ModelFileDescriptor> get files => $_getList(0);
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
    final result = create();
    if (files != null) result.files.addAll(files);
    if (rootDirectory != null) result.rootDirectory = rootDirectory;
    if (requiredPatterns != null)
      result.requiredPatterns.addAll(requiredPatterns);
    if (optionalPatterns != null)
      result.optionalPatterns.addAll(optionalPatterns);
    if (description != null) result.description = description;
    return result;
  }

  ExpectedModelFiles._();

  factory ExpectedModelFiles.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ExpectedModelFiles.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ExpectedModelFiles',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPM<ModelFileDescriptor>(1, _omitFieldNames ? '' : 'files',
        subBuilder: ModelFileDescriptor.create)
    ..aOS(2, _omitFieldNames ? '' : 'rootDirectory')
    ..pPS(3, _omitFieldNames ? '' : 'requiredPatterns')
    ..pPS(4, _omitFieldNames ? '' : 'optionalPatterns')
    ..aOS(5, _omitFieldNames ? '' : 'description')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExpectedModelFiles clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExpectedModelFiles copyWith(void Function(ExpectedModelFiles) updates) =>
      super.copyWith((message) => updates(message as ExpectedModelFiles))
          as ExpectedModelFiles;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ExpectedModelFiles create() => ExpectedModelFiles._();
  @$core.override
  ExpectedModelFiles createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ExpectedModelFiles getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ExpectedModelFiles>(create);
  static ExpectedModelFiles? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<ModelFileDescriptor> get files => $_getList(0);

  @$pb.TagNumber(2)
  $core.String get rootDirectory => $_getSZ(1);
  @$pb.TagNumber(2)
  set rootDirectory($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRootDirectory() => $_has(1);
  @$pb.TagNumber(2)
  void clearRootDirectory() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<$core.String> get requiredPatterns => $_getList(2);

  @$pb.TagNumber(4)
  $pb.PbList<$core.String> get optionalPatterns => $_getList(3);

  @$pb.TagNumber(5)
  $core.String get description => $_getSZ(4);
  @$pb.TagNumber(5)
  set description($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDescription() => $_has(4);
  @$pb.TagNumber(5)
  void clearDescription() => $_clearField(5);
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
    ModelRegistryStatus? registryStatus,
  }) {
    final result = create();
    if (framework != null) result.framework = framework;
    if (category != null) result.category = category;
    if (format != null) result.format = format;
    if (downloadedOnly != null) result.downloadedOnly = downloadedOnly;
    if (availableOnly != null) result.availableOnly = availableOnly;
    if (maxSizeBytes != null) result.maxSizeBytes = maxSizeBytes;
    if (searchQuery != null) result.searchQuery = searchQuery;
    if (source != null) result.source = source;
    if (sortField != null) result.sortField = sortField;
    if (sortOrder != null) result.sortOrder = sortOrder;
    if (registryStatus != null) result.registryStatus = registryStatus;
    return result;
  }

  ModelQuery._();

  factory ModelQuery.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelQuery.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelQuery',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<InferenceFramework>(1, _omitFieldNames ? '' : 'framework',
        enumValues: InferenceFramework.values)
    ..aE<ModelCategory>(2, _omitFieldNames ? '' : 'category',
        enumValues: ModelCategory.values)
    ..aE<ModelFormat>(3, _omitFieldNames ? '' : 'format',
        enumValues: ModelFormat.values)
    ..aOB(4, _omitFieldNames ? '' : 'downloadedOnly')
    ..aOB(5, _omitFieldNames ? '' : 'availableOnly')
    ..aInt64(6, _omitFieldNames ? '' : 'maxSizeBytes')
    ..aOS(7, _omitFieldNames ? '' : 'searchQuery')
    ..aE<ModelSource>(8, _omitFieldNames ? '' : 'source',
        enumValues: ModelSource.values)
    ..aE<ModelQuerySortField>(9, _omitFieldNames ? '' : 'sortField',
        enumValues: ModelQuerySortField.values)
    ..aE<ModelQuerySortOrder>(10, _omitFieldNames ? '' : 'sortOrder',
        enumValues: ModelQuerySortOrder.values)
    ..aE<ModelRegistryStatus>(11, _omitFieldNames ? '' : 'registryStatus',
        enumValues: ModelRegistryStatus.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelQuery clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelQuery copyWith(void Function(ModelQuery) updates) =>
      super.copyWith((message) => updates(message as ModelQuery)) as ModelQuery;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelQuery create() => ModelQuery._();
  @$core.override
  ModelQuery createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelQuery getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelQuery>(create);
  static ModelQuery? _defaultInstance;

  @$pb.TagNumber(1)
  InferenceFramework get framework => $_getN(0);
  @$pb.TagNumber(1)
  set framework(InferenceFramework value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasFramework() => $_has(0);
  @$pb.TagNumber(1)
  void clearFramework() => $_clearField(1);

  @$pb.TagNumber(2)
  ModelCategory get category => $_getN(1);
  @$pb.TagNumber(2)
  set category(ModelCategory value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasCategory() => $_has(1);
  @$pb.TagNumber(2)
  void clearCategory() => $_clearField(2);

  @$pb.TagNumber(3)
  ModelFormat get format => $_getN(2);
  @$pb.TagNumber(3)
  set format(ModelFormat value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasFormat() => $_has(2);
  @$pb.TagNumber(3)
  void clearFormat() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get downloadedOnly => $_getBF(3);
  @$pb.TagNumber(4)
  set downloadedOnly($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDownloadedOnly() => $_has(3);
  @$pb.TagNumber(4)
  void clearDownloadedOnly() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get availableOnly => $_getBF(4);
  @$pb.TagNumber(5)
  set availableOnly($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAvailableOnly() => $_has(4);
  @$pb.TagNumber(5)
  void clearAvailableOnly() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get maxSizeBytes => $_getI64(5);
  @$pb.TagNumber(6)
  set maxSizeBytes($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMaxSizeBytes() => $_has(5);
  @$pb.TagNumber(6)
  void clearMaxSizeBytes() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get searchQuery => $_getSZ(6);
  @$pb.TagNumber(7)
  set searchQuery($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSearchQuery() => $_has(6);
  @$pb.TagNumber(7)
  void clearSearchQuery() => $_clearField(7);

  @$pb.TagNumber(8)
  ModelSource get source => $_getN(7);
  @$pb.TagNumber(8)
  set source(ModelSource value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasSource() => $_has(7);
  @$pb.TagNumber(8)
  void clearSource() => $_clearField(8);

  @$pb.TagNumber(9)
  ModelQuerySortField get sortField => $_getN(8);
  @$pb.TagNumber(9)
  set sortField(ModelQuerySortField value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasSortField() => $_has(8);
  @$pb.TagNumber(9)
  void clearSortField() => $_clearField(9);

  @$pb.TagNumber(10)
  ModelQuerySortOrder get sortOrder => $_getN(9);
  @$pb.TagNumber(10)
  set sortOrder(ModelQuerySortOrder value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasSortOrder() => $_has(9);
  @$pb.TagNumber(10)
  void clearSortOrder() => $_clearField(10);

  @$pb.TagNumber(11)
  ModelRegistryStatus get registryStatus => $_getN(10);
  @$pb.TagNumber(11)
  set registryStatus(ModelRegistryStatus value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasRegistryStatus() => $_has(10);
  @$pb.TagNumber(11)
  void clearRegistryStatus() => $_clearField(11);
}

class ModelRegistryRefreshRequest extends $pb.GeneratedMessage {
  factory ModelRegistryRefreshRequest({
    $core.bool? includeRemoteCatalog,
    $core.bool? rescanLocal,
    $core.bool? pruneOrphans,
    ModelQuery? query,
    $core.String? catalogUri,
    $core.bool? forceRefresh,
    $core.bool? includeDownloadedState,
  }) {
    final result = create();
    if (includeRemoteCatalog != null)
      result.includeRemoteCatalog = includeRemoteCatalog;
    if (rescanLocal != null) result.rescanLocal = rescanLocal;
    if (pruneOrphans != null) result.pruneOrphans = pruneOrphans;
    if (query != null) result.query = query;
    if (catalogUri != null) result.catalogUri = catalogUri;
    if (forceRefresh != null) result.forceRefresh = forceRefresh;
    if (includeDownloadedState != null)
      result.includeDownloadedState = includeDownloadedState;
    return result;
  }

  ModelRegistryRefreshRequest._();

  factory ModelRegistryRefreshRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelRegistryRefreshRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelRegistryRefreshRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'includeRemoteCatalog')
    ..aOB(2, _omitFieldNames ? '' : 'rescanLocal')
    ..aOB(3, _omitFieldNames ? '' : 'pruneOrphans')
    ..aOM<ModelQuery>(4, _omitFieldNames ? '' : 'query',
        subBuilder: ModelQuery.create)
    ..aOS(5, _omitFieldNames ? '' : 'catalogUri')
    ..aOB(6, _omitFieldNames ? '' : 'forceRefresh')
    ..aOB(7, _omitFieldNames ? '' : 'includeDownloadedState')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelRegistryRefreshRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelRegistryRefreshRequest copyWith(
          void Function(ModelRegistryRefreshRequest) updates) =>
      super.copyWith(
              (message) => updates(message as ModelRegistryRefreshRequest))
          as ModelRegistryRefreshRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelRegistryRefreshRequest create() =>
      ModelRegistryRefreshRequest._();
  @$core.override
  ModelRegistryRefreshRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelRegistryRefreshRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelRegistryRefreshRequest>(create);
  static ModelRegistryRefreshRequest? _defaultInstance;

  /// Fetch or merge a remote catalog through the platform/network adapter.
  @$pb.TagNumber(1)
  $core.bool get includeRemoteCatalog => $_getBF(0);
  @$pb.TagNumber(1)
  set includeRemoteCatalog($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIncludeRemoteCatalog() => $_has(0);
  @$pb.TagNumber(1)
  void clearIncludeRemoteCatalog() => $_clearField(1);

  /// Scan managed model directories and link valid on-disk artifacts.
  @$pb.TagNumber(2)
  $core.bool get rescanLocal => $_getBF(1);
  @$pb.TagNumber(2)
  set rescanLocal($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRescanLocal() => $_has(1);
  @$pb.TagNumber(2)
  void clearRescanLocal() => $_clearField(2);

  /// Clear downloaded/available state for registry rows whose files vanished.
  @$pb.TagNumber(3)
  $core.bool get pruneOrphans => $_getBF(2);
  @$pb.TagNumber(3)
  set pruneOrphans($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPruneOrphans() => $_has(2);
  @$pb.TagNumber(3)
  void clearPruneOrphans() => $_clearField(3);

  /// Optional post-refresh filter for the returned model list.
  @$pb.TagNumber(4)
  ModelQuery get query => $_getN(3);
  @$pb.TagNumber(4)
  set query(ModelQuery value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasQuery() => $_has(3);
  @$pb.TagNumber(4)
  void clearQuery() => $_clearField(4);
  @$pb.TagNumber(4)
  ModelQuery ensureQuery() => $_ensure(3);

  /// Portable catalog selector. Auth state, cookies, native HTTP clients, and
  /// background transfer handles are supplied by platform adapters.
  @$pb.TagNumber(5)
  $core.String get catalogUri => $_getSZ(4);
  @$pb.TagNumber(5)
  set catalogUri($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCatalogUri() => $_has(4);
  @$pb.TagNumber(5)
  void clearCatalogUri() => $_clearField(5);

  /// Ignore cached catalog metadata and force a fresh adapter-backed refresh.
  @$pb.TagNumber(6)
  $core.bool get forceRefresh => $_getBF(5);
  @$pb.TagNumber(6)
  set forceRefresh($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasForceRefresh() => $_has(5);
  @$pb.TagNumber(6)
  void clearForceRefresh() => $_clearField(6);

  /// Include local downloaded/available state reconciliation in the refresh.
  @$pb.TagNumber(7)
  $core.bool get includeDownloadedState => $_getBF(6);
  @$pb.TagNumber(7)
  set includeDownloadedState($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasIncludeDownloadedState() => $_has(6);
  @$pb.TagNumber(7)
  void clearIncludeDownloadedState() => $_clearField(7);
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
    $core.int? downloadedCount,
    $core.int? availableCount,
    $core.int? errorCount,
  }) {
    final result = create();
    if (success != null) result.success = success;
    if (models != null) result.models = models;
    if (registeredCount != null) result.registeredCount = registeredCount;
    if (updatedCount != null) result.updatedCount = updatedCount;
    if (discoveredCount != null) result.discoveredCount = discoveredCount;
    if (prunedCount != null) result.prunedCount = prunedCount;
    if (refreshedAtUnixMs != null) result.refreshedAtUnixMs = refreshedAtUnixMs;
    if (warnings != null) result.warnings.addAll(warnings);
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (downloadedCount != null) result.downloadedCount = downloadedCount;
    if (availableCount != null) result.availableCount = availableCount;
    if (errorCount != null) result.errorCount = errorCount;
    return result;
  }

  ModelRegistryRefreshResult._();

  factory ModelRegistryRefreshResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelRegistryRefreshResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelRegistryRefreshResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aOM<ModelInfoList>(2, _omitFieldNames ? '' : 'models',
        subBuilder: ModelInfoList.create)
    ..aI(3, _omitFieldNames ? '' : 'registeredCount')
    ..aI(4, _omitFieldNames ? '' : 'updatedCount')
    ..aI(5, _omitFieldNames ? '' : 'discoveredCount')
    ..aI(6, _omitFieldNames ? '' : 'prunedCount')
    ..aInt64(7, _omitFieldNames ? '' : 'refreshedAtUnixMs')
    ..pPS(8, _omitFieldNames ? '' : 'warnings')
    ..aOS(9, _omitFieldNames ? '' : 'errorMessage')
    ..aI(10, _omitFieldNames ? '' : 'downloadedCount')
    ..aI(11, _omitFieldNames ? '' : 'availableCount')
    ..aI(12, _omitFieldNames ? '' : 'errorCount')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelRegistryRefreshResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelRegistryRefreshResult copyWith(
          void Function(ModelRegistryRefreshResult) updates) =>
      super.copyWith(
              (message) => updates(message as ModelRegistryRefreshResult))
          as ModelRegistryRefreshResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelRegistryRefreshResult create() => ModelRegistryRefreshResult._();
  @$core.override
  ModelRegistryRefreshResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelRegistryRefreshResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelRegistryRefreshResult>(create);
  static ModelRegistryRefreshResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);

  @$pb.TagNumber(2)
  ModelInfoList get models => $_getN(1);
  @$pb.TagNumber(2)
  set models(ModelInfoList value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasModels() => $_has(1);
  @$pb.TagNumber(2)
  void clearModels() => $_clearField(2);
  @$pb.TagNumber(2)
  ModelInfoList ensureModels() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.int get registeredCount => $_getIZ(2);
  @$pb.TagNumber(3)
  set registeredCount($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRegisteredCount() => $_has(2);
  @$pb.TagNumber(3)
  void clearRegisteredCount() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get updatedCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set updatedCount($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasUpdatedCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearUpdatedCount() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get discoveredCount => $_getIZ(4);
  @$pb.TagNumber(5)
  set discoveredCount($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDiscoveredCount() => $_has(4);
  @$pb.TagNumber(5)
  void clearDiscoveredCount() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get prunedCount => $_getIZ(5);
  @$pb.TagNumber(6)
  set prunedCount($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPrunedCount() => $_has(5);
  @$pb.TagNumber(6)
  void clearPrunedCount() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get refreshedAtUnixMs => $_getI64(6);
  @$pb.TagNumber(7)
  set refreshedAtUnixMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasRefreshedAtUnixMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearRefreshedAtUnixMs() => $_clearField(7);

  @$pb.TagNumber(8)
  $pb.PbList<$core.String> get warnings => $_getList(7);

  @$pb.TagNumber(9)
  $core.String get errorMessage => $_getSZ(8);
  @$pb.TagNumber(9)
  set errorMessage($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasErrorMessage() => $_has(8);
  @$pb.TagNumber(9)
  void clearErrorMessage() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get downloadedCount => $_getIZ(9);
  @$pb.TagNumber(10)
  set downloadedCount($core.int value) => $_setSignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasDownloadedCount() => $_has(9);
  @$pb.TagNumber(10)
  void clearDownloadedCount() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.int get availableCount => $_getIZ(10);
  @$pb.TagNumber(11)
  set availableCount($core.int value) => $_setSignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasAvailableCount() => $_has(10);
  @$pb.TagNumber(11)
  void clearAvailableCount() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.int get errorCount => $_getIZ(11);
  @$pb.TagNumber(12)
  set errorCount($core.int value) => $_setSignedInt32(11, value);
  @$pb.TagNumber(12)
  $core.bool hasErrorCount() => $_has(11);
  @$pb.TagNumber(12)
  void clearErrorCount() => $_clearField(12);
}

class ModelListRequest extends $pb.GeneratedMessage {
  factory ModelListRequest({
    ModelQuery? query,
    $core.bool? includeCounts,
  }) {
    final result = create();
    if (query != null) result.query = query;
    if (includeCounts != null) result.includeCounts = includeCounts;
    return result;
  }

  ModelListRequest._();

  factory ModelListRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelListRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelListRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOM<ModelQuery>(1, _omitFieldNames ? '' : 'query',
        subBuilder: ModelQuery.create)
    ..aOB(2, _omitFieldNames ? '' : 'includeCounts')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelListRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelListRequest copyWith(void Function(ModelListRequest) updates) =>
      super.copyWith((message) => updates(message as ModelListRequest))
          as ModelListRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelListRequest create() => ModelListRequest._();
  @$core.override
  ModelListRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelListRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelListRequest>(create);
  static ModelListRequest? _defaultInstance;

  /// Set query.downloaded_only for downloaded-only lists.
  @$pb.TagNumber(1)
  ModelQuery get query => $_getN(0);
  @$pb.TagNumber(1)
  set query(ModelQuery value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasQuery() => $_has(0);
  @$pb.TagNumber(1)
  void clearQuery() => $_clearField(1);
  @$pb.TagNumber(1)
  ModelQuery ensureQuery() => $_ensure(0);

  /// Include denormalized counts in ModelListResult.
  @$pb.TagNumber(2)
  $core.bool get includeCounts => $_getBF(1);
  @$pb.TagNumber(2)
  set includeCounts($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIncludeCounts() => $_has(1);
  @$pb.TagNumber(2)
  void clearIncludeCounts() => $_clearField(2);
}

class ModelListResult extends $pb.GeneratedMessage {
  factory ModelListResult({
    $core.bool? success,
    ModelInfoList? models,
    $core.String? errorMessage,
    $core.int? totalCount,
    $core.int? downloadedCount,
    $core.int? availableCount,
    $core.int? filteredCount,
  }) {
    final result = create();
    if (success != null) result.success = success;
    if (models != null) result.models = models;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (totalCount != null) result.totalCount = totalCount;
    if (downloadedCount != null) result.downloadedCount = downloadedCount;
    if (availableCount != null) result.availableCount = availableCount;
    if (filteredCount != null) result.filteredCount = filteredCount;
    return result;
  }

  ModelListResult._();

  factory ModelListResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelListResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelListResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aOM<ModelInfoList>(2, _omitFieldNames ? '' : 'models',
        subBuilder: ModelInfoList.create)
    ..aOS(3, _omitFieldNames ? '' : 'errorMessage')
    ..aI(4, _omitFieldNames ? '' : 'totalCount')
    ..aI(5, _omitFieldNames ? '' : 'downloadedCount')
    ..aI(6, _omitFieldNames ? '' : 'availableCount')
    ..aI(7, _omitFieldNames ? '' : 'filteredCount')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelListResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelListResult copyWith(void Function(ModelListResult) updates) =>
      super.copyWith((message) => updates(message as ModelListResult))
          as ModelListResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelListResult create() => ModelListResult._();
  @$core.override
  ModelListResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelListResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelListResult>(create);
  static ModelListResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);

  @$pb.TagNumber(2)
  ModelInfoList get models => $_getN(1);
  @$pb.TagNumber(2)
  set models(ModelInfoList value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasModels() => $_has(1);
  @$pb.TagNumber(2)
  void clearModels() => $_clearField(2);
  @$pb.TagNumber(2)
  ModelInfoList ensureModels() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.String get errorMessage => $_getSZ(2);
  @$pb.TagNumber(3)
  set errorMessage($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasErrorMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearErrorMessage() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get totalCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set totalCount($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTotalCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalCount() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get downloadedCount => $_getIZ(4);
  @$pb.TagNumber(5)
  set downloadedCount($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDownloadedCount() => $_has(4);
  @$pb.TagNumber(5)
  void clearDownloadedCount() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get availableCount => $_getIZ(5);
  @$pb.TagNumber(6)
  set availableCount($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasAvailableCount() => $_has(5);
  @$pb.TagNumber(6)
  void clearAvailableCount() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get filteredCount => $_getIZ(6);
  @$pb.TagNumber(7)
  set filteredCount($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasFilteredCount() => $_has(6);
  @$pb.TagNumber(7)
  void clearFilteredCount() => $_clearField(7);
}

class ModelGetRequest extends $pb.GeneratedMessage {
  factory ModelGetRequest({
    $core.String? modelId,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    return result;
  }

  ModelGetRequest._();

  factory ModelGetRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelGetRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelGetRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelGetRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelGetRequest copyWith(void Function(ModelGetRequest) updates) =>
      super.copyWith((message) => updates(message as ModelGetRequest))
          as ModelGetRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelGetRequest create() => ModelGetRequest._();
  @$core.override
  ModelGetRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelGetRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelGetRequest>(create);
  static ModelGetRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);
}

class ModelGetResult extends $pb.GeneratedMessage {
  factory ModelGetResult({
    $core.bool? found,
    ModelInfo? model,
    $core.String? errorMessage,
  }) {
    final result = create();
    if (found != null) result.found = found;
    if (model != null) result.model = model;
    if (errorMessage != null) result.errorMessage = errorMessage;
    return result;
  }

  ModelGetResult._();

  factory ModelGetResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelGetResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelGetResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'found')
    ..aOM<ModelInfo>(2, _omitFieldNames ? '' : 'model',
        subBuilder: ModelInfo.create)
    ..aOS(3, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelGetResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelGetResult copyWith(void Function(ModelGetResult) updates) =>
      super.copyWith((message) => updates(message as ModelGetResult))
          as ModelGetResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelGetResult create() => ModelGetResult._();
  @$core.override
  ModelGetResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelGetResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelGetResult>(create);
  static ModelGetResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get found => $_getBF(0);
  @$pb.TagNumber(1)
  set found($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFound() => $_has(0);
  @$pb.TagNumber(1)
  void clearFound() => $_clearField(1);

  @$pb.TagNumber(2)
  ModelInfo get model => $_getN(1);
  @$pb.TagNumber(2)
  set model(ModelInfo value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasModel() => $_has(1);
  @$pb.TagNumber(2)
  void clearModel() => $_clearField(2);
  @$pb.TagNumber(2)
  ModelInfo ensureModel() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.String get errorMessage => $_getSZ(2);
  @$pb.TagNumber(3)
  set errorMessage($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasErrorMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearErrorMessage() => $_clearField(3);
}

class ModelImportRequest extends $pb.GeneratedMessage {
  factory ModelImportRequest({
    ModelInfo? model,
    $core.String? sourcePath,
    $core.bool? copyIntoManagedStorage,
    $core.bool? overwriteExisting,
    $core.Iterable<ModelFileDescriptor>? files,
    $core.bool? validateBeforeRegister,
  }) {
    final result = create();
    if (model != null) result.model = model;
    if (sourcePath != null) result.sourcePath = sourcePath;
    if (copyIntoManagedStorage != null)
      result.copyIntoManagedStorage = copyIntoManagedStorage;
    if (overwriteExisting != null) result.overwriteExisting = overwriteExisting;
    if (files != null) result.files.addAll(files);
    if (validateBeforeRegister != null)
      result.validateBeforeRegister = validateBeforeRegister;
    return result;
  }

  ModelImportRequest._();

  factory ModelImportRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelImportRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelImportRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOM<ModelInfo>(1, _omitFieldNames ? '' : 'model',
        subBuilder: ModelInfo.create)
    ..aOS(2, _omitFieldNames ? '' : 'sourcePath')
    ..aOB(3, _omitFieldNames ? '' : 'copyIntoManagedStorage')
    ..aOB(4, _omitFieldNames ? '' : 'overwriteExisting')
    ..pPM<ModelFileDescriptor>(5, _omitFieldNames ? '' : 'files',
        subBuilder: ModelFileDescriptor.create)
    ..aOB(6, _omitFieldNames ? '' : 'validateBeforeRegister')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelImportRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelImportRequest copyWith(void Function(ModelImportRequest) updates) =>
      super.copyWith((message) => updates(message as ModelImportRequest))
          as ModelImportRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelImportRequest create() => ModelImportRequest._();
  @$core.override
  ModelImportRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelImportRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelImportRequest>(create);
  static ModelImportRequest? _defaultInstance;

  /// Catalog metadata to register or merge. If absent, discovery may infer a
  /// minimal ModelInfo from the file name and detected format.
  @$pb.TagNumber(1)
  ModelInfo get model => $_getN(0);
  @$pb.TagNumber(1)
  set model(ModelInfo value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasModel() => $_has(0);
  @$pb.TagNumber(1)
  void clearModel() => $_clearField(1);
  @$pb.TagNumber(1)
  ModelInfo ensureModel() => $_ensure(0);

  /// Normalized path under platform control. Do not place transient OS file
  /// picker handles in this field; adapters should first copy/link/authorize
  /// them and provide a stable path visible to the C++ workflow.
  @$pb.TagNumber(2)
  $core.String get sourcePath => $_getSZ(1);
  @$pb.TagNumber(2)
  set sourcePath($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSourcePath() => $_has(1);
  @$pb.TagNumber(2)
  void clearSourcePath() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get copyIntoManagedStorage => $_getBF(2);
  @$pb.TagNumber(3)
  set copyIntoManagedStorage($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCopyIntoManagedStorage() => $_has(2);
  @$pb.TagNumber(3)
  void clearCopyIntoManagedStorage() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get overwriteExisting => $_getBF(3);
  @$pb.TagNumber(4)
  set overwriteExisting($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasOverwriteExisting() => $_has(3);
  @$pb.TagNumber(4)
  void clearOverwriteExisting() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<ModelFileDescriptor> get files => $_getList(4);

  /// Validate format, expected files, and checksums before registry mutation.
  @$pb.TagNumber(6)
  $core.bool get validateBeforeRegister => $_getBF(5);
  @$pb.TagNumber(6)
  set validateBeforeRegister($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasValidateBeforeRegister() => $_has(5);
  @$pb.TagNumber(6)
  void clearValidateBeforeRegister() => $_clearField(6);
}

class ModelImportResult extends $pb.GeneratedMessage {
  factory ModelImportResult({
    $core.bool? success,
    ModelInfo? model,
    $core.String? localPath,
    $fixnum.Int64? importedBytes,
    $core.Iterable<$core.String>? warnings,
    $core.String? errorMessage,
    $core.bool? registered,
    $core.bool? copiedIntoManagedStorage,
  }) {
    final result = create();
    if (success != null) result.success = success;
    if (model != null) result.model = model;
    if (localPath != null) result.localPath = localPath;
    if (importedBytes != null) result.importedBytes = importedBytes;
    if (warnings != null) result.warnings.addAll(warnings);
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (registered != null) result.registered = registered;
    if (copiedIntoManagedStorage != null)
      result.copiedIntoManagedStorage = copiedIntoManagedStorage;
    return result;
  }

  ModelImportResult._();

  factory ModelImportResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelImportResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelImportResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aOM<ModelInfo>(2, _omitFieldNames ? '' : 'model',
        subBuilder: ModelInfo.create)
    ..aOS(3, _omitFieldNames ? '' : 'localPath')
    ..aInt64(4, _omitFieldNames ? '' : 'importedBytes')
    ..pPS(5, _omitFieldNames ? '' : 'warnings')
    ..aOS(6, _omitFieldNames ? '' : 'errorMessage')
    ..aOB(7, _omitFieldNames ? '' : 'registered')
    ..aOB(8, _omitFieldNames ? '' : 'copiedIntoManagedStorage')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelImportResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelImportResult copyWith(void Function(ModelImportResult) updates) =>
      super.copyWith((message) => updates(message as ModelImportResult))
          as ModelImportResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelImportResult create() => ModelImportResult._();
  @$core.override
  ModelImportResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelImportResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelImportResult>(create);
  static ModelImportResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);

  @$pb.TagNumber(2)
  ModelInfo get model => $_getN(1);
  @$pb.TagNumber(2)
  set model(ModelInfo value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasModel() => $_has(1);
  @$pb.TagNumber(2)
  void clearModel() => $_clearField(2);
  @$pb.TagNumber(2)
  ModelInfo ensureModel() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.String get localPath => $_getSZ(2);
  @$pb.TagNumber(3)
  set localPath($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLocalPath() => $_has(2);
  @$pb.TagNumber(3)
  void clearLocalPath() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get importedBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set importedBytes($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasImportedBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearImportedBytes() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get warnings => $_getList(4);

  @$pb.TagNumber(6)
  $core.String get errorMessage => $_getSZ(5);
  @$pb.TagNumber(6)
  set errorMessage($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasErrorMessage() => $_has(5);
  @$pb.TagNumber(6)
  void clearErrorMessage() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get registered => $_getBF(6);
  @$pb.TagNumber(7)
  set registered($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasRegistered() => $_has(6);
  @$pb.TagNumber(7)
  void clearRegistered() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get copiedIntoManagedStorage => $_getBF(7);
  @$pb.TagNumber(8)
  set copiedIntoManagedStorage($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasCopiedIntoManagedStorage() => $_has(7);
  @$pb.TagNumber(8)
  void clearCopiedIntoManagedStorage() => $_clearField(8);
}

class ModelDiscoveryRequest extends $pb.GeneratedMessage {
  factory ModelDiscoveryRequest({
    $core.Iterable<$core.String>? searchRoots,
    $core.bool? recursive,
    $core.bool? linkDownloaded,
    $core.bool? purgeInvalid,
    ModelQuery? query,
    $core.bool? includeBuiltIn,
    $core.bool? includeUserImports,
  }) {
    final result = create();
    if (searchRoots != null) result.searchRoots.addAll(searchRoots);
    if (recursive != null) result.recursive = recursive;
    if (linkDownloaded != null) result.linkDownloaded = linkDownloaded;
    if (purgeInvalid != null) result.purgeInvalid = purgeInvalid;
    if (query != null) result.query = query;
    if (includeBuiltIn != null) result.includeBuiltIn = includeBuiltIn;
    if (includeUserImports != null)
      result.includeUserImports = includeUserImports;
    return result;
  }

  ModelDiscoveryRequest._();

  factory ModelDiscoveryRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelDiscoveryRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelDiscoveryRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'searchRoots')
    ..aOB(2, _omitFieldNames ? '' : 'recursive')
    ..aOB(3, _omitFieldNames ? '' : 'linkDownloaded')
    ..aOB(4, _omitFieldNames ? '' : 'purgeInvalid')
    ..aOM<ModelQuery>(5, _omitFieldNames ? '' : 'query',
        subBuilder: ModelQuery.create)
    ..aOB(6, _omitFieldNames ? '' : 'includeBuiltIn')
    ..aOB(7, _omitFieldNames ? '' : 'includeUserImports')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelDiscoveryRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelDiscoveryRequest copyWith(
          void Function(ModelDiscoveryRequest) updates) =>
      super.copyWith((message) => updates(message as ModelDiscoveryRequest))
          as ModelDiscoveryRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelDiscoveryRequest create() => ModelDiscoveryRequest._();
  @$core.override
  ModelDiscoveryRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelDiscoveryRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelDiscoveryRequest>(create);
  static ModelDiscoveryRequest? _defaultInstance;

  /// Platform adapters own permission and sandbox traversal. These are stable
  /// roots that C++ may inspect using registered filesystem callbacks.
  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get searchRoots => $_getList(0);

  @$pb.TagNumber(2)
  $core.bool get recursive => $_getBF(1);
  @$pb.TagNumber(2)
  set recursive($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRecursive() => $_has(1);
  @$pb.TagNumber(2)
  void clearRecursive() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get linkDownloaded => $_getBF(2);
  @$pb.TagNumber(3)
  set linkDownloaded($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLinkDownloaded() => $_has(2);
  @$pb.TagNumber(3)
  void clearLinkDownloaded() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get purgeInvalid => $_getBF(3);
  @$pb.TagNumber(4)
  set purgeInvalid($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPurgeInvalid() => $_has(3);
  @$pb.TagNumber(4)
  void clearPurgeInvalid() => $_clearField(4);

  @$pb.TagNumber(5)
  ModelQuery get query => $_getN(4);
  @$pb.TagNumber(5)
  set query(ModelQuery value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasQuery() => $_has(4);
  @$pb.TagNumber(5)
  void clearQuery() => $_clearField(5);
  @$pb.TagNumber(5)
  ModelQuery ensureQuery() => $_ensure(4);

  @$pb.TagNumber(6)
  $core.bool get includeBuiltIn => $_getBF(5);
  @$pb.TagNumber(6)
  set includeBuiltIn($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasIncludeBuiltIn() => $_has(5);
  @$pb.TagNumber(6)
  void clearIncludeBuiltIn() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get includeUserImports => $_getBF(6);
  @$pb.TagNumber(7)
  set includeUserImports($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasIncludeUserImports() => $_has(6);
  @$pb.TagNumber(7)
  void clearIncludeUserImports() => $_clearField(7);
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
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (localPath != null) result.localPath = localPath;
    if (matchedRegistry != null) result.matchedRegistry = matchedRegistry;
    if (model != null) result.model = model;
    if (sizeBytes != null) result.sizeBytes = sizeBytes;
    if (warnings != null) result.warnings.addAll(warnings);
    return result;
  }

  DiscoveredModel._();

  factory DiscoveredModel.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DiscoveredModel.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DiscoveredModel',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aOS(2, _omitFieldNames ? '' : 'localPath')
    ..aOB(3, _omitFieldNames ? '' : 'matchedRegistry')
    ..aOM<ModelInfo>(4, _omitFieldNames ? '' : 'model',
        subBuilder: ModelInfo.create)
    ..aInt64(5, _omitFieldNames ? '' : 'sizeBytes')
    ..pPS(6, _omitFieldNames ? '' : 'warnings')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiscoveredModel clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiscoveredModel copyWith(void Function(DiscoveredModel) updates) =>
      super.copyWith((message) => updates(message as DiscoveredModel))
          as DiscoveredModel;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiscoveredModel create() => DiscoveredModel._();
  @$core.override
  DiscoveredModel createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DiscoveredModel getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DiscoveredModel>(create);
  static DiscoveredModel? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get localPath => $_getSZ(1);
  @$pb.TagNumber(2)
  set localPath($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLocalPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearLocalPath() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get matchedRegistry => $_getBF(2);
  @$pb.TagNumber(3)
  set matchedRegistry($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMatchedRegistry() => $_has(2);
  @$pb.TagNumber(3)
  void clearMatchedRegistry() => $_clearField(3);

  @$pb.TagNumber(4)
  ModelInfo get model => $_getN(3);
  @$pb.TagNumber(4)
  set model(ModelInfo value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasModel() => $_has(3);
  @$pb.TagNumber(4)
  void clearModel() => $_clearField(4);
  @$pb.TagNumber(4)
  ModelInfo ensureModel() => $_ensure(3);

  @$pb.TagNumber(5)
  $fixnum.Int64 get sizeBytes => $_getI64(4);
  @$pb.TagNumber(5)
  set sizeBytes($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSizeBytes() => $_has(4);
  @$pb.TagNumber(5)
  void clearSizeBytes() => $_clearField(5);

  @$pb.TagNumber(6)
  $pb.PbList<$core.String> get warnings => $_getList(5);
}

class ModelDiscoveryResult extends $pb.GeneratedMessage {
  factory ModelDiscoveryResult({
    $core.bool? success,
    $core.Iterable<DiscoveredModel>? discoveredModels,
    $core.int? linkedCount,
    $core.int? purgedCount,
    $core.Iterable<$core.String>? warnings,
    $core.String? errorMessage,
    $core.int? scannedCount,
    $core.int? importedCount,
  }) {
    final result = create();
    if (success != null) result.success = success;
    if (discoveredModels != null)
      result.discoveredModels.addAll(discoveredModels);
    if (linkedCount != null) result.linkedCount = linkedCount;
    if (purgedCount != null) result.purgedCount = purgedCount;
    if (warnings != null) result.warnings.addAll(warnings);
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (scannedCount != null) result.scannedCount = scannedCount;
    if (importedCount != null) result.importedCount = importedCount;
    return result;
  }

  ModelDiscoveryResult._();

  factory ModelDiscoveryResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelDiscoveryResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelDiscoveryResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..pPM<DiscoveredModel>(2, _omitFieldNames ? '' : 'discoveredModels',
        subBuilder: DiscoveredModel.create)
    ..aI(3, _omitFieldNames ? '' : 'linkedCount')
    ..aI(4, _omitFieldNames ? '' : 'purgedCount')
    ..pPS(5, _omitFieldNames ? '' : 'warnings')
    ..aOS(6, _omitFieldNames ? '' : 'errorMessage')
    ..aI(7, _omitFieldNames ? '' : 'scannedCount')
    ..aI(8, _omitFieldNames ? '' : 'importedCount')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelDiscoveryResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelDiscoveryResult copyWith(void Function(ModelDiscoveryResult) updates) =>
      super.copyWith((message) => updates(message as ModelDiscoveryResult))
          as ModelDiscoveryResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelDiscoveryResult create() => ModelDiscoveryResult._();
  @$core.override
  ModelDiscoveryResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelDiscoveryResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelDiscoveryResult>(create);
  static ModelDiscoveryResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<DiscoveredModel> get discoveredModels => $_getList(1);

  @$pb.TagNumber(3)
  $core.int get linkedCount => $_getIZ(2);
  @$pb.TagNumber(3)
  set linkedCount($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLinkedCount() => $_has(2);
  @$pb.TagNumber(3)
  void clearLinkedCount() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get purgedCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set purgedCount($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPurgedCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearPurgedCount() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get warnings => $_getList(4);

  @$pb.TagNumber(6)
  $core.String get errorMessage => $_getSZ(5);
  @$pb.TagNumber(6)
  set errorMessage($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasErrorMessage() => $_has(5);
  @$pb.TagNumber(6)
  void clearErrorMessage() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get scannedCount => $_getIZ(6);
  @$pb.TagNumber(7)
  set scannedCount($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasScannedCount() => $_has(6);
  @$pb.TagNumber(7)
  void clearScannedCount() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get importedCount => $_getIZ(7);
  @$pb.TagNumber(8)
  set importedCount($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasImportedCount() => $_has(7);
  @$pb.TagNumber(8)
  void clearImportedCount() => $_clearField(8);
}

class ModelLoadRequest extends $pb.GeneratedMessage {
  factory ModelLoadRequest({
    $core.String? modelId,
    ModelCategory? category,
    InferenceFramework? framework,
    $core.bool? forceReload,
    $core.bool? validateAvailability,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (category != null) result.category = category;
    if (framework != null) result.framework = framework;
    if (forceReload != null) result.forceReload = forceReload;
    if (validateAvailability != null)
      result.validateAvailability = validateAvailability;
    return result;
  }

  ModelLoadRequest._();

  factory ModelLoadRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelLoadRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelLoadRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aE<ModelCategory>(2, _omitFieldNames ? '' : 'category',
        enumValues: ModelCategory.values)
    ..aE<InferenceFramework>(3, _omitFieldNames ? '' : 'framework',
        enumValues: InferenceFramework.values)
    ..aOB(4, _omitFieldNames ? '' : 'forceReload')
    ..aOB(5, _omitFieldNames ? '' : 'validateAvailability')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelLoadRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelLoadRequest copyWith(void Function(ModelLoadRequest) updates) =>
      super.copyWith((message) => updates(message as ModelLoadRequest))
          as ModelLoadRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelLoadRequest create() => ModelLoadRequest._();
  @$core.override
  ModelLoadRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelLoadRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelLoadRequest>(create);
  static ModelLoadRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  @$pb.TagNumber(2)
  ModelCategory get category => $_getN(1);
  @$pb.TagNumber(2)
  set category(ModelCategory value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasCategory() => $_has(1);
  @$pb.TagNumber(2)
  void clearCategory() => $_clearField(2);

  @$pb.TagNumber(3)
  InferenceFramework get framework => $_getN(2);
  @$pb.TagNumber(3)
  set framework(InferenceFramework value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasFramework() => $_has(2);
  @$pb.TagNumber(3)
  void clearFramework() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get forceReload => $_getBF(3);
  @$pb.TagNumber(4)
  set forceReload($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasForceReload() => $_has(3);
  @$pb.TagNumber(4)
  void clearForceReload() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get validateAvailability => $_getBF(4);
  @$pb.TagNumber(5)
  set validateAvailability($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasValidateAvailability() => $_has(4);
  @$pb.TagNumber(5)
  void clearValidateAvailability() => $_clearField(5);
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
    $core.Iterable<$core.String>? warnings,
    $core.bool? alreadyLoaded,
    $core.Iterable<ModelFileDescriptor>? resolvedArtifacts,
  }) {
    final result = create();
    if (success != null) result.success = success;
    if (modelId != null) result.modelId = modelId;
    if (category != null) result.category = category;
    if (framework != null) result.framework = framework;
    if (resolvedPath != null) result.resolvedPath = resolvedPath;
    if (loadedAtUnixMs != null) result.loadedAtUnixMs = loadedAtUnixMs;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (warnings != null) result.warnings.addAll(warnings);
    if (alreadyLoaded != null) result.alreadyLoaded = alreadyLoaded;
    if (resolvedArtifacts != null)
      result.resolvedArtifacts.addAll(resolvedArtifacts);
    return result;
  }

  ModelLoadResult._();

  factory ModelLoadResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelLoadResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelLoadResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..aE<ModelCategory>(3, _omitFieldNames ? '' : 'category',
        enumValues: ModelCategory.values)
    ..aE<InferenceFramework>(4, _omitFieldNames ? '' : 'framework',
        enumValues: InferenceFramework.values)
    ..aOS(5, _omitFieldNames ? '' : 'resolvedPath')
    ..aInt64(6, _omitFieldNames ? '' : 'loadedAtUnixMs')
    ..aOS(7, _omitFieldNames ? '' : 'errorMessage')
    ..pPS(8, _omitFieldNames ? '' : 'warnings')
    ..aOB(9, _omitFieldNames ? '' : 'alreadyLoaded')
    ..pPM<ModelFileDescriptor>(10, _omitFieldNames ? '' : 'resolvedArtifacts',
        subBuilder: ModelFileDescriptor.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelLoadResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelLoadResult copyWith(void Function(ModelLoadResult) updates) =>
      super.copyWith((message) => updates(message as ModelLoadResult))
          as ModelLoadResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelLoadResult create() => ModelLoadResult._();
  @$core.override
  ModelLoadResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelLoadResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelLoadResult>(create);
  static ModelLoadResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => $_clearField(2);

  @$pb.TagNumber(3)
  ModelCategory get category => $_getN(2);
  @$pb.TagNumber(3)
  set category(ModelCategory value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasCategory() => $_has(2);
  @$pb.TagNumber(3)
  void clearCategory() => $_clearField(3);

  @$pb.TagNumber(4)
  InferenceFramework get framework => $_getN(3);
  @$pb.TagNumber(4)
  set framework(InferenceFramework value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasFramework() => $_has(3);
  @$pb.TagNumber(4)
  void clearFramework() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get resolvedPath => $_getSZ(4);
  @$pb.TagNumber(5)
  set resolvedPath($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasResolvedPath() => $_has(4);
  @$pb.TagNumber(5)
  void clearResolvedPath() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get loadedAtUnixMs => $_getI64(5);
  @$pb.TagNumber(6)
  set loadedAtUnixMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLoadedAtUnixMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearLoadedAtUnixMs() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get errorMessage => $_getSZ(6);
  @$pb.TagNumber(7)
  set errorMessage($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasErrorMessage() => $_has(6);
  @$pb.TagNumber(7)
  void clearErrorMessage() => $_clearField(7);

  @$pb.TagNumber(8)
  $pb.PbList<$core.String> get warnings => $_getList(7);

  @$pb.TagNumber(9)
  $core.bool get alreadyLoaded => $_getBF(8);
  @$pb.TagNumber(9)
  set alreadyLoaded($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasAlreadyLoaded() => $_has(8);
  @$pb.TagNumber(9)
  void clearAlreadyLoaded() => $_clearField(9);

  /// Concrete artifacts selected by C++ model path resolution. The primary
  /// model entry mirrors resolved_path; companion entries carry explicit
  /// ModelFileRole values such as MODEL_FILE_ROLE_VISION_PROJECTOR.
  @$pb.TagNumber(10)
  $pb.PbList<ModelFileDescriptor> get resolvedArtifacts => $_getList(9);
}

class ModelUnloadRequest extends $pb.GeneratedMessage {
  factory ModelUnloadRequest({
    $core.String? modelId,
    ModelCategory? category,
    $core.bool? unloadAll,
    InferenceFramework? framework,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (category != null) result.category = category;
    if (unloadAll != null) result.unloadAll = unloadAll;
    if (framework != null) result.framework = framework;
    return result;
  }

  ModelUnloadRequest._();

  factory ModelUnloadRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelUnloadRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelUnloadRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aE<ModelCategory>(2, _omitFieldNames ? '' : 'category',
        enumValues: ModelCategory.values)
    ..aOB(3, _omitFieldNames ? '' : 'unloadAll')
    ..aE<InferenceFramework>(4, _omitFieldNames ? '' : 'framework',
        enumValues: InferenceFramework.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelUnloadRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelUnloadRequest copyWith(void Function(ModelUnloadRequest) updates) =>
      super.copyWith((message) => updates(message as ModelUnloadRequest))
          as ModelUnloadRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelUnloadRequest create() => ModelUnloadRequest._();
  @$core.override
  ModelUnloadRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelUnloadRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelUnloadRequest>(create);
  static ModelUnloadRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  @$pb.TagNumber(2)
  ModelCategory get category => $_getN(1);
  @$pb.TagNumber(2)
  set category(ModelCategory value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasCategory() => $_has(1);
  @$pb.TagNumber(2)
  void clearCategory() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get unloadAll => $_getBF(2);
  @$pb.TagNumber(3)
  set unloadAll($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasUnloadAll() => $_has(2);
  @$pb.TagNumber(3)
  void clearUnloadAll() => $_clearField(3);

  @$pb.TagNumber(4)
  InferenceFramework get framework => $_getN(3);
  @$pb.TagNumber(4)
  set framework(InferenceFramework value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasFramework() => $_has(3);
  @$pb.TagNumber(4)
  void clearFramework() => $_clearField(4);
}

class ModelUnloadResult extends $pb.GeneratedMessage {
  factory ModelUnloadResult({
    $core.bool? success,
    $core.Iterable<$core.String>? unloadedModelIds,
    $core.String? errorMessage,
    $fixnum.Int64? unloadedAtUnixMs,
    $core.Iterable<$core.String>? warnings,
  }) {
    final result = create();
    if (success != null) result.success = success;
    if (unloadedModelIds != null)
      result.unloadedModelIds.addAll(unloadedModelIds);
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (unloadedAtUnixMs != null) result.unloadedAtUnixMs = unloadedAtUnixMs;
    if (warnings != null) result.warnings.addAll(warnings);
    return result;
  }

  ModelUnloadResult._();

  factory ModelUnloadResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelUnloadResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelUnloadResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..pPS(2, _omitFieldNames ? '' : 'unloadedModelIds')
    ..aOS(3, _omitFieldNames ? '' : 'errorMessage')
    ..aInt64(4, _omitFieldNames ? '' : 'unloadedAtUnixMs')
    ..pPS(5, _omitFieldNames ? '' : 'warnings')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelUnloadResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelUnloadResult copyWith(void Function(ModelUnloadResult) updates) =>
      super.copyWith((message) => updates(message as ModelUnloadResult))
          as ModelUnloadResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelUnloadResult create() => ModelUnloadResult._();
  @$core.override
  ModelUnloadResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelUnloadResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelUnloadResult>(create);
  static ModelUnloadResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get unloadedModelIds => $_getList(1);

  @$pb.TagNumber(3)
  $core.String get errorMessage => $_getSZ(2);
  @$pb.TagNumber(3)
  set errorMessage($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasErrorMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearErrorMessage() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get unloadedAtUnixMs => $_getI64(3);
  @$pb.TagNumber(4)
  set unloadedAtUnixMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasUnloadedAtUnixMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearUnloadedAtUnixMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get warnings => $_getList(4);
}

class CurrentModelRequest extends $pb.GeneratedMessage {
  factory CurrentModelRequest({
    ModelCategory? category,
    InferenceFramework? framework,
    $core.bool? includeModelMetadata,
  }) {
    final result = create();
    if (category != null) result.category = category;
    if (framework != null) result.framework = framework;
    if (includeModelMetadata != null)
      result.includeModelMetadata = includeModelMetadata;
    return result;
  }

  CurrentModelRequest._();

  factory CurrentModelRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CurrentModelRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CurrentModelRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<ModelCategory>(1, _omitFieldNames ? '' : 'category',
        enumValues: ModelCategory.values)
    ..aE<InferenceFramework>(2, _omitFieldNames ? '' : 'framework',
        enumValues: InferenceFramework.values)
    ..aOB(3, _omitFieldNames ? '' : 'includeModelMetadata')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CurrentModelRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CurrentModelRequest copyWith(void Function(CurrentModelRequest) updates) =>
      super.copyWith((message) => updates(message as CurrentModelRequest))
          as CurrentModelRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CurrentModelRequest create() => CurrentModelRequest._();
  @$core.override
  CurrentModelRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CurrentModelRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CurrentModelRequest>(create);
  static CurrentModelRequest? _defaultInstance;

  @$pb.TagNumber(1)
  ModelCategory get category => $_getN(0);
  @$pb.TagNumber(1)
  set category(ModelCategory value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCategory() => $_has(0);
  @$pb.TagNumber(1)
  void clearCategory() => $_clearField(1);

  @$pb.TagNumber(2)
  InferenceFramework get framework => $_getN(1);
  @$pb.TagNumber(2)
  set framework(InferenceFramework value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasFramework() => $_has(1);
  @$pb.TagNumber(2)
  void clearFramework() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get includeModelMetadata => $_getBF(2);
  @$pb.TagNumber(3)
  set includeModelMetadata($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIncludeModelMetadata() => $_has(2);
  @$pb.TagNumber(3)
  void clearIncludeModelMetadata() => $_clearField(3);
}

class CurrentModelResult extends $pb.GeneratedMessage {
  factory CurrentModelResult({
    $core.String? modelId,
    ModelInfo? model,
    $fixnum.Int64? loadedAtUnixMs,
    $core.bool? found,
    $core.String? errorMessage,
    ModelCategory? category,
    InferenceFramework? framework,
    $core.String? resolvedPath,
    $core.Iterable<ModelFileDescriptor>? resolvedArtifacts,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (model != null) result.model = model;
    if (loadedAtUnixMs != null) result.loadedAtUnixMs = loadedAtUnixMs;
    if (found != null) result.found = found;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (category != null) result.category = category;
    if (framework != null) result.framework = framework;
    if (resolvedPath != null) result.resolvedPath = resolvedPath;
    if (resolvedArtifacts != null)
      result.resolvedArtifacts.addAll(resolvedArtifacts);
    return result;
  }

  CurrentModelResult._();

  factory CurrentModelResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CurrentModelResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CurrentModelResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..aOM<ModelInfo>(3, _omitFieldNames ? '' : 'model',
        subBuilder: ModelInfo.create)
    ..aInt64(4, _omitFieldNames ? '' : 'loadedAtUnixMs')
    ..aOB(5, _omitFieldNames ? '' : 'found')
    ..aOS(6, _omitFieldNames ? '' : 'errorMessage')
    ..aE<ModelCategory>(7, _omitFieldNames ? '' : 'category',
        enumValues: ModelCategory.values)
    ..aE<InferenceFramework>(8, _omitFieldNames ? '' : 'framework',
        enumValues: InferenceFramework.values)
    ..aOS(9, _omitFieldNames ? '' : 'resolvedPath')
    ..pPM<ModelFileDescriptor>(10, _omitFieldNames ? '' : 'resolvedArtifacts',
        subBuilder: ModelFileDescriptor.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CurrentModelResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CurrentModelResult copyWith(void Function(CurrentModelResult) updates) =>
      super.copyWith((message) => updates(message as CurrentModelResult))
          as CurrentModelResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CurrentModelResult create() => CurrentModelResult._();
  @$core.override
  CurrentModelResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CurrentModelResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CurrentModelResult>(create);
  static CurrentModelResult? _defaultInstance;

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(2)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(2)
  void clearModelId() => $_clearField(2);

  @$pb.TagNumber(3)
  ModelInfo get model => $_getN(1);
  @$pb.TagNumber(3)
  set model(ModelInfo value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasModel() => $_has(1);
  @$pb.TagNumber(3)
  void clearModel() => $_clearField(3);
  @$pb.TagNumber(3)
  ModelInfo ensureModel() => $_ensure(1);

  @$pb.TagNumber(4)
  $fixnum.Int64 get loadedAtUnixMs => $_getI64(2);
  @$pb.TagNumber(4)
  set loadedAtUnixMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(4)
  $core.bool hasLoadedAtUnixMs() => $_has(2);
  @$pb.TagNumber(4)
  void clearLoadedAtUnixMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get found => $_getBF(3);
  @$pb.TagNumber(5)
  set found($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(5)
  $core.bool hasFound() => $_has(3);
  @$pb.TagNumber(5)
  void clearFound() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get errorMessage => $_getSZ(4);
  @$pb.TagNumber(6)
  set errorMessage($core.String value) => $_setString(4, value);
  @$pb.TagNumber(6)
  $core.bool hasErrorMessage() => $_has(4);
  @$pb.TagNumber(6)
  void clearErrorMessage() => $_clearField(6);

  @$pb.TagNumber(7)
  ModelCategory get category => $_getN(5);
  @$pb.TagNumber(7)
  set category(ModelCategory value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasCategory() => $_has(5);
  @$pb.TagNumber(7)
  void clearCategory() => $_clearField(7);

  @$pb.TagNumber(8)
  InferenceFramework get framework => $_getN(6);
  @$pb.TagNumber(8)
  set framework(InferenceFramework value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasFramework() => $_has(6);
  @$pb.TagNumber(8)
  void clearFramework() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get resolvedPath => $_getSZ(7);
  @$pb.TagNumber(9)
  set resolvedPath($core.String value) => $_setString(7, value);
  @$pb.TagNumber(9)
  $core.bool hasResolvedPath() => $_has(7);
  @$pb.TagNumber(9)
  void clearResolvedPath() => $_clearField(9);

  @$pb.TagNumber(10)
  $pb.PbList<ModelFileDescriptor> get resolvedArtifacts => $_getList(8);
}

class ModelDeleteRequest extends $pb.GeneratedMessage {
  factory ModelDeleteRequest({
    $core.String? modelId,
    $core.bool? deleteFiles,
    $core.bool? unregister,
    $core.bool? unloadIfLoaded,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (deleteFiles != null) result.deleteFiles = deleteFiles;
    if (unregister != null) result.unregister = unregister;
    if (unloadIfLoaded != null) result.unloadIfLoaded = unloadIfLoaded;
    return result;
  }

  ModelDeleteRequest._();

  factory ModelDeleteRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelDeleteRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelDeleteRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aOB(2, _omitFieldNames ? '' : 'deleteFiles')
    ..aOB(3, _omitFieldNames ? '' : 'unregister')
    ..aOB(4, _omitFieldNames ? '' : 'unloadIfLoaded')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelDeleteRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelDeleteRequest copyWith(void Function(ModelDeleteRequest) updates) =>
      super.copyWith((message) => updates(message as ModelDeleteRequest))
          as ModelDeleteRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelDeleteRequest create() => ModelDeleteRequest._();
  @$core.override
  ModelDeleteRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelDeleteRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelDeleteRequest>(create);
  static ModelDeleteRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get deleteFiles => $_getBF(1);
  @$pb.TagNumber(2)
  set deleteFiles($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDeleteFiles() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeleteFiles() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get unregister => $_getBF(2);
  @$pb.TagNumber(3)
  set unregister($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasUnregister() => $_has(2);
  @$pb.TagNumber(3)
  void clearUnregister() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get unloadIfLoaded => $_getBF(3);
  @$pb.TagNumber(4)
  set unloadIfLoaded($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasUnloadIfLoaded() => $_has(3);
  @$pb.TagNumber(4)
  void clearUnloadIfLoaded() => $_clearField(4);
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
    $core.Iterable<$core.String>? warnings,
  }) {
    final result = create();
    if (success != null) result.success = success;
    if (modelId != null) result.modelId = modelId;
    if (deletedBytes != null) result.deletedBytes = deletedBytes;
    if (filesDeleted != null) result.filesDeleted = filesDeleted;
    if (registryUpdated != null) result.registryUpdated = registryUpdated;
    if (wasLoaded != null) result.wasLoaded = wasLoaded;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (warnings != null) result.warnings.addAll(warnings);
    return result;
  }

  ModelDeleteResult._();

  factory ModelDeleteResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelDeleteResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelDeleteResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..aInt64(3, _omitFieldNames ? '' : 'deletedBytes')
    ..aOB(4, _omitFieldNames ? '' : 'filesDeleted')
    ..aOB(5, _omitFieldNames ? '' : 'registryUpdated')
    ..aOB(6, _omitFieldNames ? '' : 'wasLoaded')
    ..aOS(7, _omitFieldNames ? '' : 'errorMessage')
    ..pPS(8, _omitFieldNames ? '' : 'warnings')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelDeleteResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelDeleteResult copyWith(void Function(ModelDeleteResult) updates) =>
      super.copyWith((message) => updates(message as ModelDeleteResult))
          as ModelDeleteResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelDeleteResult create() => ModelDeleteResult._();
  @$core.override
  ModelDeleteResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelDeleteResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelDeleteResult>(create);
  static ModelDeleteResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get deletedBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set deletedBytes($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDeletedBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearDeletedBytes() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get filesDeleted => $_getBF(3);
  @$pb.TagNumber(4)
  set filesDeleted($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFilesDeleted() => $_has(3);
  @$pb.TagNumber(4)
  void clearFilesDeleted() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get registryUpdated => $_getBF(4);
  @$pb.TagNumber(5)
  set registryUpdated($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRegistryUpdated() => $_has(4);
  @$pb.TagNumber(5)
  void clearRegistryUpdated() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get wasLoaded => $_getBF(5);
  @$pb.TagNumber(6)
  set wasLoaded($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasWasLoaded() => $_has(5);
  @$pb.TagNumber(6)
  void clearWasLoaded() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get errorMessage => $_getSZ(6);
  @$pb.TagNumber(7)
  set errorMessage($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasErrorMessage() => $_has(6);
  @$pb.TagNumber(7)
  void clearErrorMessage() => $_clearField(7);

  @$pb.TagNumber(8)
  $pb.PbList<$core.String> get warnings => $_getList(7);
}

/// ---------------------------------------------------------------------------
/// Compatibility check request/result. Mirrors the public SDK
/// `checkCompatibility(modelId)` calls (RN CompatibilityBridge,
/// Kotlin compat path, Web ModelManager). The platform adapter supplies
/// available_ram_bytes / available_storage_bytes; commons looks up the
/// registry entry, computes the compatibility verdict (canRun / canFit),
/// and returns reasons / suggested alternative model ids.
/// ---------------------------------------------------------------------------
class ModelCompatibilityRequest extends $pb.GeneratedMessage {
  factory ModelCompatibilityRequest({
    $core.String? modelId,
    $1.HardwareProfile? hardwareProfile,
    $fixnum.Int64? availableRamBytes,
    $fixnum.Int64? availableStorageBytes,
    $1.AccelerationPreference? acceleratorPreference,
    InferenceFramework? preferredFramework,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (hardwareProfile != null) result.hardwareProfile = hardwareProfile;
    if (availableRamBytes != null) result.availableRamBytes = availableRamBytes;
    if (availableStorageBytes != null)
      result.availableStorageBytes = availableStorageBytes;
    if (acceleratorPreference != null)
      result.acceleratorPreference = acceleratorPreference;
    if (preferredFramework != null)
      result.preferredFramework = preferredFramework;
    return result;
  }

  ModelCompatibilityRequest._();

  factory ModelCompatibilityRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelCompatibilityRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelCompatibilityRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aOM<$1.HardwareProfile>(2, _omitFieldNames ? '' : 'hardwareProfile',
        subBuilder: $1.HardwareProfile.create)
    ..aInt64(3, _omitFieldNames ? '' : 'availableRamBytes')
    ..aInt64(4, _omitFieldNames ? '' : 'availableStorageBytes')
    ..aE<$1.AccelerationPreference>(
        5, _omitFieldNames ? '' : 'acceleratorPreference',
        enumValues: $1.AccelerationPreference.values)
    ..aE<InferenceFramework>(6, _omitFieldNames ? '' : 'preferredFramework',
        enumValues: InferenceFramework.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelCompatibilityRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelCompatibilityRequest copyWith(
          void Function(ModelCompatibilityRequest) updates) =>
      super.copyWith((message) => updates(message as ModelCompatibilityRequest))
          as ModelCompatibilityRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelCompatibilityRequest create() => ModelCompatibilityRequest._();
  @$core.override
  ModelCompatibilityRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelCompatibilityRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelCompatibilityRequest>(create);
  static ModelCompatibilityRequest? _defaultInstance;

  /// Required. Model identifier to evaluate.
  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  /// Optional cached hardware profile from the platform adapter. If
  /// unset, commons will read whatever it has cached internally; the
  /// RAM/storage values below remain authoritative for the verdict.
  @$pb.TagNumber(2)
  $1.HardwareProfile get hardwareProfile => $_getN(1);
  @$pb.TagNumber(2)
  set hardwareProfile($1.HardwareProfile value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasHardwareProfile() => $_has(1);
  @$pb.TagNumber(2)
  void clearHardwareProfile() => $_clearField(2);
  @$pb.TagNumber(2)
  $1.HardwareProfile ensureHardwareProfile() => $_ensure(1);

  /// Available RAM in bytes (from device probe). 0 = unknown — commons
  /// will treat the requirement as satisfied.
  @$pb.TagNumber(3)
  $fixnum.Int64 get availableRamBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set availableRamBytes($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAvailableRamBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearAvailableRamBytes() => $_clearField(3);

  /// Available storage in bytes (from filesystem probe). 0 = unknown.
  @$pb.TagNumber(4)
  $fixnum.Int64 get availableStorageBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set availableStorageBytes($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAvailableStorageBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearAvailableStorageBytes() => $_clearField(4);

  /// Optional caller preferences (acceleration, framework). Reserved for
  /// future use; today's verdict is based on memory/storage alone.
  @$pb.TagNumber(5)
  $1.AccelerationPreference get acceleratorPreference => $_getN(4);
  @$pb.TagNumber(5)
  set acceleratorPreference($1.AccelerationPreference value) =>
      $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasAcceleratorPreference() => $_has(4);
  @$pb.TagNumber(5)
  void clearAcceleratorPreference() => $_clearField(5);

  @$pb.TagNumber(6)
  InferenceFramework get preferredFramework => $_getN(5);
  @$pb.TagNumber(6)
  set preferredFramework(InferenceFramework value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasPreferredFramework() => $_has(5);
  @$pb.TagNumber(6)
  void clearPreferredFramework() => $_clearField(6);
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
    $core.Iterable<$core.String>? suggestedAlternatives,
    $core.String? modelId,
    $core.int? errorCode,
    $core.String? errorMessage,
  }) {
    final result = create();
    if (isCompatible != null) result.isCompatible = isCompatible;
    if (canRun != null) result.canRun = canRun;
    if (canFit != null) result.canFit = canFit;
    if (requiredMemoryBytes != null)
      result.requiredMemoryBytes = requiredMemoryBytes;
    if (availableMemoryBytes != null)
      result.availableMemoryBytes = availableMemoryBytes;
    if (requiredStorageBytes != null)
      result.requiredStorageBytes = requiredStorageBytes;
    if (availableStorageBytes != null)
      result.availableStorageBytes = availableStorageBytes;
    if (reasons != null) result.reasons.addAll(reasons);
    if (suggestedAlternatives != null)
      result.suggestedAlternatives.addAll(suggestedAlternatives);
    if (modelId != null) result.modelId = modelId;
    if (errorCode != null) result.errorCode = errorCode;
    if (errorMessage != null) result.errorMessage = errorMessage;
    return result;
  }

  ModelCompatibilityResult._();

  factory ModelCompatibilityResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelCompatibilityResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelCompatibilityResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isCompatible')
    ..aOB(2, _omitFieldNames ? '' : 'canRun')
    ..aOB(3, _omitFieldNames ? '' : 'canFit')
    ..aInt64(4, _omitFieldNames ? '' : 'requiredMemoryBytes')
    ..aInt64(5, _omitFieldNames ? '' : 'availableMemoryBytes')
    ..aInt64(6, _omitFieldNames ? '' : 'requiredStorageBytes')
    ..aInt64(7, _omitFieldNames ? '' : 'availableStorageBytes')
    ..pPS(8, _omitFieldNames ? '' : 'reasons')
    ..pPS(9, _omitFieldNames ? '' : 'suggestedAlternatives')
    ..aOS(10, _omitFieldNames ? '' : 'modelId')
    ..aI(11, _omitFieldNames ? '' : 'errorCode')
    ..aOS(12, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelCompatibilityResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelCompatibilityResult copyWith(
          void Function(ModelCompatibilityResult) updates) =>
      super.copyWith((message) => updates(message as ModelCompatibilityResult))
          as ModelCompatibilityResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelCompatibilityResult create() => ModelCompatibilityResult._();
  @$core.override
  ModelCompatibilityResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelCompatibilityResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelCompatibilityResult>(create);
  static ModelCompatibilityResult? _defaultInstance;

  /// Mirrors the existing struct fields so SDKs can keep using the same
  /// field names; populated from rac_model_compatibility_result_t.
  @$pb.TagNumber(1)
  $core.bool get isCompatible => $_getBF(0);
  @$pb.TagNumber(1)
  set isCompatible($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIsCompatible() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsCompatible() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get canRun => $_getBF(1);
  @$pb.TagNumber(2)
  set canRun($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCanRun() => $_has(1);
  @$pb.TagNumber(2)
  void clearCanRun() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get canFit => $_getBF(2);
  @$pb.TagNumber(3)
  set canFit($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCanFit() => $_has(2);
  @$pb.TagNumber(3)
  void clearCanFit() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get requiredMemoryBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set requiredMemoryBytes($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRequiredMemoryBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearRequiredMemoryBytes() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get availableMemoryBytes => $_getI64(4);
  @$pb.TagNumber(5)
  set availableMemoryBytes($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAvailableMemoryBytes() => $_has(4);
  @$pb.TagNumber(5)
  void clearAvailableMemoryBytes() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get requiredStorageBytes => $_getI64(5);
  @$pb.TagNumber(6)
  set requiredStorageBytes($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasRequiredStorageBytes() => $_has(5);
  @$pb.TagNumber(6)
  void clearRequiredStorageBytes() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get availableStorageBytes => $_getI64(6);
  @$pb.TagNumber(7)
  set availableStorageBytes($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasAvailableStorageBytes() => $_has(6);
  @$pb.TagNumber(7)
  void clearAvailableStorageBytes() => $_clearField(7);

  /// Human-readable reasons populated when the verdict is negative
  /// (e.g. "insufficient RAM: requires X, available Y").
  @$pb.TagNumber(8)
  $pb.PbList<$core.String> get reasons => $_getList(7);

  /// Optional suggested alternative model ids that *would* be compatible.
  /// The current implementation leaves this empty; reserved for future
  /// compatibility-aware suggestions.
  @$pb.TagNumber(9)
  $pb.PbList<$core.String> get suggestedAlternatives => $_getList(8);

  /// Echo of the looked-up model id so callers can correlate batched
  /// checks with their request id.
  @$pb.TagNumber(10)
  $core.String get modelId => $_getSZ(9);
  @$pb.TagNumber(10)
  set modelId($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasModelId() => $_has(9);
  @$pb.TagNumber(10)
  void clearModelId() => $_clearField(10);

  /// Negative on failure; mirrors rac_result_t. Empty error_message on
  /// success.
  @$pb.TagNumber(11)
  $core.int get errorCode => $_getIZ(10);
  @$pb.TagNumber(11)
  set errorCode($core.int value) => $_setSignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasErrorCode() => $_has(10);
  @$pb.TagNumber(11)
  void clearErrorCode() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get errorMessage => $_getSZ(11);
  @$pb.TagNumber(12)
  set errorMessage($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasErrorMessage() => $_has(11);
  @$pb.TagNumber(12)
  void clearErrorMessage() => $_clearField(12);
}

/// ---------------------------------------------------------------------------
/// URL → ModelFormat inference request/result. Moves the Dart/Kotlin-side
/// URL-suffix heuristic (".gguf" → GGUF, ".onnx" → ONNX, ".tar.gz" wrapping an
/// inner format, ...) into commons so every SDK uses one implementation.
/// ---------------------------------------------------------------------------
class ModelFormatFromUrlRequest extends $pb.GeneratedMessage {
  factory ModelFormatFromUrlRequest({
    $core.String? url,
  }) {
    final result = create();
    if (url != null) result.url = url;
    return result;
  }

  ModelFormatFromUrlRequest._();

  factory ModelFormatFromUrlRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelFormatFromUrlRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelFormatFromUrlRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'url')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelFormatFromUrlRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelFormatFromUrlRequest copyWith(
          void Function(ModelFormatFromUrlRequest) updates) =>
      super.copyWith((message) => updates(message as ModelFormatFromUrlRequest))
          as ModelFormatFromUrlRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelFormatFromUrlRequest create() => ModelFormatFromUrlRequest._();
  @$core.override
  ModelFormatFromUrlRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelFormatFromUrlRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelFormatFromUrlRequest>(create);
  static ModelFormatFromUrlRequest? _defaultInstance;

  /// Portable URL or file path string. Only the trailing file-extension
  /// suffix is inspected; query strings and fragments are ignored.
  @$pb.TagNumber(1)
  $core.String get url => $_getSZ(0);
  @$pb.TagNumber(1)
  set url($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUrl() => $_has(0);
  @$pb.TagNumber(1)
  void clearUrl() => $_clearField(1);
}

class ModelFormatFromUrlResult extends $pb.GeneratedMessage {
  factory ModelFormatFromUrlResult({
    ModelFormat? format,
    ModelFormat? innerFormat,
  }) {
    final result = create();
    if (format != null) result.format = format;
    if (innerFormat != null) result.innerFormat = innerFormat;
    return result;
  }

  ModelFormatFromUrlResult._();

  factory ModelFormatFromUrlResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelFormatFromUrlResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelFormatFromUrlResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<ModelFormat>(1, _omitFieldNames ? '' : 'format',
        enumValues: ModelFormat.values)
    ..aE<ModelFormat>(2, _omitFieldNames ? '' : 'innerFormat',
        enumValues: ModelFormat.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelFormatFromUrlResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelFormatFromUrlResult copyWith(
          void Function(ModelFormatFromUrlResult) updates) =>
      super.copyWith((message) => updates(message as ModelFormatFromUrlResult))
          as ModelFormatFromUrlResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelFormatFromUrlResult create() => ModelFormatFromUrlResult._();
  @$core.override
  ModelFormatFromUrlResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelFormatFromUrlResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelFormatFromUrlResult>(create);
  static ModelFormatFromUrlResult? _defaultInstance;

  /// Primary detected format. For archive URLs this is the archive-wrapper
  /// format (for example MODEL_FORMAT_ZIP); the extracted model format is
  /// in inner_format below.
  @$pb.TagNumber(1)
  ModelFormat get format => $_getN(0);
  @$pb.TagNumber(1)
  set format(ModelFormat value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasFormat() => $_has(0);
  @$pb.TagNumber(1)
  void clearFormat() => $_clearField(1);

  /// For archive URLs, the format of the primary file inside the archive
  /// when it can be inferred from the URL (for example
  /// "whisper-base.en.tar.gz" → inner_format = MODEL_FORMAT_ONNX). When the
  /// archive content is unknown this is MODEL_FORMAT_UNSPECIFIED.
  @$pb.TagNumber(2)
  ModelFormat get innerFormat => $_getN(1);
  @$pb.TagNumber(2)
  set innerFormat(ModelFormat value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasInnerFormat() => $_has(1);
  @$pb.TagNumber(2)
  void clearInnerFormat() => $_clearField(2);
}

/// ---------------------------------------------------------------------------
/// URL → ModelArtifactType inference request/result. Replaces Dart
/// withInferredArtifact and Kotlin inferArtifactFields with a single commons
/// call.
/// ---------------------------------------------------------------------------
class ArtifactInferFromUrlRequest extends $pb.GeneratedMessage {
  factory ArtifactInferFromUrlRequest({
    $core.String? url,
    $core.String? modelId,
  }) {
    final result = create();
    if (url != null) result.url = url;
    if (modelId != null) result.modelId = modelId;
    return result;
  }

  ArtifactInferFromUrlRequest._();

  factory ArtifactInferFromUrlRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ArtifactInferFromUrlRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ArtifactInferFromUrlRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'url')
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ArtifactInferFromUrlRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ArtifactInferFromUrlRequest copyWith(
          void Function(ArtifactInferFromUrlRequest) updates) =>
      super.copyWith(
              (message) => updates(message as ArtifactInferFromUrlRequest))
          as ArtifactInferFromUrlRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ArtifactInferFromUrlRequest create() =>
      ArtifactInferFromUrlRequest._();
  @$core.override
  ArtifactInferFromUrlRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ArtifactInferFromUrlRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ArtifactInferFromUrlRequest>(create);
  static ArtifactInferFromUrlRequest? _defaultInstance;

  /// Portable URL or file path string.
  @$pb.TagNumber(1)
  $core.String get url => $_getSZ(0);
  @$pb.TagNumber(1)
  set url($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUrl() => $_has(0);
  @$pb.TagNumber(1)
  void clearUrl() => $_clearField(1);

  /// Optional model identifier. Commons does not consult the registry with
  /// this value today; it is carried for logging and telemetry only.
  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => $_clearField(2);
}

class ArtifactInferFromUrlResult extends $pb.GeneratedMessage {
  factory ArtifactInferFromUrlResult({
    ModelArtifactType? artifactType,
    ArchiveType? archiveType,
    ArchiveStructure? archiveStructure,
    $core.String? primaryRelpath,
    ModelFormat? innerFormat,
  }) {
    final result = create();
    if (artifactType != null) result.artifactType = artifactType;
    if (archiveType != null) result.archiveType = archiveType;
    if (archiveStructure != null) result.archiveStructure = archiveStructure;
    if (primaryRelpath != null) result.primaryRelpath = primaryRelpath;
    if (innerFormat != null) result.innerFormat = innerFormat;
    return result;
  }

  ArtifactInferFromUrlResult._();

  factory ArtifactInferFromUrlResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ArtifactInferFromUrlResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ArtifactInferFromUrlResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<ModelArtifactType>(1, _omitFieldNames ? '' : 'artifactType',
        enumValues: ModelArtifactType.values)
    ..aE<ArchiveType>(2, _omitFieldNames ? '' : 'archiveType',
        enumValues: ArchiveType.values)
    ..aE<ArchiveStructure>(3, _omitFieldNames ? '' : 'archiveStructure',
        enumValues: ArchiveStructure.values)
    ..aOS(4, _omitFieldNames ? '' : 'primaryRelpath')
    ..aE<ModelFormat>(5, _omitFieldNames ? '' : 'innerFormat',
        enumValues: ModelFormat.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ArtifactInferFromUrlResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ArtifactInferFromUrlResult copyWith(
          void Function(ArtifactInferFromUrlResult) updates) =>
      super.copyWith(
              (message) => updates(message as ArtifactInferFromUrlResult))
          as ArtifactInferFromUrlResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ArtifactInferFromUrlResult create() => ArtifactInferFromUrlResult._();
  @$core.override
  ArtifactInferFromUrlResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ArtifactInferFromUrlResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ArtifactInferFromUrlResult>(create);
  static ArtifactInferFromUrlResult? _defaultInstance;

  /// Inferred artifact-type classification.
  @$pb.TagNumber(1)
  ModelArtifactType get artifactType => $_getN(0);
  @$pb.TagNumber(1)
  set artifactType(ModelArtifactType value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasArtifactType() => $_has(0);
  @$pb.TagNumber(1)
  void clearArtifactType() => $_clearField(1);

  /// For archive artifacts, the concrete archive format (ZIP, TAR_GZ, ...).
  /// For single-file or directory artifacts this is
  /// ARCHIVE_TYPE_UNSPECIFIED.
  @$pb.TagNumber(2)
  ArchiveType get archiveType => $_getN(1);
  @$pb.TagNumber(2)
  set archiveType(ArchiveType value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasArchiveType() => $_has(1);
  @$pb.TagNumber(2)
  void clearArchiveType() => $_clearField(2);

  /// For archive artifacts the known or inferred internal structure after
  /// extraction. Defaults to ARCHIVE_STRUCTURE_UNKNOWN.
  @$pb.TagNumber(3)
  ArchiveStructure get archiveStructure => $_getN(2);
  @$pb.TagNumber(3)
  set archiveStructure(ArchiveStructure value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasArchiveStructure() => $_has(2);
  @$pb.TagNumber(3)
  void clearArchiveStructure() => $_clearField(3);

  /// When the URL suggests an archive wrapping a known primary file (for
  /// example a Whisper model bundle containing encoder.onnx), this field
  /// carries the relative path inside the archive when it can be inferred.
  /// Empty otherwise.
  @$pb.TagNumber(4)
  $core.String get primaryRelpath => $_getSZ(3);
  @$pb.TagNumber(4)
  set primaryRelpath($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPrimaryRelpath() => $_has(3);
  @$pb.TagNumber(4)
  void clearPrimaryRelpath() => $_clearField(4);

  /// Inner file format for archive artifacts. MODEL_FORMAT_UNSPECIFIED when
  /// the archive contents are unknown.
  @$pb.TagNumber(5)
  ModelFormat get innerFormat => $_getN(4);
  @$pb.TagNumber(5)
  set innerFormat(ModelFormat value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasInnerFormat() => $_has(4);
  @$pb.TagNumber(5)
  void clearInnerFormat() => $_clearField(5);
}

/// ---------------------------------------------------------------------------
/// FetchAssignments request/result. Replaces the JSON shim
/// racModelRegistryFetchAssignments and the Web SDK's offline-friendly
/// fetchModelAssignments() entry point. The platform adapter owns HTTP
/// transport; commons consumes the cached / fetched entries and returns a
/// canonical proto byte payload.
/// ---------------------------------------------------------------------------
class ModelRegistryFetchAssignmentsRequest extends $pb.GeneratedMessage {
  factory ModelRegistryFetchAssignmentsRequest({
    $core.String? deviceId,
    SDKEnvironment? environment,
    $core.bool? forceRefresh,
  }) {
    final result = create();
    if (deviceId != null) result.deviceId = deviceId;
    if (environment != null) result.environment = environment;
    if (forceRefresh != null) result.forceRefresh = forceRefresh;
    return result;
  }

  ModelRegistryFetchAssignmentsRequest._();

  factory ModelRegistryFetchAssignmentsRequest.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelRegistryFetchAssignmentsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelRegistryFetchAssignmentsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'deviceId')
    ..aE<SDKEnvironment>(2, _omitFieldNames ? '' : 'environment',
        enumValues: SDKEnvironment.values)
    ..aOB(3, _omitFieldNames ? '' : 'forceRefresh')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelRegistryFetchAssignmentsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelRegistryFetchAssignmentsRequest copyWith(
          void Function(ModelRegistryFetchAssignmentsRequest) updates) =>
      super.copyWith((message) =>
              updates(message as ModelRegistryFetchAssignmentsRequest))
          as ModelRegistryFetchAssignmentsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelRegistryFetchAssignmentsRequest create() =>
      ModelRegistryFetchAssignmentsRequest._();
  @$core.override
  ModelRegistryFetchAssignmentsRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelRegistryFetchAssignmentsRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          ModelRegistryFetchAssignmentsRequest>(create);
  static ModelRegistryFetchAssignmentsRequest? _defaultInstance;

  /// Optional device identifier (forwarded to the platform adapter for
  /// any auth headers it needs). May be empty when callers rely on
  /// adapter-side auth state alone.
  @$pb.TagNumber(1)
  $core.String get deviceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set deviceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => $_clearField(1);

  /// Optional environment selector; commons does not branch on this
  /// value today, but it is preserved for adapter routing and telemetry.
  @$pb.TagNumber(2)
  SDKEnvironment get environment => $_getN(1);
  @$pb.TagNumber(2)
  set environment(SDKEnvironment value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasEnvironment() => $_has(1);
  @$pb.TagNumber(2)
  void clearEnvironment() => $_clearField(2);

  /// Bypass the assignment cache and force a fresh fetch.
  @$pb.TagNumber(3)
  $core.bool get forceRefresh => $_getBF(2);
  @$pb.TagNumber(3)
  set forceRefresh($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasForceRefresh() => $_has(2);
  @$pb.TagNumber(3)
  void clearForceRefresh() => $_clearField(3);
}

class ModelRegistryFetchAssignmentsResult extends $pb.GeneratedMessage {
  factory ModelRegistryFetchAssignmentsResult({
    $core.bool? success,
    ModelInfoList? models,
    $core.int? modelCount,
    $fixnum.Int64? fetchedAtUnixMs,
    $core.int? errorCode,
    $core.String? errorMessage,
  }) {
    final result = create();
    if (success != null) result.success = success;
    if (models != null) result.models = models;
    if (modelCount != null) result.modelCount = modelCount;
    if (fetchedAtUnixMs != null) result.fetchedAtUnixMs = fetchedAtUnixMs;
    if (errorCode != null) result.errorCode = errorCode;
    if (errorMessage != null) result.errorMessage = errorMessage;
    return result;
  }

  ModelRegistryFetchAssignmentsResult._();

  factory ModelRegistryFetchAssignmentsResult.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelRegistryFetchAssignmentsResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelRegistryFetchAssignmentsResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aOM<ModelInfoList>(2, _omitFieldNames ? '' : 'models',
        subBuilder: ModelInfoList.create)
    ..aI(3, _omitFieldNames ? '' : 'modelCount')
    ..aInt64(4, _omitFieldNames ? '' : 'fetchedAtUnixMs')
    ..aI(5, _omitFieldNames ? '' : 'errorCode')
    ..aOS(6, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelRegistryFetchAssignmentsResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelRegistryFetchAssignmentsResult copyWith(
          void Function(ModelRegistryFetchAssignmentsResult) updates) =>
      super.copyWith((message) =>
              updates(message as ModelRegistryFetchAssignmentsResult))
          as ModelRegistryFetchAssignmentsResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelRegistryFetchAssignmentsResult create() =>
      ModelRegistryFetchAssignmentsResult._();
  @$core.override
  ModelRegistryFetchAssignmentsResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelRegistryFetchAssignmentsResult getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          ModelRegistryFetchAssignmentsResult>(create);
  static ModelRegistryFetchAssignmentsResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);

  @$pb.TagNumber(2)
  ModelInfoList get models => $_getN(1);
  @$pb.TagNumber(2)
  set models(ModelInfoList value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasModels() => $_has(1);
  @$pb.TagNumber(2)
  void clearModels() => $_clearField(2);
  @$pb.TagNumber(2)
  ModelInfoList ensureModels() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.int get modelCount => $_getIZ(2);
  @$pb.TagNumber(3)
  set modelCount($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasModelCount() => $_has(2);
  @$pb.TagNumber(3)
  void clearModelCount() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get fetchedAtUnixMs => $_getI64(3);
  @$pb.TagNumber(4)
  set fetchedAtUnixMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFetchedAtUnixMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearFetchedAtUnixMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get errorCode => $_getIZ(4);
  @$pb.TagNumber(5)
  set errorCode($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasErrorCode() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorCode() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get errorMessage => $_getSZ(5);
  @$pb.TagNumber(6)
  set errorMessage($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasErrorMessage() => $_has(5);
  @$pb.TagNumber(6)
  void clearErrorMessage() => $_clearField(6);
}

/// ---------------------------------------------------------------------------
/// Inputs for the canonical RAModelInfo factory. Replaces Swift's
/// `RAModelInfo.make(...)` ~370 LOC of field-defaulting and artifact-inference
/// logic with a commons-owned implementation. Commons fills 18 ModelInfo fields
/// (id, name, category/format/framework defaults, context-length defaults,
/// thinking gating + default pattern, artifact inference, source mark,
/// timestamps, and is_downloaded probe).
/// ---------------------------------------------------------------------------
class ModelInfoMakeRequest extends $pb.GeneratedMessage {
  factory ModelInfoMakeRequest({
    $core.String? url,
    $core.String? name,
    InferenceFramework? framework,
    ModelCategory? category,
    ModelSource? source,
  }) {
    final result = create();
    if (url != null) result.url = url;
    if (name != null) result.name = name;
    if (framework != null) result.framework = framework;
    if (category != null) result.category = category;
    if (source != null) result.source = source;
    return result;
  }

  ModelInfoMakeRequest._();

  factory ModelInfoMakeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelInfoMakeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelInfoMakeRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'url')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aE<InferenceFramework>(3, _omitFieldNames ? '' : 'framework',
        enumValues: InferenceFramework.values)
    ..aE<ModelCategory>(4, _omitFieldNames ? '' : 'category',
        enumValues: ModelCategory.values)
    ..aE<ModelSource>(5, _omitFieldNames ? '' : 'source',
        enumValues: ModelSource.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelInfoMakeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelInfoMakeRequest copyWith(void Function(ModelInfoMakeRequest) updates) =>
      super.copyWith((message) => updates(message as ModelInfoMakeRequest))
          as ModelInfoMakeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelInfoMakeRequest create() => ModelInfoMakeRequest._();
  @$core.override
  ModelInfoMakeRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelInfoMakeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelInfoMakeRequest>(create);
  static ModelInfoMakeRequest? _defaultInstance;

  /// Required. Download URL or file path. Used both as the metadata field
  /// and as input to artifact-type inference (zip/tar.gz/tgz/... → archive,
  /// anything else → single_file).
  @$pb.TagNumber(1)
  $core.String get url => $_getSZ(0);
  @$pb.TagNumber(1)
  set url($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUrl() => $_has(0);
  @$pb.TagNumber(1)
  void clearUrl() => $_clearField(1);

  /// Optional human-readable name. When empty commons derives it from the
  /// URL via rac_model_generate_name() (replaces underscores/dashes with
  /// spaces).
  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  /// Optional inference framework. UNSPECIFIED triggers detection from the
  /// URL extension; commons looks up the format and maps to a default
  /// framework via rac_model_detect_framework_from_format().
  @$pb.TagNumber(3)
  InferenceFramework get framework => $_getN(2);
  @$pb.TagNumber(3)
  set framework(InferenceFramework value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasFramework() => $_has(2);
  @$pb.TagNumber(3)
  void clearFramework() => $_clearField(3);

  /// Optional category. UNSPECIFIED falls back to the framework default
  /// (rac_model_category_from_framework()).
  @$pb.TagNumber(4)
  ModelCategory get category => $_getN(3);
  @$pb.TagNumber(4)
  set category(ModelCategory value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasCategory() => $_has(3);
  @$pb.TagNumber(4)
  void clearCategory() => $_clearField(4);

  /// Optional source. UNSPECIFIED is treated as MODEL_SOURCE_REMOTE.
  @$pb.TagNumber(5)
  ModelSource get source => $_getN(4);
  @$pb.TagNumber(5)
  set source(ModelSource value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasSource() => $_has(4);
  @$pb.TagNumber(5)
  void clearSource() => $_clearField(5);
}

/// ---------------------------------------------------------------------------
/// Inputs for the canonical "register a model from a URL" entry point.
/// Composes ModelInfoMakeRequest with the existing registry save path
/// so SDKs replace ~60 LOC of build-and-save glue with a single ABI call.
/// Produces the saved ModelInfo (matches rac_model_registry_register_proto_buffer
/// shape).
/// ---------------------------------------------------------------------------
class RegisterModelFromUrlRequest extends $pb.GeneratedMessage {
  factory RegisterModelFromUrlRequest({
    $core.String? url,
    $core.String? name,
    InferenceFramework? framework,
    ModelCategory? category,
    ModelSource? source,
    $fixnum.Int64? memoryRequiredBytes,
    $core.bool? supportsThinking,
    $core.bool? supportsLora,
    ModelArtifactType? artifactType,
    $core.int? contextLength,
    $core.String? description,
    $fixnum.Int64? downloadSizeBytes,
    $core.String? id,
  }) {
    final result = create();
    if (url != null) result.url = url;
    if (name != null) result.name = name;
    if (framework != null) result.framework = framework;
    if (category != null) result.category = category;
    if (source != null) result.source = source;
    if (memoryRequiredBytes != null)
      result.memoryRequiredBytes = memoryRequiredBytes;
    if (supportsThinking != null) result.supportsThinking = supportsThinking;
    if (supportsLora != null) result.supportsLora = supportsLora;
    if (artifactType != null) result.artifactType = artifactType;
    if (contextLength != null) result.contextLength = contextLength;
    if (description != null) result.description = description;
    if (downloadSizeBytes != null) result.downloadSizeBytes = downloadSizeBytes;
    if (id != null) result.id = id;
    return result;
  }

  RegisterModelFromUrlRequest._();

  factory RegisterModelFromUrlRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RegisterModelFromUrlRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RegisterModelFromUrlRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'url')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aE<InferenceFramework>(3, _omitFieldNames ? '' : 'framework',
        enumValues: InferenceFramework.values)
    ..aE<ModelCategory>(4, _omitFieldNames ? '' : 'category',
        enumValues: ModelCategory.values)
    ..aE<ModelSource>(5, _omitFieldNames ? '' : 'source',
        enumValues: ModelSource.values)
    ..aInt64(6, _omitFieldNames ? '' : 'memoryRequiredBytes')
    ..aOB(7, _omitFieldNames ? '' : 'supportsThinking')
    ..aOB(8, _omitFieldNames ? '' : 'supportsLora')
    ..aE<ModelArtifactType>(9, _omitFieldNames ? '' : 'artifactType',
        enumValues: ModelArtifactType.values)
    ..aI(10, _omitFieldNames ? '' : 'contextLength')
    ..aOS(11, _omitFieldNames ? '' : 'description')
    ..aInt64(12, _omitFieldNames ? '' : 'downloadSizeBytes')
    ..aOS(13, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterModelFromUrlRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterModelFromUrlRequest copyWith(
          void Function(RegisterModelFromUrlRequest) updates) =>
      super.copyWith(
              (message) => updates(message as RegisterModelFromUrlRequest))
          as RegisterModelFromUrlRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RegisterModelFromUrlRequest create() =>
      RegisterModelFromUrlRequest._();
  @$core.override
  RegisterModelFromUrlRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RegisterModelFromUrlRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RegisterModelFromUrlRequest>(create);
  static RegisterModelFromUrlRequest? _defaultInstance;

  /// Required. Download URL or file path. Routed straight into
  /// ModelInfoMakeRequest.url; format/artifact inference and id/name
  /// generation reuse the same factory semantics.
  @$pb.TagNumber(1)
  $core.String get url => $_getSZ(0);
  @$pb.TagNumber(1)
  set url($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUrl() => $_has(0);
  @$pb.TagNumber(1)
  void clearUrl() => $_clearField(1);

  /// Optional human-readable name. Empty → derived from URL.
  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  /// Optional inference framework. UNSPECIFIED triggers detection from the
  /// URL extension (rac_model_detect_framework_from_format).
  @$pb.TagNumber(3)
  InferenceFramework get framework => $_getN(2);
  @$pb.TagNumber(3)
  set framework(InferenceFramework value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasFramework() => $_has(2);
  @$pb.TagNumber(3)
  void clearFramework() => $_clearField(3);

  /// Optional category. UNSPECIFIED falls back to the framework default.
  @$pb.TagNumber(4)
  ModelCategory get category => $_getN(3);
  @$pb.TagNumber(4)
  set category(ModelCategory value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasCategory() => $_has(3);
  @$pb.TagNumber(4)
  void clearCategory() => $_clearField(4);

  /// Optional source. UNSPECIFIED is treated as MODEL_SOURCE_REMOTE.
  @$pb.TagNumber(5)
  ModelSource get source => $_getN(4);
  @$pb.TagNumber(5)
  set source(ModelSource value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasSource() => $_has(4);
  @$pb.TagNumber(5)
  void clearSource() => $_clearField(5);

  /// Caller-supplied capability fields. When set, the register-from-url C++
  /// path honors them on the saved ModelInfo instead of its inference
  /// defaults (which hardcode supports_lora=false, download_size=0, infer
  /// artifact_type from the URL). This lets every SDK drop the post-register
  /// "patch + resave" pass. Tags 6-13 are free (1-5 stay wire-compatible with
  /// ModelInfoMakeRequest).
  @$pb.TagNumber(6)
  $fixnum.Int64 get memoryRequiredBytes => $_getI64(5);
  @$pb.TagNumber(6)
  set memoryRequiredBytes($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMemoryRequiredBytes() => $_has(5);
  @$pb.TagNumber(6)
  void clearMemoryRequiredBytes() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get supportsThinking => $_getBF(6);
  @$pb.TagNumber(7)
  set supportsThinking($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSupportsThinking() => $_has(6);
  @$pb.TagNumber(7)
  void clearSupportsThinking() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get supportsLora => $_getBF(7);
  @$pb.TagNumber(8)
  set supportsLora($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasSupportsLora() => $_has(7);
  @$pb.TagNumber(8)
  void clearSupportsLora() => $_clearField(8);

  @$pb.TagNumber(9)
  ModelArtifactType get artifactType => $_getN(8);
  @$pb.TagNumber(9)
  set artifactType(ModelArtifactType value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasArtifactType() => $_has(8);
  @$pb.TagNumber(9)
  void clearArtifactType() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get contextLength => $_getIZ(9);
  @$pb.TagNumber(10)
  set contextLength($core.int value) => $_setSignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasContextLength() => $_has(9);
  @$pb.TagNumber(10)
  void clearContextLength() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get description => $_getSZ(10);
  @$pb.TagNumber(11)
  set description($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasDescription() => $_has(10);
  @$pb.TagNumber(11)
  void clearDescription() => $_clearField(11);

  @$pb.TagNumber(12)
  $fixnum.Int64 get downloadSizeBytes => $_getI64(11);
  @$pb.TagNumber(12)
  set downloadSizeBytes($fixnum.Int64 value) => $_setInt64(11, value);
  @$pb.TagNumber(12)
  $core.bool hasDownloadSizeBytes() => $_has(11);
  @$pb.TagNumber(12)
  void clearDownloadSizeBytes() => $_clearField(12);

  /// Explicit id override. Empty -> derived from URL/name.
  @$pb.TagNumber(13)
  $core.String get id => $_getSZ(12);
  @$pb.TagNumber(13)
  set id($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasId() => $_has(12);
  @$pb.TagNumber(13)
  void clearId() => $_clearField(13);
}

/// ---------------------------------------------------------------------------
/// Inputs for registering a multi-file model (each file carries its own URL,
/// so there is no model-level URL). Replaces the hand-built MultiFileArtifact
/// ModelInfo every SDK assembles today. Produces the saved ModelInfo.
/// ---------------------------------------------------------------------------
class RegisterMultiFileModelRequest extends $pb.GeneratedMessage {
  factory RegisterMultiFileModelRequest({
    $core.String? id,
    $core.String? name,
    InferenceFramework? framework,
    $core.Iterable<ModelFileDescriptor>? files,
    ModelCategory? category,
    ModelFormat? format,
    $fixnum.Int64? memoryRequiredBytes,
    $fixnum.Int64? downloadSizeBytes,
    $core.int? contextLength,
    $core.bool? supportsThinking,
    $core.bool? supportsLora,
    $core.String? description,
    ModelSource? source,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (framework != null) result.framework = framework;
    if (files != null) result.files.addAll(files);
    if (category != null) result.category = category;
    if (format != null) result.format = format;
    if (memoryRequiredBytes != null)
      result.memoryRequiredBytes = memoryRequiredBytes;
    if (downloadSizeBytes != null) result.downloadSizeBytes = downloadSizeBytes;
    if (contextLength != null) result.contextLength = contextLength;
    if (supportsThinking != null) result.supportsThinking = supportsThinking;
    if (supportsLora != null) result.supportsLora = supportsLora;
    if (description != null) result.description = description;
    if (source != null) result.source = source;
    return result;
  }

  RegisterMultiFileModelRequest._();

  factory RegisterMultiFileModelRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RegisterMultiFileModelRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RegisterMultiFileModelRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aE<InferenceFramework>(3, _omitFieldNames ? '' : 'framework',
        enumValues: InferenceFramework.values)
    ..pPM<ModelFileDescriptor>(4, _omitFieldNames ? '' : 'files',
        subBuilder: ModelFileDescriptor.create)
    ..aE<ModelCategory>(5, _omitFieldNames ? '' : 'category',
        enumValues: ModelCategory.values)
    ..aE<ModelFormat>(6, _omitFieldNames ? '' : 'format',
        enumValues: ModelFormat.values)
    ..aInt64(7, _omitFieldNames ? '' : 'memoryRequiredBytes')
    ..aInt64(8, _omitFieldNames ? '' : 'downloadSizeBytes')
    ..aI(9, _omitFieldNames ? '' : 'contextLength')
    ..aOB(10, _omitFieldNames ? '' : 'supportsThinking')
    ..aOB(11, _omitFieldNames ? '' : 'supportsLora')
    ..aOS(12, _omitFieldNames ? '' : 'description')
    ..aE<ModelSource>(13, _omitFieldNames ? '' : 'source',
        enumValues: ModelSource.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterMultiFileModelRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterMultiFileModelRequest copyWith(
          void Function(RegisterMultiFileModelRequest) updates) =>
      super.copyWith(
              (message) => updates(message as RegisterMultiFileModelRequest))
          as RegisterMultiFileModelRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RegisterMultiFileModelRequest create() =>
      RegisterMultiFileModelRequest._();
  @$core.override
  RegisterMultiFileModelRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RegisterMultiFileModelRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RegisterMultiFileModelRequest>(create);
  static RegisterMultiFileModelRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  InferenceFramework get framework => $_getN(2);
  @$pb.TagNumber(3)
  set framework(InferenceFramework value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasFramework() => $_has(2);
  @$pb.TagNumber(3)
  void clearFramework() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<ModelFileDescriptor> get files => $_getList(3);

  @$pb.TagNumber(5)
  ModelCategory get category => $_getN(4);
  @$pb.TagNumber(5)
  set category(ModelCategory value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasCategory() => $_has(4);
  @$pb.TagNumber(5)
  void clearCategory() => $_clearField(5);

  @$pb.TagNumber(6)
  ModelFormat get format => $_getN(5);
  @$pb.TagNumber(6)
  set format(ModelFormat value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasFormat() => $_has(5);
  @$pb.TagNumber(6)
  void clearFormat() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get memoryRequiredBytes => $_getI64(6);
  @$pb.TagNumber(7)
  set memoryRequiredBytes($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasMemoryRequiredBytes() => $_has(6);
  @$pb.TagNumber(7)
  void clearMemoryRequiredBytes() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get downloadSizeBytes => $_getI64(7);
  @$pb.TagNumber(8)
  set downloadSizeBytes($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasDownloadSizeBytes() => $_has(7);
  @$pb.TagNumber(8)
  void clearDownloadSizeBytes() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get contextLength => $_getIZ(8);
  @$pb.TagNumber(9)
  set contextLength($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasContextLength() => $_has(8);
  @$pb.TagNumber(9)
  void clearContextLength() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.bool get supportsThinking => $_getBF(9);
  @$pb.TagNumber(10)
  set supportsThinking($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(10)
  $core.bool hasSupportsThinking() => $_has(9);
  @$pb.TagNumber(10)
  void clearSupportsThinking() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.bool get supportsLora => $_getBF(10);
  @$pb.TagNumber(11)
  set supportsLora($core.bool value) => $_setBool(10, value);
  @$pb.TagNumber(11)
  $core.bool hasSupportsLora() => $_has(10);
  @$pb.TagNumber(11)
  void clearSupportsLora() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get description => $_getSZ(11);
  @$pb.TagNumber(12)
  set description($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasDescription() => $_has(11);
  @$pb.TagNumber(12)
  void clearDescription() => $_clearField(12);

  @$pb.TagNumber(13)
  ModelSource get source => $_getN(12);
  @$pb.TagNumber(13)
  set source(ModelSource value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasSource() => $_has(12);
  @$pb.TagNumber(13)
  void clearSource() => $_clearField(13);
}

/// Logical ModelRegistry service contract. Platform adapters remain
/// responsible for native file handles, sandbox permissions, HTTP execution,
/// and destructive filesystem operations. This service carries only the
/// portable registry metadata and workflow messages owned by the IDL/C++ layer.
class ModelRegistryApi {
  final $pb.RpcClient _client;

  ModelRegistryApi(this._client);

  /// Register new model metadata and return the normalized saved entry.
  $async.Future<ModelInfo> register(
          $pb.ClientContext? ctx, ModelInfo request) =>
      _client.invoke<ModelInfo>(
          ctx, 'ModelRegistry', 'Register', request, ModelInfo());

  /// Update an existing model metadata entry and return the normalized entry.
  $async.Future<ModelInfo> update($pb.ClientContext? ctx, ModelInfo request) =>
      _client.invoke<ModelInfo>(
          ctx, 'ModelRegistry', 'Update', request, ModelInfo());

  /// Fetch a single registry entry by id.
  $async.Future<ModelGetResult> get(
          $pb.ClientContext? ctx, ModelGetRequest request) =>
      _client.invoke<ModelGetResult>(
          ctx, 'ModelRegistry', 'Get', request, ModelGetResult());

  /// List entries, optionally filtered by ModelListRequest.query.
  $async.Future<ModelListResult> list(
          $pb.ClientContext? ctx, ModelListRequest request) =>
      _client.invoke<ModelListResult>(
          ctx, 'ModelRegistry', 'List', request, ModelListResult());

  /// Remove a registry entry. File deletion/unload work remains platform or
  /// lifecycle owned even when ModelDeleteRequest flags are populated.
  $async.Future<ModelDeleteResult> remove(
          $pb.ClientContext? ctx, ModelDeleteRequest request) =>
      _client.invoke<ModelDeleteResult>(
          ctx, 'ModelRegistry', 'Remove', request, ModelDeleteResult());

  /// Import stable, platform-normalized local metadata into the registry.
  $async.Future<ModelImportResult> import(
          $pb.ClientContext? ctx, ModelImportRequest request) =>
      _client.invoke<ModelImportResult>(
          ctx, 'ModelRegistry', 'Import', request, ModelImportResult());

  /// Discover models from normalized roots supplied by platform adapters.
  $async.Future<ModelDiscoveryResult> discover(
          $pb.ClientContext? ctx, ModelDiscoveryRequest request) =>
      _client.invoke<ModelDiscoveryResult>(
          ctx, 'ModelRegistry', 'Discover', request, ModelDiscoveryResult());

  /// Refresh registry state from assignment/cache/local reconciliation inputs.
  $async.Future<ModelRegistryRefreshResult> refresh(
          $pb.ClientContext? ctx, ModelRegistryRefreshRequest request) =>
      _client.invoke<ModelRegistryRefreshResult>(ctx, 'ModelRegistry',
          'Refresh', request, ModelRegistryRefreshResult());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
