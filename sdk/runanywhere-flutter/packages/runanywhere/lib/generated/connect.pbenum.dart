// This is a generated file - do not edit.
//
// Generated from connect.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// Platform identity is explicit so commons can evaluate role availability
/// from one policy table. Platform SDKs must not hardcode the host/client
/// matrix in UI or transport code.
class ConnectPlatform extends $pb.ProtobufEnum {
  static const ConnectPlatform CONNECT_PLATFORM_UNSPECIFIED = ConnectPlatform._(
      0, _omitEnumNames ? '' : 'CONNECT_PLATFORM_UNSPECIFIED');
  static const ConnectPlatform CONNECT_PLATFORM_MACOS =
      ConnectPlatform._(1, _omitEnumNames ? '' : 'CONNECT_PLATFORM_MACOS');
  static const ConnectPlatform CONNECT_PLATFORM_IOS =
      ConnectPlatform._(2, _omitEnumNames ? '' : 'CONNECT_PLATFORM_IOS');
  static const ConnectPlatform CONNECT_PLATFORM_IPADOS =
      ConnectPlatform._(3, _omitEnumNames ? '' : 'CONNECT_PLATFORM_IPADOS');

  /// Reserved for the follow-on SDK integrations. Keeping the values in the
  /// canonical IDL avoids a later wire-format migration.
  static const ConnectPlatform CONNECT_PLATFORM_ANDROID =
      ConnectPlatform._(4, _omitEnumNames ? '' : 'CONNECT_PLATFORM_ANDROID');
  static const ConnectPlatform CONNECT_PLATFORM_REACT_NATIVE =
      ConnectPlatform._(
          5, _omitEnumNames ? '' : 'CONNECT_PLATFORM_REACT_NATIVE');
  static const ConnectPlatform CONNECT_PLATFORM_FLUTTER =
      ConnectPlatform._(6, _omitEnumNames ? '' : 'CONNECT_PLATFORM_FLUTTER');
  static const ConnectPlatform CONNECT_PLATFORM_WEB =
      ConnectPlatform._(7, _omitEnumNames ? '' : 'CONNECT_PLATFORM_WEB');

  /// Reserved now so adding the planned Windows host adapter does not require
  /// a platform-identity wire migration. Its host role remains PLANNED until
  /// the native transport, discovery, and protected-storage adapter ships.
  static const ConnectPlatform CONNECT_PLATFORM_WINDOWS =
      ConnectPlatform._(8, _omitEnumNames ? '' : 'CONNECT_PLATFORM_WINDOWS');

  static const $core.List<ConnectPlatform> values = <ConnectPlatform>[
    CONNECT_PLATFORM_UNSPECIFIED,
    CONNECT_PLATFORM_MACOS,
    CONNECT_PLATFORM_IOS,
    CONNECT_PLATFORM_IPADOS,
    CONNECT_PLATFORM_ANDROID,
    CONNECT_PLATFORM_REACT_NATIVE,
    CONNECT_PLATFORM_FLUTTER,
    CONNECT_PLATFORM_WEB,
    CONNECT_PLATFORM_WINDOWS,
  ];

  static final $core.List<ConnectPlatform?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 8);
  static ConnectPlatform? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ConnectPlatform._(super.value, super.name);
}

/// Role availability is richer than a boolean so the wire contract can reserve
/// planned platforms without accidentally advertising them as usable.
class ConnectRoleAvailability extends $pb.ProtobufEnum {
  static const ConnectRoleAvailability CONNECT_ROLE_AVAILABILITY_UNSPECIFIED =
      ConnectRoleAvailability._(
          0, _omitEnumNames ? '' : 'CONNECT_ROLE_AVAILABILITY_UNSPECIFIED');
  static const ConnectRoleAvailability CONNECT_ROLE_AVAILABILITY_DISABLED =
      ConnectRoleAvailability._(
          1, _omitEnumNames ? '' : 'CONNECT_ROLE_AVAILABILITY_DISABLED');
  static const ConnectRoleAvailability CONNECT_ROLE_AVAILABILITY_PLANNED =
      ConnectRoleAvailability._(
          2, _omitEnumNames ? '' : 'CONNECT_ROLE_AVAILABILITY_PLANNED');
  static const ConnectRoleAvailability CONNECT_ROLE_AVAILABILITY_ENABLED =
      ConnectRoleAvailability._(
          3, _omitEnumNames ? '' : 'CONNECT_ROLE_AVAILABILITY_ENABLED');

  static const $core.List<ConnectRoleAvailability> values =
      <ConnectRoleAvailability>[
    CONNECT_ROLE_AVAILABILITY_UNSPECIFIED,
    CONNECT_ROLE_AVAILABILITY_DISABLED,
    CONNECT_ROLE_AVAILABILITY_PLANNED,
    CONNECT_ROLE_AVAILABILITY_ENABLED,
  ];

  static final $core.List<ConnectRoleAvailability?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static ConnectRoleAvailability? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ConnectRoleAvailability._(super.value, super.name);
}

class ConnectHandshakeStatus extends $pb.ProtobufEnum {
  static const ConnectHandshakeStatus CONNECT_HANDSHAKE_STATUS_UNSPECIFIED =
      ConnectHandshakeStatus._(
          0, _omitEnumNames ? '' : 'CONNECT_HANDSHAKE_STATUS_UNSPECIFIED');
  static const ConnectHandshakeStatus CONNECT_HANDSHAKE_STATUS_ACCEPTED =
      ConnectHandshakeStatus._(
          1, _omitEnumNames ? '' : 'CONNECT_HANDSHAKE_STATUS_ACCEPTED');
  static const ConnectHandshakeStatus CONNECT_HANDSHAKE_STATUS_REJECTED =
      ConnectHandshakeStatus._(
          2, _omitEnumNames ? '' : 'CONNECT_HANDSHAKE_STATUS_REJECTED');

  static const $core.List<ConnectHandshakeStatus> values =
      <ConnectHandshakeStatus>[
    CONNECT_HANDSHAKE_STATUS_UNSPECIFIED,
    CONNECT_HANDSHAKE_STATUS_ACCEPTED,
    CONNECT_HANDSHAKE_STATUS_REJECTED,
  ];

  static final $core.List<ConnectHandshakeStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static ConnectHandshakeStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ConnectHandshakeStatus._(super.value, super.name);
}

class ConnectSessionState extends $pb.ProtobufEnum {
  static const ConnectSessionState CONNECT_SESSION_STATE_UNSPECIFIED =
      ConnectSessionState._(
          0, _omitEnumNames ? '' : 'CONNECT_SESSION_STATE_UNSPECIFIED');
  static const ConnectSessionState CONNECT_SESSION_STATE_CONNECTING =
      ConnectSessionState._(
          1, _omitEnumNames ? '' : 'CONNECT_SESSION_STATE_CONNECTING');
  static const ConnectSessionState CONNECT_SESSION_STATE_CONNECTED =
      ConnectSessionState._(
          2, _omitEnumNames ? '' : 'CONNECT_SESSION_STATE_CONNECTED');
  static const ConnectSessionState CONNECT_SESSION_STATE_DISCONNECTED =
      ConnectSessionState._(
          3, _omitEnumNames ? '' : 'CONNECT_SESSION_STATE_DISCONNECTED');
  static const ConnectSessionState CONNECT_SESSION_STATE_FAILED =
      ConnectSessionState._(
          4, _omitEnumNames ? '' : 'CONNECT_SESSION_STATE_FAILED');

  static const $core.List<ConnectSessionState> values = <ConnectSessionState>[
    CONNECT_SESSION_STATE_UNSPECIFIED,
    CONNECT_SESSION_STATE_CONNECTING,
    CONNECT_SESSION_STATE_CONNECTED,
    CONNECT_SESSION_STATE_DISCONNECTED,
    CONNECT_SESSION_STATE_FAILED,
  ];

  static final $core.List<ConnectSessionState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static ConnectSessionState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ConnectSessionState._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
