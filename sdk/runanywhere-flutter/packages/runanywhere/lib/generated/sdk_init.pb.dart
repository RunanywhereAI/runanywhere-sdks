// This is a generated file - do not edit.
//
// Generated from sdk_init.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'errors.pb.dart' as $0;
import 'sdk_init.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'sdk_init.pbenum.dart';

/// The only platform-supplied values commons cannot derive itself. Platform
/// adapter callbacks are registered separately through rac_platform_adapter_t
/// before this call; this message is purely the data envelope.
class SdkInitPhase1Request extends $pb.GeneratedMessage {
  factory SdkInitPhase1Request({
    SdkInitEnvironment? environment,
    $core.String? apiKey,
    $core.String? baseUrl,
    $core.String? deviceId,
    $core.String? platform,
    $core.String? sdkVersion,
  }) {
    final result = create();
    if (environment != null) result.environment = environment;
    if (apiKey != null) result.apiKey = apiKey;
    if (baseUrl != null) result.baseUrl = baseUrl;
    if (deviceId != null) result.deviceId = deviceId;
    if (platform != null) result.platform = platform;
    if (sdkVersion != null) result.sdkVersion = sdkVersion;
    return result;
  }

  SdkInitPhase1Request._();

  factory SdkInitPhase1Request.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SdkInitPhase1Request.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SdkInitPhase1Request',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<SdkInitEnvironment>(1, _omitFieldNames ? '' : 'environment',
        enumValues: SdkInitEnvironment.values)
    ..aOS(2, _omitFieldNames ? '' : 'apiKey')
    ..aOS(3, _omitFieldNames ? '' : 'baseUrl')
    ..aOS(4, _omitFieldNames ? '' : 'deviceId')
    ..aOS(5, _omitFieldNames ? '' : 'platform')
    ..aOS(6, _omitFieldNames ? '' : 'sdkVersion')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SdkInitPhase1Request clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SdkInitPhase1Request copyWith(void Function(SdkInitPhase1Request) updates) =>
      super.copyWith((message) => updates(message as SdkInitPhase1Request))
          as SdkInitPhase1Request;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SdkInitPhase1Request create() => SdkInitPhase1Request._();
  @$core.override
  SdkInitPhase1Request createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SdkInitPhase1Request getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SdkInitPhase1Request>(create);
  static SdkInitPhase1Request? _defaultInstance;

  @$pb.TagNumber(1)
  SdkInitEnvironment get environment => $_getN(0);
  @$pb.TagNumber(1)
  set environment(SdkInitEnvironment value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasEnvironment() => $_has(0);
  @$pb.TagNumber(1)
  void clearEnvironment() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get apiKey => $_getSZ(1);
  @$pb.TagNumber(2)
  set apiKey($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasApiKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearApiKey() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get baseUrl => $_getSZ(2);
  @$pb.TagNumber(3)
  set baseUrl($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBaseUrl() => $_has(2);
  @$pb.TagNumber(3)
  void clearBaseUrl() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get deviceId => $_getSZ(3);
  @$pb.TagNumber(4)
  set deviceId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDeviceId() => $_has(3);
  @$pb.TagNumber(4)
  void clearDeviceId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get platform => $_getSZ(4);
  @$pb.TagNumber(5)
  set platform($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPlatform() => $_has(4);
  @$pb.TagNumber(5)
  void clearPlatform() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get sdkVersion => $_getSZ(5);
  @$pb.TagNumber(6)
  set sdkVersion($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSdkVersion() => $_has(5);
  @$pb.TagNumber(6)
  void clearSdkVersion() => $_clearField(6);
}

/// Most state is already resident in commons after Phase 1; these are the
/// per-call hints that stay SDK-owned.
class SdkInitPhase2Request extends $pb.GeneratedMessage {
  factory SdkInitPhase2Request({
    $core.String? buildToken,
    $core.bool? forceRefreshAssignments,
    $core.bool? flushTelemetry,
    $core.bool? discoverDownloadedModels,
    $core.bool? rescanLocalModels,
  }) {
    final result = create();
    if (buildToken != null) result.buildToken = buildToken;
    if (forceRefreshAssignments != null)
      result.forceRefreshAssignments = forceRefreshAssignments;
    if (flushTelemetry != null) result.flushTelemetry = flushTelemetry;
    if (discoverDownloadedModels != null)
      result.discoverDownloadedModels = discoverDownloadedModels;
    if (rescanLocalModels != null) result.rescanLocalModels = rescanLocalModels;
    return result;
  }

  SdkInitPhase2Request._();

  factory SdkInitPhase2Request.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SdkInitPhase2Request.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SdkInitPhase2Request',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'buildToken')
    ..aOB(2, _omitFieldNames ? '' : 'forceRefreshAssignments')
    ..aOB(3, _omitFieldNames ? '' : 'flushTelemetry')
    ..aOB(4, _omitFieldNames ? '' : 'discoverDownloadedModels')
    ..aOB(5, _omitFieldNames ? '' : 'rescanLocalModels')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SdkInitPhase2Request clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SdkInitPhase2Request copyWith(void Function(SdkInitPhase2Request) updates) =>
      super.copyWith((message) => updates(message as SdkInitPhase2Request))
          as SdkInitPhase2Request;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SdkInitPhase2Request create() => SdkInitPhase2Request._();
  @$core.override
  SdkInitPhase2Request createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SdkInitPhase2Request getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SdkInitPhase2Request>(create);
  static SdkInitPhase2Request? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get buildToken => $_getSZ(0);
  @$pb.TagNumber(1)
  set buildToken($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasBuildToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearBuildToken() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get forceRefreshAssignments => $_getBF(1);
  @$pb.TagNumber(2)
  set forceRefreshAssignments($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasForceRefreshAssignments() => $_has(1);
  @$pb.TagNumber(2)
  void clearForceRefreshAssignments() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get flushTelemetry => $_getBF(2);
  @$pb.TagNumber(3)
  set flushTelemetry($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFlushTelemetry() => $_has(2);
  @$pb.TagNumber(3)
  void clearFlushTelemetry() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get discoverDownloadedModels => $_getBF(3);
  @$pb.TagNumber(4)
  set discoverDownloadedModels($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDiscoverDownloadedModels() => $_has(3);
  @$pb.TagNumber(4)
  void clearDiscoverDownloadedModels() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get rescanLocalModels => $_getBF(4);
  @$pb.TagNumber(5)
  set rescanLocalModels($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRescanLocalModels() => $_has(4);
  @$pb.TagNumber(5)
  void clearRescanLocalModels() => $_clearField(5);
}

/// Returned by Phase 1, Phase 2, and retryHTTP.
///
/// A successful Phase 2 may still carry a warning: HTTP/auth setup is allowed
/// to fail in offline mode, in which case error is unset, http_configured=false,
/// and warning holds the offline notice while the SDK continues on cached
/// models.
class SdkInitResult extends $pb.GeneratedMessage {
  factory SdkInitResult({
    SdkInitPhase? phase,
    $0.SDKError? error,
    $core.bool? httpConfigured,
    $core.bool? deviceRegistered,
    $core.int? linkedModelsCount,
    $core.int? discoveredOrphans,
    $core.String? warning,
    $fixnum.Int64? durationMs,
    $core.bool? hasCompletedHttpSetup,
    $core.bool? httpApplicable,
  }) {
    final result = create();
    if (phase != null) result.phase = phase;
    if (error != null) result.error = error;
    if (httpConfigured != null) result.httpConfigured = httpConfigured;
    if (deviceRegistered != null) result.deviceRegistered = deviceRegistered;
    if (linkedModelsCount != null) result.linkedModelsCount = linkedModelsCount;
    if (discoveredOrphans != null) result.discoveredOrphans = discoveredOrphans;
    if (warning != null) result.warning = warning;
    if (durationMs != null) result.durationMs = durationMs;
    if (hasCompletedHttpSetup != null)
      result.hasCompletedHttpSetup = hasCompletedHttpSetup;
    if (httpApplicable != null) result.httpApplicable = httpApplicable;
    return result;
  }

  SdkInitResult._();

  factory SdkInitResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SdkInitResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SdkInitResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<SdkInitPhase>(1, _omitFieldNames ? '' : 'phase',
        enumValues: SdkInitPhase.values)
    ..aOM<$0.SDKError>(3, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..aOB(4, _omitFieldNames ? '' : 'httpConfigured')
    ..aOB(5, _omitFieldNames ? '' : 'deviceRegistered')
    ..aI(6, _omitFieldNames ? '' : 'linkedModelsCount',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(7, _omitFieldNames ? '' : 'discoveredOrphans',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(8, _omitFieldNames ? '' : 'warning')
    ..aInt64(9, _omitFieldNames ? '' : 'durationMs')
    ..aOB(10, _omitFieldNames ? '' : 'hasCompletedHttpSetup')
    ..aOB(11, _omitFieldNames ? '' : 'httpApplicable')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SdkInitResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SdkInitResult copyWith(void Function(SdkInitResult) updates) =>
      super.copyWith((message) => updates(message as SdkInitResult))
          as SdkInitResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SdkInitResult create() => SdkInitResult._();
  @$core.override
  SdkInitResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SdkInitResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SdkInitResult>(create);
  static SdkInitResult? _defaultInstance;

  @$pb.TagNumber(1)
  SdkInitPhase get phase => $_getN(0);
  @$pb.TagNumber(1)
  set phase(SdkInitPhase value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPhase() => $_has(0);
  @$pb.TagNumber(1)
  void clearPhase() => $_clearField(1);

  @$pb.TagNumber(3)
  $0.SDKError get error => $_getN(1);
  @$pb.TagNumber(3)
  set error($0.SDKError value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasError() => $_has(1);
  @$pb.TagNumber(3)
  void clearError() => $_clearField(3);
  @$pb.TagNumber(3)
  $0.SDKError ensureError() => $_ensure(1);

  @$pb.TagNumber(4)
  $core.bool get httpConfigured => $_getBF(2);
  @$pb.TagNumber(4)
  set httpConfigured($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(4)
  $core.bool hasHttpConfigured() => $_has(2);
  @$pb.TagNumber(4)
  void clearHttpConfigured() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get deviceRegistered => $_getBF(3);
  @$pb.TagNumber(5)
  set deviceRegistered($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(5)
  $core.bool hasDeviceRegistered() => $_has(3);
  @$pb.TagNumber(5)
  void clearDeviceRegistered() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get linkedModelsCount => $_getIZ(4);
  @$pb.TagNumber(6)
  set linkedModelsCount($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(6)
  $core.bool hasLinkedModelsCount() => $_has(4);
  @$pb.TagNumber(6)
  void clearLinkedModelsCount() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get discoveredOrphans => $_getIZ(5);
  @$pb.TagNumber(7)
  set discoveredOrphans($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(7)
  $core.bool hasDiscoveredOrphans() => $_has(5);
  @$pb.TagNumber(7)
  void clearDiscoveredOrphans() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get warning => $_getSZ(6);
  @$pb.TagNumber(8)
  set warning($core.String value) => $_setString(6, value);
  @$pb.TagNumber(8)
  $core.bool hasWarning() => $_has(6);
  @$pb.TagNumber(8)
  void clearWarning() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get durationMs => $_getI64(7);
  @$pb.TagNumber(9)
  set durationMs($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(9)
  $core.bool hasDurationMs() => $_has(7);
  @$pb.TagNumber(9)
  void clearDurationMs() => $_clearField(9);

  /// The cross-phase latched bit that survives between calls, as opposed to
  /// http_configured, which describes only the calling phase. SDKs read this
  /// to decide whether an authenticated call can proceed without a retryHTTP.
  @$pb.TagNumber(10)
  $core.bool get hasCompletedHttpSetup => $_getBF(8);
  @$pb.TagNumber(10)
  set hasCompletedHttpSetup($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(10)
  $core.bool hasHasCompletedHttpSetup() => $_has(8);
  @$pb.TagNumber(10)
  void clearHasCompletedHttpSetup() => $_clearField(10);

  /// Whether this configuration has a usable credential and URL pair at all.
  /// Local-only development builds set it false so platform SDKs stop
  /// retrying HTTP on every guarded call.
  @$pb.TagNumber(11)
  $core.bool get httpApplicable => $_getBF(9);
  @$pb.TagNumber(11)
  set httpApplicable($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(11)
  $core.bool hasHttpApplicable() => $_has(9);
  @$pb.TagNumber(11)
  void clearHttpApplicable() => $_clearField(11);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
