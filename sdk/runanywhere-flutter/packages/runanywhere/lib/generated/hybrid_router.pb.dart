// This is a generated file - do not edit.
//
// Generated from hybrid_router.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'hybrid_router.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'hybrid_router.pbenum.dart';

enum HybridFilter_Kind { network, qualityTier, battery, custom, notSet }

/// ---------------------------------------------------------------------------
/// Hard filter — drops a candidate from consideration when the predicate
/// fails. Filters compose with AND semantics. The wire kinds match
/// thoughts/file.txt's Routing Conditions list verbatim.
/// ---------------------------------------------------------------------------
class HybridFilter extends $pb.GeneratedMessage {
  factory HybridFilter({
    $core.bool? network,
    $core.int? qualityTier,
    BatteryFilter? battery,
    CustomFilter? custom,
  }) {
    final result = create();
    if (network != null) result.network = network;
    if (qualityTier != null) result.qualityTier = qualityTier;
    if (battery != null) result.battery = battery;
    if (custom != null) result.custom = custom;
    return result;
  }

  HybridFilter._();

  factory HybridFilter.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HybridFilter.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, HybridFilter_Kind> _HybridFilter_KindByTag =
      {
    1: HybridFilter_Kind.network,
    3: HybridFilter_Kind.qualityTier,
    4: HybridFilter_Kind.battery,
    5: HybridFilter_Kind.custom,
    0: HybridFilter_Kind.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HybridFilter',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..oo(0, [1, 3, 4, 5])
    ..aOB(1, _omitFieldNames ? '' : 'network')
    ..aI(3, _omitFieldNames ? '' : 'qualityTier')
    ..aOM<BatteryFilter>(4, _omitFieldNames ? '' : 'battery',
        subBuilder: BatteryFilter.create)
    ..aOM<CustomFilter>(5, _omitFieldNames ? '' : 'custom',
        subBuilder: CustomFilter.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HybridFilter clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HybridFilter copyWith(void Function(HybridFilter) updates) =>
      super.copyWith((message) => updates(message as HybridFilter))
          as HybridFilter;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HybridFilter create() => HybridFilter._();
  @$core.override
  HybridFilter createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HybridFilter getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HybridFilter>(create);
  static HybridFilter? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  HybridFilter_Kind whichKind() => _HybridFilter_KindByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  void clearKind() => $_clearField($_whichOneof(0));

  /// True iff the host has working network. Disqualifies online
  /// candidates when false; offline candidates are unaffected.
  @$pb.TagNumber(1)
  $core.bool get network => $_getBF(0);
  @$pb.TagNumber(1)
  set network($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNetwork() => $_has(0);
  @$pb.TagNumber(1)
  void clearNetwork() => $_clearField(1);

  /// Discrete quality tier required from the candidate. Candidates
  /// declaring a lower tier in their descriptor are filtered out.
  @$pb.TagNumber(3)
  $core.int get qualityTier => $_getIZ(1);
  @$pb.TagNumber(3)
  set qualityTier($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(3)
  $core.bool hasQualityTier() => $_has(1);
  @$pb.TagNumber(3)
  void clearQualityTier() => $_clearField(3);

  /// Disqualifies cloud candidates when the device is below the
  /// given battery percent (0–100).
  @$pb.TagNumber(4)
  BatteryFilter get battery => $_getN(2);
  @$pb.TagNumber(4)
  set battery(BatteryFilter value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasBattery() => $_has(2);
  @$pb.TagNumber(4)
  void clearBattery() => $_clearField(4);
  @$pb.TagNumber(4)
  BatteryFilter ensureBattery() => $_ensure(2);

  /// Caller-supplied predicate, evaluated host-side via the
  /// registered custom-filter callback table.
  @$pb.TagNumber(5)
  CustomFilter get custom => $_getN(3);
  @$pb.TagNumber(5)
  set custom(CustomFilter value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasCustom() => $_has(3);
  @$pb.TagNumber(5)
  void clearCustom() => $_clearField(5);
  @$pb.TagNumber(5)
  CustomFilter ensureCustom() => $_ensure(3);
}

class BatteryFilter extends $pb.GeneratedMessage {
  factory BatteryFilter({
    $core.int? minBatteryPercent,
  }) {
    final result = create();
    if (minBatteryPercent != null) result.minBatteryPercent = minBatteryPercent;
    return result;
  }

  BatteryFilter._();

  factory BatteryFilter.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory BatteryFilter.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BatteryFilter',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'minBatteryPercent')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BatteryFilter clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BatteryFilter copyWith(void Function(BatteryFilter) updates) =>
      super.copyWith((message) => updates(message as BatteryFilter))
          as BatteryFilter;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BatteryFilter create() => BatteryFilter._();
  @$core.override
  BatteryFilter createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static BatteryFilter getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<BatteryFilter>(create);
  static BatteryFilter? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get minBatteryPercent => $_getIZ(0);
  @$pb.TagNumber(1)
  set minBatteryPercent($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMinBatteryPercent() => $_has(0);
  @$pb.TagNumber(1)
  void clearMinBatteryPercent() => $_clearField(1);
}

class CustomFilter extends $pb.GeneratedMessage {
  factory CustomFilter({
    $core.String? name,
    $core.String? description,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (description != null) result.description = description;
    return result;
  }

  CustomFilter._();

  factory CustomFilter.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CustomFilter.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CustomFilter',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'description')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CustomFilter clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CustomFilter copyWith(void Function(CustomFilter) updates) =>
      super.copyWith((message) => updates(message as CustomFilter))
          as CustomFilter;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CustomFilter create() => CustomFilter._();
  @$core.override
  CustomFilter createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CustomFilter getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CustomFilter>(create);
  static CustomFilter? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get description => $_getSZ(1);
  @$pb.TagNumber(2)
  set description($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDescription() => $_has(1);
  @$pb.TagNumber(2)
  void clearDescription() => $_clearField(2);
}

enum HybridCascade_Kind { confidence, notSet }

/// ---------------------------------------------------------------------------
/// Cascade — triggers fallback from the primary candidate to the next
/// candidate mid-request. Matches the file.txt Confidence policy.
/// ---------------------------------------------------------------------------
class HybridCascade extends $pb.GeneratedMessage {
  factory HybridCascade({
    ConfidenceCascade? confidence,
  }) {
    final result = create();
    if (confidence != null) result.confidence = confidence;
    return result;
  }

  HybridCascade._();

  factory HybridCascade.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HybridCascade.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, HybridCascade_Kind>
      _HybridCascade_KindByTag = {
    1: HybridCascade_Kind.confidence,
    0: HybridCascade_Kind.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HybridCascade',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..oo(0, [1])
    ..aOM<ConfidenceCascade>(1, _omitFieldNames ? '' : 'confidence',
        subBuilder: ConfidenceCascade.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HybridCascade clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HybridCascade copyWith(void Function(HybridCascade) updates) =>
      super.copyWith((message) => updates(message as HybridCascade))
          as HybridCascade;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HybridCascade create() => HybridCascade._();
  @$core.override
  HybridCascade createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HybridCascade getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HybridCascade>(create);
  static HybridCascade? _defaultInstance;

  @$pb.TagNumber(1)
  HybridCascade_Kind whichKind() => _HybridCascade_KindByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  void clearKind() => $_clearField($_whichOneof(0));

  /// Cascade when the primary's confidence/logprob signal falls below
  /// `threshold`, or when the primary returns an error (treated as
  /// "no confidence").
  @$pb.TagNumber(1)
  ConfidenceCascade get confidence => $_getN(0);
  @$pb.TagNumber(1)
  set confidence(ConfidenceCascade value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasConfidence() => $_has(0);
  @$pb.TagNumber(1)
  void clearConfidence() => $_clearField(1);
  @$pb.TagNumber(1)
  ConfidenceCascade ensureConfidence() => $_ensure(0);
}

class ConfidenceCascade extends $pb.GeneratedMessage {
  factory ConfidenceCascade({
    $core.double? threshold,
  }) {
    final result = create();
    if (threshold != null) result.threshold = threshold;
    return result;
  }

  ConfidenceCascade._();

  factory ConfidenceCascade.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConfidenceCascade.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConfidenceCascade',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'threshold', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfidenceCascade clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfidenceCascade copyWith(void Function(ConfidenceCascade) updates) =>
      super.copyWith((message) => updates(message as ConfidenceCascade))
          as ConfidenceCascade;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConfidenceCascade create() => ConfidenceCascade._();
  @$core.override
  ConfidenceCascade createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConfidenceCascade getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConfidenceCascade>(create);
  static ConfidenceCascade? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get threshold => $_getN(0);
  @$pb.TagNumber(1)
  set threshold($core.double value) => $_setFloat(0, value);
  @$pb.TagNumber(1)
  $core.bool hasThreshold() => $_has(0);
  @$pb.TagNumber(1)
  void clearThreshold() => $_clearField(1);
}

/// ---------------------------------------------------------------------------
/// Full routing policy attached to a model pair. `simple` mode collapses
/// to a single filter; `advanced` mode allows composition.
/// ---------------------------------------------------------------------------
class HybridRoutingPolicy extends $pb.GeneratedMessage {
  factory HybridRoutingPolicy({
    $core.Iterable<HybridFilter>? hardFilters,
    HybridCascade? cascade,
    HybridRank? rank,
  }) {
    final result = create();
    if (hardFilters != null) result.hardFilters.addAll(hardFilters);
    if (cascade != null) result.cascade = cascade;
    if (rank != null) result.rank = rank;
    return result;
  }

  HybridRoutingPolicy._();

  factory HybridRoutingPolicy.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HybridRoutingPolicy.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HybridRoutingPolicy',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPM<HybridFilter>(1, _omitFieldNames ? '' : 'hardFilters',
        subBuilder: HybridFilter.create)
    ..aOM<HybridCascade>(2, _omitFieldNames ? '' : 'cascade',
        subBuilder: HybridCascade.create)
    ..aE<HybridRank>(3, _omitFieldNames ? '' : 'rank',
        enumValues: HybridRank.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HybridRoutingPolicy clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HybridRoutingPolicy copyWith(void Function(HybridRoutingPolicy) updates) =>
      super.copyWith((message) => updates(message as HybridRoutingPolicy))
          as HybridRoutingPolicy;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HybridRoutingPolicy create() => HybridRoutingPolicy._();
  @$core.override
  HybridRoutingPolicy createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HybridRoutingPolicy getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HybridRoutingPolicy>(create);
  static HybridRoutingPolicy? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<HybridFilter> get hardFilters => $_getList(0);

  @$pb.TagNumber(2)
  HybridCascade get cascade => $_getN(1);
  @$pb.TagNumber(2)
  set cascade(HybridCascade value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasCascade() => $_has(1);
  @$pb.TagNumber(2)
  void clearCascade() => $_clearField(2);
  @$pb.TagNumber(2)
  HybridCascade ensureCascade() => $_ensure(1);

  @$pb.TagNumber(3)
  HybridRank get rank => $_getN(2);
  @$pb.TagNumber(3)
  set rank(HybridRank value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasRank() => $_has(2);
  @$pb.TagNumber(3)
  void clearRank() => $_clearField(3);
}

/// ---------------------------------------------------------------------------
/// Descriptor for a single registered model on one side of the pair.
/// ---------------------------------------------------------------------------
class HybridModelDescriptor extends $pb.GeneratedMessage {
  factory HybridModelDescriptor({
    $core.String? modelId,
    HybridModelType? modelType,
    HybridBackendKind? backend,
    $core.String? provider,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (modelType != null) result.modelType = modelType;
    if (backend != null) result.backend = backend;
    if (provider != null) result.provider = provider;
    return result;
  }

  HybridModelDescriptor._();

  factory HybridModelDescriptor.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HybridModelDescriptor.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HybridModelDescriptor',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aE<HybridModelType>(2, _omitFieldNames ? '' : 'modelType',
        enumValues: HybridModelType.values)
    ..aE<HybridBackendKind>(3, _omitFieldNames ? '' : 'backend',
        enumValues: HybridBackendKind.values)
    ..aOS(4, _omitFieldNames ? '' : 'provider')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HybridModelDescriptor clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HybridModelDescriptor copyWith(
          void Function(HybridModelDescriptor) updates) =>
      super.copyWith((message) => updates(message as HybridModelDescriptor))
          as HybridModelDescriptor;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HybridModelDescriptor create() => HybridModelDescriptor._();
  @$core.override
  HybridModelDescriptor createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HybridModelDescriptor getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HybridModelDescriptor>(create);
  static HybridModelDescriptor? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  @$pb.TagNumber(2)
  HybridModelType get modelType => $_getN(1);
  @$pb.TagNumber(2)
  set modelType(HybridModelType value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasModelType() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelType() => $_clearField(2);

  @$pb.TagNumber(3)
  HybridBackendKind get backend => $_getN(2);
  @$pb.TagNumber(3)
  set backend(HybridBackendKind value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasBackend() => $_has(2);
  @$pb.TagNumber(3)
  void clearBackend() => $_clearField(3);

  /// Concrete cloud provider when backend == HYBRID_BACKEND_CLOUD (e.g.
  /// "sarvam"). The cloud_stt engine reads it from config_json["provider"];
  /// empty defaults to "sarvam". Ignored for non-cloud backends.
  @$pb.TagNumber(4)
  $core.String get provider => $_getSZ(3);
  @$pb.TagNumber(4)
  set provider($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasProvider() => $_has(3);
  @$pb.TagNumber(4)
  void clearProvider() => $_clearField(4);
}

/// ---------------------------------------------------------------------------
/// Metadata returned alongside the capability result describing what the
/// router did. Always populated even on success.
/// ---------------------------------------------------------------------------
class HybridRoutedMetadata extends $pb.GeneratedMessage {
  factory HybridRoutedMetadata({
    $core.String? chosenModelId,
    $core.bool? wasFallback,
    $core.int? attemptCount,
    $core.int? primaryErrorCode,
    $core.String? primaryErrorMessage,
    $core.double? confidence,
    $core.double? primaryConfidence,
  }) {
    final result = create();
    if (chosenModelId != null) result.chosenModelId = chosenModelId;
    if (wasFallback != null) result.wasFallback = wasFallback;
    if (attemptCount != null) result.attemptCount = attemptCount;
    if (primaryErrorCode != null) result.primaryErrorCode = primaryErrorCode;
    if (primaryErrorMessage != null)
      result.primaryErrorMessage = primaryErrorMessage;
    if (confidence != null) result.confidence = confidence;
    if (primaryConfidence != null) result.primaryConfidence = primaryConfidence;
    return result;
  }

  HybridRoutedMetadata._();

  factory HybridRoutedMetadata.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HybridRoutedMetadata.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HybridRoutedMetadata',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'chosenModelId')
    ..aOB(2, _omitFieldNames ? '' : 'wasFallback')
    ..aI(3, _omitFieldNames ? '' : 'attemptCount')
    ..aI(4, _omitFieldNames ? '' : 'primaryErrorCode')
    ..aOS(5, _omitFieldNames ? '' : 'primaryErrorMessage')
    ..aD(6, _omitFieldNames ? '' : 'confidence', fieldType: $pb.PbFieldType.OF)
    ..aD(7, _omitFieldNames ? '' : 'primaryConfidence',
        fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HybridRoutedMetadata clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HybridRoutedMetadata copyWith(void Function(HybridRoutedMetadata) updates) =>
      super.copyWith((message) => updates(message as HybridRoutedMetadata))
          as HybridRoutedMetadata;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HybridRoutedMetadata create() => HybridRoutedMetadata._();
  @$core.override
  HybridRoutedMetadata createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HybridRoutedMetadata getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HybridRoutedMetadata>(create);
  static HybridRoutedMetadata? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get chosenModelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set chosenModelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChosenModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChosenModelId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get wasFallback => $_getBF(1);
  @$pb.TagNumber(2)
  set wasFallback($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasWasFallback() => $_has(1);
  @$pb.TagNumber(2)
  void clearWasFallback() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get attemptCount => $_getIZ(2);
  @$pb.TagNumber(3)
  set attemptCount($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAttemptCount() => $_has(2);
  @$pb.TagNumber(3)
  void clearAttemptCount() => $_clearField(3);

  /// Why the router fell back to the secondary. Zero (RAC_SUCCESS) when
  /// the primary served the request or no fallback occurred.
  @$pb.TagNumber(4)
  $core.int get primaryErrorCode => $_getIZ(3);
  @$pb.TagNumber(4)
  set primaryErrorCode($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPrimaryErrorCode() => $_has(3);
  @$pb.TagNumber(4)
  void clearPrimaryErrorCode() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get primaryErrorMessage => $_getSZ(4);
  @$pb.TagNumber(5)
  set primaryErrorMessage($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPrimaryErrorMessage() => $_has(4);
  @$pb.TagNumber(5)
  void clearPrimaryErrorMessage() => $_clearField(5);

  /// Final confidence of the result that was actually returned. NaN when
  /// the engine does not surface a quality signal (e.g. sherpa-onnx Whisper).
  @$pb.TagNumber(6)
  $core.double get confidence => $_getN(5);
  @$pb.TagNumber(6)
  set confidence($core.double value) => $_setFloat(5, value);
  @$pb.TagNumber(6)
  $core.bool hasConfidence() => $_has(5);
  @$pb.TagNumber(6)
  void clearConfidence() => $_clearField(6);

  /// Primary's confidence captured BEFORE cascading to the secondary.
  /// Populated only when `was_fallback = true` AND the fallback fired on
  /// confidence (not on an error). NaN otherwise.
  @$pb.TagNumber(7)
  $core.double get primaryConfidence => $_getN(6);
  @$pb.TagNumber(7)
  set primaryConfidence($core.double value) => $_setFloat(6, value);
  @$pb.TagNumber(7)
  $core.bool hasPrimaryConfidence() => $_has(6);
  @$pb.TagNumber(7)
  void clearPrimaryConfidence() => $_clearField(7);
}

/// ---------------------------------------------------------------------------
/// Per-request routing context — caller-supplied hints only.
///
/// Device-state fields (is_online, battery_percent, thermal_throttled) live
/// behind the rac_hybrid_device_state C ABI vtable in commons (task #22).
/// `input_is_sensitive` (tag 2) was the privacy PII hint; removed entirely
/// alongside the HybridFilter.privacy gate.
///
/// Reserved tags 1–4 prevent re-use of any old field number.
/// ---------------------------------------------------------------------------
class HybridRoutingContext extends $pb.GeneratedMessage {
  factory HybridRoutingContext() => create();

  HybridRoutingContext._();

  factory HybridRoutingContext.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HybridRoutingContext.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HybridRoutingContext',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HybridRoutingContext clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HybridRoutingContext copyWith(void Function(HybridRoutingContext) updates) =>
      super.copyWith((message) => updates(message as HybridRoutingContext))
          as HybridRoutingContext;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HybridRoutingContext create() => HybridRoutingContext._();
  @$core.override
  HybridRoutingContext createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HybridRoutingContext getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HybridRoutingContext>(create);
  static HybridRoutingContext? _defaultInstance;
}

/// ---------------------------------------------------------------------------
/// Cloud STT backend registration config. Replaces the hand-built
/// `config_json` string that Swift (CloudSTT.swift), Kotlin (CloudModelEntry /
/// HybridRouterBridgeAdapter), Flutter (CloudModelEntry.toConfigJson), RN
/// (CloudSTT.configJSON), and Web (CloudSTT) each assemble identically and pass
/// across the FFI/JNI boundary as `config_json`. The cloud_stt engine reads
/// these fields when a model's backend == HYBRID_BACKEND_CLOUD; today it parses
/// the same keys out of the JSON blob (`config_json["provider"]` etc., see
/// HybridModelDescriptor.provider).
/// ---------------------------------------------------------------------------
class CloudSttBackendConfig extends $pb.GeneratedMessage {
  factory CloudSttBackendConfig({
    $core.String? provider,
    $core.String? model,
    $core.String? apiKey,
    $core.String? languageCode,
    $core.String? baseUrl,
    $core.int? timeoutMs,
  }) {
    final result = create();
    if (provider != null) result.provider = provider;
    if (model != null) result.model = model;
    if (apiKey != null) result.apiKey = apiKey;
    if (languageCode != null) result.languageCode = languageCode;
    if (baseUrl != null) result.baseUrl = baseUrl;
    if (timeoutMs != null) result.timeoutMs = timeoutMs;
    return result;
  }

  CloudSttBackendConfig._();

  factory CloudSttBackendConfig.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CloudSttBackendConfig.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CloudSttBackendConfig',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'provider')
    ..aOS(2, _omitFieldNames ? '' : 'model')
    ..aOS(3, _omitFieldNames ? '' : 'apiKey')
    ..aOS(4, _omitFieldNames ? '' : 'languageCode')
    ..aOS(5, _omitFieldNames ? '' : 'baseUrl')
    ..aI(6, _omitFieldNames ? '' : 'timeoutMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CloudSttBackendConfig clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CloudSttBackendConfig copyWith(
          void Function(CloudSttBackendConfig) updates) =>
      super.copyWith((message) => updates(message as CloudSttBackendConfig))
          as CloudSttBackendConfig;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CloudSttBackendConfig create() => CloudSttBackendConfig._();
  @$core.override
  CloudSttBackendConfig createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CloudSttBackendConfig getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CloudSttBackendConfig>(create);
  static CloudSttBackendConfig? _defaultInstance;

  /// HTTP provider implementation (e.g. "sarvam"). Empty defaults to "sarvam".
  @$pb.TagNumber(1)
  $core.String get provider => $_getSZ(0);
  @$pb.TagNumber(1)
  set provider($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasProvider() => $_has(0);
  @$pb.TagNumber(1)
  void clearProvider() => $_clearField(1);

  /// Provider-side model id (e.g. "saarika:v2").
  @$pb.TagNumber(2)
  $core.String get model => $_getSZ(1);
  @$pb.TagNumber(2)
  set model($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasModel() => $_has(1);
  @$pb.TagNumber(2)
  void clearModel() => $_clearField(2);

  /// Provider API key / credential.
  @$pb.TagNumber(3)
  $core.String get apiKey => $_getSZ(2);
  @$pb.TagNumber(3)
  set apiKey($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasApiKey() => $_has(2);
  @$pb.TagNumber(3)
  void clearApiKey() => $_clearField(3);

  /// BCP-47 language hint forwarded to the provider (empty = auto-detect).
  @$pb.TagNumber(4)
  $core.String get languageCode => $_getSZ(3);
  @$pb.TagNumber(4)
  set languageCode($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLanguageCode() => $_has(3);
  @$pb.TagNumber(4)
  void clearLanguageCode() => $_clearField(4);

  /// Override the provider base URL (empty = provider default).
  @$pb.TagNumber(5)
  $core.String get baseUrl => $_getSZ(4);
  @$pb.TagNumber(5)
  set baseUrl($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasBaseUrl() => $_has(4);
  @$pb.TagNumber(5)
  void clearBaseUrl() => $_clearField(5);

  /// Request timeout in milliseconds (0 = engine default).
  @$pb.TagNumber(6)
  $core.int get timeoutMs => $_getIZ(5);
  @$pb.TagNumber(6)
  set timeoutMs($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTimeoutMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearTimeoutMs() => $_clearField(6);
}

/// ---------------------------------------------------------------------------
/// STT transcription options carried through the router. Sample rate and
/// audio_format mirror the C `rac_stt_options_t` knobs; `language` is the
/// caller-supplied BCP-47 hint (empty = backend auto-detect).
/// ---------------------------------------------------------------------------
class HybridSttTranscribeOptions extends $pb.GeneratedMessage {
  factory HybridSttTranscribeOptions({
    $core.String? language,
    $core.int? sampleRate,
    $core.int? audioFormat,
  }) {
    final result = create();
    if (language != null) result.language = language;
    if (sampleRate != null) result.sampleRate = sampleRate;
    if (audioFormat != null) result.audioFormat = audioFormat;
    return result;
  }

  HybridSttTranscribeOptions._();

  factory HybridSttTranscribeOptions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HybridSttTranscribeOptions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HybridSttTranscribeOptions',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'language')
    ..aI(2, _omitFieldNames ? '' : 'sampleRate')
    ..aI(3, _omitFieldNames ? '' : 'audioFormat')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HybridSttTranscribeOptions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HybridSttTranscribeOptions copyWith(
          void Function(HybridSttTranscribeOptions) updates) =>
      super.copyWith(
              (message) => updates(message as HybridSttTranscribeOptions))
          as HybridSttTranscribeOptions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HybridSttTranscribeOptions create() => HybridSttTranscribeOptions._();
  @$core.override
  HybridSttTranscribeOptions createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HybridSttTranscribeOptions getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HybridSttTranscribeOptions>(create);
  static HybridSttTranscribeOptions? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get language => $_getSZ(0);
  @$pb.TagNumber(1)
  set language($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLanguage() => $_has(0);
  @$pb.TagNumber(1)
  void clearLanguage() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get sampleRate => $_getIZ(1);
  @$pb.TagNumber(2)
  set sampleRate($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSampleRate() => $_has(1);
  @$pb.TagNumber(2)
  void clearSampleRate() => $_clearField(2);

  /// Matches rac_audio_format_enum_t: 0=PCM, 1=WAV, 2=MP3, 3=OPUS, 4=AAC, 5=FLAC.
  @$pb.TagNumber(3)
  $core.int get audioFormat => $_getIZ(2);
  @$pb.TagNumber(3)
  set audioFormat($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAudioFormat() => $_has(2);
  @$pb.TagNumber(3)
  void clearAudioFormat() => $_clearField(3);
}

/// ---------------------------------------------------------------------------
/// Request handed to the JNI transcribe thunk. Audio bytes are passed
/// verbatim to the chosen backend; each engine is responsible for parsing
/// the encoded format (the cloud provider, e.g. Sarvam, reads the multipart
/// file part; sherpa decodes the WAV/PCM bytes).
/// ---------------------------------------------------------------------------
class HybridSttTranscribeRequest extends $pb.GeneratedMessage {
  factory HybridSttTranscribeRequest({
    $core.List<$core.int>? audioBytes,
    HybridRoutingContext? context,
    HybridSttTranscribeOptions? options,
  }) {
    final result = create();
    if (audioBytes != null) result.audioBytes = audioBytes;
    if (context != null) result.context = context;
    if (options != null) result.options = options;
    return result;
  }

  HybridSttTranscribeRequest._();

  factory HybridSttTranscribeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HybridSttTranscribeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HybridSttTranscribeRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'audioBytes', $pb.PbFieldType.OY)
    ..aOM<HybridRoutingContext>(2, _omitFieldNames ? '' : 'context',
        subBuilder: HybridRoutingContext.create)
    ..aOM<HybridSttTranscribeOptions>(3, _omitFieldNames ? '' : 'options',
        subBuilder: HybridSttTranscribeOptions.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HybridSttTranscribeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HybridSttTranscribeRequest copyWith(
          void Function(HybridSttTranscribeRequest) updates) =>
      super.copyWith(
              (message) => updates(message as HybridSttTranscribeRequest))
          as HybridSttTranscribeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HybridSttTranscribeRequest create() => HybridSttTranscribeRequest._();
  @$core.override
  HybridSttTranscribeRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HybridSttTranscribeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HybridSttTranscribeRequest>(create);
  static HybridSttTranscribeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get audioBytes => $_getN(0);
  @$pb.TagNumber(1)
  set audioBytes($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAudioBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearAudioBytes() => $_clearField(1);

  @$pb.TagNumber(2)
  HybridRoutingContext get context => $_getN(1);
  @$pb.TagNumber(2)
  set context(HybridRoutingContext value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasContext() => $_has(1);
  @$pb.TagNumber(2)
  void clearContext() => $_clearField(2);
  @$pb.TagNumber(2)
  HybridRoutingContext ensureContext() => $_ensure(1);

  @$pb.TagNumber(3)
  HybridSttTranscribeOptions get options => $_getN(2);
  @$pb.TagNumber(3)
  set options(HybridSttTranscribeOptions value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasOptions() => $_has(2);
  @$pb.TagNumber(3)
  void clearOptions() => $_clearField(3);
  @$pb.TagNumber(3)
  HybridSttTranscribeOptions ensureOptions() => $_ensure(2);
}

/// ---------------------------------------------------------------------------
/// Response returned by the JNI transcribe thunk. Carries the transcript,
/// the detected (or hinted) language, the routing decision metadata, the
/// native rc, and a human-readable error message when rc != 0.
/// ---------------------------------------------------------------------------
class HybridSttTranscribeResponse extends $pb.GeneratedMessage {
  factory HybridSttTranscribeResponse({
    $core.int? rc,
    $core.String? text,
    $core.String? detectedLanguage,
    HybridRoutedMetadata? routing,
    $core.String? errorMsg,
  }) {
    final result = create();
    if (rc != null) result.rc = rc;
    if (text != null) result.text = text;
    if (detectedLanguage != null) result.detectedLanguage = detectedLanguage;
    if (routing != null) result.routing = routing;
    if (errorMsg != null) result.errorMsg = errorMsg;
    return result;
  }

  HybridSttTranscribeResponse._();

  factory HybridSttTranscribeResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HybridSttTranscribeResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HybridSttTranscribeResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'rc')
    ..aOS(2, _omitFieldNames ? '' : 'text')
    ..aOS(3, _omitFieldNames ? '' : 'detectedLanguage')
    ..aOM<HybridRoutedMetadata>(4, _omitFieldNames ? '' : 'routing',
        subBuilder: HybridRoutedMetadata.create)
    ..aOS(5, _omitFieldNames ? '' : 'errorMsg')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HybridSttTranscribeResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HybridSttTranscribeResponse copyWith(
          void Function(HybridSttTranscribeResponse) updates) =>
      super.copyWith(
              (message) => updates(message as HybridSttTranscribeResponse))
          as HybridSttTranscribeResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HybridSttTranscribeResponse create() =>
      HybridSttTranscribeResponse._();
  @$core.override
  HybridSttTranscribeResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HybridSttTranscribeResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HybridSttTranscribeResponse>(create);
  static HybridSttTranscribeResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get rc => $_getIZ(0);
  @$pb.TagNumber(1)
  set rc($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRc() => $_has(0);
  @$pb.TagNumber(1)
  void clearRc() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get text => $_getSZ(1);
  @$pb.TagNumber(2)
  set text($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get detectedLanguage => $_getSZ(2);
  @$pb.TagNumber(3)
  set detectedLanguage($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDetectedLanguage() => $_has(2);
  @$pb.TagNumber(3)
  void clearDetectedLanguage() => $_clearField(3);

  @$pb.TagNumber(4)
  HybridRoutedMetadata get routing => $_getN(3);
  @$pb.TagNumber(4)
  set routing(HybridRoutedMetadata value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasRouting() => $_has(3);
  @$pb.TagNumber(4)
  void clearRouting() => $_clearField(4);
  @$pb.TagNumber(4)
  HybridRoutedMetadata ensureRouting() => $_ensure(3);

  @$pb.TagNumber(5)
  $core.String get errorMsg => $_getSZ(4);
  @$pb.TagNumber(5)
  set errorMsg($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasErrorMsg() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorMsg() => $_clearField(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
