///
//  Generated code. Do not modify.
//  source: stt_options.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'stt_options.pbenum.dart';
import 'model_types.pbenum.dart' as $1;

export 'stt_options.pbenum.dart';

class STTConfiguration extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'STTConfiguration', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'modelId')
    ..e<STTLanguage>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'language', $pb.PbFieldType.OE, defaultOrMaker: STTLanguage.STT_LANGUAGE_UNSPECIFIED, valueOf: STTLanguage.valueOf, enumValues: STTLanguage.values)
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sampleRate', $pb.PbFieldType.O3)
    ..aOB(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'enableVad')
    ..e<$1.AudioFormat>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'audioFormat', $pb.PbFieldType.OE, defaultOrMaker: $1.AudioFormat.AUDIO_FORMAT_UNSPECIFIED, valueOf: $1.AudioFormat.valueOf, enumValues: $1.AudioFormat.values)
    ..hasRequiredFields = false
  ;

  STTConfiguration._() : super();
  factory STTConfiguration({
    $core.String? modelId,
    STTLanguage? language,
    $core.int? sampleRate,
    $core.bool? enableVad,
    $1.AudioFormat? audioFormat,
  }) {
    final _result = create();
    if (modelId != null) {
      _result.modelId = modelId;
    }
    if (language != null) {
      _result.language = language;
    }
    if (sampleRate != null) {
      _result.sampleRate = sampleRate;
    }
    if (enableVad != null) {
      _result.enableVad = enableVad;
    }
    if (audioFormat != null) {
      _result.audioFormat = audioFormat;
    }
    return _result;
  }
  factory STTConfiguration.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory STTConfiguration.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  STTConfiguration clone() => STTConfiguration()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  STTConfiguration copyWith(void Function(STTConfiguration) updates) => super.copyWith((message) => updates(message as STTConfiguration)) as STTConfiguration; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static STTConfiguration create() => STTConfiguration._();
  STTConfiguration createEmptyInstance() => create();
  static $pb.PbList<STTConfiguration> createRepeated() => $pb.PbList<STTConfiguration>();
  @$core.pragma('dart2js:noInline')
  static STTConfiguration getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<STTConfiguration>(create);
  static STTConfiguration? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => clearField(1);

  @$pb.TagNumber(2)
  STTLanguage get language => $_getN(1);
  @$pb.TagNumber(2)
  set language(STTLanguage v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasLanguage() => $_has(1);
  @$pb.TagNumber(2)
  void clearLanguage() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get sampleRate => $_getIZ(2);
  @$pb.TagNumber(3)
  set sampleRate($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSampleRate() => $_has(2);
  @$pb.TagNumber(3)
  void clearSampleRate() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get enableVad => $_getBF(3);
  @$pb.TagNumber(4)
  set enableVad($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasEnableVad() => $_has(3);
  @$pb.TagNumber(4)
  void clearEnableVad() => clearField(4);

  @$pb.TagNumber(5)
  $1.AudioFormat get audioFormat => $_getN(4);
  @$pb.TagNumber(5)
  set audioFormat($1.AudioFormat v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasAudioFormat() => $_has(4);
  @$pb.TagNumber(5)
  void clearAudioFormat() => clearField(5);
}

class STTOptions extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'STTOptions', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<STTLanguage>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'language', $pb.PbFieldType.OE, defaultOrMaker: STTLanguage.STT_LANGUAGE_UNSPECIFIED, valueOf: STTLanguage.valueOf, enumValues: STTLanguage.values)
    ..aOB(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'enablePunctuation')
    ..aOB(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'enableDiarization')
    ..a<$core.int>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'maxSpeakers', $pb.PbFieldType.O3)
    ..pPS(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'vocabularyList')
    ..aOB(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'enableWordTimestamps')
    ..a<$core.int>(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'beamSize', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  STTOptions._() : super();
  factory STTOptions({
    STTLanguage? language,
    $core.bool? enablePunctuation,
    $core.bool? enableDiarization,
    $core.int? maxSpeakers,
    $core.Iterable<$core.String>? vocabularyList,
    $core.bool? enableWordTimestamps,
    $core.int? beamSize,
  }) {
    final _result = create();
    if (language != null) {
      _result.language = language;
    }
    if (enablePunctuation != null) {
      _result.enablePunctuation = enablePunctuation;
    }
    if (enableDiarization != null) {
      _result.enableDiarization = enableDiarization;
    }
    if (maxSpeakers != null) {
      _result.maxSpeakers = maxSpeakers;
    }
    if (vocabularyList != null) {
      _result.vocabularyList.addAll(vocabularyList);
    }
    if (enableWordTimestamps != null) {
      _result.enableWordTimestamps = enableWordTimestamps;
    }
    if (beamSize != null) {
      _result.beamSize = beamSize;
    }
    return _result;
  }
  factory STTOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory STTOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  STTOptions clone() => STTOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  STTOptions copyWith(void Function(STTOptions) updates) => super.copyWith((message) => updates(message as STTOptions)) as STTOptions; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static STTOptions create() => STTOptions._();
  STTOptions createEmptyInstance() => create();
  static $pb.PbList<STTOptions> createRepeated() => $pb.PbList<STTOptions>();
  @$core.pragma('dart2js:noInline')
  static STTOptions getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<STTOptions>(create);
  static STTOptions? _defaultInstance;

  @$pb.TagNumber(1)
  STTLanguage get language => $_getN(0);
  @$pb.TagNumber(1)
  set language(STTLanguage v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasLanguage() => $_has(0);
  @$pb.TagNumber(1)
  void clearLanguage() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get enablePunctuation => $_getBF(1);
  @$pb.TagNumber(2)
  set enablePunctuation($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasEnablePunctuation() => $_has(1);
  @$pb.TagNumber(2)
  void clearEnablePunctuation() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get enableDiarization => $_getBF(2);
  @$pb.TagNumber(3)
  set enableDiarization($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasEnableDiarization() => $_has(2);
  @$pb.TagNumber(3)
  void clearEnableDiarization() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get maxSpeakers => $_getIZ(3);
  @$pb.TagNumber(4)
  set maxSpeakers($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasMaxSpeakers() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxSpeakers() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.String> get vocabularyList => $_getList(4);

  @$pb.TagNumber(6)
  $core.bool get enableWordTimestamps => $_getBF(5);
  @$pb.TagNumber(6)
  set enableWordTimestamps($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasEnableWordTimestamps() => $_has(5);
  @$pb.TagNumber(6)
  void clearEnableWordTimestamps() => clearField(6);

  @$pb.TagNumber(7)
  $core.int get beamSize => $_getIZ(6);
  @$pb.TagNumber(7)
  set beamSize($core.int v) { $_setSignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasBeamSize() => $_has(6);
  @$pb.TagNumber(7)
  void clearBeamSize() => clearField(7);
}

class WordTimestamp extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'WordTimestamp', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'word')
    ..aInt64(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'startMs')
    ..aInt64(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'endMs')
    ..a<$core.double>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'confidence', $pb.PbFieldType.OF)
    ..hasRequiredFields = false
  ;

  WordTimestamp._() : super();
  factory WordTimestamp({
    $core.String? word,
    $fixnum.Int64? startMs,
    $fixnum.Int64? endMs,
    $core.double? confidence,
  }) {
    final _result = create();
    if (word != null) {
      _result.word = word;
    }
    if (startMs != null) {
      _result.startMs = startMs;
    }
    if (endMs != null) {
      _result.endMs = endMs;
    }
    if (confidence != null) {
      _result.confidence = confidence;
    }
    return _result;
  }
  factory WordTimestamp.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory WordTimestamp.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  WordTimestamp clone() => WordTimestamp()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  WordTimestamp copyWith(void Function(WordTimestamp) updates) => super.copyWith((message) => updates(message as WordTimestamp)) as WordTimestamp; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static WordTimestamp create() => WordTimestamp._();
  WordTimestamp createEmptyInstance() => create();
  static $pb.PbList<WordTimestamp> createRepeated() => $pb.PbList<WordTimestamp>();
  @$core.pragma('dart2js:noInline')
  static WordTimestamp getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WordTimestamp>(create);
  static WordTimestamp? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get word => $_getSZ(0);
  @$pb.TagNumber(1)
  set word($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasWord() => $_has(0);
  @$pb.TagNumber(1)
  void clearWord() => clearField(1);

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

  @$pb.TagNumber(4)
  $core.double get confidence => $_getN(3);
  @$pb.TagNumber(4)
  set confidence($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasConfidence() => $_has(3);
  @$pb.TagNumber(4)
  void clearConfidence() => clearField(4);
}

class TranscriptionAlternative extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'TranscriptionAlternative', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'text')
    ..a<$core.double>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'confidence', $pb.PbFieldType.OF)
    ..pc<WordTimestamp>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'words', $pb.PbFieldType.PM, subBuilder: WordTimestamp.create)
    ..hasRequiredFields = false
  ;

  TranscriptionAlternative._() : super();
  factory TranscriptionAlternative({
    $core.String? text,
    $core.double? confidence,
    $core.Iterable<WordTimestamp>? words,
  }) {
    final _result = create();
    if (text != null) {
      _result.text = text;
    }
    if (confidence != null) {
      _result.confidence = confidence;
    }
    if (words != null) {
      _result.words.addAll(words);
    }
    return _result;
  }
  factory TranscriptionAlternative.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TranscriptionAlternative.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TranscriptionAlternative clone() => TranscriptionAlternative()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TranscriptionAlternative copyWith(void Function(TranscriptionAlternative) updates) => super.copyWith((message) => updates(message as TranscriptionAlternative)) as TranscriptionAlternative; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static TranscriptionAlternative create() => TranscriptionAlternative._();
  TranscriptionAlternative createEmptyInstance() => create();
  static $pb.PbList<TranscriptionAlternative> createRepeated() => $pb.PbList<TranscriptionAlternative>();
  @$core.pragma('dart2js:noInline')
  static TranscriptionAlternative getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TranscriptionAlternative>(create);
  static TranscriptionAlternative? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => clearField(1);

  @$pb.TagNumber(2)
  $core.double get confidence => $_getN(1);
  @$pb.TagNumber(2)
  set confidence($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasConfidence() => $_has(1);
  @$pb.TagNumber(2)
  void clearConfidence() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<WordTimestamp> get words => $_getList(2);
}

class TranscriptionMetadata extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'TranscriptionMetadata', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'modelId')
    ..aInt64(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'processingTimeMs')
    ..aInt64(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'audioLengthMs')
    ..a<$core.double>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'realTimeFactor', $pb.PbFieldType.OF)
    ..hasRequiredFields = false
  ;

  TranscriptionMetadata._() : super();
  factory TranscriptionMetadata({
    $core.String? modelId,
    $fixnum.Int64? processingTimeMs,
    $fixnum.Int64? audioLengthMs,
    $core.double? realTimeFactor,
  }) {
    final _result = create();
    if (modelId != null) {
      _result.modelId = modelId;
    }
    if (processingTimeMs != null) {
      _result.processingTimeMs = processingTimeMs;
    }
    if (audioLengthMs != null) {
      _result.audioLengthMs = audioLengthMs;
    }
    if (realTimeFactor != null) {
      _result.realTimeFactor = realTimeFactor;
    }
    return _result;
  }
  factory TranscriptionMetadata.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TranscriptionMetadata.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TranscriptionMetadata clone() => TranscriptionMetadata()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TranscriptionMetadata copyWith(void Function(TranscriptionMetadata) updates) => super.copyWith((message) => updates(message as TranscriptionMetadata)) as TranscriptionMetadata; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static TranscriptionMetadata create() => TranscriptionMetadata._();
  TranscriptionMetadata createEmptyInstance() => create();
  static $pb.PbList<TranscriptionMetadata> createRepeated() => $pb.PbList<TranscriptionMetadata>();
  @$core.pragma('dart2js:noInline')
  static TranscriptionMetadata getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TranscriptionMetadata>(create);
  static TranscriptionMetadata? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get processingTimeMs => $_getI64(1);
  @$pb.TagNumber(2)
  set processingTimeMs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasProcessingTimeMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearProcessingTimeMs() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get audioLengthMs => $_getI64(2);
  @$pb.TagNumber(3)
  set audioLengthMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAudioLengthMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearAudioLengthMs() => clearField(3);

  @$pb.TagNumber(4)
  $core.double get realTimeFactor => $_getN(3);
  @$pb.TagNumber(4)
  set realTimeFactor($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasRealTimeFactor() => $_has(3);
  @$pb.TagNumber(4)
  void clearRealTimeFactor() => clearField(4);
}

class STTOutput extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'STTOutput', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'text')
    ..e<STTLanguage>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'language', $pb.PbFieldType.OE, defaultOrMaker: STTLanguage.STT_LANGUAGE_UNSPECIFIED, valueOf: STTLanguage.valueOf, enumValues: STTLanguage.values)
    ..a<$core.double>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'confidence', $pb.PbFieldType.OF)
    ..pc<WordTimestamp>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'words', $pb.PbFieldType.PM, subBuilder: WordTimestamp.create)
    ..pc<TranscriptionAlternative>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'alternatives', $pb.PbFieldType.PM, subBuilder: TranscriptionAlternative.create)
    ..aOM<TranscriptionMetadata>(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'metadata', subBuilder: TranscriptionMetadata.create)
    ..hasRequiredFields = false
  ;

  STTOutput._() : super();
  factory STTOutput({
    $core.String? text,
    STTLanguage? language,
    $core.double? confidence,
    $core.Iterable<WordTimestamp>? words,
    $core.Iterable<TranscriptionAlternative>? alternatives,
    TranscriptionMetadata? metadata,
  }) {
    final _result = create();
    if (text != null) {
      _result.text = text;
    }
    if (language != null) {
      _result.language = language;
    }
    if (confidence != null) {
      _result.confidence = confidence;
    }
    if (words != null) {
      _result.words.addAll(words);
    }
    if (alternatives != null) {
      _result.alternatives.addAll(alternatives);
    }
    if (metadata != null) {
      _result.metadata = metadata;
    }
    return _result;
  }
  factory STTOutput.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory STTOutput.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  STTOutput clone() => STTOutput()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  STTOutput copyWith(void Function(STTOutput) updates) => super.copyWith((message) => updates(message as STTOutput)) as STTOutput; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static STTOutput create() => STTOutput._();
  STTOutput createEmptyInstance() => create();
  static $pb.PbList<STTOutput> createRepeated() => $pb.PbList<STTOutput>();
  @$core.pragma('dart2js:noInline')
  static STTOutput getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<STTOutput>(create);
  static STTOutput? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => clearField(1);

  @$pb.TagNumber(2)
  STTLanguage get language => $_getN(1);
  @$pb.TagNumber(2)
  set language(STTLanguage v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasLanguage() => $_has(1);
  @$pb.TagNumber(2)
  void clearLanguage() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get confidence => $_getN(2);
  @$pb.TagNumber(3)
  set confidence($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasConfidence() => $_has(2);
  @$pb.TagNumber(3)
  void clearConfidence() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<WordTimestamp> get words => $_getList(3);

  @$pb.TagNumber(5)
  $core.List<TranscriptionAlternative> get alternatives => $_getList(4);

  @$pb.TagNumber(6)
  TranscriptionMetadata get metadata => $_getN(5);
  @$pb.TagNumber(6)
  set metadata(TranscriptionMetadata v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasMetadata() => $_has(5);
  @$pb.TagNumber(6)
  void clearMetadata() => clearField(6);
  @$pb.TagNumber(6)
  TranscriptionMetadata ensureMetadata() => $_ensure(5);
}

class STTPartialResult extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'STTPartialResult', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'text')
    ..aOB(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'isFinal')
    ..a<$core.double>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'stability', $pb.PbFieldType.OF)
    ..hasRequiredFields = false
  ;

  STTPartialResult._() : super();
  factory STTPartialResult({
    $core.String? text,
    $core.bool? isFinal,
    $core.double? stability,
  }) {
    final _result = create();
    if (text != null) {
      _result.text = text;
    }
    if (isFinal != null) {
      _result.isFinal = isFinal;
    }
    if (stability != null) {
      _result.stability = stability;
    }
    return _result;
  }
  factory STTPartialResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory STTPartialResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  STTPartialResult clone() => STTPartialResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  STTPartialResult copyWith(void Function(STTPartialResult) updates) => super.copyWith((message) => updates(message as STTPartialResult)) as STTPartialResult; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static STTPartialResult create() => STTPartialResult._();
  STTPartialResult createEmptyInstance() => create();
  static $pb.PbList<STTPartialResult> createRepeated() => $pb.PbList<STTPartialResult>();
  @$core.pragma('dart2js:noInline')
  static STTPartialResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<STTPartialResult>(create);
  static STTPartialResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get isFinal => $_getBF(1);
  @$pb.TagNumber(2)
  set isFinal($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasIsFinal() => $_has(1);
  @$pb.TagNumber(2)
  void clearIsFinal() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get stability => $_getN(2);
  @$pb.TagNumber(3)
  set stability($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasStability() => $_has(2);
  @$pb.TagNumber(3)
  void clearStability() => clearField(3);
}

