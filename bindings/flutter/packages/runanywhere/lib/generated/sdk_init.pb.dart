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

import 'package:protobuf/protobuf.dart' as $pb;

import 'errors.pb.dart' as $0;
import 'model_types.pbenum.dart' as $1;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// The only platform-supplied values commons cannot derive itself. Platform
/// adapter callbacks are registered separately through rac_platform_adapter_t
/// before this call; this message is purely the data envelope.
class SdkInitPhase1Request extends $pb.GeneratedMessage {
  factory SdkInitPhase1Request({
    $1.SDKEnvironment? environment,
    $core.String? apiKey,
    $core.String? baseUrl,
    $core.String? deviceId,
    $core.String? platform,
    $core.String? sdkVersion,
    $core.int? requestTimeoutMs,
    $core.int? maxRetries,
  }) {
    final result = create();
    if (environment != null) result.environment = environment;
    if (apiKey != null) result.apiKey = apiKey;
    if (baseUrl != null) result.baseUrl = baseUrl;
    if (deviceId != null) result.deviceId = deviceId;
    if (platform != null) result.platform = platform;
    if (sdkVersion != null) result.sdkVersion = sdkVersion;
    if (requestTimeoutMs != null) result.requestTimeoutMs = requestTimeoutMs;
    if (maxRetries != null) result.maxRetries = maxRetries;
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
    ..aE<$1.SDKEnvironment>(1, _omitFieldNames ? '' : 'environment',
        enumValues: $1.SDKEnvironment.values)
    ..aOS(2, _omitFieldNames ? '' : 'apiKey')
    ..aOS(3, _omitFieldNames ? '' : 'baseUrl')
    ..aOS(4, _omitFieldNames ? '' : 'deviceId')
    ..aOS(5, _omitFieldNames ? '' : 'platform')
    ..aOS(6, _omitFieldNames ? '' : 'sdkVersion')
    ..aI(7, _omitFieldNames ? '' : 'requestTimeoutMs')
    ..aI(8, _omitFieldNames ? '' : 'maxRetries')
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

  /// model_types.proto's SDKEnvironment is the single environment vocabulary.
  /// Its zero is UNSPECIFIED, so an omitted field means unset, not
  /// "development": commons must fail closed rather than pick an environment.
  @$pb.TagNumber(1)
  $1.SDKEnvironment get environment => $_getN(0);
  @$pb.TagNumber(1)
  set environment($1.SDKEnvironment value) => $_setField(1, value);
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

  /// Caller override for NetworkDefaults.request_timeout_ms. Unset = the pool
  /// default (60000). openai-python / anthropic-python `timeout`.
  @$pb.TagNumber(7)
  $core.int get requestTimeoutMs => $_getIZ(6);
  @$pb.TagNumber(7)
  set requestTimeoutMs($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasRequestTimeoutMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearRequestTimeoutMs() => $_clearField(7);

  /// Caller override for NetworkDefaults.max_retries. Unset = the pool
  /// default (3). openai-python / anthropic-python `max_retries`; 0 disables
  /// retries.
  @$pb.TagNumber(8)
  $core.int get maxRetries => $_getIZ(7);
  @$pb.TagNumber(8)
  set maxRetries($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasMaxRetries() => $_has(7);
  @$pb.TagNumber(8)
  void clearMaxRetries() => $_clearField(8);
}

/// The one value that legitimately varies between a dev build and a release.
/// Telemetry flushing and registry/local-file reconciliation are commons
/// behaviour, not per-call hints.
class SdkInitPhase2Request extends $pb.GeneratedMessage {
  factory SdkInitPhase2Request({
    $core.String? buildToken,
  }) {
    final result = create();
    if (buildToken != null) result.buildToken = buildToken;
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
}

/// Returned by Phase 1, Phase 2, and retryHTTP.
///
/// A successful Phase 2 may still carry a warning: HTTP/auth setup is allowed
/// to fail in offline mode, in which case error is unset and warning holds the
/// offline notice while the SDK continues on cached models.
class SdkInitResult extends $pb.GeneratedMessage {
  factory SdkInitResult({
    $0.SDKError? error,
    $core.int? linkedModelsCount,
    $core.String? warning,
    $core.bool? hasCompletedHttpSetup,
    $core.bool? httpApplicable,
  }) {
    final result = create();
    if (error != null) result.error = error;
    if (linkedModelsCount != null) result.linkedModelsCount = linkedModelsCount;
    if (warning != null) result.warning = warning;
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
    ..aOM<$0.SDKError>(1, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..aI(2, _omitFieldNames ? '' : 'linkedModelsCount',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(3, _omitFieldNames ? '' : 'warning')
    ..aOB(4, _omitFieldNames ? '' : 'hasCompletedHttpSetup')
    ..aOB(5, _omitFieldNames ? '' : 'httpApplicable')
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
  $0.SDKError get error => $_getN(0);
  @$pb.TagNumber(1)
  set error($0.SDKError value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasError() => $_has(0);
  @$pb.TagNumber(1)
  void clearError() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.SDKError ensureError() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.int get linkedModelsCount => $_getIZ(1);
  @$pb.TagNumber(2)
  set linkedModelsCount($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLinkedModelsCount() => $_has(1);
  @$pb.TagNumber(2)
  void clearLinkedModelsCount() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get warning => $_getSZ(2);
  @$pb.TagNumber(3)
  set warning($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasWarning() => $_has(2);
  @$pb.TagNumber(3)
  void clearWarning() => $_clearField(3);

  /// The cross-phase latched bit that survives between calls. SDKs read this
  /// to decide whether an authenticated call can proceed without a retryHTTP.
  @$pb.TagNumber(4)
  $core.bool get hasCompletedHttpSetup => $_getBF(3);
  @$pb.TagNumber(4)
  set hasCompletedHttpSetup($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasHasCompletedHttpSetup() => $_has(3);
  @$pb.TagNumber(4)
  void clearHasCompletedHttpSetup() => $_clearField(4);

  /// Whether this configuration has a usable credential and URL pair at all.
  /// Local-only development builds set it false so platform SDKs stop
  /// retrying HTTP on every guarded call.
  @$pb.TagNumber(5)
  $core.bool get httpApplicable => $_getBF(4);
  @$pb.TagNumber(5)
  set httpApplicable($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasHttpApplicable() => $_has(4);
  @$pb.TagNumber(5)
  void clearHttpApplicable() => $_clearField(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
