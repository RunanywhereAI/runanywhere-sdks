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
import 'model_types.pbenum.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'hybrid_router.pbenum.dart';

enum HybridFilter_Kind { network, battery, custom, notSet }

/// A candidate must pass every hard filter to stay in the running.
class HybridFilter extends $pb.GeneratedMessage {
  factory HybridFilter({
    $core.bool? network,
    BatteryFilter? battery,
    CustomFilter? custom,
  }) {
    final result = create();
    if (network != null) result.network = network;
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
    2: HybridFilter_Kind.battery,
    3: HybridFilter_Kind.custom,
    0: HybridFilter_Kind.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HybridFilter',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..oo(0, [1, 2, 3])
    ..aOB(1, _omitFieldNames ? '' : 'network')
    ..aOM<BatteryFilter>(2, _omitFieldNames ? '' : 'battery',
        subBuilder: BatteryFilter.create)
    ..aOM<CustomFilter>(3, _omitFieldNames ? '' : 'custom',
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
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  HybridFilter_Kind whichKind() => _HybridFilter_KindByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  void clearKind() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.bool get network => $_getBF(0);
  @$pb.TagNumber(1)
  set network($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNetwork() => $_has(0);
  @$pb.TagNumber(1)
  void clearNetwork() => $_clearField(1);

  @$pb.TagNumber(2)
  BatteryFilter get battery => $_getN(1);
  @$pb.TagNumber(2)
  set battery(BatteryFilter value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasBattery() => $_has(1);
  @$pb.TagNumber(2)
  void clearBattery() => $_clearField(2);
  @$pb.TagNumber(2)
  BatteryFilter ensureBattery() => $_ensure(1);

  @$pb.TagNumber(3)
  CustomFilter get custom => $_getN(2);
  @$pb.TagNumber(3)
  set custom(CustomFilter value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasCustom() => $_has(2);
  @$pb.TagNumber(3)
  void clearCustom() => $_clearField(3);
  @$pb.TagNumber(3)
  CustomFilter ensureCustom() => $_ensure(2);
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

  /// Charge floor, 0-100, below which the on-device candidate is dropped.
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

/// Below this on-device confidence, the router escalates to cloud.
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

/// The candidate chain for one routed request: tried first to last, first
/// success wins, position IS the priority. `mode` still governs whether the
/// chain may cross the on-device/cloud line.
class HybridRoutingPolicy extends $pb.GeneratedMessage {
  factory HybridRoutingPolicy({
    $core.Iterable<HybridFilter>? hardFilters,
    HybridCascade? cascade,
    HybridInferenceMode? mode,
    $core.int? attemptTimeoutMs,
    $core.Iterable<HybridModelDescriptor>? models,
  }) {
    final result = create();
    if (hardFilters != null) result.hardFilters.addAll(hardFilters);
    if (cascade != null) result.cascade = cascade;
    if (mode != null) result.mode = mode;
    if (attemptTimeoutMs != null) result.attemptTimeoutMs = attemptTimeoutMs;
    if (models != null) result.models.addAll(models);
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
    ..aE<HybridInferenceMode>(3, _omitFieldNames ? '' : 'mode',
        enumValues: HybridInferenceMode.values)
    ..aI(4, _omitFieldNames ? '' : 'attemptTimeoutMs')
    ..pPM<HybridModelDescriptor>(5, _omitFieldNames ? '' : 'models',
        subBuilder: HybridModelDescriptor.create)
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
  HybridInferenceMode get mode => $_getN(2);
  @$pb.TagNumber(3)
  set mode(HybridInferenceMode value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasMode() => $_has(2);
  @$pb.TagNumber(3)
  void clearMode() => $_clearField(3);

  /// Per-ATTEMPT deadline, not the overall request deadline. When a candidate
  /// has produced nothing within this many milliseconds it is abandoned and
  /// the next candidate is tried. 0 = no per-attempt deadline.
  @$pb.TagNumber(4)
  $core.int get attemptTimeoutMs => $_getIZ(3);
  @$pb.TagNumber(4)
  set attemptTimeoutMs($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAttemptTimeoutMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearAttemptTimeoutMs() => $_clearField(4);

  /// Ordered candidates, priority first. Replaces the offline/online pair.
  @$pb.TagNumber(5)
  $pb.PbList<HybridModelDescriptor> get models => $_getList(4);
}

class HybridModelDescriptor extends $pb.GeneratedMessage {
  factory HybridModelDescriptor({
    $core.String? modelId,
    $core.bool? isOnDevice,
    $core.String? engine,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (isOnDevice != null) result.isOnDevice = isOnDevice;
    if (engine != null) result.engine = engine;
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
    ..aOB(2, _omitFieldNames ? '' : 'isOnDevice')
    ..aOS(3, _omitFieldNames ? '' : 'engine')
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

  /// True = this candidate runs ON DEVICE (and is exempt from the network and
  /// battery filters). False = it runs IN CLOUD. Firebase/Android vocabulary.
  @$pb.TagNumber(2)
  $core.bool get isOnDevice => $_getBF(1);
  @$pb.TagNumber(2)
  set isOnDevice($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIsOnDevice() => $_has(1);
  @$pb.TagNumber(2)
  void clearIsOnDevice() => $_clearField(2);

  /// The plugin-registry engine name the runtime already pins on: "sherpa",
  /// "llamacpp", "onnx", "qhexrt", "mlx", "cloud", or any name passed to
  /// registerCloudProvider(). Empty = let the registry pick by priority.
  @$pb.TagNumber(3)
  $core.String get engine => $_getSZ(2);
  @$pb.TagNumber(3)
  set engine($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEngine() => $_has(2);
  @$pb.TagNumber(3)
  void clearEngine() => $_clearField(3);
}

/// What the router actually did, including the failed primary attempt.
class HybridRoutedMetadata extends $pb.GeneratedMessage {
  factory HybridRoutedMetadata({
    $core.String? chosenModelId,
    $core.bool? wasFallback,
    $core.int? attemptCount,
    $core.int? primaryErrorCode,
    $core.String? primaryErrorMessage,
    $core.double? confidence,
    $core.double? primaryConfidence,
    $core.bool? servedOnDevice,
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
    if (servedOnDevice != null) result.servedOnDevice = servedOnDevice;
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
    ..aOB(8, _omitFieldNames ? '' : 'servedOnDevice')
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

  /// Absent (not NaN, not 0.0) when the engine reports no quality score.
  @$pb.TagNumber(6)
  $core.double get confidence => $_getN(5);
  @$pb.TagNumber(6)
  set confidence($core.double value) => $_setFloat(5, value);
  @$pb.TagNumber(6)
  $core.bool hasConfidence() => $_has(5);
  @$pb.TagNumber(6)
  void clearConfidence() => $_clearField(6);

  /// Absent unless a confidence cascade discarded a primary answer.
  @$pb.TagNumber(7)
  $core.double get primaryConfidence => $_getN(6);
  @$pb.TagNumber(7)
  set primaryConfidence($core.double value) => $_setFloat(6, value);
  @$pb.TagNumber(7)
  $core.bool hasPrimaryConfidence() => $_has(6);
  @$pb.TagNumber(7)
  void clearPrimaryConfidence() => $_clearField(7);

  /// True when the answer was produced ON DEVICE. This is the field an app
  /// reads to truthfully claim "processed on your device"; never infer it by
  /// comparing chosen_model_id.
  @$pb.TagNumber(8)
  $core.bool get servedOnDevice => $_getBF(7);
  @$pb.TagNumber(8)
  set servedOnDevice($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasServedOnDevice() => $_has(7);
  @$pb.TagNumber(8)
  void clearServedOnDevice() => $_clearField(8);
}

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

  @$pb.TagNumber(1)
  $core.String get provider => $_getSZ(0);
  @$pb.TagNumber(1)
  set provider($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasProvider() => $_has(0);
  @$pb.TagNumber(1)
  void clearProvider() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get model => $_getSZ(1);
  @$pb.TagNumber(2)
  set model($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasModel() => $_has(1);
  @$pb.TagNumber(2)
  void clearModel() => $_clearField(2);

  /// SECRET. Held in memory only; never logged, never persisted, never
  /// included in a toString()/toJSON() dump.
  @$pb.TagNumber(3)
  $core.String get apiKey => $_getSZ(2);
  @$pb.TagNumber(3)
  set apiKey($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasApiKey() => $_has(2);
  @$pb.TagNumber(3)
  void clearApiKey() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get languageCode => $_getSZ(3);
  @$pb.TagNumber(4)
  set languageCode($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLanguageCode() => $_has(3);
  @$pb.TagNumber(4)
  void clearLanguageCode() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get baseUrl => $_getSZ(4);
  @$pb.TagNumber(5)
  set baseUrl($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasBaseUrl() => $_has(4);
  @$pb.TagNumber(5)
  void clearBaseUrl() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get timeoutMs => $_getIZ(5);
  @$pb.TagNumber(6)
  set timeoutMs($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTimeoutMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearTimeoutMs() => $_clearField(6);
}

class HybridSttTranscribeOptions extends $pb.GeneratedMessage {
  factory HybridSttTranscribeOptions({
    $core.String? language,
    $core.int? sampleRate,
    $0.AudioFormat? audioFormat,
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
    ..aE<$0.AudioFormat>(3, _omitFieldNames ? '' : 'audioFormat',
        enumValues: $0.AudioFormat.values)
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

  /// Container the bytes are already in. UNSPECIFIED (the proto3 zero) means
  /// headerless PCM16, which commons wraps in a WAV container.
  @$pb.TagNumber(3)
  $0.AudioFormat get audioFormat => $_getN(2);
  @$pb.TagNumber(3)
  set audioFormat($0.AudioFormat value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasAudioFormat() => $_has(2);
  @$pb.TagNumber(3)
  void clearAudioFormat() => $_clearField(3);
}

class HybridSttTranscribeRequest extends $pb.GeneratedMessage {
  factory HybridSttTranscribeRequest({
    $core.List<$core.int>? audioBytes,
    HybridSttTranscribeOptions? options,
  }) {
    final result = create();
    if (audioBytes != null) result.audioBytes = audioBytes;
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
    ..aOM<HybridSttTranscribeOptions>(2, _omitFieldNames ? '' : 'options',
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
  HybridSttTranscribeOptions get options => $_getN(1);
  @$pb.TagNumber(2)
  set options(HybridSttTranscribeOptions value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasOptions() => $_has(1);
  @$pb.TagNumber(2)
  void clearOptions() => $_clearField(2);
  @$pb.TagNumber(2)
  HybridSttTranscribeOptions ensureOptions() => $_ensure(1);
}

class HybridSttTranscribeResponse extends $pb.GeneratedMessage {
  factory HybridSttTranscribeResponse({
    $core.int? rc,
    $core.String? text,
    $core.String? detectedLanguage,
    HybridRoutedMetadata? routing,
  }) {
    final result = create();
    if (rc != null) result.rc = rc;
    if (text != null) result.text = text;
    if (detectedLanguage != null) result.detectedLanguage = detectedLanguage;
    if (routing != null) result.routing = routing;
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
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
