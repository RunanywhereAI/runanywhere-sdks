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

import 'package:protobuf/protobuf.dart' as $pb;

/// Host OS family. Closed set — a producer that cannot classify itself sends
/// PLATFORM_UNSPECIFIED rather than inventing a spelling.
class Platform extends $pb.ProtobufEnum {
  static const Platform PLATFORM_UNSPECIFIED =
      Platform._(0, _omitEnumNames ? '' : 'PLATFORM_UNSPECIFIED');
  static const Platform PLATFORM_IOS =
      Platform._(1, _omitEnumNames ? '' : 'PLATFORM_IOS');
  static const Platform PLATFORM_ANDROID =
      Platform._(2, _omitEnumNames ? '' : 'PLATFORM_ANDROID');
  static const Platform PLATFORM_MACOS =
      Platform._(3, _omitEnumNames ? '' : 'PLATFORM_MACOS');
  static const Platform PLATFORM_WEB =
      Platform._(4, _omitEnumNames ? '' : 'PLATFORM_WEB');
  static const Platform PLATFORM_LINUX =
      Platform._(5, _omitEnumNames ? '' : 'PLATFORM_LINUX');
  static const Platform PLATFORM_WINDOWS =
      Platform._(6, _omitEnumNames ? '' : 'PLATFORM_WINDOWS');
  static const Platform PLATFORM_TVOS =
      Platform._(7, _omitEnumNames ? '' : 'PLATFORM_TVOS');
  static const Platform PLATFORM_WATCHOS =
      Platform._(8, _omitEnumNames ? '' : 'PLATFORM_WATCHOS');
  static const Platform PLATFORM_VISIONOS =
      Platform._(9, _omitEnumNames ? '' : 'PLATFORM_VISIONOS');

  static const $core.List<Platform> values = <Platform>[
    PLATFORM_UNSPECIFIED,
    PLATFORM_IOS,
    PLATFORM_ANDROID,
    PLATFORM_MACOS,
    PLATFORM_WEB,
    PLATFORM_LINUX,
    PLATFORM_WINDOWS,
    PLATFORM_TVOS,
    PLATFORM_WATCHOS,
    PLATFORM_VISIONOS,
  ];

  static final $core.List<Platform?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 9);
  static Platform? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Platform._(super.value, super.name);
}

/// Physical device class.
class FormFactor extends $pb.ProtobufEnum {
  static const FormFactor FORM_FACTOR_UNSPECIFIED =
      FormFactor._(0, _omitEnumNames ? '' : 'FORM_FACTOR_UNSPECIFIED');
  static const FormFactor FORM_FACTOR_PHONE =
      FormFactor._(1, _omitEnumNames ? '' : 'FORM_FACTOR_PHONE');
  static const FormFactor FORM_FACTOR_TABLET =
      FormFactor._(2, _omitEnumNames ? '' : 'FORM_FACTOR_TABLET');
  static const FormFactor FORM_FACTOR_DESKTOP =
      FormFactor._(3, _omitEnumNames ? '' : 'FORM_FACTOR_DESKTOP');
  static const FormFactor FORM_FACTOR_LAPTOP =
      FormFactor._(4, _omitEnumNames ? '' : 'FORM_FACTOR_LAPTOP');
  static const FormFactor FORM_FACTOR_TV =
      FormFactor._(5, _omitEnumNames ? '' : 'FORM_FACTOR_TV');
  static const FormFactor FORM_FACTOR_WATCH =
      FormFactor._(6, _omitEnumNames ? '' : 'FORM_FACTOR_WATCH');
  static const FormFactor FORM_FACTOR_HEADSET =
      FormFactor._(7, _omitEnumNames ? '' : 'FORM_FACTOR_HEADSET');

  static const $core.List<FormFactor> values = <FormFactor>[
    FORM_FACTOR_UNSPECIFIED,
    FORM_FACTOR_PHONE,
    FORM_FACTOR_TABLET,
    FORM_FACTOR_DESKTOP,
    FORM_FACTOR_LAPTOP,
    FORM_FACTOR_TV,
    FORM_FACTOR_WATCH,
    FORM_FACTOR_HEADSET,
  ];

  static final $core.List<FormFactor?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 7);
  static FormFactor? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const FormFactor._(super.value, super.name);
}

/// Charging state of the main battery.
class BatteryState extends $pb.ProtobufEnum {
  static const BatteryState BATTERY_STATE_UNSPECIFIED =
      BatteryState._(0, _omitEnumNames ? '' : 'BATTERY_STATE_UNSPECIFIED');
  static const BatteryState BATTERY_STATE_CHARGING =
      BatteryState._(1, _omitEnumNames ? '' : 'BATTERY_STATE_CHARGING');
  static const BatteryState BATTERY_STATE_UNPLUGGED =
      BatteryState._(2, _omitEnumNames ? '' : 'BATTERY_STATE_UNPLUGGED');
  static const BatteryState BATTERY_STATE_FULL =
      BatteryState._(3, _omitEnumNames ? '' : 'BATTERY_STATE_FULL');

  static const $core.List<BatteryState> values = <BatteryState>[
    BATTERY_STATE_UNSPECIFIED,
    BATTERY_STATE_CHARGING,
    BATTERY_STATE_UNPLUGGED,
    BATTERY_STATE_FULL,
  ];

  static final $core.List<BatteryState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static BatteryState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const BatteryState._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
