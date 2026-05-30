// This is a generated file - do not edit.
//
// Generated from rag.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'rag.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'rag.pbenum.dart';

/// ---------------------------------------------------------------------------
/// RAGConfiguration — low-level pipeline config.
///
/// This message carries *model ids*, not filesystem paths.
/// The commons RAG session ABI (rac_rag_session_create_proto) is responsible
/// for resolving those ids to on-disk paths through the canonical model
/// registry. SDK callers MUST register the embedding / LLM / reranker models
/// first and pass only their ids here.
/// ---------------------------------------------------------------------------
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

  /// Registered id of the embedding model (required, e.g. "bge-small-en-v1.5").
  /// Commons resolves this to the primary artifact path via the model registry.
  @$pb.TagNumber(1)
  $core.String get embeddingModelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set embeddingModelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEmbeddingModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearEmbeddingModelId() => $_clearField(1);

  /// Registered id of the LLM model (e.g. "qwen3-4b-q4_k_m"). Optional —
  /// leave empty to create an embed-only / retrieval-only pipeline.
  @$pb.TagNumber(2)
  $core.String get llmModelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set llmModelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLlmModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearLlmModelId() => $_clearField(2);

  /// Embedding vector dimension — must match the embedding model.
  /// Common: 384 (all-MiniLM-L6-v2), 768 (bge-base), 1024 (bge-large).
  /// Optional so callers can distinguish "unset" (commons stamps the
  /// canonical default) from explicit zero / explicit override.
  @$pb.TagNumber(3)
  $core.int get embeddingDimension => $_getIZ(2);
  @$pb.TagNumber(3)
  set embeddingDimension($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEmbeddingDimension() => $_has(2);
  @$pb.TagNumber(3)
  void clearEmbeddingDimension() => $_clearField(3);

  /// Number of top chunks to retrieve per query.
  /// Optional so callers can distinguish "unset" from an explicit value.
  @$pb.TagNumber(4)
  $core.int get topK => $_getIZ(3);
  @$pb.TagNumber(4)
  set topK($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTopK() => $_has(3);
  @$pb.TagNumber(4)
  void clearTopK() => $_clearField(4);

  /// Minimum cosine similarity threshold (0.0–1.0). Chunks below this
  /// score are discarded before being passed to the LLM as context.
  /// Optional so callers can distinguish "unset" from explicit 0.0
  /// (accept-everything) without losing the canonical default.
  @$pb.TagNumber(5)
  $core.double get similarityThreshold => $_getN(4);
  @$pb.TagNumber(5)
  set similarityThreshold($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSimilarityThreshold() => $_has(4);
  @$pb.TagNumber(5)
  void clearSimilarityThreshold() => $_clearField(5);

  /// Tokens per chunk when splitting documents during ingestion.
  /// Optional so callers can distinguish "unset" from an explicit value.
  @$pb.TagNumber(6)
  $core.int get chunkSize => $_getIZ(5);
  @$pb.TagNumber(6)
  set chunkSize($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasChunkSize() => $_has(5);
  @$pb.TagNumber(6)
  void clearChunkSize() => $_clearField(6);

  /// Overlap tokens between consecutive chunks. Must be < chunk_size.
  /// Optional so callers can explicitly request zero overlap (no overlap)
  /// without it being silently replaced by the canonical default of 64.
  @$pb.TagNumber(7)
  $core.int get chunkOverlap => $_getIZ(6);
  @$pb.TagNumber(7)
  set chunkOverlap($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasChunkOverlap() => $_has(6);
  @$pb.TagNumber(7)
  void clearChunkOverlap() => $_clearField(7);

  /// Maximum tokens of retrieved context passed to the LLM.
  /// Optional so callers can distinguish "unset" from an explicit value.
  @$pb.TagNumber(8)
  $core.int get maxContextTokens => $_getIZ(7);
  @$pb.TagNumber(8)
  set maxContextTokens($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasMaxContextTokens() => $_has(7);
  @$pb.TagNumber(8)
  void clearMaxContextTokens() => $_clearField(8);

  /// Prompt template with `{context}` and `{query}` placeholders.
  @$pb.TagNumber(9)
  $core.String get promptTemplate => $_getSZ(8);
  @$pb.TagNumber(9)
  set promptTemplate($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasPromptTemplate() => $_has(8);
  @$pb.TagNumber(9)
  void clearPromptTemplate() => $_clearField(9);

  /// Backend-specific config JSON passed to the embedding model/provider.
  @$pb.TagNumber(10)
  $core.String get embeddingConfigJson => $_getSZ(9);
  @$pb.TagNumber(10)
  set embeddingConfigJson($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasEmbeddingConfigJson() => $_has(9);
  @$pb.TagNumber(10)
  void clearEmbeddingConfigJson() => $_clearField(10);

  /// Backend-specific config JSON passed to the LLM provider.
  @$pb.TagNumber(11)
  $core.String get llmConfigJson => $_getSZ(10);
  @$pb.TagNumber(11)
  set llmConfigJson($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasLlmConfigJson() => $_has(10);
  @$pb.TagNumber(11)
  void clearLlmConfigJson() => $_clearField(11);

  /// Index persistence and retrieval behavior. Empty path = in-memory index.
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

  /// Registered id of the reranker model (optional).
  @$pb.TagNumber(15)
  $core.String get rerankerModelId => $_getSZ(14);
  @$pb.TagNumber(15)
  set rerankerModelId($core.String value) => $_setString(14, value);
  @$pb.TagNumber(15)
  $core.bool hasRerankerModelId() => $_has(14);
  @$pb.TagNumber(15)
  void clearRerankerModelId() => $_clearField(15);
}

/// ---------------------------------------------------------------------------
/// RAGDocument — batch-ingest input item.
/// ---------------------------------------------------------------------------
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

  /// Optional caller-supplied document id.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  /// Plain text content to chunk/embed.
  @$pb.TagNumber(2)
  $core.String get text => $_getSZ(1);
  @$pb.TagNumber(2)
  set text($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => $_clearField(2);

  /// Typed metadata map for generated-proto callers.
  @$pb.TagNumber(4)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(2);

  /// Adapter-normalized document source. Pickers, sandbox bookmarks, and
  /// platform file access remain SDK-owned.
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

class RAGIngestRequest extends $pb.GeneratedMessage {
  factory RAGIngestRequest({
    $core.String? requestId,
    $core.Iterable<RAGDocument>? documents,
    $core.bool? replaceExisting,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (documents != null) result.documents.addAll(documents);
    if (replaceExisting != null) result.replaceExisting = replaceExisting;
    if (metadata != null) result.metadata.addEntries(metadata);
    return result;
  }

  RAGIngestRequest._();

  factory RAGIngestRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RAGIngestRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RAGIngestRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..pPM<RAGDocument>(2, _omitFieldNames ? '' : 'documents',
        subBuilder: RAGDocument.create)
    ..aOB(3, _omitFieldNames ? '' : 'replaceExisting')
    ..m<$core.String, $core.String>(4, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'RAGIngestRequest.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGIngestRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGIngestRequest copyWith(void Function(RAGIngestRequest) updates) =>
      super.copyWith((message) => updates(message as RAGIngestRequest))
          as RAGIngestRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGIngestRequest create() => RAGIngestRequest._();
  @$core.override
  RAGIngestRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RAGIngestRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RAGIngestRequest>(create);
  static RAGIngestRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<RAGDocument> get documents => $_getList(1);

  @$pb.TagNumber(3)
  $core.bool get replaceExisting => $_getBF(2);
  @$pb.TagNumber(3)
  set replaceExisting($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasReplaceExisting() => $_has(2);
  @$pb.TagNumber(3)
  void clearReplaceExisting() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(3);
}

/// ---------------------------------------------------------------------------
/// RAGQueryOptions — per-query sampling and prompt overrides.
/// ---------------------------------------------------------------------------
class RAGQueryOptions extends $pb.GeneratedMessage {
  factory RAGQueryOptions({
    $core.String? question,
    $core.String? systemPrompt,
    $core.int? maxTokens,
    $core.double? temperature,
    $core.double? topP,
    $core.int? topK,
    $core.int? retrievalTopK,
    $core.double? similarityThreshold,
    $core.bool? stream,
  }) {
    final result = create();
    if (question != null) result.question = question;
    if (systemPrompt != null) result.systemPrompt = systemPrompt;
    if (maxTokens != null) result.maxTokens = maxTokens;
    if (temperature != null) result.temperature = temperature;
    if (topP != null) result.topP = topP;
    if (topK != null) result.topK = topK;
    if (retrievalTopK != null) result.retrievalTopK = retrievalTopK;
    if (similarityThreshold != null)
      result.similarityThreshold = similarityThreshold;
    if (stream != null) result.stream = stream;
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
    ..aOS(2, _omitFieldNames ? '' : 'systemPrompt')
    ..aI(3, _omitFieldNames ? '' : 'maxTokens')
    ..aD(4, _omitFieldNames ? '' : 'temperature', fieldType: $pb.PbFieldType.OF)
    ..aD(5, _omitFieldNames ? '' : 'topP', fieldType: $pb.PbFieldType.OF)
    ..aI(6, _omitFieldNames ? '' : 'topK')
    ..aI(7, _omitFieldNames ? '' : 'retrievalTopK')
    ..aD(8, _omitFieldNames ? '' : 'similarityThreshold',
        fieldType: $pb.PbFieldType.OF)
    ..aOB(9, _omitFieldNames ? '' : 'stream')
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

  /// The user question to answer. Required (empty = no-op).
  @$pb.TagNumber(1)
  $core.String get question => $_getSZ(0);
  @$pb.TagNumber(1)
  set question($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasQuestion() => $_has(0);
  @$pb.TagNumber(1)
  void clearQuestion() => $_clearField(1);

  /// Optional system prompt override. Unset uses the pipeline default.
  @$pb.TagNumber(2)
  $core.String get systemPrompt => $_getSZ(1);
  @$pb.TagNumber(2)
  set systemPrompt($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSystemPrompt() => $_has(1);
  @$pb.TagNumber(2)
  void clearSystemPrompt() => $_clearField(2);

  /// Maximum tokens to generate in the answer.
  @$pb.TagNumber(3)
  $core.int get maxTokens => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxTokens($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMaxTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxTokens() => $_clearField(3);

  /// Sampling temperature. 0.0 = greedy, higher = more random.
  @$pb.TagNumber(4)
  $core.double get temperature => $_getN(3);
  @$pb.TagNumber(4)
  set temperature($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTemperature() => $_has(3);
  @$pb.TagNumber(4)
  void clearTemperature() => $_clearField(4);

  /// Nucleus (top-p) sampling parameter. 1.0 = disabled.
  @$pb.TagNumber(5)
  $core.double get topP => $_getN(4);
  @$pb.TagNumber(5)
  set topP($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTopP() => $_has(4);
  @$pb.TagNumber(5)
  void clearTopP() => $_clearField(5);

  /// Top-k sampling parameter. 0 = disabled.
  @$pb.TagNumber(6)
  $core.int get topK => $_getIZ(5);
  @$pb.TagNumber(6)
  set topK($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTopK() => $_has(5);
  @$pb.TagNumber(6)
  void clearTopK() => $_clearField(6);

  /// Retrieval overrides. 0/unset = use RAGConfiguration defaults.
  @$pb.TagNumber(7)
  $core.int get retrievalTopK => $_getIZ(6);
  @$pb.TagNumber(7)
  set retrievalTopK($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasRetrievalTopK() => $_has(6);
  @$pb.TagNumber(7)
  void clearRetrievalTopK() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.double get similarityThreshold => $_getN(7);
  @$pb.TagNumber(8)
  set similarityThreshold($core.double value) => $_setFloat(7, value);
  @$pb.TagNumber(8)
  $core.bool hasSimilarityThreshold() => $_has(7);
  @$pb.TagNumber(8)
  void clearSimilarityThreshold() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.bool get stream => $_getBF(8);
  @$pb.TagNumber(9)
  set stream($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasStream() => $_has(8);
  @$pb.TagNumber(9)
  void clearStream() => $_clearField(9);
}

class RAGQueryRequest extends $pb.GeneratedMessage {
  factory RAGQueryRequest({
    $core.String? requestId,
    RAGQueryOptions? options,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (options != null) result.options = options;
    if (metadata != null) result.metadata.addEntries(metadata);
    return result;
  }

  RAGQueryRequest._();

  factory RAGQueryRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RAGQueryRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RAGQueryRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOM<RAGQueryOptions>(2, _omitFieldNames ? '' : 'options',
        subBuilder: RAGQueryOptions.create)
    ..m<$core.String, $core.String>(3, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'RAGQueryRequest.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGQueryRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGQueryRequest copyWith(void Function(RAGQueryRequest) updates) =>
      super.copyWith((message) => updates(message as RAGQueryRequest))
          as RAGQueryRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGQueryRequest create() => RAGQueryRequest._();
  @$core.override
  RAGQueryRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RAGQueryRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RAGQueryRequest>(create);
  static RAGQueryRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  RAGQueryOptions get options => $_getN(1);
  @$pb.TagNumber(2)
  set options(RAGQueryOptions value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasOptions() => $_has(1);
  @$pb.TagNumber(2)
  void clearOptions() => $_clearField(2);
  @$pb.TagNumber(2)
  RAGQueryOptions ensureOptions() => $_ensure(1);

  @$pb.TagNumber(3)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(2);
}

/// ---------------------------------------------------------------------------
/// RAGSearchResult — a single retrieved document chunk with similarity score.
/// ---------------------------------------------------------------------------
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

  /// Unique identifier of the chunk (assigned at ingestion time).
  @$pb.TagNumber(1)
  $core.String get chunkId => $_getSZ(0);
  @$pb.TagNumber(1)
  set chunkId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChunkId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChunkId() => $_clearField(1);

  /// Text content of the chunk (the actual snippet shown to the LLM).
  @$pb.TagNumber(2)
  $core.String get text => $_getSZ(1);
  @$pb.TagNumber(2)
  set text($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => $_clearField(2);

  /// Cosine similarity score (0.0–1.0). Higher = more relevant.
  @$pb.TagNumber(3)
  $core.double get similarityScore => $_getN(2);
  @$pb.TagNumber(3)
  set similarityScore($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSimilarityScore() => $_has(2);
  @$pb.TagNumber(3)
  void clearSimilarityScore() => $_clearField(3);

  /// Optional source document identifier (filename, URL, or document ID).
  /// Set when the chunk's origin is tracked at ingestion time.
  @$pb.TagNumber(4)
  $core.String get sourceDocument => $_getSZ(3);
  @$pb.TagNumber(4)
  set sourceDocument($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSourceDocument() => $_has(3);
  @$pb.TagNumber(4)
  void clearSourceDocument() => $_clearField(4);

  /// Free-form metadata associated with the chunk (e.g. page number, section,
  /// ingestion timestamp). Pre-IDL all SDKs encoded this as a JSON string;
  /// canonicalized here as a typed map so consumers don't re-parse.
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

/// ---------------------------------------------------------------------------
/// RAGResult — the full result of a RAG query.
/// ---------------------------------------------------------------------------
class RAGResult extends $pb.GeneratedMessage {
  factory RAGResult({
    $core.String? answer,
    $core.Iterable<RAGSearchResult>? retrievedChunks,
    $core.String? contextUsed,
    $fixnum.Int64? retrievalTimeMs,
    $fixnum.Int64? generationTimeMs,
    $fixnum.Int64? totalTimeMs,
    $core.int? promptTokens,
    $core.int? completionTokens,
    $core.int? totalTokens,
    $core.String? errorMessage,
    $core.int? errorCode,
    $core.String? requestId,
  }) {
    final result = create();
    if (answer != null) result.answer = answer;
    if (retrievedChunks != null) result.retrievedChunks.addAll(retrievedChunks);
    if (contextUsed != null) result.contextUsed = contextUsed;
    if (retrievalTimeMs != null) result.retrievalTimeMs = retrievalTimeMs;
    if (generationTimeMs != null) result.generationTimeMs = generationTimeMs;
    if (totalTimeMs != null) result.totalTimeMs = totalTimeMs;
    if (promptTokens != null) result.promptTokens = promptTokens;
    if (completionTokens != null) result.completionTokens = completionTokens;
    if (totalTokens != null) result.totalTokens = totalTokens;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    if (requestId != null) result.requestId = requestId;
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
    ..aI(7, _omitFieldNames ? '' : 'promptTokens')
    ..aI(8, _omitFieldNames ? '' : 'completionTokens')
    ..aI(9, _omitFieldNames ? '' : 'totalTokens')
    ..aOS(10, _omitFieldNames ? '' : 'errorMessage')
    ..aI(11, _omitFieldNames ? '' : 'errorCode')
    ..aOS(12, _omitFieldNames ? '' : 'requestId')
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

  /// The LLM-generated answer grounded in the retrieved context.
  @$pb.TagNumber(1)
  $core.String get answer => $_getSZ(0);
  @$pb.TagNumber(1)
  set answer($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAnswer() => $_has(0);
  @$pb.TagNumber(1)
  void clearAnswer() => $_clearField(1);

  /// Document chunks retrieved during vector search and used as context.
  /// Order matches retrieval rank (highest similarity first).
  @$pb.TagNumber(2)
  $pb.PbList<RAGSearchResult> get retrievedChunks => $_getList(1);

  /// Full context string passed to the LLM (chunks joined into a prompt).
  /// May be empty for queries with no matching chunks.
  @$pb.TagNumber(3)
  $core.String get contextUsed => $_getSZ(2);
  @$pb.TagNumber(3)
  set contextUsed($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasContextUsed() => $_has(2);
  @$pb.TagNumber(3)
  void clearContextUsed() => $_clearField(3);

  /// Time spent in the retrieval phase (vector search), in milliseconds.
  @$pb.TagNumber(4)
  $fixnum.Int64 get retrievalTimeMs => $_getI64(3);
  @$pb.TagNumber(4)
  set retrievalTimeMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRetrievalTimeMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearRetrievalTimeMs() => $_clearField(4);

  /// Time spent in the LLM generation phase, in milliseconds.
  @$pb.TagNumber(5)
  $fixnum.Int64 get generationTimeMs => $_getI64(4);
  @$pb.TagNumber(5)
  set generationTimeMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasGenerationTimeMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearGenerationTimeMs() => $_clearField(5);

  /// Total end-to-end query time (retrieval + generation + overhead),
  /// in milliseconds.
  @$pb.TagNumber(6)
  $fixnum.Int64 get totalTimeMs => $_getI64(5);
  @$pb.TagNumber(6)
  set totalTimeMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTotalTimeMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearTotalTimeMs() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get promptTokens => $_getIZ(6);
  @$pb.TagNumber(7)
  set promptTokens($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasPromptTokens() => $_has(6);
  @$pb.TagNumber(7)
  void clearPromptTokens() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get completionTokens => $_getIZ(7);
  @$pb.TagNumber(8)
  set completionTokens($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasCompletionTokens() => $_has(7);
  @$pb.TagNumber(8)
  void clearCompletionTokens() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get totalTokens => $_getIZ(8);
  @$pb.TagNumber(9)
  set totalTokens($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasTotalTokens() => $_has(8);
  @$pb.TagNumber(9)
  void clearTotalTokens() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get errorMessage => $_getSZ(9);
  @$pb.TagNumber(10)
  set errorMessage($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasErrorMessage() => $_has(9);
  @$pb.TagNumber(10)
  void clearErrorMessage() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.int get errorCode => $_getIZ(10);
  @$pb.TagNumber(11)
  set errorCode($core.int value) => $_setSignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasErrorCode() => $_has(10);
  @$pb.TagNumber(11)
  void clearErrorCode() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get requestId => $_getSZ(11);
  @$pb.TagNumber(12)
  set requestId($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasRequestId() => $_has(11);
  @$pb.TagNumber(12)
  void clearRequestId() => $_clearField(12);
}

/// ---------------------------------------------------------------------------
/// RAGStatistics — index-level counters for the RAG pipeline.
///
/// Returned by RunAnywhere.rag.statistics() / ragGetStatistics().
/// ---------------------------------------------------------------------------
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
    $core.String? errorMessage,
    $core.int? errorCode,
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
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
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
    ..aOS(10, _omitFieldNames ? '' : 'errorMessage')
    ..aI(11, _omitFieldNames ? '' : 'errorCode')
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

  /// Total number of documents ever ingested into the index.
  @$pb.TagNumber(1)
  $fixnum.Int64 get indexedDocuments => $_getI64(0);
  @$pb.TagNumber(1)
  set indexedDocuments($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIndexedDocuments() => $_has(0);
  @$pb.TagNumber(1)
  void clearIndexedDocuments() => $_clearField(1);

  /// Total number of chunks across all indexed documents.
  @$pb.TagNumber(2)
  $fixnum.Int64 get indexedChunks => $_getI64(1);
  @$pb.TagNumber(2)
  set indexedChunks($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIndexedChunks() => $_has(1);
  @$pb.TagNumber(2)
  void clearIndexedChunks() => $_clearField(2);

  /// Approximate total token count across all indexed chunks.
  @$pb.TagNumber(3)
  $fixnum.Int64 get totalTokensIndexed => $_getI64(2);
  @$pb.TagNumber(3)
  set totalTokensIndexed($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTotalTokensIndexed() => $_has(2);
  @$pb.TagNumber(3)
  void clearTotalTokensIndexed() => $_clearField(3);

  /// Wall-clock timestamp of the most recent ingestion, in milliseconds
  /// since Unix epoch. 0 = no ingestion yet.
  @$pb.TagNumber(4)
  $fixnum.Int64 get lastUpdatedMs => $_getI64(3);
  @$pb.TagNumber(4)
  set lastUpdatedMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLastUpdatedMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearLastUpdatedMs() => $_clearField(4);

  /// Filesystem path to the on-disk index, when applicable. Unset for
  /// in-memory-only indexes.
  @$pb.TagNumber(5)
  $core.String get indexPath => $_getSZ(4);
  @$pb.TagNumber(5)
  set indexPath($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasIndexPath() => $_has(4);
  @$pb.TagNumber(5)
  void clearIndexPath() => $_clearField(5);

  /// Raw backend statistics JSON for implementations that cannot yet project
  /// every counter into typed fields.
  @$pb.TagNumber(6)
  $core.String get statsJson => $_getSZ(5);
  @$pb.TagNumber(6)
  set statsJson($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasStatsJson() => $_has(5);
  @$pb.TagNumber(6)
  void clearStatsJson() => $_clearField(6);

  /// Approximate vector-store footprint in bytes, when known.
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

  @$pb.TagNumber(10)
  $core.String get errorMessage => $_getSZ(9);
  @$pb.TagNumber(10)
  set errorMessage($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasErrorMessage() => $_has(9);
  @$pb.TagNumber(10)
  void clearErrorMessage() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.int get errorCode => $_getIZ(10);
  @$pb.TagNumber(11)
  set errorCode($core.int value) => $_setSignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasErrorCode() => $_has(10);
  @$pb.TagNumber(11)
  void clearErrorCode() => $_clearField(11);
}

class RAGIngestResult extends $pb.GeneratedMessage {
  factory RAGIngestResult({
    $core.String? requestId,
    $fixnum.Int64? documentsIngested,
    $fixnum.Int64? chunksIngested,
    RAGStatistics? statistics,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (documentsIngested != null) result.documentsIngested = documentsIngested;
    if (chunksIngested != null) result.chunksIngested = chunksIngested;
    if (statistics != null) result.statistics = statistics;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    return result;
  }

  RAGIngestResult._();

  factory RAGIngestResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RAGIngestResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RAGIngestResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aInt64(2, _omitFieldNames ? '' : 'documentsIngested')
    ..aInt64(3, _omitFieldNames ? '' : 'chunksIngested')
    ..aOM<RAGStatistics>(4, _omitFieldNames ? '' : 'statistics',
        subBuilder: RAGStatistics.create)
    ..aOS(5, _omitFieldNames ? '' : 'errorMessage')
    ..aI(6, _omitFieldNames ? '' : 'errorCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGIngestResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGIngestResult copyWith(void Function(RAGIngestResult) updates) =>
      super.copyWith((message) => updates(message as RAGIngestResult))
          as RAGIngestResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGIngestResult create() => RAGIngestResult._();
  @$core.override
  RAGIngestResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RAGIngestResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RAGIngestResult>(create);
  static RAGIngestResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get documentsIngested => $_getI64(1);
  @$pb.TagNumber(2)
  set documentsIngested($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDocumentsIngested() => $_has(1);
  @$pb.TagNumber(2)
  void clearDocumentsIngested() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get chunksIngested => $_getI64(2);
  @$pb.TagNumber(3)
  set chunksIngested($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasChunksIngested() => $_has(2);
  @$pb.TagNumber(3)
  void clearChunksIngested() => $_clearField(3);

  @$pb.TagNumber(4)
  RAGStatistics get statistics => $_getN(3);
  @$pb.TagNumber(4)
  set statistics(RAGStatistics value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasStatistics() => $_has(3);
  @$pb.TagNumber(4)
  void clearStatistics() => $_clearField(4);
  @$pb.TagNumber(4)
  RAGStatistics ensureStatistics() => $_ensure(3);

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

class RAGStreamEvent extends $pb.GeneratedMessage {
  factory RAGStreamEvent({
    $fixnum.Int64? seq,
    $fixnum.Int64? timestampUs,
    $core.String? requestId,
    RAGStreamEventKind? kind,
    RAGSearchResult? chunk,
    $core.String? token,
    RAGResult? result,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final result$ = create();
    if (seq != null) result$.seq = seq;
    if (timestampUs != null) result$.timestampUs = timestampUs;
    if (requestId != null) result$.requestId = requestId;
    if (kind != null) result$.kind = kind;
    if (chunk != null) result$.chunk = chunk;
    if (token != null) result$.token = token;
    if (result != null) result$.result = result;
    if (errorMessage != null) result$.errorMessage = errorMessage;
    if (errorCode != null) result$.errorCode = errorCode;
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
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(3, _omitFieldNames ? '' : 'requestId')
    ..aE<RAGStreamEventKind>(4, _omitFieldNames ? '' : 'kind',
        enumValues: RAGStreamEventKind.values)
    ..aOM<RAGSearchResult>(5, _omitFieldNames ? '' : 'chunk',
        subBuilder: RAGSearchResult.create)
    ..aOS(6, _omitFieldNames ? '' : 'token')
    ..aOM<RAGResult>(7, _omitFieldNames ? '' : 'result',
        subBuilder: RAGResult.create)
    ..aOS(8, _omitFieldNames ? '' : 'errorMessage')
    ..aI(9, _omitFieldNames ? '' : 'errorCode')
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
  RAGStreamEventKind get kind => $_getN(3);
  @$pb.TagNumber(4)
  set kind(RAGStreamEventKind value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasKind() => $_has(3);
  @$pb.TagNumber(4)
  void clearKind() => $_clearField(4);

  @$pb.TagNumber(5)
  RAGSearchResult get chunk => $_getN(4);
  @$pb.TagNumber(5)
  set chunk(RAGSearchResult value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasChunk() => $_has(4);
  @$pb.TagNumber(5)
  void clearChunk() => $_clearField(5);
  @$pb.TagNumber(5)
  RAGSearchResult ensureChunk() => $_ensure(4);

  @$pb.TagNumber(6)
  $core.String get token => $_getSZ(5);
  @$pb.TagNumber(6)
  set token($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasToken() => $_has(5);
  @$pb.TagNumber(6)
  void clearToken() => $_clearField(6);

  @$pb.TagNumber(7)
  RAGResult get result => $_getN(6);
  @$pb.TagNumber(7)
  set result(RAGResult value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasResult() => $_has(6);
  @$pb.TagNumber(7)
  void clearResult() => $_clearField(7);
  @$pb.TagNumber(7)
  RAGResult ensureResult() => $_ensure(6);

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
}

class RAGServiceState extends $pb.GeneratedMessage {
  factory RAGServiceState({
    $core.bool? isReady,
    RAGStatistics? statistics,
    $core.bool? isIndexing,
    $core.bool? isQuerying,
    $core.String? activeRequestId,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final result = create();
    if (isReady != null) result.isReady = isReady;
    if (statistics != null) result.statistics = statistics;
    if (isIndexing != null) result.isIndexing = isIndexing;
    if (isQuerying != null) result.isQuerying = isQuerying;
    if (activeRequestId != null) result.activeRequestId = activeRequestId;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    return result;
  }

  RAGServiceState._();

  factory RAGServiceState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RAGServiceState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RAGServiceState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isReady')
    ..aOM<RAGStatistics>(2, _omitFieldNames ? '' : 'statistics',
        subBuilder: RAGStatistics.create)
    ..aOB(3, _omitFieldNames ? '' : 'isIndexing')
    ..aOB(4, _omitFieldNames ? '' : 'isQuerying')
    ..aOS(5, _omitFieldNames ? '' : 'activeRequestId')
    ..aOS(6, _omitFieldNames ? '' : 'errorMessage')
    ..aI(7, _omitFieldNames ? '' : 'errorCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGServiceState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGServiceState copyWith(void Function(RAGServiceState) updates) =>
      super.copyWith((message) => updates(message as RAGServiceState))
          as RAGServiceState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGServiceState create() => RAGServiceState._();
  @$core.override
  RAGServiceState createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RAGServiceState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RAGServiceState>(create);
  static RAGServiceState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get isReady => $_getBF(0);
  @$pb.TagNumber(1)
  set isReady($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIsReady() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsReady() => $_clearField(1);

  @$pb.TagNumber(2)
  RAGStatistics get statistics => $_getN(1);
  @$pb.TagNumber(2)
  set statistics(RAGStatistics value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasStatistics() => $_has(1);
  @$pb.TagNumber(2)
  void clearStatistics() => $_clearField(2);
  @$pb.TagNumber(2)
  RAGStatistics ensureStatistics() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.bool get isIndexing => $_getBF(2);
  @$pb.TagNumber(3)
  set isIndexing($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIsIndexing() => $_has(2);
  @$pb.TagNumber(3)
  void clearIsIndexing() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get isQuerying => $_getBF(3);
  @$pb.TagNumber(4)
  set isQuerying($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasIsQuerying() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsQuerying() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get activeRequestId => $_getSZ(4);
  @$pb.TagNumber(5)
  set activeRequestId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasActiveRequestId() => $_has(4);
  @$pb.TagNumber(5)
  void clearActiveRequestId() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get errorMessage => $_getSZ(5);
  @$pb.TagNumber(6)
  set errorMessage($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasErrorMessage() => $_has(5);
  @$pb.TagNumber(6)
  void clearErrorMessage() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get errorCode => $_getIZ(6);
  @$pb.TagNumber(7)
  set errorCode($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasErrorCode() => $_has(6);
  @$pb.TagNumber(7)
  void clearErrorCode() => $_clearField(7);
}

/// Logical RAG service contract. Native file pickers, sandbox handles, browser
/// File System Access handles, and backend execution remain adapter-owned; C++
/// consumes only serialized configuration/request/result/state/event messages.
class RAGApi {
  final $pb.RpcClient _client;

  RAGApi(this._client);

  /// Create or reconfigure the logical RAG session from registered model ids
  /// and index settings. Commons resolves model ids → on-disk paths via the
  /// global model registry; SDK callers MUST register their embedding /
  /// LLM / reranker models before invoking Create.
  $async.Future<RAGServiceState> create_(
          $pb.ClientContext? ctx, RAGConfiguration request) =>
      _client.invoke<RAGServiceState>(
          ctx, 'RAG', 'Create', request, RAGServiceState());

  /// Ingest caller-provided documents into the current logical index.
  $async.Future<RAGIngestResult> ingest(
          $pb.ClientContext? ctx, RAGIngestRequest request) =>
      _client.invoke<RAGIngestResult>(
          ctx, 'RAG', 'Ingest', request, RAGIngestResult());

  /// Retrieval-augmented generation returning grounded answer text, chunks,
  /// and timing/token metrics.
  $async.Future<RAGResult> query(
          $pb.ClientContext? ctx, RAGQueryRequest request) =>
      _client.invoke<RAGResult>(ctx, 'RAG', 'Query', request, RAGResult());

  /// Retrieval-only search. The returned RAGResult carries retrieved_chunks and
  /// request/timing fields; answer/context fields may be empty.
  $async.Future<RAGResult> search(
          $pb.ClientContext? ctx, RAGQueryRequest request) =>
      _client.invoke<RAGResult>(ctx, 'RAG', 'Search', request, RAGResult());

  /// Snapshot current index statistics from the logical service state.
  $async.Future<RAGStatistics> stats(
          $pb.ClientContext? ctx, RAGServiceState request) =>
      _client.invoke<RAGStatistics>(
          ctx, 'RAG', 'Stats', request, RAGStatistics());

  /// Clear the current logical index and return the post-clear state.
  $async.Future<RAGServiceState> clear_(
          $pb.ClientContext? ctx, RAGServiceState request) =>
      _client.invoke<RAGServiceState>(
          ctx, 'RAG', 'Clear', request, RAGServiceState());

  /// Server-streaming query events: retrieval start, chunks, context readiness,
  /// token deltas, terminal completion, and errors.
  $async.Future<RAGStreamEvent> stream(
          $pb.ClientContext? ctx, RAGQueryRequest request) =>
      _client.invoke<RAGStreamEvent>(
          ctx, 'RAG', 'Stream', request, RAGStreamEvent());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
