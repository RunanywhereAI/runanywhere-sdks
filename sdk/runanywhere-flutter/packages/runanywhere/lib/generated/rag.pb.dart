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

import 'errors.pb.dart' as $0;
import 'llm_options.pb.dart' as $1;
import 'rag.pbenum.dart';
import 'token_usage.pb.dart' as $2;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'rag.pbenum.dart';

class RAGConfiguration extends $pb.GeneratedMessage {
  factory RAGConfiguration({
    $core.String? embeddingModelId,
    $core.String? llmModelId,
    $core.int? embeddingDimension,
    $core.int? topK,
    $core.double? scoreThreshold,
    $core.int? chunkSize,
    $core.int? chunkOverlap,
    $core.int? maxContextTokens,
    $core.String? promptTemplate,
    $core.String? embeddingConfigJson,
    $core.bool? rerankResults,
  }) {
    final result = create();
    if (embeddingModelId != null) result.embeddingModelId = embeddingModelId;
    if (llmModelId != null) result.llmModelId = llmModelId;
    if (embeddingDimension != null)
      result.embeddingDimension = embeddingDimension;
    if (topK != null) result.topK = topK;
    if (scoreThreshold != null) result.scoreThreshold = scoreThreshold;
    if (chunkSize != null) result.chunkSize = chunkSize;
    if (chunkOverlap != null) result.chunkOverlap = chunkOverlap;
    if (maxContextTokens != null) result.maxContextTokens = maxContextTokens;
    if (promptTemplate != null) result.promptTemplate = promptTemplate;
    if (embeddingConfigJson != null)
      result.embeddingConfigJson = embeddingConfigJson;
    if (rerankResults != null) result.rerankResults = rerankResults;
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
    ..aD(5, _omitFieldNames ? '' : 'scoreThreshold',
        fieldType: $pb.PbFieldType.OF)
    ..aI(6, _omitFieldNames ? '' : 'chunkSize')
    ..aI(7, _omitFieldNames ? '' : 'chunkOverlap')
    ..aI(8, _omitFieldNames ? '' : 'maxContextTokens')
    ..aOS(9, _omitFieldNames ? '' : 'promptTemplate')
    ..aOS(10, _omitFieldNames ? '' : 'embeddingConfigJson')
    ..aOB(11, _omitFieldNames ? '' : 'rerankResults')
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

  /// Drop hits scoring below this. 0.0 = no filtering.
  @$pb.TagNumber(5)
  $core.double get scoreThreshold => $_getN(4);
  @$pb.TagNumber(5)
  set scoreThreshold($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasScoreThreshold() => $_has(4);
  @$pb.TagNumber(5)
  void clearScoreThreshold() => $_clearField(5);

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

  /// Pointwise rerank of the retrieved chunks using the session LLM.
  @$pb.TagNumber(11)
  $core.bool get rerankResults => $_getBF(10);
  @$pb.TagNumber(11)
  set rerankResults($core.bool value) => $_setBool(10, value);
  @$pb.TagNumber(11)
  $core.bool hasRerankResults() => $_has(10);
  @$pb.TagNumber(11)
  void clearRerankResults() => $_clearField(11);
}

class RAGDocument extends $pb.GeneratedMessage {
  factory RAGDocument({
    $core.String? id,
    $core.String? text,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
    $core.String? sourceUri,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (text != null) result.text = text;
    if (metadata != null) result.metadata.addEntries(metadata);
    if (sourceUri != null) result.sourceUri = sourceUri;
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
    ..m<$core.String, $core.String>(3, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'RAGDocument.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..aOS(4, _omitFieldNames ? '' : 'sourceUri')
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

  /// Caller-owned stable id. Re-ingesting an existing id REPLACES its chunks.
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

  @$pb.TagNumber(3)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(2);

  /// Where this document came from. Copied into every chunk's metadata as
  /// "source" and returned as RAGSearchResult.source_document.
  @$pb.TagNumber(4)
  $core.String get sourceUri => $_getSZ(3);
  @$pb.TagNumber(4)
  set sourceUri($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSourceUri() => $_has(3);
  @$pb.TagNumber(4)
  void clearSourceUri() => $_clearField(4);
}

/// Remove whole documents from the index for `rac_rag_delete_proto`.
class RAGDeleteRequest extends $pb.GeneratedMessage {
  factory RAGDeleteRequest({
    $core.Iterable<$core.String>? documentIds,
  }) {
    final result = create();
    if (documentIds != null) result.documentIds.addAll(documentIds);
    return result;
  }

  RAGDeleteRequest._();

  factory RAGDeleteRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RAGDeleteRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RAGDeleteRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'documentIds')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGDeleteRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGDeleteRequest copyWith(void Function(RAGDeleteRequest) updates) =>
      super.copyWith((message) => updates(message as RAGDeleteRequest))
          as RAGDeleteRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGDeleteRequest create() => RAGDeleteRequest._();
  @$core.override
  RAGDeleteRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RAGDeleteRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RAGDeleteRequest>(create);
  static RAGDeleteRequest? _defaultInstance;

  /// RAGDocument.id values given at ingest. Empty is an error — use clear().
  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get documentIds => $_getList(0);
}

class RAGDeleteResponse extends $pb.GeneratedMessage {
  factory RAGDeleteResponse({
    $fixnum.Int64? deletedChunks,
    $core.Iterable<$core.String>? missingIds,
    $0.SDKError? error,
  }) {
    final result = create();
    if (deletedChunks != null) result.deletedChunks = deletedChunks;
    if (missingIds != null) result.missingIds.addAll(missingIds);
    if (error != null) result.error = error;
    return result;
  }

  RAGDeleteResponse._();

  factory RAGDeleteResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RAGDeleteResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RAGDeleteResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'deletedChunks')
    ..pPS(2, _omitFieldNames ? '' : 'missingIds')
    ..aOM<$0.SDKError>(3, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGDeleteResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGDeleteResponse copyWith(void Function(RAGDeleteResponse) updates) =>
      super.copyWith((message) => updates(message as RAGDeleteResponse))
          as RAGDeleteResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGDeleteResponse create() => RAGDeleteResponse._();
  @$core.override
  RAGDeleteResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RAGDeleteResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RAGDeleteResponse>(create);
  static RAGDeleteResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get deletedChunks => $_getI64(0);
  @$pb.TagNumber(1)
  set deletedChunks($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDeletedChunks() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeletedChunks() => $_clearField(1);

  /// Ids that were not in the index. Not an error.
  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get missingIds => $_getList(1);

  @$pb.TagNumber(3)
  $0.SDKError get error => $_getN(2);
  @$pb.TagNumber(3)
  set error($0.SDKError value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(3)
  void clearError() => $_clearField(3);
  @$pb.TagNumber(3)
  $0.SDKError ensureError() => $_ensure(2);
}

/// The retrieval knobs, declared once. Every field unset = inherit RAGConfiguration.
class RAGRetrievalOptions extends $pb.GeneratedMessage {
  factory RAGRetrievalOptions({
    $core.int? topK,
    $core.double? scoreThreshold,
    $core.bool? enableMultiQuery,
    $core.int? multiQueryCount,
    $core.String? scopePrefix,
  }) {
    final result = create();
    if (topK != null) result.topK = topK;
    if (scoreThreshold != null) result.scoreThreshold = scoreThreshold;
    if (enableMultiQuery != null) result.enableMultiQuery = enableMultiQuery;
    if (multiQueryCount != null) result.multiQueryCount = multiQueryCount;
    if (scopePrefix != null) result.scopePrefix = scopePrefix;
    return result;
  }

  RAGRetrievalOptions._();

  factory RAGRetrievalOptions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RAGRetrievalOptions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RAGRetrievalOptions',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'topK')
    ..aD(2, _omitFieldNames ? '' : 'scoreThreshold',
        fieldType: $pb.PbFieldType.OF)
    ..aOB(3, _omitFieldNames ? '' : 'enableMultiQuery')
    ..aI(4, _omitFieldNames ? '' : 'multiQueryCount')
    ..aOS(5, _omitFieldNames ? '' : 'scopePrefix')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGRetrievalOptions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGRetrievalOptions copyWith(void Function(RAGRetrievalOptions) updates) =>
      super.copyWith((message) => updates(message as RAGRetrievalOptions))
          as RAGRetrievalOptions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGRetrievalOptions create() => RAGRetrievalOptions._();
  @$core.override
  RAGRetrievalOptions createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RAGRetrievalOptions getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RAGRetrievalOptions>(create);
  static RAGRetrievalOptions? _defaultInstance;

  /// Retrieval depth for this call. Unset inherits RAGConfiguration.top_k.
  @$pb.TagNumber(1)
  $core.int get topK => $_getIZ(0);
  @$pb.TagNumber(1)
  set topK($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTopK() => $_has(0);
  @$pb.TagNumber(1)
  void clearTopK() => $_clearField(1);

  /// Drop hits scoring below this. Unset inherits RAGConfiguration.score_threshold.
  @$pb.TagNumber(2)
  $core.double get scoreThreshold => $_getN(1);
  @$pb.TagNumber(2)
  set scoreThreshold($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasScoreThreshold() => $_has(1);
  @$pb.TagNumber(2)
  void clearScoreThreshold() => $_clearField(2);

  /// Expand the query into several phrasings and merge the results.
  /// Requires a session LLM.
  @$pb.TagNumber(3)
  $core.bool get enableMultiQuery => $_getBF(2);
  @$pb.TagNumber(3)
  set enableMultiQuery($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEnableMultiQuery() => $_has(2);
  @$pb.TagNumber(3)
  void clearEnableMultiQuery() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get multiQueryCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set multiQueryCount($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMultiQueryCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearMultiQueryCount() => $_clearField(4);

  /// Keep only chunks whose document id starts with this prefix.
  @$pb.TagNumber(5)
  $core.String get scopePrefix => $_getSZ(4);
  @$pb.TagNumber(5)
  set scopePrefix($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasScopePrefix() => $_has(4);
  @$pb.TagNumber(5)
  void clearScopePrefix() => $_clearField(5);
}

class RAGQueryOptions extends $pb.GeneratedMessage {
  factory RAGQueryOptions({
    $core.String? query,
    RAGRetrievalOptions? retrieval,
    $1.LLMGenerationOptions? generation,
  }) {
    final result = create();
    if (query != null) result.query = query;
    if (retrieval != null) result.retrieval = retrieval;
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
    ..aOS(1, _omitFieldNames ? '' : 'query')
    ..aOM<RAGRetrievalOptions>(2, _omitFieldNames ? '' : 'retrieval',
        subBuilder: RAGRetrievalOptions.create)
    ..aOM<$1.LLMGenerationOptions>(3, _omitFieldNames ? '' : 'generation',
        subBuilder: $1.LLMGenerationOptions.create)
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
  $core.String get query => $_getSZ(0);
  @$pb.TagNumber(1)
  set query($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasQuery() => $_has(0);
  @$pb.TagNumber(1)
  void clearQuery() => $_clearField(1);

  @$pb.TagNumber(2)
  RAGRetrievalOptions get retrieval => $_getN(1);
  @$pb.TagNumber(2)
  set retrieval(RAGRetrievalOptions value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasRetrieval() => $_has(1);
  @$pb.TagNumber(2)
  void clearRetrieval() => $_clearField(2);
  @$pb.TagNumber(2)
  RAGRetrievalOptions ensureRetrieval() => $_ensure(1);

  @$pb.TagNumber(3)
  $1.LLMGenerationOptions get generation => $_getN(2);
  @$pb.TagNumber(3)
  set generation($1.LLMGenerationOptions value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasGeneration() => $_has(2);
  @$pb.TagNumber(3)
  void clearGeneration() => $_clearField(3);
  @$pb.TagNumber(3)
  $1.LLMGenerationOptions ensureGeneration() => $_ensure(2);
}

/// Retrieval-only request for `rac_rag_search_proto` / SDK `rag.search()`.
/// Intentionally omits generation options — that is `RAGQueryOptions` /
/// `rac_rag_query_proto` / SDK `rag.query()`.
class RAGSearchRequest extends $pb.GeneratedMessage {
  factory RAGSearchRequest({
    $core.String? query,
    RAGRetrievalOptions? retrieval,
  }) {
    final result = create();
    if (query != null) result.query = query;
    if (retrieval != null) result.retrieval = retrieval;
    return result;
  }

  RAGSearchRequest._();

  factory RAGSearchRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RAGSearchRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RAGSearchRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'query')
    ..aOM<RAGRetrievalOptions>(2, _omitFieldNames ? '' : 'retrieval',
        subBuilder: RAGRetrievalOptions.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGSearchRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGSearchRequest copyWith(void Function(RAGSearchRequest) updates) =>
      super.copyWith((message) => updates(message as RAGSearchRequest))
          as RAGSearchRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGSearchRequest create() => RAGSearchRequest._();
  @$core.override
  RAGSearchRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RAGSearchRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RAGSearchRequest>(create);
  static RAGSearchRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get query => $_getSZ(0);
  @$pb.TagNumber(1)
  set query($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasQuery() => $_has(0);
  @$pb.TagNumber(1)
  void clearQuery() => $_clearField(1);

  @$pb.TagNumber(2)
  RAGRetrievalOptions get retrieval => $_getN(1);
  @$pb.TagNumber(2)
  set retrieval(RAGRetrievalOptions value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasRetrieval() => $_has(1);
  @$pb.TagNumber(2)
  void clearRetrieval() => $_clearField(2);
  @$pb.TagNumber(2)
  RAGRetrievalOptions ensureRetrieval() => $_ensure(1);
}

class RAGSearchResult extends $pb.GeneratedMessage {
  factory RAGSearchResult({
    $core.String? chunkId,
    $core.String? text,
    $core.double? score,
    $core.String? sourceDocument,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
    $core.int? startOffset,
    $core.int? endOffset,
    $core.int? tokenCount,
  }) {
    final result = create();
    if (chunkId != null) result.chunkId = chunkId;
    if (text != null) result.text = text;
    if (score != null) result.score = score;
    if (sourceDocument != null) result.sourceDocument = sourceDocument;
    if (metadata != null) result.metadata.addEntries(metadata);
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
    ..aD(3, _omitFieldNames ? '' : 'score', fieldType: $pb.PbFieldType.OF)
    ..aOS(4, _omitFieldNames ? '' : 'sourceDocument')
    ..m<$core.String, $core.String>(5, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'RAGSearchResult.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..aI(6, _omitFieldNames ? '' : 'startOffset')
    ..aI(7, _omitFieldNames ? '' : 'endOffset')
    ..aI(8, _omitFieldNames ? '' : 'tokenCount')
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

  /// Relevance, higher-is-better, normalised to 0..1. Fused dense + BM25 (RRF),
  /// not a raw cosine similarity.
  @$pb.TagNumber(3)
  $core.double get score => $_getN(2);
  @$pb.TagNumber(3)
  set score($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasScore() => $_has(2);
  @$pb.TagNumber(3)
  void clearScore() => $_clearField(3);

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

  /// Character offsets into the source document.
  @$pb.TagNumber(6)
  $core.int get startOffset => $_getIZ(5);
  @$pb.TagNumber(6)
  set startOffset($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasStartOffset() => $_has(5);
  @$pb.TagNumber(6)
  void clearStartOffset() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get endOffset => $_getIZ(6);
  @$pb.TagNumber(7)
  set endOffset($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasEndOffset() => $_has(6);
  @$pb.TagNumber(7)
  void clearEndOffset() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get tokenCount => $_getIZ(7);
  @$pb.TagNumber(8)
  set tokenCount($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasTokenCount() => $_has(7);
  @$pb.TagNumber(8)
  void clearTokenCount() => $_clearField(8);
}

/// Retrieval-only response for `rac_rag_search_proto`.
class RAGSearchResponse extends $pb.GeneratedMessage {
  factory RAGSearchResponse({
    $core.Iterable<RAGSearchResult>? chunks,
    $fixnum.Int64? retrievalTimeMs,
    $core.String? requestId,
    $0.SDKError? error,
  }) {
    final result = create();
    if (chunks != null) result.chunks.addAll(chunks);
    if (retrievalTimeMs != null) result.retrievalTimeMs = retrievalTimeMs;
    if (requestId != null) result.requestId = requestId;
    if (error != null) result.error = error;
    return result;
  }

  RAGSearchResponse._();

  factory RAGSearchResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RAGSearchResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RAGSearchResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPM<RAGSearchResult>(1, _omitFieldNames ? '' : 'chunks',
        subBuilder: RAGSearchResult.create)
    ..aInt64(2, _omitFieldNames ? '' : 'retrievalTimeMs')
    ..aOS(3, _omitFieldNames ? '' : 'requestId')
    ..aOM<$0.SDKError>(4, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGSearchResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGSearchResponse copyWith(void Function(RAGSearchResponse) updates) =>
      super.copyWith((message) => updates(message as RAGSearchResponse))
          as RAGSearchResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGSearchResponse create() => RAGSearchResponse._();
  @$core.override
  RAGSearchResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RAGSearchResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RAGSearchResponse>(create);
  static RAGSearchResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<RAGSearchResult> get chunks => $_getList(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get retrievalTimeMs => $_getI64(1);
  @$pb.TagNumber(2)
  set retrievalTimeMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRetrievalTimeMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearRetrievalTimeMs() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get requestId => $_getSZ(2);
  @$pb.TagNumber(3)
  set requestId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRequestId() => $_has(2);
  @$pb.TagNumber(3)
  void clearRequestId() => $_clearField(3);

  @$pb.TagNumber(4)
  $0.SDKError get error => $_getN(3);
  @$pb.TagNumber(4)
  set error($0.SDKError value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasError() => $_has(3);
  @$pb.TagNumber(4)
  void clearError() => $_clearField(4);
  @$pb.TagNumber(4)
  $0.SDKError ensureError() => $_ensure(3);
}

class RAGResult extends $pb.GeneratedMessage {
  factory RAGResult({
    $core.String? answer,
    $core.Iterable<RAGSearchResult>? retrievedChunks,
    $core.String? contextUsed,
    $fixnum.Int64? retrievalTimeMs,
    $fixnum.Int64? generationTimeMs,
    $core.String? requestId,
    $core.String? thinkingContent,
    $2.TokenUsage? usage,
    $0.SDKError? error,
  }) {
    final result = create();
    if (answer != null) result.answer = answer;
    if (retrievedChunks != null) result.retrievedChunks.addAll(retrievedChunks);
    if (contextUsed != null) result.contextUsed = contextUsed;
    if (retrievalTimeMs != null) result.retrievalTimeMs = retrievalTimeMs;
    if (generationTimeMs != null) result.generationTimeMs = generationTimeMs;
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
    ..aOS(6, _omitFieldNames ? '' : 'requestId')
    ..aOS(7, _omitFieldNames ? '' : 'thinkingContent')
    ..aOM<$2.TokenUsage>(8, _omitFieldNames ? '' : 'usage',
        subBuilder: $2.TokenUsage.create)
    ..aOM<$0.SDKError>(9, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
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

  /// Measured directly, not by subtraction: embed the query + search + fuse.
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

  /// MUST be set by rac_rag_proto_abi (event_id()).
  @$pb.TagNumber(6)
  $core.String get requestId => $_getSZ(5);
  @$pb.TagNumber(6)
  set requestId($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasRequestId() => $_has(5);
  @$pb.TagNumber(6)
  void clearRequestId() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get thinkingContent => $_getSZ(6);
  @$pb.TagNumber(7)
  set thinkingContent($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasThinkingContent() => $_has(6);
  @$pb.TagNumber(7)
  void clearThinkingContent() => $_clearField(7);

  /// MUST be copied from the LLM result the pipeline already holds.
  @$pb.TagNumber(8)
  $2.TokenUsage get usage => $_getN(7);
  @$pb.TagNumber(8)
  set usage($2.TokenUsage value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasUsage() => $_has(7);
  @$pb.TagNumber(8)
  void clearUsage() => $_clearField(8);
  @$pb.TagNumber(8)
  $2.TokenUsage ensureUsage() => $_ensure(7);

  @$pb.TagNumber(9)
  $0.SDKError get error => $_getN(8);
  @$pb.TagNumber(9)
  set error($0.SDKError value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasError() => $_has(8);
  @$pb.TagNumber(9)
  void clearError() => $_clearField(9);
  @$pb.TagNumber(9)
  $0.SDKError ensureError() => $_ensure(8);
}

class RAGStatistics extends $pb.GeneratedMessage {
  factory RAGStatistics({
    $fixnum.Int64? indexedDocuments,
    $fixnum.Int64? indexedChunks,
    $fixnum.Int64? totalTokensIndexed,
    $fixnum.Int64? lastUpdatedMs,
    $fixnum.Int64? vectorStoreSizeBytes,
    $0.SDKError? error,
  }) {
    final result = create();
    if (indexedDocuments != null) result.indexedDocuments = indexedDocuments;
    if (indexedChunks != null) result.indexedChunks = indexedChunks;
    if (totalTokensIndexed != null)
      result.totalTokensIndexed = totalTokensIndexed;
    if (lastUpdatedMs != null) result.lastUpdatedMs = lastUpdatedMs;
    if (vectorStoreSizeBytes != null)
      result.vectorStoreSizeBytes = vectorStoreSizeBytes;
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
    ..aInt64(5, _omitFieldNames ? '' : 'vectorStoreSizeBytes')
    ..aOM<$0.SDKError>(6, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
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

  /// Milliseconds since the Unix epoch when the index last changed.
  @$pb.TagNumber(4)
  $fixnum.Int64 get lastUpdatedMs => $_getI64(3);
  @$pb.TagNumber(4)
  set lastUpdatedMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLastUpdatedMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearLastUpdatedMs() => $_clearField(4);

  /// Bytes the index occupies (industry: VectorStore.usage_bytes).
  /// MUST be populated by make_stats() — it is surfaced as RagStats.indexSizeBytes.
  @$pb.TagNumber(5)
  $fixnum.Int64 get vectorStoreSizeBytes => $_getI64(4);
  @$pb.TagNumber(5)
  set vectorStoreSizeBytes($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasVectorStoreSizeBytes() => $_has(4);
  @$pb.TagNumber(5)
  void clearVectorStoreSizeBytes() => $_clearField(5);

  @$pb.TagNumber(6)
  $0.SDKError get error => $_getN(5);
  @$pb.TagNumber(6)
  set error($0.SDKError value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(6)
  void clearError() => $_clearField(6);
  @$pb.TagNumber(6)
  $0.SDKError ensureError() => $_ensure(5);
}

class RAGStreamEvent extends $pb.GeneratedMessage {
  factory RAGStreamEvent({
    $fixnum.Int64? timestampUs,
    $core.String? requestId,
    RAGStreamEventKind? kind,
    $core.String? token,
    RAGResult? result,
    $0.SDKError? error,
  }) {
    final result$ = create();
    if (timestampUs != null) result$.timestampUs = timestampUs;
    if (requestId != null) result$.requestId = requestId;
    if (kind != null) result$.kind = kind;
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
    ..aInt64(1, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(2, _omitFieldNames ? '' : 'requestId')
    ..aE<RAGStreamEventKind>(3, _omitFieldNames ? '' : 'kind',
        enumValues: RAGStreamEventKind.values)
    ..aOS(4, _omitFieldNames ? '' : 'token')
    ..aOM<RAGResult>(5, _omitFieldNames ? '' : 'result',
        subBuilder: RAGResult.create)
    ..aOM<$0.SDKError>(6, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
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

  /// Microseconds since the Unix epoch, matching every other modality.
  @$pb.TagNumber(1)
  $fixnum.Int64 get timestampUs => $_getI64(0);
  @$pb.TagNumber(1)
  set timestampUs($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTimestampUs() => $_has(0);
  @$pb.TagNumber(1)
  void clearTimestampUs() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get requestId => $_getSZ(1);
  @$pb.TagNumber(2)
  set requestId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRequestId() => $_has(1);
  @$pb.TagNumber(2)
  void clearRequestId() => $_clearField(2);

  @$pb.TagNumber(3)
  RAGStreamEventKind get kind => $_getN(2);
  @$pb.TagNumber(3)
  set kind(RAGStreamEventKind value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasKind() => $_has(2);
  @$pb.TagNumber(3)
  void clearKind() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get token => $_getSZ(3);
  @$pb.TagNumber(4)
  set token($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasToken() => $_has(3);
  @$pb.TagNumber(4)
  void clearToken() => $_clearField(4);

  @$pb.TagNumber(5)
  RAGResult get result => $_getN(4);
  @$pb.TagNumber(5)
  set result(RAGResult value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasResult() => $_has(4);
  @$pb.TagNumber(5)
  void clearResult() => $_clearField(5);
  @$pb.TagNumber(5)
  RAGResult ensureResult() => $_ensure(4);

  @$pb.TagNumber(6)
  $0.SDKError get error => $_getN(5);
  @$pb.TagNumber(6)
  set error($0.SDKError value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(6)
  void clearError() => $_clearField(6);
  @$pb.TagNumber(6)
  $0.SDKError ensureError() => $_ensure(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
