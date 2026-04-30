///
//  Generated code. Do not modify.
//  source: hardware_profile.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'hardware_profile.pbenum.dart';

export 'hardware_profile.pbenum.dart';

class HardwareProfile extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'HardwareProfile', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'chip')
    ..aOB(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'hasNeuralEngine')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'accelerationMode')
    ..a<$fixnum.Int64>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'totalMemoryBytes', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.int>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'coreCount', $pb.PbFieldType.OU3)
    ..a<$core.int>(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'performanceCores', $pb.PbFieldType.OU3)
    ..a<$core.int>(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'efficiencyCores', $pb.PbFieldType.OU3)
    ..aOS(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'architecture')
    ..aOS(9, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'platform')
    ..hasRequiredFields = false
  ;

  HardwareProfile._() : super();
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
  }) {
    final _result = create();
    if (chip != null) {
      _result.chip = chip;
    }
    if (hasNeuralEngine != null) {
      _result.hasNeuralEngine = hasNeuralEngine;
    }
    if (accelerationMode != null) {
      _result.accelerationMode = accelerationMode;
    }
    if (totalMemoryBytes != null) {
      _result.totalMemoryBytes = totalMemoryBytes;
    }
    if (coreCount != null) {
      _result.coreCount = coreCount;
    }
    if (performanceCores != null) {
      _result.performanceCores = performanceCores;
    }
    if (efficiencyCores != null) {
      _result.efficiencyCores = efficiencyCores;
    }
    if (architecture != null) {
      _result.architecture = architecture;
    }
    if (platform != null) {
      _result.platform = platform;
    }
    return _result;
  }
  factory HardwareProfile.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory HardwareProfile.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  HardwareProfile clone() => HardwareProfile()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  HardwareProfile copyWith(void Function(HardwareProfile) updates) => super.copyWith((message) => updates(message as HardwareProfile)) as HardwareProfile; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static HardwareProfile create() => HardwareProfile._();
  HardwareProfile createEmptyInstance() => create();
  static $pb.PbList<HardwareProfile> createRepeated() => $pb.PbList<HardwareProfile>();
  @$core.pragma('dart2js:noInline')
  static HardwareProfile getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<HardwareProfile>(create);
  static HardwareProfile? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get chip => $_getSZ(0);
  @$pb.TagNumber(1)
  set chip($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChip() => $_has(0);
  @$pb.TagNumber(1)
  void clearChip() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get hasNeuralEngine => $_getBF(1);
  @$pb.TagNumber(2)
  set hasNeuralEngine($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasHasNeuralEngine() => $_has(1);
  @$pb.TagNumber(2)
  void clearHasNeuralEngine() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get accelerationMode => $_getSZ(2);
  @$pb.TagNumber(3)
  set accelerationMode($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAccelerationMode() => $_has(2);
  @$pb.TagNumber(3)
  void clearAccelerationMode() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get totalMemoryBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set totalMemoryBytes($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTotalMemoryBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalMemoryBytes() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get coreCount => $_getIZ(4);
  @$pb.TagNumber(5)
  set coreCount($core.int v) { $_setUnsignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasCoreCount() => $_has(4);
  @$pb.TagNumber(5)
  void clearCoreCount() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get performanceCores => $_getIZ(5);
  @$pb.TagNumber(6)
  set performanceCores($core.int v) { $_setUnsignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasPerformanceCores() => $_has(5);
  @$pb.TagNumber(6)
  void clearPerformanceCores() => clearField(6);

  @$pb.TagNumber(7)
  $core.int get efficiencyCores => $_getIZ(6);
  @$pb.TagNumber(7)
  set efficiencyCores($core.int v) { $_setUnsignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasEfficiencyCores() => $_has(6);
  @$pb.TagNumber(7)
  void clearEfficiencyCores() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get architecture => $_getSZ(7);
  @$pb.TagNumber(8)
  set architecture($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasArchitecture() => $_has(7);
  @$pb.TagNumber(8)
  void clearArchitecture() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get platform => $_getSZ(8);
  @$pb.TagNumber(9)
  set platform($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasPlatform() => $_has(8);
  @$pb.TagNumber(9)
  void clearPlatform() => clearField(9);
}

class AcceleratorInfo extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'AcceleratorInfo', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'name')
    ..e<AcceleratorPreference>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'type', $pb.PbFieldType.OE, defaultOrMaker: AcceleratorPreference.ACCELERATOR_PREFERENCE_AUTO, valueOf: AcceleratorPreference.valueOf, enumValues: AcceleratorPreference.values)
    ..aOB(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'available')
    ..hasRequiredFields = false
  ;

  AcceleratorInfo._() : super();
  factory AcceleratorInfo({
    $core.String? name,
    AcceleratorPreference? type,
    $core.bool? available,
  }) {
    final _result = create();
    if (name != null) {
      _result.name = name;
    }
    if (type != null) {
      _result.type = type;
    }
    if (available != null) {
      _result.available = available;
    }
    return _result;
  }
  factory AcceleratorInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AcceleratorInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AcceleratorInfo clone() => AcceleratorInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AcceleratorInfo copyWith(void Function(AcceleratorInfo) updates) => super.copyWith((message) => updates(message as AcceleratorInfo)) as AcceleratorInfo; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static AcceleratorInfo create() => AcceleratorInfo._();
  AcceleratorInfo createEmptyInstance() => create();
  static $pb.PbList<AcceleratorInfo> createRepeated() => $pb.PbList<AcceleratorInfo>();
  @$core.pragma('dart2js:noInline')
  static AcceleratorInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AcceleratorInfo>(create);
  static AcceleratorInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  @$pb.TagNumber(2)
  AcceleratorPreference get type => $_getN(1);
  @$pb.TagNumber(2)
  set type(AcceleratorPreference v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get available => $_getBF(2);
  @$pb.TagNumber(3)
  set available($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAvailable() => $_has(2);
  @$pb.TagNumber(3)
  void clearAvailable() => clearField(3);
}

class HardwareProfileResult extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'HardwareProfileResult', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOM<HardwareProfile>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'profile', subBuilder: HardwareProfile.create)
    ..pc<AcceleratorInfo>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'accelerators', $pb.PbFieldType.PM, subBuilder: AcceleratorInfo.create)
    ..hasRequiredFields = false
  ;

  HardwareProfileResult._() : super();
  factory HardwareProfileResult({
    HardwareProfile? profile,
    $core.Iterable<AcceleratorInfo>? accelerators,
  }) {
    final _result = create();
    if (profile != null) {
      _result.profile = profile;
    }
    if (accelerators != null) {
      _result.accelerators.addAll(accelerators);
    }
    return _result;
  }
  factory HardwareProfileResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory HardwareProfileResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  HardwareProfileResult clone() => HardwareProfileResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  HardwareProfileResult copyWith(void Function(HardwareProfileResult) updates) => super.copyWith((message) => updates(message as HardwareProfileResult)) as HardwareProfileResult; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static HardwareProfileResult create() => HardwareProfileResult._();
  HardwareProfileResult createEmptyInstance() => create();
  static $pb.PbList<HardwareProfileResult> createRepeated() => $pb.PbList<HardwareProfileResult>();
  @$core.pragma('dart2js:noInline')
  static HardwareProfileResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<HardwareProfileResult>(create);
  static HardwareProfileResult? _defaultInstance;

  @$pb.TagNumber(1)
  HardwareProfile get profile => $_getN(0);
  @$pb.TagNumber(1)
  set profile(HardwareProfile v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasProfile() => $_has(0);
  @$pb.TagNumber(1)
  void clearProfile() => clearField(1);
  @$pb.TagNumber(1)
  HardwareProfile ensureProfile() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.List<AcceleratorInfo> get accelerators => $_getList(1);
}

