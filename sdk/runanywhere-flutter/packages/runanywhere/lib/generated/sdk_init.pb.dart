//
//  Generated code. Do not modify.
//  source: sdk_init.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'errors.pb.dart' as $13;
import 'sdk_init.pbenum.dart';

export 'sdk_init.pbenum.dart';

///  ---------------------------------------------------------------------------
///  Phase 1 input — synchronous core initialization. Carries the only
///  platform-supplied values commons cannot derive on its own: API credentials
///  + environment + device id (resolved by platform Keychain/Keystore lookup).
///
///  Platform adapter callbacks (file I/O, secure storage, HTTP transport, log,
///  memory) are registered separately via rac_platform_adapter_t prior to
///  calling this entry point. This message is purely the data envelope.
///  ---------------------------------------------------------------------------
class SdkInitPhase1Request extends $pb.GeneratedMessage {
  factory SdkInitPhase1Request({
    SdkInitEnvironment? environment,
    $core.String? apiKey,
    $core.String? baseUrl,
    $core.String? deviceId,
  }) {
    final $result = create();
    if (environment != null) {
      $result.environment = environment;
    }
    if (apiKey != null) {
      $result.apiKey = apiKey;
    }
    if (baseUrl != null) {
      $result.baseUrl = baseUrl;
    }
    if (deviceId != null) {
      $result.deviceId = deviceId;
    }
    return $result;
  }
  SdkInitPhase1Request._() : super();
  factory SdkInitPhase1Request.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SdkInitPhase1Request.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SdkInitPhase1Request', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<SdkInitEnvironment>(1, _omitFieldNames ? '' : 'environment', $pb.PbFieldType.OE, defaultOrMaker: SdkInitEnvironment.SDK_INIT_ENVIRONMENT_DEVELOPMENT, valueOf: SdkInitEnvironment.valueOf, enumValues: SdkInitEnvironment.values)
    ..aOS(2, _omitFieldNames ? '' : 'apiKey')
    ..aOS(3, _omitFieldNames ? '' : 'baseUrl')
    ..aOS(4, _omitFieldNames ? '' : 'deviceId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SdkInitPhase1Request clone() => SdkInitPhase1Request()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SdkInitPhase1Request copyWith(void Function(SdkInitPhase1Request) updates) => super.copyWith((message) => updates(message as SdkInitPhase1Request)) as SdkInitPhase1Request;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SdkInitPhase1Request create() => SdkInitPhase1Request._();
  SdkInitPhase1Request createEmptyInstance() => create();
  static $pb.PbList<SdkInitPhase1Request> createRepeated() => $pb.PbList<SdkInitPhase1Request>();
  @$core.pragma('dart2js:noInline')
  static SdkInitPhase1Request getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SdkInitPhase1Request>(create);
  static SdkInitPhase1Request? _defaultInstance;

  @$pb.TagNumber(1)
  SdkInitEnvironment get environment => $_getN(0);
  @$pb.TagNumber(1)
  set environment(SdkInitEnvironment v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasEnvironment() => $_has(0);
  @$pb.TagNumber(1)
  void clearEnvironment() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get apiKey => $_getSZ(1);
  @$pb.TagNumber(2)
  set apiKey($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasApiKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearApiKey() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get baseUrl => $_getSZ(2);
  @$pb.TagNumber(3)
  set baseUrl($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasBaseUrl() => $_has(2);
  @$pb.TagNumber(3)
  void clearBaseUrl() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get deviceId => $_getSZ(3);
  @$pb.TagNumber(4)
  set deviceId($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasDeviceId() => $_has(3);
  @$pb.TagNumber(4)
  void clearDeviceId() => clearField(4);
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
  SdkInitPhase2Request._() : super();
  factory SdkInitPhase2Request.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SdkInitPhase2Request.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SdkInitPhase2Request', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SdkInitPhase2Request clone() => SdkInitPhase2Request()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SdkInitPhase2Request copyWith(void Function(SdkInitPhase2Request) updates) => super.copyWith((message) => updates(message as SdkInitPhase2Request)) as SdkInitPhase2Request;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SdkInitPhase2Request create() => SdkInitPhase2Request._();
  SdkInitPhase2Request createEmptyInstance() => create();
  static $pb.PbList<SdkInitPhase2Request> createRepeated() => $pb.PbList<SdkInitPhase2Request>();
  @$core.pragma('dart2js:noInline')
  static SdkInitPhase2Request getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SdkInitPhase2Request>(create);
  static SdkInitPhase2Request? _defaultInstance;
}

///  ---------------------------------------------------------------------------
///  Result envelope returned by Phase 1 / Phase 2 / retryHTTP. Mirrors the
///  Swift RunAnywhere.swift Phase 2 logging shape (phase + duration + outcome
///  counts) so each SDK reports the same structured result to its consumer.
///
///  success = true when the phase reached its terminal step. Even successful
///  Phase 2 results may carry warnings: HTTP/auth setup is allowed to fail in
///  offline mode; the SDK continues with cached/local models. In that case
///  success=true, http_configured=false, and warning carries the offline-mode
///  notice.
///  ---------------------------------------------------------------------------
class SdkInitResult extends $pb.GeneratedMessage {
  factory SdkInitResult({
    SdkInitPhase? phase,
    $core.bool? success,
    $13.SDKError? error,
    $core.bool? httpConfigured,
    $core.bool? deviceRegistered,
    $core.int? linkedModelsCount,
    $core.int? discoveredOrphans,
    $core.String? warning,
    $fixnum.Int64? durationMs,
  }) {
    final $result = create();
    if (phase != null) {
      $result.phase = phase;
    }
    if (success != null) {
      $result.success = success;
    }
    if (error != null) {
      $result.error = error;
    }
    if (httpConfigured != null) {
      $result.httpConfigured = httpConfigured;
    }
    if (deviceRegistered != null) {
      $result.deviceRegistered = deviceRegistered;
    }
    if (linkedModelsCount != null) {
      $result.linkedModelsCount = linkedModelsCount;
    }
    if (discoveredOrphans != null) {
      $result.discoveredOrphans = discoveredOrphans;
    }
    if (warning != null) {
      $result.warning = warning;
    }
    if (durationMs != null) {
      $result.durationMs = durationMs;
    }
    return $result;
  }
  SdkInitResult._() : super();
  factory SdkInitResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SdkInitResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SdkInitResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<SdkInitPhase>(1, _omitFieldNames ? '' : 'phase', $pb.PbFieldType.OE, defaultOrMaker: SdkInitPhase.SDK_INIT_PHASE_UNSPECIFIED, valueOf: SdkInitPhase.valueOf, enumValues: SdkInitPhase.values)
    ..aOB(2, _omitFieldNames ? '' : 'success')
    ..aOM<$13.SDKError>(3, _omitFieldNames ? '' : 'error', subBuilder: $13.SDKError.create)
    ..aOB(4, _omitFieldNames ? '' : 'httpConfigured')
    ..aOB(5, _omitFieldNames ? '' : 'deviceRegistered')
    ..a<$core.int>(6, _omitFieldNames ? '' : 'linkedModelsCount', $pb.PbFieldType.OU3)
    ..a<$core.int>(7, _omitFieldNames ? '' : 'discoveredOrphans', $pb.PbFieldType.OU3)
    ..aOS(8, _omitFieldNames ? '' : 'warning')
    ..aInt64(9, _omitFieldNames ? '' : 'durationMs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SdkInitResult clone() => SdkInitResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SdkInitResult copyWith(void Function(SdkInitResult) updates) => super.copyWith((message) => updates(message as SdkInitResult)) as SdkInitResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SdkInitResult create() => SdkInitResult._();
  SdkInitResult createEmptyInstance() => create();
  static $pb.PbList<SdkInitResult> createRepeated() => $pb.PbList<SdkInitResult>();
  @$core.pragma('dart2js:noInline')
  static SdkInitResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SdkInitResult>(create);
  static SdkInitResult? _defaultInstance;

  @$pb.TagNumber(1)
  SdkInitPhase get phase => $_getN(0);
  @$pb.TagNumber(1)
  set phase(SdkInitPhase v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasPhase() => $_has(0);
  @$pb.TagNumber(1)
  void clearPhase() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get success => $_getBF(1);
  @$pb.TagNumber(2)
  set success($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSuccess() => $_has(1);
  @$pb.TagNumber(2)
  void clearSuccess() => clearField(2);

  @$pb.TagNumber(3)
  $13.SDKError get error => $_getN(2);
  @$pb.TagNumber(3)
  set error($13.SDKError v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(3)
  void clearError() => clearField(3);
  @$pb.TagNumber(3)
  $13.SDKError ensureError() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.bool get httpConfigured => $_getBF(3);
  @$pb.TagNumber(4)
  set httpConfigured($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasHttpConfigured() => $_has(3);
  @$pb.TagNumber(4)
  void clearHttpConfigured() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get deviceRegistered => $_getBF(4);
  @$pb.TagNumber(5)
  set deviceRegistered($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasDeviceRegistered() => $_has(4);
  @$pb.TagNumber(5)
  void clearDeviceRegistered() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get linkedModelsCount => $_getIZ(5);
  @$pb.TagNumber(6)
  set linkedModelsCount($core.int v) { $_setUnsignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasLinkedModelsCount() => $_has(5);
  @$pb.TagNumber(6)
  void clearLinkedModelsCount() => clearField(6);

  @$pb.TagNumber(7)
  $core.int get discoveredOrphans => $_getIZ(6);
  @$pb.TagNumber(7)
  set discoveredOrphans($core.int v) { $_setUnsignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasDiscoveredOrphans() => $_has(6);
  @$pb.TagNumber(7)
  void clearDiscoveredOrphans() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get warning => $_getSZ(7);
  @$pb.TagNumber(8)
  set warning($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasWarning() => $_has(7);
  @$pb.TagNumber(8)
  void clearWarning() => clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get durationMs => $_getI64(8);
  @$pb.TagNumber(9)
  set durationMs($fixnum.Int64 v) { $_setInt64(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasDurationMs() => $_has(8);
  @$pb.TagNumber(9)
  void clearDurationMs() => clearField(9);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
