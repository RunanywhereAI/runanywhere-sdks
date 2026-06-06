// This is a generated file - do not edit.
//
// Generated from device_info.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class DeviceInfo extends $pb.GeneratedMessage {
  factory DeviceInfo({
    $core.String? deviceModel,
    $core.String? deviceName,
    $core.String? platform,
    $core.String? osVersion,
    $core.String? formFactor,
    $core.String? architecture,
    $core.String? chipName,
    $fixnum.Int64? totalMemory,
    $fixnum.Int64? availableMemory,
    $core.bool? hasNeuralEngine,
    $core.int? neuralEngineCores,
    $core.String? gpuFamily,
    $core.double? batteryLevel,
    $core.String? batteryState,
    $core.bool? isLowPowerMode,
    $core.int? coreCount,
    $core.int? performanceCores,
    $core.int? efficiencyCores,
    $core.String? deviceFingerprint,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? platformExtras,
  }) {
    final result = create();
    if (deviceModel != null) result.deviceModel = deviceModel;
    if (deviceName != null) result.deviceName = deviceName;
    if (platform != null) result.platform = platform;
    if (osVersion != null) result.osVersion = osVersion;
    if (formFactor != null) result.formFactor = formFactor;
    if (architecture != null) result.architecture = architecture;
    if (chipName != null) result.chipName = chipName;
    if (totalMemory != null) result.totalMemory = totalMemory;
    if (availableMemory != null) result.availableMemory = availableMemory;
    if (hasNeuralEngine != null) result.hasNeuralEngine = hasNeuralEngine;
    if (neuralEngineCores != null) result.neuralEngineCores = neuralEngineCores;
    if (gpuFamily != null) result.gpuFamily = gpuFamily;
    if (batteryLevel != null) result.batteryLevel = batteryLevel;
    if (batteryState != null) result.batteryState = batteryState;
    if (isLowPowerMode != null) result.isLowPowerMode = isLowPowerMode;
    if (coreCount != null) result.coreCount = coreCount;
    if (performanceCores != null) result.performanceCores = performanceCores;
    if (efficiencyCores != null) result.efficiencyCores = efficiencyCores;
    if (deviceFingerprint != null) result.deviceFingerprint = deviceFingerprint;
    if (platformExtras != null)
      result.platformExtras.addEntries(platformExtras);
    return result;
  }

  DeviceInfo._();

  factory DeviceInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DeviceInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeviceInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'deviceModel')
    ..aOS(2, _omitFieldNames ? '' : 'deviceName')
    ..aOS(3, _omitFieldNames ? '' : 'platform')
    ..aOS(4, _omitFieldNames ? '' : 'osVersion')
    ..aOS(5, _omitFieldNames ? '' : 'formFactor')
    ..aOS(6, _omitFieldNames ? '' : 'architecture')
    ..aOS(7, _omitFieldNames ? '' : 'chipName')
    ..aInt64(8, _omitFieldNames ? '' : 'totalMemory')
    ..aInt64(9, _omitFieldNames ? '' : 'availableMemory')
    ..aOB(10, _omitFieldNames ? '' : 'hasNeuralEngine')
    ..aI(11, _omitFieldNames ? '' : 'neuralEngineCores')
    ..aOS(12, _omitFieldNames ? '' : 'gpuFamily')
    ..aD(13, _omitFieldNames ? '' : 'batteryLevel',
        fieldType: $pb.PbFieldType.OF)
    ..aOS(14, _omitFieldNames ? '' : 'batteryState')
    ..aOB(15, _omitFieldNames ? '' : 'isLowPowerMode')
    ..aI(16, _omitFieldNames ? '' : 'coreCount')
    ..aI(17, _omitFieldNames ? '' : 'performanceCores')
    ..aI(18, _omitFieldNames ? '' : 'efficiencyCores')
    ..aOS(19, _omitFieldNames ? '' : 'deviceFingerprint')
    ..m<$core.String, $core.String>(20, _omitFieldNames ? '' : 'platformExtras',
        entryClassName: 'DeviceInfo.PlatformExtrasEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceInfo copyWith(void Function(DeviceInfo) updates) =>
      super.copyWith((message) => updates(message as DeviceInfo)) as DeviceInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeviceInfo create() => DeviceInfo._();
  @$core.override
  DeviceInfo createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DeviceInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeviceInfo>(create);
  static DeviceInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get deviceModel => $_getSZ(0);
  @$pb.TagNumber(1)
  set deviceModel($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDeviceModel() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceModel() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get deviceName => $_getSZ(1);
  @$pb.TagNumber(2)
  set deviceName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDeviceName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get platform => $_getSZ(2);
  @$pb.TagNumber(3)
  set platform($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPlatform() => $_has(2);
  @$pb.TagNumber(3)
  void clearPlatform() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get osVersion => $_getSZ(3);
  @$pb.TagNumber(4)
  set osVersion($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasOsVersion() => $_has(3);
  @$pb.TagNumber(4)
  void clearOsVersion() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get formFactor => $_getSZ(4);
  @$pb.TagNumber(5)
  set formFactor($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasFormFactor() => $_has(4);
  @$pb.TagNumber(5)
  void clearFormFactor() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get architecture => $_getSZ(5);
  @$pb.TagNumber(6)
  set architecture($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasArchitecture() => $_has(5);
  @$pb.TagNumber(6)
  void clearArchitecture() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get chipName => $_getSZ(6);
  @$pb.TagNumber(7)
  set chipName($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasChipName() => $_has(6);
  @$pb.TagNumber(7)
  void clearChipName() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get totalMemory => $_getI64(7);
  @$pb.TagNumber(8)
  set totalMemory($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasTotalMemory() => $_has(7);
  @$pb.TagNumber(8)
  void clearTotalMemory() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get availableMemory => $_getI64(8);
  @$pb.TagNumber(9)
  set availableMemory($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasAvailableMemory() => $_has(8);
  @$pb.TagNumber(9)
  void clearAvailableMemory() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.bool get hasNeuralEngine => $_getBF(9);
  @$pb.TagNumber(10)
  set hasNeuralEngine($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(10)
  $core.bool hasHasNeuralEngine() => $_has(9);
  @$pb.TagNumber(10)
  void clearHasNeuralEngine() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.int get neuralEngineCores => $_getIZ(10);
  @$pb.TagNumber(11)
  set neuralEngineCores($core.int value) => $_setSignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasNeuralEngineCores() => $_has(10);
  @$pb.TagNumber(11)
  void clearNeuralEngineCores() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get gpuFamily => $_getSZ(11);
  @$pb.TagNumber(12)
  set gpuFamily($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasGpuFamily() => $_has(11);
  @$pb.TagNumber(12)
  void clearGpuFamily() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.double get batteryLevel => $_getN(12);
  @$pb.TagNumber(13)
  set batteryLevel($core.double value) => $_setFloat(12, value);
  @$pb.TagNumber(13)
  $core.bool hasBatteryLevel() => $_has(12);
  @$pb.TagNumber(13)
  void clearBatteryLevel() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get batteryState => $_getSZ(13);
  @$pb.TagNumber(14)
  set batteryState($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasBatteryState() => $_has(13);
  @$pb.TagNumber(14)
  void clearBatteryState() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.bool get isLowPowerMode => $_getBF(14);
  @$pb.TagNumber(15)
  set isLowPowerMode($core.bool value) => $_setBool(14, value);
  @$pb.TagNumber(15)
  $core.bool hasIsLowPowerMode() => $_has(14);
  @$pb.TagNumber(15)
  void clearIsLowPowerMode() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.int get coreCount => $_getIZ(15);
  @$pb.TagNumber(16)
  set coreCount($core.int value) => $_setSignedInt32(15, value);
  @$pb.TagNumber(16)
  $core.bool hasCoreCount() => $_has(15);
  @$pb.TagNumber(16)
  void clearCoreCount() => $_clearField(16);

  @$pb.TagNumber(17)
  $core.int get performanceCores => $_getIZ(16);
  @$pb.TagNumber(17)
  set performanceCores($core.int value) => $_setSignedInt32(16, value);
  @$pb.TagNumber(17)
  $core.bool hasPerformanceCores() => $_has(16);
  @$pb.TagNumber(17)
  void clearPerformanceCores() => $_clearField(17);

  @$pb.TagNumber(18)
  $core.int get efficiencyCores => $_getIZ(17);
  @$pb.TagNumber(18)
  set efficiencyCores($core.int value) => $_setSignedInt32(17, value);
  @$pb.TagNumber(18)
  $core.bool hasEfficiencyCores() => $_has(17);
  @$pb.TagNumber(18)
  void clearEfficiencyCores() => $_clearField(18);

  @$pb.TagNumber(19)
  $core.String get deviceFingerprint => $_getSZ(18);
  @$pb.TagNumber(19)
  set deviceFingerprint($core.String value) => $_setString(18, value);
  @$pb.TagNumber(19)
  $core.bool hasDeviceFingerprint() => $_has(18);
  @$pb.TagNumber(19)
  void clearDeviceFingerprint() => $_clearField(19);

  /// Platform-specific fields that are not part of the cross-SDK core
  /// (e.g. web: "has_webgpu", "has_shared_array_buffer"; android: "manufacturer",
  /// "android_api_level", "os_build_id", ...).
  @$pb.TagNumber(20)
  $pb.PbMap<$core.String, $core.String> get platformExtras => $_getMap(19);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
