// This is a generated file - do not edit.
//
// Generated from hardware_profile.proto.

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

import 'hardware_profile.pbenum.dart';
import 'storage_types.pbenum.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'hardware_profile.pbenum.dart';

class HardwareProfile extends $pb.GeneratedMessage {
  factory HardwareProfile({
    $core.String? chip,
    $core.bool? hasNeuralEngine,
    $core.String? accelerationMode,
    $fixnum.Int64? totalMemoryBytes,
    $core.int? coreCount,
    $core.int? performanceCores,
    $core.int? efficiencyCores,
    $core.String? architecture,
    $core.String? platform,
    $0.NPUChip? npuChip,
  }) {
    final result = create();
    if (chip != null) result.chip = chip;
    if (hasNeuralEngine != null) result.hasNeuralEngine = hasNeuralEngine;
    if (accelerationMode != null) result.accelerationMode = accelerationMode;
    if (totalMemoryBytes != null) result.totalMemoryBytes = totalMemoryBytes;
    if (coreCount != null) result.coreCount = coreCount;
    if (performanceCores != null) result.performanceCores = performanceCores;
    if (efficiencyCores != null) result.efficiencyCores = efficiencyCores;
    if (architecture != null) result.architecture = architecture;
    if (platform != null) result.platform = platform;
    if (npuChip != null) result.npuChip = npuChip;
    return result;
  }

  HardwareProfile._();

  factory HardwareProfile.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HardwareProfile.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HardwareProfile',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'chip')
    ..aOB(2, _omitFieldNames ? '' : 'hasNeuralEngine')
    ..aOS(3, _omitFieldNames ? '' : 'accelerationMode')
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'totalMemoryBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(5, _omitFieldNames ? '' : 'coreCount', fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'performanceCores',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(7, _omitFieldNames ? '' : 'efficiencyCores',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(8, _omitFieldNames ? '' : 'architecture')
    ..aOS(9, _omitFieldNames ? '' : 'platform')
    ..aE<$0.NPUChip>(10, _omitFieldNames ? '' : 'npuChip',
        enumValues: $0.NPUChip.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HardwareProfile clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HardwareProfile copyWith(void Function(HardwareProfile) updates) =>
      super.copyWith((message) => updates(message as HardwareProfile))
          as HardwareProfile;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HardwareProfile create() => HardwareProfile._();
  @$core.override
  HardwareProfile createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HardwareProfile getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HardwareProfile>(create);
  static HardwareProfile? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get chip => $_getSZ(0);
  @$pb.TagNumber(1)
  set chip($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChip() => $_has(0);
  @$pb.TagNumber(1)
  void clearChip() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get hasNeuralEngine => $_getBF(1);
  @$pb.TagNumber(2)
  set hasNeuralEngine($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHasNeuralEngine() => $_has(1);
  @$pb.TagNumber(2)
  void clearHasNeuralEngine() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get accelerationMode => $_getSZ(2);
  @$pb.TagNumber(3)
  set accelerationMode($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAccelerationMode() => $_has(2);
  @$pb.TagNumber(3)
  void clearAccelerationMode() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get totalMemoryBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set totalMemoryBytes($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTotalMemoryBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalMemoryBytes() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get coreCount => $_getIZ(4);
  @$pb.TagNumber(5)
  set coreCount($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCoreCount() => $_has(4);
  @$pb.TagNumber(5)
  void clearCoreCount() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get performanceCores => $_getIZ(5);
  @$pb.TagNumber(6)
  set performanceCores($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPerformanceCores() => $_has(5);
  @$pb.TagNumber(6)
  void clearPerformanceCores() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get efficiencyCores => $_getIZ(6);
  @$pb.TagNumber(7)
  set efficiencyCores($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasEfficiencyCores() => $_has(6);
  @$pb.TagNumber(7)
  void clearEfficiencyCores() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get architecture => $_getSZ(7);
  @$pb.TagNumber(8)
  set architecture($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasArchitecture() => $_has(7);
  @$pb.TagNumber(8)
  void clearArchitecture() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get platform => $_getSZ(8);
  @$pb.TagNumber(9)
  set platform($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasPlatform() => $_has(8);
  @$pb.TagNumber(9)
  void clearPlatform() => $_clearField(9);

  @$pb.TagNumber(10)
  $0.NPUChip get npuChip => $_getN(9);
  @$pb.TagNumber(10)
  set npuChip($0.NPUChip value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasNpuChip() => $_has(9);
  @$pb.TagNumber(10)
  void clearNpuChip() => $_clearField(10);
}

class AcceleratorInfo extends $pb.GeneratedMessage {
  factory AcceleratorInfo({
    $core.String? name,
    AccelerationPreference? type,
    $core.bool? available,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (type != null) result.type = type;
    if (available != null) result.available = available;
    return result;
  }

  AcceleratorInfo._();

  factory AcceleratorInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AcceleratorInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AcceleratorInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aE<AccelerationPreference>(2, _omitFieldNames ? '' : 'type',
        enumValues: AccelerationPreference.values)
    ..aOB(3, _omitFieldNames ? '' : 'available')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AcceleratorInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AcceleratorInfo copyWith(void Function(AcceleratorInfo) updates) =>
      super.copyWith((message) => updates(message as AcceleratorInfo))
          as AcceleratorInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AcceleratorInfo create() => AcceleratorInfo._();
  @$core.override
  AcceleratorInfo createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AcceleratorInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AcceleratorInfo>(create);
  static AcceleratorInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  AccelerationPreference get type => $_getN(1);
  @$pb.TagNumber(2)
  set type(AccelerationPreference value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get available => $_getBF(2);
  @$pb.TagNumber(3)
  set available($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAvailable() => $_has(2);
  @$pb.TagNumber(3)
  void clearAvailable() => $_clearField(3);
}

class HardwareProfileResult extends $pb.GeneratedMessage {
  factory HardwareProfileResult({
    HardwareProfile? profile,
    $core.Iterable<AcceleratorInfo>? accelerators,
  }) {
    final result = create();
    if (profile != null) result.profile = profile;
    if (accelerators != null) result.accelerators.addAll(accelerators);
    return result;
  }

  HardwareProfileResult._();

  factory HardwareProfileResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HardwareProfileResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HardwareProfileResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOM<HardwareProfile>(1, _omitFieldNames ? '' : 'profile',
        subBuilder: HardwareProfile.create)
    ..pPM<AcceleratorInfo>(2, _omitFieldNames ? '' : 'accelerators',
        subBuilder: AcceleratorInfo.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HardwareProfileResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HardwareProfileResult copyWith(
          void Function(HardwareProfileResult) updates) =>
      super.copyWith((message) => updates(message as HardwareProfileResult))
          as HardwareProfileResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HardwareProfileResult create() => HardwareProfileResult._();
  @$core.override
  HardwareProfileResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HardwareProfileResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HardwareProfileResult>(create);
  static HardwareProfileResult? _defaultInstance;

  @$pb.TagNumber(1)
  HardwareProfile get profile => $_getN(0);
  @$pb.TagNumber(1)
  set profile(HardwareProfile value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasProfile() => $_has(0);
  @$pb.TagNumber(1)
  void clearProfile() => $_clearField(1);
  @$pb.TagNumber(1)
  HardwareProfile ensureProfile() => $_ensure(0);

  @$pb.TagNumber(2)
  $pb.PbList<AcceleratorInfo> get accelerators => $_getList(1);
}

/// Empty request for the cached hardware profile. The native probe is owned by
/// platform adapters; this request carries no portable parameters today.
class HardwareProfileRequest extends $pb.GeneratedMessage {
  factory HardwareProfileRequest() => create();

  HardwareProfileRequest._();

  factory HardwareProfileRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HardwareProfileRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HardwareProfileRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HardwareProfileRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HardwareProfileRequest copyWith(
          void Function(HardwareProfileRequest) updates) =>
      super.copyWith((message) => updates(message as HardwareProfileRequest))
          as HardwareProfileRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HardwareProfileRequest create() => HardwareProfileRequest._();
  @$core.override
  HardwareProfileRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HardwareProfileRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HardwareProfileRequest>(create);
  static HardwareProfileRequest? _defaultInstance;
}

/// Empty request for the accelerator list. Mirrors HardwareProfileRequest:
/// platform probes own all OS-level acceleration discovery.
class HardwareAcceleratorsRequest extends $pb.GeneratedMessage {
  factory HardwareAcceleratorsRequest() => create();

  HardwareAcceleratorsRequest._();

  factory HardwareAcceleratorsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HardwareAcceleratorsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HardwareAcceleratorsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HardwareAcceleratorsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HardwareAcceleratorsRequest copyWith(
          void Function(HardwareAcceleratorsRequest) updates) =>
      super.copyWith(
              (message) => updates(message as HardwareAcceleratorsRequest))
          as HardwareAcceleratorsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HardwareAcceleratorsRequest create() =>
      HardwareAcceleratorsRequest._();
  @$core.override
  HardwareAcceleratorsRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HardwareAcceleratorsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HardwareAcceleratorsRequest>(create);
  static HardwareAcceleratorsRequest? _defaultInstance;
}

/// Result-shaped response for SetAcceleratorPreference so the service contract
/// stays consistent (every rpc returns a non-empty message).
class HardwareAcceleratorPreferenceRequest extends $pb.GeneratedMessage {
  factory HardwareAcceleratorPreferenceRequest({
    AccelerationPreference? preference,
  }) {
    final result = create();
    if (preference != null) result.preference = preference;
    return result;
  }

  HardwareAcceleratorPreferenceRequest._();

  factory HardwareAcceleratorPreferenceRequest.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HardwareAcceleratorPreferenceRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HardwareAcceleratorPreferenceRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<AccelerationPreference>(1, _omitFieldNames ? '' : 'preference',
        enumValues: AccelerationPreference.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HardwareAcceleratorPreferenceRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HardwareAcceleratorPreferenceRequest copyWith(
          void Function(HardwareAcceleratorPreferenceRequest) updates) =>
      super.copyWith((message) =>
              updates(message as HardwareAcceleratorPreferenceRequest))
          as HardwareAcceleratorPreferenceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HardwareAcceleratorPreferenceRequest create() =>
      HardwareAcceleratorPreferenceRequest._();
  @$core.override
  HardwareAcceleratorPreferenceRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HardwareAcceleratorPreferenceRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          HardwareAcceleratorPreferenceRequest>(create);
  static HardwareAcceleratorPreferenceRequest? _defaultInstance;

  @$pb.TagNumber(1)
  AccelerationPreference get preference => $_getN(0);
  @$pb.TagNumber(1)
  set preference(AccelerationPreference value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPreference() => $_has(0);
  @$pb.TagNumber(1)
  void clearPreference() => $_clearField(1);
}

class HardwareAcceleratorPreferenceResult extends $pb.GeneratedMessage {
  factory HardwareAcceleratorPreferenceResult({
    $core.bool? success,
    $core.String? errorMessage,
  }) {
    final result = create();
    if (success != null) result.success = success;
    if (errorMessage != null) result.errorMessage = errorMessage;
    return result;
  }

  HardwareAcceleratorPreferenceResult._();

  factory HardwareAcceleratorPreferenceResult.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HardwareAcceleratorPreferenceResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HardwareAcceleratorPreferenceResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aOS(2, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HardwareAcceleratorPreferenceResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HardwareAcceleratorPreferenceResult copyWith(
          void Function(HardwareAcceleratorPreferenceResult) updates) =>
      super.copyWith((message) =>
              updates(message as HardwareAcceleratorPreferenceResult))
          as HardwareAcceleratorPreferenceResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HardwareAcceleratorPreferenceResult create() =>
      HardwareAcceleratorPreferenceResult._();
  @$core.override
  HardwareAcceleratorPreferenceResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HardwareAcceleratorPreferenceResult getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          HardwareAcceleratorPreferenceResult>(create);
  static HardwareAcceleratorPreferenceResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get errorMessage => $_getSZ(1);
  @$pb.TagNumber(2)
  set errorMessage($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasErrorMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearErrorMessage() => $_clearField(2);
}

class NpuCapability extends $pb.GeneratedMessage {
  factory NpuCapability({
    $core.String? socModel,
    $core.int? socId,
    HexagonArch? hexagonArch,
    $core.bool? qhexrtSupported,
    $core.String? archName,
  }) {
    final result = create();
    if (socModel != null) result.socModel = socModel;
    if (socId != null) result.socId = socId;
    if (hexagonArch != null) result.hexagonArch = hexagonArch;
    if (qhexrtSupported != null) result.qhexrtSupported = qhexrtSupported;
    if (archName != null) result.archName = archName;
    return result;
  }

  NpuCapability._();

  factory NpuCapability.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory NpuCapability.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NpuCapability',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'socModel')
    ..aI(2, _omitFieldNames ? '' : 'socId')
    ..aE<HexagonArch>(3, _omitFieldNames ? '' : 'hexagonArch',
        enumValues: HexagonArch.values)
    ..aOB(4, _omitFieldNames ? '' : 'qhexrtSupported')
    ..aOS(5, _omitFieldNames ? '' : 'archName')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NpuCapability clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NpuCapability copyWith(void Function(NpuCapability) updates) =>
      super.copyWith((message) => updates(message as NpuCapability))
          as NpuCapability;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static NpuCapability create() => NpuCapability._();
  @$core.override
  NpuCapability createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static NpuCapability getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NpuCapability>(create);
  static NpuCapability? _defaultInstance;

  /// Vendor SoC model (e.g. "SM8750"); empty when unknown.
  @$pb.TagNumber(1)
  $core.String get socModel => $_getSZ(0);
  @$pb.TagNumber(1)
  set socModel($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSocModel() => $_has(0);
  @$pb.TagNumber(1)
  void clearSocModel() => $_clearField(1);

  /// /sys/devices/soc0/soc_id value; -1 when unavailable.
  @$pb.TagNumber(2)
  $core.int get socId => $_getIZ(1);
  @$pb.TagNumber(2)
  set socId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSocId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSocId() => $_clearField(2);

  @$pb.TagNumber(3)
  HexagonArch get hexagonArch => $_getN(2);
  @$pb.TagNumber(3)
  set hexagonArch(HexagonArch value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasHexagonArch() => $_has(2);
  @$pb.TagNumber(3)
  void clearHexagonArch() => $_clearField(3);

  /// True iff hexagon_arch is in the QHexRT-supported set (v75/v79/v81 today).
  @$pb.TagNumber(4)
  $core.bool get qhexrtSupported => $_getBF(3);
  @$pb.TagNumber(4)
  set qhexrtSupported($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasQhexrtSupported() => $_has(3);
  @$pb.TagNumber(4)
  void clearQhexrtSupported() => $_clearField(4);

  /// rac_hexagon_arch_name(): "v68" ... "v81", "unknown". Materialized so
  /// SDKs never re-derive the display name from the enum.
  @$pb.TagNumber(5)
  $core.String get archName => $_getSZ(4);
  @$pb.TagNumber(5)
  set archName($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasArchName() => $_has(4);
  @$pb.TagNumber(5)
  void clearArchName() => $_clearField(5);
}

/// Empty request for the NPU probe; mirrors HardwareProfileRequest.
class NpuProbeRequest extends $pb.GeneratedMessage {
  factory NpuProbeRequest() => create();

  NpuProbeRequest._();

  factory NpuProbeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory NpuProbeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NpuProbeRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NpuProbeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NpuProbeRequest copyWith(void Function(NpuProbeRequest) updates) =>
      super.copyWith((message) => updates(message as NpuProbeRequest))
          as NpuProbeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static NpuProbeRequest create() => NpuProbeRequest._();
  @$core.override
  NpuProbeRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static NpuProbeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NpuProbeRequest>(create);
  static NpuProbeRequest? _defaultInstance;
}

class HardwareApi {
  final $pb.RpcClient _client;

  HardwareApi(this._client);

  $async.Future<HardwareProfileResult> getProfile(
          $pb.ClientContext? ctx, HardwareProfileRequest request) =>
      _client.invoke<HardwareProfileResult>(
          ctx, 'Hardware', 'GetProfile', request, HardwareProfileResult());
  $async.Future<HardwareProfileResult> getAccelerators(
          $pb.ClientContext? ctx, HardwareAcceleratorsRequest request) =>
      _client.invoke<HardwareProfileResult>(
          ctx, 'Hardware', 'GetAccelerators', request, HardwareProfileResult());
  $async.Future<HardwareAcceleratorPreferenceResult> setAcceleratorPreference(
          $pb.ClientContext? ctx,
          HardwareAcceleratorPreferenceRequest request) =>
      _client.invoke<HardwareAcceleratorPreferenceResult>(
          ctx,
          'Hardware',
          'SetAcceleratorPreference',
          request,
          HardwareAcceleratorPreferenceResult());

  /// Pre-flight Hexagon NPU capability (rac_npu_probe_proto).
  $async.Future<NpuCapability> probeNpu(
          $pb.ClientContext? ctx, NpuProbeRequest request) =>
      _client.invoke<NpuCapability>(
          ctx, 'Hardware', 'ProbeNpu', request, NpuCapability());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
