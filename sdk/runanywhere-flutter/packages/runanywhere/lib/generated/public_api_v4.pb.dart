// This is a generated file - do not edit.
//
// Generated from public_api_v4.proto.

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
import 'model_types.pbenum.dart' as $3;
import 'public_api_v4.pbenum.dart';
import 'token_usage.pb.dart' as $2;
import 'tool_calling.pb.dart' as $1;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'public_api_v4.pbenum.dart';

class BackendPreference extends $pb.GeneratedMessage {
  factory BackendPreference({
    $3.InferenceFramework? backend,
    $core.bool? required,
  }) {
    final result = create();
    if (backend != null) result.backend = backend;
    if (required != null) result.required = required;
    return result;
  }

  BackendPreference._();

  factory BackendPreference.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory BackendPreference.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BackendPreference',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<$3.InferenceFramework>(1, _omitFieldNames ? '' : 'backend',
        enumValues: $3.InferenceFramework.values)
    ..aOB(2, _omitFieldNames ? '' : 'required')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BackendPreference clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BackendPreference copyWith(void Function(BackendPreference) updates) =>
      super.copyWith((message) => updates(message as BackendPreference))
          as BackendPreference;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BackendPreference create() => BackendPreference._();
  @$core.override
  BackendPreference createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static BackendPreference getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<BackendPreference>(create);
  static BackendPreference? _defaultInstance;

  @$pb.TagNumber(1)
  $3.InferenceFramework get backend => $_getN(0);
  @$pb.TagNumber(1)
  set backend($3.InferenceFramework value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasBackend() => $_has(0);
  @$pb.TagNumber(1)
  void clearBackend() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get required => $_getBF(1);
  @$pb.TagNumber(2)
  set required($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRequired() => $_has(1);
  @$pb.TagNumber(2)
  void clearRequired() => $_clearField(2);
}

class DevicePlacement extends $pb.GeneratedMessage {
  factory DevicePlacement({
    $core.String? deviceId,
    $core.String? deviceName,
    $core.String? deviceKind,
  }) {
    final result = create();
    if (deviceId != null) result.deviceId = deviceId;
    if (deviceName != null) result.deviceName = deviceName;
    if (deviceKind != null) result.deviceKind = deviceKind;
    return result;
  }

  DevicePlacement._();

  factory DevicePlacement.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DevicePlacement.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DevicePlacement',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'deviceId')
    ..aOS(2, _omitFieldNames ? '' : 'deviceName')
    ..aOS(3, _omitFieldNames ? '' : 'deviceKind')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DevicePlacement clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DevicePlacement copyWith(void Function(DevicePlacement) updates) =>
      super.copyWith((message) => updates(message as DevicePlacement))
          as DevicePlacement;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DevicePlacement create() => DevicePlacement._();
  @$core.override
  DevicePlacement createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DevicePlacement getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DevicePlacement>(create);
  static DevicePlacement? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get deviceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set deviceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get deviceName => $_getSZ(1);
  @$pb.TagNumber(2)
  set deviceName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDeviceName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get deviceKind => $_getSZ(2);
  @$pb.TagNumber(3)
  set deviceKind($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDeviceKind() => $_has(2);
  @$pb.TagNumber(3)
  void clearDeviceKind() => $_clearField(3);
}

/// Resident ownership handle returned by models.load.
class LoadedModelInfo extends $pb.GeneratedMessage {
  factory LoadedModelInfo({
    $core.String? modelId,
    $3.ModelCategory? category,
    $3.InferenceFramework? requestedBackend,
    $3.InferenceFramework? actualBackend,
    DevicePlacement? actualDevice,
    $core.String? runtimeVersion,
    $core.String? abiVersion,
    $core.String? fallbackReason,
    $core.String? resolvedPath,
    $fixnum.Int64? loadedAtUnixMs,
    $core.bool? alreadyLoaded,
    $core.Iterable<$core.String>? warnings,
    $0.SDKError? error,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (category != null) result.category = category;
    if (requestedBackend != null) result.requestedBackend = requestedBackend;
    if (actualBackend != null) result.actualBackend = actualBackend;
    if (actualDevice != null) result.actualDevice = actualDevice;
    if (runtimeVersion != null) result.runtimeVersion = runtimeVersion;
    if (abiVersion != null) result.abiVersion = abiVersion;
    if (fallbackReason != null) result.fallbackReason = fallbackReason;
    if (resolvedPath != null) result.resolvedPath = resolvedPath;
    if (loadedAtUnixMs != null) result.loadedAtUnixMs = loadedAtUnixMs;
    if (alreadyLoaded != null) result.alreadyLoaded = alreadyLoaded;
    if (warnings != null) result.warnings.addAll(warnings);
    if (error != null) result.error = error;
    return result;
  }

  LoadedModelInfo._();

  factory LoadedModelInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoadedModelInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoadedModelInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aE<$3.ModelCategory>(2, _omitFieldNames ? '' : 'category',
        enumValues: $3.ModelCategory.values)
    ..aE<$3.InferenceFramework>(3, _omitFieldNames ? '' : 'requestedBackend',
        enumValues: $3.InferenceFramework.values)
    ..aE<$3.InferenceFramework>(4, _omitFieldNames ? '' : 'actualBackend',
        enumValues: $3.InferenceFramework.values)
    ..aOM<DevicePlacement>(5, _omitFieldNames ? '' : 'actualDevice',
        subBuilder: DevicePlacement.create)
    ..aOS(6, _omitFieldNames ? '' : 'runtimeVersion')
    ..aOS(7, _omitFieldNames ? '' : 'abiVersion')
    ..aOS(8, _omitFieldNames ? '' : 'fallbackReason')
    ..aOS(9, _omitFieldNames ? '' : 'resolvedPath')
    ..aInt64(10, _omitFieldNames ? '' : 'loadedAtUnixMs')
    ..aOB(11, _omitFieldNames ? '' : 'alreadyLoaded')
    ..pPS(12, _omitFieldNames ? '' : 'warnings')
    ..aOM<$0.SDKError>(13, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoadedModelInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoadedModelInfo copyWith(void Function(LoadedModelInfo) updates) =>
      super.copyWith((message) => updates(message as LoadedModelInfo))
          as LoadedModelInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoadedModelInfo create() => LoadedModelInfo._();
  @$core.override
  LoadedModelInfo createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoadedModelInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoadedModelInfo>(create);
  static LoadedModelInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  @$pb.TagNumber(2)
  $3.ModelCategory get category => $_getN(1);
  @$pb.TagNumber(2)
  set category($3.ModelCategory value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasCategory() => $_has(1);
  @$pb.TagNumber(2)
  void clearCategory() => $_clearField(2);

  @$pb.TagNumber(3)
  $3.InferenceFramework get requestedBackend => $_getN(2);
  @$pb.TagNumber(3)
  set requestedBackend($3.InferenceFramework value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasRequestedBackend() => $_has(2);
  @$pb.TagNumber(3)
  void clearRequestedBackend() => $_clearField(3);

  @$pb.TagNumber(4)
  $3.InferenceFramework get actualBackend => $_getN(3);
  @$pb.TagNumber(4)
  set actualBackend($3.InferenceFramework value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasActualBackend() => $_has(3);
  @$pb.TagNumber(4)
  void clearActualBackend() => $_clearField(4);

  @$pb.TagNumber(5)
  DevicePlacement get actualDevice => $_getN(4);
  @$pb.TagNumber(5)
  set actualDevice(DevicePlacement value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasActualDevice() => $_has(4);
  @$pb.TagNumber(5)
  void clearActualDevice() => $_clearField(5);
  @$pb.TagNumber(5)
  DevicePlacement ensureActualDevice() => $_ensure(4);

  @$pb.TagNumber(6)
  $core.String get runtimeVersion => $_getSZ(5);
  @$pb.TagNumber(6)
  set runtimeVersion($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasRuntimeVersion() => $_has(5);
  @$pb.TagNumber(6)
  void clearRuntimeVersion() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get abiVersion => $_getSZ(6);
  @$pb.TagNumber(7)
  set abiVersion($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasAbiVersion() => $_has(6);
  @$pb.TagNumber(7)
  void clearAbiVersion() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get fallbackReason => $_getSZ(7);
  @$pb.TagNumber(8)
  set fallbackReason($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasFallbackReason() => $_has(7);
  @$pb.TagNumber(8)
  void clearFallbackReason() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get resolvedPath => $_getSZ(8);
  @$pb.TagNumber(9)
  set resolvedPath($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasResolvedPath() => $_has(8);
  @$pb.TagNumber(9)
  void clearResolvedPath() => $_clearField(9);

  @$pb.TagNumber(10)
  $fixnum.Int64 get loadedAtUnixMs => $_getI64(9);
  @$pb.TagNumber(10)
  set loadedAtUnixMs($fixnum.Int64 value) => $_setInt64(9, value);
  @$pb.TagNumber(10)
  $core.bool hasLoadedAtUnixMs() => $_has(9);
  @$pb.TagNumber(10)
  void clearLoadedAtUnixMs() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.bool get alreadyLoaded => $_getBF(10);
  @$pb.TagNumber(11)
  set alreadyLoaded($core.bool value) => $_setBool(10, value);
  @$pb.TagNumber(11)
  $core.bool hasAlreadyLoaded() => $_has(10);
  @$pb.TagNumber(11)
  void clearAlreadyLoaded() => $_clearField(11);

  @$pb.TagNumber(12)
  $pb.PbList<$core.String> get warnings => $_getList(11);

  @$pb.TagNumber(13)
  $0.SDKError get error => $_getN(12);
  @$pb.TagNumber(13)
  set error($0.SDKError value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasError() => $_has(12);
  @$pb.TagNumber(13)
  void clearError() => $_clearField(13);
  @$pb.TagNumber(13)
  $0.SDKError ensureError() => $_ensure(12);
}

class AudioFormatSpec extends $pb.GeneratedMessage {
  factory AudioFormatSpec({
    $3.AudioEncoding? encoding,
    $core.int? sampleRate,
    $core.int? channels,
    $3.AudioFormat? container,
  }) {
    final result = create();
    if (encoding != null) result.encoding = encoding;
    if (sampleRate != null) result.sampleRate = sampleRate;
    if (channels != null) result.channels = channels;
    if (container != null) result.container = container;
    return result;
  }

  AudioFormatSpec._();

  factory AudioFormatSpec.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AudioFormatSpec.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AudioFormatSpec',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<$3.AudioEncoding>(1, _omitFieldNames ? '' : 'encoding',
        enumValues: $3.AudioEncoding.values)
    ..aI(2, _omitFieldNames ? '' : 'sampleRate')
    ..aI(3, _omitFieldNames ? '' : 'channels')
    ..aE<$3.AudioFormat>(4, _omitFieldNames ? '' : 'container',
        enumValues: $3.AudioFormat.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AudioFormatSpec clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AudioFormatSpec copyWith(void Function(AudioFormatSpec) updates) =>
      super.copyWith((message) => updates(message as AudioFormatSpec))
          as AudioFormatSpec;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AudioFormatSpec create() => AudioFormatSpec._();
  @$core.override
  AudioFormatSpec createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AudioFormatSpec getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AudioFormatSpec>(create);
  static AudioFormatSpec? _defaultInstance;

  @$pb.TagNumber(1)
  $3.AudioEncoding get encoding => $_getN(0);
  @$pb.TagNumber(1)
  set encoding($3.AudioEncoding value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasEncoding() => $_has(0);
  @$pb.TagNumber(1)
  void clearEncoding() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get sampleRate => $_getIZ(1);
  @$pb.TagNumber(2)
  set sampleRate($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSampleRate() => $_has(1);
  @$pb.TagNumber(2)
  void clearSampleRate() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get channels => $_getIZ(2);
  @$pb.TagNumber(3)
  set channels($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasChannels() => $_has(2);
  @$pb.TagNumber(3)
  void clearChannels() => $_clearField(3);

  @$pb.TagNumber(4)
  $3.AudioFormat get container => $_getN(3);
  @$pb.TagNumber(4)
  set container($3.AudioFormat value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasContainer() => $_has(3);
  @$pb.TagNumber(4)
  void clearContainer() => $_clearField(4);
}

class AudioFrame extends $pb.GeneratedMessage {
  factory AudioFrame({
    $core.List<$core.int>? samples,
    $core.int? sampleCount,
    $fixnum.Int64? timestampMs,
  }) {
    final result = create();
    if (samples != null) result.samples = samples;
    if (sampleCount != null) result.sampleCount = sampleCount;
    if (timestampMs != null) result.timestampMs = timestampMs;
    return result;
  }

  AudioFrame._();

  factory AudioFrame.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AudioFrame.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AudioFrame',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'samples', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'sampleCount')
    ..aInt64(3, _omitFieldNames ? '' : 'timestampMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AudioFrame clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AudioFrame copyWith(void Function(AudioFrame) updates) =>
      super.copyWith((message) => updates(message as AudioFrame)) as AudioFrame;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AudioFrame create() => AudioFrame._();
  @$core.override
  AudioFrame createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AudioFrame getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AudioFrame>(create);
  static AudioFrame? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get samples => $_getN(0);
  @$pb.TagNumber(1)
  set samples($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSamples() => $_has(0);
  @$pb.TagNumber(1)
  void clearSamples() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get sampleCount => $_getIZ(1);
  @$pb.TagNumber(2)
  set sampleCount($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSampleCount() => $_has(1);
  @$pb.TagNumber(2)
  void clearSampleCount() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get timestampMs => $_getI64(2);
  @$pb.TagNumber(3)
  set timestampMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTimestampMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearTimestampMs() => $_clearField(3);
}

class AudioStreamOpenRequest extends $pb.GeneratedMessage {
  factory AudioStreamOpenRequest({
    $core.String? requestId,
    AudioFormatSpec? format,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (format != null) result.format = format;
    if (metadata != null) result.metadata.addEntries(metadata);
    return result;
  }

  AudioStreamOpenRequest._();

  factory AudioStreamOpenRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AudioStreamOpenRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AudioStreamOpenRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOM<AudioFormatSpec>(2, _omitFieldNames ? '' : 'format',
        subBuilder: AudioFormatSpec.create)
    ..m<$core.String, $core.String>(3, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'AudioStreamOpenRequest.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AudioStreamOpenRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AudioStreamOpenRequest copyWith(
          void Function(AudioStreamOpenRequest) updates) =>
      super.copyWith((message) => updates(message as AudioStreamOpenRequest))
          as AudioStreamOpenRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AudioStreamOpenRequest create() => AudioStreamOpenRequest._();
  @$core.override
  AudioStreamOpenRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AudioStreamOpenRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AudioStreamOpenRequest>(create);
  static AudioStreamOpenRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  AudioFormatSpec get format => $_getN(1);
  @$pb.TagNumber(2)
  set format(AudioFormatSpec value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasFormat() => $_has(1);
  @$pb.TagNumber(2)
  void clearFormat() => $_clearField(2);
  @$pb.TagNumber(2)
  AudioFormatSpec ensureFormat() => $_ensure(1);

  @$pb.TagNumber(3)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(2);
}

class SpeechHandleState extends $pb.GeneratedMessage {
  factory SpeechHandleState({
    $core.String? id,
    $core.bool? interrupted,
    $core.bool? done,
    $0.SDKError? error,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (interrupted != null) result.interrupted = interrupted;
    if (done != null) result.done = done;
    if (error != null) result.error = error;
    return result;
  }

  SpeechHandleState._();

  factory SpeechHandleState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SpeechHandleState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SpeechHandleState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOB(2, _omitFieldNames ? '' : 'interrupted')
    ..aOB(3, _omitFieldNames ? '' : 'done')
    ..aOM<$0.SDKError>(4, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SpeechHandleState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SpeechHandleState copyWith(void Function(SpeechHandleState) updates) =>
      super.copyWith((message) => updates(message as SpeechHandleState))
          as SpeechHandleState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SpeechHandleState create() => SpeechHandleState._();
  @$core.override
  SpeechHandleState createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SpeechHandleState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SpeechHandleState>(create);
  static SpeechHandleState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get interrupted => $_getBF(1);
  @$pb.TagNumber(2)
  set interrupted($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasInterrupted() => $_has(1);
  @$pb.TagNumber(2)
  void clearInterrupted() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get done => $_getBF(2);
  @$pb.TagNumber(3)
  set done($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDone() => $_has(2);
  @$pb.TagNumber(3)
  void clearDone() => $_clearField(3);

  @$pb.TagNumber(4)
  $0.SDKError get error => $_getN(3);
  @$pb.TagNumber(4)
  set error($0.SDKError value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasError() => $_has(3);
  @$pb.TagNumber(4)
  void clearError() => $_clearField(4);
  @$pb.TagNumber(4)
  $0.SDKError ensureError() => $_ensure(3);
}

class UnavailableCapability extends $pb.GeneratedMessage {
  factory UnavailableCapability({
    $core.String? name,
    $core.String? reason,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (reason != null) result.reason = reason;
    return result;
  }

  UnavailableCapability._();

  factory UnavailableCapability.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UnavailableCapability.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UnavailableCapability',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'reason')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UnavailableCapability clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UnavailableCapability copyWith(
          void Function(UnavailableCapability) updates) =>
      super.copyWith((message) => updates(message as UnavailableCapability))
          as UnavailableCapability;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UnavailableCapability create() => UnavailableCapability._();
  @$core.override
  UnavailableCapability createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UnavailableCapability getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UnavailableCapability>(create);
  static UnavailableCapability? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get reason => $_getSZ(1);
  @$pb.TagNumber(2)
  set reason($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReason() => $_has(1);
  @$pb.TagNumber(2)
  void clearReason() => $_clearField(2);
}

class ToolCapabilities extends $pb.GeneratedMessage {
  factory ToolCapabilities({
    $core.bool? registry,
    $core.bool? parallel,
    $core.bool? cancellation,
  }) {
    final result = create();
    if (registry != null) result.registry = registry;
    if (parallel != null) result.parallel = parallel;
    if (cancellation != null) result.cancellation = cancellation;
    return result;
  }

  ToolCapabilities._();

  factory ToolCapabilities.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolCapabilities.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolCapabilities',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'registry')
    ..aOB(2, _omitFieldNames ? '' : 'parallel')
    ..aOB(3, _omitFieldNames ? '' : 'cancellation')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCapabilities clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCapabilities copyWith(void Function(ToolCapabilities) updates) =>
      super.copyWith((message) => updates(message as ToolCapabilities))
          as ToolCapabilities;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCapabilities create() => ToolCapabilities._();
  @$core.override
  ToolCapabilities createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolCapabilities getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToolCapabilities>(create);
  static ToolCapabilities? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get registry => $_getBF(0);
  @$pb.TagNumber(1)
  set registry($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRegistry() => $_has(0);
  @$pb.TagNumber(1)
  void clearRegistry() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get parallel => $_getBF(1);
  @$pb.TagNumber(2)
  set parallel($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasParallel() => $_has(1);
  @$pb.TagNumber(2)
  void clearParallel() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get cancellation => $_getBF(2);
  @$pb.TagNumber(3)
  set cancellation($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCancellation() => $_has(2);
  @$pb.TagNumber(3)
  void clearCancellation() => $_clearField(3);
}

class RagCapabilities extends $pb.GeneratedMessage {
  factory RagCapabilities({
    $core.bool? multiSession,
    $core.bool? persistent,
    $core.bool? documentListing,
    $core.bool? documentRemoval,
  }) {
    final result = create();
    if (multiSession != null) result.multiSession = multiSession;
    if (persistent != null) result.persistent = persistent;
    if (documentListing != null) result.documentListing = documentListing;
    if (documentRemoval != null) result.documentRemoval = documentRemoval;
    return result;
  }

  RagCapabilities._();

  factory RagCapabilities.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RagCapabilities.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RagCapabilities',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'multiSession')
    ..aOB(2, _omitFieldNames ? '' : 'persistent')
    ..aOB(3, _omitFieldNames ? '' : 'documentListing')
    ..aOB(4, _omitFieldNames ? '' : 'documentRemoval')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RagCapabilities clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RagCapabilities copyWith(void Function(RagCapabilities) updates) =>
      super.copyWith((message) => updates(message as RagCapabilities))
          as RagCapabilities;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RagCapabilities create() => RagCapabilities._();
  @$core.override
  RagCapabilities createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RagCapabilities getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RagCapabilities>(create);
  static RagCapabilities? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get multiSession => $_getBF(0);
  @$pb.TagNumber(1)
  set multiSession($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMultiSession() => $_has(0);
  @$pb.TagNumber(1)
  void clearMultiSession() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get persistent => $_getBF(1);
  @$pb.TagNumber(2)
  set persistent($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPersistent() => $_has(1);
  @$pb.TagNumber(2)
  void clearPersistent() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get documentListing => $_getBF(2);
  @$pb.TagNumber(3)
  set documentListing($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDocumentListing() => $_has(2);
  @$pb.TagNumber(3)
  void clearDocumentListing() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get documentRemoval => $_getBF(3);
  @$pb.TagNumber(4)
  set documentRemoval($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDocumentRemoval() => $_has(3);
  @$pb.TagNumber(4)
  void clearDocumentRemoval() => $_clearField(4);
}

class StreamingCapabilities extends $pb.GeneratedMessage {
  factory StreamingCapabilities({
    $core.bool? llmTokenStream,
    $core.bool? sttLiveFrames,
    $core.bool? ttsAudioChunks,
    $core.bool? vadLiveFrames,
    $core.bool? voiceSession,
  }) {
    final result = create();
    if (llmTokenStream != null) result.llmTokenStream = llmTokenStream;
    if (sttLiveFrames != null) result.sttLiveFrames = sttLiveFrames;
    if (ttsAudioChunks != null) result.ttsAudioChunks = ttsAudioChunks;
    if (vadLiveFrames != null) result.vadLiveFrames = vadLiveFrames;
    if (voiceSession != null) result.voiceSession = voiceSession;
    return result;
  }

  StreamingCapabilities._();

  factory StreamingCapabilities.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StreamingCapabilities.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StreamingCapabilities',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'llmTokenStream')
    ..aOB(2, _omitFieldNames ? '' : 'sttLiveFrames')
    ..aOB(3, _omitFieldNames ? '' : 'ttsAudioChunks')
    ..aOB(4, _omitFieldNames ? '' : 'vadLiveFrames')
    ..aOB(5, _omitFieldNames ? '' : 'voiceSession')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StreamingCapabilities clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StreamingCapabilities copyWith(
          void Function(StreamingCapabilities) updates) =>
      super.copyWith((message) => updates(message as StreamingCapabilities))
          as StreamingCapabilities;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StreamingCapabilities create() => StreamingCapabilities._();
  @$core.override
  StreamingCapabilities createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StreamingCapabilities getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StreamingCapabilities>(create);
  static StreamingCapabilities? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get llmTokenStream => $_getBF(0);
  @$pb.TagNumber(1)
  set llmTokenStream($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLlmTokenStream() => $_has(0);
  @$pb.TagNumber(1)
  void clearLlmTokenStream() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get sttLiveFrames => $_getBF(1);
  @$pb.TagNumber(2)
  set sttLiveFrames($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSttLiveFrames() => $_has(1);
  @$pb.TagNumber(2)
  void clearSttLiveFrames() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get ttsAudioChunks => $_getBF(2);
  @$pb.TagNumber(3)
  set ttsAudioChunks($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTtsAudioChunks() => $_has(2);
  @$pb.TagNumber(3)
  void clearTtsAudioChunks() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get vadLiveFrames => $_getBF(3);
  @$pb.TagNumber(4)
  set vadLiveFrames($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasVadLiveFrames() => $_has(3);
  @$pb.TagNumber(4)
  void clearVadLiveFrames() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get voiceSession => $_getBF(4);
  @$pb.TagNumber(5)
  set voiceSession($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasVoiceSession() => $_has(4);
  @$pb.TagNumber(5)
  void clearVoiceSession() => $_clearField(5);
}

class SDKCapabilities extends $pb.GeneratedMessage {
  factory SDKCapabilities({
    $core.Iterable<$core.String>? modalities,
    $core.Iterable<$3.InferenceFramework>? backends,
    $core.Iterable<$3.AudioFormat>? audioFormats,
    StreamingCapabilities? streaming,
    ToolCapabilities? tools,
    RagCapabilities? rag,
    $core.Iterable<UnavailableCapability>? unavailable,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
  }) {
    final result = create();
    if (modalities != null) result.modalities.addAll(modalities);
    if (backends != null) result.backends.addAll(backends);
    if (audioFormats != null) result.audioFormats.addAll(audioFormats);
    if (streaming != null) result.streaming = streaming;
    if (tools != null) result.tools = tools;
    if (rag != null) result.rag = rag;
    if (unavailable != null) result.unavailable.addAll(unavailable);
    if (metadata != null) result.metadata.addEntries(metadata);
    return result;
  }

  SDKCapabilities._();

  factory SDKCapabilities.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SDKCapabilities.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SDKCapabilities',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'modalities')
    ..pc<$3.InferenceFramework>(
        2, _omitFieldNames ? '' : 'backends', $pb.PbFieldType.KE,
        valueOf: $3.InferenceFramework.valueOf,
        enumValues: $3.InferenceFramework.values,
        defaultEnumValue: $3.InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED)
    ..pc<$3.AudioFormat>(
        3, _omitFieldNames ? '' : 'audioFormats', $pb.PbFieldType.KE,
        valueOf: $3.AudioFormat.valueOf,
        enumValues: $3.AudioFormat.values,
        defaultEnumValue: $3.AudioFormat.AUDIO_FORMAT_UNSPECIFIED)
    ..aOM<StreamingCapabilities>(4, _omitFieldNames ? '' : 'streaming',
        subBuilder: StreamingCapabilities.create)
    ..aOM<ToolCapabilities>(5, _omitFieldNames ? '' : 'tools',
        subBuilder: ToolCapabilities.create)
    ..aOM<RagCapabilities>(6, _omitFieldNames ? '' : 'rag',
        subBuilder: RagCapabilities.create)
    ..pPM<UnavailableCapability>(7, _omitFieldNames ? '' : 'unavailable',
        subBuilder: UnavailableCapability.create)
    ..m<$core.String, $core.String>(8, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'SDKCapabilities.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SDKCapabilities clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SDKCapabilities copyWith(void Function(SDKCapabilities) updates) =>
      super.copyWith((message) => updates(message as SDKCapabilities))
          as SDKCapabilities;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SDKCapabilities create() => SDKCapabilities._();
  @$core.override
  SDKCapabilities createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SDKCapabilities getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SDKCapabilities>(create);
  static SDKCapabilities? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get modalities => $_getList(0);

  @$pb.TagNumber(2)
  $pb.PbList<$3.InferenceFramework> get backends => $_getList(1);

  @$pb.TagNumber(3)
  $pb.PbList<$3.AudioFormat> get audioFormats => $_getList(2);

  @$pb.TagNumber(4)
  StreamingCapabilities get streaming => $_getN(3);
  @$pb.TagNumber(4)
  set streaming(StreamingCapabilities value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasStreaming() => $_has(3);
  @$pb.TagNumber(4)
  void clearStreaming() => $_clearField(4);
  @$pb.TagNumber(4)
  StreamingCapabilities ensureStreaming() => $_ensure(3);

  @$pb.TagNumber(5)
  ToolCapabilities get tools => $_getN(4);
  @$pb.TagNumber(5)
  set tools(ToolCapabilities value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasTools() => $_has(4);
  @$pb.TagNumber(5)
  void clearTools() => $_clearField(5);
  @$pb.TagNumber(5)
  ToolCapabilities ensureTools() => $_ensure(4);

  @$pb.TagNumber(6)
  RagCapabilities get rag => $_getN(5);
  @$pb.TagNumber(6)
  set rag(RagCapabilities value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasRag() => $_has(5);
  @$pb.TagNumber(6)
  void clearRag() => $_clearField(6);
  @$pb.TagNumber(6)
  RagCapabilities ensureRag() => $_ensure(5);

  @$pb.TagNumber(7)
  $pb.PbList<UnavailableCapability> get unavailable => $_getList(6);

  @$pb.TagNumber(8)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(7);
}

class PublicGenerationEvent extends $pb.GeneratedMessage {
  factory PublicGenerationEvent({
    PublicGenerationEventKind? kind,
    $core.String? requestId,
    $fixnum.Int64? sequence,
    $core.String? itemId,
    $core.int? index,
    $core.String? text,
    $1.ToolCall? toolCall,
    $core.String? argumentsJson,
    $core.String? argumentsDelta,
    $2.TokenUsage? usage,
    $core.String? partialText,
    $core.String? resultJson,
    $0.SDKError? error,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (requestId != null) result.requestId = requestId;
    if (sequence != null) result.sequence = sequence;
    if (itemId != null) result.itemId = itemId;
    if (index != null) result.index = index;
    if (text != null) result.text = text;
    if (toolCall != null) result.toolCall = toolCall;
    if (argumentsJson != null) result.argumentsJson = argumentsJson;
    if (argumentsDelta != null) result.argumentsDelta = argumentsDelta;
    if (usage != null) result.usage = usage;
    if (partialText != null) result.partialText = partialText;
    if (resultJson != null) result.resultJson = resultJson;
    if (error != null) result.error = error;
    return result;
  }

  PublicGenerationEvent._();

  factory PublicGenerationEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PublicGenerationEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PublicGenerationEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<PublicGenerationEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: PublicGenerationEventKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'requestId')
    ..aInt64(3, _omitFieldNames ? '' : 'sequence')
    ..aOS(4, _omitFieldNames ? '' : 'itemId')
    ..aI(5, _omitFieldNames ? '' : 'index')
    ..aOS(6, _omitFieldNames ? '' : 'text')
    ..aOM<$1.ToolCall>(7, _omitFieldNames ? '' : 'toolCall',
        subBuilder: $1.ToolCall.create)
    ..aOS(8, _omitFieldNames ? '' : 'argumentsJson')
    ..aOS(9, _omitFieldNames ? '' : 'argumentsDelta')
    ..aOM<$2.TokenUsage>(10, _omitFieldNames ? '' : 'usage',
        subBuilder: $2.TokenUsage.create)
    ..aOS(11, _omitFieldNames ? '' : 'partialText')
    ..aOS(12, _omitFieldNames ? '' : 'resultJson')
    ..aOM<$0.SDKError>(13, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PublicGenerationEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PublicGenerationEvent copyWith(
          void Function(PublicGenerationEvent) updates) =>
      super.copyWith((message) => updates(message as PublicGenerationEvent))
          as PublicGenerationEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PublicGenerationEvent create() => PublicGenerationEvent._();
  @$core.override
  PublicGenerationEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PublicGenerationEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PublicGenerationEvent>(create);
  static PublicGenerationEvent? _defaultInstance;

  @$pb.TagNumber(1)
  PublicGenerationEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(PublicGenerationEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get requestId => $_getSZ(1);
  @$pb.TagNumber(2)
  set requestId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRequestId() => $_has(1);
  @$pb.TagNumber(2)
  void clearRequestId() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get sequence => $_getI64(2);
  @$pb.TagNumber(3)
  set sequence($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSequence() => $_has(2);
  @$pb.TagNumber(3)
  void clearSequence() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get itemId => $_getSZ(3);
  @$pb.TagNumber(4)
  set itemId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasItemId() => $_has(3);
  @$pb.TagNumber(4)
  void clearItemId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get index => $_getIZ(4);
  @$pb.TagNumber(5)
  set index($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasIndex() => $_has(4);
  @$pb.TagNumber(5)
  void clearIndex() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get text => $_getSZ(5);
  @$pb.TagNumber(6)
  set text($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasText() => $_has(5);
  @$pb.TagNumber(6)
  void clearText() => $_clearField(6);

  @$pb.TagNumber(7)
  $1.ToolCall get toolCall => $_getN(6);
  @$pb.TagNumber(7)
  set toolCall($1.ToolCall value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasToolCall() => $_has(6);
  @$pb.TagNumber(7)
  void clearToolCall() => $_clearField(7);
  @$pb.TagNumber(7)
  $1.ToolCall ensureToolCall() => $_ensure(6);

  @$pb.TagNumber(8)
  $core.String get argumentsJson => $_getSZ(7);
  @$pb.TagNumber(8)
  set argumentsJson($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasArgumentsJson() => $_has(7);
  @$pb.TagNumber(8)
  void clearArgumentsJson() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get argumentsDelta => $_getSZ(8);
  @$pb.TagNumber(9)
  set argumentsDelta($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasArgumentsDelta() => $_has(8);
  @$pb.TagNumber(9)
  void clearArgumentsDelta() => $_clearField(9);

  @$pb.TagNumber(10)
  $2.TokenUsage get usage => $_getN(9);
  @$pb.TagNumber(10)
  set usage($2.TokenUsage value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasUsage() => $_has(9);
  @$pb.TagNumber(10)
  void clearUsage() => $_clearField(10);
  @$pb.TagNumber(10)
  $2.TokenUsage ensureUsage() => $_ensure(9);

  @$pb.TagNumber(11)
  $core.String get partialText => $_getSZ(10);
  @$pb.TagNumber(11)
  set partialText($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasPartialText() => $_has(10);
  @$pb.TagNumber(11)
  void clearPartialText() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get resultJson => $_getSZ(11);
  @$pb.TagNumber(12)
  set resultJson($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasResultJson() => $_has(11);
  @$pb.TagNumber(12)
  void clearResultJson() => $_clearField(12);

  @$pb.TagNumber(13)
  $0.SDKError get error => $_getN(12);
  @$pb.TagNumber(13)
  set error($0.SDKError value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasError() => $_has(12);
  @$pb.TagNumber(13)
  void clearError() => $_clearField(13);
  @$pb.TagNumber(13)
  $0.SDKError ensureError() => $_ensure(12);
}

class PublicDownloadEvent extends $pb.GeneratedMessage {
  factory PublicDownloadEvent({
    PublicDownloadEventKind? kind,
    $core.String? operationId,
    $fixnum.Int64? sequence,
    $fixnum.Int64? bytesDone,
    $fixnum.Int64? bytesTotal,
    $core.String? file,
    $core.double? percent,
    $core.String? modelId,
    $0.SDKError? error,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (operationId != null) result.operationId = operationId;
    if (sequence != null) result.sequence = sequence;
    if (bytesDone != null) result.bytesDone = bytesDone;
    if (bytesTotal != null) result.bytesTotal = bytesTotal;
    if (file != null) result.file = file;
    if (percent != null) result.percent = percent;
    if (modelId != null) result.modelId = modelId;
    if (error != null) result.error = error;
    return result;
  }

  PublicDownloadEvent._();

  factory PublicDownloadEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PublicDownloadEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PublicDownloadEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<PublicDownloadEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: PublicDownloadEventKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'operationId')
    ..aInt64(3, _omitFieldNames ? '' : 'sequence')
    ..aInt64(4, _omitFieldNames ? '' : 'bytesDone')
    ..aInt64(5, _omitFieldNames ? '' : 'bytesTotal')
    ..aOS(6, _omitFieldNames ? '' : 'file')
    ..aD(7, _omitFieldNames ? '' : 'percent', fieldType: $pb.PbFieldType.OF)
    ..aOS(8, _omitFieldNames ? '' : 'modelId')
    ..aOM<$0.SDKError>(9, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PublicDownloadEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PublicDownloadEvent copyWith(void Function(PublicDownloadEvent) updates) =>
      super.copyWith((message) => updates(message as PublicDownloadEvent))
          as PublicDownloadEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PublicDownloadEvent create() => PublicDownloadEvent._();
  @$core.override
  PublicDownloadEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PublicDownloadEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PublicDownloadEvent>(create);
  static PublicDownloadEvent? _defaultInstance;

  @$pb.TagNumber(1)
  PublicDownloadEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(PublicDownloadEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get operationId => $_getSZ(1);
  @$pb.TagNumber(2)
  set operationId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOperationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearOperationId() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get sequence => $_getI64(2);
  @$pb.TagNumber(3)
  set sequence($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSequence() => $_has(2);
  @$pb.TagNumber(3)
  void clearSequence() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get bytesDone => $_getI64(3);
  @$pb.TagNumber(4)
  set bytesDone($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBytesDone() => $_has(3);
  @$pb.TagNumber(4)
  void clearBytesDone() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get bytesTotal => $_getI64(4);
  @$pb.TagNumber(5)
  set bytesTotal($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasBytesTotal() => $_has(4);
  @$pb.TagNumber(5)
  void clearBytesTotal() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get file => $_getSZ(5);
  @$pb.TagNumber(6)
  set file($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasFile() => $_has(5);
  @$pb.TagNumber(6)
  void clearFile() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.double get percent => $_getN(6);
  @$pb.TagNumber(7)
  set percent($core.double value) => $_setFloat(6, value);
  @$pb.TagNumber(7)
  $core.bool hasPercent() => $_has(6);
  @$pb.TagNumber(7)
  void clearPercent() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get modelId => $_getSZ(7);
  @$pb.TagNumber(8)
  set modelId($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasModelId() => $_has(7);
  @$pb.TagNumber(8)
  void clearModelId() => $_clearField(8);

  @$pb.TagNumber(9)
  $0.SDKError get error => $_getN(8);
  @$pb.TagNumber(9)
  set error($0.SDKError value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasError() => $_has(8);
  @$pb.TagNumber(9)
  void clearError() => $_clearField(9);
  @$pb.TagNumber(9)
  $0.SDKError ensureError() => $_ensure(8);
}

class TranscriptAlternative extends $pb.GeneratedMessage {
  factory TranscriptAlternative({
    $core.String? text,
    $core.double? confidence,
  }) {
    final result = create();
    if (text != null) result.text = text;
    if (confidence != null) result.confidence = confidence;
    return result;
  }

  TranscriptAlternative._();

  factory TranscriptAlternative.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TranscriptAlternative.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TranscriptAlternative',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aD(2, _omitFieldNames ? '' : 'confidence', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TranscriptAlternative clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TranscriptAlternative copyWith(
          void Function(TranscriptAlternative) updates) =>
      super.copyWith((message) => updates(message as TranscriptAlternative))
          as TranscriptAlternative;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TranscriptAlternative create() => TranscriptAlternative._();
  @$core.override
  TranscriptAlternative createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TranscriptAlternative getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TranscriptAlternative>(create);
  static TranscriptAlternative? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get confidence => $_getN(1);
  @$pb.TagNumber(2)
  set confidence($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasConfidence() => $_has(1);
  @$pb.TagNumber(2)
  void clearConfidence() => $_clearField(2);
}

class PublicTranscriptionEvent extends $pb.GeneratedMessage {
  factory PublicTranscriptionEvent({
    PublicTranscriptionEventKind? kind,
    $core.String? requestId,
    $fixnum.Int64? sequence,
    $core.String? segmentId,
    $core.int? revision,
    $core.Iterable<TranscriptAlternative>? alternatives,
    $core.String? finalText,
    $fixnum.Int64? timestampMs,
    $2.TokenUsage? usage,
    $0.SDKError? error,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (requestId != null) result.requestId = requestId;
    if (sequence != null) result.sequence = sequence;
    if (segmentId != null) result.segmentId = segmentId;
    if (revision != null) result.revision = revision;
    if (alternatives != null) result.alternatives.addAll(alternatives);
    if (finalText != null) result.finalText = finalText;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (usage != null) result.usage = usage;
    if (error != null) result.error = error;
    return result;
  }

  PublicTranscriptionEvent._();

  factory PublicTranscriptionEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PublicTranscriptionEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PublicTranscriptionEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<PublicTranscriptionEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: PublicTranscriptionEventKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'requestId')
    ..aInt64(3, _omitFieldNames ? '' : 'sequence')
    ..aOS(4, _omitFieldNames ? '' : 'segmentId')
    ..aI(5, _omitFieldNames ? '' : 'revision')
    ..pPM<TranscriptAlternative>(6, _omitFieldNames ? '' : 'alternatives',
        subBuilder: TranscriptAlternative.create)
    ..aOS(7, _omitFieldNames ? '' : 'finalText')
    ..aInt64(8, _omitFieldNames ? '' : 'timestampMs')
    ..aOM<$2.TokenUsage>(9, _omitFieldNames ? '' : 'usage',
        subBuilder: $2.TokenUsage.create)
    ..aOM<$0.SDKError>(10, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PublicTranscriptionEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PublicTranscriptionEvent copyWith(
          void Function(PublicTranscriptionEvent) updates) =>
      super.copyWith((message) => updates(message as PublicTranscriptionEvent))
          as PublicTranscriptionEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PublicTranscriptionEvent create() => PublicTranscriptionEvent._();
  @$core.override
  PublicTranscriptionEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PublicTranscriptionEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PublicTranscriptionEvent>(create);
  static PublicTranscriptionEvent? _defaultInstance;

  @$pb.TagNumber(1)
  PublicTranscriptionEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(PublicTranscriptionEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get requestId => $_getSZ(1);
  @$pb.TagNumber(2)
  set requestId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRequestId() => $_has(1);
  @$pb.TagNumber(2)
  void clearRequestId() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get sequence => $_getI64(2);
  @$pb.TagNumber(3)
  set sequence($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSequence() => $_has(2);
  @$pb.TagNumber(3)
  void clearSequence() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get segmentId => $_getSZ(3);
  @$pb.TagNumber(4)
  set segmentId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSegmentId() => $_has(3);
  @$pb.TagNumber(4)
  void clearSegmentId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get revision => $_getIZ(4);
  @$pb.TagNumber(5)
  set revision($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRevision() => $_has(4);
  @$pb.TagNumber(5)
  void clearRevision() => $_clearField(5);

  @$pb.TagNumber(6)
  $pb.PbList<TranscriptAlternative> get alternatives => $_getList(5);

  @$pb.TagNumber(7)
  $core.String get finalText => $_getSZ(6);
  @$pb.TagNumber(7)
  set finalText($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasFinalText() => $_has(6);
  @$pb.TagNumber(7)
  void clearFinalText() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get timestampMs => $_getI64(7);
  @$pb.TagNumber(8)
  set timestampMs($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasTimestampMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearTimestampMs() => $_clearField(8);

  @$pb.TagNumber(9)
  $2.TokenUsage get usage => $_getN(8);
  @$pb.TagNumber(9)
  set usage($2.TokenUsage value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasUsage() => $_has(8);
  @$pb.TagNumber(9)
  void clearUsage() => $_clearField(9);
  @$pb.TagNumber(9)
  $2.TokenUsage ensureUsage() => $_ensure(8);

  @$pb.TagNumber(10)
  $0.SDKError get error => $_getN(9);
  @$pb.TagNumber(10)
  set error($0.SDKError value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasError() => $_has(9);
  @$pb.TagNumber(10)
  void clearError() => $_clearField(10);
  @$pb.TagNumber(10)
  $0.SDKError ensureError() => $_ensure(9);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
