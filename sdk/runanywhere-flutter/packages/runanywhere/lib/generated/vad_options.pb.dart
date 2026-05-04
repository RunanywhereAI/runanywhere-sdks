//
//  Generated code. Do not modify.
//  source: vad_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'model_types.pbenum.dart' as $0;
import 'vad_options.pbenum.dart';

export 'vad_options.pbenum.dart';

///  ---------------------------------------------------------------------------
///  Compile-time / load-time configuration for a VAD instance.
///  Sources pre-IDL:
///    Swift  VADTypes.swift:15                (energyThreshold, sampleRate, frameLength,
///                                             enableAutoCalibration, calibrationMultiplier)
///    Kotlin VADTypes.kt:26                   (same five fields, defaults match Swift)
///    Dart   vad_configuration.dart:5         (same five fields)
///    RN     VADTypes.ts:12                   (sampleRate, frameLength, energyThreshold;
///                                             no calibration fields)
///    Web    VADTypes.ts —                    (no VADConfiguration; per-backend in WebSDK)
///    C ABI  rac_vad_types.h:63 (rac_vad_config_t)
///                                            (model_id, preferred_framework, energy_threshold,
///                                             sample_rate, frame_length, enable_auto_calibration,
///                                             calibration_multiplier)
///
///  `frame_length_ms` is the canonical wire field — Swift/Kotlin/Dart/C use
///  seconds (float), but ms is more interoperable across protobuf consumers.
///  Generators must convert when binding to per-platform types.
///  ---------------------------------------------------------------------------
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
    final $result = create();
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (sampleRate != null) {
      $result.sampleRate = sampleRate;
    }
    if (frameLengthMs != null) {
      $result.frameLengthMs = frameLengthMs;
    }
    if (threshold != null) {
      $result.threshold = threshold;
    }
    if (enableAutoCalibration != null) {
      $result.enableAutoCalibration = enableAutoCalibration;
    }
    if (calibrationMultiplier != null) {
      $result.calibrationMultiplier = calibrationMultiplier;
    }
    if (preferredFramework != null) {
      $result.preferredFramework = preferredFramework;
    }
    if (modelPath != null) {
      $result.modelPath = modelPath;
    }
    if (windowSizeSamples != null) {
      $result.windowSizeSamples = windowSizeSamples;
    }
    if (maxSpeechDurationMs != null) {
      $result.maxSpeechDurationMs = maxSpeechDurationMs;
    }
    return $result;
  }
  VADConfiguration._() : super();
  factory VADConfiguration.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VADConfiguration.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VADConfiguration', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..a<$core.int>(2, _omitFieldNames ? '' : 'sampleRate', $pb.PbFieldType.O3)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'frameLengthMs', $pb.PbFieldType.O3)
    ..a<$core.double>(4, _omitFieldNames ? '' : 'threshold', $pb.PbFieldType.OF)
    ..aOB(5, _omitFieldNames ? '' : 'enableAutoCalibration')
    ..a<$core.double>(6, _omitFieldNames ? '' : 'calibrationMultiplier', $pb.PbFieldType.OF)
    ..e<$0.InferenceFramework>(7, _omitFieldNames ? '' : 'preferredFramework', $pb.PbFieldType.OE, defaultOrMaker: $0.InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED, valueOf: $0.InferenceFramework.valueOf, enumValues: $0.InferenceFramework.values)
    ..aOS(8, _omitFieldNames ? '' : 'modelPath')
    ..a<$core.int>(9, _omitFieldNames ? '' : 'windowSizeSamples', $pb.PbFieldType.O3)
    ..a<$core.int>(10, _omitFieldNames ? '' : 'maxSpeechDurationMs', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VADConfiguration clone() => VADConfiguration()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VADConfiguration copyWith(void Function(VADConfiguration) updates) => super.copyWith((message) => updates(message as VADConfiguration)) as VADConfiguration;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VADConfiguration create() => VADConfiguration._();
  VADConfiguration createEmptyInstance() => create();
  static $pb.PbList<VADConfiguration> createRepeated() => $pb.PbList<VADConfiguration>();
  @$core.pragma('dart2js:noInline')
  static VADConfiguration getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VADConfiguration>(create);
  static VADConfiguration? _defaultInstance;

  /// Optional model id; empty when using the built-in energy VAD.
  /// C ABI: model_id (rac_vad_config_t::model_id, may be NULL).
  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => clearField(1);

  /// PCM sample rate in Hz. Default 16000 (RAC_VAD_DEFAULT_SAMPLE_RATE).
  @$pb.TagNumber(2)
  $core.int get sampleRate => $_getIZ(1);
  @$pb.TagNumber(2)
  set sampleRate($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSampleRate() => $_has(1);
  @$pb.TagNumber(2)
  void clearSampleRate() => clearField(2);

  /// Frame length in milliseconds. Default 100 (Swift/Kotlin/Dart store
  /// 0.1 seconds; we canonicalize to ms on the wire).
  @$pb.TagNumber(3)
  $core.int get frameLengthMs => $_getIZ(2);
  @$pb.TagNumber(3)
  set frameLengthMs($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasFrameLengthMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearFrameLengthMs() => clearField(3);

  /// Energy threshold in [0.0, 1.0] for voice detection.
  /// Recommended range 0.01–0.05; default 0.015 across SDKs.
  @$pb.TagNumber(4)
  $core.double get threshold => $_getN(3);
  @$pb.TagNumber(4)
  set threshold($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasThreshold() => $_has(3);
  @$pb.TagNumber(4)
  void clearThreshold() => clearField(4);

  /// When true, the VAD performs ambient-noise calibration and uses the
  /// result as a multiplier on the threshold (see calibration_multiplier
  /// in the C ABI). Defaults to false.
  @$pb.TagNumber(5)
  $core.bool get enableAutoCalibration => $_getBF(4);
  @$pb.TagNumber(5)
  set enableAutoCalibration($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasEnableAutoCalibration() => $_has(4);
  @$pb.TagNumber(5)
  void clearEnableAutoCalibration() => clearField(5);

  /// Calibration multiplier (threshold = ambient noise * multiplier).
  /// Present in Swift/Kotlin/Dart configs and rac_vad_config_t.
  @$pb.TagNumber(6)
  $core.double get calibrationMultiplier => $_getN(5);
  @$pb.TagNumber(6)
  set calibrationMultiplier($core.double v) { $_setFloat(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasCalibrationMultiplier() => $_has(5);
  @$pb.TagNumber(6)
  void clearCalibrationMultiplier() => clearField(6);

  /// Preferred framework for VAD. Absent = auto.
  @$pb.TagNumber(7)
  $0.InferenceFramework get preferredFramework => $_getN(6);
  @$pb.TagNumber(7)
  set preferredFramework($0.InferenceFramework v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasPreferredFramework() => $_has(6);
  @$pb.TagNumber(7)
  void clearPreferredFramework() => clearField(7);

  /// Optional model path for backend-specific VADs (e.g. Silero ONNX).
  @$pb.TagNumber(8)
  $core.String get modelPath => $_getSZ(7);
  @$pb.TagNumber(8)
  set modelPath($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasModelPath() => $_has(7);
  @$pb.TagNumber(8)
  void clearModelPath() => clearField(8);

  /// Window size in samples for frame-based neural VAD backends. 0 =
  /// backend/default.
  @$pb.TagNumber(9)
  $core.int get windowSizeSamples => $_getIZ(8);
  @$pb.TagNumber(9)
  set windowSizeSamples($core.int v) { $_setSignedInt32(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasWindowSizeSamples() => $_has(8);
  @$pb.TagNumber(9)
  void clearWindowSizeSamples() => clearField(9);

  /// Maximum continuous speech segment duration in milliseconds. 0 =
  /// backend/default.
  @$pb.TagNumber(10)
  $core.int get maxSpeechDurationMs => $_getIZ(9);
  @$pb.TagNumber(10)
  set maxSpeechDurationMs($core.int v) { $_setSignedInt32(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasMaxSpeechDurationMs() => $_has(9);
  @$pb.TagNumber(10)
  void clearMaxSpeechDurationMs() => clearField(10);
}

///  ---------------------------------------------------------------------------
///  Runtime / per-call options applied to a VAD pass.
///  Sources pre-IDL:
///    Swift  none — Swift uses raw arguments to detectSpeech().
///    Kotlin none — same as Swift.
///    Dart   runanywhere_vad.dart:99          (`detectSpeech` takes raw Float32List)
///    RN     VADTypes.ts —                    (no per-call options struct)
///    Web    VADTypes.ts —                    (no per-call options struct)
///    C ABI  rac_vad_types.h:123 (rac_vad_input_t)
///                                            (audio_samples, num_samples,
///                                             energy_threshold_override)
///
///  We canonicalize on the energy_threshold_override + the speech-duration
///  gates that already appear as constants in rac_vad_types.h:50-51:
///    RAC_VAD_MIN_SPEECH_DURATION_MS  = 100
///    RAC_VAD_MIN_SILENCE_DURATION_MS = 300
///  Surfacing them as fields lets callers tune debouncing without a rebuild.
///  ---------------------------------------------------------------------------
class VADOptions extends $pb.GeneratedMessage {
  factory VADOptions({
    $core.double? threshold,
    $core.int? minSpeechDurationMs,
    $core.int? minSilenceDurationMs,
    $core.int? maxSpeechDurationMs,
  }) {
    final $result = create();
    if (threshold != null) {
      $result.threshold = threshold;
    }
    if (minSpeechDurationMs != null) {
      $result.minSpeechDurationMs = minSpeechDurationMs;
    }
    if (minSilenceDurationMs != null) {
      $result.minSilenceDurationMs = minSilenceDurationMs;
    }
    if (maxSpeechDurationMs != null) {
      $result.maxSpeechDurationMs = maxSpeechDurationMs;
    }
    return $result;
  }
  VADOptions._() : super();
  factory VADOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VADOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VADOptions', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.double>(1, _omitFieldNames ? '' : 'threshold', $pb.PbFieldType.OF)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'minSpeechDurationMs', $pb.PbFieldType.O3)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'minSilenceDurationMs', $pb.PbFieldType.O3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'maxSpeechDurationMs', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VADOptions clone() => VADOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VADOptions copyWith(void Function(VADOptions) updates) => super.copyWith((message) => updates(message as VADOptions)) as VADOptions;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VADOptions create() => VADOptions._();
  VADOptions createEmptyInstance() => create();
  static $pb.PbList<VADOptions> createRepeated() => $pb.PbList<VADOptions>();
  @$core.pragma('dart2js:noInline')
  static VADOptions getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VADOptions>(create);
  static VADOptions? _defaultInstance;

  /// Per-call energy threshold override. Use 0 (default) to keep the
  /// configured threshold. Mirrors rac_vad_input_t::energy_threshold_override
  /// (which uses -1 as the sentinel; on the wire we use 0 for proto3
  /// default semantics — generators emit -1 when this is unset).
  @$pb.TagNumber(1)
  $core.double get threshold => $_getN(0);
  @$pb.TagNumber(1)
  set threshold($core.double v) { $_setFloat(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasThreshold() => $_has(0);
  @$pb.TagNumber(1)
  void clearThreshold() => clearField(1);

  /// Minimum continuous speech duration (ms) before SPEECH_STARTED fires.
  /// Default 100 (RAC_VAD_MIN_SPEECH_DURATION_MS).
  @$pb.TagNumber(2)
  $core.int get minSpeechDurationMs => $_getIZ(1);
  @$pb.TagNumber(2)
  set minSpeechDurationMs($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMinSpeechDurationMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearMinSpeechDurationMs() => clearField(2);

  /// Minimum continuous silence duration (ms) before SPEECH_ENDED fires.
  /// Default 300 (RAC_VAD_MIN_SILENCE_DURATION_MS).
  @$pb.TagNumber(3)
  $core.int get minSilenceDurationMs => $_getIZ(2);
  @$pb.TagNumber(3)
  set minSilenceDurationMs($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMinSilenceDurationMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearMinSilenceDurationMs() => clearField(3);

  /// Maximum continuous speech duration (ms) before forcing a segment split.
  /// 0 = backend/default.
  @$pb.TagNumber(4)
  $core.int get maxSpeechDurationMs => $_getIZ(3);
  @$pb.TagNumber(4)
  set maxSpeechDurationMs($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasMaxSpeechDurationMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxSpeechDurationMs() => clearField(4);
}

///  ---------------------------------------------------------------------------
///  Result of a single VAD pass over a chunk of PCM audio.
///  Sources pre-IDL:
///    Swift  VADTypes.swift —                 (no struct; bool returned from detectSpeech())
///    Kotlin VADTypes.kt:152                  (isSpeech, confidence, energyLevel,
///                                             statistics, timestamp)
///    Dart   dart_bridge_vad.dart:290         (isSpeech, energy, speechProbability)
///    RN     VADTypes.ts:26                   (isSpeech, probability, startTime, endTime)
///    Web    VADTypes.ts —                    (no VADResult; only SpeechSegment)
///    C ABI  rac_vad_types.h:151 (rac_vad_output_t)
///                                            (is_speech_detected, energy_level, timestamp_ms)
///
///  Drift notes:
///    - Kotlin's `confidence` and Dart's `speechProbability` and RN's
///      `probability` collapse onto the canonical `confidence` field.
///    - Kotlin/RN/C all carry timing — we encode duration_ms (length of the
///      analyzed frame). Wall-clock timestamps belong on the carrying envelope
///      (e.g. VoiceEvent.timestamp_us in voice_events.proto).
///  ---------------------------------------------------------------------------
class VADResult extends $pb.GeneratedMessage {
  factory VADResult({
    $core.bool? isSpeech,
    $core.double? confidence,
    $core.double? energy,
    $core.int? durationMs,
    $fixnum.Int64? timestampMs,
    $fixnum.Int64? startTimeMs,
    $fixnum.Int64? endTimeMs,
  }) {
    final $result = create();
    if (isSpeech != null) {
      $result.isSpeech = isSpeech;
    }
    if (confidence != null) {
      $result.confidence = confidence;
    }
    if (energy != null) {
      $result.energy = energy;
    }
    if (durationMs != null) {
      $result.durationMs = durationMs;
    }
    if (timestampMs != null) {
      $result.timestampMs = timestampMs;
    }
    if (startTimeMs != null) {
      $result.startTimeMs = startTimeMs;
    }
    if (endTimeMs != null) {
      $result.endTimeMs = endTimeMs;
    }
    return $result;
  }
  VADResult._() : super();
  factory VADResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VADResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VADResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isSpeech')
    ..a<$core.double>(2, _omitFieldNames ? '' : 'confidence', $pb.PbFieldType.OF)
    ..a<$core.double>(3, _omitFieldNames ? '' : 'energy', $pb.PbFieldType.OF)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'durationMs', $pb.PbFieldType.O3)
    ..aInt64(5, _omitFieldNames ? '' : 'timestampMs')
    ..aInt64(6, _omitFieldNames ? '' : 'startTimeMs')
    ..aInt64(7, _omitFieldNames ? '' : 'endTimeMs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VADResult clone() => VADResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VADResult copyWith(void Function(VADResult) updates) => super.copyWith((message) => updates(message as VADResult)) as VADResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VADResult create() => VADResult._();
  VADResult createEmptyInstance() => create();
  static $pb.PbList<VADResult> createRepeated() => $pb.PbList<VADResult>();
  @$core.pragma('dart2js:noInline')
  static VADResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VADResult>(create);
  static VADResult? _defaultInstance;

  /// Whether speech was detected in this frame.
  /// Mirrors rac_vad_output_t::is_speech_detected.
  @$pb.TagNumber(1)
  $core.bool get isSpeech => $_getBF(0);
  @$pb.TagNumber(1)
  set isSpeech($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasIsSpeech() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsSpeech() => clearField(1);

  /// Confidence / probability in [0.0, 1.0]. Backend-dependent.
  @$pb.TagNumber(2)
  $core.double get confidence => $_getN(1);
  @$pb.TagNumber(2)
  set confidence($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasConfidence() => $_has(1);
  @$pb.TagNumber(2)
  void clearConfidence() => clearField(2);

  /// RMS energy level of the analyzed frame.
  /// Mirrors rac_vad_output_t::energy_level.
  @$pb.TagNumber(3)
  $core.double get energy => $_getN(2);
  @$pb.TagNumber(3)
  set energy($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasEnergy() => $_has(2);
  @$pb.TagNumber(3)
  void clearEnergy() => clearField(3);

  /// Length of the analyzed frame in milliseconds.
  @$pb.TagNumber(4)
  $core.int get durationMs => $_getIZ(3);
  @$pb.TagNumber(4)
  set durationMs($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasDurationMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearDurationMs() => clearField(4);

  /// Wall-clock timestamp for this frame/result, in milliseconds since epoch.
  @$pb.TagNumber(5)
  $fixnum.Int64 get timestampMs => $_getI64(4);
  @$pb.TagNumber(5)
  set timestampMs($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasTimestampMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearTimestampMs() => clearField(5);

  /// Optional detected segment start/end times, in milliseconds. 0 = unset.
  @$pb.TagNumber(6)
  $fixnum.Int64 get startTimeMs => $_getI64(5);
  @$pb.TagNumber(6)
  set startTimeMs($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasStartTimeMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearStartTimeMs() => clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get endTimeMs => $_getI64(6);
  @$pb.TagNumber(7)
  set endTimeMs($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasEndTimeMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearEndTimeMs() => clearField(7);
}

///  ---------------------------------------------------------------------------
///  Internal VAD statistics, exposed for debugging / waveform UIs.
///  Sources pre-IDL:
///    Swift  VADTypes.swift:174               (current, threshold, ambient,
///                                             recentAvg, recentMax)
///    Kotlin VADTypes.kt:123                  (same five fields)
///    Dart   none — Dart bridge does not surface statistics yet.
///    RN     VADTypes.ts —                    (none)
///    Web    VADTypes.ts —                    (none)
///    C ABI  rac_vad_types.h:194 (rac_vad_statistics_t)
///                                            (current_threshold, ambient_noise_level,
///                                             total_speech_segments, total_speech_duration_ms,
///                                             average_energy, peak_energy)
///
///  We canonicalize on the Swift/Kotlin shape because it is the most widely
///  used. The richer C ABI fields (segment counts, totals) belong on a future
///  VADAnalytics message and are intentionally NOT included here.
///  ---------------------------------------------------------------------------
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
    final $result = create();
    if (currentEnergy != null) {
      $result.currentEnergy = currentEnergy;
    }
    if (currentThreshold != null) {
      $result.currentThreshold = currentThreshold;
    }
    if (ambientLevel != null) {
      $result.ambientLevel = ambientLevel;
    }
    if (recentAvg != null) {
      $result.recentAvg = recentAvg;
    }
    if (recentMax != null) {
      $result.recentMax = recentMax;
    }
    if (totalSpeechSegments != null) {
      $result.totalSpeechSegments = totalSpeechSegments;
    }
    if (totalSpeechDurationMs != null) {
      $result.totalSpeechDurationMs = totalSpeechDurationMs;
    }
    if (averageEnergy != null) {
      $result.averageEnergy = averageEnergy;
    }
    if (peakEnergy != null) {
      $result.peakEnergy = peakEnergy;
    }
    return $result;
  }
  VADStatistics._() : super();
  factory VADStatistics.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VADStatistics.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VADStatistics', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.double>(1, _omitFieldNames ? '' : 'currentEnergy', $pb.PbFieldType.OF)
    ..a<$core.double>(2, _omitFieldNames ? '' : 'currentThreshold', $pb.PbFieldType.OF)
    ..a<$core.double>(3, _omitFieldNames ? '' : 'ambientLevel', $pb.PbFieldType.OF)
    ..a<$core.double>(4, _omitFieldNames ? '' : 'recentAvg', $pb.PbFieldType.OF)
    ..a<$core.double>(5, _omitFieldNames ? '' : 'recentMax', $pb.PbFieldType.OF)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'totalSpeechSegments', $pb.PbFieldType.O3)
    ..aInt64(7, _omitFieldNames ? '' : 'totalSpeechDurationMs')
    ..a<$core.double>(8, _omitFieldNames ? '' : 'averageEnergy', $pb.PbFieldType.OF)
    ..a<$core.double>(9, _omitFieldNames ? '' : 'peakEnergy', $pb.PbFieldType.OF)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VADStatistics clone() => VADStatistics()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VADStatistics copyWith(void Function(VADStatistics) updates) => super.copyWith((message) => updates(message as VADStatistics)) as VADStatistics;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VADStatistics create() => VADStatistics._();
  VADStatistics createEmptyInstance() => create();
  static $pb.PbList<VADStatistics> createRepeated() => $pb.PbList<VADStatistics>();
  @$core.pragma('dart2js:noInline')
  static VADStatistics getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VADStatistics>(create);
  static VADStatistics? _defaultInstance;

  /// Current instantaneous energy level. (Swift/Kotlin: `current`)
  @$pb.TagNumber(1)
  $core.double get currentEnergy => $_getN(0);
  @$pb.TagNumber(1)
  set currentEnergy($core.double v) { $_setFloat(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCurrentEnergy() => $_has(0);
  @$pb.TagNumber(1)
  void clearCurrentEnergy() => clearField(1);

  /// Energy threshold currently in use. (Swift/Kotlin: `threshold`;
  /// C ABI: rac_vad_statistics_t::current_threshold)
  @$pb.TagNumber(2)
  $core.double get currentThreshold => $_getN(1);
  @$pb.TagNumber(2)
  set currentThreshold($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCurrentThreshold() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrentThreshold() => clearField(2);

  /// Ambient noise level captured by calibration. (Swift/Kotlin: `ambient`;
  /// C ABI: rac_vad_statistics_t::ambient_noise_level)
  @$pb.TagNumber(3)
  $core.double get ambientLevel => $_getN(2);
  @$pb.TagNumber(3)
  set ambientLevel($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAmbientLevel() => $_has(2);
  @$pb.TagNumber(3)
  void clearAmbientLevel() => clearField(3);

  /// Recent moving-window average energy. (Swift/Kotlin: `recentAvg`)
  @$pb.TagNumber(4)
  $core.double get recentAvg => $_getN(3);
  @$pb.TagNumber(4)
  set recentAvg($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasRecentAvg() => $_has(3);
  @$pb.TagNumber(4)
  void clearRecentAvg() => clearField(4);

  /// Recent moving-window peak energy. (Swift/Kotlin: `recentMax`)
  @$pb.TagNumber(5)
  $core.double get recentMax => $_getN(4);
  @$pb.TagNumber(5)
  set recentMax($core.double v) { $_setFloat(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasRecentMax() => $_has(4);
  @$pb.TagNumber(5)
  void clearRecentMax() => clearField(5);

  /// Richer service-level counters from rac_vad_statistics_t. Zero = unset
  /// for energy-only implementations.
  @$pb.TagNumber(6)
  $core.int get totalSpeechSegments => $_getIZ(5);
  @$pb.TagNumber(6)
  set totalSpeechSegments($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTotalSpeechSegments() => $_has(5);
  @$pb.TagNumber(6)
  void clearTotalSpeechSegments() => clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get totalSpeechDurationMs => $_getI64(6);
  @$pb.TagNumber(7)
  set totalSpeechDurationMs($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasTotalSpeechDurationMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearTotalSpeechDurationMs() => clearField(7);

  @$pb.TagNumber(8)
  $core.double get averageEnergy => $_getN(7);
  @$pb.TagNumber(8)
  set averageEnergy($core.double v) { $_setFloat(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasAverageEnergy() => $_has(7);
  @$pb.TagNumber(8)
  void clearAverageEnergy() => clearField(8);

  @$pb.TagNumber(9)
  $core.double get peakEnergy => $_getN(8);
  @$pb.TagNumber(9)
  set peakEnergy($core.double v) { $_setFloat(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasPeakEnergy() => $_has(8);
  @$pb.TagNumber(9)
  void clearPeakEnergy() => clearField(9);
}

///  ---------------------------------------------------------------------------
///  Activity transition emitted by the VAD as it watches a stream.
///  Sources pre-IDL:
///    Swift  VADTypes.swift:235               (SpeechActivityEvent enum: started/ended)
///    Kotlin VADTypes.kt:171                  (SpeechActivityEvent enum: STARTED/ENDED)
///    Dart   runanywhere_vad.dart:28          (SpeechActivityEvent enum: started/ended)
///    RN     VADTypes.ts:43                   ('started' | 'ended' string union)
///    Web    VADTypes.ts:8                    (SpeechActivity enum: Started/Ended/Ongoing)
///    C ABI  rac_vad_types.h:107 (rac_speech_activity_t)
///                                            (RAC_SPEECH_STARTED/ENDED/ONGOING)
///
///  Distinct from voice_events.proto's `VADEvent`/`VADEventType`, which carry
///  the broader pipeline-level taxonomy (BARGE_IN, END_OF_UTTERANCE, etc).
///  `SpeechActivityEvent` here is the narrow component-level transition.
///  ---------------------------------------------------------------------------
class SpeechActivityEvent extends $pb.GeneratedMessage {
  factory SpeechActivityEvent({
    SpeechActivityKind? eventType,
    $fixnum.Int64? timestampMs,
    $core.int? durationMs,
  }) {
    final $result = create();
    if (eventType != null) {
      $result.eventType = eventType;
    }
    if (timestampMs != null) {
      $result.timestampMs = timestampMs;
    }
    if (durationMs != null) {
      $result.durationMs = durationMs;
    }
    return $result;
  }
  SpeechActivityEvent._() : super();
  factory SpeechActivityEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SpeechActivityEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SpeechActivityEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<SpeechActivityKind>(1, _omitFieldNames ? '' : 'eventType', $pb.PbFieldType.OE, defaultOrMaker: SpeechActivityKind.SPEECH_ACTIVITY_KIND_UNSPECIFIED, valueOf: SpeechActivityKind.valueOf, enumValues: SpeechActivityKind.values)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampMs')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'durationMs', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SpeechActivityEvent clone() => SpeechActivityEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SpeechActivityEvent copyWith(void Function(SpeechActivityEvent) updates) => super.copyWith((message) => updates(message as SpeechActivityEvent)) as SpeechActivityEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SpeechActivityEvent create() => SpeechActivityEvent._();
  SpeechActivityEvent createEmptyInstance() => create();
  static $pb.PbList<SpeechActivityEvent> createRepeated() => $pb.PbList<SpeechActivityEvent>();
  @$core.pragma('dart2js:noInline')
  static SpeechActivityEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SpeechActivityEvent>(create);
  static SpeechActivityEvent? _defaultInstance;

  /// Which transition happened.
  @$pb.TagNumber(1)
  SpeechActivityKind get eventType => $_getN(0);
  @$pb.TagNumber(1)
  set eventType(SpeechActivityKind v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasEventType() => $_has(0);
  @$pb.TagNumber(1)
  void clearEventType() => clearField(1);

  /// Wall-clock time of the transition, in milliseconds since epoch.
  /// Aligns with rac_vad_output_t::timestamp_ms.
  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampMs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampMs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTimestampMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampMs() => clearField(2);

  /// Optional duration of the speech / silence that triggered this event,
  /// in milliseconds. Set on SPEECH_ENDED to communicate the just-finished
  /// utterance length; left zero on SPEECH_STARTED.
  @$pb.TagNumber(3)
  $core.int get durationMs => $_getIZ(2);
  @$pb.TagNumber(3)
  set durationMs($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDurationMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearDurationMs() => clearField(3);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
