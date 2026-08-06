// This is a generated file - do not edit.
//
// Generated from tts_options.proto.

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
import 'model_types.pbenum.dart' as $1;
import 'tts_options.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'tts_options.pbenum.dart';

class TTSOptions extends $pb.GeneratedMessage {
  factory TTSOptions({
    $core.String? voice,
    $core.String? languageCode,
    $core.double? speed,
    $core.double? pitch,
    $core.double? volume,
    $1.AudioFormat? audioFormat,
    $core.int? sampleRate,
    $core.String? model,
  }) {
    final result = create();
    if (voice != null) result.voice = voice;
    if (languageCode != null) result.languageCode = languageCode;
    if (speed != null) result.speed = speed;
    if (pitch != null) result.pitch = pitch;
    if (volume != null) result.volume = volume;
    if (audioFormat != null) result.audioFormat = audioFormat;
    if (sampleRate != null) result.sampleRate = sampleRate;
    if (model != null) result.model = model;
    return result;
  }

  TTSOptions._();

  factory TTSOptions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TTSOptions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TTSOptions',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'voice')
    ..aOS(2, _omitFieldNames ? '' : 'languageCode')
    ..aD(3, _omitFieldNames ? '' : 'speed', fieldType: $pb.PbFieldType.OF)
    ..aD(4, _omitFieldNames ? '' : 'pitch', fieldType: $pb.PbFieldType.OF)
    ..aD(5, _omitFieldNames ? '' : 'volume', fieldType: $pb.PbFieldType.OF)
    ..aE<$1.AudioFormat>(7, _omitFieldNames ? '' : 'audioFormat',
        enumValues: $1.AudioFormat.values)
    ..aI(8, _omitFieldNames ? '' : 'sampleRate')
    ..aOS(13, _omitFieldNames ? '' : 'model')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TTSOptions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TTSOptions copyWith(void Function(TTSOptions) updates) =>
      super.copyWith((message) => updates(message as TTSOptions)) as TTSOptions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TTSOptions create() => TTSOptions._();
  @$core.override
  TTSOptions createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TTSOptions getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TTSOptions>(create);
  static TTSOptions? _defaultInstance;

  /// Empty = use the component's configured voice.
  @$pb.TagNumber(1)
  $core.String get voice => $_getSZ(0);
  @$pb.TagNumber(1)
  set voice($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasVoice() => $_has(0);
  @$pb.TagNumber(1)
  void clearVoice() => $_clearField(1);

  /// BCP-47. Empty = use the component default.
  @$pb.TagNumber(2)
  $core.String get languageCode => $_getSZ(1);
  @$pb.TagNumber(2)
  set languageCode($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLanguageCode() => $_has(1);
  @$pb.TagNumber(2)
  void clearLanguageCode() => $_clearField(2);

  /// Speed multiplier, matching OpenAI /audio/speech `speed`.
  @$pb.TagNumber(3)
  $core.double get speed => $_getN(2);
  @$pb.TagNumber(3)
  set speed($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSpeed() => $_has(2);
  @$pb.TagNumber(3)
  void clearSpeed() => $_clearField(3);

  /// Fundamental-frequency multiplier, 1.0 = the voice's own pitch. Honoured
  /// only by the platform backend (Apple System TTS / Android TextToSpeech);
  /// neural voices (sherpa/Piper/Kokoro, qhexrt) ignore it, because for them
  /// pitch is voice identity rather than a dial.
  @$pb.TagNumber(4)
  $core.double get pitch => $_getN(3);
  @$pb.TagNumber(4)
  set pitch($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPitch() => $_has(3);
  @$pb.TagNumber(4)
  void clearPitch() => $_clearField(4);

  /// 0.0 - 1.0.
  @$pb.TagNumber(5)
  $core.double get volume => $_getN(4);
  @$pb.TagNumber(5)
  set volume($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasVolume() => $_has(4);
  @$pb.TagNumber(5)
  void clearVolume() => $_clearField(5);

  /// TTS honours exactly AUDIO_FORMAT_PCM (float32) and AUDIO_FORMAT_WAV.
  /// Other values, including AUDIO_FORMAT_PCM_S16LE, fall through to PCM
  /// silently today; do not rely on them until that is fixed.
  @$pb.TagNumber(7)
  $1.AudioFormat get audioFormat => $_getN(5);
  @$pb.TagNumber(7)
  set audioFormat($1.AudioFormat value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasAudioFormat() => $_has(5);
  @$pb.TagNumber(7)
  void clearAudioFormat() => $_clearField(7);

  /// 0 (the default) = render at the voice's native rate. Naming any other
  /// rate forces a resample and costs quality. TTSOutput.sample_rate always
  /// reports the rate actually used.
  @$pb.TagNumber(8)
  $core.int get sampleRate => $_getIZ(6);
  @$pb.TagNumber(8)
  set sampleRate($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(8)
  $core.bool hasSampleRate() => $_has(6);
  @$pb.TagNumber(8)
  void clearSampleRate() => $_clearField(8);

  /// Voice/model id to synthesize with. Unset = use whatever is already
  /// loaded for MODEL_CATEGORY_SPEECH_SYNTHESIS; set = load it first,
  /// downloading if needed.
  @$pb.TagNumber(13)
  $core.String get model => $_getSZ(7);
  @$pb.TagNumber(13)
  set model($core.String value) => $_setString(7, value);
  @$pb.TagNumber(13)
  $core.bool hasModel() => $_has(7);
  @$pb.TagNumber(13)
  void clearModel() => $_clearField(13);
}

class TTSSynthesisRequest extends $pb.GeneratedMessage {
  factory TTSSynthesisRequest({
    $core.String? requestId,
    $core.String? text,
    TTSOptions? options,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (text != null) result.text = text;
    if (options != null) result.options = options;
    return result;
  }

  TTSSynthesisRequest._();

  factory TTSSynthesisRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TTSSynthesisRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TTSSynthesisRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOS(2, _omitFieldNames ? '' : 'text')
    ..aOM<TTSOptions>(4, _omitFieldNames ? '' : 'options',
        subBuilder: TTSOptions.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TTSSynthesisRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TTSSynthesisRequest copyWith(void Function(TTSSynthesisRequest) updates) =>
      super.copyWith((message) => updates(message as TTSSynthesisRequest))
          as TTSSynthesisRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TTSSynthesisRequest create() => TTSSynthesisRequest._();
  @$core.override
  TTSSynthesisRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TTSSynthesisRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TTSSynthesisRequest>(create);
  static TTSSynthesisRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get text => $_getSZ(1);
  @$pb.TagNumber(2)
  set text($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => $_clearField(2);

  @$pb.TagNumber(4)
  TTSOptions get options => $_getN(2);
  @$pb.TagNumber(4)
  set options(TTSOptions value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasOptions() => $_has(2);
  @$pb.TagNumber(4)
  void clearOptions() => $_clearField(4);
  @$pb.TagNumber(4)
  TTSOptions ensureOptions() => $_ensure(2);
}

class TTSSynthesisMetadata extends $pb.GeneratedMessage {
  factory TTSSynthesisMetadata({
    $core.String? voiceId,
    $core.String? languageCode,
    $fixnum.Int64? processingTimeMs,
    $core.int? inputBytes,
  }) {
    final result = create();
    if (voiceId != null) result.voiceId = voiceId;
    if (languageCode != null) result.languageCode = languageCode;
    if (processingTimeMs != null) result.processingTimeMs = processingTimeMs;
    if (inputBytes != null) result.inputBytes = inputBytes;
    return result;
  }

  TTSSynthesisMetadata._();

  factory TTSSynthesisMetadata.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TTSSynthesisMetadata.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TTSSynthesisMetadata',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'voiceId')
    ..aOS(2, _omitFieldNames ? '' : 'languageCode')
    ..aInt64(3, _omitFieldNames ? '' : 'processingTimeMs')
    ..aI(4, _omitFieldNames ? '' : 'inputBytes')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TTSSynthesisMetadata clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TTSSynthesisMetadata copyWith(void Function(TTSSynthesisMetadata) updates) =>
      super.copyWith((message) => updates(message as TTSSynthesisMetadata))
          as TTSSynthesisMetadata;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TTSSynthesisMetadata create() => TTSSynthesisMetadata._();
  @$core.override
  TTSSynthesisMetadata createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TTSSynthesisMetadata getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TTSSynthesisMetadata>(create);
  static TTSSynthesisMetadata? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get voiceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set voiceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasVoiceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearVoiceId() => $_clearField(1);

  /// BCP-47.
  @$pb.TagNumber(2)
  $core.String get languageCode => $_getSZ(1);
  @$pb.TagNumber(2)
  set languageCode($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLanguageCode() => $_has(1);
  @$pb.TagNumber(2)
  void clearLanguageCode() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get processingTimeMs => $_getI64(2);
  @$pb.TagNumber(3)
  set processingTimeMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasProcessingTimeMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearProcessingTimeMs() => $_clearField(3);

  /// UTF-8 byte length of the spoken input, not a codepoint count.
  @$pb.TagNumber(4)
  $core.int get inputBytes => $_getIZ(3);
  @$pb.TagNumber(4)
  set inputBytes($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasInputBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearInputBytes() => $_clearField(4);
}

class TTSOutput extends $pb.GeneratedMessage {
  factory TTSOutput({
    $core.List<$core.int>? audioData,
    $1.AudioFormat? audioFormat,
    $core.int? sampleRate,
    $fixnum.Int64? durationMs,
    TTSSynthesisMetadata? metadata,
    $fixnum.Int64? timestampMs,
    $core.int? chunkIndex,
    $core.bool? isFinal,
    $0.SDKError? error,
  }) {
    final result = create();
    if (audioData != null) result.audioData = audioData;
    if (audioFormat != null) result.audioFormat = audioFormat;
    if (sampleRate != null) result.sampleRate = sampleRate;
    if (durationMs != null) result.durationMs = durationMs;
    if (metadata != null) result.metadata = metadata;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (chunkIndex != null) result.chunkIndex = chunkIndex;
    if (isFinal != null) result.isFinal = isFinal;
    if (error != null) result.error = error;
    return result;
  }

  TTSOutput._();

  factory TTSOutput.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TTSOutput.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TTSOutput',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'audioData', $pb.PbFieldType.OY)
    ..aE<$1.AudioFormat>(2, _omitFieldNames ? '' : 'audioFormat',
        enumValues: $1.AudioFormat.values)
    ..aI(3, _omitFieldNames ? '' : 'sampleRate')
    ..aInt64(4, _omitFieldNames ? '' : 'durationMs')
    ..aOM<TTSSynthesisMetadata>(6, _omitFieldNames ? '' : 'metadata',
        subBuilder: TTSSynthesisMetadata.create)
    ..aInt64(7, _omitFieldNames ? '' : 'timestampMs')
    ..aI(8, _omitFieldNames ? '' : 'chunkIndex')
    ..aOB(9, _omitFieldNames ? '' : 'isFinal')
    ..aOM<$0.SDKError>(13, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TTSOutput clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TTSOutput copyWith(void Function(TTSOutput) updates) =>
      super.copyWith((message) => updates(message as TTSOutput)) as TTSOutput;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TTSOutput create() => TTSOutput._();
  @$core.override
  TTSOutput createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TTSOutput getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TTSOutput>(create);
  static TTSOutput? _defaultInstance;

  /// Encoded per audio_format.
  @$pb.TagNumber(1)
  $core.List<$core.int> get audioData => $_getN(0);
  @$pb.TagNumber(1)
  set audioData($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAudioData() => $_has(0);
  @$pb.TagNumber(1)
  void clearAudioData() => $_clearField(1);

  @$pb.TagNumber(2)
  $1.AudioFormat get audioFormat => $_getN(1);
  @$pb.TagNumber(2)
  set audioFormat($1.AudioFormat value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasAudioFormat() => $_has(1);
  @$pb.TagNumber(2)
  void clearAudioFormat() => $_clearField(2);

  /// Required to interpret PCM payloads. For compressed formats this is the
  /// synthesis rate, not the container rate.
  @$pb.TagNumber(3)
  $core.int get sampleRate => $_getIZ(2);
  @$pb.TagNumber(3)
  set sampleRate($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSampleRate() => $_has(2);
  @$pb.TagNumber(3)
  void clearSampleRate() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get durationMs => $_getI64(3);
  @$pb.TagNumber(4)
  set durationMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDurationMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearDurationMs() => $_clearField(4);

  @$pb.TagNumber(6)
  TTSSynthesisMetadata get metadata => $_getN(4);
  @$pb.TagNumber(6)
  set metadata(TTSSynthesisMetadata value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasMetadata() => $_has(4);
  @$pb.TagNumber(6)
  void clearMetadata() => $_clearField(6);
  @$pb.TagNumber(6)
  TTSSynthesisMetadata ensureMetadata() => $_ensure(4);

  /// Milliseconds since epoch.
  @$pb.TagNumber(7)
  $fixnum.Int64 get timestampMs => $_getI64(5);
  @$pb.TagNumber(7)
  set timestampMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(7)
  $core.bool hasTimestampMs() => $_has(5);
  @$pb.TagNumber(7)
  void clearTimestampMs() => $_clearField(7);

  /// For one-shot synthesis, chunk_index=0 and is_final=true.
  @$pb.TagNumber(8)
  $core.int get chunkIndex => $_getIZ(6);
  @$pb.TagNumber(8)
  set chunkIndex($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(8)
  $core.bool hasChunkIndex() => $_has(6);
  @$pb.TagNumber(8)
  void clearChunkIndex() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.bool get isFinal => $_getBF(7);
  @$pb.TagNumber(9)
  set isFinal($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(9)
  $core.bool hasIsFinal() => $_has(7);
  @$pb.TagNumber(9)
  void clearIsFinal() => $_clearField(9);

  @$pb.TagNumber(13)
  $0.SDKError get error => $_getN(8);
  @$pb.TagNumber(13)
  set error($0.SDKError value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasError() => $_has(8);
  @$pb.TagNumber(13)
  void clearError() => $_clearField(13);
  @$pb.TagNumber(13)
  $0.SDKError ensureError() => $_ensure(8);
}

/// Metadata-only view for callers that let the SDK play the audio and never
/// need the raw bytes.
class TTSSpeakResult extends $pb.GeneratedMessage {
  factory TTSSpeakResult({
    $1.AudioFormat? audioFormat,
    $core.int? sampleRate,
    $fixnum.Int64? durationMs,
    $fixnum.Int64? audioSizeBytes,
    TTSSynthesisMetadata? metadata,
    $fixnum.Int64? timestampMs,
    $0.SDKError? error,
  }) {
    final result = create();
    if (audioFormat != null) result.audioFormat = audioFormat;
    if (sampleRate != null) result.sampleRate = sampleRate;
    if (durationMs != null) result.durationMs = durationMs;
    if (audioSizeBytes != null) result.audioSizeBytes = audioSizeBytes;
    if (metadata != null) result.metadata = metadata;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (error != null) result.error = error;
    return result;
  }

  TTSSpeakResult._();

  factory TTSSpeakResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TTSSpeakResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TTSSpeakResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<$1.AudioFormat>(1, _omitFieldNames ? '' : 'audioFormat',
        enumValues: $1.AudioFormat.values)
    ..aI(2, _omitFieldNames ? '' : 'sampleRate')
    ..aInt64(3, _omitFieldNames ? '' : 'durationMs')
    ..aInt64(4, _omitFieldNames ? '' : 'audioSizeBytes')
    ..aOM<TTSSynthesisMetadata>(5, _omitFieldNames ? '' : 'metadata',
        subBuilder: TTSSynthesisMetadata.create)
    ..aInt64(6, _omitFieldNames ? '' : 'timestampMs')
    ..aOM<$0.SDKError>(9, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TTSSpeakResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TTSSpeakResult copyWith(void Function(TTSSpeakResult) updates) =>
      super.copyWith((message) => updates(message as TTSSpeakResult))
          as TTSSpeakResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TTSSpeakResult create() => TTSSpeakResult._();
  @$core.override
  TTSSpeakResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TTSSpeakResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TTSSpeakResult>(create);
  static TTSSpeakResult? _defaultInstance;

  @$pb.TagNumber(1)
  $1.AudioFormat get audioFormat => $_getN(0);
  @$pb.TagNumber(1)
  set audioFormat($1.AudioFormat value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasAudioFormat() => $_has(0);
  @$pb.TagNumber(1)
  void clearAudioFormat() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get sampleRate => $_getIZ(1);
  @$pb.TagNumber(2)
  set sampleRate($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSampleRate() => $_has(1);
  @$pb.TagNumber(2)
  void clearSampleRate() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get durationMs => $_getI64(2);
  @$pb.TagNumber(3)
  set durationMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDurationMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearDurationMs() => $_clearField(3);

  /// 0 for system TTS that plays directly without exposing buffers.
  @$pb.TagNumber(4)
  $fixnum.Int64 get audioSizeBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set audioSizeBytes($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAudioSizeBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearAudioSizeBytes() => $_clearField(4);

  @$pb.TagNumber(5)
  TTSSynthesisMetadata get metadata => $_getN(4);
  @$pb.TagNumber(5)
  set metadata(TTSSynthesisMetadata value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasMetadata() => $_has(4);
  @$pb.TagNumber(5)
  void clearMetadata() => $_clearField(5);
  @$pb.TagNumber(5)
  TTSSynthesisMetadata ensureMetadata() => $_ensure(4);

  /// Milliseconds since epoch, when speech completed.
  @$pb.TagNumber(6)
  $fixnum.Int64 get timestampMs => $_getI64(5);
  @$pb.TagNumber(6)
  set timestampMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTimestampMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearTimestampMs() => $_clearField(6);

  @$pb.TagNumber(9)
  $0.SDKError get error => $_getN(6);
  @$pb.TagNumber(9)
  set error($0.SDKError value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasError() => $_has(6);
  @$pb.TagNumber(9)
  void clearError() => $_clearField(9);
  @$pb.TagNumber(9)
  $0.SDKError ensureError() => $_ensure(6);
}

class TTSVoiceInfo extends $pb.GeneratedMessage {
  factory TTSVoiceInfo({
    $core.String? id,
    $core.String? displayName,
    $core.String? languageCode,
    $core.int? sampleRate,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (displayName != null) result.displayName = displayName;
    if (languageCode != null) result.languageCode = languageCode;
    if (sampleRate != null) result.sampleRate = sampleRate;
    return result;
  }

  TTSVoiceInfo._();

  factory TTSVoiceInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TTSVoiceInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TTSVoiceInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'displayName')
    ..aOS(3, _omitFieldNames ? '' : 'languageCode')
    ..aI(8, _omitFieldNames ? '' : 'sampleRate')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TTSVoiceInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TTSVoiceInfo copyWith(void Function(TTSVoiceInfo) updates) =>
      super.copyWith((message) => updates(message as TTSVoiceInfo))
          as TTSVoiceInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TTSVoiceInfo create() => TTSVoiceInfo._();
  @$core.override
  TTSVoiceInfo createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TTSVoiceInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TTSVoiceInfo>(create);
  static TTSVoiceInfo? _defaultInstance;

  /// Passed back as TTSOptions.voice.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  /// e.g. "Samantha". MUST NOT be a copy of `id` -- fall back to the model
  /// id only when the engine reports no display name.
  @$pb.TagNumber(2)
  $core.String get displayName => $_getSZ(1);
  @$pb.TagNumber(2)
  set displayName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDisplayName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDisplayName() => $_clearField(2);

  /// BCP-47.
  @$pb.TagNumber(3)
  $core.String get languageCode => $_getSZ(2);
  @$pb.TagNumber(3)
  set languageCode($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLanguageCode() => $_has(2);
  @$pb.TagNumber(3)
  void clearLanguageCode() => $_clearField(3);

  /// The voice's native rate in Hz -- tells the caller whether naming a
  /// different TTSOptions.sample_rate buys anything.
  @$pb.TagNumber(8)
  $core.int get sampleRate => $_getIZ(3);
  @$pb.TagNumber(8)
  set sampleRate($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(8)
  $core.bool hasSampleRate() => $_has(3);
  @$pb.TagNumber(8)
  void clearSampleRate() => $_clearField(8);
}

class TTSVoiceList extends $pb.GeneratedMessage {
  factory TTSVoiceList({
    $core.Iterable<TTSVoiceInfo>? voices,
  }) {
    final result = create();
    if (voices != null) result.voices.addAll(voices);
    return result;
  }

  TTSVoiceList._();

  factory TTSVoiceList.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TTSVoiceList.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TTSVoiceList',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPM<TTSVoiceInfo>(1, _omitFieldNames ? '' : 'voices',
        subBuilder: TTSVoiceInfo.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TTSVoiceList clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TTSVoiceList copyWith(void Function(TTSVoiceList) updates) =>
      super.copyWith((message) => updates(message as TTSVoiceList))
          as TTSVoiceList;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TTSVoiceList create() => TTSVoiceList._();
  @$core.override
  TTSVoiceList createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TTSVoiceList getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TTSVoiceList>(create);
  static TTSVoiceList? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<TTSVoiceInfo> get voices => $_getList(0);
}

class TTSStreamEvent extends $pb.GeneratedMessage {
  factory TTSStreamEvent({
    $fixnum.Int64? timestampUs,
    $core.String? requestId,
    TTSStreamEventKind? kind,
    TTSOutput? output,
    $0.SDKError? error,
  }) {
    final result = create();
    if (timestampUs != null) result.timestampUs = timestampUs;
    if (requestId != null) result.requestId = requestId;
    if (kind != null) result.kind = kind;
    if (output != null) result.output = output;
    if (error != null) result.error = error;
    return result;
  }

  TTSStreamEvent._();

  factory TTSStreamEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TTSStreamEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TTSStreamEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(3, _omitFieldNames ? '' : 'requestId')
    ..aE<TTSStreamEventKind>(4, _omitFieldNames ? '' : 'kind',
        enumValues: TTSStreamEventKind.values)
    ..aOM<TTSOutput>(5, _omitFieldNames ? '' : 'output',
        subBuilder: TTSOutput.create)
    ..aOM<$0.SDKError>(15, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TTSStreamEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TTSStreamEvent copyWith(void Function(TTSStreamEvent) updates) =>
      super.copyWith((message) => updates(message as TTSStreamEvent))
          as TTSStreamEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TTSStreamEvent create() => TTSStreamEvent._();
  @$core.override
  TTSStreamEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TTSStreamEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TTSStreamEvent>(create);
  static TTSStreamEvent? _defaultInstance;

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampUs => $_getI64(0);
  @$pb.TagNumber(2)
  set timestampUs($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestampUs() => $_has(0);
  @$pb.TagNumber(2)
  void clearTimestampUs() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get requestId => $_getSZ(1);
  @$pb.TagNumber(3)
  set requestId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(3)
  $core.bool hasRequestId() => $_has(1);
  @$pb.TagNumber(3)
  void clearRequestId() => $_clearField(3);

  @$pb.TagNumber(4)
  TTSStreamEventKind get kind => $_getN(2);
  @$pb.TagNumber(4)
  set kind(TTSStreamEventKind value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasKind() => $_has(2);
  @$pb.TagNumber(4)
  void clearKind() => $_clearField(4);

  @$pb.TagNumber(5)
  TTSOutput get output => $_getN(3);
  @$pb.TagNumber(5)
  set output(TTSOutput value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasOutput() => $_has(3);
  @$pb.TagNumber(5)
  void clearOutput() => $_clearField(5);
  @$pb.TagNumber(5)
  TTSOutput ensureOutput() => $_ensure(3);

  @$pb.TagNumber(15)
  $0.SDKError get error => $_getN(4);
  @$pb.TagNumber(15)
  set error($0.SDKError value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasError() => $_has(4);
  @$pb.TagNumber(15)
  void clearError() => $_clearField(15);
  @$pb.TagNumber(15)
  $0.SDKError ensureError() => $_ensure(4);
}

class TTSServiceState extends $pb.GeneratedMessage {
  factory TTSServiceState({
    $core.bool? isReady,
    $core.String? currentVoice,
    $core.Iterable<$core.String>? supportedLanguageCodes,
    $0.SDKError? error,
  }) {
    final result = create();
    if (isReady != null) result.isReady = isReady;
    if (currentVoice != null) result.currentVoice = currentVoice;
    if (supportedLanguageCodes != null)
      result.supportedLanguageCodes.addAll(supportedLanguageCodes);
    if (error != null) result.error = error;
    return result;
  }

  TTSServiceState._();

  factory TTSServiceState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TTSServiceState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TTSServiceState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isReady')
    ..aOS(2, _omitFieldNames ? '' : 'currentVoice')
    ..pPS(4, _omitFieldNames ? '' : 'supportedLanguageCodes')
    ..aOM<$0.SDKError>(7, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TTSServiceState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TTSServiceState copyWith(void Function(TTSServiceState) updates) =>
      super.copyWith((message) => updates(message as TTSServiceState))
          as TTSServiceState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TTSServiceState create() => TTSServiceState._();
  @$core.override
  TTSServiceState createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TTSServiceState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TTSServiceState>(create);
  static TTSServiceState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get isReady => $_getBF(0);
  @$pb.TagNumber(1)
  set isReady($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIsReady() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsReady() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get currentVoice => $_getSZ(1);
  @$pb.TagNumber(2)
  set currentVoice($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCurrentVoice() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrentVoice() => $_clearField(2);

  @$pb.TagNumber(4)
  $pb.PbList<$core.String> get supportedLanguageCodes => $_getList(2);

  @$pb.TagNumber(7)
  $0.SDKError get error => $_getN(3);
  @$pb.TagNumber(7)
  set error($0.SDKError value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasError() => $_has(3);
  @$pb.TagNumber(7)
  void clearError() => $_clearField(7);
  @$pb.TagNumber(7)
  $0.SDKError ensureError() => $_ensure(3);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
