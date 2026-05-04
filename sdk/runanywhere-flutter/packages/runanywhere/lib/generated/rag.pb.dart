//
//  Generated code. Do not modify.
//  source: rag.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

///  ---------------------------------------------------------------------------
///  RAGConfiguration — low-level pipeline config (pre-IDL hand-rolled).
///
///  This is the runtime configuration consumed by the RAG pipeline directly,
///  distinct from solutions.proto::RAGConfig (which is the high-level solution
///  spec resolved through the model registry). RAGConfiguration takes raw model
///  paths because the pipeline runs after model resolution has already happened.
///  ---------------------------------------------------------------------------
class RAGConfiguration extends $pb.GeneratedMessage {
  factory RAGConfiguration({
    $core.String? embeddingModelPath,
    $core.String? llmModelPath,
    $core.int? embeddingDimension,
    $core.int? topK,
    $core.double? similarityThreshold,
    $core.int? chunkSize,
    $core.int? chunkOverlap,
    $core.int? maxContextTokens,
    $core.String? promptTemplate,
    $core.String? embeddingConfigJson,
    $core.String? llmConfigJson,
  }) {
    final $result = create();
    if (embeddingModelPath != null) {
      $result.embeddingModelPath = embeddingModelPath;
    }
    if (llmModelPath != null) {
      $result.llmModelPath = llmModelPath;
    }
    if (embeddingDimension != null) {
      $result.embeddingDimension = embeddingDimension;
    }
    if (topK != null) {
      $result.topK = topK;
    }
    if (similarityThreshold != null) {
      $result.similarityThreshold = similarityThreshold;
    }
    if (chunkSize != null) {
      $result.chunkSize = chunkSize;
    }
    if (chunkOverlap != null) {
      $result.chunkOverlap = chunkOverlap;
    }
    if (maxContextTokens != null) {
      $result.maxContextTokens = maxContextTokens;
    }
    if (promptTemplate != null) {
      $result.promptTemplate = promptTemplate;
    }
    if (embeddingConfigJson != null) {
      $result.embeddingConfigJson = embeddingConfigJson;
    }
    if (llmConfigJson != null) {
      $result.llmConfigJson = llmConfigJson;
    }
    return $result;
  }
  RAGConfiguration._() : super();
  factory RAGConfiguration.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RAGConfiguration.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RAGConfiguration', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'embeddingModelPath')
    ..aOS(2, _omitFieldNames ? '' : 'llmModelPath')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'embeddingDimension', $pb.PbFieldType.O3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'topK', $pb.PbFieldType.O3)
    ..a<$core.double>(5, _omitFieldNames ? '' : 'similarityThreshold', $pb.PbFieldType.OF)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'chunkSize', $pb.PbFieldType.O3)
    ..a<$core.int>(7, _omitFieldNames ? '' : 'chunkOverlap', $pb.PbFieldType.O3)
    ..a<$core.int>(8, _omitFieldNames ? '' : 'maxContextTokens', $pb.PbFieldType.O3)
    ..aOS(9, _omitFieldNames ? '' : 'promptTemplate')
    ..aOS(10, _omitFieldNames ? '' : 'embeddingConfigJson')
    ..aOS(11, _omitFieldNames ? '' : 'llmConfigJson')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RAGConfiguration clone() => RAGConfiguration()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RAGConfiguration copyWith(void Function(RAGConfiguration) updates) => super.copyWith((message) => updates(message as RAGConfiguration)) as RAGConfiguration;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGConfiguration create() => RAGConfiguration._();
  RAGConfiguration createEmptyInstance() => create();
  static $pb.PbList<RAGConfiguration> createRepeated() => $pb.PbList<RAGConfiguration>();
  @$core.pragma('dart2js:noInline')
  static RAGConfiguration getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RAGConfiguration>(create);
  static RAGConfiguration? _defaultInstance;

  /// Filesystem path to the embedding model (typically ONNX).
  @$pb.TagNumber(1)
  $core.String get embeddingModelPath => $_getSZ(0);
  @$pb.TagNumber(1)
  set embeddingModelPath($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEmbeddingModelPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearEmbeddingModelPath() => clearField(1);

  /// Filesystem path to the LLM model (typically GGUF).
  @$pb.TagNumber(2)
  $core.String get llmModelPath => $_getSZ(1);
  @$pb.TagNumber(2)
  set llmModelPath($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasLlmModelPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearLlmModelPath() => clearField(2);

  /// Embedding vector dimension — must match the embedding model.
  /// Common: 384 (all-MiniLM-L6-v2), 768 (bge-base), 1024 (bge-large).
  @$pb.TagNumber(3)
  $core.int get embeddingDimension => $_getIZ(2);
  @$pb.TagNumber(3)
  set embeddingDimension($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasEmbeddingDimension() => $_has(2);
  @$pb.TagNumber(3)
  void clearEmbeddingDimension() => clearField(3);

  /// Number of top chunks to retrieve per query.
  @$pb.TagNumber(4)
  $core.int get topK => $_getIZ(3);
  @$pb.TagNumber(4)
  set topK($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTopK() => $_has(3);
  @$pb.TagNumber(4)
  void clearTopK() => clearField(4);

  /// Minimum cosine similarity threshold (0.0–1.0). Chunks below this
  /// score are discarded before being passed to the LLM as context.
  @$pb.TagNumber(5)
  $core.double get similarityThreshold => $_getN(4);
  @$pb.TagNumber(5)
  set similarityThreshold($core.double v) { $_setFloat(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSimilarityThreshold() => $_has(4);
  @$pb.TagNumber(5)
  void clearSimilarityThreshold() => clearField(5);

  /// Tokens per chunk when splitting documents during ingestion.
  @$pb.TagNumber(6)
  $core.int get chunkSize => $_getIZ(5);
  @$pb.TagNumber(6)
  set chunkSize($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasChunkSize() => $_has(5);
  @$pb.TagNumber(6)
  void clearChunkSize() => clearField(6);

  /// Overlap tokens between consecutive chunks. Must be < chunk_size.
  @$pb.TagNumber(7)
  $core.int get chunkOverlap => $_getIZ(6);
  @$pb.TagNumber(7)
  set chunkOverlap($core.int v) { $_setSignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasChunkOverlap() => $_has(6);
  @$pb.TagNumber(7)
  void clearChunkOverlap() => clearField(7);

  /// Maximum tokens of retrieved context passed to the LLM.
  @$pb.TagNumber(8)
  $core.int get maxContextTokens => $_getIZ(7);
  @$pb.TagNumber(8)
  set maxContextTokens($core.int v) { $_setSignedInt32(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasMaxContextTokens() => $_has(7);
  @$pb.TagNumber(8)
  void clearMaxContextTokens() => clearField(8);

  /// Prompt template with `{context}` and `{query}` placeholders.
  @$pb.TagNumber(9)
  $core.String get promptTemplate => $_getSZ(8);
  @$pb.TagNumber(9)
  set promptTemplate($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasPromptTemplate() => $_has(8);
  @$pb.TagNumber(9)
  void clearPromptTemplate() => clearField(9);

  /// Backend-specific config JSON passed to the embedding model/provider.
  @$pb.TagNumber(10)
  $core.String get embeddingConfigJson => $_getSZ(9);
  @$pb.TagNumber(10)
  set embeddingConfigJson($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasEmbeddingConfigJson() => $_has(9);
  @$pb.TagNumber(10)
  void clearEmbeddingConfigJson() => clearField(10);

  /// Backend-specific config JSON passed to the LLM provider.
  @$pb.TagNumber(11)
  $core.String get llmConfigJson => $_getSZ(10);
  @$pb.TagNumber(11)
  set llmConfigJson($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasLlmConfigJson() => $_has(10);
  @$pb.TagNumber(11)
  void clearLlmConfigJson() => clearField(11);
}

/// ---------------------------------------------------------------------------
/// RAGDocument — batch-ingest input item.
/// ---------------------------------------------------------------------------
class RAGDocument extends $pb.GeneratedMessage {
  factory RAGDocument({
    $core.String? id,
    $core.String? text,
    $core.String? metadataJson,
    $core.Map<$core.String, $core.String>? metadata,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (text != null) {
      $result.text = text;
    }
    if (metadataJson != null) {
      $result.metadataJson = metadataJson;
    }
    if (metadata != null) {
      $result.metadata.addAll(metadata);
    }
    return $result;
  }
  RAGDocument._() : super();
  factory RAGDocument.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RAGDocument.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RAGDocument', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'text')
    ..aOS(3, _omitFieldNames ? '' : 'metadataJson')
    ..m<$core.String, $core.String>(4, _omitFieldNames ? '' : 'metadata', entryClassName: 'RAGDocument.MetadataEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RAGDocument clone() => RAGDocument()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RAGDocument copyWith(void Function(RAGDocument) updates) => super.copyWith((message) => updates(message as RAGDocument)) as RAGDocument;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGDocument create() => RAGDocument._();
  RAGDocument createEmptyInstance() => create();
  static $pb.PbList<RAGDocument> createRepeated() => $pb.PbList<RAGDocument>();
  @$core.pragma('dart2js:noInline')
  static RAGDocument getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RAGDocument>(create);
  static RAGDocument? _defaultInstance;

  /// Optional caller-supplied document id.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  /// Plain text content to chunk/embed.
  @$pb.TagNumber(2)
  $core.String get text => $_getSZ(1);
  @$pb.TagNumber(2)
  set text($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => clearField(2);

  /// Legacy metadata JSON blob.
  @$pb.TagNumber(3)
  $core.String get metadataJson => $_getSZ(2);
  @$pb.TagNumber(3)
  set metadataJson($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMetadataJson() => $_has(2);
  @$pb.TagNumber(3)
  void clearMetadataJson() => clearField(3);

  /// Typed metadata map for generated-proto callers.
  @$pb.TagNumber(4)
  $core.Map<$core.String, $core.String> get metadata => $_getMap(3);
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
  }) {
    final $result = create();
    if (question != null) {
      $result.question = question;
    }
    if (systemPrompt != null) {
      $result.systemPrompt = systemPrompt;
    }
    if (maxTokens != null) {
      $result.maxTokens = maxTokens;
    }
    if (temperature != null) {
      $result.temperature = temperature;
    }
    if (topP != null) {
      $result.topP = topP;
    }
    if (topK != null) {
      $result.topK = topK;
    }
    return $result;
  }
  RAGQueryOptions._() : super();
  factory RAGQueryOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RAGQueryOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RAGQueryOptions', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'question')
    ..aOS(2, _omitFieldNames ? '' : 'systemPrompt')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'maxTokens', $pb.PbFieldType.O3)
    ..a<$core.double>(4, _omitFieldNames ? '' : 'temperature', $pb.PbFieldType.OF)
    ..a<$core.double>(5, _omitFieldNames ? '' : 'topP', $pb.PbFieldType.OF)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'topK', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RAGQueryOptions clone() => RAGQueryOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RAGQueryOptions copyWith(void Function(RAGQueryOptions) updates) => super.copyWith((message) => updates(message as RAGQueryOptions)) as RAGQueryOptions;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGQueryOptions create() => RAGQueryOptions._();
  RAGQueryOptions createEmptyInstance() => create();
  static $pb.PbList<RAGQueryOptions> createRepeated() => $pb.PbList<RAGQueryOptions>();
  @$core.pragma('dart2js:noInline')
  static RAGQueryOptions getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RAGQueryOptions>(create);
  static RAGQueryOptions? _defaultInstance;

  /// The user question to answer. Required (empty = no-op).
  @$pb.TagNumber(1)
  $core.String get question => $_getSZ(0);
  @$pb.TagNumber(1)
  set question($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasQuestion() => $_has(0);
  @$pb.TagNumber(1)
  void clearQuestion() => clearField(1);

  /// Optional system prompt override. Unset uses the pipeline default.
  @$pb.TagNumber(2)
  $core.String get systemPrompt => $_getSZ(1);
  @$pb.TagNumber(2)
  set systemPrompt($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSystemPrompt() => $_has(1);
  @$pb.TagNumber(2)
  void clearSystemPrompt() => clearField(2);

  /// Maximum tokens to generate in the answer.
  @$pb.TagNumber(3)
  $core.int get maxTokens => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxTokens($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMaxTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxTokens() => clearField(3);

  /// Sampling temperature. 0.0 = greedy, higher = more random.
  @$pb.TagNumber(4)
  $core.double get temperature => $_getN(3);
  @$pb.TagNumber(4)
  set temperature($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTemperature() => $_has(3);
  @$pb.TagNumber(4)
  void clearTemperature() => clearField(4);

  /// Nucleus (top-p) sampling parameter. 1.0 = disabled.
  @$pb.TagNumber(5)
  $core.double get topP => $_getN(4);
  @$pb.TagNumber(5)
  set topP($core.double v) { $_setFloat(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasTopP() => $_has(4);
  @$pb.TagNumber(5)
  void clearTopP() => clearField(5);

  /// Top-k sampling parameter. 0 = disabled.
  @$pb.TagNumber(6)
  $core.int get topK => $_getIZ(5);
  @$pb.TagNumber(6)
  set topK($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTopK() => $_has(5);
  @$pb.TagNumber(6)
  void clearTopK() => clearField(6);
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
    $core.Map<$core.String, $core.String>? metadata,
    $core.String? metadataJson,
  }) {
    final $result = create();
    if (chunkId != null) {
      $result.chunkId = chunkId;
    }
    if (text != null) {
      $result.text = text;
    }
    if (similarityScore != null) {
      $result.similarityScore = similarityScore;
    }
    if (sourceDocument != null) {
      $result.sourceDocument = sourceDocument;
    }
    if (metadata != null) {
      $result.metadata.addAll(metadata);
    }
    if (metadataJson != null) {
      $result.metadataJson = metadataJson;
    }
    return $result;
  }
  RAGSearchResult._() : super();
  factory RAGSearchResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RAGSearchResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RAGSearchResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'chunkId')
    ..aOS(2, _omitFieldNames ? '' : 'text')
    ..a<$core.double>(3, _omitFieldNames ? '' : 'similarityScore', $pb.PbFieldType.OF)
    ..aOS(4, _omitFieldNames ? '' : 'sourceDocument')
    ..m<$core.String, $core.String>(5, _omitFieldNames ? '' : 'metadata', entryClassName: 'RAGSearchResult.MetadataEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('runanywhere.v1'))
    ..aOS(6, _omitFieldNames ? '' : 'metadataJson')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RAGSearchResult clone() => RAGSearchResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RAGSearchResult copyWith(void Function(RAGSearchResult) updates) => super.copyWith((message) => updates(message as RAGSearchResult)) as RAGSearchResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGSearchResult create() => RAGSearchResult._();
  RAGSearchResult createEmptyInstance() => create();
  static $pb.PbList<RAGSearchResult> createRepeated() => $pb.PbList<RAGSearchResult>();
  @$core.pragma('dart2js:noInline')
  static RAGSearchResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RAGSearchResult>(create);
  static RAGSearchResult? _defaultInstance;

  /// Unique identifier of the chunk (assigned at ingestion time).
  @$pb.TagNumber(1)
  $core.String get chunkId => $_getSZ(0);
  @$pb.TagNumber(1)
  set chunkId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChunkId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChunkId() => clearField(1);

  /// Text content of the chunk (the actual snippet shown to the LLM).
  @$pb.TagNumber(2)
  $core.String get text => $_getSZ(1);
  @$pb.TagNumber(2)
  set text($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => clearField(2);

  /// Cosine similarity score (0.0–1.0). Higher = more relevant.
  @$pb.TagNumber(3)
  $core.double get similarityScore => $_getN(2);
  @$pb.TagNumber(3)
  set similarityScore($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSimilarityScore() => $_has(2);
  @$pb.TagNumber(3)
  void clearSimilarityScore() => clearField(3);

  /// Optional source document identifier (filename, URL, or document ID).
  /// Set when the chunk's origin is tracked at ingestion time.
  @$pb.TagNumber(4)
  $core.String get sourceDocument => $_getSZ(3);
  @$pb.TagNumber(4)
  set sourceDocument($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSourceDocument() => $_has(3);
  @$pb.TagNumber(4)
  void clearSourceDocument() => clearField(4);

  /// Free-form metadata associated with the chunk (e.g. page number, section,
  /// ingestion timestamp). Pre-IDL all SDKs encoded this as a JSON string;
  /// canonicalized here as a typed map so consumers don't re-parse.
  @$pb.TagNumber(5)
  $core.Map<$core.String, $core.String> get metadata => $_getMap(4);

  /// Legacy metadata JSON blob preserved for C ABI / SDK surfaces that still
  /// pass metadata without parsing it.
  @$pb.TagNumber(6)
  $core.String get metadataJson => $_getSZ(5);
  @$pb.TagNumber(6)
  set metadataJson($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasMetadataJson() => $_has(5);
  @$pb.TagNumber(6)
  void clearMetadataJson() => clearField(6);
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
  }) {
    final $result = create();
    if (answer != null) {
      $result.answer = answer;
    }
    if (retrievedChunks != null) {
      $result.retrievedChunks.addAll(retrievedChunks);
    }
    if (contextUsed != null) {
      $result.contextUsed = contextUsed;
    }
    if (retrievalTimeMs != null) {
      $result.retrievalTimeMs = retrievalTimeMs;
    }
    if (generationTimeMs != null) {
      $result.generationTimeMs = generationTimeMs;
    }
    if (totalTimeMs != null) {
      $result.totalTimeMs = totalTimeMs;
    }
    return $result;
  }
  RAGResult._() : super();
  factory RAGResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RAGResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RAGResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'answer')
    ..pc<RAGSearchResult>(2, _omitFieldNames ? '' : 'retrievedChunks', $pb.PbFieldType.PM, subBuilder: RAGSearchResult.create)
    ..aOS(3, _omitFieldNames ? '' : 'contextUsed')
    ..aInt64(4, _omitFieldNames ? '' : 'retrievalTimeMs')
    ..aInt64(5, _omitFieldNames ? '' : 'generationTimeMs')
    ..aInt64(6, _omitFieldNames ? '' : 'totalTimeMs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RAGResult clone() => RAGResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RAGResult copyWith(void Function(RAGResult) updates) => super.copyWith((message) => updates(message as RAGResult)) as RAGResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGResult create() => RAGResult._();
  RAGResult createEmptyInstance() => create();
  static $pb.PbList<RAGResult> createRepeated() => $pb.PbList<RAGResult>();
  @$core.pragma('dart2js:noInline')
  static RAGResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RAGResult>(create);
  static RAGResult? _defaultInstance;

  /// The LLM-generated answer grounded in the retrieved context.
  @$pb.TagNumber(1)
  $core.String get answer => $_getSZ(0);
  @$pb.TagNumber(1)
  set answer($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAnswer() => $_has(0);
  @$pb.TagNumber(1)
  void clearAnswer() => clearField(1);

  /// Document chunks retrieved during vector search and used as context.
  /// Order matches retrieval rank (highest similarity first).
  @$pb.TagNumber(2)
  $core.List<RAGSearchResult> get retrievedChunks => $_getList(1);

  /// Full context string passed to the LLM (chunks joined into a prompt).
  /// May be empty for queries with no matching chunks.
  @$pb.TagNumber(3)
  $core.String get contextUsed => $_getSZ(2);
  @$pb.TagNumber(3)
  set contextUsed($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasContextUsed() => $_has(2);
  @$pb.TagNumber(3)
  void clearContextUsed() => clearField(3);

  /// Time spent in the retrieval phase (vector search), in milliseconds.
  @$pb.TagNumber(4)
  $fixnum.Int64 get retrievalTimeMs => $_getI64(3);
  @$pb.TagNumber(4)
  set retrievalTimeMs($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasRetrievalTimeMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearRetrievalTimeMs() => clearField(4);

  /// Time spent in the LLM generation phase, in milliseconds.
  @$pb.TagNumber(5)
  $fixnum.Int64 get generationTimeMs => $_getI64(4);
  @$pb.TagNumber(5)
  set generationTimeMs($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasGenerationTimeMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearGenerationTimeMs() => clearField(5);

  /// Total end-to-end query time (retrieval + generation + overhead),
  /// in milliseconds.
  @$pb.TagNumber(6)
  $fixnum.Int64 get totalTimeMs => $_getI64(5);
  @$pb.TagNumber(6)
  set totalTimeMs($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTotalTimeMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearTotalTimeMs() => clearField(6);
}

///  ---------------------------------------------------------------------------
///  RAGStatistics — index-level counters for the RAG pipeline.
///
///  Returned by RunAnywhere.rag.statistics() / ragGetStatistics().
///  ---------------------------------------------------------------------------
class RAGStatistics extends $pb.GeneratedMessage {
  factory RAGStatistics({
    $fixnum.Int64? indexedDocuments,
    $fixnum.Int64? indexedChunks,
    $fixnum.Int64? totalTokensIndexed,
    $fixnum.Int64? lastUpdatedMs,
    $core.String? indexPath,
    $core.String? statsJson,
    $fixnum.Int64? vectorStoreSizeBytes,
  }) {
    final $result = create();
    if (indexedDocuments != null) {
      $result.indexedDocuments = indexedDocuments;
    }
    if (indexedChunks != null) {
      $result.indexedChunks = indexedChunks;
    }
    if (totalTokensIndexed != null) {
      $result.totalTokensIndexed = totalTokensIndexed;
    }
    if (lastUpdatedMs != null) {
      $result.lastUpdatedMs = lastUpdatedMs;
    }
    if (indexPath != null) {
      $result.indexPath = indexPath;
    }
    if (statsJson != null) {
      $result.statsJson = statsJson;
    }
    if (vectorStoreSizeBytes != null) {
      $result.vectorStoreSizeBytes = vectorStoreSizeBytes;
    }
    return $result;
  }
  RAGStatistics._() : super();
  factory RAGStatistics.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RAGStatistics.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RAGStatistics', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'indexedDocuments')
    ..aInt64(2, _omitFieldNames ? '' : 'indexedChunks')
    ..aInt64(3, _omitFieldNames ? '' : 'totalTokensIndexed')
    ..aInt64(4, _omitFieldNames ? '' : 'lastUpdatedMs')
    ..aOS(5, _omitFieldNames ? '' : 'indexPath')
    ..aOS(6, _omitFieldNames ? '' : 'statsJson')
    ..aInt64(7, _omitFieldNames ? '' : 'vectorStoreSizeBytes')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RAGStatistics clone() => RAGStatistics()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RAGStatistics copyWith(void Function(RAGStatistics) updates) => super.copyWith((message) => updates(message as RAGStatistics)) as RAGStatistics;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGStatistics create() => RAGStatistics._();
  RAGStatistics createEmptyInstance() => create();
  static $pb.PbList<RAGStatistics> createRepeated() => $pb.PbList<RAGStatistics>();
  @$core.pragma('dart2js:noInline')
  static RAGStatistics getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RAGStatistics>(create);
  static RAGStatistics? _defaultInstance;

  /// Total number of documents ever ingested into the index.
  @$pb.TagNumber(1)
  $fixnum.Int64 get indexedDocuments => $_getI64(0);
  @$pb.TagNumber(1)
  set indexedDocuments($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasIndexedDocuments() => $_has(0);
  @$pb.TagNumber(1)
  void clearIndexedDocuments() => clearField(1);

  /// Total number of chunks across all indexed documents.
  @$pb.TagNumber(2)
  $fixnum.Int64 get indexedChunks => $_getI64(1);
  @$pb.TagNumber(2)
  set indexedChunks($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasIndexedChunks() => $_has(1);
  @$pb.TagNumber(2)
  void clearIndexedChunks() => clearField(2);

  /// Approximate total token count across all indexed chunks.
  @$pb.TagNumber(3)
  $fixnum.Int64 get totalTokensIndexed => $_getI64(2);
  @$pb.TagNumber(3)
  set totalTokensIndexed($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTotalTokensIndexed() => $_has(2);
  @$pb.TagNumber(3)
  void clearTotalTokensIndexed() => clearField(3);

  /// Wall-clock timestamp of the most recent ingestion, in milliseconds
  /// since Unix epoch. 0 = no ingestion yet.
  @$pb.TagNumber(4)
  $fixnum.Int64 get lastUpdatedMs => $_getI64(3);
  @$pb.TagNumber(4)
  set lastUpdatedMs($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasLastUpdatedMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearLastUpdatedMs() => clearField(4);

  /// Filesystem path to the on-disk index, when applicable. Unset for
  /// in-memory-only indexes.
  @$pb.TagNumber(5)
  $core.String get indexPath => $_getSZ(4);
  @$pb.TagNumber(5)
  set indexPath($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasIndexPath() => $_has(4);
  @$pb.TagNumber(5)
  void clearIndexPath() => clearField(5);

  /// Raw backend statistics JSON for implementations that cannot yet project
  /// every counter into typed fields.
  @$pb.TagNumber(6)
  $core.String get statsJson => $_getSZ(5);
  @$pb.TagNumber(6)
  set statsJson($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasStatsJson() => $_has(5);
  @$pb.TagNumber(6)
  void clearStatsJson() => clearField(6);

  /// Approximate vector-store footprint in bytes, when known.
  @$pb.TagNumber(7)
  $fixnum.Int64 get vectorStoreSizeBytes => $_getI64(6);
  @$pb.TagNumber(7)
  set vectorStoreSizeBytes($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasVectorStoreSizeBytes() => $_has(6);
  @$pb.TagNumber(7)
  void clearVectorStoreSizeBytes() => clearField(7);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
