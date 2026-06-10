// This is a generated file - do not edit.
//
// Generated from vad_options.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'model_types.pbenum.dart' as $0;
import 'vad_options.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'vad_options.pbenum.dart';

/// ---------------------------------------------------------------------------
/// Compile-time / load-time configuration for a VAD instance.
/// Sources pre-IDL:
///   Swift  VADTypes.swift:15                (energyThreshold, sampleRate, frameLength,
///                                            enableAutoCalibration, calibrationMultiplier)
///   Kotlin VADTypes.kt:26                   (same five fields, defaults match Swift)
///   Dart   vad_configuration.dart:5         (same five fields)
///   RN     VADTypes.ts:12                   (sampleRate, frameLength, energyThreshold;
///                                            no calibration fields)
///   Web    VADTypes.ts —                    (no VADConfiguration; per-backend in WebSDK)
///   C ABI  rac_vad_types.h:63 (rac_vad_config_t)
///                                           (model_id, preferred_framework, energy_threshold,
///                                            sample_rate, frame_length, enable_auto_calibration,
///                                            calibration_multiplier)
///
/// `frame_length_ms` is the canonical wire field — Swift/Kotlin/Dart/C use
/// seconds (float), but ms is more interoperable across protobuf consumers.
/// Generators must convert when binding to per-platform types.
/// ---------------------------------------------------------------------------
class VADConfiguration extends $pb.GeneratedMessage {
  factory VADConfiguration({
    $core.String? modelId,
    $core.int? sampleRate,
    $core.int? frameLengthMs,
    $core.double? threshold,
    $core.bool? enableAutoCalibration,
    $core.double? calibrationMultiplier,
    $0.InferenceFramework? preferredFramework,
    $core.String? modelPath,
    $core.int? windowSizeSamples,
    $core.int? maxSpeechDurationMs,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (sampleRate != null) result.sampleRate = sampleRate;
    if (frameLengthMs != null) result.frameLengthMs = frameLengthMs;
    if (threshold != null) result.threshold = threshold;
    if (enableAutoCalibration != null)
      result.enableAutoCalibration = enableAutoCalibration;
    if (calibrationMultiplier != null)
      result.calibrationMultiplier = calibrationMultiplier;
    if (preferredFramework != null)
      result.preferredFramework = preferredFramework;
    if (modelPath != null) result.modelPath = modelPath;
    if (windowSizeSamples != null) result.windowSizeSamples = windowSizeSamples;
    if (maxSpeechDurationMs != null)
      result.maxSpeechDurationMs = maxSpeechDurationMs;
    return result;
  }

  VADConfiguration._();

  factory VADConfiguration.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VADConfiguration.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VADConfiguration',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aI(2, _omitFieldNames ? '' : 'sampleRate')
    ..aI(3, _omitFieldNames ? '' : 'frameLengthMs')
    ..aD(4, _omitFieldNames ? '' : 'threshold', fieldType: $pb.PbFieldType.OF)
    ..aOB(5, _omitFieldNames ? '' : 'enableAutoCalibration')
    ..aD(6, _omitFieldNames ? '' : 'calibrationMultiplier',
        fieldType: $pb.PbFieldType.OF)
    ..aE<$0.InferenceFramework>(7, _omitFieldNames ? '' : 'preferredFramework',
        enumValues: $0.InferenceFramework.values)
    ..aOS(8, _omitFieldNames ? '' : 'modelPath')
    ..aI(9, _omitFieldNames ? '' : 'windowSizeSamples')
    ..aI(10, _omitFieldNames ? '' : 'maxSpeechDurationMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VADConfiguration clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VADConfiguration copyWith(void Function(VADConfiguration) updates) =>
      super.copyWith((message) => updates(message as VADConfiguration))
          as VADConfiguration;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VADConfiguration create() => VADConfiguration._();
  @$core.override
  VADConfiguration createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VADConfiguration getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VADConfiguration>(create);
  static VADConfiguration? _defaultInstance;

  /// Optional model id; empty when using the built-in energy VAD.
  /// C ABI: model_id (rac_vad_config_t::model_id, may be NULL).
  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  /// PCM sample rate in Hz. Default 16000 (RAC_VAD_DEFAULT_SAMPLE_RATE).
  @$pb.TagNumber(2)
  $core.int get sampleRate => $_getIZ(1);
  @$pb.TagNumber(2)
  set sampleRate($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSampleRate() => $_has(1);
  @$pb.TagNumber(2)
  void clearSampleRate() => $_clearField(2);

  /// Frame length in milliseconds. Default 100 (Swift/Kotlin/Dart store
  /// 0.1 seconds; we canonicalize to ms on the wire).
  @$pb.TagNumber(3)
  $core.int get frameLengthMs => $_getIZ(2);
  @$pb.TagNumber(3)
  set frameLengthMs($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFrameLengthMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearFrameLengthMs() => $_clearField(3);

  /// Energy threshold in [0.0, 1.0] for voice detection.
  /// Recommended range 0.01–0.05; default 0.015 across SDKs.
  @$pb.TagNumber(4)
  $core.double get threshold => $_getN(3);
  @$pb.TagNumber(4)
  set threshold($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasThreshold() => $_has(3);
  @$pb.TagNumber(4)
  void clearThreshold() => $_clearField(4);

  /// When true, the VAD performs ambient-noise calibration and uses the
  /// result as a multiplier on the threshold (see calibration_multiplier
  /// in the C ABI). Defaults to false.
  @$pb.TagNumber(5)
  $core.bool get enableAutoCalibration => $_getBF(4);
  @$pb.TagNumber(5)
  set enableAutoCalibration($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasEnableAutoCalibration() => $_has(4);
  @$pb.TagNumber(5)
  void clearEnableAutoCalibration() => $_clearField(5);

  /// Calibration multiplier (threshold = ambient noise * multiplier).
  /// Present in Swift/Kotlin/Dart configs and rac_vad_config_t.
  @$pb.TagNumber(6)
  $core.double get calibrationMultiplier => $_getN(5);
  @$pb.TagNumber(6)
  set calibrationMultiplier($core.double value) => $_setFloat(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCalibrationMultiplier() => $_has(5);
  @$pb.TagNumber(6)
  void clearCalibrationMultiplier() => $_clearField(6);

  /// Preferred framework for VAD. Absent = auto.
  @$pb.TagNumber(7)
  $0.InferenceFramework get preferredFramework => $_getN(6);
  @$pb.TagNumber(7)
  set preferredFramework($0.InferenceFramework value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasPreferredFramework() => $_has(6);
  @$pb.TagNumber(7)
  void clearPreferredFramework() => $_clearField(7);

  /// Optional model path for backend-specific VADs (e.g. Silero ONNX).
  @$pb.TagNumber(8)
  $core.String get modelPath => $_getSZ(7);
  @$pb.TagNumber(8)
  set modelPath($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasModelPath() => $_has(7);
  @$pb.TagNumber(8)
  void clearModelPath() => $_clearField(8);

  /// Window size in samples for frame-based neural VAD backends. 0 =
  /// backend/default.
  @$pb.TagNumber(9)
  $core.int get windowSizeSamples => $_getIZ(8);
  @$pb.TagNumber(9)
  set windowSizeSamples($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasWindowSizeSamples() => $_has(8);
  @$pb.TagNumber(9)
  void clearWindowSizeSamples() => $_clearField(9);

  /// Maximum continuous speech segment duration in milliseconds. 0 =
  /// backend/default.
  @$pb.TagNumber(10)
  $core.int get maxSpeechDurationMs => $_getIZ(9);
  @$pb.TagNumber(10)
  set maxSpeechDurationMs($core.int value) => $_setSignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasMaxSpeechDurationMs() => $_has(9);
  @$pb.TagNumber(10)
  void clearMaxSpeechDurationMs() => $_clearField(10);
}

/// ---------------------------------------------------------------------------
/// Runtime / per-call options applied to a VAD pass.
/// Sources pre-IDL:
///   Swift  none — Swift uses raw arguments to detectSpeech().
///   Kotlin none — same as Swift.
///   Dart   runanywhere_vad.dart:99          (`detectSpeech` takes raw Float32List)
///   RN     VADTypes.ts —                    (no per-call options struct)
///   Web    VADTypes.ts —                    (no per-call options struct)
///   C ABI  rac_vad_types.h:123 (rac_vad_input_t)
///                                           (audio_samples, num_samples,
///                                            energy_threshold_override)
///
/// We canonicalize on the energy_threshold_override + the speech-duration
/// gates that already appear as constants in rac_vad_types.h:50-51:
///   RAC_VAD_MIN_SPEECH_DURATION_MS  = 100
///   RAC_VAD_MIN_SILENCE_DURATION_MS = 300
/// Surfacing them as fields lets callers tune debouncing without a rebuild.
/// ---------------------------------------------------------------------------
class VADOptions extends $pb.GeneratedMessage {
  factory VADOptions({
    $core.double? threshold,
    $core.int? minSpeechDurationMs,
    $core.int? minSilenceDurationMs,
    $core.int? maxSpeechDurationMs,
    $core.bool? includeStatistics,
  }) {
    final result = create();
    if (threshold != null) result.threshold = threshold;
    if (minSpeechDurationMs != null)
      result.minSpeechDurationMs = minSpeechDurationMs;
    if (minSilenceDurationMs != null)
      result.minSilenceDurationMs = minSilenceDurationMs;
    if (maxSpeechDurationMs != null)
      result.maxSpeechDurationMs = maxSpeechDurationMs;
    if (includeStatistics != null) result.includeStatistics = includeStatistics;
    return result;
  }

  VADOptions._();

  factory VADOptions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VADOptions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VADOptions',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'threshold', fieldType: $pb.PbFieldType.OF)
    ..aI(2, _omitFieldNames ? '' : 'minSpeechDurationMs')
    ..aI(3, _omitFieldNames ? '' : 'minSilenceDurationMs')
    ..aI(4, _omitFieldNames ? '' : 'maxSpeechDurationMs')
    ..aOB(5, _omitFieldNames ? '' : 'includeStatistics')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VADOptions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VADOptions copyWith(void Function(VADOptions) updates) =>
      super.copyWith((message) => updates(message as VADOptions)) as VADOptions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VADOptions create() => VADOptions._();
  @$core.override
  VADOptions createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VADOptions getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VADOptions>(create);
  static VADOptions? _defaultInstance;

  /// Per-call energy threshold override. Use 0 (default) to keep the
  /// configured threshold. Mirrors rac_vad_input_t::energy_threshold_override
  /// (which uses -1 as the sentinel; on the wire we use 0 for proto3
  /// default semantics — generators emit -1 when this is unset).
  @$pb.TagNumber(1)
  $core.double get threshold => $_getN(0);
  @$pb.TagNumber(1)
  set threshold($core.double value) => $_setFloat(0, value);
  @$pb.TagNumber(1)
  $core.bool hasThreshold() => $_has(0);
  @$pb.TagNumber(1)
  void clearThreshold() => $_clearField(1);

  /// Minimum continuous speech duration (ms) before SPEECH_STARTED fires.
  /// Default 100 (RAC_VAD_MIN_SPEECH_DURATION_MS).
  @$pb.TagNumber(2)
  $core.int get minSpeechDurationMs => $_getIZ(1);
  @$pb.TagNumber(2)
  set minSpeechDurationMs($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMinSpeechDurationMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearMinSpeechDurationMs() => $_clearField(2);

  /// Minimum continuous silence duration (ms) before SPEECH_ENDED fires.
  /// Default 300 (RAC_VAD_MIN_SILENCE_DURATION_MS).
  @$pb.TagNumber(3)
  $core.int get minSilenceDurationMs => $_getIZ(2);
  @$pb.TagNumber(3)
  set minSilenceDurationMs($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMinSilenceDurationMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearMinSilenceDurationMs() => $_clearField(3);

  /// Maximum continuous speech duration (ms) before forcing a segment split.
  /// 0 = backend/default.
  @$pb.TagNumber(4)
  $core.int get maxSpeechDurationMs => $_getIZ(3);
  @$pb.TagNumber(4)
  set maxSpeechDurationMs($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMaxSpeechDurationMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxSpeechDurationMs() => $_clearField(4);

  /// Whether to include VADStatistics in stream events when available.
  @$pb.TagNumber(5)
  $core.bool get includeStatistics => $_getBF(4);
  @$pb.TagNumber(5)
  set includeStatistics($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasIncludeStatistics() => $_has(4);
  @$pb.TagNumber(5)
  void clearIncludeStatistics() => $_clearField(5);
}

enum VADAudioSource_Source { audioData, adapterHandle, notSet }

class VADAudioSource extends $pb.GeneratedMessage {
  factory VADAudioSource({
    $core.List<$core.int>? audioData,
    $core.String? adapterHandle,
    VADAudioEncoding? encoding,
    $core.int? sampleRate,
    $core.int? channels,
    $fixnum.Int64? frameOffsetMs,
  }) {
    final result = create();
    if (audioData != null) result.audioData = audioData;
    if (adapterHandle != null) result.adapterHandle = adapterHandle;
    if (encoding != null) result.encoding = encoding;
    if (sampleRate != null) result.sampleRate = sampleRate;
    if (channels != null) result.channels = channels;
    if (frameOffsetMs != null) result.frameOffsetMs = frameOffsetMs;
    return result;
  }

  VADAudioSource._();

  factory VADAudioSource.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VADAudioSource.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, VADAudioSource_Source>
      _VADAudioSource_SourceByTag = {
    1: VADAudioSource_Source.audioData,
    2: VADAudioSource_Source.adapterHandle,
    0: VADAudioSource_Source.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VADAudioSource',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..oo(0, [1, 2])
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'audioData', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'adapterHandle')
    ..aE<VADAudioEncoding>(3, _omitFieldNames ? '' : 'encoding',
        enumValues: VADAudioEncoding.values)
    ..aI(4, _omitFieldNames ? '' : 'sampleRate')
    ..aI(5, _omitFieldNames ? '' : 'channels')
    ..aInt64(6, _omitFieldNames ? '' : 'frameOffsetMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VADAudioSource clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VADAudioSource copyWith(void Function(VADAudioSource) updates) =>
      super.copyWith((message) => updates(message as VADAudioSource))
          as VADAudioSource;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VADAudioSource create() => VADAudioSource._();
  @$core.override
  VADAudioSource createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VADAudioSource getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VADAudioSource>(create);
  static VADAudioSource? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  VADAudioSource_Source whichSource() =>
      _VADAudioSource_SourceByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  void clearSource() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.List<$core.int> get audioData => $_getN(0);
  @$pb.TagNumber(1)
  set audioData($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAudioData() => $_has(0);
  @$pb.TagNumber(1)
  void clearAudioData() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get adapterHandle => $_getSZ(1);
  @$pb.TagNumber(2)
  set adapterHandle($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAdapterHandle() => $_has(1);
  @$pb.TagNumber(2)
  void clearAdapterHandle() => $_clearField(2);

  @$pb.TagNumber(3)
  VADAudioEncoding get encoding => $_getN(2);
  @$pb.TagNumber(3)
  set encoding(VADAudioEncoding value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasEncoding() => $_has(2);
  @$pb.TagNumber(3)
  void clearEncoding() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get sampleRate => $_getIZ(3);
  @$pb.TagNumber(4)
  set sampleRate($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSampleRate() => $_has(3);
  @$pb.TagNumber(4)
  void clearSampleRate() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get channels => $_getIZ(4);
  @$pb.TagNumber(5)
  set channels($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasChannels() => $_has(4);
  @$pb.TagNumber(5)
  void clearChannels() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get frameOffsetMs => $_getI64(5);
  @$pb.TagNumber(6)
  set frameOffsetMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasFrameOffsetMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearFrameOffsetMs() => $_clearField(6);
}

class VADProcessRequest extends $pb.GeneratedMessage {
  factory VADProcessRequest({
    $core.String? requestId,
    VADAudioSource? audio,
    VADOptions? options,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (audio != null) result.audio = audio;
    if (options != null) result.options = options;
    if (metadata != null) result.metadata.addEntries(metadata);
    return result;
  }

  VADProcessRequest._();

  factory VADProcessRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VADProcessRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VADProcessRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOM<VADAudioSource>(2, _omitFieldNames ? '' : 'audio',
        subBuilder: VADAudioSource.create)
    ..aOM<VADOptions>(3, _omitFieldNames ? '' : 'options',
        subBuilder: VADOptions.create)
    ..m<$core.String, $core.String>(4, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'VADProcessRequest.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VADProcessRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VADProcessRequest copyWith(void Function(VADProcessRequest) updates) =>
      super.copyWith((message) => updates(message as VADProcessRequest))
          as VADProcessRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VADProcessRequest create() => VADProcessRequest._();
  @$core.override
  VADProcessRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VADProcessRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VADProcessRequest>(create);
  static VADProcessRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  VADAudioSource get audio => $_getN(1);
  @$pb.TagNumber(2)
  set audio(VADAudioSource value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasAudio() => $_has(1);
  @$pb.TagNumber(2)
  void clearAudio() => $_clearField(2);
  @$pb.TagNumber(2)
  VADAudioSource ensureAudio() => $_ensure(1);

  @$pb.TagNumber(3)
  VADOptions get options => $_getN(2);
  @$pb.TagNumber(3)
  set options(VADOptions value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasOptions() => $_has(2);
  @$pb.TagNumber(3)
  void clearOptions() => $_clearField(3);
  @$pb.TagNumber(3)
  VADOptions ensureOptions() => $_ensure(2);

  @$pb.TagNumber(4)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(3);
}

/// ---------------------------------------------------------------------------
/// Result of a single VAD pass over a chunk of PCM audio.
/// Sources pre-IDL:
///   Swift  VADTypes.swift —                 (no struct; bool returned from detectSpeech())
///   Kotlin VADTypes.kt:152                  (isSpeech, confidence, energyLevel,
///                                            statistics, timestamp)
///   Dart   dart_bridge_vad.dart:290         (isSpeech, energy, speechProbability)
///   RN     VADTypes.ts:26                   (isSpeech, probability, startTime, endTime)
///   Web    VADTypes.ts —                    (no VADResult; only SpeechSegment)
///   C ABI  rac_vad_types.h:151 (rac_vad_output_t)
///                                           (is_speech_detected, energy_level, timestamp_ms)
///
/// Drift notes:
///   - Kotlin's `confidence` and Dart's `speechProbability` and RN's
///     `probability` collapse onto the canonical `confidence` field.
///   - Kotlin/RN/C all carry timing — we encode duration_ms (length of the
///     analyzed frame). Wall-clock timestamps belong on the carrying envelope
///     (e.g. VoiceEvent.timestamp_us in voice_events.proto).
/// ---------------------------------------------------------------------------
class VADResult extends $pb.GeneratedMessage {
  factory VADResult({
    $core.bool? isSpeech,
    $core.double? confidence,
    $core.double? energy,
    $core.int? durationMs,
    $fixnum.Int64? timestampMs,
    $fixnum.Int64? startTimeMs,
    $fixnum.Int64? endTimeMs,
    VADStatistics? statistics,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final result = create();
    if (isSpeech != null) result.isSpeech = isSpeech;
    if (confidence != null) result.confidence = confidence;
    if (energy != null) result.energy = energy;
    if (durationMs != null) result.durationMs = durationMs;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (startTimeMs != null) result.startTimeMs = startTimeMs;
    if (endTimeMs != null) result.endTimeMs = endTimeMs;
    if (statistics != null) result.statistics = statistics;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    return result;
  }

  VADResult._();

  factory VADResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VADResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VADResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isSpeech')
    ..aD(2, _omitFieldNames ? '' : 'confidence', fieldType: $pb.PbFieldType.OF)
    ..aD(3, _omitFieldNames ? '' : 'energy', fieldType: $pb.PbFieldType.OF)
    ..aI(4, _omitFieldNames ? '' : 'durationMs')
    ..aInt64(5, _omitFieldNames ? '' : 'timestampMs')
    ..aInt64(6, _omitFieldNames ? '' : 'startTimeMs')
    ..aInt64(7, _omitFieldNames ? '' : 'endTimeMs')
    ..aOM<VADStatistics>(8, _omitFieldNames ? '' : 'statistics',
        subBuilder: VADStatistics.create)
    ..aOS(9, _omitFieldNames ? '' : 'errorMessage')
    ..aI(10, _omitFieldNames ? '' : 'errorCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VADResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VADResult copyWith(void Function(VADResult) updates) =>
      super.copyWith((message) => updates(message as VADResult)) as VADResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VADResult create() => VADResult._();
  @$core.override
  VADResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VADResult getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VADResult>(create);
  static VADResult? _defaultInstance;

  /// Whether speech was detected in this frame.
  /// Mirrors rac_vad_output_t::is_speech_detected.
  @$pb.TagNumber(1)
  $core.bool get isSpeech => $_getBF(0);
  @$pb.TagNumber(1)
  set isSpeech($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIsSpeech() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsSpeech() => $_clearField(1);

  /// Confidence / probability in [0.0, 1.0]. Backend-dependent.
  @$pb.TagNumber(2)
  $core.double get confidence => $_getN(1);
  @$pb.TagNumber(2)
  set confidence($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasConfidence() => $_has(1);
  @$pb.TagNumber(2)
  void clearConfidence() => $_clearField(2);

  /// RMS energy level of the analyzed frame.
  /// Mirrors rac_vad_output_t::energy_level.
  @$pb.TagNumber(3)
  $core.double get energy => $_getN(2);
  @$pb.TagNumber(3)
  set energy($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEnergy() => $_has(2);
  @$pb.TagNumber(3)
  void clearEnergy() => $_clearField(3);

  /// Length of the analyzed frame in milliseconds.
  @$pb.TagNumber(4)
  $core.int get durationMs => $_getIZ(3);
  @$pb.TagNumber(4)
  set durationMs($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDurationMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearDurationMs() => $_clearField(4);

  /// Wall-clock timestamp for this frame/result, in milliseconds since epoch.
  @$pb.TagNumber(5)
  $fixnum.Int64 get timestampMs => $_getI64(4);
  @$pb.TagNumber(5)
  set timestampMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTimestampMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearTimestampMs() => $_clearField(5);

  /// Optional detected segment start/end times, in milliseconds. 0 = unset.
  @$pb.TagNumber(6)
  $fixnum.Int64 get startTimeMs => $_getI64(5);
  @$pb.TagNumber(6)
  set startTimeMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasStartTimeMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearStartTimeMs() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get endTimeMs => $_getI64(6);
  @$pb.TagNumber(7)
  set endTimeMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasEndTimeMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearEndTimeMs() => $_clearField(7);

  /// Optional statistics snapshot and result-envelope error details.
  @$pb.TagNumber(8)
  VADStatistics get statistics => $_getN(7);
  @$pb.TagNumber(8)
  set statistics(VADStatistics value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasStatistics() => $_has(7);
  @$pb.TagNumber(8)
  void clearStatistics() => $_clearField(8);
  @$pb.TagNumber(8)
  VADStatistics ensureStatistics() => $_ensure(7);

  @$pb.TagNumber(9)
  $core.String get errorMessage => $_getSZ(8);
  @$pb.TagNumber(9)
  set errorMessage($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasErrorMessage() => $_has(8);
  @$pb.TagNumber(9)
  void clearErrorMessage() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get errorCode => $_getIZ(9);
  @$pb.TagNumber(10)
  set errorCode($core.int value) => $_setSignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasErrorCode() => $_has(9);
  @$pb.TagNumber(10)
  void clearErrorCode() => $_clearField(10);
}

/// ---------------------------------------------------------------------------
/// Internal VAD statistics, exposed for debugging / waveform UIs.
/// Sources pre-IDL:
///   Swift  VADTypes.swift:174               (current, threshold, ambient,
///                                            recentAvg, recentMax)
///   Kotlin VADTypes.kt:123                  (same five fields)
///   Dart   none — Dart bridge does not surface statistics yet.
///   RN     VADTypes.ts —                    (none)
///   Web    VADTypes.ts —                    (none)
///   C ABI  rac_vad_types.h:194 (rac_vad_statistics_t)
///                                           (current_threshold, ambient_noise_level,
///                                            total_speech_segments, total_speech_duration_ms,
///                                            average_energy, peak_energy)
///
/// We canonicalize on the Swift/Kotlin shape because it is the most widely
/// used. The richer C ABI fields (segment counts, totals) belong on a future
/// VADAnalytics message and are intentionally NOT included here.
/// ---------------------------------------------------------------------------
class VADStatistics extends $pb.GeneratedMessage {
  factory VADStatistics({
    $core.double? currentEnergy,
    $core.double? currentThreshold,
    $core.double? ambientLevel,
    $core.double? recentAvg,
    $core.double? recentMax,
    $core.int? totalSpeechSegments,
    $fixnum.Int64? totalSpeechDurationMs,
    $core.double? averageEnergy,
    $core.double? peakEnergy,
  }) {
    final result = create();
    if (currentEnergy != null) result.currentEnergy = currentEnergy;
    if (currentThreshold != null) result.currentThreshold = currentThreshold;
    if (ambientLevel != null) result.ambientLevel = ambientLevel;
    if (recentAvg != null) result.recentAvg = recentAvg;
    if (recentMax != null) result.recentMax = recentMax;
    if (totalSpeechSegments != null)
      result.totalSpeechSegments = totalSpeechSegments;
    if (totalSpeechDurationMs != null)
      result.totalSpeechDurationMs = totalSpeechDurationMs;
    if (averageEnergy != null) result.averageEnergy = averageEnergy;
    if (peakEnergy != null) result.peakEnergy = peakEnergy;
    return result;
  }

  VADStatistics._();

  factory VADStatistics.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VADStatistics.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VADStatistics',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'currentEnergy',
        fieldType: $pb.PbFieldType.OF)
    ..aD(2, _omitFieldNames ? '' : 'currentThreshold',
        fieldType: $pb.PbFieldType.OF)
    ..aD(3, _omitFieldNames ? '' : 'ambientLevel',
        fieldType: $pb.PbFieldType.OF)
    ..aD(4, _omitFieldNames ? '' : 'recentAvg', fieldType: $pb.PbFieldType.OF)
    ..aD(5, _omitFieldNames ? '' : 'recentMax', fieldType: $pb.PbFieldType.OF)
    ..aI(6, _omitFieldNames ? '' : 'totalSpeechSegments')
    ..aInt64(7, _omitFieldNames ? '' : 'totalSpeechDurationMs')
    ..aD(8, _omitFieldNames ? '' : 'averageEnergy',
        fieldType: $pb.PbFieldType.OF)
    ..aD(9, _omitFieldNames ? '' : 'peakEnergy', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VADStatistics clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VADStatistics copyWith(void Function(VADStatistics) updates) =>
      super.copyWith((message) => updates(message as VADStatistics))
          as VADStatistics;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VADStatistics create() => VADStatistics._();
  @$core.override
  VADStatistics createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VADStatistics getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VADStatistics>(create);
  static VADStatistics? _defaultInstance;

  /// Current instantaneous energy level. (Swift/Kotlin: `current`)
  @$pb.TagNumber(1)
  $core.double get currentEnergy => $_getN(0);
  @$pb.TagNumber(1)
  set currentEnergy($core.double value) => $_setFloat(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCurrentEnergy() => $_has(0);
  @$pb.TagNumber(1)
  void clearCurrentEnergy() => $_clearField(1);

  /// Energy threshold currently in use. (Swift/Kotlin: `threshold`;
  /// C ABI: rac_vad_statistics_t::current_threshold)
  @$pb.TagNumber(2)
  $core.double get currentThreshold => $_getN(1);
  @$pb.TagNumber(2)
  set currentThreshold($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCurrentThreshold() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrentThreshold() => $_clearField(2);

  /// Ambient noise level captured by calibration. (Swift/Kotlin: `ambient`;
  /// C ABI: rac_vad_statistics_t::ambient_noise_level)
  @$pb.TagNumber(3)
  $core.double get ambientLevel => $_getN(2);
  @$pb.TagNumber(3)
  set ambientLevel($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAmbientLevel() => $_has(2);
  @$pb.TagNumber(3)
  void clearAmbientLevel() => $_clearField(3);

  /// Recent moving-window average energy. (Swift/Kotlin: `recentAvg`)
  @$pb.TagNumber(4)
  $core.double get recentAvg => $_getN(3);
  @$pb.TagNumber(4)
  set recentAvg($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRecentAvg() => $_has(3);
  @$pb.TagNumber(4)
  void clearRecentAvg() => $_clearField(4);

  /// Recent moving-window peak energy. (Swift/Kotlin: `recentMax`)
  @$pb.TagNumber(5)
  $core.double get recentMax => $_getN(4);
  @$pb.TagNumber(5)
  set recentMax($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRecentMax() => $_has(4);
  @$pb.TagNumber(5)
  void clearRecentMax() => $_clearField(5);

  /// Richer service-level counters from rac_vad_statistics_t. Zero = unset
  /// for energy-only implementations.
  @$pb.TagNumber(6)
  $core.int get totalSpeechSegments => $_getIZ(5);
  @$pb.TagNumber(6)
  set totalSpeechSegments($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTotalSpeechSegments() => $_has(5);
  @$pb.TagNumber(6)
  void clearTotalSpeechSegments() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get totalSpeechDurationMs => $_getI64(6);
  @$pb.TagNumber(7)
  set totalSpeechDurationMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasTotalSpeechDurationMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearTotalSpeechDurationMs() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.double get averageEnergy => $_getN(7);
  @$pb.TagNumber(8)
  set averageEnergy($core.double value) => $_setFloat(7, value);
  @$pb.TagNumber(8)
  $core.bool hasAverageEnergy() => $_has(7);
  @$pb.TagNumber(8)
  void clearAverageEnergy() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.double get peakEnergy => $_getN(8);
  @$pb.TagNumber(9)
  set peakEnergy($core.double value) => $_setFloat(8, value);
  @$pb.TagNumber(9)
  $core.bool hasPeakEnergy() => $_has(8);
  @$pb.TagNumber(9)
  void clearPeakEnergy() => $_clearField(9);
}

/// ---------------------------------------------------------------------------
/// Activity transition emitted by the VAD as it watches a stream.
/// Sources pre-IDL:
///   Swift  VADTypes.swift:235               (SpeechActivityEvent enum: started/ended)
///   Kotlin VADTypes.kt:171                  (SpeechActivityEvent enum: STARTED/ENDED)
///   Dart   runanywhere_vad.dart:28          (SpeechActivityEvent enum: started/ended)
///   RN     VADTypes.ts:43                   ('started' | 'ended' string union)
///   Web    VADTypes.ts:8                    (SpeechActivity enum: Started/Ended/Ongoing)
///   C ABI  rac_vad_types.h:107 (rac_speech_activity_t)
///                                           (RAC_SPEECH_STARTED/ENDED/ONGOING)
///
/// Distinct from voice_events.proto's `VADEvent`, which carries the broader
/// pipeline-level taxonomy (BARGE_IN, END_OF_UTTERANCE, etc) via
/// `VADStreamEventKind`. `SpeechActivityEvent` here is the narrow
/// component-level transition.
/// ---------------------------------------------------------------------------
class SpeechActivityEvent extends $pb.GeneratedMessage {
  factory SpeechActivityEvent({
    SpeechActivityKind? eventType,
    $fixnum.Int64? timestampMs,
    $core.int? durationMs,
    $core.double? confidence,
    VADResult? result,
    $core.String? segmentId,
  }) {
    final result$ = create();
    if (eventType != null) result$.eventType = eventType;
    if (timestampMs != null) result$.timestampMs = timestampMs;
    if (durationMs != null) result$.durationMs = durationMs;
    if (confidence != null) result$.confidence = confidence;
    if (result != null) result$.result = result;
    if (segmentId != null) result$.segmentId = segmentId;
    return result$;
  }

  SpeechActivityEvent._();

  factory SpeechActivityEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SpeechActivityEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SpeechActivityEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<SpeechActivityKind>(1, _omitFieldNames ? '' : 'eventType',
        enumValues: SpeechActivityKind.values)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampMs')
    ..aI(3, _omitFieldNames ? '' : 'durationMs')
    ..aD(4, _omitFieldNames ? '' : 'confidence', fieldType: $pb.PbFieldType.OF)
    ..aOM<VADResult>(5, _omitFieldNames ? '' : 'result',
        subBuilder: VADResult.create)
    ..aOS(6, _omitFieldNames ? '' : 'segmentId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SpeechActivityEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SpeechActivityEvent copyWith(void Function(SpeechActivityEvent) updates) =>
      super.copyWith((message) => updates(message as SpeechActivityEvent))
          as SpeechActivityEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SpeechActivityEvent create() => SpeechActivityEvent._();
  @$core.override
  SpeechActivityEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SpeechActivityEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SpeechActivityEvent>(create);
  static SpeechActivityEvent? _defaultInstance;

  /// Which transition happened.
  @$pb.TagNumber(1)
  SpeechActivityKind get eventType => $_getN(0);
  @$pb.TagNumber(1)
  set eventType(SpeechActivityKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasEventType() => $_has(0);
  @$pb.TagNumber(1)
  void clearEventType() => $_clearField(1);

  /// Wall-clock time of the transition, in milliseconds since epoch.
  /// Aligns with rac_vad_output_t::timestamp_ms.
  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampMs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestampMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampMs() => $_clearField(2);

  /// Optional duration of the speech / silence that triggered this event,
  /// in milliseconds. Set on SPEECH_ENDED to communicate the just-finished
  /// utterance length; left zero on SPEECH_STARTED.
  @$pb.TagNumber(3)
  $core.int get durationMs => $_getIZ(2);
  @$pb.TagNumber(3)
  set durationMs($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDurationMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearDurationMs() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get confidence => $_getN(3);
  @$pb.TagNumber(4)
  set confidence($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasConfidence() => $_has(3);
  @$pb.TagNumber(4)
  void clearConfidence() => $_clearField(4);

  @$pb.TagNumber(5)
  VADResult get result => $_getN(4);
  @$pb.TagNumber(5)
  set result(VADResult value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasResult() => $_has(4);
  @$pb.TagNumber(5)
  void clearResult() => $_clearField(5);
  @$pb.TagNumber(5)
  VADResult ensureResult() => $_ensure(4);

  @$pb.TagNumber(6)
  $core.String get segmentId => $_getSZ(5);
  @$pb.TagNumber(6)
  set segmentId($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSegmentId() => $_has(5);
  @$pb.TagNumber(6)
  void clearSegmentId() => $_clearField(6);
}

class VADStreamEvent extends $pb.GeneratedMessage {
  factory VADStreamEvent({
    $fixnum.Int64? seq,
    $fixnum.Int64? timestampUs,
    $core.String? requestId,
    VADStreamEventKind? kind,
    VADResult? result,
    SpeechActivityEvent? activity,
    VADStatistics? statistics,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final result$ = create();
    if (seq != null) result$.seq = seq;
    if (timestampUs != null) result$.timestampUs = timestampUs;
    if (requestId != null) result$.requestId = requestId;
    if (kind != null) result$.kind = kind;
    if (result != null) result$.result = result;
    if (activity != null) result$.activity = activity;
    if (statistics != null) result$.statistics = statistics;
    if (errorMessage != null) result$.errorMessage = errorMessage;
    if (errorCode != null) result$.errorCode = errorCode;
    return result$;
  }

  VADStreamEvent._();

  factory VADStreamEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VADStreamEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VADStreamEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(3, _omitFieldNames ? '' : 'requestId')
    ..aE<VADStreamEventKind>(4, _omitFieldNames ? '' : 'kind',
        enumValues: VADStreamEventKind.values)
    ..aOM<VADResult>(5, _omitFieldNames ? '' : 'result',
        subBuilder: VADResult.create)
    ..aOM<SpeechActivityEvent>(6, _omitFieldNames ? '' : 'activity',
        subBuilder: SpeechActivityEvent.create)
    ..aOM<VADStatistics>(7, _omitFieldNames ? '' : 'statistics',
        subBuilder: VADStatistics.create)
    ..aOS(8, _omitFieldNames ? '' : 'errorMessage')
    ..aI(9, _omitFieldNames ? '' : 'errorCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VADStreamEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VADStreamEvent copyWith(void Function(VADStreamEvent) updates) =>
      super.copyWith((message) => updates(message as VADStreamEvent))
          as VADStreamEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VADStreamEvent create() => VADStreamEvent._();
  @$core.override
  VADStreamEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VADStreamEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VADStreamEvent>(create);
  static VADStreamEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get seq => $_getI64(0);
  @$pb.TagNumber(1)
  set seq($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampUs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampUs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestampUs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampUs() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get requestId => $_getSZ(2);
  @$pb.TagNumber(3)
  set requestId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRequestId() => $_has(2);
  @$pb.TagNumber(3)
  void clearRequestId() => $_clearField(3);

  @$pb.TagNumber(4)
  VADStreamEventKind get kind => $_getN(3);
  @$pb.TagNumber(4)
  set kind(VADStreamEventKind value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasKind() => $_has(3);
  @$pb.TagNumber(4)
  void clearKind() => $_clearField(4);

  @$pb.TagNumber(5)
  VADResult get result => $_getN(4);
  @$pb.TagNumber(5)
  set result(VADResult value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasResult() => $_has(4);
  @$pb.TagNumber(5)
  void clearResult() => $_clearField(5);
  @$pb.TagNumber(5)
  VADResult ensureResult() => $_ensure(4);

  @$pb.TagNumber(6)
  SpeechActivityEvent get activity => $_getN(5);
  @$pb.TagNumber(6)
  set activity(SpeechActivityEvent value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasActivity() => $_has(5);
  @$pb.TagNumber(6)
  void clearActivity() => $_clearField(6);
  @$pb.TagNumber(6)
  SpeechActivityEvent ensureActivity() => $_ensure(5);

  @$pb.TagNumber(7)
  VADStatistics get statistics => $_getN(6);
  @$pb.TagNumber(7)
  set statistics(VADStatistics value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasStatistics() => $_has(6);
  @$pb.TagNumber(7)
  void clearStatistics() => $_clearField(7);
  @$pb.TagNumber(7)
  VADStatistics ensureStatistics() => $_ensure(6);

  @$pb.TagNumber(8)
  $core.String get errorMessage => $_getSZ(7);
  @$pb.TagNumber(8)
  set errorMessage($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasErrorMessage() => $_has(7);
  @$pb.TagNumber(8)
  void clearErrorMessage() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get errorCode => $_getIZ(8);
  @$pb.TagNumber(9)
  set errorCode($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasErrorCode() => $_has(8);
  @$pb.TagNumber(9)
  void clearErrorCode() => $_clearField(9);
}

class VADServiceState extends $pb.GeneratedMessage {
  factory VADServiceState({
    $core.bool? isReady,
    $core.bool? isSpeechActive,
    $core.double? energyThreshold,
    $core.int? sampleRate,
    $core.int? frameLengthMs,
    $core.String? currentModel,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final result = create();
    if (isReady != null) result.isReady = isReady;
    if (isSpeechActive != null) result.isSpeechActive = isSpeechActive;
    if (energyThreshold != null) result.energyThreshold = energyThreshold;
    if (sampleRate != null) result.sampleRate = sampleRate;
    if (frameLengthMs != null) result.frameLengthMs = frameLengthMs;
    if (currentModel != null) result.currentModel = currentModel;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    return result;
  }

  VADServiceState._();

  factory VADServiceState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VADServiceState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VADServiceState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isReady')
    ..aOB(2, _omitFieldNames ? '' : 'isSpeechActive')
    ..aD(3, _omitFieldNames ? '' : 'energyThreshold',
        fieldType: $pb.PbFieldType.OF)
    ..aI(4, _omitFieldNames ? '' : 'sampleRate')
    ..aI(5, _omitFieldNames ? '' : 'frameLengthMs')
    ..aOS(6, _omitFieldNames ? '' : 'currentModel')
    ..aOS(7, _omitFieldNames ? '' : 'errorMessage')
    ..aI(8, _omitFieldNames ? '' : 'errorCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VADServiceState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VADServiceState copyWith(void Function(VADServiceState) updates) =>
      super.copyWith((message) => updates(message as VADServiceState))
          as VADServiceState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VADServiceState create() => VADServiceState._();
  @$core.override
  VADServiceState createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VADServiceState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VADServiceState>(create);
  static VADServiceState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get isReady => $_getBF(0);
  @$pb.TagNumber(1)
  set isReady($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIsReady() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsReady() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get isSpeechActive => $_getBF(1);
  @$pb.TagNumber(2)
  set isSpeechActive($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIsSpeechActive() => $_has(1);
  @$pb.TagNumber(2)
  void clearIsSpeechActive() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get energyThreshold => $_getN(2);
  @$pb.TagNumber(3)
  set energyThreshold($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEnergyThreshold() => $_has(2);
  @$pb.TagNumber(3)
  void clearEnergyThreshold() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get sampleRate => $_getIZ(3);
  @$pb.TagNumber(4)
  set sampleRate($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSampleRate() => $_has(3);
  @$pb.TagNumber(4)
  void clearSampleRate() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get frameLengthMs => $_getIZ(4);
  @$pb.TagNumber(5)
  set frameLengthMs($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasFrameLengthMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearFrameLengthMs() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get currentModel => $_getSZ(5);
  @$pb.TagNumber(6)
  set currentModel($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCurrentModel() => $_has(5);
  @$pb.TagNumber(6)
  void clearCurrentModel() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get errorMessage => $_getSZ(6);
  @$pb.TagNumber(7)
  set errorMessage($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasErrorMessage() => $_has(6);
  @$pb.TagNumber(7)
  void clearErrorMessage() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get errorCode => $_getIZ(7);
  @$pb.TagNumber(8)
  set errorCode($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasErrorCode() => $_has(7);
  @$pb.TagNumber(8)
  void clearErrorCode() => $_clearField(8);
}

/// Logical VAD service contract. Native microphone capture, audio-session
/// ownership, device routing, and platform stream plumbing remain outside C++;
/// C++ consumes only serialized frame requests and emits logical VAD events.
class VADApi {
  final $pb.RpcClient _client;

  VADApi(this._client);

  /// One-shot frame processing over PCM bytes or an adapter-provided logical
  /// audio handle.
  $async.Future<VADResult> processFrame(
          $pb.ClientContext? ctx, VADProcessRequest request) =>
      _client.invoke<VADResult>(
          ctx, 'VAD', 'ProcessFrame', request, VADResult());

  /// Server-streaming speech-activity events: frame results, transitions,
  /// statistics snapshots, terminal stop, and errors.
  $async.Future<VADStreamEvent> stream(
          $pb.ClientContext? ctx, VADProcessRequest request) =>
      _client.invoke<VADStreamEvent>(
          ctx, 'VAD', 'Stream', request, VADStreamEvent());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
