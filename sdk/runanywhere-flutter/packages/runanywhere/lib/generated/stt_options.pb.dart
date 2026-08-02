// This is a generated file - do not edit.
//
// Generated from stt_options.proto.

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
import 'stt_options.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'stt_options.pbenum.dart';

/// Init-time settings. Per-call knobs live on STTOptions; adapters mirror the
/// transcription defaults below into STTOptions when building a request.
class STTConfiguration extends $pb.GeneratedMessage {
  factory STTConfiguration({
    $core.String? modelId,
    $core.int? sampleRate,
    $core.bool? enableVad,
    $1.AudioFormat? audioFormat,
    $core.bool? enablePunctuation,
    $core.bool? enableDiarization,
    $core.Iterable<$core.String>? vocabularyList,
    $core.int? maxAlternatives,
    $core.bool? enableWordTimestamps,
    $1.InferenceFramework? preferredFramework,
    $core.String? language,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (sampleRate != null) result.sampleRate = sampleRate;
    if (enableVad != null) result.enableVad = enableVad;
    if (audioFormat != null) result.audioFormat = audioFormat;
    if (enablePunctuation != null) result.enablePunctuation = enablePunctuation;
    if (enableDiarization != null) result.enableDiarization = enableDiarization;
    if (vocabularyList != null) result.vocabularyList.addAll(vocabularyList);
    if (maxAlternatives != null) result.maxAlternatives = maxAlternatives;
    if (enableWordTimestamps != null)
      result.enableWordTimestamps = enableWordTimestamps;
    if (preferredFramework != null)
      result.preferredFramework = preferredFramework;
    if (language != null) result.language = language;
    return result;
  }

  STTConfiguration._();

  factory STTConfiguration.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory STTConfiguration.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'STTConfiguration',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aI(3, _omitFieldNames ? '' : 'sampleRate')
    ..aOB(4, _omitFieldNames ? '' : 'enableVad')
    ..aE<$1.AudioFormat>(5, _omitFieldNames ? '' : 'audioFormat',
        enumValues: $1.AudioFormat.values)
    ..aOB(6, _omitFieldNames ? '' : 'enablePunctuation')
    ..aOB(7, _omitFieldNames ? '' : 'enableDiarization')
    ..pPS(8, _omitFieldNames ? '' : 'vocabularyList')
    ..aI(9, _omitFieldNames ? '' : 'maxAlternatives')
    ..aOB(10, _omitFieldNames ? '' : 'enableWordTimestamps')
    ..aE<$1.InferenceFramework>(11, _omitFieldNames ? '' : 'preferredFramework',
        enumValues: $1.InferenceFramework.values)
    ..aOS(13, _omitFieldNames ? '' : 'language')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  STTConfiguration clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  STTConfiguration copyWith(void Function(STTConfiguration) updates) =>
      super.copyWith((message) => updates(message as STTConfiguration))
          as STTConfiguration;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static STTConfiguration create() => STTConfiguration._();
  @$core.override
  STTConfiguration createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static STTConfiguration getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<STTConfiguration>(create);
  static STTConfiguration? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  @$pb.TagNumber(3)
  $core.int get sampleRate => $_getIZ(1);
  @$pb.TagNumber(3)
  set sampleRate($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(3)
  $core.bool hasSampleRate() => $_has(1);
  @$pb.TagNumber(3)
  void clearSampleRate() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get enableVad => $_getBF(2);
  @$pb.TagNumber(4)
  set enableVad($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(4)
  $core.bool hasEnableVad() => $_has(2);
  @$pb.TagNumber(4)
  void clearEnableVad() => $_clearField(4);

  @$pb.TagNumber(5)
  $1.AudioFormat get audioFormat => $_getN(3);
  @$pb.TagNumber(5)
  set audioFormat($1.AudioFormat value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasAudioFormat() => $_has(3);
  @$pb.TagNumber(5)
  void clearAudioFormat() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get enablePunctuation => $_getBF(4);
  @$pb.TagNumber(6)
  set enablePunctuation($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(6)
  $core.bool hasEnablePunctuation() => $_has(4);
  @$pb.TagNumber(6)
  void clearEnablePunctuation() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get enableDiarization => $_getBF(5);
  @$pb.TagNumber(7)
  set enableDiarization($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(7)
  $core.bool hasEnableDiarization() => $_has(5);
  @$pb.TagNumber(7)
  void clearEnableDiarization() => $_clearField(7);

  @$pb.TagNumber(8)
  $pb.PbList<$core.String> get vocabularyList => $_getList(6);

  @$pb.TagNumber(9)
  $core.int get maxAlternatives => $_getIZ(7);
  @$pb.TagNumber(9)
  set maxAlternatives($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(9)
  $core.bool hasMaxAlternatives() => $_has(7);
  @$pb.TagNumber(9)
  void clearMaxAlternatives() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.bool get enableWordTimestamps => $_getBF(8);
  @$pb.TagNumber(10)
  set enableWordTimestamps($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(10)
  $core.bool hasEnableWordTimestamps() => $_has(8);
  @$pb.TagNumber(10)
  void clearEnableWordTimestamps() => $_clearField(10);

  @$pb.TagNumber(11)
  $1.InferenceFramework get preferredFramework => $_getN(9);
  @$pb.TagNumber(11)
  set preferredFramework($1.InferenceFramework value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasPreferredFramework() => $_has(9);
  @$pb.TagNumber(11)
  void clearPreferredFramework() => $_clearField(11);

  @$pb.TagNumber(13)
  $core.String get language => $_getSZ(10);
  @$pb.TagNumber(13)
  set language($core.String value) => $_setString(10, value);
  @$pb.TagNumber(13)
  $core.bool hasLanguage() => $_has(10);
  @$pb.TagNumber(13)
  void clearLanguage() => $_clearField(13);
}

/// Per-call overrides.
class STTOptions extends $pb.GeneratedMessage {
  factory STTOptions({
    $core.bool? enablePunctuation,
    $core.bool? enableDiarization,
    $core.int? maxSpeakers,
    $core.Iterable<$core.String>? vocabularyList,
    $core.bool? enableWordTimestamps,
    $core.int? beamSize,
    $core.int? maxAlternatives,
    $core.int? chunkDurationMs,
    $core.int? endpointSilenceMs,
    $core.bool? suppressBlank,
    $core.bool? translateToEnglish,
    $core.String? language,
  }) {
    final result = create();
    if (enablePunctuation != null) result.enablePunctuation = enablePunctuation;
    if (enableDiarization != null) result.enableDiarization = enableDiarization;
    if (maxSpeakers != null) result.maxSpeakers = maxSpeakers;
    if (vocabularyList != null) result.vocabularyList.addAll(vocabularyList);
    if (enableWordTimestamps != null)
      result.enableWordTimestamps = enableWordTimestamps;
    if (beamSize != null) result.beamSize = beamSize;
    if (maxAlternatives != null) result.maxAlternatives = maxAlternatives;
    if (chunkDurationMs != null) result.chunkDurationMs = chunkDurationMs;
    if (endpointSilenceMs != null) result.endpointSilenceMs = endpointSilenceMs;
    if (suppressBlank != null) result.suppressBlank = suppressBlank;
    if (translateToEnglish != null)
      result.translateToEnglish = translateToEnglish;
    if (language != null) result.language = language;
    return result;
  }

  STTOptions._();

  factory STTOptions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory STTOptions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'STTOptions',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(2, _omitFieldNames ? '' : 'enablePunctuation')
    ..aOB(3, _omitFieldNames ? '' : 'enableDiarization')
    ..aI(4, _omitFieldNames ? '' : 'maxSpeakers')
    ..pPS(5, _omitFieldNames ? '' : 'vocabularyList')
    ..aOB(6, _omitFieldNames ? '' : 'enableWordTimestamps')
    ..aI(7, _omitFieldNames ? '' : 'beamSize')
    ..aI(12, _omitFieldNames ? '' : 'maxAlternatives')
    ..aI(13, _omitFieldNames ? '' : 'chunkDurationMs')
    ..aI(14, _omitFieldNames ? '' : 'endpointSilenceMs')
    ..aOB(15, _omitFieldNames ? '' : 'suppressBlank')
    ..aOB(16, _omitFieldNames ? '' : 'translateToEnglish')
    ..aOS(17, _omitFieldNames ? '' : 'language')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  STTOptions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  STTOptions copyWith(void Function(STTOptions) updates) =>
      super.copyWith((message) => updates(message as STTOptions)) as STTOptions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static STTOptions create() => STTOptions._();
  @$core.override
  STTOptions createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static STTOptions getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<STTOptions>(create);
  static STTOptions? _defaultInstance;

  @$pb.TagNumber(2)
  $core.bool get enablePunctuation => $_getBF(0);
  @$pb.TagNumber(2)
  set enablePunctuation($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(2)
  $core.bool hasEnablePunctuation() => $_has(0);
  @$pb.TagNumber(2)
  void clearEnablePunctuation() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get enableDiarization => $_getBF(1);
  @$pb.TagNumber(3)
  set enableDiarization($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(3)
  $core.bool hasEnableDiarization() => $_has(1);
  @$pb.TagNumber(3)
  void clearEnableDiarization() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get maxSpeakers => $_getIZ(2);
  @$pb.TagNumber(4)
  set maxSpeakers($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(4)
  $core.bool hasMaxSpeakers() => $_has(2);
  @$pb.TagNumber(4)
  void clearMaxSpeakers() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get vocabularyList => $_getList(3);

  @$pb.TagNumber(6)
  $core.bool get enableWordTimestamps => $_getBF(4);
  @$pb.TagNumber(6)
  set enableWordTimestamps($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(6)
  $core.bool hasEnableWordTimestamps() => $_has(4);
  @$pb.TagNumber(6)
  void clearEnableWordTimestamps() => $_clearField(6);

  /// 0 = backend default, for all four of these.
  @$pb.TagNumber(7)
  $core.int get beamSize => $_getIZ(5);
  @$pb.TagNumber(7)
  set beamSize($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(7)
  $core.bool hasBeamSize() => $_has(5);
  @$pb.TagNumber(7)
  void clearBeamSize() => $_clearField(7);

  @$pb.TagNumber(12)
  $core.int get maxAlternatives => $_getIZ(6);
  @$pb.TagNumber(12)
  set maxAlternatives($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(12)
  $core.bool hasMaxAlternatives() => $_has(6);
  @$pb.TagNumber(12)
  void clearMaxAlternatives() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.int get chunkDurationMs => $_getIZ(7);
  @$pb.TagNumber(13)
  set chunkDurationMs($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(13)
  $core.bool hasChunkDurationMs() => $_has(7);
  @$pb.TagNumber(13)
  void clearChunkDurationMs() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.int get endpointSilenceMs => $_getIZ(8);
  @$pb.TagNumber(14)
  set endpointSilenceMs($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(14)
  $core.bool hasEndpointSilenceMs() => $_has(8);
  @$pb.TagNumber(14)
  void clearEndpointSilenceMs() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.bool get suppressBlank => $_getBF(9);
  @$pb.TagNumber(15)
  set suppressBlank($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(15)
  $core.bool hasSuppressBlank() => $_has(9);
  @$pb.TagNumber(15)
  void clearSuppressBlank() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.bool get translateToEnglish => $_getBF(10);
  @$pb.TagNumber(16)
  set translateToEnglish($core.bool value) => $_setBool(10, value);
  @$pb.TagNumber(16)
  $core.bool hasTranslateToEnglish() => $_has(10);
  @$pb.TagNumber(16)
  void clearTranslateToEnglish() => $_clearField(16);

  @$pb.TagNumber(17)
  $core.String get language => $_getSZ(11);
  @$pb.TagNumber(17)
  set language($core.String value) => $_setString(11, value);
  @$pb.TagNumber(17)
  $core.bool hasLanguage() => $_has(11);
  @$pb.TagNumber(17)
  void clearLanguage() => $_clearField(17);
}

enum STTAudioSource_Source { audioData, fileUri, adapterHandle, notSet }

class STTAudioSource extends $pb.GeneratedMessage {
  factory STTAudioSource({
    $core.List<$core.int>? audioData,
    $core.String? fileUri,
    $core.String? adapterHandle,
    $1.AudioEncoding? encoding,
    $1.AudioFormat? audioFormat,
    $core.int? sampleRate,
    $core.int? channels,
    $core.int? bitsPerSample,
    $fixnum.Int64? durationMs,
  }) {
    final result = create();
    if (audioData != null) result.audioData = audioData;
    if (fileUri != null) result.fileUri = fileUri;
    if (adapterHandle != null) result.adapterHandle = adapterHandle;
    if (encoding != null) result.encoding = encoding;
    if (audioFormat != null) result.audioFormat = audioFormat;
    if (sampleRate != null) result.sampleRate = sampleRate;
    if (channels != null) result.channels = channels;
    if (bitsPerSample != null) result.bitsPerSample = bitsPerSample;
    if (durationMs != null) result.durationMs = durationMs;
    return result;
  }

  STTAudioSource._();

  factory STTAudioSource.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory STTAudioSource.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, STTAudioSource_Source>
      _STTAudioSource_SourceByTag = {
    1: STTAudioSource_Source.audioData,
    2: STTAudioSource_Source.fileUri,
    3: STTAudioSource_Source.adapterHandle,
    0: STTAudioSource_Source.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'STTAudioSource',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..oo(0, [1, 2, 3])
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'audioData', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'fileUri')
    ..aOS(3, _omitFieldNames ? '' : 'adapterHandle')
    ..aE<$1.AudioEncoding>(4, _omitFieldNames ? '' : 'encoding',
        enumValues: $1.AudioEncoding.values)
    ..aE<$1.AudioFormat>(5, _omitFieldNames ? '' : 'audioFormat',
        enumValues: $1.AudioFormat.values)
    ..aI(6, _omitFieldNames ? '' : 'sampleRate')
    ..aI(7, _omitFieldNames ? '' : 'channels')
    ..aI(8, _omitFieldNames ? '' : 'bitsPerSample')
    ..aInt64(9, _omitFieldNames ? '' : 'durationMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  STTAudioSource clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  STTAudioSource copyWith(void Function(STTAudioSource) updates) =>
      super.copyWith((message) => updates(message as STTAudioSource))
          as STTAudioSource;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static STTAudioSource create() => STTAudioSource._();
  @$core.override
  STTAudioSource createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static STTAudioSource getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<STTAudioSource>(create);
  static STTAudioSource? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  STTAudioSource_Source whichSource() =>
      _STTAudioSource_SourceByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
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
  $core.String get fileUri => $_getSZ(1);
  @$pb.TagNumber(2)
  set fileUri($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFileUri() => $_has(1);
  @$pb.TagNumber(2)
  void clearFileUri() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get adapterHandle => $_getSZ(2);
  @$pb.TagNumber(3)
  set adapterHandle($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAdapterHandle() => $_has(2);
  @$pb.TagNumber(3)
  void clearAdapterHandle() => $_clearField(3);

  @$pb.TagNumber(4)
  $1.AudioEncoding get encoding => $_getN(3);
  @$pb.TagNumber(4)
  set encoding($1.AudioEncoding value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasEncoding() => $_has(3);
  @$pb.TagNumber(4)
  void clearEncoding() => $_clearField(4);

  @$pb.TagNumber(5)
  $1.AudioFormat get audioFormat => $_getN(4);
  @$pb.TagNumber(5)
  set audioFormat($1.AudioFormat value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasAudioFormat() => $_has(4);
  @$pb.TagNumber(5)
  void clearAudioFormat() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get sampleRate => $_getIZ(5);
  @$pb.TagNumber(6)
  set sampleRate($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSampleRate() => $_has(5);
  @$pb.TagNumber(6)
  void clearSampleRate() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get channels => $_getIZ(6);
  @$pb.TagNumber(7)
  set channels($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasChannels() => $_has(6);
  @$pb.TagNumber(7)
  void clearChannels() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get bitsPerSample => $_getIZ(7);
  @$pb.TagNumber(8)
  set bitsPerSample($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasBitsPerSample() => $_has(7);
  @$pb.TagNumber(8)
  void clearBitsPerSample() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get durationMs => $_getI64(8);
  @$pb.TagNumber(9)
  set durationMs($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasDurationMs() => $_has(8);
  @$pb.TagNumber(9)
  void clearDurationMs() => $_clearField(9);
}

class STTTranscriptionRequest extends $pb.GeneratedMessage {
  factory STTTranscriptionRequest({
    $core.String? requestId,
    STTAudioSource? audio,
    STTOptions? options,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (audio != null) result.audio = audio;
    if (options != null) result.options = options;
    if (metadata != null) result.metadata.addEntries(metadata);
    return result;
  }

  STTTranscriptionRequest._();

  factory STTTranscriptionRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory STTTranscriptionRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'STTTranscriptionRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOM<STTAudioSource>(2, _omitFieldNames ? '' : 'audio',
        subBuilder: STTAudioSource.create)
    ..aOM<STTOptions>(3, _omitFieldNames ? '' : 'options',
        subBuilder: STTOptions.create)
    ..m<$core.String, $core.String>(4, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'STTTranscriptionRequest.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  STTTranscriptionRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  STTTranscriptionRequest copyWith(
          void Function(STTTranscriptionRequest) updates) =>
      super.copyWith((message) => updates(message as STTTranscriptionRequest))
          as STTTranscriptionRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static STTTranscriptionRequest create() => STTTranscriptionRequest._();
  @$core.override
  STTTranscriptionRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static STTTranscriptionRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<STTTranscriptionRequest>(create);
  static STTTranscriptionRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  STTAudioSource get audio => $_getN(1);
  @$pb.TagNumber(2)
  set audio(STTAudioSource value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasAudio() => $_has(1);
  @$pb.TagNumber(2)
  void clearAudio() => $_clearField(2);
  @$pb.TagNumber(2)
  STTAudioSource ensureAudio() => $_ensure(1);

  @$pb.TagNumber(3)
  STTOptions get options => $_getN(2);
  @$pb.TagNumber(3)
  set options(STTOptions value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasOptions() => $_has(2);
  @$pb.TagNumber(3)
  void clearOptions() => $_clearField(3);
  @$pb.TagNumber(3)
  STTOptions ensureOptions() => $_ensure(2);

  @$pb.TagNumber(4)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(3);
}

class WordTimestamp extends $pb.GeneratedMessage {
  factory WordTimestamp({
    $core.String? word,
    $fixnum.Int64? startMs,
    $fixnum.Int64? endMs,
    $core.double? confidence,
    $core.String? speakerId,
  }) {
    final result = create();
    if (word != null) result.word = word;
    if (startMs != null) result.startMs = startMs;
    if (endMs != null) result.endMs = endMs;
    if (confidence != null) result.confidence = confidence;
    if (speakerId != null) result.speakerId = speakerId;
    return result;
  }

  WordTimestamp._();

  factory WordTimestamp.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory WordTimestamp.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WordTimestamp',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'word')
    ..aInt64(2, _omitFieldNames ? '' : 'startMs')
    ..aInt64(3, _omitFieldNames ? '' : 'endMs')
    ..aD(4, _omitFieldNames ? '' : 'confidence', fieldType: $pb.PbFieldType.OF)
    ..aOS(5, _omitFieldNames ? '' : 'speakerId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WordTimestamp clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WordTimestamp copyWith(void Function(WordTimestamp) updates) =>
      super.copyWith((message) => updates(message as WordTimestamp))
          as WordTimestamp;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static WordTimestamp create() => WordTimestamp._();
  @$core.override
  WordTimestamp createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static WordTimestamp getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WordTimestamp>(create);
  static WordTimestamp? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get word => $_getSZ(0);
  @$pb.TagNumber(1)
  set word($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasWord() => $_has(0);
  @$pb.TagNumber(1)
  void clearWord() => $_clearField(1);

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

  @$pb.TagNumber(4)
  $core.double get confidence => $_getN(3);
  @$pb.TagNumber(4)
  set confidence($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasConfidence() => $_has(3);
  @$pb.TagNumber(4)
  void clearConfidence() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get speakerId => $_getSZ(4);
  @$pb.TagNumber(5)
  set speakerId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSpeakerId() => $_has(4);
  @$pb.TagNumber(5)
  void clearSpeakerId() => $_clearField(5);
}

/// One n-best hypothesis. Per-word breakdown only when the backend emits it.
class TranscriptionAlternative extends $pb.GeneratedMessage {
  factory TranscriptionAlternative({
    $core.String? text,
    $core.double? confidence,
    $core.Iterable<WordTimestamp>? words,
  }) {
    final result = create();
    if (text != null) result.text = text;
    if (confidence != null) result.confidence = confidence;
    if (words != null) result.words.addAll(words);
    return result;
  }

  TranscriptionAlternative._();

  factory TranscriptionAlternative.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TranscriptionAlternative.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TranscriptionAlternative',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aD(2, _omitFieldNames ? '' : 'confidence', fieldType: $pb.PbFieldType.OF)
    ..pPM<WordTimestamp>(3, _omitFieldNames ? '' : 'words',
        subBuilder: WordTimestamp.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TranscriptionAlternative clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TranscriptionAlternative copyWith(
          void Function(TranscriptionAlternative) updates) =>
      super.copyWith((message) => updates(message as TranscriptionAlternative))
          as TranscriptionAlternative;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TranscriptionAlternative create() => TranscriptionAlternative._();
  @$core.override
  TranscriptionAlternative createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TranscriptionAlternative getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TranscriptionAlternative>(create);
  static TranscriptionAlternative? _defaultInstance;

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

  @$pb.TagNumber(3)
  $pb.PbList<WordTimestamp> get words => $_getList(2);
}

class TranscriptionMetadata extends $pb.GeneratedMessage {
  factory TranscriptionMetadata({
    $core.String? modelId,
    $fixnum.Int64? processingTimeMs,
    $fixnum.Int64? audioLengthMs,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (processingTimeMs != null) result.processingTimeMs = processingTimeMs;
    if (audioLengthMs != null) result.audioLengthMs = audioLengthMs;
    return result;
  }

  TranscriptionMetadata._();

  factory TranscriptionMetadata.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TranscriptionMetadata.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TranscriptionMetadata',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aInt64(2, _omitFieldNames ? '' : 'processingTimeMs')
    ..aInt64(3, _omitFieldNames ? '' : 'audioLengthMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TranscriptionMetadata clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TranscriptionMetadata copyWith(
          void Function(TranscriptionMetadata) updates) =>
      super.copyWith((message) => updates(message as TranscriptionMetadata))
          as TranscriptionMetadata;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TranscriptionMetadata create() => TranscriptionMetadata._();
  @$core.override
  TranscriptionMetadata createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TranscriptionMetadata getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TranscriptionMetadata>(create);
  static TranscriptionMetadata? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get processingTimeMs => $_getI64(1);
  @$pb.TagNumber(2)
  set processingTimeMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasProcessingTimeMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearProcessingTimeMs() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get audioLengthMs => $_getI64(2);
  @$pb.TagNumber(3)
  set audioLengthMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAudioLengthMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearAudioLengthMs() => $_clearField(3);
}

class STTOutput extends $pb.GeneratedMessage {
  factory STTOutput({
    $core.String? text,
    $core.double? confidence,
    $core.Iterable<WordTimestamp>? words,
    $core.Iterable<TranscriptionAlternative>? alternatives,
    TranscriptionMetadata? metadata,
    $fixnum.Int64? timestampMs,
    $fixnum.Int64? durationMs,
    $core.Iterable<$core.String>? speakerIds,
    $core.int? segmentIndex,
    $core.String? language,
    $0.SDKError? error,
  }) {
    final result = create();
    if (text != null) result.text = text;
    if (confidence != null) result.confidence = confidence;
    if (words != null) result.words.addAll(words);
    if (alternatives != null) result.alternatives.addAll(alternatives);
    if (metadata != null) result.metadata = metadata;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (durationMs != null) result.durationMs = durationMs;
    if (speakerIds != null) result.speakerIds.addAll(speakerIds);
    if (segmentIndex != null) result.segmentIndex = segmentIndex;
    if (language != null) result.language = language;
    if (error != null) result.error = error;
    return result;
  }

  STTOutput._();

  factory STTOutput.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory STTOutput.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'STTOutput',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aD(3, _omitFieldNames ? '' : 'confidence', fieldType: $pb.PbFieldType.OF)
    ..pPM<WordTimestamp>(4, _omitFieldNames ? '' : 'words',
        subBuilder: WordTimestamp.create)
    ..pPM<TranscriptionAlternative>(5, _omitFieldNames ? '' : 'alternatives',
        subBuilder: TranscriptionAlternative.create)
    ..aOM<TranscriptionMetadata>(6, _omitFieldNames ? '' : 'metadata',
        subBuilder: TranscriptionMetadata.create)
    ..aInt64(8, _omitFieldNames ? '' : 'timestampMs')
    ..aInt64(9, _omitFieldNames ? '' : 'durationMs')
    ..pPS(10, _omitFieldNames ? '' : 'speakerIds')
    ..aI(13, _omitFieldNames ? '' : 'segmentIndex')
    ..aOS(14, _omitFieldNames ? '' : 'language')
    ..aOM<$0.SDKError>(15, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  STTOutput clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  STTOutput copyWith(void Function(STTOutput) updates) =>
      super.copyWith((message) => updates(message as STTOutput)) as STTOutput;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static STTOutput create() => STTOutput._();
  @$core.override
  STTOutput createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static STTOutput getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<STTOutput>(create);
  static STTOutput? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  @$pb.TagNumber(3)
  $core.double get confidence => $_getN(1);
  @$pb.TagNumber(3)
  set confidence($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(3)
  $core.bool hasConfidence() => $_has(1);
  @$pb.TagNumber(3)
  void clearConfidence() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<WordTimestamp> get words => $_getList(2);

  @$pb.TagNumber(5)
  $pb.PbList<TranscriptionAlternative> get alternatives => $_getList(3);

  @$pb.TagNumber(6)
  TranscriptionMetadata get metadata => $_getN(4);
  @$pb.TagNumber(6)
  set metadata(TranscriptionMetadata value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasMetadata() => $_has(4);
  @$pb.TagNumber(6)
  void clearMetadata() => $_clearField(6);
  @$pb.TagNumber(6)
  TranscriptionMetadata ensureMetadata() => $_ensure(4);

  /// Milliseconds since epoch.
  @$pb.TagNumber(8)
  $fixnum.Int64 get timestampMs => $_getI64(5);
  @$pb.TagNumber(8)
  set timestampMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(8)
  $core.bool hasTimestampMs() => $_has(5);
  @$pb.TagNumber(8)
  void clearTimestampMs() => $_clearField(8);

  /// Often duplicates metadata.audio_length_ms.
  @$pb.TagNumber(9)
  $fixnum.Int64 get durationMs => $_getI64(6);
  @$pb.TagNumber(9)
  set durationMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(9)
  $core.bool hasDurationMs() => $_has(6);
  @$pb.TagNumber(9)
  void clearDurationMs() => $_clearField(9);

  @$pb.TagNumber(10)
  $pb.PbList<$core.String> get speakerIds => $_getList(7);

  /// For long-running or streaming transcription.
  @$pb.TagNumber(13)
  $core.int get segmentIndex => $_getIZ(8);
  @$pb.TagNumber(13)
  set segmentIndex($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(13)
  $core.bool hasSegmentIndex() => $_has(8);
  @$pb.TagNumber(13)
  void clearSegmentIndex() => $_clearField(13);

  /// Detected language, BCP-47. Empty = unknown.
  @$pb.TagNumber(14)
  $core.String get language => $_getSZ(9);
  @$pb.TagNumber(14)
  set language($core.String value) => $_setString(9, value);
  @$pb.TagNumber(14)
  $core.bool hasLanguage() => $_has(9);
  @$pb.TagNumber(14)
  void clearLanguage() => $_clearField(14);

  @$pb.TagNumber(15)
  $0.SDKError get error => $_getN(10);
  @$pb.TagNumber(15)
  set error($0.SDKError value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasError() => $_has(10);
  @$pb.TagNumber(15)
  void clearError() => $_clearField(15);
  @$pb.TagNumber(15)
  $0.SDKError ensureError() => $_ensure(10);
}

class STTPartialResult extends $pb.GeneratedMessage {
  factory STTPartialResult({
    $core.String? text,
    $core.bool? isFinal,
    $core.double? stability,
    $core.double? confidence,
    $fixnum.Int64? timestampMs,
    $core.Iterable<TranscriptionAlternative>? alternatives,
    $core.String? requestId,
    $core.int? segmentIndex,
    $fixnum.Int64? audioStartMs,
    $fixnum.Int64? audioEndMs,
    STTOutput? finalOutput,
    $core.String? language,
  }) {
    final result = create();
    if (text != null) result.text = text;
    if (isFinal != null) result.isFinal = isFinal;
    if (stability != null) result.stability = stability;
    if (confidence != null) result.confidence = confidence;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (alternatives != null) result.alternatives.addAll(alternatives);
    if (requestId != null) result.requestId = requestId;
    if (segmentIndex != null) result.segmentIndex = segmentIndex;
    if (audioStartMs != null) result.audioStartMs = audioStartMs;
    if (audioEndMs != null) result.audioEndMs = audioEndMs;
    if (finalOutput != null) result.finalOutput = finalOutput;
    if (language != null) result.language = language;
    return result;
  }

  STTPartialResult._();

  factory STTPartialResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory STTPartialResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'STTPartialResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOB(2, _omitFieldNames ? '' : 'isFinal')
    ..aD(3, _omitFieldNames ? '' : 'stability', fieldType: $pb.PbFieldType.OF)
    ..aD(4, _omitFieldNames ? '' : 'confidence', fieldType: $pb.PbFieldType.OF)
    ..aInt64(6, _omitFieldNames ? '' : 'timestampMs')
    ..pPM<TranscriptionAlternative>(7, _omitFieldNames ? '' : 'alternatives',
        subBuilder: TranscriptionAlternative.create)
    ..aOS(9, _omitFieldNames ? '' : 'requestId')
    ..aI(10, _omitFieldNames ? '' : 'segmentIndex')
    ..aInt64(11, _omitFieldNames ? '' : 'audioStartMs')
    ..aInt64(12, _omitFieldNames ? '' : 'audioEndMs')
    ..aOM<STTOutput>(13, _omitFieldNames ? '' : 'finalOutput',
        subBuilder: STTOutput.create)
    ..aOS(14, _omitFieldNames ? '' : 'language')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  STTPartialResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  STTPartialResult copyWith(void Function(STTPartialResult) updates) =>
      super.copyWith((message) => updates(message as STTPartialResult))
          as STTPartialResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static STTPartialResult create() => STTPartialResult._();
  @$core.override
  STTPartialResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static STTPartialResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<STTPartialResult>(create);
  static STTPartialResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get isFinal => $_getBF(1);
  @$pb.TagNumber(2)
  set isFinal($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIsFinal() => $_has(1);
  @$pb.TagNumber(2)
  void clearIsFinal() => $_clearField(2);

  /// Whisper-style hypothesis stability, 0.0-1.0. 0.0 when unsupported.
  @$pb.TagNumber(3)
  $core.double get stability => $_getN(2);
  @$pb.TagNumber(3)
  set stability($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStability() => $_has(2);
  @$pb.TagNumber(3)
  void clearStability() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get confidence => $_getN(3);
  @$pb.TagNumber(4)
  set confidence($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasConfidence() => $_has(3);
  @$pb.TagNumber(4)
  void clearConfidence() => $_clearField(4);

  @$pb.TagNumber(6)
  $fixnum.Int64 get timestampMs => $_getI64(4);
  @$pb.TagNumber(6)
  set timestampMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(6)
  $core.bool hasTimestampMs() => $_has(4);
  @$pb.TagNumber(6)
  void clearTimestampMs() => $_clearField(6);

  @$pb.TagNumber(7)
  $pb.PbList<TranscriptionAlternative> get alternatives => $_getList(5);

  @$pb.TagNumber(9)
  $core.String get requestId => $_getSZ(6);
  @$pb.TagNumber(9)
  set requestId($core.String value) => $_setString(6, value);
  @$pb.TagNumber(9)
  $core.bool hasRequestId() => $_has(6);
  @$pb.TagNumber(9)
  void clearRequestId() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get segmentIndex => $_getIZ(7);
  @$pb.TagNumber(10)
  set segmentIndex($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(10)
  $core.bool hasSegmentIndex() => $_has(7);
  @$pb.TagNumber(10)
  void clearSegmentIndex() => $_clearField(10);

  @$pb.TagNumber(11)
  $fixnum.Int64 get audioStartMs => $_getI64(8);
  @$pb.TagNumber(11)
  set audioStartMs($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(11)
  $core.bool hasAudioStartMs() => $_has(8);
  @$pb.TagNumber(11)
  void clearAudioStartMs() => $_clearField(11);

  @$pb.TagNumber(12)
  $fixnum.Int64 get audioEndMs => $_getI64(9);
  @$pb.TagNumber(12)
  set audioEndMs($fixnum.Int64 value) => $_setInt64(9, value);
  @$pb.TagNumber(12)
  $core.bool hasAudioEndMs() => $_has(9);
  @$pb.TagNumber(12)
  void clearAudioEndMs() => $_clearField(12);

  @$pb.TagNumber(13)
  STTOutput get finalOutput => $_getN(10);
  @$pb.TagNumber(13)
  set finalOutput(STTOutput value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasFinalOutput() => $_has(10);
  @$pb.TagNumber(13)
  void clearFinalOutput() => $_clearField(13);
  @$pb.TagNumber(13)
  STTOutput ensureFinalOutput() => $_ensure(10);

  @$pb.TagNumber(14)
  $core.String get language => $_getSZ(11);
  @$pb.TagNumber(14)
  set language($core.String value) => $_setString(11, value);
  @$pb.TagNumber(14)
  $core.bool hasLanguage() => $_has(11);
  @$pb.TagNumber(14)
  void clearLanguage() => $_clearField(14);
}

class STTStreamEvent extends $pb.GeneratedMessage {
  factory STTStreamEvent({
    $fixnum.Int64? seq,
    $fixnum.Int64? timestampUs,
    $core.String? requestId,
    STTStreamEventKind? kind,
    STTPartialResult? partial,
    STTOutput? finalOutput,
    $0.SDKError? error,
  }) {
    final result = create();
    if (seq != null) result.seq = seq;
    if (timestampUs != null) result.timestampUs = timestampUs;
    if (requestId != null) result.requestId = requestId;
    if (kind != null) result.kind = kind;
    if (partial != null) result.partial = partial;
    if (finalOutput != null) result.finalOutput = finalOutput;
    if (error != null) result.error = error;
    return result;
  }

  STTStreamEvent._();

  factory STTStreamEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory STTStreamEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'STTStreamEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(3, _omitFieldNames ? '' : 'requestId')
    ..aE<STTStreamEventKind>(4, _omitFieldNames ? '' : 'kind',
        enumValues: STTStreamEventKind.values)
    ..aOM<STTPartialResult>(5, _omitFieldNames ? '' : 'partial',
        subBuilder: STTPartialResult.create)
    ..aOM<STTOutput>(6, _omitFieldNames ? '' : 'finalOutput',
        subBuilder: STTOutput.create)
    ..aOM<$0.SDKError>(9, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  STTStreamEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  STTStreamEvent copyWith(void Function(STTStreamEvent) updates) =>
      super.copyWith((message) => updates(message as STTStreamEvent))
          as STTStreamEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static STTStreamEvent create() => STTStreamEvent._();
  @$core.override
  STTStreamEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static STTStreamEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<STTStreamEvent>(create);
  static STTStreamEvent? _defaultInstance;

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
  STTStreamEventKind get kind => $_getN(3);
  @$pb.TagNumber(4)
  set kind(STTStreamEventKind value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasKind() => $_has(3);
  @$pb.TagNumber(4)
  void clearKind() => $_clearField(4);

  @$pb.TagNumber(5)
  STTPartialResult get partial => $_getN(4);
  @$pb.TagNumber(5)
  set partial(STTPartialResult value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasPartial() => $_has(4);
  @$pb.TagNumber(5)
  void clearPartial() => $_clearField(5);
  @$pb.TagNumber(5)
  STTPartialResult ensurePartial() => $_ensure(4);

  @$pb.TagNumber(6)
  STTOutput get finalOutput => $_getN(5);
  @$pb.TagNumber(6)
  set finalOutput(STTOutput value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasFinalOutput() => $_has(5);
  @$pb.TagNumber(6)
  void clearFinalOutput() => $_clearField(6);
  @$pb.TagNumber(6)
  STTOutput ensureFinalOutput() => $_ensure(5);

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

class STTServiceState extends $pb.GeneratedMessage {
  factory STTServiceState({
    $core.bool? isReady,
    $core.String? currentModel,
    $core.bool? supportsStreaming,
    $core.Iterable<$core.String>? supportedLanguageCodes,
    $0.SDKError? error,
  }) {
    final result = create();
    if (isReady != null) result.isReady = isReady;
    if (currentModel != null) result.currentModel = currentModel;
    if (supportsStreaming != null) result.supportsStreaming = supportsStreaming;
    if (supportedLanguageCodes != null)
      result.supportedLanguageCodes.addAll(supportedLanguageCodes);
    if (error != null) result.error = error;
    return result;
  }

  STTServiceState._();

  factory STTServiceState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory STTServiceState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'STTServiceState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isReady')
    ..aOS(2, _omitFieldNames ? '' : 'currentModel')
    ..aOB(3, _omitFieldNames ? '' : 'supportsStreaming')
    ..pPS(4, _omitFieldNames ? '' : 'supportedLanguageCodes')
    ..aOM<$0.SDKError>(7, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  STTServiceState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  STTServiceState copyWith(void Function(STTServiceState) updates) =>
      super.copyWith((message) => updates(message as STTServiceState))
          as STTServiceState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static STTServiceState create() => STTServiceState._();
  @$core.override
  STTServiceState createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static STTServiceState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<STTServiceState>(create);
  static STTServiceState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get isReady => $_getBF(0);
  @$pb.TagNumber(1)
  set isReady($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIsReady() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsReady() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get currentModel => $_getSZ(1);
  @$pb.TagNumber(2)
  set currentModel($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCurrentModel() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrentModel() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get supportsStreaming => $_getBF(2);
  @$pb.TagNumber(3)
  set supportsStreaming($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSupportsStreaming() => $_has(2);
  @$pb.TagNumber(3)
  void clearSupportsStreaming() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<$core.String> get supportedLanguageCodes => $_getList(3);

  @$pb.TagNumber(7)
  $0.SDKError get error => $_getN(4);
  @$pb.TagNumber(7)
  set error($0.SDKError value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasError() => $_has(4);
  @$pb.TagNumber(7)
  void clearError() => $_clearField(7);
  @$pb.TagNumber(7)
  $0.SDKError ensureError() => $_ensure(4);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
