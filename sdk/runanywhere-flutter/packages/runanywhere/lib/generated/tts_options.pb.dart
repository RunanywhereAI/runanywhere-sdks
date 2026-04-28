///
//  Generated code. Do not modify.
//  source: tts_options.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'model_types.pbenum.dart' as $1;
import 'tts_options.pbenum.dart';

export 'tts_options.pbenum.dart';

class TTSConfiguration extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'TTSConfiguration', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'modelId')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'voice')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'languageCode')
    ..a<$core.double>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'speakingRate', $pb.PbFieldType.OF)
    ..a<$core.double>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'pitch', $pb.PbFieldType.OF)
    ..a<$core.double>(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'volume', $pb.PbFieldType.OF)
    ..e<$1.AudioFormat>(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'audioFormat', $pb.PbFieldType.OE, defaultOrMaker: $1.AudioFormat.AUDIO_FORMAT_UNSPECIFIED, valueOf: $1.AudioFormat.valueOf, enumValues: $1.AudioFormat.values)
    ..a<$core.int>(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sampleRate', $pb.PbFieldType.O3)
    ..aOB(9, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'enableNeuralVoice')
    ..aOB(10, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'enableSsml')
    ..hasRequiredFields = false
  ;

  TTSConfiguration._() : super();
  factory TTSConfiguration({
    $core.String? modelId,
    $core.String? voice,
    $core.String? languageCode,
    $core.double? speakingRate,
    $core.double? pitch,
    $core.double? volume,
    $1.AudioFormat? audioFormat,
    $core.int? sampleRate,
    $core.bool? enableNeuralVoice,
    $core.bool? enableSsml,
  }) {
    final _result = create();
    if (modelId != null) {
      _result.modelId = modelId;
    }
    if (voice != null) {
      _result.voice = voice;
    }
    if (languageCode != null) {
      _result.languageCode = languageCode;
    }
    if (speakingRate != null) {
      _result.speakingRate = speakingRate;
    }
    if (pitch != null) {
      _result.pitch = pitch;
    }
    if (volume != null) {
      _result.volume = volume;
    }
    if (audioFormat != null) {
      _result.audioFormat = audioFormat;
    }
    if (sampleRate != null) {
      _result.sampleRate = sampleRate;
    }
    if (enableNeuralVoice != null) {
      _result.enableNeuralVoice = enableNeuralVoice;
    }
    if (enableSsml != null) {
      _result.enableSsml = enableSsml;
    }
    return _result;
  }
  factory TTSConfiguration.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TTSConfiguration.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TTSConfiguration clone() => TTSConfiguration()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TTSConfiguration copyWith(void Function(TTSConfiguration) updates) => super.copyWith((message) => updates(message as TTSConfiguration)) as TTSConfiguration; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static TTSConfiguration create() => TTSConfiguration._();
  TTSConfiguration createEmptyInstance() => create();
  static $pb.PbList<TTSConfiguration> createRepeated() => $pb.PbList<TTSConfiguration>();
  @$core.pragma('dart2js:noInline')
  static TTSConfiguration getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TTSConfiguration>(create);
  static TTSConfiguration? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get voice => $_getSZ(1);
  @$pb.TagNumber(2)
  set voice($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasVoice() => $_has(1);
  @$pb.TagNumber(2)
  void clearVoice() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get languageCode => $_getSZ(2);
  @$pb.TagNumber(3)
  set languageCode($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasLanguageCode() => $_has(2);
  @$pb.TagNumber(3)
  void clearLanguageCode() => clearField(3);

  @$pb.TagNumber(4)
  $core.double get speakingRate => $_getN(3);
  @$pb.TagNumber(4)
  set speakingRate($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSpeakingRate() => $_has(3);
  @$pb.TagNumber(4)
  void clearSpeakingRate() => clearField(4);

  @$pb.TagNumber(5)
  $core.double get pitch => $_getN(4);
  @$pb.TagNumber(5)
  set pitch($core.double v) { $_setFloat(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasPitch() => $_has(4);
  @$pb.TagNumber(5)
  void clearPitch() => clearField(5);

  @$pb.TagNumber(6)
  $core.double get volume => $_getN(5);
  @$pb.TagNumber(6)
  set volume($core.double v) { $_setFloat(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasVolume() => $_has(5);
  @$pb.TagNumber(6)
  void clearVolume() => clearField(6);

  @$pb.TagNumber(7)
  $1.AudioFormat get audioFormat => $_getN(6);
  @$pb.TagNumber(7)
  set audioFormat($1.AudioFormat v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasAudioFormat() => $_has(6);
  @$pb.TagNumber(7)
  void clearAudioFormat() => clearField(7);

  @$pb.TagNumber(8)
  $core.int get sampleRate => $_getIZ(7);
  @$pb.TagNumber(8)
  set sampleRate($core.int v) { $_setSignedInt32(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasSampleRate() => $_has(7);
  @$pb.TagNumber(8)
  void clearSampleRate() => clearField(8);

  @$pb.TagNumber(9)
  $core.bool get enableNeuralVoice => $_getBF(8);
  @$pb.TagNumber(9)
  set enableNeuralVoice($core.bool v) { $_setBool(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasEnableNeuralVoice() => $_has(8);
  @$pb.TagNumber(9)
  void clearEnableNeuralVoice() => clearField(9);

  @$pb.TagNumber(10)
  $core.bool get enableSsml => $_getBF(9);
  @$pb.TagNumber(10)
  set enableSsml($core.bool v) { $_setBool(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasEnableSsml() => $_has(9);
  @$pb.TagNumber(10)
  void clearEnableSsml() => clearField(10);
}

class TTSOptions extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'TTSOptions', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'voice')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'languageCode')
    ..a<$core.double>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'speakingRate', $pb.PbFieldType.OF)
    ..a<$core.double>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'pitch', $pb.PbFieldType.OF)
    ..a<$core.double>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'volume', $pb.PbFieldType.OF)
    ..aOB(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'enableSsml')
    ..e<$1.AudioFormat>(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'audioFormat', $pb.PbFieldType.OE, defaultOrMaker: $1.AudioFormat.AUDIO_FORMAT_UNSPECIFIED, valueOf: $1.AudioFormat.valueOf, enumValues: $1.AudioFormat.values)
    ..hasRequiredFields = false
  ;

  TTSOptions._() : super();
  factory TTSOptions({
    $core.String? voice,
    $core.String? languageCode,
    $core.double? speakingRate,
    $core.double? pitch,
    $core.double? volume,
    $core.bool? enableSsml,
    $1.AudioFormat? audioFormat,
  }) {
    final _result = create();
    if (voice != null) {
      _result.voice = voice;
    }
    if (languageCode != null) {
      _result.languageCode = languageCode;
    }
    if (speakingRate != null) {
      _result.speakingRate = speakingRate;
    }
    if (pitch != null) {
      _result.pitch = pitch;
    }
    if (volume != null) {
      _result.volume = volume;
    }
    if (enableSsml != null) {
      _result.enableSsml = enableSsml;
    }
    if (audioFormat != null) {
      _result.audioFormat = audioFormat;
    }
    return _result;
  }
  factory TTSOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TTSOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TTSOptions clone() => TTSOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TTSOptions copyWith(void Function(TTSOptions) updates) => super.copyWith((message) => updates(message as TTSOptions)) as TTSOptions; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static TTSOptions create() => TTSOptions._();
  TTSOptions createEmptyInstance() => create();
  static $pb.PbList<TTSOptions> createRepeated() => $pb.PbList<TTSOptions>();
  @$core.pragma('dart2js:noInline')
  static TTSOptions getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TTSOptions>(create);
  static TTSOptions? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get voice => $_getSZ(0);
  @$pb.TagNumber(1)
  set voice($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasVoice() => $_has(0);
  @$pb.TagNumber(1)
  void clearVoice() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get languageCode => $_getSZ(1);
  @$pb.TagNumber(2)
  set languageCode($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasLanguageCode() => $_has(1);
  @$pb.TagNumber(2)
  void clearLanguageCode() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get speakingRate => $_getN(2);
  @$pb.TagNumber(3)
  set speakingRate($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSpeakingRate() => $_has(2);
  @$pb.TagNumber(3)
  void clearSpeakingRate() => clearField(3);

  @$pb.TagNumber(4)
  $core.double get pitch => $_getN(3);
  @$pb.TagNumber(4)
  set pitch($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasPitch() => $_has(3);
  @$pb.TagNumber(4)
  void clearPitch() => clearField(4);

  @$pb.TagNumber(5)
  $core.double get volume => $_getN(4);
  @$pb.TagNumber(5)
  set volume($core.double v) { $_setFloat(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasVolume() => $_has(4);
  @$pb.TagNumber(5)
  void clearVolume() => clearField(5);

  @$pb.TagNumber(6)
  $core.bool get enableSsml => $_getBF(5);
  @$pb.TagNumber(6)
  set enableSsml($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasEnableSsml() => $_has(5);
  @$pb.TagNumber(6)
  void clearEnableSsml() => clearField(6);

  @$pb.TagNumber(7)
  $1.AudioFormat get audioFormat => $_getN(6);
  @$pb.TagNumber(7)
  set audioFormat($1.AudioFormat v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasAudioFormat() => $_has(6);
  @$pb.TagNumber(7)
  void clearAudioFormat() => clearField(7);
}

class TTSPhonemeTimestamp extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'TTSPhonemeTimestamp', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'phoneme')
    ..aInt64(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'startMs')
    ..aInt64(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'endMs')
    ..hasRequiredFields = false
  ;

  TTSPhonemeTimestamp._() : super();
  factory TTSPhonemeTimestamp({
    $core.String? phoneme,
    $fixnum.Int64? startMs,
    $fixnum.Int64? endMs,
  }) {
    final _result = create();
    if (phoneme != null) {
      _result.phoneme = phoneme;
    }
    if (startMs != null) {
      _result.startMs = startMs;
    }
    if (endMs != null) {
      _result.endMs = endMs;
    }
    return _result;
  }
  factory TTSPhonemeTimestamp.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TTSPhonemeTimestamp.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TTSPhonemeTimestamp clone() => TTSPhonemeTimestamp()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TTSPhonemeTimestamp copyWith(void Function(TTSPhonemeTimestamp) updates) => super.copyWith((message) => updates(message as TTSPhonemeTimestamp)) as TTSPhonemeTimestamp; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static TTSPhonemeTimestamp create() => TTSPhonemeTimestamp._();
  TTSPhonemeTimestamp createEmptyInstance() => create();
  static $pb.PbList<TTSPhonemeTimestamp> createRepeated() => $pb.PbList<TTSPhonemeTimestamp>();
  @$core.pragma('dart2js:noInline')
  static TTSPhonemeTimestamp getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TTSPhonemeTimestamp>(create);
  static TTSPhonemeTimestamp? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get phoneme => $_getSZ(0);
  @$pb.TagNumber(1)
  set phoneme($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPhoneme() => $_has(0);
  @$pb.TagNumber(1)
  void clearPhoneme() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get startMs => $_getI64(1);
  @$pb.TagNumber(2)
  set startMs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasStartMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearStartMs() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get endMs => $_getI64(2);
  @$pb.TagNumber(3)
  set endMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasEndMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearEndMs() => clearField(3);
}

class TTSSynthesisMetadata extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'TTSSynthesisMetadata', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'voiceId')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'languageCode')
    ..aInt64(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'processingTimeMs')
    ..a<$core.int>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'characterCount', $pb.PbFieldType.O3)
    ..aInt64(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'audioDurationMs')
    ..hasRequiredFields = false
  ;

  TTSSynthesisMetadata._() : super();
  factory TTSSynthesisMetadata({
    $core.String? voiceId,
    $core.String? languageCode,
    $fixnum.Int64? processingTimeMs,
    $core.int? characterCount,
    $fixnum.Int64? audioDurationMs,
  }) {
    final _result = create();
    if (voiceId != null) {
      _result.voiceId = voiceId;
    }
    if (languageCode != null) {
      _result.languageCode = languageCode;
    }
    if (processingTimeMs != null) {
      _result.processingTimeMs = processingTimeMs;
    }
    if (characterCount != null) {
      _result.characterCount = characterCount;
    }
    if (audioDurationMs != null) {
      _result.audioDurationMs = audioDurationMs;
    }
    return _result;
  }
  factory TTSSynthesisMetadata.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TTSSynthesisMetadata.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TTSSynthesisMetadata clone() => TTSSynthesisMetadata()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TTSSynthesisMetadata copyWith(void Function(TTSSynthesisMetadata) updates) => super.copyWith((message) => updates(message as TTSSynthesisMetadata)) as TTSSynthesisMetadata; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static TTSSynthesisMetadata create() => TTSSynthesisMetadata._();
  TTSSynthesisMetadata createEmptyInstance() => create();
  static $pb.PbList<TTSSynthesisMetadata> createRepeated() => $pb.PbList<TTSSynthesisMetadata>();
  @$core.pragma('dart2js:noInline')
  static TTSSynthesisMetadata getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TTSSynthesisMetadata>(create);
  static TTSSynthesisMetadata? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get voiceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set voiceId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasVoiceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearVoiceId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get languageCode => $_getSZ(1);
  @$pb.TagNumber(2)
  set languageCode($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasLanguageCode() => $_has(1);
  @$pb.TagNumber(2)
  void clearLanguageCode() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get processingTimeMs => $_getI64(2);
  @$pb.TagNumber(3)
  set processingTimeMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasProcessingTimeMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearProcessingTimeMs() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get characterCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set characterCount($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasCharacterCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearCharacterCount() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get audioDurationMs => $_getI64(4);
  @$pb.TagNumber(5)
  set audioDurationMs($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAudioDurationMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearAudioDurationMs() => clearField(5);
}

class TTSOutput extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'TTSOutput', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'audioData', $pb.PbFieldType.OY)
    ..e<$1.AudioFormat>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'audioFormat', $pb.PbFieldType.OE, defaultOrMaker: $1.AudioFormat.AUDIO_FORMAT_UNSPECIFIED, valueOf: $1.AudioFormat.valueOf, enumValues: $1.AudioFormat.values)
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sampleRate', $pb.PbFieldType.O3)
    ..aInt64(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'durationMs')
    ..pc<TTSPhonemeTimestamp>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'phonemeTimestamps', $pb.PbFieldType.PM, subBuilder: TTSPhonemeTimestamp.create)
    ..aOM<TTSSynthesisMetadata>(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'metadata', subBuilder: TTSSynthesisMetadata.create)
    ..aInt64(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'timestampMs')
    ..hasRequiredFields = false
  ;

  TTSOutput._() : super();
  factory TTSOutput({
    $core.List<$core.int>? audioData,
    $1.AudioFormat? audioFormat,
    $core.int? sampleRate,
    $fixnum.Int64? durationMs,
    $core.Iterable<TTSPhonemeTimestamp>? phonemeTimestamps,
    TTSSynthesisMetadata? metadata,
    $fixnum.Int64? timestampMs,
  }) {
    final _result = create();
    if (audioData != null) {
      _result.audioData = audioData;
    }
    if (audioFormat != null) {
      _result.audioFormat = audioFormat;
    }
    if (sampleRate != null) {
      _result.sampleRate = sampleRate;
    }
    if (durationMs != null) {
      _result.durationMs = durationMs;
    }
    if (phonemeTimestamps != null) {
      _result.phonemeTimestamps.addAll(phonemeTimestamps);
    }
    if (metadata != null) {
      _result.metadata = metadata;
    }
    if (timestampMs != null) {
      _result.timestampMs = timestampMs;
    }
    return _result;
  }
  factory TTSOutput.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TTSOutput.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TTSOutput clone() => TTSOutput()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TTSOutput copyWith(void Function(TTSOutput) updates) => super.copyWith((message) => updates(message as TTSOutput)) as TTSOutput; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static TTSOutput create() => TTSOutput._();
  TTSOutput createEmptyInstance() => create();
  static $pb.PbList<TTSOutput> createRepeated() => $pb.PbList<TTSOutput>();
  @$core.pragma('dart2js:noInline')
  static TTSOutput getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TTSOutput>(create);
  static TTSOutput? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get audioData => $_getN(0);
  @$pb.TagNumber(1)
  set audioData($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAudioData() => $_has(0);
  @$pb.TagNumber(1)
  void clearAudioData() => clearField(1);

  @$pb.TagNumber(2)
  $1.AudioFormat get audioFormat => $_getN(1);
  @$pb.TagNumber(2)
  set audioFormat($1.AudioFormat v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasAudioFormat() => $_has(1);
  @$pb.TagNumber(2)
  void clearAudioFormat() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get sampleRate => $_getIZ(2);
  @$pb.TagNumber(3)
  set sampleRate($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSampleRate() => $_has(2);
  @$pb.TagNumber(3)
  void clearSampleRate() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get durationMs => $_getI64(3);
  @$pb.TagNumber(4)
  set durationMs($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasDurationMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearDurationMs() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<TTSPhonemeTimestamp> get phonemeTimestamps => $_getList(4);

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

  @$pb.TagNumber(7)
  $fixnum.Int64 get timestampMs => $_getI64(6);
  @$pb.TagNumber(7)
  set timestampMs($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasTimestampMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearTimestampMs() => clearField(7);
}

class TTSSpeakResult extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'TTSSpeakResult', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<$1.AudioFormat>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'audioFormat', $pb.PbFieldType.OE, defaultOrMaker: $1.AudioFormat.AUDIO_FORMAT_UNSPECIFIED, valueOf: $1.AudioFormat.valueOf, enumValues: $1.AudioFormat.values)
    ..a<$core.int>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sampleRate', $pb.PbFieldType.O3)
    ..aInt64(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'durationMs')
    ..aInt64(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'audioSizeBytes')
    ..aOM<TTSSynthesisMetadata>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'metadata', subBuilder: TTSSynthesisMetadata.create)
    ..aInt64(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'timestampMs')
    ..hasRequiredFields = false
  ;

  TTSSpeakResult._() : super();
  factory TTSSpeakResult({
    $1.AudioFormat? audioFormat,
    $core.int? sampleRate,
    $fixnum.Int64? durationMs,
    $fixnum.Int64? audioSizeBytes,
    TTSSynthesisMetadata? metadata,
    $fixnum.Int64? timestampMs,
  }) {
    final _result = create();
    if (audioFormat != null) {
      _result.audioFormat = audioFormat;
    }
    if (sampleRate != null) {
      _result.sampleRate = sampleRate;
    }
    if (durationMs != null) {
      _result.durationMs = durationMs;
    }
    if (audioSizeBytes != null) {
      _result.audioSizeBytes = audioSizeBytes;
    }
    if (metadata != null) {
      _result.metadata = metadata;
    }
    if (timestampMs != null) {
      _result.timestampMs = timestampMs;
    }
    return _result;
  }
  factory TTSSpeakResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TTSSpeakResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TTSSpeakResult clone() => TTSSpeakResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TTSSpeakResult copyWith(void Function(TTSSpeakResult) updates) => super.copyWith((message) => updates(message as TTSSpeakResult)) as TTSSpeakResult; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static TTSSpeakResult create() => TTSSpeakResult._();
  TTSSpeakResult createEmptyInstance() => create();
  static $pb.PbList<TTSSpeakResult> createRepeated() => $pb.PbList<TTSSpeakResult>();
  @$core.pragma('dart2js:noInline')
  static TTSSpeakResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TTSSpeakResult>(create);
  static TTSSpeakResult? _defaultInstance;

  @$pb.TagNumber(1)
  $1.AudioFormat get audioFormat => $_getN(0);
  @$pb.TagNumber(1)
  set audioFormat($1.AudioFormat v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasAudioFormat() => $_has(0);
  @$pb.TagNumber(1)
  void clearAudioFormat() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get sampleRate => $_getIZ(1);
  @$pb.TagNumber(2)
  set sampleRate($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSampleRate() => $_has(1);
  @$pb.TagNumber(2)
  void clearSampleRate() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get durationMs => $_getI64(2);
  @$pb.TagNumber(3)
  set durationMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDurationMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearDurationMs() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get audioSizeBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set audioSizeBytes($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAudioSizeBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearAudioSizeBytes() => clearField(4);

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

  @$pb.TagNumber(6)
  $fixnum.Int64 get timestampMs => $_getI64(5);
  @$pb.TagNumber(6)
  set timestampMs($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTimestampMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearTimestampMs() => clearField(6);
}

class TTSVoiceInfo extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'TTSVoiceInfo', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'id')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'displayName')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'languageCode')
    ..e<TTSVoiceGender>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'gender', $pb.PbFieldType.OE, defaultOrMaker: TTSVoiceGender.TTS_VOICE_GENDER_UNSPECIFIED, valueOf: TTSVoiceGender.valueOf, enumValues: TTSVoiceGender.values)
    ..aOS(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'description')
    ..hasRequiredFields = false
  ;

  TTSVoiceInfo._() : super();
  factory TTSVoiceInfo({
    $core.String? id,
    $core.String? displayName,
    $core.String? languageCode,
    TTSVoiceGender? gender,
    $core.String? description,
  }) {
    final _result = create();
    if (id != null) {
      _result.id = id;
    }
    if (displayName != null) {
      _result.displayName = displayName;
    }
    if (languageCode != null) {
      _result.languageCode = languageCode;
    }
    if (gender != null) {
      _result.gender = gender;
    }
    if (description != null) {
      _result.description = description;
    }
    return _result;
  }
  factory TTSVoiceInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TTSVoiceInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TTSVoiceInfo clone() => TTSVoiceInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TTSVoiceInfo copyWith(void Function(TTSVoiceInfo) updates) => super.copyWith((message) => updates(message as TTSVoiceInfo)) as TTSVoiceInfo; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static TTSVoiceInfo create() => TTSVoiceInfo._();
  TTSVoiceInfo createEmptyInstance() => create();
  static $pb.PbList<TTSVoiceInfo> createRepeated() => $pb.PbList<TTSVoiceInfo>();
  @$core.pragma('dart2js:noInline')
  static TTSVoiceInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TTSVoiceInfo>(create);
  static TTSVoiceInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get displayName => $_getSZ(1);
  @$pb.TagNumber(2)
  set displayName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDisplayName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDisplayName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get languageCode => $_getSZ(2);
  @$pb.TagNumber(3)
  set languageCode($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasLanguageCode() => $_has(2);
  @$pb.TagNumber(3)
  void clearLanguageCode() => clearField(3);

  @$pb.TagNumber(4)
  TTSVoiceGender get gender => $_getN(3);
  @$pb.TagNumber(4)
  set gender(TTSVoiceGender v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasGender() => $_has(3);
  @$pb.TagNumber(4)
  void clearGender() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get description => $_getSZ(4);
  @$pb.TagNumber(5)
  set description($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasDescription() => $_has(4);
  @$pb.TagNumber(5)
  void clearDescription() => clearField(5);
}

