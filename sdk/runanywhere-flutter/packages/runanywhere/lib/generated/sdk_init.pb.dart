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

/// ---------------------------------------------------------------------------
/// Phase 1 input — synchronous core initialization. Carries the only
/// platform-supplied values commons cannot derive on its own: API credentials
/// + environment + device id (resolved by platform Keychain/Keystore lookup).
///
/// Platform adapter callbacks (file I/O, secure storage, HTTP transport, log,
/// memory) are registered separately via rac_platform_adapter_t prior to
/// calling this entry point. This message is purely the data envelope.
/// ---------------------------------------------------------------------------
class SdkInitPhase1Request extends $pb.GeneratedMessage {
  factory SdkInitPhase1Request({
    SdkInitEnvironment? environment,
    $core.String? apiKey,
    $core.String? baseUrl,
    $core.String? deviceId,
  }) {
    final result = create();
    if (environment != null) result.environment = environment;
    if (apiKey != null) result.apiKey = apiKey;
    if (baseUrl != null) result.baseUrl = baseUrl;
    if (deviceId != null) result.deviceId = deviceId;
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
}

/// ---------------------------------------------------------------------------
/// Phase 2 input — async services initialization. Most state is already
/// resident in commons after Phase 1; this envelope exists so SDKs can pass
/// per-call hints without changing the signature. Currently empty — reserved
/// for future flags such as `force_refresh_assignments` or
/// `skip_device_registration` once Kotlin/RN/Flutter parity demands them.
/// ---------------------------------------------------------------------------
class SdkInitPhase2Request extends $pb.GeneratedMessage {
  factory SdkInitPhase2Request() => create();

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
}

/// ---------------------------------------------------------------------------
/// Result envelope returned by Phase 1 / Phase 2 / retryHTTP. Mirrors the
/// Swift RunAnywhere.swift Phase 2 logging shape (phase + duration + outcome
/// counts) so each SDK reports the same structured result to its consumer.
///
/// success = true when the phase reached its terminal step. Even successful
/// Phase 2 results may carry warnings: HTTP/auth setup is allowed to fail in
/// offline mode; the SDK continues with cached/local models. In that case
/// success=true, http_configured=false, and warning carries the offline-mode
/// notice.
/// ---------------------------------------------------------------------------
class SdkInitResult extends $pb.GeneratedMessage {
  factory SdkInitResult({
    SdkInitPhase? phase,
    $core.bool? success,
    $0.SDKError? error,
    $core.bool? httpConfigured,
    $core.bool? deviceRegistered,
    $core.int? linkedModelsCount,
    $core.int? discoveredOrphans,
    $core.String? warning,
    $fixnum.Int64? durationMs,
    $core.bool? hasCompletedHttpSetup,
  }) {
    final result = create();
    if (phase != null) result.phase = phase;
    if (success != null) result.success = success;
    if (error != null) result.error = error;
    if (httpConfigured != null) result.httpConfigured = httpConfigured;
    if (deviceRegistered != null) result.deviceRegistered = deviceRegistered;
    if (linkedModelsCount != null) result.linkedModelsCount = linkedModelsCount;
    if (discoveredOrphans != null) result.discoveredOrphans = discoveredOrphans;
    if (warning != null) result.warning = warning;
    if (durationMs != null) result.durationMs = durationMs;
    if (hasCompletedHttpSetup != null)
      result.hasCompletedHttpSetup = hasCompletedHttpSetup;
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
    ..aOB(2, _omitFieldNames ? '' : 'success')
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

  @$pb.TagNumber(2)
  $core.bool get success => $_getBF(1);
  @$pb.TagNumber(2)
  set success($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSuccess() => $_has(1);
  @$pb.TagNumber(2)
  void clearSuccess() => $_clearField(2);

  @$pb.TagNumber(3)
  $0.SDKError get error => $_getN(2);
  @$pb.TagNumber(3)
  set error($0.SDKError value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(3)
  void clearError() => $_clearField(3);
  @$pb.TagNumber(3)
  $0.SDKError ensureError() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.bool get httpConfigured => $_getBF(3);
  @$pb.TagNumber(4)
  set httpConfigured($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasHttpConfigured() => $_has(3);
  @$pb.TagNumber(4)
  void clearHttpConfigured() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get deviceRegistered => $_getBF(4);
  @$pb.TagNumber(5)
  set deviceRegistered($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDeviceRegistered() => $_has(4);
  @$pb.TagNumber(5)
  void clearDeviceRegistered() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get linkedModelsCount => $_getIZ(5);
  @$pb.TagNumber(6)
  set linkedModelsCount($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLinkedModelsCount() => $_has(5);
  @$pb.TagNumber(6)
  void clearLinkedModelsCount() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get discoveredOrphans => $_getIZ(6);
  @$pb.TagNumber(7)
  set discoveredOrphans($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasDiscoveredOrphans() => $_has(6);
  @$pb.TagNumber(7)
  void clearDiscoveredOrphans() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get warning => $_getSZ(7);
  @$pb.TagNumber(8)
  set warning($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasWarning() => $_has(7);
  @$pb.TagNumber(8)
  void clearWarning() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get durationMs => $_getI64(8);
  @$pb.TagNumber(9)
  set durationMs($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasDurationMs() => $_has(8);
  @$pb.TagNumber(9)
  void clearDurationMs() => $_clearField(9);

  /// Explicit two-phase HTTP-setup completion flag,
  /// decoupled from services-init completion so SDKs that initialize
  /// offline (no connectivity) can still report success=true with
  /// has_completed_http_setup=false and retry HTTP later via the
  /// SDK_INIT_PHASE_RETRY_HTTP path. Mirrors RunAnywhere.swift:37
  /// (`internal static var hasCompletedHTTPSetup`) and is the canonical
  /// signal Flutter / Web / RN consume to decide whether the next
  /// download/authenticated call can proceed without a retryHTTP step.
  ///
  /// Distinct from `http_configured` (field 4) which historically meant
  /// "HTTP transport wired up at this phase's call site"; this field is
  /// the cross-phase latched bit that survives between phase calls.
  @$pb.TagNumber(10)
  $core.bool get hasCompletedHttpSetup => $_getBF(9);
  @$pb.TagNumber(10)
  set hasCompletedHttpSetup($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(10)
  $core.bool hasHasCompletedHttpSetup() => $_has(9);
  @$pb.TagNumber(10)
  void clearHasCompletedHttpSetup() => $_clearField(10);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
