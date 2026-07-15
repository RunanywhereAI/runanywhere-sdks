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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'connect.pbenum.dart';
import 'llm_service.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'connect.pbenum.dart';

class ConnectPlatformPolicyRequest extends $pb.GeneratedMessage {
  factory ConnectPlatformPolicyRequest({
    ConnectPlatform? platform,
  }) {
    final result = create();
    if (platform != null) result.platform = platform;
    return result;
  }

  ConnectPlatformPolicyRequest._();

  factory ConnectPlatformPolicyRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConnectPlatformPolicyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectPlatformPolicyRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<ConnectPlatform>(1, _omitFieldNames ? '' : 'platform',
        enumValues: ConnectPlatform.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectPlatformPolicyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectPlatformPolicyRequest copyWith(
          void Function(ConnectPlatformPolicyRequest) updates) =>
      super.copyWith(
              (message) => updates(message as ConnectPlatformPolicyRequest))
          as ConnectPlatformPolicyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConnectPlatformPolicyRequest create() =>
      ConnectPlatformPolicyRequest._();
  @$core.override
  ConnectPlatformPolicyRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConnectPlatformPolicyRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectPlatformPolicyRequest>(create);
  static ConnectPlatformPolicyRequest? _defaultInstance;

  @$pb.TagNumber(1)
  ConnectPlatform get platform => $_getN(0);
  @$pb.TagNumber(1)
  set platform(ConnectPlatform value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPlatform() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlatform() => $_clearField(1);
}

/// Commons is the authority for this policy. SDKs may query it to shape UI,
/// but every host/client entrypoint also enforces it inside C++.
class ConnectPlatformPolicy extends $pb.GeneratedMessage {
  factory ConnectPlatformPolicy({
    ConnectPlatform? platform,
    ConnectRoleAvailability? hostRole,
    ConnectRoleAvailability? clientRole,
  }) {
    final result = create();
    if (platform != null) result.platform = platform;
    if (hostRole != null) result.hostRole = hostRole;
    if (clientRole != null) result.clientRole = clientRole;
    return result;
  }

  ConnectPlatformPolicy._();

  factory ConnectPlatformPolicy.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConnectPlatformPolicy.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectPlatformPolicy',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<ConnectPlatform>(1, _omitFieldNames ? '' : 'platform',
        enumValues: ConnectPlatform.values)
    ..aE<ConnectRoleAvailability>(2, _omitFieldNames ? '' : 'hostRole',
        enumValues: ConnectRoleAvailability.values)
    ..aE<ConnectRoleAvailability>(3, _omitFieldNames ? '' : 'clientRole',
        enumValues: ConnectRoleAvailability.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectPlatformPolicy clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectPlatformPolicy copyWith(
          void Function(ConnectPlatformPolicy) updates) =>
      super.copyWith((message) => updates(message as ConnectPlatformPolicy))
          as ConnectPlatformPolicy;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConnectPlatformPolicy create() => ConnectPlatformPolicy._();
  @$core.override
  ConnectPlatformPolicy createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConnectPlatformPolicy getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectPlatformPolicy>(create);
  static ConnectPlatformPolicy? _defaultInstance;

  @$pb.TagNumber(1)
  ConnectPlatform get platform => $_getN(0);
  @$pb.TagNumber(1)
  set platform(ConnectPlatform value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPlatform() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlatform() => $_clearField(1);

  @$pb.TagNumber(2)
  ConnectRoleAvailability get hostRole => $_getN(1);
  @$pb.TagNumber(2)
  set hostRole(ConnectRoleAvailability value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasHostRole() => $_has(1);
  @$pb.TagNumber(2)
  void clearHostRole() => $_clearField(2);

  @$pb.TagNumber(3)
  ConnectRoleAvailability get clientRole => $_getN(2);
  @$pb.TagNumber(3)
  set clientRole(ConnectRoleAvailability value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasClientRole() => $_has(2);
  @$pb.TagNumber(3)
  void clearClientRole() => $_clearField(3);
}

/// Non-secret metadata published through LAN service discovery and echoed by
/// the handshake. `instance_id` is generated anew whenever the host starts;
/// it is not a persistent device identifier or a credential.
class ConnectDiscoveryMetadata extends $pb.GeneratedMessage {
  factory ConnectDiscoveryMetadata({
    $core.String? instanceId,
    $core.String? displayName,
    ConnectPlatform? platform,
    $core.int? protocolVersion,
  }) {
    final result = create();
    if (instanceId != null) result.instanceId = instanceId;
    if (displayName != null) result.displayName = displayName;
    if (platform != null) result.platform = platform;
    if (protocolVersion != null) result.protocolVersion = protocolVersion;
    return result;
  }

  ConnectDiscoveryMetadata._();

  factory ConnectDiscoveryMetadata.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConnectDiscoveryMetadata.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectDiscoveryMetadata',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'instanceId')
    ..aOS(2, _omitFieldNames ? '' : 'displayName')
    ..aE<ConnectPlatform>(3, _omitFieldNames ? '' : 'platform',
        enumValues: ConnectPlatform.values)
    ..aI(4, _omitFieldNames ? '' : 'protocolVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectDiscoveryMetadata clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectDiscoveryMetadata copyWith(
          void Function(ConnectDiscoveryMetadata) updates) =>
      super.copyWith((message) => updates(message as ConnectDiscoveryMetadata))
          as ConnectDiscoveryMetadata;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConnectDiscoveryMetadata create() => ConnectDiscoveryMetadata._();
  @$core.override
  ConnectDiscoveryMetadata createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConnectDiscoveryMetadata getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectDiscoveryMetadata>(create);
  static ConnectDiscoveryMetadata? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get displayName => $_getSZ(1);
  @$pb.TagNumber(2)
  set displayName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDisplayName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDisplayName() => $_clearField(2);

  @$pb.TagNumber(3)
  ConnectPlatform get platform => $_getN(2);
  @$pb.TagNumber(3)
  set platform(ConnectPlatform value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasPlatform() => $_has(2);
  @$pb.TagNumber(3)
  void clearPlatform() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get protocolVersion => $_getIZ(3);
  @$pb.TagNumber(4)
  set protocolVersion($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasProtocolVersion() => $_has(3);
  @$pb.TagNumber(4)
  void clearProtocolVersion() => $_clearField(4);
}

/// The single language model currently shared by a host. A host must select a
/// loaded model before it starts publishing; this lets clients enter chat
/// immediately without downloading or selecting a local model.
class ConnectModelDescriptor extends $pb.GeneratedMessage {
  factory ConnectModelDescriptor({
    $core.String? modelId,
    $core.String? displayName,
    $core.String? framework,
    $core.int? contextWindow,
    $core.bool? supportsStreaming,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (displayName != null) result.displayName = displayName;
    if (framework != null) result.framework = framework;
    if (contextWindow != null) result.contextWindow = contextWindow;
    if (supportsStreaming != null) result.supportsStreaming = supportsStreaming;
    return result;
  }

  ConnectModelDescriptor._();

  factory ConnectModelDescriptor.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConnectModelDescriptor.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectModelDescriptor',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aOS(2, _omitFieldNames ? '' : 'displayName')
    ..aOS(3, _omitFieldNames ? '' : 'framework')
    ..aI(4, _omitFieldNames ? '' : 'contextWindow',
        fieldType: $pb.PbFieldType.OU3)
    ..aOB(5, _omitFieldNames ? '' : 'supportsStreaming')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectModelDescriptor clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectModelDescriptor copyWith(
          void Function(ConnectModelDescriptor) updates) =>
      super.copyWith((message) => updates(message as ConnectModelDescriptor))
          as ConnectModelDescriptor;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConnectModelDescriptor create() => ConnectModelDescriptor._();
  @$core.override
  ConnectModelDescriptor createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConnectModelDescriptor getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectModelDescriptor>(create);
  static ConnectModelDescriptor? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get displayName => $_getSZ(1);
  @$pb.TagNumber(2)
  set displayName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDisplayName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDisplayName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get framework => $_getSZ(2);
  @$pb.TagNumber(3)
  set framework($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFramework() => $_has(2);
  @$pb.TagNumber(3)
  void clearFramework() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get contextWindow => $_getIZ(3);
  @$pb.TagNumber(4)
  set contextWindow($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasContextWindow() => $_has(3);
  @$pb.TagNumber(4)
  void clearContextWindow() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get supportsStreaming => $_getBF(4);
  @$pb.TagNumber(5)
  set supportsStreaming($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSupportsStreaming() => $_has(4);
  @$pb.TagNumber(5)
  void clearSupportsStreaming() => $_clearField(5);
}

class ConnectHostStartRequest extends $pb.GeneratedMessage {
  factory ConnectHostStartRequest({
    $core.String? displayName,
    ConnectPlatform? platform,
    $core.int? protocolVersion,
    ConnectModelDescriptor? model,
  }) {
    final result = create();
    if (displayName != null) result.displayName = displayName;
    if (platform != null) result.platform = platform;
    if (protocolVersion != null) result.protocolVersion = protocolVersion;
    if (model != null) result.model = model;
    return result;
  }

  ConnectHostStartRequest._();

  factory ConnectHostStartRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConnectHostStartRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectHostStartRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'displayName')
    ..aE<ConnectPlatform>(2, _omitFieldNames ? '' : 'platform',
        enumValues: ConnectPlatform.values)
    ..aI(3, _omitFieldNames ? '' : 'protocolVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<ConnectModelDescriptor>(4, _omitFieldNames ? '' : 'model',
        subBuilder: ConnectModelDescriptor.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectHostStartRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectHostStartRequest copyWith(
          void Function(ConnectHostStartRequest) updates) =>
      super.copyWith((message) => updates(message as ConnectHostStartRequest))
          as ConnectHostStartRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConnectHostStartRequest create() => ConnectHostStartRequest._();
  @$core.override
  ConnectHostStartRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConnectHostStartRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectHostStartRequest>(create);
  static ConnectHostStartRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get displayName => $_getSZ(0);
  @$pb.TagNumber(1)
  set displayName($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDisplayName() => $_has(0);
  @$pb.TagNumber(1)
  void clearDisplayName() => $_clearField(1);

  @$pb.TagNumber(2)
  ConnectPlatform get platform => $_getN(1);
  @$pb.TagNumber(2)
  set platform(ConnectPlatform value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPlatform() => $_has(1);
  @$pb.TagNumber(2)
  void clearPlatform() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get protocolVersion => $_getIZ(2);
  @$pb.TagNumber(3)
  set protocolVersion($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasProtocolVersion() => $_has(2);
  @$pb.TagNumber(3)
  void clearProtocolVersion() => $_clearField(3);

  @$pb.TagNumber(4)
  ConnectModelDescriptor get model => $_getN(3);
  @$pb.TagNumber(4)
  set model(ConnectModelDescriptor value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasModel() => $_has(3);
  @$pb.TagNumber(4)
  void clearModel() => $_clearField(4);
  @$pb.TagNumber(4)
  ConnectModelDescriptor ensureModel() => $_ensure(3);
}

class ConnectHostStopRequest extends $pb.GeneratedMessage {
  factory ConnectHostStopRequest() => create();

  ConnectHostStopRequest._();

  factory ConnectHostStopRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConnectHostStopRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectHostStopRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectHostStopRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectHostStopRequest copyWith(
          void Function(ConnectHostStopRequest) updates) =>
      super.copyWith((message) => updates(message as ConnectHostStopRequest))
          as ConnectHostStopRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConnectHostStopRequest create() => ConnectHostStopRequest._();
  @$core.override
  ConnectHostStopRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConnectHostStopRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectHostStopRequest>(create);
  static ConnectHostStopRequest? _defaultInstance;
}

class ConnectHostState extends $pb.GeneratedMessage {
  factory ConnectHostState({
    $core.bool? isHosting,
    ConnectDiscoveryMetadata? discoveryMetadata,
    $core.int? activeClientCount,
    $core.String? errorMessage,
    ConnectModelDescriptor? model,
  }) {
    final result = create();
    if (isHosting != null) result.isHosting = isHosting;
    if (discoveryMetadata != null) result.discoveryMetadata = discoveryMetadata;
    if (activeClientCount != null) result.activeClientCount = activeClientCount;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (model != null) result.model = model;
    return result;
  }

  ConnectHostState._();

  factory ConnectHostState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConnectHostState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectHostState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isHosting')
    ..aOM<ConnectDiscoveryMetadata>(
        2, _omitFieldNames ? '' : 'discoveryMetadata',
        subBuilder: ConnectDiscoveryMetadata.create)
    ..aI(3, _omitFieldNames ? '' : 'activeClientCount',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(4, _omitFieldNames ? '' : 'errorMessage')
    ..aOM<ConnectModelDescriptor>(5, _omitFieldNames ? '' : 'model',
        subBuilder: ConnectModelDescriptor.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectHostState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectHostState copyWith(void Function(ConnectHostState) updates) =>
      super.copyWith((message) => updates(message as ConnectHostState))
          as ConnectHostState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConnectHostState create() => ConnectHostState._();
  @$core.override
  ConnectHostState createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConnectHostState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectHostState>(create);
  static ConnectHostState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get isHosting => $_getBF(0);
  @$pb.TagNumber(1)
  set isHosting($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIsHosting() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsHosting() => $_clearField(1);

  @$pb.TagNumber(2)
  ConnectDiscoveryMetadata get discoveryMetadata => $_getN(1);
  @$pb.TagNumber(2)
  set discoveryMetadata(ConnectDiscoveryMetadata value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasDiscoveryMetadata() => $_has(1);
  @$pb.TagNumber(2)
  void clearDiscoveryMetadata() => $_clearField(2);
  @$pb.TagNumber(2)
  ConnectDiscoveryMetadata ensureDiscoveryMetadata() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.int get activeClientCount => $_getIZ(2);
  @$pb.TagNumber(3)
  set activeClientCount($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasActiveClientCount() => $_has(2);
  @$pb.TagNumber(3)
  void clearActiveClientCount() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get errorMessage => $_getSZ(3);
  @$pb.TagNumber(4)
  set errorMessage($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasErrorMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearErrorMessage() => $_clearField(4);

  @$pb.TagNumber(5)
  ConnectModelDescriptor get model => $_getN(4);
  @$pb.TagNumber(5)
  set model(ConnectModelDescriptor value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasModel() => $_has(4);
  @$pb.TagNumber(5)
  void clearModel() => $_clearField(5);
  @$pb.TagNumber(5)
  ConnectModelDescriptor ensureModel() => $_ensure(4);
}

class ConnectClientStartRequest extends $pb.GeneratedMessage {
  factory ConnectClientStartRequest({
    $core.String? displayName,
    ConnectPlatform? platform,
    $core.int? protocolVersion,
  }) {
    final result = create();
    if (displayName != null) result.displayName = displayName;
    if (platform != null) result.platform = platform;
    if (protocolVersion != null) result.protocolVersion = protocolVersion;
    return result;
  }

  ConnectClientStartRequest._();

  factory ConnectClientStartRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConnectClientStartRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectClientStartRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'displayName')
    ..aE<ConnectPlatform>(2, _omitFieldNames ? '' : 'platform',
        enumValues: ConnectPlatform.values)
    ..aI(3, _omitFieldNames ? '' : 'protocolVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectClientStartRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectClientStartRequest copyWith(
          void Function(ConnectClientStartRequest) updates) =>
      super.copyWith((message) => updates(message as ConnectClientStartRequest))
          as ConnectClientStartRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConnectClientStartRequest create() => ConnectClientStartRequest._();
  @$core.override
  ConnectClientStartRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConnectClientStartRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectClientStartRequest>(create);
  static ConnectClientStartRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get displayName => $_getSZ(0);
  @$pb.TagNumber(1)
  set displayName($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDisplayName() => $_has(0);
  @$pb.TagNumber(1)
  void clearDisplayName() => $_clearField(1);

  @$pb.TagNumber(2)
  ConnectPlatform get platform => $_getN(1);
  @$pb.TagNumber(2)
  set platform(ConnectPlatform value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPlatform() => $_has(1);
  @$pb.TagNumber(2)
  void clearPlatform() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get protocolVersion => $_getIZ(2);
  @$pb.TagNumber(3)
  set protocolVersion($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasProtocolVersion() => $_has(2);
  @$pb.TagNumber(3)
  void clearProtocolVersion() => $_clearField(3);
}

/// Sent by a client immediately after the platform transport is connected.
class ConnectClientHello extends $pb.GeneratedMessage {
  factory ConnectClientHello({
    $core.String? instanceId,
    $core.String? displayName,
    ConnectPlatform? platform,
    $core.int? protocolVersion,
  }) {
    final result = create();
    if (instanceId != null) result.instanceId = instanceId;
    if (displayName != null) result.displayName = displayName;
    if (platform != null) result.platform = platform;
    if (protocolVersion != null) result.protocolVersion = protocolVersion;
    return result;
  }

  ConnectClientHello._();

  factory ConnectClientHello.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConnectClientHello.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectClientHello',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'instanceId')
    ..aOS(2, _omitFieldNames ? '' : 'displayName')
    ..aE<ConnectPlatform>(3, _omitFieldNames ? '' : 'platform',
        enumValues: ConnectPlatform.values)
    ..aI(4, _omitFieldNames ? '' : 'protocolVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectClientHello clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectClientHello copyWith(void Function(ConnectClientHello) updates) =>
      super.copyWith((message) => updates(message as ConnectClientHello))
          as ConnectClientHello;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConnectClientHello create() => ConnectClientHello._();
  @$core.override
  ConnectClientHello createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConnectClientHello getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectClientHello>(create);
  static ConnectClientHello? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get displayName => $_getSZ(1);
  @$pb.TagNumber(2)
  set displayName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDisplayName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDisplayName() => $_clearField(2);

  @$pb.TagNumber(3)
  ConnectPlatform get platform => $_getN(2);
  @$pb.TagNumber(3)
  set platform(ConnectPlatform value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasPlatform() => $_has(2);
  @$pb.TagNumber(3)
  void clearPlatform() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get protocolVersion => $_getIZ(3);
  @$pb.TagNumber(4)
  set protocolVersion($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasProtocolVersion() => $_has(3);
  @$pb.TagNumber(4)
  void clearProtocolVersion() => $_clearField(4);
}

/// Sent by the host after commons has accepted or rejected a client hello.
class ConnectHandshakeResponse extends $pb.GeneratedMessage {
  factory ConnectHandshakeResponse({
    ConnectHandshakeStatus? status,
    $core.String? sessionId,
    ConnectDiscoveryMetadata? host,
    $core.String? rejectionReason,
    ConnectModelDescriptor? model,
  }) {
    final result = create();
    if (status != null) result.status = status;
    if (sessionId != null) result.sessionId = sessionId;
    if (host != null) result.host = host;
    if (rejectionReason != null) result.rejectionReason = rejectionReason;
    if (model != null) result.model = model;
    return result;
  }

  ConnectHandshakeResponse._();

  factory ConnectHandshakeResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConnectHandshakeResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectHandshakeResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<ConnectHandshakeStatus>(1, _omitFieldNames ? '' : 'status',
        enumValues: ConnectHandshakeStatus.values)
    ..aOS(2, _omitFieldNames ? '' : 'sessionId')
    ..aOM<ConnectDiscoveryMetadata>(3, _omitFieldNames ? '' : 'host',
        subBuilder: ConnectDiscoveryMetadata.create)
    ..aOS(4, _omitFieldNames ? '' : 'rejectionReason')
    ..aOM<ConnectModelDescriptor>(5, _omitFieldNames ? '' : 'model',
        subBuilder: ConnectModelDescriptor.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectHandshakeResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectHandshakeResponse copyWith(
          void Function(ConnectHandshakeResponse) updates) =>
      super.copyWith((message) => updates(message as ConnectHandshakeResponse))
          as ConnectHandshakeResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConnectHandshakeResponse create() => ConnectHandshakeResponse._();
  @$core.override
  ConnectHandshakeResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConnectHandshakeResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectHandshakeResponse>(create);
  static ConnectHandshakeResponse? _defaultInstance;

  @$pb.TagNumber(1)
  ConnectHandshakeStatus get status => $_getN(0);
  @$pb.TagNumber(1)
  set status(ConnectHandshakeStatus value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasStatus() => $_has(0);
  @$pb.TagNumber(1)
  void clearStatus() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get sessionId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sessionId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSessionId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSessionId() => $_clearField(2);

  @$pb.TagNumber(3)
  ConnectDiscoveryMetadata get host => $_getN(2);
  @$pb.TagNumber(3)
  set host(ConnectDiscoveryMetadata value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasHost() => $_has(2);
  @$pb.TagNumber(3)
  void clearHost() => $_clearField(3);
  @$pb.TagNumber(3)
  ConnectDiscoveryMetadata ensureHost() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.String get rejectionReason => $_getSZ(3);
  @$pb.TagNumber(4)
  set rejectionReason($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRejectionReason() => $_has(3);
  @$pb.TagNumber(4)
  void clearRejectionReason() => $_clearField(4);

  @$pb.TagNumber(5)
  ConnectModelDescriptor get model => $_getN(4);
  @$pb.TagNumber(5)
  set model(ConnectModelDescriptor value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasModel() => $_has(4);
  @$pb.TagNumber(5)
  void clearModel() => $_clearField(5);
  @$pb.TagNumber(5)
  ConnectModelDescriptor ensureModel() => $_ensure(4);
}

/// The client validates the host response through commons and receives the
/// public session state it can expose to its platform UI.
class ConnectClientSessionState extends $pb.GeneratedMessage {
  factory ConnectClientSessionState({
    ConnectSessionState? state,
    $core.String? sessionId,
    ConnectDiscoveryMetadata? host,
    $core.String? errorMessage,
    ConnectModelDescriptor? model,
  }) {
    final result = create();
    if (state != null) result.state = state;
    if (sessionId != null) result.sessionId = sessionId;
    if (host != null) result.host = host;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (model != null) result.model = model;
    return result;
  }

  ConnectClientSessionState._();

  factory ConnectClientSessionState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConnectClientSessionState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectClientSessionState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<ConnectSessionState>(1, _omitFieldNames ? '' : 'state',
        enumValues: ConnectSessionState.values)
    ..aOS(2, _omitFieldNames ? '' : 'sessionId')
    ..aOM<ConnectDiscoveryMetadata>(3, _omitFieldNames ? '' : 'host',
        subBuilder: ConnectDiscoveryMetadata.create)
    ..aOS(4, _omitFieldNames ? '' : 'errorMessage')
    ..aOM<ConnectModelDescriptor>(5, _omitFieldNames ? '' : 'model',
        subBuilder: ConnectModelDescriptor.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectClientSessionState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectClientSessionState copyWith(
          void Function(ConnectClientSessionState) updates) =>
      super.copyWith((message) => updates(message as ConnectClientSessionState))
          as ConnectClientSessionState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConnectClientSessionState create() => ConnectClientSessionState._();
  @$core.override
  ConnectClientSessionState createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConnectClientSessionState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectClientSessionState>(create);
  static ConnectClientSessionState? _defaultInstance;

  @$pb.TagNumber(1)
  ConnectSessionState get state => $_getN(0);
  @$pb.TagNumber(1)
  set state(ConnectSessionState value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasState() => $_has(0);
  @$pb.TagNumber(1)
  void clearState() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get sessionId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sessionId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSessionId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSessionId() => $_clearField(2);

  @$pb.TagNumber(3)
  ConnectDiscoveryMetadata get host => $_getN(2);
  @$pb.TagNumber(3)
  set host(ConnectDiscoveryMetadata value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasHost() => $_has(2);
  @$pb.TagNumber(3)
  void clearHost() => $_clearField(3);
  @$pb.TagNumber(3)
  ConnectDiscoveryMetadata ensureHost() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.String get errorMessage => $_getSZ(3);
  @$pb.TagNumber(4)
  set errorMessage($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasErrorMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearErrorMessage() => $_clearField(4);

  @$pb.TagNumber(5)
  ConnectModelDescriptor get model => $_getN(4);
  @$pb.TagNumber(5)
  set model(ConnectModelDescriptor value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasModel() => $_has(4);
  @$pb.TagNumber(5)
  void clearModel() => $_clearField(5);
  @$pb.TagNumber(5)
  ConnectModelDescriptor ensureModel() => $_ensure(4);
}

class ConnectSessionCloseRequest extends $pb.GeneratedMessage {
  factory ConnectSessionCloseRequest({
    $core.String? sessionId,
  }) {
    final result = create();
    if (sessionId != null) result.sessionId = sessionId;
    return result;
  }

  ConnectSessionCloseRequest._();

  factory ConnectSessionCloseRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConnectSessionCloseRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectSessionCloseRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'sessionId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectSessionCloseRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectSessionCloseRequest copyWith(
          void Function(ConnectSessionCloseRequest) updates) =>
      super.copyWith(
              (message) => updates(message as ConnectSessionCloseRequest))
          as ConnectSessionCloseRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConnectSessionCloseRequest create() => ConnectSessionCloseRequest._();
  @$core.override
  ConnectSessionCloseRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConnectSessionCloseRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectSessionCloseRequest>(create);
  static ConnectSessionCloseRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sessionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set sessionId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSessionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionId() => $_clearField(1);
}

/// A client sends the existing typed LLM request to the selected host model.
/// `session_id` binds the request to the prior handshake; `generation.model_id`
/// must match the model the host published for that session.
class ConnectInvocationRequest extends $pb.GeneratedMessage {
  factory ConnectInvocationRequest({
    $core.String? sessionId,
    $core.String? requestId,
    $0.LLMGenerateRequest? generation,
  }) {
    final result = create();
    if (sessionId != null) result.sessionId = sessionId;
    if (requestId != null) result.requestId = requestId;
    if (generation != null) result.generation = generation;
    return result;
  }

  ConnectInvocationRequest._();

  factory ConnectInvocationRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConnectInvocationRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectInvocationRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'sessionId')
    ..aOS(2, _omitFieldNames ? '' : 'requestId')
    ..aOM<$0.LLMGenerateRequest>(3, _omitFieldNames ? '' : 'generation',
        subBuilder: $0.LLMGenerateRequest.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectInvocationRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectInvocationRequest copyWith(
          void Function(ConnectInvocationRequest) updates) =>
      super.copyWith((message) => updates(message as ConnectInvocationRequest))
          as ConnectInvocationRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConnectInvocationRequest create() => ConnectInvocationRequest._();
  @$core.override
  ConnectInvocationRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConnectInvocationRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectInvocationRequest>(create);
  static ConnectInvocationRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sessionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set sessionId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSessionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get requestId => $_getSZ(1);
  @$pb.TagNumber(2)
  set requestId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRequestId() => $_has(1);
  @$pb.TagNumber(2)
  void clearRequestId() => $_clearField(2);

  @$pb.TagNumber(3)
  $0.LLMGenerateRequest get generation => $_getN(2);
  @$pb.TagNumber(3)
  set generation($0.LLMGenerateRequest value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasGeneration() => $_has(2);
  @$pb.TagNumber(3)
  void clearGeneration() => $_clearField(3);
  @$pb.TagNumber(3)
  $0.LLMGenerateRequest ensureGeneration() => $_ensure(2);
}

/// Commons validates that an invocation belongs to an active session and uses
/// the host's published model before any platform runtime receives the prompt.
class ConnectInvocationValidation extends $pb.GeneratedMessage {
  factory ConnectInvocationValidation({
    $core.bool? accepted,
    $core.String? rejectionReason,
  }) {
    final result = create();
    if (accepted != null) result.accepted = accepted;
    if (rejectionReason != null) result.rejectionReason = rejectionReason;
    return result;
  }

  ConnectInvocationValidation._();

  factory ConnectInvocationValidation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConnectInvocationValidation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectInvocationValidation',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'accepted')
    ..aOS(2, _omitFieldNames ? '' : 'rejectionReason')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectInvocationValidation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectInvocationValidation copyWith(
          void Function(ConnectInvocationValidation) updates) =>
      super.copyWith(
              (message) => updates(message as ConnectInvocationValidation))
          as ConnectInvocationValidation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConnectInvocationValidation create() =>
      ConnectInvocationValidation._();
  @$core.override
  ConnectInvocationValidation createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConnectInvocationValidation getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectInvocationValidation>(create);
  static ConnectInvocationValidation? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get accepted => $_getBF(0);
  @$pb.TagNumber(1)
  set accepted($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAccepted() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccepted() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get rejectionReason => $_getSZ(1);
  @$pb.TagNumber(2)
  set rejectionReason($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRejectionReason() => $_has(1);
  @$pb.TagNumber(2)
  void clearRejectionReason() => $_clearField(2);
}

/// Hosts forward the SDK's canonical stream events without translating them to
/// a platform-specific token shape. This is the portable streaming surface for
/// future Kotlin, React Native, Flutter, and Web clients.
class ConnectInvocationEvent extends $pb.GeneratedMessage {
  factory ConnectInvocationEvent({
    $core.String? requestId,
    $0.LLMStreamEvent? event,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (event != null) result.event = event;
    return result;
  }

  ConnectInvocationEvent._();

  factory ConnectInvocationEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConnectInvocationEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectInvocationEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOM<$0.LLMStreamEvent>(2, _omitFieldNames ? '' : 'event',
        subBuilder: $0.LLMStreamEvent.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectInvocationEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectInvocationEvent copyWith(
          void Function(ConnectInvocationEvent) updates) =>
      super.copyWith((message) => updates(message as ConnectInvocationEvent))
          as ConnectInvocationEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConnectInvocationEvent create() => ConnectInvocationEvent._();
  @$core.override
  ConnectInvocationEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConnectInvocationEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectInvocationEvent>(create);
  static ConnectInvocationEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $0.LLMStreamEvent get event => $_getN(1);
  @$pb.TagNumber(2)
  set event($0.LLMStreamEvent value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasEvent() => $_has(1);
  @$pb.TagNumber(2)
  void clearEvent() => $_clearField(2);
  @$pb.TagNumber(2)
  $0.LLMStreamEvent ensureEvent() => $_ensure(1);
}

/// The connection stays open between generations, so the client needs a
/// control-plane exchange that can detect a host stopped while chat is idle.
/// These frames deliberately remain separate from LLM invocation payloads:
/// a health check must never reach a model or appear as an assistant message.
class ConnectHeartbeatRequest extends $pb.GeneratedMessage {
  factory ConnectHeartbeatRequest({
    $core.String? sessionId,
    $fixnum.Int64? sequence,
  }) {
    final result = create();
    if (sessionId != null) result.sessionId = sessionId;
    if (sequence != null) result.sequence = sequence;
    return result;
  }

  ConnectHeartbeatRequest._();

  factory ConnectHeartbeatRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConnectHeartbeatRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectHeartbeatRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'sessionId')
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'sequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectHeartbeatRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectHeartbeatRequest copyWith(
          void Function(ConnectHeartbeatRequest) updates) =>
      super.copyWith((message) => updates(message as ConnectHeartbeatRequest))
          as ConnectHeartbeatRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConnectHeartbeatRequest create() => ConnectHeartbeatRequest._();
  @$core.override
  ConnectHeartbeatRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConnectHeartbeatRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectHeartbeatRequest>(create);
  static ConnectHeartbeatRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sessionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set sessionId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSessionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get sequence => $_getI64(1);
  @$pb.TagNumber(2)
  set sequence($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSequence() => $_has(1);
  @$pb.TagNumber(2)
  void clearSequence() => $_clearField(2);
}

class ConnectHeartbeatResponse extends $pb.GeneratedMessage {
  factory ConnectHeartbeatResponse({
    $core.String? sessionId,
    $fixnum.Int64? sequence,
  }) {
    final result = create();
    if (sessionId != null) result.sessionId = sessionId;
    if (sequence != null) result.sequence = sequence;
    return result;
  }

  ConnectHeartbeatResponse._();

  factory ConnectHeartbeatResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConnectHeartbeatResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectHeartbeatResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'sessionId')
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'sequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectHeartbeatResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectHeartbeatResponse copyWith(
          void Function(ConnectHeartbeatResponse) updates) =>
      super.copyWith((message) => updates(message as ConnectHeartbeatResponse))
          as ConnectHeartbeatResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConnectHeartbeatResponse create() => ConnectHeartbeatResponse._();
  @$core.override
  ConnectHeartbeatResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConnectHeartbeatResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectHeartbeatResponse>(create);
  static ConnectHeartbeatResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sessionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set sessionId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSessionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get sequence => $_getI64(1);
  @$pb.TagNumber(2)
  set sequence($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSequence() => $_has(1);
  @$pb.TagNumber(2)
  void clearSequence() => $_clearField(2);
}

enum ConnectClientFrame_Payload { invocation, heartbeat, notSet }

/// Every frame after the initial ClientHello handshake is carried in one of
/// these explicit envelopes. This leaves typed inference traffic untouched
/// while allowing clients to verify an otherwise-idle host connection.
class ConnectClientFrame extends $pb.GeneratedMessage {
  factory ConnectClientFrame({
    ConnectInvocationRequest? invocation,
    ConnectHeartbeatRequest? heartbeat,
  }) {
    final result = create();
    if (invocation != null) result.invocation = invocation;
    if (heartbeat != null) result.heartbeat = heartbeat;
    return result;
  }

  ConnectClientFrame._();

  factory ConnectClientFrame.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConnectClientFrame.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ConnectClientFrame_Payload>
      _ConnectClientFrame_PayloadByTag = {
    1: ConnectClientFrame_Payload.invocation,
    2: ConnectClientFrame_Payload.heartbeat,
    0: ConnectClientFrame_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectClientFrame',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..oo(0, [1, 2])
    ..aOM<ConnectInvocationRequest>(1, _omitFieldNames ? '' : 'invocation',
        subBuilder: ConnectInvocationRequest.create)
    ..aOM<ConnectHeartbeatRequest>(2, _omitFieldNames ? '' : 'heartbeat',
        subBuilder: ConnectHeartbeatRequest.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectClientFrame clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectClientFrame copyWith(void Function(ConnectClientFrame) updates) =>
      super.copyWith((message) => updates(message as ConnectClientFrame))
          as ConnectClientFrame;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConnectClientFrame create() => ConnectClientFrame._();
  @$core.override
  ConnectClientFrame createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConnectClientFrame getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectClientFrame>(create);
  static ConnectClientFrame? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  ConnectClientFrame_Payload whichPayload() =>
      _ConnectClientFrame_PayloadByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  void clearPayload() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  ConnectInvocationRequest get invocation => $_getN(0);
  @$pb.TagNumber(1)
  set invocation(ConnectInvocationRequest value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasInvocation() => $_has(0);
  @$pb.TagNumber(1)
  void clearInvocation() => $_clearField(1);
  @$pb.TagNumber(1)
  ConnectInvocationRequest ensureInvocation() => $_ensure(0);

  @$pb.TagNumber(2)
  ConnectHeartbeatRequest get heartbeat => $_getN(1);
  @$pb.TagNumber(2)
  set heartbeat(ConnectHeartbeatRequest value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasHeartbeat() => $_has(1);
  @$pb.TagNumber(2)
  void clearHeartbeat() => $_clearField(2);
  @$pb.TagNumber(2)
  ConnectHeartbeatRequest ensureHeartbeat() => $_ensure(1);
}

enum ConnectHostFrame_Payload { invocationEvent, heartbeat, notSet }

class ConnectHostFrame extends $pb.GeneratedMessage {
  factory ConnectHostFrame({
    ConnectInvocationEvent? invocationEvent,
    ConnectHeartbeatResponse? heartbeat,
  }) {
    final result = create();
    if (invocationEvent != null) result.invocationEvent = invocationEvent;
    if (heartbeat != null) result.heartbeat = heartbeat;
    return result;
  }

  ConnectHostFrame._();

  factory ConnectHostFrame.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConnectHostFrame.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ConnectHostFrame_Payload>
      _ConnectHostFrame_PayloadByTag = {
    1: ConnectHostFrame_Payload.invocationEvent,
    2: ConnectHostFrame_Payload.heartbeat,
    0: ConnectHostFrame_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectHostFrame',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..oo(0, [1, 2])
    ..aOM<ConnectInvocationEvent>(1, _omitFieldNames ? '' : 'invocationEvent',
        subBuilder: ConnectInvocationEvent.create)
    ..aOM<ConnectHeartbeatResponse>(2, _omitFieldNames ? '' : 'heartbeat',
        subBuilder: ConnectHeartbeatResponse.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectHostFrame clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectHostFrame copyWith(void Function(ConnectHostFrame) updates) =>
      super.copyWith((message) => updates(message as ConnectHostFrame))
          as ConnectHostFrame;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConnectHostFrame create() => ConnectHostFrame._();
  @$core.override
  ConnectHostFrame createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConnectHostFrame getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectHostFrame>(create);
  static ConnectHostFrame? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  ConnectHostFrame_Payload whichPayload() =>
      _ConnectHostFrame_PayloadByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  void clearPayload() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  ConnectInvocationEvent get invocationEvent => $_getN(0);
  @$pb.TagNumber(1)
  set invocationEvent(ConnectInvocationEvent value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasInvocationEvent() => $_has(0);
  @$pb.TagNumber(1)
  void clearInvocationEvent() => $_clearField(1);
  @$pb.TagNumber(1)
  ConnectInvocationEvent ensureInvocationEvent() => $_ensure(0);

  @$pb.TagNumber(2)
  ConnectHeartbeatResponse get heartbeat => $_getN(1);
  @$pb.TagNumber(2)
  set heartbeat(ConnectHeartbeatResponse value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasHeartbeat() => $_has(1);
  @$pb.TagNumber(2)
  void clearHeartbeat() => $_clearField(2);
  @$pb.TagNumber(2)
  ConnectHeartbeatResponse ensureHeartbeat() => $_ensure(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
