// This is a generated file - do not edit.
//
// Generated from hardware_profile.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'hardware_profile.pbenum.dart';
import 'storage_types.pbenum.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'hardware_profile.pbenum.dart';

/// The single NPU-capability description in this IDL. Static device
/// description lives in exactly one other place: device_info.proto's
/// DeviceInfo.
class NpuCapability extends $pb.GeneratedMessage {
  factory NpuCapability({
    $core.String? socModel,
    $core.int? socId,
    HexagonArch? hexagonArch,
    $core.bool? supported,
    $0.NPUChip? npu,
  }) {
    final result = create();
    if (socModel != null) result.socModel = socModel;
    if (socId != null) result.socId = socId;
    if (hexagonArch != null) result.hexagonArch = hexagonArch;
    if (supported != null) result.supported = supported;
    if (npu != null) result.npu = npu;
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
    ..aOB(4, _omitFieldNames ? '' : 'supported')
    ..aE<$0.NPUChip>(5, _omitFieldNames ? '' : 'npu',
        enumValues: $0.NPUChip.values)
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

  /// /sys/devices/soc0/soc_id value. ABSENT when unavailable — never a -1 or 0
  /// sentinel; a default-constructed message is already "unavailable".
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

  /// True iff this accelerator generation is in the device-validated supported
  /// set (Hexagon v75/v79/v81 today). Engine-agnostic on purpose: a second NPU
  /// engine must not require a second boolean.
  @$pb.TagNumber(4)
  $core.bool get supported => $_getBF(3);
  @$pb.TagNumber(4)
  set supported($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSupported() => $_has(3);
  @$pb.TagNumber(4)
  void clearSupported() => $_clearField(4);

  /// NPU vendor family. Re-homed here so a non-Qualcomm device gets a
  /// meaningful answer instead of an empty message.
  @$pb.TagNumber(5)
  $0.NPUChip get npu => $_getN(4);
  @$pb.TagNumber(5)
  set npu($0.NPUChip value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasNpu() => $_has(4);
  @$pb.TagNumber(5)
  void clearNpu() => $_clearField(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
