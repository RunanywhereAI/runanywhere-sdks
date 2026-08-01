// This is a generated file - do not edit.
//
// Generated from rag.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'errors.pb.dart' as $2;
import 'llm_options.pb.dart' as $0;
import 'rag.pbenum.dart';
import 'token_usage.pb.dart' as $1;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'rag.pbenum.dart';

class RAGConfiguration extends $pb.GeneratedMessage {
  factory RAGConfiguration({
    $core.String? embeddingModelId,
    $core.String? llmModelId,
    $core.int? embeddingDimension,
    $core.int? topK,
    $core.double? similarityThreshold,
    $core.int? chunkSize,
    $core.int? chunkOverlap,
    $core.int? maxContextTokens,
    $core.String? promptTemplate,
    $core.String? embeddingConfigJson,
    $core.String? llmConfigJson,
    $core.String? indexPath,
    $core.bool? persistIndex,
    $core.bool? rerankResults,
    $core.String? rerankerModelId,
  }) {
    final result = create();
    if (embeddingModelId != null) result.embeddingModelId = embeddingModelId;
    if (llmModelId != null) result.llmModelId = llmModelId;
    if (embeddingDimension != null)
      result.embeddingDimension = embeddingDimension;
    if (topK != null) result.topK = topK;
    if (similarityThreshold != null)
      result.similarityThreshold = similarityThreshold;
    if (chunkSize != null) result.chunkSize = chunkSize;
    if (chunkOverlap != null) result.chunkOverlap = chunkOverlap;
    if (maxContextTokens != null) result.maxContextTokens = maxContextTokens;
    if (promptTemplate != null) result.promptTemplate = promptTemplate;
    if (embeddingConfigJson != null)
      result.embeddingConfigJson = embeddingConfigJson;
    if (llmConfigJson != null) result.llmConfigJson = llmConfigJson;
    if (indexPath != null) result.indexPath = indexPath;
    if (persistIndex != null) result.persistIndex = persistIndex;
    if (rerankResults != null) result.rerankResults = rerankResults;
    if (rerankerModelId != null) result.rerankerModelId = rerankerModelId;
    return result;
  }

  RAGConfiguration._();

  factory RAGConfiguration.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RAGConfiguration.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RAGConfiguration',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'embeddingModelId')
    ..aOS(2, _omitFieldNames ? '' : 'llmModelId')
    ..aI(3, _omitFieldNames ? '' : 'embeddingDimension')
    ..aI(4, _omitFieldNames ? '' : 'topK')
    ..aD(5, _omitFieldNames ? '' : 'similarityThreshold',
        fieldType: $pb.PbFieldType.OF)
    ..aI(6, _omitFieldNames ? '' : 'chunkSize')
    ..aI(7, _omitFieldNames ? '' : 'chunkOverlap')
    ..aI(8, _omitFieldNames ? '' : 'maxContextTokens')
    ..aOS(9, _omitFieldNames ? '' : 'promptTemplate')
    ..aOS(10, _omitFieldNames ? '' : 'embeddingConfigJson')
    ..aOS(11, _omitFieldNames ? '' : 'llmConfigJson')
    ..aOS(12, _omitFieldNames ? '' : 'indexPath')
    ..aOB(13, _omitFieldNames ? '' : 'persistIndex')
    ..aOB(14, _omitFieldNames ? '' : 'rerankResults')
    ..aOS(15, _omitFieldNames ? '' : 'rerankerModelId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGConfiguration clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGConfiguration copyWith(void Function(RAGConfiguration) updates) =>
      super.copyWith((message) => updates(message as RAGConfiguration))
          as RAGConfiguration;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGConfiguration create() => RAGConfiguration._();
  @$core.override
  RAGConfiguration createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RAGConfiguration getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RAGConfiguration>(create);
  static RAGConfiguration? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get embeddingModelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set embeddingModelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEmbeddingModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearEmbeddingModelId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get llmModelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set llmModelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLlmModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearLlmModelId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get embeddingDimension => $_getIZ(2);
  @$pb.TagNumber(3)
  set embeddingDimension($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEmbeddingDimension() => $_has(2);
  @$pb.TagNumber(3)
  void clearEmbeddingDimension() => $_clearField(3);

  /// Retrieval depth, not sampling top_k.
  @$pb.TagNumber(4)
  $core.int get topK => $_getIZ(3);
  @$pb.TagNumber(4)
  set topK($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTopK() => $_has(3);
  @$pb.TagNumber(4)
  void clearTopK() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get similarityThreshold => $_getN(4);
  @$pb.TagNumber(5)
  set similarityThreshold($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSimilarityThreshold() => $_has(4);
  @$pb.TagNumber(5)
  void clearSimilarityThreshold() => $_clearField(5);

  /// Tokens per chunk, and the overlap carried between adjacent chunks.
  @$pb.TagNumber(6)
  $core.int get chunkSize => $_getIZ(5);
  @$pb.TagNumber(6)
  set chunkSize($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasChunkSize() => $_has(5);
  @$pb.TagNumber(6)
  void clearChunkSize() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get chunkOverlap => $_getIZ(6);
  @$pb.TagNumber(7)
  set chunkOverlap($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasChunkOverlap() => $_has(6);
  @$pb.TagNumber(7)
  void clearChunkOverlap() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get maxContextTokens => $_getIZ(7);
  @$pb.TagNumber(8)
  set maxContextTokens($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasMaxContextTokens() => $_has(7);
  @$pb.TagNumber(8)
  void clearMaxContextTokens() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get promptTemplate => $_getSZ(8);
  @$pb.TagNumber(9)
  set promptTemplate($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasPromptTemplate() => $_has(8);
  @$pb.TagNumber(9)
  void clearPromptTemplate() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get embeddingConfigJson => $_getSZ(9);
  @$pb.TagNumber(10)
  set embeddingConfigJson($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasEmbeddingConfigJson() => $_has(9);
  @$pb.TagNumber(10)
  void clearEmbeddingConfigJson() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get llmConfigJson => $_getSZ(10);
  @$pb.TagNumber(11)
  set llmConfigJson($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasLlmConfigJson() => $_has(10);
  @$pb.TagNumber(11)
  void clearLlmConfigJson() => $_clearField(11);

  /// Where the vector index lives, and whether it survives the session.
  @$pb.TagNumber(12)
  $core.String get indexPath => $_getSZ(11);
  @$pb.TagNumber(12)
  set indexPath($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasIndexPath() => $_has(11);
  @$pb.TagNumber(12)
  void clearIndexPath() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.bool get persistIndex => $_getBF(12);
  @$pb.TagNumber(13)
  set persistIndex($core.bool value) => $_setBool(12, value);
  @$pb.TagNumber(13)
  $core.bool hasPersistIndex() => $_has(12);
  @$pb.TagNumber(13)
  void clearPersistIndex() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.bool get rerankResults => $_getBF(13);
  @$pb.TagNumber(14)
  set rerankResults($core.bool value) => $_setBool(13, value);
  @$pb.TagNumber(14)
  $core.bool hasRerankResults() => $_has(13);
  @$pb.TagNumber(14)
  void clearRerankResults() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.String get rerankerModelId => $_getSZ(14);
  @$pb.TagNumber(15)
  set rerankerModelId($core.String value) => $_setString(14, value);
  @$pb.TagNumber(15)
  $core.bool hasRerankerModelId() => $_has(14);
  @$pb.TagNumber(15)
  void clearRerankerModelId() => $_clearField(15);
}

class RAGDocument extends $pb.GeneratedMessage {
  factory RAGDocument({
    $core.String? id,
    $core.String? text,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
    $core.String? sourceUri,
    $core.String? adapterHandle,
    $core.String? mediaType,
    $fixnum.Int64? sizeBytes,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (text != null) result.text = text;
    if (metadata != null) result.metadata.addEntries(metadata);
    if (sourceUri != null) result.sourceUri = sourceUri;
    if (adapterHandle != null) result.adapterHandle = adapterHandle;
    if (mediaType != null) result.mediaType = mediaType;
    if (sizeBytes != null) result.sizeBytes = sizeBytes;
    return result;
  }

  RAGDocument._();

  factory RAGDocument.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RAGDocument.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RAGDocument',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'text')
    ..m<$core.String, $core.String>(4, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'RAGDocument.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..aOS(5, _omitFieldNames ? '' : 'sourceUri')
    ..aOS(6, _omitFieldNames ? '' : 'adapterHandle')
    ..aOS(7, _omitFieldNames ? '' : 'mediaType')
    ..aInt64(8, _omitFieldNames ? '' : 'sizeBytes')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGDocument clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGDocument copyWith(void Function(RAGDocument) updates) =>
      super.copyWith((message) => updates(message as RAGDocument))
          as RAGDocument;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGDocument create() => RAGDocument._();
  @$core.override
  RAGDocument createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RAGDocument getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RAGDocument>(create);
  static RAGDocument? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get text => $_getSZ(1);
  @$pb.TagNumber(2)
  set text($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => $_clearField(2);

  @$pb.TagNumber(4)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(2);

  @$pb.TagNumber(5)
  $core.String get sourceUri => $_getSZ(3);
  @$pb.TagNumber(5)
  set sourceUri($core.String value) => $_setString(3, value);
  @$pb.TagNumber(5)
  $core.bool hasSourceUri() => $_has(3);
  @$pb.TagNumber(5)
  void clearSourceUri() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get adapterHandle => $_getSZ(4);
  @$pb.TagNumber(6)
  set adapterHandle($core.String value) => $_setString(4, value);
  @$pb.TagNumber(6)
  $core.bool hasAdapterHandle() => $_has(4);
  @$pb.TagNumber(6)
  void clearAdapterHandle() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get mediaType => $_getSZ(5);
  @$pb.TagNumber(7)
  set mediaType($core.String value) => $_setString(5, value);
  @$pb.TagNumber(7)
  $core.bool hasMediaType() => $_has(5);
  @$pb.TagNumber(7)
  void clearMediaType() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get sizeBytes => $_getI64(6);
  @$pb.TagNumber(8)
  set sizeBytes($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(8)
  $core.bool hasSizeBytes() => $_has(6);
  @$pb.TagNumber(8)
  void clearSizeBytes() => $_clearField(8);
}

class RAGQueryOptions extends $pb.GeneratedMessage {
  factory RAGQueryOptions({
    $core.String? question,
    $core.int? retrievalTopK,
    $core.double? similarityThreshold,
    $core.bool? stream,
    $core.bool? enableMultiQuery,
    $core.int? multiQueryCount,
    $core.String? scopePrefix,
    $0.LLMGenerationOptions? generation,
  }) {
    final result = create();
    if (question != null) result.question = question;
    if (retrievalTopK != null) result.retrievalTopK = retrievalTopK;
    if (similarityThreshold != null)
      result.similarityThreshold = similarityThreshold;
    if (stream != null) result.stream = stream;
    if (enableMultiQuery != null) result.enableMultiQuery = enableMultiQuery;
    if (multiQueryCount != null) result.multiQueryCount = multiQueryCount;
    if (scopePrefix != null) result.scopePrefix = scopePrefix;
    if (generation != null) result.generation = generation;
    return result;
  }

  RAGQueryOptions._();

  factory RAGQueryOptions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RAGQueryOptions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RAGQueryOptions',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'question')
    ..aI(7, _omitFieldNames ? '' : 'retrievalTopK')
    ..aD(8, _omitFieldNames ? '' : 'similarityThreshold',
        fieldType: $pb.PbFieldType.OF)
    ..aOB(9, _omitFieldNames ? '' : 'stream')
    ..aOB(11, _omitFieldNames ? '' : 'enableMultiQuery')
    ..aI(12, _omitFieldNames ? '' : 'multiQueryCount')
    ..aOS(13, _omitFieldNames ? '' : 'scopePrefix')
    ..aOM<$0.LLMGenerationOptions>(14, _omitFieldNames ? '' : 'generation',
        subBuilder: $0.LLMGenerationOptions.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGQueryOptions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGQueryOptions copyWith(void Function(RAGQueryOptions) updates) =>
      super.copyWith((message) => updates(message as RAGQueryOptions))
          as RAGQueryOptions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGQueryOptions create() => RAGQueryOptions._();
  @$core.override
  RAGQueryOptions createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RAGQueryOptions getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RAGQueryOptions>(create);
  static RAGQueryOptions? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get question => $_getSZ(0);
  @$pb.TagNumber(1)
  set question($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasQuestion() => $_has(0);
  @$pb.TagNumber(1)
  void clearQuestion() => $_clearField(1);

  /// Retrieval depth for this call, overriding RAGConfiguration.top_k.
  @$pb.TagNumber(7)
  $core.int get retrievalTopK => $_getIZ(1);
  @$pb.TagNumber(7)
  set retrievalTopK($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(7)
  $core.bool hasRetrievalTopK() => $_has(1);
  @$pb.TagNumber(7)
  void clearRetrievalTopK() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.double get similarityThreshold => $_getN(2);
  @$pb.TagNumber(8)
  set similarityThreshold($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(8)
  $core.bool hasSimilarityThreshold() => $_has(2);
  @$pb.TagNumber(8)
  void clearSimilarityThreshold() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.bool get stream => $_getBF(3);
  @$pb.TagNumber(9)
  set stream($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(9)
  $core.bool hasStream() => $_has(3);
  @$pb.TagNumber(9)
  void clearStream() => $_clearField(9);

  /// Expand the question into several queries and merge the results.
  @$pb.TagNumber(11)
  $core.bool get enableMultiQuery => $_getBF(4);
  @$pb.TagNumber(11)
  set enableMultiQuery($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(11)
  $core.bool hasEnableMultiQuery() => $_has(4);
  @$pb.TagNumber(11)
  void clearEnableMultiQuery() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.int get multiQueryCount => $_getIZ(5);
  @$pb.TagNumber(12)
  set multiQueryCount($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(12)
  $core.bool hasMultiQueryCount() => $_has(5);
  @$pb.TagNumber(12)
  void clearMultiQueryCount() => $_clearField(12);

  /// Restrict retrieval to chunks whose source matches this prefix.
  @$pb.TagNumber(13)
  $core.String get scopePrefix => $_getSZ(6);
  @$pb.TagNumber(13)
  set scopePrefix($core.String value) => $_setString(6, value);
  @$pb.TagNumber(13)
  $core.bool hasScopePrefix() => $_has(6);
  @$pb.TagNumber(13)
  void clearScopePrefix() => $_clearField(13);

  @$pb.TagNumber(14)
  $0.LLMGenerationOptions get generation => $_getN(7);
  @$pb.TagNumber(14)
  set generation($0.LLMGenerationOptions value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasGeneration() => $_has(7);
  @$pb.TagNumber(14)
  void clearGeneration() => $_clearField(14);
  @$pb.TagNumber(14)
  $0.LLMGenerationOptions ensureGeneration() => $_ensure(7);
}

class RAGSearchResult extends $pb.GeneratedMessage {
  factory RAGSearchResult({
    $core.String? chunkId,
    $core.String? text,
    $core.double? similarityScore,
    $core.String? sourceDocument,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
    $core.int? rank,
    $core.int? startOffset,
    $core.int? endOffset,
    $core.int? tokenCount,
  }) {
    final result = create();
    if (chunkId != null) result.chunkId = chunkId;
    if (text != null) result.text = text;
    if (similarityScore != null) result.similarityScore = similarityScore;
    if (sourceDocument != null) result.sourceDocument = sourceDocument;
    if (metadata != null) result.metadata.addEntries(metadata);
    if (rank != null) result.rank = rank;
    if (startOffset != null) result.startOffset = startOffset;
    if (endOffset != null) result.endOffset = endOffset;
    if (tokenCount != null) result.tokenCount = tokenCount;
    return result;
  }

  RAGSearchResult._();

  factory RAGSearchResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RAGSearchResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RAGSearchResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'chunkId')
    ..aOS(2, _omitFieldNames ? '' : 'text')
    ..aD(3, _omitFieldNames ? '' : 'similarityScore',
        fieldType: $pb.PbFieldType.OF)
    ..aOS(4, _omitFieldNames ? '' : 'sourceDocument')
    ..m<$core.String, $core.String>(5, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'RAGSearchResult.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..aI(7, _omitFieldNames ? '' : 'rank')
    ..aI(8, _omitFieldNames ? '' : 'startOffset')
    ..aI(9, _omitFieldNames ? '' : 'endOffset')
    ..aI(10, _omitFieldNames ? '' : 'tokenCount')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGSearchResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGSearchResult copyWith(void Function(RAGSearchResult) updates) =>
      super.copyWith((message) => updates(message as RAGSearchResult))
          as RAGSearchResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGSearchResult create() => RAGSearchResult._();
  @$core.override
  RAGSearchResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RAGSearchResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RAGSearchResult>(create);
  static RAGSearchResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get chunkId => $_getSZ(0);
  @$pb.TagNumber(1)
  set chunkId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChunkId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChunkId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get text => $_getSZ(1);
  @$pb.TagNumber(2)
  set text($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get similarityScore => $_getN(2);
  @$pb.TagNumber(3)
  set similarityScore($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSimilarityScore() => $_has(2);
  @$pb.TagNumber(3)
  void clearSimilarityScore() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get sourceDocument => $_getSZ(3);
  @$pb.TagNumber(4)
  set sourceDocument($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSourceDocument() => $_has(3);
  @$pb.TagNumber(4)
  void clearSourceDocument() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(4);

  @$pb.TagNumber(7)
  $core.int get rank => $_getIZ(5);
  @$pb.TagNumber(7)
  set rank($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(7)
  $core.bool hasRank() => $_has(5);
  @$pb.TagNumber(7)
  void clearRank() => $_clearField(7);

  /// Character offsets into the source document.
  @$pb.TagNumber(8)
  $core.int get startOffset => $_getIZ(6);
  @$pb.TagNumber(8)
  set startOffset($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(8)
  $core.bool hasStartOffset() => $_has(6);
  @$pb.TagNumber(8)
  void clearStartOffset() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get endOffset => $_getIZ(7);
  @$pb.TagNumber(9)
  set endOffset($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(9)
  $core.bool hasEndOffset() => $_has(7);
  @$pb.TagNumber(9)
  void clearEndOffset() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get tokenCount => $_getIZ(8);
  @$pb.TagNumber(10)
  set tokenCount($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(10)
  $core.bool hasTokenCount() => $_has(8);
  @$pb.TagNumber(10)
  void clearTokenCount() => $_clearField(10);
}

class RAGResult extends $pb.GeneratedMessage {
  factory RAGResult({
    $core.String? answer,
    $core.Iterable<RAGSearchResult>? retrievedChunks,
    $core.String? contextUsed,
    $fixnum.Int64? retrievalTimeMs,
    $fixnum.Int64? generationTimeMs,
    $fixnum.Int64? totalTimeMs,
    $core.String? requestId,
    $core.String? thinkingContent,
    $1.TokenUsage? usage,
    $2.SDKError? error,
  }) {
    final result = create();
    if (answer != null) result.answer = answer;
    if (retrievedChunks != null) result.retrievedChunks.addAll(retrievedChunks);
    if (contextUsed != null) result.contextUsed = contextUsed;
    if (retrievalTimeMs != null) result.retrievalTimeMs = retrievalTimeMs;
    if (generationTimeMs != null) result.generationTimeMs = generationTimeMs;
    if (totalTimeMs != null) result.totalTimeMs = totalTimeMs;
    if (requestId != null) result.requestId = requestId;
    if (thinkingContent != null) result.thinkingContent = thinkingContent;
    if (usage != null) result.usage = usage;
    if (error != null) result.error = error;
    return result;
  }

  RAGResult._();

  factory RAGResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RAGResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RAGResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'answer')
    ..pPM<RAGSearchResult>(2, _omitFieldNames ? '' : 'retrievedChunks',
        subBuilder: RAGSearchResult.create)
    ..aOS(3, _omitFieldNames ? '' : 'contextUsed')
    ..aInt64(4, _omitFieldNames ? '' : 'retrievalTimeMs')
    ..aInt64(5, _omitFieldNames ? '' : 'generationTimeMs')
    ..aInt64(6, _omitFieldNames ? '' : 'totalTimeMs')
    ..aOS(12, _omitFieldNames ? '' : 'requestId')
    ..aOS(13, _omitFieldNames ? '' : 'thinkingContent')
    ..aOM<$1.TokenUsage>(14, _omitFieldNames ? '' : 'usage',
        subBuilder: $1.TokenUsage.create)
    ..aOM<$2.SDKError>(15, _omitFieldNames ? '' : 'error',
        subBuilder: $2.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGResult copyWith(void Function(RAGResult) updates) =>
      super.copyWith((message) => updates(message as RAGResult)) as RAGResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGResult create() => RAGResult._();
  @$core.override
  RAGResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RAGResult getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RAGResult>(create);
  static RAGResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get answer => $_getSZ(0);
  @$pb.TagNumber(1)
  set answer($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAnswer() => $_has(0);
  @$pb.TagNumber(1)
  void clearAnswer() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<RAGSearchResult> get retrievedChunks => $_getList(1);

  @$pb.TagNumber(3)
  $core.String get contextUsed => $_getSZ(2);
  @$pb.TagNumber(3)
  set contextUsed($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasContextUsed() => $_has(2);
  @$pb.TagNumber(3)
  void clearContextUsed() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get retrievalTimeMs => $_getI64(3);
  @$pb.TagNumber(4)
  set retrievalTimeMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRetrievalTimeMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearRetrievalTimeMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get generationTimeMs => $_getI64(4);
  @$pb.TagNumber(5)
  set generationTimeMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasGenerationTimeMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearGenerationTimeMs() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get totalTimeMs => $_getI64(5);
  @$pb.TagNumber(6)
  set totalTimeMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTotalTimeMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearTotalTimeMs() => $_clearField(6);

  @$pb.TagNumber(12)
  $core.String get requestId => $_getSZ(6);
  @$pb.TagNumber(12)
  set requestId($core.String value) => $_setString(6, value);
  @$pb.TagNumber(12)
  $core.bool hasRequestId() => $_has(6);
  @$pb.TagNumber(12)
  void clearRequestId() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get thinkingContent => $_getSZ(7);
  @$pb.TagNumber(13)
  set thinkingContent($core.String value) => $_setString(7, value);
  @$pb.TagNumber(13)
  $core.bool hasThinkingContent() => $_has(7);
  @$pb.TagNumber(13)
  void clearThinkingContent() => $_clearField(13);

  @$pb.TagNumber(14)
  $1.TokenUsage get usage => $_getN(8);
  @$pb.TagNumber(14)
  set usage($1.TokenUsage value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasUsage() => $_has(8);
  @$pb.TagNumber(14)
  void clearUsage() => $_clearField(14);
  @$pb.TagNumber(14)
  $1.TokenUsage ensureUsage() => $_ensure(8);

  @$pb.TagNumber(15)
  $2.SDKError get error => $_getN(9);
  @$pb.TagNumber(15)
  set error($2.SDKError value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasError() => $_has(9);
  @$pb.TagNumber(15)
  void clearError() => $_clearField(15);
  @$pb.TagNumber(15)
  $2.SDKError ensureError() => $_ensure(9);
}

class RAGStatistics extends $pb.GeneratedMessage {
  factory RAGStatistics({
    $fixnum.Int64? indexedDocuments,
    $fixnum.Int64? indexedChunks,
    $fixnum.Int64? totalTokensIndexed,
    $fixnum.Int64? lastUpdatedMs,
    $core.String? indexPath,
    $core.String? statsJson,
    $fixnum.Int64? vectorStoreSizeBytes,
    $core.bool? isPersistent,
    $fixnum.Int64? lastQueryMs,
    $2.SDKError? error,
  }) {
    final result = create();
    if (indexedDocuments != null) result.indexedDocuments = indexedDocuments;
    if (indexedChunks != null) result.indexedChunks = indexedChunks;
    if (totalTokensIndexed != null)
      result.totalTokensIndexed = totalTokensIndexed;
    if (lastUpdatedMs != null) result.lastUpdatedMs = lastUpdatedMs;
    if (indexPath != null) result.indexPath = indexPath;
    if (statsJson != null) result.statsJson = statsJson;
    if (vectorStoreSizeBytes != null)
      result.vectorStoreSizeBytes = vectorStoreSizeBytes;
    if (isPersistent != null) result.isPersistent = isPersistent;
    if (lastQueryMs != null) result.lastQueryMs = lastQueryMs;
    if (error != null) result.error = error;
    return result;
  }

  RAGStatistics._();

  factory RAGStatistics.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RAGStatistics.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RAGStatistics',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'indexedDocuments')
    ..aInt64(2, _omitFieldNames ? '' : 'indexedChunks')
    ..aInt64(3, _omitFieldNames ? '' : 'totalTokensIndexed')
    ..aInt64(4, _omitFieldNames ? '' : 'lastUpdatedMs')
    ..aOS(5, _omitFieldNames ? '' : 'indexPath')
    ..aOS(6, _omitFieldNames ? '' : 'statsJson')
    ..aInt64(7, _omitFieldNames ? '' : 'vectorStoreSizeBytes')
    ..aOB(8, _omitFieldNames ? '' : 'isPersistent')
    ..aInt64(9, _omitFieldNames ? '' : 'lastQueryMs')
    ..aOM<$2.SDKError>(12, _omitFieldNames ? '' : 'error',
        subBuilder: $2.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGStatistics clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGStatistics copyWith(void Function(RAGStatistics) updates) =>
      super.copyWith((message) => updates(message as RAGStatistics))
          as RAGStatistics;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGStatistics create() => RAGStatistics._();
  @$core.override
  RAGStatistics createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RAGStatistics getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RAGStatistics>(create);
  static RAGStatistics? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get indexedDocuments => $_getI64(0);
  @$pb.TagNumber(1)
  set indexedDocuments($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIndexedDocuments() => $_has(0);
  @$pb.TagNumber(1)
  void clearIndexedDocuments() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get indexedChunks => $_getI64(1);
  @$pb.TagNumber(2)
  set indexedChunks($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIndexedChunks() => $_has(1);
  @$pb.TagNumber(2)
  void clearIndexedChunks() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get totalTokensIndexed => $_getI64(2);
  @$pb.TagNumber(3)
  set totalTokensIndexed($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTotalTokensIndexed() => $_has(2);
  @$pb.TagNumber(3)
  void clearTotalTokensIndexed() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get lastUpdatedMs => $_getI64(3);
  @$pb.TagNumber(4)
  set lastUpdatedMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLastUpdatedMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearLastUpdatedMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get indexPath => $_getSZ(4);
  @$pb.TagNumber(5)
  set indexPath($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasIndexPath() => $_has(4);
  @$pb.TagNumber(5)
  void clearIndexPath() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get statsJson => $_getSZ(5);
  @$pb.TagNumber(6)
  set statsJson($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasStatsJson() => $_has(5);
  @$pb.TagNumber(6)
  void clearStatsJson() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get vectorStoreSizeBytes => $_getI64(6);
  @$pb.TagNumber(7)
  set vectorStoreSizeBytes($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasVectorStoreSizeBytes() => $_has(6);
  @$pb.TagNumber(7)
  void clearVectorStoreSizeBytes() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get isPersistent => $_getBF(7);
  @$pb.TagNumber(8)
  set isPersistent($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasIsPersistent() => $_has(7);
  @$pb.TagNumber(8)
  void clearIsPersistent() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get lastQueryMs => $_getI64(8);
  @$pb.TagNumber(9)
  set lastQueryMs($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasLastQueryMs() => $_has(8);
  @$pb.TagNumber(9)
  void clearLastQueryMs() => $_clearField(9);

  @$pb.TagNumber(12)
  $2.SDKError get error => $_getN(9);
  @$pb.TagNumber(12)
  set error($2.SDKError value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasError() => $_has(9);
  @$pb.TagNumber(12)
  void clearError() => $_clearField(12);
  @$pb.TagNumber(12)
  $2.SDKError ensureError() => $_ensure(9);
}

class RAGStreamEvent extends $pb.GeneratedMessage {
  factory RAGStreamEvent({
    $fixnum.Int64? timestampUs,
    $core.String? requestId,
    RAGStreamEventKind? kind,
    RAGSearchResult? chunk,
    $core.String? token,
    RAGResult? result,
    $2.SDKError? error,
  }) {
    final result$ = create();
    if (timestampUs != null) result$.timestampUs = timestampUs;
    if (requestId != null) result$.requestId = requestId;
    if (kind != null) result$.kind = kind;
    if (chunk != null) result$.chunk = chunk;
    if (token != null) result$.token = token;
    if (result != null) result$.result = result;
    if (error != null) result$.error = error;
    return result$;
  }

  RAGStreamEvent._();

  factory RAGStreamEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RAGStreamEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RAGStreamEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(3, _omitFieldNames ? '' : 'requestId')
    ..aE<RAGStreamEventKind>(4, _omitFieldNames ? '' : 'kind',
        enumValues: RAGStreamEventKind.values)
    ..aOM<RAGSearchResult>(5, _omitFieldNames ? '' : 'chunk',
        subBuilder: RAGSearchResult.create)
    ..aOS(6, _omitFieldNames ? '' : 'token')
    ..aOM<RAGResult>(7, _omitFieldNames ? '' : 'result',
        subBuilder: RAGResult.create)
    ..aOM<$2.SDKError>(10, _omitFieldNames ? '' : 'error',
        subBuilder: $2.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGStreamEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGStreamEvent copyWith(void Function(RAGStreamEvent) updates) =>
      super.copyWith((message) => updates(message as RAGStreamEvent))
          as RAGStreamEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGStreamEvent create() => RAGStreamEvent._();
  @$core.override
  RAGStreamEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RAGStreamEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RAGStreamEvent>(create);
  static RAGStreamEvent? _defaultInstance;

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
  RAGStreamEventKind get kind => $_getN(2);
  @$pb.TagNumber(4)
  set kind(RAGStreamEventKind value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasKind() => $_has(2);
  @$pb.TagNumber(4)
  void clearKind() => $_clearField(4);

  @$pb.TagNumber(5)
  RAGSearchResult get chunk => $_getN(3);
  @$pb.TagNumber(5)
  set chunk(RAGSearchResult value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasChunk() => $_has(3);
  @$pb.TagNumber(5)
  void clearChunk() => $_clearField(5);
  @$pb.TagNumber(5)
  RAGSearchResult ensureChunk() => $_ensure(3);

  @$pb.TagNumber(6)
  $core.String get token => $_getSZ(4);
  @$pb.TagNumber(6)
  set token($core.String value) => $_setString(4, value);
  @$pb.TagNumber(6)
  $core.bool hasToken() => $_has(4);
  @$pb.TagNumber(6)
  void clearToken() => $_clearField(6);

  @$pb.TagNumber(7)
  RAGResult get result => $_getN(5);
  @$pb.TagNumber(7)
  set result(RAGResult value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasResult() => $_has(5);
  @$pb.TagNumber(7)
  void clearResult() => $_clearField(7);
  @$pb.TagNumber(7)
  RAGResult ensureResult() => $_ensure(5);

  @$pb.TagNumber(10)
  $2.SDKError get error => $_getN(6);
  @$pb.TagNumber(10)
  set error($2.SDKError value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasError() => $_has(6);
  @$pb.TagNumber(10)
  void clearError() => $_clearField(10);
  @$pb.TagNumber(10)
  $2.SDKError ensureError() => $_ensure(6);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
