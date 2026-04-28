///
//  Generated code. Do not modify.
//  source: rag.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

class RAGConfiguration extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'RAGConfiguration', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'embeddingModelPath')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'llmModelPath')
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'embeddingDimension', $pb.PbFieldType.O3)
    ..a<$core.int>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'topK', $pb.PbFieldType.O3)
    ..a<$core.double>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'similarityThreshold', $pb.PbFieldType.OF)
    ..a<$core.int>(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'chunkSize', $pb.PbFieldType.O3)
    ..a<$core.int>(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'chunkOverlap', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  RAGConfiguration._() : super();
  factory RAGConfiguration({
    $core.String? embeddingModelPath,
    $core.String? llmModelPath,
    $core.int? embeddingDimension,
    $core.int? topK,
    $core.double? similarityThreshold,
    $core.int? chunkSize,
    $core.int? chunkOverlap,
  }) {
    final _result = create();
    if (embeddingModelPath != null) {
      _result.embeddingModelPath = embeddingModelPath;
    }
    if (llmModelPath != null) {
      _result.llmModelPath = llmModelPath;
    }
    if (embeddingDimension != null) {
      _result.embeddingDimension = embeddingDimension;
    }
    if (topK != null) {
      _result.topK = topK;
    }
    if (similarityThreshold != null) {
      _result.similarityThreshold = similarityThreshold;
    }
    if (chunkSize != null) {
      _result.chunkSize = chunkSize;
    }
    if (chunkOverlap != null) {
      _result.chunkOverlap = chunkOverlap;
    }
    return _result;
  }
  factory RAGConfiguration.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RAGConfiguration.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RAGConfiguration clone() => RAGConfiguration()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RAGConfiguration copyWith(void Function(RAGConfiguration) updates) => super.copyWith((message) => updates(message as RAGConfiguration)) as RAGConfiguration; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static RAGConfiguration create() => RAGConfiguration._();
  RAGConfiguration createEmptyInstance() => create();
  static $pb.PbList<RAGConfiguration> createRepeated() => $pb.PbList<RAGConfiguration>();
  @$core.pragma('dart2js:noInline')
  static RAGConfiguration getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RAGConfiguration>(create);
  static RAGConfiguration? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get embeddingModelPath => $_getSZ(0);
  @$pb.TagNumber(1)
  set embeddingModelPath($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEmbeddingModelPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearEmbeddingModelPath() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get llmModelPath => $_getSZ(1);
  @$pb.TagNumber(2)
  set llmModelPath($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasLlmModelPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearLlmModelPath() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get embeddingDimension => $_getIZ(2);
  @$pb.TagNumber(3)
  set embeddingDimension($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasEmbeddingDimension() => $_has(2);
  @$pb.TagNumber(3)
  void clearEmbeddingDimension() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get topK => $_getIZ(3);
  @$pb.TagNumber(4)
  set topK($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTopK() => $_has(3);
  @$pb.TagNumber(4)
  void clearTopK() => clearField(4);

  @$pb.TagNumber(5)
  $core.double get similarityThreshold => $_getN(4);
  @$pb.TagNumber(5)
  set similarityThreshold($core.double v) { $_setFloat(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSimilarityThreshold() => $_has(4);
  @$pb.TagNumber(5)
  void clearSimilarityThreshold() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get chunkSize => $_getIZ(5);
  @$pb.TagNumber(6)
  set chunkSize($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasChunkSize() => $_has(5);
  @$pb.TagNumber(6)
  void clearChunkSize() => clearField(6);

  @$pb.TagNumber(7)
  $core.int get chunkOverlap => $_getIZ(6);
  @$pb.TagNumber(7)
  set chunkOverlap($core.int v) { $_setSignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasChunkOverlap() => $_has(6);
  @$pb.TagNumber(7)
  void clearChunkOverlap() => clearField(7);
}

class RAGQueryOptions extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'RAGQueryOptions', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'question')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'systemPrompt')
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'maxTokens', $pb.PbFieldType.O3)
    ..a<$core.double>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'temperature', $pb.PbFieldType.OF)
    ..a<$core.double>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'topP', $pb.PbFieldType.OF)
    ..a<$core.int>(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'topK', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  RAGQueryOptions._() : super();
  factory RAGQueryOptions({
    $core.String? question,
    $core.String? systemPrompt,
    $core.int? maxTokens,
    $core.double? temperature,
    $core.double? topP,
    $core.int? topK,
  }) {
    final _result = create();
    if (question != null) {
      _result.question = question;
    }
    if (systemPrompt != null) {
      _result.systemPrompt = systemPrompt;
    }
    if (maxTokens != null) {
      _result.maxTokens = maxTokens;
    }
    if (temperature != null) {
      _result.temperature = temperature;
    }
    if (topP != null) {
      _result.topP = topP;
    }
    if (topK != null) {
      _result.topK = topK;
    }
    return _result;
  }
  factory RAGQueryOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RAGQueryOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RAGQueryOptions clone() => RAGQueryOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RAGQueryOptions copyWith(void Function(RAGQueryOptions) updates) => super.copyWith((message) => updates(message as RAGQueryOptions)) as RAGQueryOptions; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static RAGQueryOptions create() => RAGQueryOptions._();
  RAGQueryOptions createEmptyInstance() => create();
  static $pb.PbList<RAGQueryOptions> createRepeated() => $pb.PbList<RAGQueryOptions>();
  @$core.pragma('dart2js:noInline')
  static RAGQueryOptions getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RAGQueryOptions>(create);
  static RAGQueryOptions? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get question => $_getSZ(0);
  @$pb.TagNumber(1)
  set question($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasQuestion() => $_has(0);
  @$pb.TagNumber(1)
  void clearQuestion() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get systemPrompt => $_getSZ(1);
  @$pb.TagNumber(2)
  set systemPrompt($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSystemPrompt() => $_has(1);
  @$pb.TagNumber(2)
  void clearSystemPrompt() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get maxTokens => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxTokens($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMaxTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxTokens() => clearField(3);

  @$pb.TagNumber(4)
  $core.double get temperature => $_getN(3);
  @$pb.TagNumber(4)
  set temperature($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTemperature() => $_has(3);
  @$pb.TagNumber(4)
  void clearTemperature() => clearField(4);

  @$pb.TagNumber(5)
  $core.double get topP => $_getN(4);
  @$pb.TagNumber(5)
  set topP($core.double v) { $_setFloat(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasTopP() => $_has(4);
  @$pb.TagNumber(5)
  void clearTopP() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get topK => $_getIZ(5);
  @$pb.TagNumber(6)
  set topK($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTopK() => $_has(5);
  @$pb.TagNumber(6)
  void clearTopK() => clearField(6);
}

class RAGSearchResult extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'RAGSearchResult', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'chunkId')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'text')
    ..a<$core.double>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'similarityScore', $pb.PbFieldType.OF)
    ..aOS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sourceDocument')
    ..m<$core.String, $core.String>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'metadata', entryClassName: 'RAGSearchResult.MetadataEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false
  ;

  RAGSearchResult._() : super();
  factory RAGSearchResult({
    $core.String? chunkId,
    $core.String? text,
    $core.double? similarityScore,
    $core.String? sourceDocument,
    $core.Map<$core.String, $core.String>? metadata,
  }) {
    final _result = create();
    if (chunkId != null) {
      _result.chunkId = chunkId;
    }
    if (text != null) {
      _result.text = text;
    }
    if (similarityScore != null) {
      _result.similarityScore = similarityScore;
    }
    if (sourceDocument != null) {
      _result.sourceDocument = sourceDocument;
    }
    if (metadata != null) {
      _result.metadata.addAll(metadata);
    }
    return _result;
  }
  factory RAGSearchResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RAGSearchResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RAGSearchResult clone() => RAGSearchResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RAGSearchResult copyWith(void Function(RAGSearchResult) updates) => super.copyWith((message) => updates(message as RAGSearchResult)) as RAGSearchResult; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static RAGSearchResult create() => RAGSearchResult._();
  RAGSearchResult createEmptyInstance() => create();
  static $pb.PbList<RAGSearchResult> createRepeated() => $pb.PbList<RAGSearchResult>();
  @$core.pragma('dart2js:noInline')
  static RAGSearchResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RAGSearchResult>(create);
  static RAGSearchResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get chunkId => $_getSZ(0);
  @$pb.TagNumber(1)
  set chunkId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChunkId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChunkId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get text => $_getSZ(1);
  @$pb.TagNumber(2)
  set text($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get similarityScore => $_getN(2);
  @$pb.TagNumber(3)
  set similarityScore($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSimilarityScore() => $_has(2);
  @$pb.TagNumber(3)
  void clearSimilarityScore() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get sourceDocument => $_getSZ(3);
  @$pb.TagNumber(4)
  set sourceDocument($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSourceDocument() => $_has(3);
  @$pb.TagNumber(4)
  void clearSourceDocument() => clearField(4);

  @$pb.TagNumber(5)
  $core.Map<$core.String, $core.String> get metadata => $_getMap(4);
}

class RAGResult extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'RAGResult', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'answer')
    ..pc<RAGSearchResult>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'retrievedChunks', $pb.PbFieldType.PM, subBuilder: RAGSearchResult.create)
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'contextUsed')
    ..aInt64(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'retrievalTimeMs')
    ..aInt64(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'generationTimeMs')
    ..aInt64(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'totalTimeMs')
    ..hasRequiredFields = false
  ;

  RAGResult._() : super();
  factory RAGResult({
    $core.String? answer,
    $core.Iterable<RAGSearchResult>? retrievedChunks,
    $core.String? contextUsed,
    $fixnum.Int64? retrievalTimeMs,
    $fixnum.Int64? generationTimeMs,
    $fixnum.Int64? totalTimeMs,
  }) {
    final _result = create();
    if (answer != null) {
      _result.answer = answer;
    }
    if (retrievedChunks != null) {
      _result.retrievedChunks.addAll(retrievedChunks);
    }
    if (contextUsed != null) {
      _result.contextUsed = contextUsed;
    }
    if (retrievalTimeMs != null) {
      _result.retrievalTimeMs = retrievalTimeMs;
    }
    if (generationTimeMs != null) {
      _result.generationTimeMs = generationTimeMs;
    }
    if (totalTimeMs != null) {
      _result.totalTimeMs = totalTimeMs;
    }
    return _result;
  }
  factory RAGResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RAGResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RAGResult clone() => RAGResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RAGResult copyWith(void Function(RAGResult) updates) => super.copyWith((message) => updates(message as RAGResult)) as RAGResult; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static RAGResult create() => RAGResult._();
  RAGResult createEmptyInstance() => create();
  static $pb.PbList<RAGResult> createRepeated() => $pb.PbList<RAGResult>();
  @$core.pragma('dart2js:noInline')
  static RAGResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RAGResult>(create);
  static RAGResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get answer => $_getSZ(0);
  @$pb.TagNumber(1)
  set answer($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAnswer() => $_has(0);
  @$pb.TagNumber(1)
  void clearAnswer() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<RAGSearchResult> get retrievedChunks => $_getList(1);

  @$pb.TagNumber(3)
  $core.String get contextUsed => $_getSZ(2);
  @$pb.TagNumber(3)
  set contextUsed($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasContextUsed() => $_has(2);
  @$pb.TagNumber(3)
  void clearContextUsed() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get retrievalTimeMs => $_getI64(3);
  @$pb.TagNumber(4)
  set retrievalTimeMs($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasRetrievalTimeMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearRetrievalTimeMs() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get generationTimeMs => $_getI64(4);
  @$pb.TagNumber(5)
  set generationTimeMs($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasGenerationTimeMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearGenerationTimeMs() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get totalTimeMs => $_getI64(5);
  @$pb.TagNumber(6)
  set totalTimeMs($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTotalTimeMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearTotalTimeMs() => clearField(6);
}

class RAGStatistics extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'RAGStatistics', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aInt64(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'indexedDocuments')
    ..aInt64(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'indexedChunks')
    ..aInt64(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'totalTokensIndexed')
    ..aInt64(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'lastUpdatedMs')
    ..aOS(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'indexPath')
    ..hasRequiredFields = false
  ;

  RAGStatistics._() : super();
  factory RAGStatistics({
    $fixnum.Int64? indexedDocuments,
    $fixnum.Int64? indexedChunks,
    $fixnum.Int64? totalTokensIndexed,
    $fixnum.Int64? lastUpdatedMs,
    $core.String? indexPath,
  }) {
    final _result = create();
    if (indexedDocuments != null) {
      _result.indexedDocuments = indexedDocuments;
    }
    if (indexedChunks != null) {
      _result.indexedChunks = indexedChunks;
    }
    if (totalTokensIndexed != null) {
      _result.totalTokensIndexed = totalTokensIndexed;
    }
    if (lastUpdatedMs != null) {
      _result.lastUpdatedMs = lastUpdatedMs;
    }
    if (indexPath != null) {
      _result.indexPath = indexPath;
    }
    return _result;
  }
  factory RAGStatistics.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RAGStatistics.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RAGStatistics clone() => RAGStatistics()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RAGStatistics copyWith(void Function(RAGStatistics) updates) => super.copyWith((message) => updates(message as RAGStatistics)) as RAGStatistics; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static RAGStatistics create() => RAGStatistics._();
  RAGStatistics createEmptyInstance() => create();
  static $pb.PbList<RAGStatistics> createRepeated() => $pb.PbList<RAGStatistics>();
  @$core.pragma('dart2js:noInline')
  static RAGStatistics getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RAGStatistics>(create);
  static RAGStatistics? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get indexedDocuments => $_getI64(0);
  @$pb.TagNumber(1)
  set indexedDocuments($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasIndexedDocuments() => $_has(0);
  @$pb.TagNumber(1)
  void clearIndexedDocuments() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get indexedChunks => $_getI64(1);
  @$pb.TagNumber(2)
  set indexedChunks($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasIndexedChunks() => $_has(1);
  @$pb.TagNumber(2)
  void clearIndexedChunks() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get totalTokensIndexed => $_getI64(2);
  @$pb.TagNumber(3)
  set totalTokensIndexed($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTotalTokensIndexed() => $_has(2);
  @$pb.TagNumber(3)
  void clearTotalTokensIndexed() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get lastUpdatedMs => $_getI64(3);
  @$pb.TagNumber(4)
  set lastUpdatedMs($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasLastUpdatedMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearLastUpdatedMs() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get indexPath => $_getSZ(4);
  @$pb.TagNumber(5)
  set indexPath($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasIndexPath() => $_has(4);
  @$pb.TagNumber(5)
  void clearIndexPath() => clearField(5);
}

