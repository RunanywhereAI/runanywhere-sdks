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

import 'device_info.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'device_info.pbenum.dart';

class DeviceInfo extends $pb.GeneratedMessage {
  factory DeviceInfo({
    $core.String? deviceModel,
    Platform? platform,
    $core.String? osVersion,
    FormFactor? formFactor,
    $core.String? architecture,
    $core.String? chipName,
    $fixnum.Int64? totalMemoryBytes,
    $fixnum.Int64? availableMemoryBytes,
    $core.bool? hasNpu,
    $core.int? npuCores,
    $core.String? gpuFamily,
    $core.double? batteryLevel,
    BatteryState? batteryState,
    $core.bool? isLowPowerMode,
    $core.int? coreCount,
    $core.int? performanceCores,
    $core.String? deviceFingerprint,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? platformExtras,
  }) {
    final result = create();
    if (deviceModel != null) result.deviceModel = deviceModel;
    if (platform != null) result.platform = platform;
    if (osVersion != null) result.osVersion = osVersion;
    if (formFactor != null) result.formFactor = formFactor;
    if (architecture != null) result.architecture = architecture;
    if (chipName != null) result.chipName = chipName;
    if (totalMemoryBytes != null) result.totalMemoryBytes = totalMemoryBytes;
    if (availableMemoryBytes != null)
      result.availableMemoryBytes = availableMemoryBytes;
    if (hasNpu != null) result.hasNpu = hasNpu;
    if (npuCores != null) result.npuCores = npuCores;
    if (gpuFamily != null) result.gpuFamily = gpuFamily;
    if (batteryLevel != null) result.batteryLevel = batteryLevel;
    if (batteryState != null) result.batteryState = batteryState;
    if (isLowPowerMode != null) result.isLowPowerMode = isLowPowerMode;
    if (coreCount != null) result.coreCount = coreCount;
    if (performanceCores != null) result.performanceCores = performanceCores;
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
    ..aE<Platform>(2, _omitFieldNames ? '' : 'platform',
        enumValues: Platform.values)
    ..aOS(3, _omitFieldNames ? '' : 'osVersion')
    ..aE<FormFactor>(4, _omitFieldNames ? '' : 'formFactor',
        enumValues: FormFactor.values)
    ..aOS(5, _omitFieldNames ? '' : 'architecture')
    ..aOS(6, _omitFieldNames ? '' : 'chipName')
    ..aInt64(7, _omitFieldNames ? '' : 'totalMemoryBytes')
    ..aInt64(8, _omitFieldNames ? '' : 'availableMemoryBytes')
    ..aOB(9, _omitFieldNames ? '' : 'hasNpu')
    ..aI(10, _omitFieldNames ? '' : 'npuCores')
    ..aOS(11, _omitFieldNames ? '' : 'gpuFamily')
    ..aD(12, _omitFieldNames ? '' : 'batteryLevel',
        fieldType: $pb.PbFieldType.OF)
    ..aE<BatteryState>(13, _omitFieldNames ? '' : 'batteryState',
        enumValues: BatteryState.values)
    ..aOB(14, _omitFieldNames ? '' : 'isLowPowerMode')
    ..aI(15, _omitFieldNames ? '' : 'coreCount')
    ..aI(16, _omitFieldNames ? '' : 'performanceCores')
    ..aOS(17, _omitFieldNames ? '' : 'deviceFingerprint')
    ..m<$core.String, $core.String>(18, _omitFieldNames ? '' : 'platformExtras',
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
  Platform get platform => $_getN(1);
  @$pb.TagNumber(2)
  set platform(Platform value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPlatform() => $_has(1);
  @$pb.TagNumber(2)
  void clearPlatform() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get osVersion => $_getSZ(2);
  @$pb.TagNumber(3)
  set osVersion($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasOsVersion() => $_has(2);
  @$pb.TagNumber(3)
  void clearOsVersion() => $_clearField(3);

  @$pb.TagNumber(4)
  FormFactor get formFactor => $_getN(3);
  @$pb.TagNumber(4)
  set formFactor(FormFactor value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasFormFactor() => $_has(3);
  @$pb.TagNumber(4)
  void clearFormFactor() => $_clearField(4);

  /// ABI name as the OS reports it: Android sends Build.SUPPORTED_ABIS[0]
  /// ("arm64-v8a"), Apple "arm64", Web "wasm32". Kept a string because no
  /// industry API enumerates ABIs — but the spelling is the OS's, not ours.
  @$pb.TagNumber(5)
  $core.String get architecture => $_getSZ(4);
  @$pb.TagNumber(5)
  set architecture($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasArchitecture() => $_has(4);
  @$pb.TagNumber(5)
  void clearArchitecture() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get chipName => $_getSZ(5);
  @$pb.TagNumber(6)
  set chipName($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasChipName() => $_has(5);
  @$pb.TagNumber(6)
  void clearChipName() => $_clearField(6);

  /// Physical RAM installed, in BYTES. Never the JVM heap cap — Android must
  /// read ActivityManager.MemoryInfo.totalMem, not Runtime.maxMemory().
  @$pb.TagNumber(7)
  $fixnum.Int64 get totalMemoryBytes => $_getI64(6);
  @$pb.TagNumber(7)
  set totalMemoryBytes($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasTotalMemoryBytes() => $_has(6);
  @$pb.TagNumber(7)
  void clearTotalMemoryBytes() => $_clearField(7);

  /// Free + reclaimable system RAM at snapshot time, in BYTES.
  /// 0 = UNKNOWN (the Web producer cannot read it). A consumer MUST NOT read
  /// 0 as "no memory left" and refuse to load.
  @$pb.TagNumber(8)
  $fixnum.Int64 get availableMemoryBytes => $_getI64(7);
  @$pb.TagNumber(8)
  set availableMemoryBytes($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasAvailableMemoryBytes() => $_has(7);
  @$pb.TagNumber(8)
  void clearAvailableMemoryBytes() => $_clearField(8);

  /// Dedicated neural accelerator present (ANE, Hexagon, APU, ...).
  @$pb.TagNumber(9)
  $core.bool get hasNpu => $_getBF(8);
  @$pb.TagNumber(9)
  set hasNpu($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasHasNpu() => $_has(8);
  @$pb.TagNumber(9)
  void clearHasNpu() => $_clearField(9);

  /// 0 = none OR present-but-unreported.
  @$pb.TagNumber(10)
  $core.int get npuCores => $_getIZ(9);
  @$pb.TagNumber(10)
  set npuCores($core.int value) => $_setSignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasNpuCores() => $_has(9);
  @$pb.TagNumber(10)
  void clearNpuCores() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get gpuFamily => $_getSZ(10);
  @$pb.TagNumber(11)
  set gpuFamily($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasGpuFamily() => $_has(10);
  @$pb.TagNumber(11)
  void clearGpuFamily() => $_clearField(11);

  /// Remaining charge as a fraction of full. ABSENT is the ONLY encoding of
  /// "unknown" — 0.0 means a flat battery, not an unreadable one. Producers
  /// bridging through rac_device_registration_info_t (which uses a negative
  /// sentinel) MUST map negative -> absent, never negative -> 0.
  @$pb.TagNumber(12)
  $core.double get batteryLevel => $_getN(11);
  @$pb.TagNumber(12)
  set batteryLevel($core.double value) => $_setFloat(11, value);
  @$pb.TagNumber(12)
  $core.bool hasBatteryLevel() => $_has(11);
  @$pb.TagNumber(12)
  void clearBatteryLevel() => $_clearField(12);

  /// ABSENT when the platform reports no battery at all; UNSPECIFIED when a
  /// battery exists but its state could not be read. The C ABI member is
  /// documented NULL-if-unavailable, which is why this stays `optional`.
  @$pb.TagNumber(13)
  BatteryState get batteryState => $_getN(12);
  @$pb.TagNumber(13)
  set batteryState(BatteryState value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasBatteryState() => $_has(12);
  @$pb.TagNumber(13)
  void clearBatteryState() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.bool get isLowPowerMode => $_getBF(13);
  @$pb.TagNumber(14)
  set isLowPowerMode($core.bool value) => $_setBool(13, value);
  @$pb.TagNumber(14)
  $core.bool hasIsLowPowerMode() => $_has(13);
  @$pb.TagNumber(14)
  void clearIsLowPowerMode() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.int get coreCount => $_getIZ(14);
  @$pb.TagNumber(15)
  set coreCount($core.int value) => $_setSignedInt32(14, value);
  @$pb.TagNumber(15)
  $core.bool hasCoreCount() => $_has(14);
  @$pb.TagNumber(15)
  void clearCoreCount() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.int get performanceCores => $_getIZ(15);
  @$pb.TagNumber(16)
  set performanceCores($core.int value) => $_setSignedInt32(15, value);
  @$pb.TagNumber(16)
  $core.bool hasPerformanceCores() => $_has(15);
  @$pb.TagNumber(16)
  void clearPerformanceCores() => $_clearField(16);

  @$pb.TagNumber(17)
  $core.String get deviceFingerprint => $_getSZ(16);
  @$pb.TagNumber(17)
  set deviceFingerprint($core.String value) => $_setString(16, value);
  @$pb.TagNumber(17)
  $core.bool hasDeviceFingerprint() => $_has(16);
  @$pb.TagNumber(17)
  void clearDeviceFingerprint() => $_clearField(17);

  /// Vendor escape hatch, CLOSED key set:
  ///   android: "manufacturer", "device_id", "os_build_id", "sdk_version",
  ///            "android_api_level", "locale", "timezone"
  ///   web:     "has_webgpu", "has_shared_array_buffer"
  ///
  /// "manufacturer" and "device_id" are the only two the native parser reads
  /// ("device_id" arrives as a promoted top-level JSON key). Keys not listed
  /// here are NOT dropped: the Kotlin serializer flattens them into the
  /// outbound registration body verbatim, where no client code reads them.
  ///
  /// A key that restates a typed field above MUST NOT be sent — "device_type",
  /// "os_name", "processor_count" and "is_simulator" were removed for exactly
  /// that reason, and "device_id" duplicates device_fingerprint and should
  /// follow once the native parser reads the typed field instead.
  ///
  /// Values are always strings. This map does not cross the C ABI on Apple
  /// platforms, so nothing load-bearing may live here.
  @$pb.TagNumber(18)
  $pb.PbMap<$core.String, $core.String> get platformExtras => $_getMap(17);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
