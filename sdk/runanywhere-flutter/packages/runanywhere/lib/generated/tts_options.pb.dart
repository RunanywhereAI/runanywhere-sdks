//
//  Generated code. Do not modify.
//  source: tts_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'model_types.pbenum.dart' as $0;
import 'tts_options.pbenum.dart';

export 'tts_options.pbenum.dart';

///  ---------------------------------------------------------------------------
///  Component-level TTS configuration.
///
///  Mirrors the C ABI rac_tts_config_t exactly (minus preferred_framework, which
///  is a runtime hint, not part of the wire contract). Field names match Swift
///  TTSConfiguration / Kotlin TTSConfiguration.
///
///  Defaults (for documentation; proto3 zero-values apply on the wire):
///    voice              = "default"  (Kotlin) / "com.apple.ttsbundle..." (Swift)
///    language_code      = "en-US"
///    speaking_rate      = 1.0   (range 0.5 – 2.0)
///    pitch              = 1.0   (range 0.5 – 2.0)
///    volume             = 1.0   (range 0.0 – 1.0)
///    audio_format       = AUDIO_FORMAT_PCM
///    sample_rate        = 22050 (RAC_TTS_DEFAULT_SAMPLE_RATE)
///    enable_neural_voice= true
///    enable_ssml        = false
///  ---------------------------------------------------------------------------
class TTSConfiguration extends $pb.GeneratedMessage {
  factory TTSConfiguration({
    $core.String? modelId,
    $core.String? voice,
    $core.String? languageCode,
    $core.double? speakingRate,
    $core.double? pitch,
    $core.double? volume,
    $0.AudioFormat? audioFormat,
    $core.int? sampleRate,
    $core.bool? enableNeuralVoice,
    $core.bool? enableSsml,
    $0.InferenceFramework? preferredFramework,
  }) {
    final $result = create();
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (voice != null) {
      $result.voice = voice;
    }
    if (languageCode != null) {
      $result.languageCode = languageCode;
    }
    if (speakingRate != null) {
      $result.speakingRate = speakingRate;
    }
    if (pitch != null) {
      $result.pitch = pitch;
    }
    if (volume != null) {
      $result.volume = volume;
    }
    if (audioFormat != null) {
      $result.audioFormat = audioFormat;
    }
    if (sampleRate != null) {
      $result.sampleRate = sampleRate;
    }
    if (enableNeuralVoice != null) {
      $result.enableNeuralVoice = enableNeuralVoice;
    }
    if (enableSsml != null) {
      $result.enableSsml = enableSsml;
    }
    if (preferredFramework != null) {
      $result.preferredFramework = preferredFramework;
    }
    return $result;
  }
  TTSConfiguration._() : super();
  factory TTSConfiguration.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TTSConfiguration.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TTSConfiguration', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aOS(2, _omitFieldNames ? '' : 'voice')
    ..aOS(3, _omitFieldNames ? '' : 'languageCode')
    ..a<$core.double>(4, _omitFieldNames ? '' : 'speakingRate', $pb.PbFieldType.OF)
    ..a<$core.double>(5, _omitFieldNames ? '' : 'pitch', $pb.PbFieldType.OF)
    ..a<$core.double>(6, _omitFieldNames ? '' : 'volume', $pb.PbFieldType.OF)
    ..e<$0.AudioFormat>(7, _omitFieldNames ? '' : 'audioFormat', $pb.PbFieldType.OE, defaultOrMaker: $0.AudioFormat.AUDIO_FORMAT_UNSPECIFIED, valueOf: $0.AudioFormat.valueOf, enumValues: $0.AudioFormat.values)
    ..a<$core.int>(8, _omitFieldNames ? '' : 'sampleRate', $pb.PbFieldType.O3)
    ..aOB(9, _omitFieldNames ? '' : 'enableNeuralVoice')
    ..aOB(10, _omitFieldNames ? '' : 'enableSsml')
    ..e<$0.InferenceFramework>(11, _omitFieldNames ? '' : 'preferredFramework', $pb.PbFieldType.OE, defaultOrMaker: $0.InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED, valueOf: $0.InferenceFramework.valueOf, enumValues: $0.InferenceFramework.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TTSConfiguration clone() => TTSConfiguration()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TTSConfiguration copyWith(void Function(TTSConfiguration) updates) => super.copyWith((message) => updates(message as TTSConfiguration)) as TTSConfiguration;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TTSConfiguration create() => TTSConfiguration._();
  TTSConfiguration createEmptyInstance() => create();
  static $pb.PbList<TTSConfiguration> createRepeated() => $pb.PbList<TTSConfiguration>();
  @$core.pragma('dart2js:noInline')
  static TTSConfiguration getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TTSConfiguration>(create);
  static TTSConfiguration? _defaultInstance;

  /// Model identifier (voice model file id, e.g. piper voice). Optional —
  /// platform TTS engines (Apple System TTS, Android TextToSpeech) don't
  /// require a model file.
  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => clearField(1);

  /// Voice identifier to use for synthesis. For platform engines this is the
  /// engine-specific voice id (e.g. "com.apple.ttsbundle.siri_female_en-US_compact").
  @$pb.TagNumber(2)
  $core.String get voice => $_getSZ(1);
  @$pb.TagNumber(2)
  set voice($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasVoice() => $_has(1);
  @$pb.TagNumber(2)
  void clearVoice() => clearField(2);

  /// Language for synthesis (BCP-47, e.g. "en-US").
  @$pb.TagNumber(3)
  $core.String get languageCode => $_getSZ(2);
  @$pb.TagNumber(3)
  set languageCode($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasLanguageCode() => $_has(2);
  @$pb.TagNumber(3)
  void clearLanguageCode() => clearField(3);

  /// Speaking rate (0.5 – 2.0; 1.0 is normal).
  @$pb.TagNumber(4)
  $core.double get speakingRate => $_getN(3);
  @$pb.TagNumber(4)
  set speakingRate($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSpeakingRate() => $_has(3);
  @$pb.TagNumber(4)
  void clearSpeakingRate() => clearField(4);

  /// Speech pitch (0.5 – 2.0; 1.0 is normal).
  @$pb.TagNumber(5)
  $core.double get pitch => $_getN(4);
  @$pb.TagNumber(5)
  set pitch($core.double v) { $_setFloat(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasPitch() => $_has(4);
  @$pb.TagNumber(5)
  void clearPitch() => clearField(5);

  /// Speech volume (0.0 – 1.0).
  @$pb.TagNumber(6)
  $core.double get volume => $_getN(5);
  @$pb.TagNumber(6)
  set volume($core.double v) { $_setFloat(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasVolume() => $_has(5);
  @$pb.TagNumber(6)
  void clearVolume() => clearField(6);

  /// Output audio format.
  @$pb.TagNumber(7)
  $0.AudioFormat get audioFormat => $_getN(6);
  @$pb.TagNumber(7)
  set audioFormat($0.AudioFormat v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasAudioFormat() => $_has(6);
  @$pb.TagNumber(7)
  void clearAudioFormat() => clearField(7);

  /// Sample rate for output audio in Hz. 0 = engine default
  /// (RAC_TTS_DEFAULT_SAMPLE_RATE = 22050).
  @$pb.TagNumber(8)
  $core.int get sampleRate => $_getIZ(7);
  @$pb.TagNumber(8)
  set sampleRate($core.int v) { $_setSignedInt32(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasSampleRate() => $_has(7);
  @$pb.TagNumber(8)
  void clearSampleRate() => clearField(8);

  /// Whether to use neural / premium voice if available.
  @$pb.TagNumber(9)
  $core.bool get enableNeuralVoice => $_getBF(8);
  @$pb.TagNumber(9)
  set enableNeuralVoice($core.bool v) { $_setBool(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasEnableNeuralVoice() => $_has(8);
  @$pb.TagNumber(9)
  void clearEnableNeuralVoice() => clearField(9);

  /// Whether to enable SSML markup support.
  @$pb.TagNumber(10)
  $core.bool get enableSsml => $_getBF(9);
  @$pb.TagNumber(10)
  set enableSsml($core.bool v) { $_setBool(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasEnableSsml() => $_has(9);
  @$pb.TagNumber(10)
  void clearEnableSsml() => clearField(10);

  /// Preferred framework for the component. Absent = auto. Mirrors the C
  /// ABI rac_tts_config_t preferred_framework field.
  @$pb.TagNumber(11)
  $0.InferenceFramework get preferredFramework => $_getN(10);
  @$pb.TagNumber(11)
  set preferredFramework($0.InferenceFramework v) { setField(11, v); }
  @$pb.TagNumber(11)
  $core.bool hasPreferredFramework() => $_has(10);
  @$pb.TagNumber(11)
  void clearPreferredFramework() => clearField(11);
}

///  ---------------------------------------------------------------------------
///  Per-call TTS synthesis options.
///
///  Mirrors the C ABI rac_tts_options_t exactly. Field names match Swift
///  TTSOptions / Kotlin TTSOptions / Dart TTSOptions.
///
///  Note: `voice` is optional at the source (Swift `String?`, C `const char* =
///  NULL`). On the wire, an empty string MUST be interpreted as "use the
///  component's configured voice".
///  ---------------------------------------------------------------------------
class TTSOptions extends $pb.GeneratedMessage {
  factory TTSOptions({
    $core.String? voice,
    $core.String? languageCode,
    $core.double? speakingRate,
    $core.double? pitch,
    $core.double? volume,
    $core.bool? enableSsml,
    $0.AudioFormat? audioFormat,
    $core.int? sampleRate,
    $core.int? speakerId,
    $core.double? speed,
    $core.String? style,
  }) {
    final $result = create();
    if (voice != null) {
      $result.voice = voice;
    }
    if (languageCode != null) {
      $result.languageCode = languageCode;
    }
    if (speakingRate != null) {
      $result.speakingRate = speakingRate;
    }
    if (pitch != null) {
      $result.pitch = pitch;
    }
    if (volume != null) {
      $result.volume = volume;
    }
    if (enableSsml != null) {
      $result.enableSsml = enableSsml;
    }
    if (audioFormat != null) {
      $result.audioFormat = audioFormat;
    }
    if (sampleRate != null) {
      $result.sampleRate = sampleRate;
    }
    if (speakerId != null) {
      $result.speakerId = speakerId;
    }
    if (speed != null) {
      $result.speed = speed;
    }
    if (style != null) {
      $result.style = style;
    }
    return $result;
  }
  TTSOptions._() : super();
  factory TTSOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TTSOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TTSOptions', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'voice')
    ..aOS(2, _omitFieldNames ? '' : 'languageCode')
    ..a<$core.double>(3, _omitFieldNames ? '' : 'speakingRate', $pb.PbFieldType.OF)
    ..a<$core.double>(4, _omitFieldNames ? '' : 'pitch', $pb.PbFieldType.OF)
    ..a<$core.double>(5, _omitFieldNames ? '' : 'volume', $pb.PbFieldType.OF)
    ..aOB(6, _omitFieldNames ? '' : 'enableSsml')
    ..e<$0.AudioFormat>(7, _omitFieldNames ? '' : 'audioFormat', $pb.PbFieldType.OE, defaultOrMaker: $0.AudioFormat.AUDIO_FORMAT_UNSPECIFIED, valueOf: $0.AudioFormat.valueOf, enumValues: $0.AudioFormat.values)
    ..a<$core.int>(8, _omitFieldNames ? '' : 'sampleRate', $pb.PbFieldType.O3)
    ..a<$core.int>(9, _omitFieldNames ? '' : 'speakerId', $pb.PbFieldType.O3)
    ..a<$core.double>(10, _omitFieldNames ? '' : 'speed', $pb.PbFieldType.OF)
    ..aOS(11, _omitFieldNames ? '' : 'style')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TTSOptions clone() => TTSOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TTSOptions copyWith(void Function(TTSOptions) updates) => super.copyWith((message) => updates(message as TTSOptions)) as TTSOptions;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TTSOptions create() => TTSOptions._();
  TTSOptions createEmptyInstance() => create();
  static $pb.PbList<TTSOptions> createRepeated() => $pb.PbList<TTSOptions>();
  @$core.pragma('dart2js:noInline')
  static TTSOptions getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TTSOptions>(create);
  static TTSOptions? _defaultInstance;

  /// Voice override (empty = use component default).
  @$pb.TagNumber(1)
  $core.String get voice => $_getSZ(0);
  @$pb.TagNumber(1)
  set voice($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasVoice() => $_has(0);
  @$pb.TagNumber(1)
  void clearVoice() => clearField(1);

  /// Language override (BCP-47). Empty = use component default.
  @$pb.TagNumber(2)
  $core.String get languageCode => $_getSZ(1);
  @$pb.TagNumber(2)
  set languageCode($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasLanguageCode() => $_has(1);
  @$pb.TagNumber(2)
  void clearLanguageCode() => clearField(2);

  /// Speech rate (0.0 – 2.0; 1.0 is normal). Note Swift/Kotlin use the name
  /// `rate`, Dart uses `rate`, RN uses `rate`. C ABI field is `rate`. We
  /// canonicalize on `speaking_rate` to match TTSConfiguration; bindings
  /// alias to `rate` where appropriate.
  @$pb.TagNumber(3)
  $core.double get speakingRate => $_getN(2);
  @$pb.TagNumber(3)
  set speakingRate($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSpeakingRate() => $_has(2);
  @$pb.TagNumber(3)
  void clearSpeakingRate() => clearField(3);

  /// Speech pitch (0.5 – 2.0; 1.0 is normal).
  @$pb.TagNumber(4)
  $core.double get pitch => $_getN(3);
  @$pb.TagNumber(4)
  set pitch($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasPitch() => $_has(3);
  @$pb.TagNumber(4)
  void clearPitch() => clearField(4);

  /// Speech volume (0.0 – 1.0).
  @$pb.TagNumber(5)
  $core.double get volume => $_getN(4);
  @$pb.TagNumber(5)
  set volume($core.double v) { $_setFloat(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasVolume() => $_has(4);
  @$pb.TagNumber(5)
  void clearVolume() => clearField(5);

  /// Whether the input contains SSML markup. C ABI: `use_ssml`, Swift:
  /// `useSSML`, Kotlin: `useSSML`, Dart: `useSSML`. Canonicalized to
  /// `enable_ssml` for consistency with TTSConfiguration.
  @$pb.TagNumber(6)
  $core.bool get enableSsml => $_getBF(5);
  @$pb.TagNumber(6)
  set enableSsml($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasEnableSsml() => $_has(5);
  @$pb.TagNumber(6)
  void clearEnableSsml() => clearField(6);

  /// Output audio format.
  @$pb.TagNumber(7)
  $0.AudioFormat get audioFormat => $_getN(6);
  @$pb.TagNumber(7)
  set audioFormat($0.AudioFormat v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasAudioFormat() => $_has(6);
  @$pb.TagNumber(7)
  void clearAudioFormat() => clearField(7);

  /// Output sample rate override in Hz. 0 = component/default sample rate.
  /// Present in rac_tts_options_t and several SDK option structs.
  @$pb.TagNumber(8)
  $core.int get sampleRate => $_getIZ(7);
  @$pb.TagNumber(8)
  set sampleRate($core.int v) { $_setSignedInt32(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasSampleRate() => $_has(7);
  @$pb.TagNumber(8)
  void clearSampleRate() => clearField(8);

  /// Speaker index for multi-speaker voices. -1/0 = backend default
  /// depending on model convention.
  @$pb.TagNumber(9)
  $core.int get speakerId => $_getIZ(8);
  @$pb.TagNumber(9)
  set speakerId($core.int v) { $_setSignedInt32(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasSpeakerId() => $_has(8);
  @$pb.TagNumber(9)
  void clearSpeakerId() => clearField(9);

  /// Web/ONNX ergonomic alias for speaking_rate. 0.0 = use speaking_rate.
  @$pb.TagNumber(10)
  $core.double get speed => $_getN(9);
  @$pb.TagNumber(10)
  set speed($core.double v) { $_setFloat(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasSpeed() => $_has(9);
  @$pb.TagNumber(10)
  void clearSpeed() => clearField(10);

  /// Optional style/emotion hint for voices that support style transfer.
  @$pb.TagNumber(11)
  $core.String get style => $_getSZ(10);
  @$pb.TagNumber(11)
  set style($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasStyle() => $_has(10);
  @$pb.TagNumber(11)
  void clearStyle() => clearField(11);
}

class TTSSynthesisRequest extends $pb.GeneratedMessage {
  factory TTSSynthesisRequest({
    $core.String? requestId,
    $core.String? text,
    $core.String? ssml,
    TTSOptions? options,
    $core.Map<$core.String, $core.String>? metadata,
  }) {
    final $result = create();
    if (requestId != null) {
      $result.requestId = requestId;
    }
    if (text != null) {
      $result.text = text;
    }
    if (ssml != null) {
      $result.ssml = ssml;
    }
    if (options != null) {
      $result.options = options;
    }
    if (metadata != null) {
      $result.metadata.addAll(metadata);
    }
    return $result;
  }
  TTSSynthesisRequest._() : super();
  factory TTSSynthesisRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TTSSynthesisRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TTSSynthesisRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOS(2, _omitFieldNames ? '' : 'text')
    ..aOS(3, _omitFieldNames ? '' : 'ssml')
    ..aOM<TTSOptions>(4, _omitFieldNames ? '' : 'options', subBuilder: TTSOptions.create)
    ..m<$core.String, $core.String>(5, _omitFieldNames ? '' : 'metadata', entryClassName: 'TTSSynthesisRequest.MetadataEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TTSSynthesisRequest clone() => TTSSynthesisRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TTSSynthesisRequest copyWith(void Function(TTSSynthesisRequest) updates) => super.copyWith((message) => updates(message as TTSSynthesisRequest)) as TTSSynthesisRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TTSSynthesisRequest create() => TTSSynthesisRequest._();
  TTSSynthesisRequest createEmptyInstance() => create();
  static $pb.PbList<TTSSynthesisRequest> createRepeated() => $pb.PbList<TTSSynthesisRequest>();
  @$core.pragma('dart2js:noInline')
  static TTSSynthesisRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TTSSynthesisRequest>(create);
  static TTSSynthesisRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get text => $_getSZ(1);
  @$pb.TagNumber(2)
  set text($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get ssml => $_getSZ(2);
  @$pb.TagNumber(3)
  set ssml($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSsml() => $_has(2);
  @$pb.TagNumber(3)
  void clearSsml() => clearField(3);

  @$pb.TagNumber(4)
  TTSOptions get options => $_getN(3);
  @$pb.TagNumber(4)
  set options(TTSOptions v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasOptions() => $_has(3);
  @$pb.TagNumber(4)
  void clearOptions() => clearField(4);
  @$pb.TagNumber(4)
  TTSOptions ensureOptions() => $_ensure(3);

  @$pb.TagNumber(5)
  $core.Map<$core.String, $core.String> get metadata => $_getMap(4);
}

///  ---------------------------------------------------------------------------
///  Phoneme-level timestamp.
///
///  Mirrors the C ABI rac_tts_phoneme_timestamp_t exactly. Time units are
///  **milliseconds** on the wire (matches C ABI). Swift / Kotlin / Dart bindings
///  expose seconds (double) and convert at the binding boundary.
///  ---------------------------------------------------------------------------
class TTSPhonemeTimestamp extends $pb.GeneratedMessage {
  factory TTSPhonemeTimestamp({
    $core.String? phoneme,
    $fixnum.Int64? startMs,
    $fixnum.Int64? endMs,
  }) {
    final $result = create();
    if (phoneme != null) {
      $result.phoneme = phoneme;
    }
    if (startMs != null) {
      $result.startMs = startMs;
    }
    if (endMs != null) {
      $result.endMs = endMs;
    }
    return $result;
  }
  TTSPhonemeTimestamp._() : super();
  factory TTSPhonemeTimestamp.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TTSPhonemeTimestamp.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TTSPhonemeTimestamp', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'phoneme')
    ..aInt64(2, _omitFieldNames ? '' : 'startMs')
    ..aInt64(3, _omitFieldNames ? '' : 'endMs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TTSPhonemeTimestamp clone() => TTSPhonemeTimestamp()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TTSPhonemeTimestamp copyWith(void Function(TTSPhonemeTimestamp) updates) => super.copyWith((message) => updates(message as TTSPhonemeTimestamp)) as TTSPhonemeTimestamp;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TTSPhonemeTimestamp create() => TTSPhonemeTimestamp._();
  TTSPhonemeTimestamp createEmptyInstance() => create();
  static $pb.PbList<TTSPhonemeTimestamp> createRepeated() => $pb.PbList<TTSPhonemeTimestamp>();
  @$core.pragma('dart2js:noInline')
  static TTSPhonemeTimestamp getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TTSPhonemeTimestamp>(create);
  static TTSPhonemeTimestamp? _defaultInstance;

  /// The phoneme symbol (IPA or engine-specific).
  @$pb.TagNumber(1)
  $core.String get phoneme => $_getSZ(0);
  @$pb.TagNumber(1)
  set phoneme($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPhoneme() => $_has(0);
  @$pb.TagNumber(1)
  void clearPhoneme() => clearField(1);

  /// Start time within the synthesized audio, in milliseconds.
  @$pb.TagNumber(2)
  $fixnum.Int64 get startMs => $_getI64(1);
  @$pb.TagNumber(2)
  set startMs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasStartMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearStartMs() => clearField(2);

  /// End time within the synthesized audio, in milliseconds.
  @$pb.TagNumber(3)
  $fixnum.Int64 get endMs => $_getI64(2);
  @$pb.TagNumber(3)
  set endMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasEndMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearEndMs() => clearField(3);
}

///  ---------------------------------------------------------------------------
///  Synthesis metadata.
///
///  Mirrors the C ABI rac_tts_synthesis_metadata_t. Time units in milliseconds
///  and durations as int64 to match the C ABI.
///  ---------------------------------------------------------------------------
class TTSSynthesisMetadata extends $pb.GeneratedMessage {
  factory TTSSynthesisMetadata({
    $core.String? voiceId,
    $core.String? languageCode,
    $fixnum.Int64? processingTimeMs,
    $core.int? characterCount,
    $fixnum.Int64? audioDurationMs,
    $core.double? charactersPerSecond,
  }) {
    final $result = create();
    if (voiceId != null) {
      $result.voiceId = voiceId;
    }
    if (languageCode != null) {
      $result.languageCode = languageCode;
    }
    if (processingTimeMs != null) {
      $result.processingTimeMs = processingTimeMs;
    }
    if (characterCount != null) {
      $result.characterCount = characterCount;
    }
    if (audioDurationMs != null) {
      $result.audioDurationMs = audioDurationMs;
    }
    if (charactersPerSecond != null) {
      $result.charactersPerSecond = charactersPerSecond;
    }
    return $result;
  }
  TTSSynthesisMetadata._() : super();
  factory TTSSynthesisMetadata.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TTSSynthesisMetadata.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TTSSynthesisMetadata', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'voiceId')
    ..aOS(2, _omitFieldNames ? '' : 'languageCode')
    ..aInt64(3, _omitFieldNames ? '' : 'processingTimeMs')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'characterCount', $pb.PbFieldType.O3)
    ..aInt64(5, _omitFieldNames ? '' : 'audioDurationMs')
    ..a<$core.double>(6, _omitFieldNames ? '' : 'charactersPerSecond', $pb.PbFieldType.OF)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TTSSynthesisMetadata clone() => TTSSynthesisMetadata()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TTSSynthesisMetadata copyWith(void Function(TTSSynthesisMetadata) updates) => super.copyWith((message) => updates(message as TTSSynthesisMetadata)) as TTSSynthesisMetadata;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TTSSynthesisMetadata create() => TTSSynthesisMetadata._();
  TTSSynthesisMetadata createEmptyInstance() => create();
  static $pb.PbList<TTSSynthesisMetadata> createRepeated() => $pb.PbList<TTSSynthesisMetadata>();
  @$core.pragma('dart2js:noInline')
  static TTSSynthesisMetadata getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TTSSynthesisMetadata>(create);
  static TTSSynthesisMetadata? _defaultInstance;

  /// Voice id used for synthesis.
  @$pb.TagNumber(1)
  $core.String get voiceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set voiceId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasVoiceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearVoiceId() => clearField(1);

  /// Language used for synthesis (BCP-47). Source field name varies:
  /// C ABI: `language`, Swift: `language`, Kotlin: `language`. We use
  /// `language_code` to match TTSConfiguration / TTSOptions.
  @$pb.TagNumber(2)
  $core.String get languageCode => $_getSZ(1);
  @$pb.TagNumber(2)
  set languageCode($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasLanguageCode() => $_has(1);
  @$pb.TagNumber(2)
  void clearLanguageCode() => clearField(2);

  /// Wall-clock processing time in milliseconds.
  @$pb.TagNumber(3)
  $fixnum.Int64 get processingTimeMs => $_getI64(2);
  @$pb.TagNumber(3)
  set processingTimeMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasProcessingTimeMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearProcessingTimeMs() => clearField(3);

  /// Number of input characters synthesized.
  @$pb.TagNumber(4)
  $core.int get characterCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set characterCount($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasCharacterCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearCharacterCount() => clearField(4);

  /// Audio duration in milliseconds. Present in C ABI rac_tts_output_t but
  /// mirrored here so metadata is self-describing for clients that consume
  /// metadata-only paths (e.g. TTSSpeakResult).
  @$pb.TagNumber(5)
  $fixnum.Int64 get audioDurationMs => $_getI64(4);
  @$pb.TagNumber(5)
  set audioDurationMs($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAudioDurationMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearAudioDurationMs() => clearField(5);

  /// Characters processed per second. Some native paths expose this directly;
  /// consumers may also compute it from character_count / processing_time_ms.
  @$pb.TagNumber(6)
  $core.double get charactersPerSecond => $_getN(5);
  @$pb.TagNumber(6)
  set charactersPerSecond($core.double v) { $_setFloat(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasCharactersPerSecond() => $_has(5);
  @$pb.TagNumber(6)
  void clearCharactersPerSecond() => clearField(6);
}

///  ---------------------------------------------------------------------------
///  Full TTS output: synthesized audio plus metadata.
///
///  Mirrors the C ABI rac_tts_output_t. `audio_data` is opaque bytes; bindings
///  adapt to native buffers (Swift Data, Kotlin ByteArray, Dart Uint8List,
///  JS ArrayBuffer/Float32Array, C void*). Sample rate is required because PCM
///  payloads are otherwise unparseable.
///  ---------------------------------------------------------------------------
class TTSOutput extends $pb.GeneratedMessage {
  factory TTSOutput({
    $core.List<$core.int>? audioData,
    $0.AudioFormat? audioFormat,
    $core.int? sampleRate,
    $fixnum.Int64? durationMs,
    $core.Iterable<TTSPhonemeTimestamp>? phonemeTimestamps,
    TTSSynthesisMetadata? metadata,
    $fixnum.Int64? timestampMs,
    $core.int? chunkIndex,
    $core.bool? isFinal,
    $fixnum.Int64? audioSizeBytes,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final $result = create();
    if (audioData != null) {
      $result.audioData = audioData;
    }
    if (audioFormat != null) {
      $result.audioFormat = audioFormat;
    }
    if (sampleRate != null) {
      $result.sampleRate = sampleRate;
    }
    if (durationMs != null) {
      $result.durationMs = durationMs;
    }
    if (phonemeTimestamps != null) {
      $result.phonemeTimestamps.addAll(phonemeTimestamps);
    }
    if (metadata != null) {
      $result.metadata = metadata;
    }
    if (timestampMs != null) {
      $result.timestampMs = timestampMs;
    }
    if (chunkIndex != null) {
      $result.chunkIndex = chunkIndex;
    }
    if (isFinal != null) {
      $result.isFinal = isFinal;
    }
    if (audioSizeBytes != null) {
      $result.audioSizeBytes = audioSizeBytes;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    return $result;
  }
  TTSOutput._() : super();
  factory TTSOutput.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TTSOutput.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TTSOutput', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'audioData', $pb.PbFieldType.OY)
    ..e<$0.AudioFormat>(2, _omitFieldNames ? '' : 'audioFormat', $pb.PbFieldType.OE, defaultOrMaker: $0.AudioFormat.AUDIO_FORMAT_UNSPECIFIED, valueOf: $0.AudioFormat.valueOf, enumValues: $0.AudioFormat.values)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'sampleRate', $pb.PbFieldType.O3)
    ..aInt64(4, _omitFieldNames ? '' : 'durationMs')
    ..pc<TTSPhonemeTimestamp>(5, _omitFieldNames ? '' : 'phonemeTimestamps', $pb.PbFieldType.PM, subBuilder: TTSPhonemeTimestamp.create)
    ..aOM<TTSSynthesisMetadata>(6, _omitFieldNames ? '' : 'metadata', subBuilder: TTSSynthesisMetadata.create)
    ..aInt64(7, _omitFieldNames ? '' : 'timestampMs')
    ..a<$core.int>(8, _omitFieldNames ? '' : 'chunkIndex', $pb.PbFieldType.O3)
    ..aOB(9, _omitFieldNames ? '' : 'isFinal')
    ..aInt64(10, _omitFieldNames ? '' : 'audioSizeBytes')
    ..aOS(11, _omitFieldNames ? '' : 'errorMessage')
    ..a<$core.int>(12, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TTSOutput clone() => TTSOutput()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TTSOutput copyWith(void Function(TTSOutput) updates) => super.copyWith((message) => updates(message as TTSOutput)) as TTSOutput;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TTSOutput create() => TTSOutput._();
  TTSOutput createEmptyInstance() => create();
  static $pb.PbList<TTSOutput> createRepeated() => $pb.PbList<TTSOutput>();
  @$core.pragma('dart2js:noInline')
  static TTSOutput getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TTSOutput>(create);
  static TTSOutput? _defaultInstance;

  /// Synthesized audio bytes, encoded per `audio_format`.
  @$pb.TagNumber(1)
  $core.List<$core.int> get audioData => $_getN(0);
  @$pb.TagNumber(1)
  set audioData($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAudioData() => $_has(0);
  @$pb.TagNumber(1)
  void clearAudioData() => clearField(1);

  /// Audio format of the bytes in `audio_data`.
  @$pb.TagNumber(2)
  $0.AudioFormat get audioFormat => $_getN(1);
  @$pb.TagNumber(2)
  set audioFormat($0.AudioFormat v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasAudioFormat() => $_has(1);
  @$pb.TagNumber(2)
  void clearAudioFormat() => clearField(2);

  /// Sample rate in Hz. For PCM payloads this is required to interpret the
  /// bytes; for compressed formats (mp3, opus, …) it reflects the synthesis
  /// sample rate, not the container rate.
  @$pb.TagNumber(3)
  $core.int get sampleRate => $_getIZ(2);
  @$pb.TagNumber(3)
  set sampleRate($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSampleRate() => $_has(2);
  @$pb.TagNumber(3)
  void clearSampleRate() => clearField(3);

  /// Audio duration in milliseconds (matches C ABI `duration_ms`).
  @$pb.TagNumber(4)
  $fixnum.Int64 get durationMs => $_getI64(3);
  @$pb.TagNumber(4)
  set durationMs($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasDurationMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearDurationMs() => clearField(4);

  /// Phoneme-level timestamps, if the engine produced them. May be empty.
  @$pb.TagNumber(5)
  $core.List<TTSPhonemeTimestamp> get phonemeTimestamps => $_getList(4);

  /// Per-pass synthesis metadata.
  @$pb.TagNumber(6)
  TTSSynthesisMetadata get metadata => $_getN(5);
  @$pb.TagNumber(6)
  set metadata(TTSSynthesisMetadata v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasMetadata() => $_has(5);
  @$pb.TagNumber(6)
  void clearMetadata() => clearField(6);
  @$pb.TagNumber(6)
  TTSSynthesisMetadata ensureMetadata() => $_ensure(5);

  /// Wall-clock timestamp when the output was produced
  /// (milliseconds since UNIX epoch). Mirrors C ABI `timestamp_ms`.
  @$pb.TagNumber(7)
  $fixnum.Int64 get timestampMs => $_getI64(6);
  @$pb.TagNumber(7)
  set timestampMs($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasTimestampMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearTimestampMs() => clearField(7);

  /// Stream chunk metadata. For one-shot synthesis, chunk_index=0 and
  /// is_final=true when set by the producer.
  @$pb.TagNumber(8)
  $core.int get chunkIndex => $_getIZ(7);
  @$pb.TagNumber(8)
  set chunkIndex($core.int v) { $_setSignedInt32(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasChunkIndex() => $_has(7);
  @$pb.TagNumber(8)
  void clearChunkIndex() => clearField(8);

  @$pb.TagNumber(9)
  $core.bool get isFinal => $_getBF(8);
  @$pb.TagNumber(9)
  set isFinal($core.bool v) { $_setBool(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasIsFinal() => $_has(8);
  @$pb.TagNumber(9)
  void clearIsFinal() => clearField(9);

  @$pb.TagNumber(10)
  $fixnum.Int64 get audioSizeBytes => $_getI64(9);
  @$pb.TagNumber(10)
  set audioSizeBytes($fixnum.Int64 v) { $_setInt64(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasAudioSizeBytes() => $_has(9);
  @$pb.TagNumber(10)
  void clearAudioSizeBytes() => clearField(10);

  /// Terminal error details for result-envelope APIs.
  @$pb.TagNumber(11)
  $core.String get errorMessage => $_getSZ(10);
  @$pb.TagNumber(11)
  set errorMessage($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasErrorMessage() => $_has(10);
  @$pb.TagNumber(11)
  void clearErrorMessage() => clearField(11);

  @$pb.TagNumber(12)
  $core.int get errorCode => $_getIZ(11);
  @$pb.TagNumber(12)
  set errorCode($core.int v) { $_setSignedInt32(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasErrorCode() => $_has(11);
  @$pb.TagNumber(12)
  void clearErrorCode() => clearField(12);
}

///  ---------------------------------------------------------------------------
///  Result of a `speak()` call — metadata-only view of an already-played
///  synthesis pass. Used when the SDK plays audio internally and the caller
///  does not need raw bytes.
///
///  Mirrors the C ABI rac_tts_speak_result_t. Identical to TTSOutput minus
///  `audio_data` and `phoneme_timestamps`; `audio_size_bytes` is retained for
///  callers that want to know how much was synthesized.
///  ---------------------------------------------------------------------------
class TTSSpeakResult extends $pb.GeneratedMessage {
  factory TTSSpeakResult({
    $0.AudioFormat? audioFormat,
    $core.int? sampleRate,
    $fixnum.Int64? durationMs,
    $fixnum.Int64? audioSizeBytes,
    TTSSynthesisMetadata? metadata,
    $fixnum.Int64? timestampMs,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final $result = create();
    if (audioFormat != null) {
      $result.audioFormat = audioFormat;
    }
    if (sampleRate != null) {
      $result.sampleRate = sampleRate;
    }
    if (durationMs != null) {
      $result.durationMs = durationMs;
    }
    if (audioSizeBytes != null) {
      $result.audioSizeBytes = audioSizeBytes;
    }
    if (metadata != null) {
      $result.metadata = metadata;
    }
    if (timestampMs != null) {
      $result.timestampMs = timestampMs;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    return $result;
  }
  TTSSpeakResult._() : super();
  factory TTSSpeakResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TTSSpeakResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TTSSpeakResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<$0.AudioFormat>(1, _omitFieldNames ? '' : 'audioFormat', $pb.PbFieldType.OE, defaultOrMaker: $0.AudioFormat.AUDIO_FORMAT_UNSPECIFIED, valueOf: $0.AudioFormat.valueOf, enumValues: $0.AudioFormat.values)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'sampleRate', $pb.PbFieldType.O3)
    ..aInt64(3, _omitFieldNames ? '' : 'durationMs')
    ..aInt64(4, _omitFieldNames ? '' : 'audioSizeBytes')
    ..aOM<TTSSynthesisMetadata>(5, _omitFieldNames ? '' : 'metadata', subBuilder: TTSSynthesisMetadata.create)
    ..aInt64(6, _omitFieldNames ? '' : 'timestampMs')
    ..aOS(7, _omitFieldNames ? '' : 'errorMessage')
    ..a<$core.int>(8, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TTSSpeakResult clone() => TTSSpeakResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TTSSpeakResult copyWith(void Function(TTSSpeakResult) updates) => super.copyWith((message) => updates(message as TTSSpeakResult)) as TTSSpeakResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TTSSpeakResult create() => TTSSpeakResult._();
  TTSSpeakResult createEmptyInstance() => create();
  static $pb.PbList<TTSSpeakResult> createRepeated() => $pb.PbList<TTSSpeakResult>();
  @$core.pragma('dart2js:noInline')
  static TTSSpeakResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TTSSpeakResult>(create);
  static TTSSpeakResult? _defaultInstance;

  /// Audio format used during synthesis.
  @$pb.TagNumber(1)
  $0.AudioFormat get audioFormat => $_getN(0);
  @$pb.TagNumber(1)
  set audioFormat($0.AudioFormat v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasAudioFormat() => $_has(0);
  @$pb.TagNumber(1)
  void clearAudioFormat() => clearField(1);

  /// Sample rate in Hz used during synthesis.
  @$pb.TagNumber(2)
  $core.int get sampleRate => $_getIZ(1);
  @$pb.TagNumber(2)
  set sampleRate($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSampleRate() => $_has(1);
  @$pb.TagNumber(2)
  void clearSampleRate() => clearField(2);

  /// Audio duration in milliseconds.
  @$pb.TagNumber(3)
  $fixnum.Int64 get durationMs => $_getI64(2);
  @$pb.TagNumber(3)
  set durationMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDurationMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearDurationMs() => clearField(3);

  /// Audio size in bytes (0 for system TTS that plays directly without
  /// exposing buffers).
  @$pb.TagNumber(4)
  $fixnum.Int64 get audioSizeBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set audioSizeBytes($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAudioSizeBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearAudioSizeBytes() => clearField(4);

  /// Per-pass synthesis metadata.
  @$pb.TagNumber(5)
  TTSSynthesisMetadata get metadata => $_getN(4);
  @$pb.TagNumber(5)
  set metadata(TTSSynthesisMetadata v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasMetadata() => $_has(4);
  @$pb.TagNumber(5)
  void clearMetadata() => clearField(5);
  @$pb.TagNumber(5)
  TTSSynthesisMetadata ensureMetadata() => $_ensure(4);

  /// Wall-clock timestamp when speech completed (ms since UNIX epoch).
  @$pb.TagNumber(6)
  $fixnum.Int64 get timestampMs => $_getI64(5);
  @$pb.TagNumber(6)
  set timestampMs($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTimestampMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearTimestampMs() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get errorMessage => $_getSZ(6);
  @$pb.TagNumber(7)
  set errorMessage($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasErrorMessage() => $_has(6);
  @$pb.TagNumber(7)
  void clearErrorMessage() => clearField(7);

  @$pb.TagNumber(8)
  $core.int get errorCode => $_getIZ(7);
  @$pb.TagNumber(8)
  set errorCode($core.int v) { $_setSignedInt32(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasErrorCode() => $_has(7);
  @$pb.TagNumber(8)
  void clearErrorCode() => clearField(8);
}

///  ---------------------------------------------------------------------------
///  Descriptor for a TTS voice the engine can use.
///
///  Pre-IDL only RN exposed this (TTSTypes.ts:106). Canonicalized here so all
///  SDKs gain a typed voice-listing API. `gender` uses an enum to avoid the
///  string-typed drift that RN had ('male' | 'female' | 'neutral').
///  ---------------------------------------------------------------------------
class TTSVoiceInfo extends $pb.GeneratedMessage {
  factory TTSVoiceInfo({
    $core.String? id,
    $core.String? displayName,
    $core.String? languageCode,
    TTSVoiceGender? gender,
    $core.String? description,
    $core.bool? isNeural,
    $core.bool? isSystem,
    $core.int? sampleRate,
    $core.Iterable<$core.String>? supportedStyles,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (displayName != null) {
      $result.displayName = displayName;
    }
    if (languageCode != null) {
      $result.languageCode = languageCode;
    }
    if (gender != null) {
      $result.gender = gender;
    }
    if (description != null) {
      $result.description = description;
    }
    if (isNeural != null) {
      $result.isNeural = isNeural;
    }
    if (isSystem != null) {
      $result.isSystem = isSystem;
    }
    if (sampleRate != null) {
      $result.sampleRate = sampleRate;
    }
    if (supportedStyles != null) {
      $result.supportedStyles.addAll(supportedStyles);
    }
    return $result;
  }
  TTSVoiceInfo._() : super();
  factory TTSVoiceInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TTSVoiceInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TTSVoiceInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'displayName')
    ..aOS(3, _omitFieldNames ? '' : 'languageCode')
    ..e<TTSVoiceGender>(4, _omitFieldNames ? '' : 'gender', $pb.PbFieldType.OE, defaultOrMaker: TTSVoiceGender.TTS_VOICE_GENDER_UNSPECIFIED, valueOf: TTSVoiceGender.valueOf, enumValues: TTSVoiceGender.values)
    ..aOS(5, _omitFieldNames ? '' : 'description')
    ..aOB(6, _omitFieldNames ? '' : 'isNeural')
    ..aOB(7, _omitFieldNames ? '' : 'isSystem')
    ..a<$core.int>(8, _omitFieldNames ? '' : 'sampleRate', $pb.PbFieldType.O3)
    ..pPS(9, _omitFieldNames ? '' : 'supportedStyles')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TTSVoiceInfo clone() => TTSVoiceInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TTSVoiceInfo copyWith(void Function(TTSVoiceInfo) updates) => super.copyWith((message) => updates(message as TTSVoiceInfo)) as TTSVoiceInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TTSVoiceInfo create() => TTSVoiceInfo._();
  TTSVoiceInfo createEmptyInstance() => create();
  static $pb.PbList<TTSVoiceInfo> createRepeated() => $pb.PbList<TTSVoiceInfo>();
  @$core.pragma('dart2js:noInline')
  static TTSVoiceInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TTSVoiceInfo>(create);
  static TTSVoiceInfo? _defaultInstance;

  /// Engine-specific voice identifier (passed back as TTSOptions.voice or
  /// TTSConfiguration.voice).
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  /// Human-readable display name (e.g. "Samantha", "Daniel").
  @$pb.TagNumber(2)
  $core.String get displayName => $_getSZ(1);
  @$pb.TagNumber(2)
  set displayName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDisplayName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDisplayName() => clearField(2);

  /// Language spoken by this voice (BCP-47, e.g. "en-US").
  @$pb.TagNumber(3)
  $core.String get languageCode => $_getSZ(2);
  @$pb.TagNumber(3)
  set languageCode($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasLanguageCode() => $_has(2);
  @$pb.TagNumber(3)
  void clearLanguageCode() => clearField(3);

  /// Voice gender, when known.
  @$pb.TagNumber(4)
  TTSVoiceGender get gender => $_getN(3);
  @$pb.TagNumber(4)
  set gender(TTSVoiceGender v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasGender() => $_has(3);
  @$pb.TagNumber(4)
  void clearGender() => clearField(4);

  /// Optional descriptive text (locale, age, style notes).
  @$pb.TagNumber(5)
  $core.String get description => $_getSZ(4);
  @$pb.TagNumber(5)
  set description($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasDescription() => $_has(4);
  @$pb.TagNumber(5)
  void clearDescription() => clearField(5);

  /// Additional discovery fields surfaced by system and ONNX/Piper voices.
  @$pb.TagNumber(6)
  $core.bool get isNeural => $_getBF(5);
  @$pb.TagNumber(6)
  set isNeural($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasIsNeural() => $_has(5);
  @$pb.TagNumber(6)
  void clearIsNeural() => clearField(6);

  @$pb.TagNumber(7)
  $core.bool get isSystem => $_getBF(6);
  @$pb.TagNumber(7)
  set isSystem($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasIsSystem() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsSystem() => clearField(7);

  @$pb.TagNumber(8)
  $core.int get sampleRate => $_getIZ(7);
  @$pb.TagNumber(8)
  set sampleRate($core.int v) { $_setSignedInt32(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasSampleRate() => $_has(7);
  @$pb.TagNumber(8)
  void clearSampleRate() => clearField(8);

  @$pb.TagNumber(9)
  $core.List<$core.String> get supportedStyles => $_getList(8);
}

class TTSStreamEvent extends $pb.GeneratedMessage {
  factory TTSStreamEvent({
    $fixnum.Int64? seq,
    $fixnum.Int64? timestampUs,
    $core.String? requestId,
    TTSStreamEventKind? kind,
    TTSOutput? output,
    TTSPhonemeTimestamp? phoneme,
    TTSSpeakResult? speakResult,
    $core.String? errorMessage,
    $core.int? errorCode,
    $core.double? progress,
    $core.int? chunkIndex,
    $core.int? totalChunks,
    $fixnum.Int64? elapsedMs,
    $core.String? statusMessage,
  }) {
    final $result = create();
    if (seq != null) {
      $result.seq = seq;
    }
    if (timestampUs != null) {
      $result.timestampUs = timestampUs;
    }
    if (requestId != null) {
      $result.requestId = requestId;
    }
    if (kind != null) {
      $result.kind = kind;
    }
    if (output != null) {
      $result.output = output;
    }
    if (phoneme != null) {
      $result.phoneme = phoneme;
    }
    if (speakResult != null) {
      $result.speakResult = speakResult;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    if (progress != null) {
      $result.progress = progress;
    }
    if (chunkIndex != null) {
      $result.chunkIndex = chunkIndex;
    }
    if (totalChunks != null) {
      $result.totalChunks = totalChunks;
    }
    if (elapsedMs != null) {
      $result.elapsedMs = elapsedMs;
    }
    if (statusMessage != null) {
      $result.statusMessage = statusMessage;
    }
    return $result;
  }
  TTSStreamEvent._() : super();
  factory TTSStreamEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TTSStreamEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TTSStreamEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(3, _omitFieldNames ? '' : 'requestId')
    ..e<TTSStreamEventKind>(4, _omitFieldNames ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: TTSStreamEventKind.TTS_STREAM_EVENT_KIND_UNSPECIFIED, valueOf: TTSStreamEventKind.valueOf, enumValues: TTSStreamEventKind.values)
    ..aOM<TTSOutput>(5, _omitFieldNames ? '' : 'output', subBuilder: TTSOutput.create)
    ..aOM<TTSPhonemeTimestamp>(6, _omitFieldNames ? '' : 'phoneme', subBuilder: TTSPhonemeTimestamp.create)
    ..aOM<TTSSpeakResult>(7, _omitFieldNames ? '' : 'speakResult', subBuilder: TTSSpeakResult.create)
    ..aOS(8, _omitFieldNames ? '' : 'errorMessage')
    ..a<$core.int>(9, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..a<$core.double>(10, _omitFieldNames ? '' : 'progress', $pb.PbFieldType.OF)
    ..a<$core.int>(11, _omitFieldNames ? '' : 'chunkIndex', $pb.PbFieldType.O3)
    ..a<$core.int>(12, _omitFieldNames ? '' : 'totalChunks', $pb.PbFieldType.O3)
    ..aInt64(13, _omitFieldNames ? '' : 'elapsedMs')
    ..aOS(14, _omitFieldNames ? '' : 'statusMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TTSStreamEvent clone() => TTSStreamEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TTSStreamEvent copyWith(void Function(TTSStreamEvent) updates) => super.copyWith((message) => updates(message as TTSStreamEvent)) as TTSStreamEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TTSStreamEvent create() => TTSStreamEvent._();
  TTSStreamEvent createEmptyInstance() => create();
  static $pb.PbList<TTSStreamEvent> createRepeated() => $pb.PbList<TTSStreamEvent>();
  @$core.pragma('dart2js:noInline')
  static TTSStreamEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TTSStreamEvent>(create);
  static TTSStreamEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get seq => $_getI64(0);
  @$pb.TagNumber(1)
  set seq($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampUs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampUs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTimestampUs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampUs() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get requestId => $_getSZ(2);
  @$pb.TagNumber(3)
  set requestId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRequestId() => $_has(2);
  @$pb.TagNumber(3)
  void clearRequestId() => clearField(3);

  @$pb.TagNumber(4)
  TTSStreamEventKind get kind => $_getN(3);
  @$pb.TagNumber(4)
  set kind(TTSStreamEventKind v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasKind() => $_has(3);
  @$pb.TagNumber(4)
  void clearKind() => clearField(4);

  @$pb.TagNumber(5)
  TTSOutput get output => $_getN(4);
  @$pb.TagNumber(5)
  set output(TTSOutput v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasOutput() => $_has(4);
  @$pb.TagNumber(5)
  void clearOutput() => clearField(5);
  @$pb.TagNumber(5)
  TTSOutput ensureOutput() => $_ensure(4);

  @$pb.TagNumber(6)
  TTSPhonemeTimestamp get phoneme => $_getN(5);
  @$pb.TagNumber(6)
  set phoneme(TTSPhonemeTimestamp v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasPhoneme() => $_has(5);
  @$pb.TagNumber(6)
  void clearPhoneme() => clearField(6);
  @$pb.TagNumber(6)
  TTSPhonemeTimestamp ensurePhoneme() => $_ensure(5);

  @$pb.TagNumber(7)
  TTSSpeakResult get speakResult => $_getN(6);
  @$pb.TagNumber(7)
  set speakResult(TTSSpeakResult v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasSpeakResult() => $_has(6);
  @$pb.TagNumber(7)
  void clearSpeakResult() => clearField(7);
  @$pb.TagNumber(7)
  TTSSpeakResult ensureSpeakResult() => $_ensure(6);

  @$pb.TagNumber(8)
  $core.String get errorMessage => $_getSZ(7);
  @$pb.TagNumber(8)
  set errorMessage($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasErrorMessage() => $_has(7);
  @$pb.TagNumber(8)
  void clearErrorMessage() => clearField(8);

  @$pb.TagNumber(9)
  $core.int get errorCode => $_getIZ(8);
  @$pb.TagNumber(9)
  set errorCode($core.int v) { $_setSignedInt32(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasErrorCode() => $_has(8);
  @$pb.TagNumber(9)
  void clearErrorCode() => clearField(9);

  /// Progress metadata for started/progress/audio_chunk/completed events.
  /// progress is 0.0..1.0 when known; total_chunks=0 means unknown.
  @$pb.TagNumber(10)
  $core.double get progress => $_getN(9);
  @$pb.TagNumber(10)
  set progress($core.double v) { $_setFloat(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasProgress() => $_has(9);
  @$pb.TagNumber(10)
  void clearProgress() => clearField(10);

  @$pb.TagNumber(11)
  $core.int get chunkIndex => $_getIZ(10);
  @$pb.TagNumber(11)
  set chunkIndex($core.int v) { $_setSignedInt32(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasChunkIndex() => $_has(10);
  @$pb.TagNumber(11)
  void clearChunkIndex() => clearField(11);

  @$pb.TagNumber(12)
  $core.int get totalChunks => $_getIZ(11);
  @$pb.TagNumber(12)
  set totalChunks($core.int v) { $_setSignedInt32(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasTotalChunks() => $_has(11);
  @$pb.TagNumber(12)
  void clearTotalChunks() => clearField(12);

  @$pb.TagNumber(13)
  $fixnum.Int64 get elapsedMs => $_getI64(12);
  @$pb.TagNumber(13)
  set elapsedMs($fixnum.Int64 v) { $_setInt64(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasElapsedMs() => $_has(12);
  @$pb.TagNumber(13)
  void clearElapsedMs() => clearField(13);

  @$pb.TagNumber(14)
  $core.String get statusMessage => $_getSZ(13);
  @$pb.TagNumber(14)
  set statusMessage($core.String v) { $_setString(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasStatusMessage() => $_has(13);
  @$pb.TagNumber(14)
  void clearStatusMessage() => clearField(14);
}

class TTSServiceState extends $pb.GeneratedMessage {
  factory TTSServiceState({
    $core.bool? isReady,
    $core.String? currentVoice,
    $core.Iterable<TTSVoiceInfo>? voices,
    $core.Iterable<$core.String>? supportedLanguageCodes,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final $result = create();
    if (isReady != null) {
      $result.isReady = isReady;
    }
    if (currentVoice != null) {
      $result.currentVoice = currentVoice;
    }
    if (voices != null) {
      $result.voices.addAll(voices);
    }
    if (supportedLanguageCodes != null) {
      $result.supportedLanguageCodes.addAll(supportedLanguageCodes);
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    return $result;
  }
  TTSServiceState._() : super();
  factory TTSServiceState.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TTSServiceState.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TTSServiceState', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isReady')
    ..aOS(2, _omitFieldNames ? '' : 'currentVoice')
    ..pc<TTSVoiceInfo>(3, _omitFieldNames ? '' : 'voices', $pb.PbFieldType.PM, subBuilder: TTSVoiceInfo.create)
    ..pPS(4, _omitFieldNames ? '' : 'supportedLanguageCodes')
    ..aOS(5, _omitFieldNames ? '' : 'errorMessage')
    ..a<$core.int>(6, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TTSServiceState clone() => TTSServiceState()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TTSServiceState copyWith(void Function(TTSServiceState) updates) => super.copyWith((message) => updates(message as TTSServiceState)) as TTSServiceState;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TTSServiceState create() => TTSServiceState._();
  TTSServiceState createEmptyInstance() => create();
  static $pb.PbList<TTSServiceState> createRepeated() => $pb.PbList<TTSServiceState>();
  @$core.pragma('dart2js:noInline')
  static TTSServiceState getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TTSServiceState>(create);
  static TTSServiceState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get isReady => $_getBF(0);
  @$pb.TagNumber(1)
  set isReady($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasIsReady() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsReady() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get currentVoice => $_getSZ(1);
  @$pb.TagNumber(2)
  set currentVoice($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCurrentVoice() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrentVoice() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<TTSVoiceInfo> get voices => $_getList(2);

  @$pb.TagNumber(4)
  $core.List<$core.String> get supportedLanguageCodes => $_getList(3);

  @$pb.TagNumber(5)
  $core.String get errorMessage => $_getSZ(4);
  @$pb.TagNumber(5)
  set errorMessage($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasErrorMessage() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorMessage() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get errorCode => $_getIZ(5);
  @$pb.TagNumber(6)
  set errorCode($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasErrorCode() => $_has(5);
  @$pb.TagNumber(6)
  void clearErrorCode() => clearField(6);
}

class TTSApi {
  $pb.RpcClient _client;
  TTSApi(this._client);

  $async.Future<TTSOutput> synthesize($pb.ClientContext? ctx, TTSSynthesisRequest request) =>
    _client.invoke<TTSOutput>(ctx, 'TTS', 'Synthesize', request, TTSOutput())
  ;
  $async.Future<TTSStreamEvent> stream($pb.ClientContext? ctx, TTSSynthesisRequest request) =>
    _client.invoke<TTSStreamEvent>(ctx, 'TTS', 'Stream', request, TTSStreamEvent())
  ;
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
