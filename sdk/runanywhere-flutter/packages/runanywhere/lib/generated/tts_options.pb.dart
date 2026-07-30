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

import 'model_types.pbenum.dart' as $0;
import 'tts_options.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'tts_options.pbenum.dart';

class TTSConfiguration extends $pb.GeneratedMessage {
  factory TTSConfiguration({
    $core.String? modelId,
    $core.bool? enableNeuralVoice,
    $0.InferenceFramework? preferredFramework,
    TTSOptions? defaultOptions,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (enableNeuralVoice != null) result.enableNeuralVoice = enableNeuralVoice;
    if (preferredFramework != null)
      result.preferredFramework = preferredFramework;
    if (defaultOptions != null) result.defaultOptions = defaultOptions;
    return result;
  }

  TTSConfiguration._();

  factory TTSConfiguration.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TTSConfiguration.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TTSConfiguration',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aOB(9, _omitFieldNames ? '' : 'enableNeuralVoice')
    ..aE<$0.InferenceFramework>(11, _omitFieldNames ? '' : 'preferredFramework',
        enumValues: $0.InferenceFramework.values)
    ..aOM<TTSOptions>(12, _omitFieldNames ? '' : 'defaultOptions',
        subBuilder: TTSOptions.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TTSConfiguration clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TTSConfiguration copyWith(void Function(TTSConfiguration) updates) =>
      super.copyWith((message) => updates(message as TTSConfiguration))
          as TTSConfiguration;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TTSConfiguration create() => TTSConfiguration._();
  @$core.override
  TTSConfiguration createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TTSConfiguration getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TTSConfiguration>(create);
  static TTSConfiguration? _defaultInstance;

  /// Voice model file id, e.g. a piper voice. Empty for platform TTS engines
  /// (Apple System TTS, Android TextToSpeech), which need no model file.
  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  /// Use the neural or premium voice when available.
  @$pb.TagNumber(9)
  $core.bool get enableNeuralVoice => $_getBF(1);
  @$pb.TagNumber(9)
  set enableNeuralVoice($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(9)
  $core.bool hasEnableNeuralVoice() => $_has(1);
  @$pb.TagNumber(9)
  void clearEnableNeuralVoice() => $_clearField(9);

  @$pb.TagNumber(11)
  $0.InferenceFramework get preferredFramework => $_getN(2);
  @$pb.TagNumber(11)
  set preferredFramework($0.InferenceFramework value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasPreferredFramework() => $_has(2);
  @$pb.TagNumber(11)
  void clearPreferredFramework() => $_clearField(11);

  /// Applied when a per-call TTSOptions is absent or leaves a field unset.
  @$pb.TagNumber(12)
  TTSOptions get defaultOptions => $_getN(3);
  @$pb.TagNumber(12)
  set defaultOptions(TTSOptions value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasDefaultOptions() => $_has(3);
  @$pb.TagNumber(12)
  void clearDefaultOptions() => $_clearField(12);
  @$pb.TagNumber(12)
  TTSOptions ensureDefaultOptions() => $_ensure(3);
}

class TTSOptions extends $pb.GeneratedMessage {
  factory TTSOptions({
    $core.String? voice,
    $core.String? languageCode,
    $core.double? speed,
    $core.double? pitch,
    $core.double? volume,
    $core.bool? enableSsml,
    $0.AudioFormat? audioFormat,
    $core.int? sampleRate,
    $core.int? speakerId,
    $core.String? style,
  }) {
    final result = create();
    if (voice != null) result.voice = voice;
    if (languageCode != null) result.languageCode = languageCode;
    if (speed != null) result.speed = speed;
    if (pitch != null) result.pitch = pitch;
    if (volume != null) result.volume = volume;
    if (enableSsml != null) result.enableSsml = enableSsml;
    if (audioFormat != null) result.audioFormat = audioFormat;
    if (sampleRate != null) result.sampleRate = sampleRate;
    if (speakerId != null) result.speakerId = speakerId;
    if (style != null) result.style = style;
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
    ..aOB(6, _omitFieldNames ? '' : 'enableSsml')
    ..aE<$0.AudioFormat>(7, _omitFieldNames ? '' : 'audioFormat',
        enumValues: $0.AudioFormat.values)
    ..aI(8, _omitFieldNames ? '' : 'sampleRate')
    ..aI(9, _omitFieldNames ? '' : 'speakerId')
    ..aOS(11, _omitFieldNames ? '' : 'style')
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

  /// 0.5 - 2.0.
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

  /// Whether the input carries SSML markup.
  @$pb.TagNumber(6)
  $core.bool get enableSsml => $_getBF(5);
  @$pb.TagNumber(6)
  set enableSsml($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasEnableSsml() => $_has(5);
  @$pb.TagNumber(6)
  void clearEnableSsml() => $_clearField(6);

  @$pb.TagNumber(7)
  $0.AudioFormat get audioFormat => $_getN(6);
  @$pb.TagNumber(7)
  set audioFormat($0.AudioFormat value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasAudioFormat() => $_has(6);
  @$pb.TagNumber(7)
  void clearAudioFormat() => $_clearField(7);

  /// 0 = component default.
  @$pb.TagNumber(8)
  $core.int get sampleRate => $_getIZ(7);
  @$pb.TagNumber(8)
  set sampleRate($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasSampleRate() => $_has(7);
  @$pb.TagNumber(8)
  void clearSampleRate() => $_clearField(8);

  /// For multi-speaker voices. -1 or 0 = backend default, per model convention.
  @$pb.TagNumber(9)
  $core.int get speakerId => $_getIZ(8);
  @$pb.TagNumber(9)
  set speakerId($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasSpeakerId() => $_has(8);
  @$pb.TagNumber(9)
  void clearSpeakerId() => $_clearField(9);

  /// Style or emotion hint for voices supporting style transfer.
  @$pb.TagNumber(11)
  $core.String get style => $_getSZ(9);
  @$pb.TagNumber(11)
  set style($core.String value) => $_setString(9, value);
  @$pb.TagNumber(11)
  $core.bool hasStyle() => $_has(9);
  @$pb.TagNumber(11)
  void clearStyle() => $_clearField(11);
}

class TTSSynthesisRequest extends $pb.GeneratedMessage {
  factory TTSSynthesisRequest({
    $core.String? requestId,
    $core.String? text,
    $core.String? ssml,
    TTSOptions? options,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (text != null) result.text = text;
    if (ssml != null) result.ssml = ssml;
    if (options != null) result.options = options;
    if (metadata != null) result.metadata.addEntries(metadata);
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
    ..aOS(3, _omitFieldNames ? '' : 'ssml')
    ..aOM<TTSOptions>(4, _omitFieldNames ? '' : 'options',
        subBuilder: TTSOptions.create)
    ..m<$core.String, $core.String>(5, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'TTSSynthesisRequest.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
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

  @$pb.TagNumber(3)
  $core.String get ssml => $_getSZ(2);
  @$pb.TagNumber(3)
  set ssml($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSsml() => $_has(2);
  @$pb.TagNumber(3)
  void clearSsml() => $_clearField(3);

  @$pb.TagNumber(4)
  TTSOptions get options => $_getN(3);
  @$pb.TagNumber(4)
  set options(TTSOptions value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasOptions() => $_has(3);
  @$pb.TagNumber(4)
  void clearOptions() => $_clearField(4);
  @$pb.TagNumber(4)
  TTSOptions ensureOptions() => $_ensure(3);

  @$pb.TagNumber(5)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(4);
}

class TTSPhonemeTimestamp extends $pb.GeneratedMessage {
  factory TTSPhonemeTimestamp({
    $core.String? phoneme,
    $fixnum.Int64? startMs,
    $fixnum.Int64? endMs,
  }) {
    final result = create();
    if (phoneme != null) result.phoneme = phoneme;
    if (startMs != null) result.startMs = startMs;
    if (endMs != null) result.endMs = endMs;
    return result;
  }

  TTSPhonemeTimestamp._();

  factory TTSPhonemeTimestamp.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TTSPhonemeTimestamp.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TTSPhonemeTimestamp',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'phoneme')
    ..aInt64(2, _omitFieldNames ? '' : 'startMs')
    ..aInt64(3, _omitFieldNames ? '' : 'endMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TTSPhonemeTimestamp clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TTSPhonemeTimestamp copyWith(void Function(TTSPhonemeTimestamp) updates) =>
      super.copyWith((message) => updates(message as TTSPhonemeTimestamp))
          as TTSPhonemeTimestamp;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TTSPhonemeTimestamp create() => TTSPhonemeTimestamp._();
  @$core.override
  TTSPhonemeTimestamp createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TTSPhonemeTimestamp getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TTSPhonemeTimestamp>(create);
  static TTSPhonemeTimestamp? _defaultInstance;

  /// IPA or engine-specific symbol.
  @$pb.TagNumber(1)
  $core.String get phoneme => $_getSZ(0);
  @$pb.TagNumber(1)
  set phoneme($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPhoneme() => $_has(0);
  @$pb.TagNumber(1)
  void clearPhoneme() => $_clearField(1);

  /// Offsets within the synthesized audio.
  @$pb.TagNumber(2)
  $fixnum.Int64 get startMs => $_getI64(1);
  @$pb.TagNumber(2)
  set startMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStartMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearStartMs() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get endMs => $_getI64(2);
  @$pb.TagNumber(3)
  set endMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEndMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearEndMs() => $_clearField(3);
}

class TTSSynthesisMetadata extends $pb.GeneratedMessage {
  factory TTSSynthesisMetadata({
    $core.String? voiceId,
    $core.String? languageCode,
    $fixnum.Int64? processingTimeMs,
    $core.int? characterCount,
    $fixnum.Int64? audioDurationMs,
    $core.double? charactersPerSecond,
  }) {
    final result = create();
    if (voiceId != null) result.voiceId = voiceId;
    if (languageCode != null) result.languageCode = languageCode;
    if (processingTimeMs != null) result.processingTimeMs = processingTimeMs;
    if (characterCount != null) result.characterCount = characterCount;
    if (audioDurationMs != null) result.audioDurationMs = audioDurationMs;
    if (charactersPerSecond != null)
      result.charactersPerSecond = charactersPerSecond;
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
    ..aI(4, _omitFieldNames ? '' : 'characterCount')
    ..aInt64(5, _omitFieldNames ? '' : 'audioDurationMs')
    ..aD(6, _omitFieldNames ? '' : 'charactersPerSecond',
        fieldType: $pb.PbFieldType.OF)
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

  @$pb.TagNumber(4)
  $core.int get characterCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set characterCount($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCharacterCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearCharacterCount() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get audioDurationMs => $_getI64(4);
  @$pb.TagNumber(5)
  set audioDurationMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAudioDurationMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearAudioDurationMs() => $_clearField(5);

  /// character_count / processing_time_ms, set by the producer.
  @$pb.TagNumber(6)
  $core.double get charactersPerSecond => $_getN(5);
  @$pb.TagNumber(6)
  set charactersPerSecond($core.double value) => $_setFloat(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCharactersPerSecond() => $_has(5);
  @$pb.TagNumber(6)
  void clearCharactersPerSecond() => $_clearField(6);
}

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
    final result = create();
    if (audioData != null) result.audioData = audioData;
    if (audioFormat != null) result.audioFormat = audioFormat;
    if (sampleRate != null) result.sampleRate = sampleRate;
    if (durationMs != null) result.durationMs = durationMs;
    if (phonemeTimestamps != null)
      result.phonemeTimestamps.addAll(phonemeTimestamps);
    if (metadata != null) result.metadata = metadata;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (chunkIndex != null) result.chunkIndex = chunkIndex;
    if (isFinal != null) result.isFinal = isFinal;
    if (audioSizeBytes != null) result.audioSizeBytes = audioSizeBytes;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
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
    ..aE<$0.AudioFormat>(2, _omitFieldNames ? '' : 'audioFormat',
        enumValues: $0.AudioFormat.values)
    ..aI(3, _omitFieldNames ? '' : 'sampleRate')
    ..aInt64(4, _omitFieldNames ? '' : 'durationMs')
    ..pPM<TTSPhonemeTimestamp>(5, _omitFieldNames ? '' : 'phonemeTimestamps',
        subBuilder: TTSPhonemeTimestamp.create)
    ..aOM<TTSSynthesisMetadata>(6, _omitFieldNames ? '' : 'metadata',
        subBuilder: TTSSynthesisMetadata.create)
    ..aInt64(7, _omitFieldNames ? '' : 'timestampMs')
    ..aI(8, _omitFieldNames ? '' : 'chunkIndex')
    ..aOB(9, _omitFieldNames ? '' : 'isFinal')
    ..aInt64(10, _omitFieldNames ? '' : 'audioSizeBytes')
    ..aOS(11, _omitFieldNames ? '' : 'errorMessage')
    ..aI(12, _omitFieldNames ? '' : 'errorCode')
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
  $0.AudioFormat get audioFormat => $_getN(1);
  @$pb.TagNumber(2)
  set audioFormat($0.AudioFormat value) => $_setField(2, value);
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

  /// Empty unless the engine produced them.
  @$pb.TagNumber(5)
  $pb.PbList<TTSPhonemeTimestamp> get phonemeTimestamps => $_getList(4);

  @$pb.TagNumber(6)
  TTSSynthesisMetadata get metadata => $_getN(5);
  @$pb.TagNumber(6)
  set metadata(TTSSynthesisMetadata value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasMetadata() => $_has(5);
  @$pb.TagNumber(6)
  void clearMetadata() => $_clearField(6);
  @$pb.TagNumber(6)
  TTSSynthesisMetadata ensureMetadata() => $_ensure(5);

  /// Milliseconds since epoch.
  @$pb.TagNumber(7)
  $fixnum.Int64 get timestampMs => $_getI64(6);
  @$pb.TagNumber(7)
  set timestampMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasTimestampMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearTimestampMs() => $_clearField(7);

  /// For one-shot synthesis, chunk_index=0 and is_final=true.
  @$pb.TagNumber(8)
  $core.int get chunkIndex => $_getIZ(7);
  @$pb.TagNumber(8)
  set chunkIndex($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasChunkIndex() => $_has(7);
  @$pb.TagNumber(8)
  void clearChunkIndex() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.bool get isFinal => $_getBF(8);
  @$pb.TagNumber(9)
  set isFinal($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasIsFinal() => $_has(8);
  @$pb.TagNumber(9)
  void clearIsFinal() => $_clearField(9);

  @$pb.TagNumber(10)
  $fixnum.Int64 get audioSizeBytes => $_getI64(9);
  @$pb.TagNumber(10)
  set audioSizeBytes($fixnum.Int64 value) => $_setInt64(9, value);
  @$pb.TagNumber(10)
  $core.bool hasAudioSizeBytes() => $_has(9);
  @$pb.TagNumber(10)
  void clearAudioSizeBytes() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get errorMessage => $_getSZ(10);
  @$pb.TagNumber(11)
  set errorMessage($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasErrorMessage() => $_has(10);
  @$pb.TagNumber(11)
  void clearErrorMessage() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.int get errorCode => $_getIZ(11);
  @$pb.TagNumber(12)
  set errorCode($core.int value) => $_setSignedInt32(11, value);
  @$pb.TagNumber(12)
  $core.bool hasErrorCode() => $_has(11);
  @$pb.TagNumber(12)
  void clearErrorCode() => $_clearField(12);
}

/// Metadata-only view for callers that let the SDK play the audio and never
/// need the raw bytes.
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
    final result = create();
    if (audioFormat != null) result.audioFormat = audioFormat;
    if (sampleRate != null) result.sampleRate = sampleRate;
    if (durationMs != null) result.durationMs = durationMs;
    if (audioSizeBytes != null) result.audioSizeBytes = audioSizeBytes;
    if (metadata != null) result.metadata = metadata;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
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
    ..aE<$0.AudioFormat>(1, _omitFieldNames ? '' : 'audioFormat',
        enumValues: $0.AudioFormat.values)
    ..aI(2, _omitFieldNames ? '' : 'sampleRate')
    ..aInt64(3, _omitFieldNames ? '' : 'durationMs')
    ..aInt64(4, _omitFieldNames ? '' : 'audioSizeBytes')
    ..aOM<TTSSynthesisMetadata>(5, _omitFieldNames ? '' : 'metadata',
        subBuilder: TTSSynthesisMetadata.create)
    ..aInt64(6, _omitFieldNames ? '' : 'timestampMs')
    ..aOS(7, _omitFieldNames ? '' : 'errorMessage')
    ..aI(8, _omitFieldNames ? '' : 'errorCode')
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
  $0.AudioFormat get audioFormat => $_getN(0);
  @$pb.TagNumber(1)
  set audioFormat($0.AudioFormat value) => $_setField(1, value);
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
    final result = create();
    if (id != null) result.id = id;
    if (displayName != null) result.displayName = displayName;
    if (languageCode != null) result.languageCode = languageCode;
    if (gender != null) result.gender = gender;
    if (description != null) result.description = description;
    if (isNeural != null) result.isNeural = isNeural;
    if (isSystem != null) result.isSystem = isSystem;
    if (sampleRate != null) result.sampleRate = sampleRate;
    if (supportedStyles != null) result.supportedStyles.addAll(supportedStyles);
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
    ..aE<TTSVoiceGender>(4, _omitFieldNames ? '' : 'gender',
        enumValues: TTSVoiceGender.values)
    ..aOS(5, _omitFieldNames ? '' : 'description')
    ..aOB(6, _omitFieldNames ? '' : 'isNeural')
    ..aOB(7, _omitFieldNames ? '' : 'isSystem')
    ..aI(8, _omitFieldNames ? '' : 'sampleRate')
    ..pPS(9, _omitFieldNames ? '' : 'supportedStyles')
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

  /// e.g. "Samantha".
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

  @$pb.TagNumber(4)
  TTSVoiceGender get gender => $_getN(3);
  @$pb.TagNumber(4)
  set gender(TTSVoiceGender value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasGender() => $_has(3);
  @$pb.TagNumber(4)
  void clearGender() => $_clearField(4);

  /// Locale, age, or style notes.
  @$pb.TagNumber(5)
  $core.String get description => $_getSZ(4);
  @$pb.TagNumber(5)
  set description($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDescription() => $_has(4);
  @$pb.TagNumber(5)
  void clearDescription() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get isNeural => $_getBF(5);
  @$pb.TagNumber(6)
  set isNeural($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasIsNeural() => $_has(5);
  @$pb.TagNumber(6)
  void clearIsNeural() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get isSystem => $_getBF(6);
  @$pb.TagNumber(7)
  set isSystem($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasIsSystem() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsSystem() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get sampleRate => $_getIZ(7);
  @$pb.TagNumber(8)
  set sampleRate($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasSampleRate() => $_has(7);
  @$pb.TagNumber(8)
  void clearSampleRate() => $_clearField(8);

  @$pb.TagNumber(9)
  $pb.PbList<$core.String> get supportedStyles => $_getList(8);
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
    final result = create();
    if (seq != null) result.seq = seq;
    if (timestampUs != null) result.timestampUs = timestampUs;
    if (requestId != null) result.requestId = requestId;
    if (kind != null) result.kind = kind;
    if (output != null) result.output = output;
    if (phoneme != null) result.phoneme = phoneme;
    if (speakResult != null) result.speakResult = speakResult;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    if (progress != null) result.progress = progress;
    if (chunkIndex != null) result.chunkIndex = chunkIndex;
    if (totalChunks != null) result.totalChunks = totalChunks;
    if (elapsedMs != null) result.elapsedMs = elapsedMs;
    if (statusMessage != null) result.statusMessage = statusMessage;
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
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(3, _omitFieldNames ? '' : 'requestId')
    ..aE<TTSStreamEventKind>(4, _omitFieldNames ? '' : 'kind',
        enumValues: TTSStreamEventKind.values)
    ..aOM<TTSOutput>(5, _omitFieldNames ? '' : 'output',
        subBuilder: TTSOutput.create)
    ..aOM<TTSPhonemeTimestamp>(6, _omitFieldNames ? '' : 'phoneme',
        subBuilder: TTSPhonemeTimestamp.create)
    ..aOM<TTSSpeakResult>(7, _omitFieldNames ? '' : 'speakResult',
        subBuilder: TTSSpeakResult.create)
    ..aOS(8, _omitFieldNames ? '' : 'errorMessage')
    ..aI(9, _omitFieldNames ? '' : 'errorCode')
    ..aD(10, _omitFieldNames ? '' : 'progress', fieldType: $pb.PbFieldType.OF)
    ..aI(11, _omitFieldNames ? '' : 'chunkIndex')
    ..aI(12, _omitFieldNames ? '' : 'totalChunks')
    ..aInt64(13, _omitFieldNames ? '' : 'elapsedMs')
    ..aOS(14, _omitFieldNames ? '' : 'statusMessage')
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
  TTSStreamEventKind get kind => $_getN(3);
  @$pb.TagNumber(4)
  set kind(TTSStreamEventKind value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasKind() => $_has(3);
  @$pb.TagNumber(4)
  void clearKind() => $_clearField(4);

  @$pb.TagNumber(5)
  TTSOutput get output => $_getN(4);
  @$pb.TagNumber(5)
  set output(TTSOutput value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasOutput() => $_has(4);
  @$pb.TagNumber(5)
  void clearOutput() => $_clearField(5);
  @$pb.TagNumber(5)
  TTSOutput ensureOutput() => $_ensure(4);

  @$pb.TagNumber(6)
  TTSPhonemeTimestamp get phoneme => $_getN(5);
  @$pb.TagNumber(6)
  set phoneme(TTSPhonemeTimestamp value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasPhoneme() => $_has(5);
  @$pb.TagNumber(6)
  void clearPhoneme() => $_clearField(6);
  @$pb.TagNumber(6)
  TTSPhonemeTimestamp ensurePhoneme() => $_ensure(5);

  @$pb.TagNumber(7)
  TTSSpeakResult get speakResult => $_getN(6);
  @$pb.TagNumber(7)
  set speakResult(TTSSpeakResult value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasSpeakResult() => $_has(6);
  @$pb.TagNumber(7)
  void clearSpeakResult() => $_clearField(7);
  @$pb.TagNumber(7)
  TTSSpeakResult ensureSpeakResult() => $_ensure(6);

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

  /// progress is 0.0-1.0 when known; total_chunks 0 = unknown.
  @$pb.TagNumber(10)
  $core.double get progress => $_getN(9);
  @$pb.TagNumber(10)
  set progress($core.double value) => $_setFloat(9, value);
  @$pb.TagNumber(10)
  $core.bool hasProgress() => $_has(9);
  @$pb.TagNumber(10)
  void clearProgress() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.int get chunkIndex => $_getIZ(10);
  @$pb.TagNumber(11)
  set chunkIndex($core.int value) => $_setSignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasChunkIndex() => $_has(10);
  @$pb.TagNumber(11)
  void clearChunkIndex() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.int get totalChunks => $_getIZ(11);
  @$pb.TagNumber(12)
  set totalChunks($core.int value) => $_setSignedInt32(11, value);
  @$pb.TagNumber(12)
  $core.bool hasTotalChunks() => $_has(11);
  @$pb.TagNumber(12)
  void clearTotalChunks() => $_clearField(12);

  @$pb.TagNumber(13)
  $fixnum.Int64 get elapsedMs => $_getI64(12);
  @$pb.TagNumber(13)
  set elapsedMs($fixnum.Int64 value) => $_setInt64(12, value);
  @$pb.TagNumber(13)
  $core.bool hasElapsedMs() => $_has(12);
  @$pb.TagNumber(13)
  void clearElapsedMs() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get statusMessage => $_getSZ(13);
  @$pb.TagNumber(14)
  set statusMessage($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasStatusMessage() => $_has(13);
  @$pb.TagNumber(14)
  void clearStatusMessage() => $_clearField(14);
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
    final result = create();
    if (isReady != null) result.isReady = isReady;
    if (currentVoice != null) result.currentVoice = currentVoice;
    if (voices != null) result.voices.addAll(voices);
    if (supportedLanguageCodes != null)
      result.supportedLanguageCodes.addAll(supportedLanguageCodes);
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
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
    ..pPM<TTSVoiceInfo>(3, _omitFieldNames ? '' : 'voices',
        subBuilder: TTSVoiceInfo.create)
    ..pPS(4, _omitFieldNames ? '' : 'supportedLanguageCodes')
    ..aOS(5, _omitFieldNames ? '' : 'errorMessage')
    ..aI(6, _omitFieldNames ? '' : 'errorCode')
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

  @$pb.TagNumber(3)
  $pb.PbList<TTSVoiceInfo> get voices => $_getList(2);

  @$pb.TagNumber(4)
  $pb.PbList<$core.String> get supportedLanguageCodes => $_getList(3);

  @$pb.TagNumber(5)
  $core.String get errorMessage => $_getSZ(4);
  @$pb.TagNumber(5)
  set errorMessage($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasErrorMessage() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorMessage() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get errorCode => $_getIZ(5);
  @$pb.TagNumber(6)
  set errorCode($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasErrorCode() => $_has(5);
  @$pb.TagNumber(6)
  void clearErrorCode() => $_clearField(6);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
