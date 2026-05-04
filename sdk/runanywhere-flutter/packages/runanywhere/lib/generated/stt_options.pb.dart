//
//  Generated code. Do not modify.
//  source: stt_options.proto
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
import 'stt_options.pbenum.dart';

export 'stt_options.pbenum.dart';

///  ---------------------------------------------------------------------------
///  STT component configuration (init-time settings).
///  Sources pre-IDL:
///    Swift  STTTypes.swift:15           STTConfiguration
///    Kotlin STTTypes.kt:27              STTConfiguration
///    Dart   stt_configuration.dart:9    STTConfiguration
///    C ABI  rac_stt_types.h:76          rac_stt_config_t
///
///  Note: max_alternatives, enable_punctuation, enable_diarization, and
///  enable_timestamps appear in the pre-IDL configs but are runtime knobs
///  in the canonical model. They live on STTOptions; STTConfiguration
///  keeps only true init-time fields (model id, language, sample rate,
///  VAD toggle, audio format). Producers should mirror runtime knobs into
///  STTOptions when constructing requests.
///  ---------------------------------------------------------------------------
class STTConfiguration extends $pb.GeneratedMessage {
  factory STTConfiguration({
    $core.String? modelId,
    STTLanguage? language,
    $core.int? sampleRate,
    $core.bool? enableVad,
    $0.AudioFormat? audioFormat,
    $core.bool? enablePunctuation,
    $core.bool? enableDiarization,
    $core.Iterable<$core.String>? vocabularyList,
    $core.int? maxAlternatives,
    $core.bool? enableWordTimestamps,
    $0.InferenceFramework? preferredFramework,
    $core.String? languageCode,
  }) {
    final $result = create();
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (language != null) {
      $result.language = language;
    }
    if (sampleRate != null) {
      $result.sampleRate = sampleRate;
    }
    if (enableVad != null) {
      $result.enableVad = enableVad;
    }
    if (audioFormat != null) {
      $result.audioFormat = audioFormat;
    }
    if (enablePunctuation != null) {
      $result.enablePunctuation = enablePunctuation;
    }
    if (enableDiarization != null) {
      $result.enableDiarization = enableDiarization;
    }
    if (vocabularyList != null) {
      $result.vocabularyList.addAll(vocabularyList);
    }
    if (maxAlternatives != null) {
      $result.maxAlternatives = maxAlternatives;
    }
    if (enableWordTimestamps != null) {
      $result.enableWordTimestamps = enableWordTimestamps;
    }
    if (preferredFramework != null) {
      $result.preferredFramework = preferredFramework;
    }
    if (languageCode != null) {
      $result.languageCode = languageCode;
    }
    return $result;
  }
  STTConfiguration._() : super();
  factory STTConfiguration.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory STTConfiguration.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'STTConfiguration', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..e<STTLanguage>(2, _omitFieldNames ? '' : 'language', $pb.PbFieldType.OE, defaultOrMaker: STTLanguage.STT_LANGUAGE_UNSPECIFIED, valueOf: STTLanguage.valueOf, enumValues: STTLanguage.values)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'sampleRate', $pb.PbFieldType.O3)
    ..aOB(4, _omitFieldNames ? '' : 'enableVad')
    ..e<$0.AudioFormat>(5, _omitFieldNames ? '' : 'audioFormat', $pb.PbFieldType.OE, defaultOrMaker: $0.AudioFormat.AUDIO_FORMAT_UNSPECIFIED, valueOf: $0.AudioFormat.valueOf, enumValues: $0.AudioFormat.values)
    ..aOB(6, _omitFieldNames ? '' : 'enablePunctuation')
    ..aOB(7, _omitFieldNames ? '' : 'enableDiarization')
    ..pPS(8, _omitFieldNames ? '' : 'vocabularyList')
    ..a<$core.int>(9, _omitFieldNames ? '' : 'maxAlternatives', $pb.PbFieldType.O3)
    ..aOB(10, _omitFieldNames ? '' : 'enableWordTimestamps')
    ..e<$0.InferenceFramework>(11, _omitFieldNames ? '' : 'preferredFramework', $pb.PbFieldType.OE, defaultOrMaker: $0.InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED, valueOf: $0.InferenceFramework.valueOf, enumValues: $0.InferenceFramework.values)
    ..aOS(12, _omitFieldNames ? '' : 'languageCode')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  STTConfiguration clone() => STTConfiguration()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  STTConfiguration copyWith(void Function(STTConfiguration) updates) => super.copyWith((message) => updates(message as STTConfiguration)) as STTConfiguration;

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
  $0.AudioFormat get audioFormat => $_getN(4);
  @$pb.TagNumber(5)
  set audioFormat($0.AudioFormat v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasAudioFormat() => $_has(4);
  @$pb.TagNumber(5)
  void clearAudioFormat() => clearField(5);

  /// C ABI / legacy SDK config-level transcription defaults. These may be
  /// mirrored into STTOptions by adapters for per-call overrides.
  @$pb.TagNumber(6)
  $core.bool get enablePunctuation => $_getBF(5);
  @$pb.TagNumber(6)
  set enablePunctuation($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasEnablePunctuation() => $_has(5);
  @$pb.TagNumber(6)
  void clearEnablePunctuation() => clearField(6);

  @$pb.TagNumber(7)
  $core.bool get enableDiarization => $_getBF(6);
  @$pb.TagNumber(7)
  set enableDiarization($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasEnableDiarization() => $_has(6);
  @$pb.TagNumber(7)
  void clearEnableDiarization() => clearField(7);

  @$pb.TagNumber(8)
  $core.List<$core.String> get vocabularyList => $_getList(7);

  @$pb.TagNumber(9)
  $core.int get maxAlternatives => $_getIZ(8);
  @$pb.TagNumber(9)
  set maxAlternatives($core.int v) { $_setSignedInt32(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasMaxAlternatives() => $_has(8);
  @$pb.TagNumber(9)
  void clearMaxAlternatives() => clearField(9);

  @$pb.TagNumber(10)
  $core.bool get enableWordTimestamps => $_getBF(9);
  @$pb.TagNumber(10)
  set enableWordTimestamps($core.bool v) { $_setBool(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasEnableWordTimestamps() => $_has(9);
  @$pb.TagNumber(10)
  void clearEnableWordTimestamps() => clearField(10);

  /// Preferred framework for the component. Absent = auto.
  @$pb.TagNumber(11)
  $0.InferenceFramework get preferredFramework => $_getN(10);
  @$pb.TagNumber(11)
  set preferredFramework($0.InferenceFramework v) { setField(11, v); }
  @$pb.TagNumber(11)
  $core.bool hasPreferredFramework() => $_has(10);
  @$pb.TagNumber(11)
  void clearPreferredFramework() => clearField(11);

  /// Free-form BCP-47 language tag ("en-US", "pt-BR", etc.) for callers
  /// that cannot be represented by STTLanguage's base-code enum.
  @$pb.TagNumber(12)
  $core.String get languageCode => $_getSZ(11);
  @$pb.TagNumber(12)
  set languageCode($core.String v) { $_setString(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasLanguageCode() => $_has(11);
  @$pb.TagNumber(12)
  void clearLanguageCode() => clearField(12);
}

///  ---------------------------------------------------------------------------
///  STT runtime transcription options (per-call overrides).
///  Sources pre-IDL:
///    Swift  STTTypes.swift:64           STTOptions  (10 fields)
///    Kotlin STTTypes.kt:65              STTOptions  (10 fields)
///    Dart   generation_types.dart:78    STTOptions  (10 fields)
///    RN     STTTypes.ts:12              STTOptions  (5 fields, narrower)
///    Web    STTTypes.ts:25              STTTranscribeOptions (2 fields)
///    C ABI  rac_stt_types.h:130         rac_stt_options_t (8 fields)
///
///  Per spec, this canonical message exposes: language, enable_punctuation,
///  enable_diarization, max_speakers, vocabulary_list, enable_word_timestamps,
///  beam_size. Other pre-IDL fields (audio_format, sample_rate, detect_language,
///  preferred_framework) are part of STTConfiguration or implied by
///  STT_LANGUAGE_AUTO.
///  ---------------------------------------------------------------------------
class STTOptions extends $pb.GeneratedMessage {
  factory STTOptions({
    STTLanguage? language,
    $core.bool? enablePunctuation,
    $core.bool? enableDiarization,
    $core.int? maxSpeakers,
    $core.Iterable<$core.String>? vocabularyList,
    $core.bool? enableWordTimestamps,
    $core.int? beamSize,
    $core.String? languageCode,
    $core.bool? detectLanguage,
    $0.AudioFormat? audioFormat,
    $core.int? sampleRate,
    $core.int? maxAlternatives,
  }) {
    final $result = create();
    if (language != null) {
      $result.language = language;
    }
    if (enablePunctuation != null) {
      $result.enablePunctuation = enablePunctuation;
    }
    if (enableDiarization != null) {
      $result.enableDiarization = enableDiarization;
    }
    if (maxSpeakers != null) {
      $result.maxSpeakers = maxSpeakers;
    }
    if (vocabularyList != null) {
      $result.vocabularyList.addAll(vocabularyList);
    }
    if (enableWordTimestamps != null) {
      $result.enableWordTimestamps = enableWordTimestamps;
    }
    if (beamSize != null) {
      $result.beamSize = beamSize;
    }
    if (languageCode != null) {
      $result.languageCode = languageCode;
    }
    if (detectLanguage != null) {
      $result.detectLanguage = detectLanguage;
    }
    if (audioFormat != null) {
      $result.audioFormat = audioFormat;
    }
    if (sampleRate != null) {
      $result.sampleRate = sampleRate;
    }
    if (maxAlternatives != null) {
      $result.maxAlternatives = maxAlternatives;
    }
    return $result;
  }
  STTOptions._() : super();
  factory STTOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory STTOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'STTOptions', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<STTLanguage>(1, _omitFieldNames ? '' : 'language', $pb.PbFieldType.OE, defaultOrMaker: STTLanguage.STT_LANGUAGE_UNSPECIFIED, valueOf: STTLanguage.valueOf, enumValues: STTLanguage.values)
    ..aOB(2, _omitFieldNames ? '' : 'enablePunctuation')
    ..aOB(3, _omitFieldNames ? '' : 'enableDiarization')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'maxSpeakers', $pb.PbFieldType.O3)
    ..pPS(5, _omitFieldNames ? '' : 'vocabularyList')
    ..aOB(6, _omitFieldNames ? '' : 'enableWordTimestamps')
    ..a<$core.int>(7, _omitFieldNames ? '' : 'beamSize', $pb.PbFieldType.O3)
    ..aOS(8, _omitFieldNames ? '' : 'languageCode')
    ..aOB(9, _omitFieldNames ? '' : 'detectLanguage')
    ..e<$0.AudioFormat>(10, _omitFieldNames ? '' : 'audioFormat', $pb.PbFieldType.OE, defaultOrMaker: $0.AudioFormat.AUDIO_FORMAT_UNSPECIFIED, valueOf: $0.AudioFormat.valueOf, enumValues: $0.AudioFormat.values)
    ..a<$core.int>(11, _omitFieldNames ? '' : 'sampleRate', $pb.PbFieldType.O3)
    ..a<$core.int>(12, _omitFieldNames ? '' : 'maxAlternatives', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  STTOptions clone() => STTOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  STTOptions copyWith(void Function(STTOptions) updates) => super.copyWith((message) => updates(message as STTOptions)) as STTOptions;

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

  /// Free-form BCP-47 language tag. When set, consumers should prefer this
  /// over the base-language enum above.
  @$pb.TagNumber(8)
  $core.String get languageCode => $_getSZ(7);
  @$pb.TagNumber(8)
  set languageCode($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasLanguageCode() => $_has(7);
  @$pb.TagNumber(8)
  void clearLanguageCode() => clearField(8);

  /// Explicit language auto-detection flag for C ABI parity. Equivalent to
  /// language == STT_LANGUAGE_AUTO for generated-only consumers.
  @$pb.TagNumber(9)
  $core.bool get detectLanguage => $_getBF(8);
  @$pb.TagNumber(9)
  set detectLanguage($core.bool v) { $_setBool(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasDetectLanguage() => $_has(8);
  @$pb.TagNumber(9)
  void clearDetectLanguage() => clearField(9);

  /// Per-call input audio hints mirrored from rac_stt_options_t.
  @$pb.TagNumber(10)
  $0.AudioFormat get audioFormat => $_getN(9);
  @$pb.TagNumber(10)
  set audioFormat($0.AudioFormat v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasAudioFormat() => $_has(9);
  @$pb.TagNumber(10)
  void clearAudioFormat() => clearField(10);

  @$pb.TagNumber(11)
  $core.int get sampleRate => $_getIZ(10);
  @$pb.TagNumber(11)
  set sampleRate($core.int v) { $_setSignedInt32(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasSampleRate() => $_has(10);
  @$pb.TagNumber(11)
  void clearSampleRate() => clearField(11);

  /// Maximum number of alternatives to return. 0 = backend/default.
  @$pb.TagNumber(12)
  $core.int get maxAlternatives => $_getIZ(11);
  @$pb.TagNumber(12)
  set maxAlternatives($core.int v) { $_setSignedInt32(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasMaxAlternatives() => $_has(11);
  @$pb.TagNumber(12)
  void clearMaxAlternatives() => clearField(12);
}

///  ---------------------------------------------------------------------------
///  Word-level timestamp.
///  Sources pre-IDL:
///    Swift  STTTypes.swift:260          WordTimestamp (TimeInterval seconds)
///    Kotlin STTTypes.kt:141             WordTimestamp (Double seconds)
///    Dart   generation_types.dart:124   WordTimestamp (double seconds, conf?)
///    RN     STTTypes.ts:55              WordTimestamp (number seconds)
///    Web    STTTypes.ts:18              STTWord       (number ms)
///    C ABI  rac_stt_types.h:175         rac_stt_word_t (int64 ms)
///
///  Canonicalize on int64 *_ms (matches C ABI and Web).
///  ---------------------------------------------------------------------------
class WordTimestamp extends $pb.GeneratedMessage {
  factory WordTimestamp({
    $core.String? word,
    $fixnum.Int64? startMs,
    $fixnum.Int64? endMs,
    $core.double? confidence,
  }) {
    final $result = create();
    if (word != null) {
      $result.word = word;
    }
    if (startMs != null) {
      $result.startMs = startMs;
    }
    if (endMs != null) {
      $result.endMs = endMs;
    }
    if (confidence != null) {
      $result.confidence = confidence;
    }
    return $result;
  }
  WordTimestamp._() : super();
  factory WordTimestamp.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory WordTimestamp.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'WordTimestamp', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'word')
    ..aInt64(2, _omitFieldNames ? '' : 'startMs')
    ..aInt64(3, _omitFieldNames ? '' : 'endMs')
    ..a<$core.double>(4, _omitFieldNames ? '' : 'confidence', $pb.PbFieldType.OF)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  WordTimestamp clone() => WordTimestamp()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  WordTimestamp copyWith(void Function(WordTimestamp) updates) => super.copyWith((message) => updates(message as WordTimestamp)) as WordTimestamp;

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

///  ---------------------------------------------------------------------------
///  Alternative transcription hypothesis (n-best).
///  Sources pre-IDL:
///    Swift  STTTypes.swift:275          TranscriptionAlternative (text, confidence)
///    Kotlin STTTypes.kt:155             TranscriptionAlternative (text, confidence)
///    Dart   generation_types.dart:146   TranscriptionAlternative (transcript, confidence)
///    RN     STTTypes.ts:65              STTAlternative (text, confidence)
///    C ABI  rac_stt_types.h:320         rac_transcription_alternative_t (text, confidence)
///
///  Drift: Dart uses `transcript` while everyone else uses `text`. Canonical
///  field name is `text`. Per-word breakdown is OPTIONAL (only some backends
///  emit it for alternatives).
///  ---------------------------------------------------------------------------
class TranscriptionAlternative extends $pb.GeneratedMessage {
  factory TranscriptionAlternative({
    $core.String? text,
    $core.double? confidence,
    $core.Iterable<WordTimestamp>? words,
  }) {
    final $result = create();
    if (text != null) {
      $result.text = text;
    }
    if (confidence != null) {
      $result.confidence = confidence;
    }
    if (words != null) {
      $result.words.addAll(words);
    }
    return $result;
  }
  TranscriptionAlternative._() : super();
  factory TranscriptionAlternative.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TranscriptionAlternative.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TranscriptionAlternative', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..a<$core.double>(2, _omitFieldNames ? '' : 'confidence', $pb.PbFieldType.OF)
    ..pc<WordTimestamp>(3, _omitFieldNames ? '' : 'words', $pb.PbFieldType.PM, subBuilder: WordTimestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TranscriptionAlternative clone() => TranscriptionAlternative()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TranscriptionAlternative copyWith(void Function(TranscriptionAlternative) updates) => super.copyWith((message) => updates(message as TranscriptionAlternative)) as TranscriptionAlternative;

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

///  ---------------------------------------------------------------------------
///  Per-pass transcription metadata.
///  Sources pre-IDL:
///    Swift  STTTypes.swift:241          TranscriptionMetadata (s + computed RTF)
///    Kotlin STTTypes.kt:124             TranscriptionMetadata (s + computed RTF)
///    Dart   generation_types.dart:160   TranscriptionMetadata (s + computed RTF)
///    RN     STTTypes.ts:73              TranscriptionMetadata (s + optional RTF)
///    C ABI  rac_stt_types.h:297         rac_transcription_metadata_t (ms + RTF)
///
///  Canonicalize on ms (matches C ABI). real_time_factor is producer-set;
///  consumers may recompute as processing_time_ms / audio_length_ms.
///  ---------------------------------------------------------------------------
class TranscriptionMetadata extends $pb.GeneratedMessage {
  factory TranscriptionMetadata({
    $core.String? modelId,
    $fixnum.Int64? processingTimeMs,
    $fixnum.Int64? audioLengthMs,
    $core.double? realTimeFactor,
  }) {
    final $result = create();
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (processingTimeMs != null) {
      $result.processingTimeMs = processingTimeMs;
    }
    if (audioLengthMs != null) {
      $result.audioLengthMs = audioLengthMs;
    }
    if (realTimeFactor != null) {
      $result.realTimeFactor = realTimeFactor;
    }
    return $result;
  }
  TranscriptionMetadata._() : super();
  factory TranscriptionMetadata.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TranscriptionMetadata.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TranscriptionMetadata', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aInt64(2, _omitFieldNames ? '' : 'processingTimeMs')
    ..aInt64(3, _omitFieldNames ? '' : 'audioLengthMs')
    ..a<$core.double>(4, _omitFieldNames ? '' : 'realTimeFactor', $pb.PbFieldType.OF)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TranscriptionMetadata clone() => TranscriptionMetadata()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TranscriptionMetadata copyWith(void Function(TranscriptionMetadata) updates) => super.copyWith((message) => updates(message as TranscriptionMetadata)) as TranscriptionMetadata;

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

///  ---------------------------------------------------------------------------
///  Final STT output.
///  Sources pre-IDL:
///    Swift  STTTypes.swift:147          STTOutput (text, conf, words, lang, alts, meta, ts)
///    Kotlin STTTypes.kt:100             STTOutput (text, conf, words, lang, alts, meta, ts)
///    Dart   generation_types.dart:218   STTResult / STTOutput (text, conf, durMs, lang, words, alts, meta, ts)
///    RN     STTTypes.ts:32              STTOutput (text, conf, words, lang, alts, meta)
///    Web    STTTypes.ts:9               STTTranscriptionResult (text, conf, lang, procMs, words)
///    C ABI  rac_stt_types.h:338         rac_stt_output_t (text, conf, words, lang, alts, meta, ts_ms)
///
///  Drift reconciled:
///    - language: detected language. Promoted to STTLanguage enum.
///    - durationMs (Dart) / processingTimeMs (Web) → captured in metadata.
///  ---------------------------------------------------------------------------
class STTOutput extends $pb.GeneratedMessage {
  factory STTOutput({
    $core.String? text,
    STTLanguage? language,
    $core.double? confidence,
    $core.Iterable<WordTimestamp>? words,
    $core.Iterable<TranscriptionAlternative>? alternatives,
    TranscriptionMetadata? metadata,
    $core.String? languageCode,
    $fixnum.Int64? timestampMs,
    $fixnum.Int64? durationMs,
  }) {
    final $result = create();
    if (text != null) {
      $result.text = text;
    }
    if (language != null) {
      $result.language = language;
    }
    if (confidence != null) {
      $result.confidence = confidence;
    }
    if (words != null) {
      $result.words.addAll(words);
    }
    if (alternatives != null) {
      $result.alternatives.addAll(alternatives);
    }
    if (metadata != null) {
      $result.metadata = metadata;
    }
    if (languageCode != null) {
      $result.languageCode = languageCode;
    }
    if (timestampMs != null) {
      $result.timestampMs = timestampMs;
    }
    if (durationMs != null) {
      $result.durationMs = durationMs;
    }
    return $result;
  }
  STTOutput._() : super();
  factory STTOutput.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory STTOutput.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'STTOutput', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..e<STTLanguage>(2, _omitFieldNames ? '' : 'language', $pb.PbFieldType.OE, defaultOrMaker: STTLanguage.STT_LANGUAGE_UNSPECIFIED, valueOf: STTLanguage.valueOf, enumValues: STTLanguage.values)
    ..a<$core.double>(3, _omitFieldNames ? '' : 'confidence', $pb.PbFieldType.OF)
    ..pc<WordTimestamp>(4, _omitFieldNames ? '' : 'words', $pb.PbFieldType.PM, subBuilder: WordTimestamp.create)
    ..pc<TranscriptionAlternative>(5, _omitFieldNames ? '' : 'alternatives', $pb.PbFieldType.PM, subBuilder: TranscriptionAlternative.create)
    ..aOM<TranscriptionMetadata>(6, _omitFieldNames ? '' : 'metadata', subBuilder: TranscriptionMetadata.create)
    ..aOS(7, _omitFieldNames ? '' : 'languageCode')
    ..aInt64(8, _omitFieldNames ? '' : 'timestampMs')
    ..aInt64(9, _omitFieldNames ? '' : 'durationMs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  STTOutput clone() => STTOutput()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  STTOutput copyWith(void Function(STTOutput) updates) => super.copyWith((message) => updates(message as STTOutput)) as STTOutput;

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

  /// Free-form detected language tag, preserving regional variants.
  @$pb.TagNumber(7)
  $core.String get languageCode => $_getSZ(6);
  @$pb.TagNumber(7)
  set languageCode($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasLanguageCode() => $_has(6);
  @$pb.TagNumber(7)
  void clearLanguageCode() => clearField(7);

  /// Wall-clock output timestamp in milliseconds since Unix epoch.
  @$pb.TagNumber(8)
  $fixnum.Int64 get timestampMs => $_getI64(7);
  @$pb.TagNumber(8)
  set timestampMs($fixnum.Int64 v) { $_setInt64(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasTimestampMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearTimestampMs() => clearField(8);

  /// Audio duration in milliseconds for SDKs that expose duration directly.
  /// Often duplicates metadata.audio_length_ms.
  @$pb.TagNumber(9)
  $fixnum.Int64 get durationMs => $_getI64(8);
  @$pb.TagNumber(9)
  set durationMs($fixnum.Int64 v) { $_setInt64(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasDurationMs() => $_has(8);
  @$pb.TagNumber(9)
  void clearDurationMs() => clearField(9);
}

///  ---------------------------------------------------------------------------
///  Streaming partial result emitted during live transcription.
///  Sources pre-IDL:
///    Dart   generation_types.dart:184   STTPartialResult (transcript, conf, isFinal, lang, ts, alts)
///    RN     STTTypes.ts:90              STTPartialResult (transcript, conf, ts, lang, alts, isFinal)
///    C ABI  rac_stt_types.h:240         rac_stt_stream_callback_t (partial_text, is_final)
///    Web    STTTypes.ts:31              STTStreamCallback (text, isFinal)
///
///  Canonical minimal shape per spec: text, is_final, stability. Full word
///  timestamps + alternatives flow through STTOutput on the terminal event.
///  `stability` is the Whisper-style hypothesis stability score (0.0-1.0);
///  0.0 when backend does not provide one.
///  ---------------------------------------------------------------------------
class STTPartialResult extends $pb.GeneratedMessage {
  factory STTPartialResult({
    $core.String? text,
    $core.bool? isFinal,
    $core.double? stability,
    $core.double? confidence,
    STTLanguage? language,
    $fixnum.Int64? timestampMs,
    $core.Iterable<TranscriptionAlternative>? alternatives,
    $core.String? languageCode,
  }) {
    final $result = create();
    if (text != null) {
      $result.text = text;
    }
    if (isFinal != null) {
      $result.isFinal = isFinal;
    }
    if (stability != null) {
      $result.stability = stability;
    }
    if (confidence != null) {
      $result.confidence = confidence;
    }
    if (language != null) {
      $result.language = language;
    }
    if (timestampMs != null) {
      $result.timestampMs = timestampMs;
    }
    if (alternatives != null) {
      $result.alternatives.addAll(alternatives);
    }
    if (languageCode != null) {
      $result.languageCode = languageCode;
    }
    return $result;
  }
  STTPartialResult._() : super();
  factory STTPartialResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory STTPartialResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'STTPartialResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOB(2, _omitFieldNames ? '' : 'isFinal')
    ..a<$core.double>(3, _omitFieldNames ? '' : 'stability', $pb.PbFieldType.OF)
    ..a<$core.double>(4, _omitFieldNames ? '' : 'confidence', $pb.PbFieldType.OF)
    ..e<STTLanguage>(5, _omitFieldNames ? '' : 'language', $pb.PbFieldType.OE, defaultOrMaker: STTLanguage.STT_LANGUAGE_UNSPECIFIED, valueOf: STTLanguage.valueOf, enumValues: STTLanguage.values)
    ..aInt64(6, _omitFieldNames ? '' : 'timestampMs')
    ..pc<TranscriptionAlternative>(7, _omitFieldNames ? '' : 'alternatives', $pb.PbFieldType.PM, subBuilder: TranscriptionAlternative.create)
    ..aOS(8, _omitFieldNames ? '' : 'languageCode')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  STTPartialResult clone() => STTPartialResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  STTPartialResult copyWith(void Function(STTPartialResult) updates) => super.copyWith((message) => updates(message as STTPartialResult)) as STTPartialResult;

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

  /// Additional partial-hypothesis fields carried by Dart/RN live streams.
  @$pb.TagNumber(4)
  $core.double get confidence => $_getN(3);
  @$pb.TagNumber(4)
  set confidence($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasConfidence() => $_has(3);
  @$pb.TagNumber(4)
  void clearConfidence() => clearField(4);

  @$pb.TagNumber(5)
  STTLanguage get language => $_getN(4);
  @$pb.TagNumber(5)
  set language(STTLanguage v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasLanguage() => $_has(4);
  @$pb.TagNumber(5)
  void clearLanguage() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get timestampMs => $_getI64(5);
  @$pb.TagNumber(6)
  set timestampMs($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTimestampMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearTimestampMs() => clearField(6);

  @$pb.TagNumber(7)
  $core.List<TranscriptionAlternative> get alternatives => $_getList(6);

  @$pb.TagNumber(8)
  $core.String get languageCode => $_getSZ(7);
  @$pb.TagNumber(8)
  set languageCode($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasLanguageCode() => $_has(7);
  @$pb.TagNumber(8)
  void clearLanguageCode() => clearField(8);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
