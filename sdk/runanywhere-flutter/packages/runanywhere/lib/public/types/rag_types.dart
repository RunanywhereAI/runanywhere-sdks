/// RAG (Retrieval-Augmented Generation) Types
///
/// Public types for RAG pipeline configuration, query options, and results.
/// Mirrors iOS RAGTypes.swift adapted for Flutter/Dart.
library rag_types;

// MARK: - RAGConfiguration

/// Configuration for the RAG pipeline.
///
/// Specifies model paths, chunking parameters, and generation settings.
/// Mirrors iOS `RAGConfiguration` exactly.
class RAGConfiguration {
  /// Path to the ONNX embedding model file (required).
  final String embeddingModelPath;

  /// Path to the GGUF LLM model file (required).
  /// Can be a directory — the C++ bridge will auto-resolve to the first .gguf file.
  final String llmModelPath;

  /// Embedding vector dimension (default: 384).
  final int embeddingDimension;

  /// Number of top chunks to retrieve (default: 10).
  final int topK;

  /// Minimum cosine similarity threshold for retrieval (default: 0.15).
  final double similarityThreshold;

  /// Maximum context tokens to send to the LLM (default: 2048).
  final int maxContextTokens;

  /// Tokens per chunk when splitting documents (default: 180, matches iOS).
  final int chunkSize;

  /// Overlap tokens between chunks (default: 30, matches iOS).
  final int chunkOverlap;

  /// Optional custom prompt template for the LLM.
  final String? promptTemplate;

  /// Optional JSON configuration for the embedding model.
  final String? embeddingConfigJSON;

  /// Optional JSON configuration for the LLM.
  final String? llmConfigJSON;

  const RAGConfiguration({
    required this.embeddingModelPath,
    required this.llmModelPath,
    this.embeddingDimension = 384,
    this.topK = 10,
    this.similarityThreshold = 0.15,
    this.maxContextTokens = 2048,
    this.chunkSize = 180,
    this.chunkOverlap = 30,
    this.promptTemplate,
    this.embeddingConfigJSON,
    this.llmConfigJSON,
  });

  /// Serialize to JSON for C++ bridge.
  Map<String, dynamic> toJson() => {
        'embeddingModelPath': embeddingModelPath,
        'llmModelPath': llmModelPath,
        'embeddingDimension': embeddingDimension,
        'topK': topK,
        'similarityThreshold': similarityThreshold,
        'maxContextTokens': maxContextTokens,
        'chunkSize': chunkSize,
        'chunkOverlap': chunkOverlap,
        if (promptTemplate != null) 'promptTemplate': promptTemplate,
        if (embeddingConfigJSON != null)
          'embeddingConfigJSON': embeddingConfigJSON,
        if (llmConfigJSON != null) 'llmConfigJSON': llmConfigJSON,
      };

  @override
  String toString() {
    return 'RAGConfiguration(embeddingModel: $embeddingModelPath, '
        'llmModel: $llmModelPath, topK: $topK)';
  }
}

// MARK: - RAGQueryOptions

/// Options for a RAG query.
///
/// Specifies the question and generation parameters.
/// Mirrors iOS `RAGQueryOptions` exactly.
class RAGQueryOptions {
  /// The user's question (required).
  final String question;

  /// Optional system prompt override.
  final String? systemPrompt;

  /// Maximum tokens to generate (default: 512).
  final int maxTokens;

  /// Sampling temperature (default: 0.7).
  final double temperature;

  /// Nucleus sampling probability (default: 0.9).
  final double topP;

  /// Top-k sampling (default: 40).
  final int topK;

  const RAGQueryOptions({
    required this.question,
    this.systemPrompt,
    this.maxTokens = 512,
    this.temperature = 0.7,
    this.topP = 0.9,
    this.topK = 40,
  });

  /// Serialize to JSON for C++ bridge.
  Map<String, dynamic> toJson() => {
        'question': question,
        if (systemPrompt != null) 'systemPrompt': systemPrompt,
        'maxTokens': maxTokens,
        'temperature': temperature,
        'topP': topP,
        'topK': topK,
      };

  @override
  String toString() {
    return 'RAGQueryOptions(question: "${question.length > 50 ? question.substring(0, 50) : question}...", '
        'maxTokens: $maxTokens, temperature: $temperature)';
  }
}

// MARK: - RAGSearchResult

/// A single retrieved chunk from vector search.
///
/// Represents a document chunk that was retrieved as relevant context.
/// Mirrors iOS `RAGSearchResult` exactly.
class RAGSearchResult {
  /// Unique identifier for this chunk.
  final String chunkId;

  /// Text content of the chunk.
  final String text;

  /// Cosine similarity score (0.0–1.0).
  final double similarityScore;

  /// Optional JSON metadata associated with the chunk.
  /// Empty strings from the bridge are converted to null.
  final String? metadataJSON;

  const RAGSearchResult({
    required this.chunkId,
    required this.text,
    required this.similarityScore,
    this.metadataJSON,
  });

  /// Deserialize from JSON returned by C++ bridge.
  factory RAGSearchResult.fromJson(Map<String, dynamic> json) =>
      RAGSearchResult(
        chunkId: json['chunkId'] as String? ?? '',
        text: json['text'] as String? ?? '',
        similarityScore: (json['similarityScore'] as num?)?.toDouble() ?? 0.0,
        metadataJSON: _nonEmpty(json['metadataJson'] as String?),
      );

  @override
  String toString() {
    return 'RAGSearchResult(chunkId: $chunkId, score: $similarityScore)';
  }
}

// MARK: - RAGResult

/// The result of a RAG query.
///
/// Contains the generated answer, retrieved chunks, and timing metrics.
/// Mirrors iOS `RAGResult` exactly.
class RAGResult {
  /// The generated answer text.
  final String answer;

  /// The document chunks retrieved and used as context.
  final List<RAGSearchResult> retrievedChunks;

  /// The full context text sent to the LLM.
  /// Null if context was empty.
  final String? contextUsed;

  /// Time taken for the retrieval phase in milliseconds.
  final double retrievalTimeMs;

  /// Time taken for LLM generation in milliseconds.
  final double generationTimeMs;

  /// Total query time in milliseconds.
  final double totalTimeMs;

  const RAGResult({
    required this.answer,
    required this.retrievedChunks,
    this.contextUsed,
    required this.retrievalTimeMs,
    required this.generationTimeMs,
    required this.totalTimeMs,
  });

  /// Deserialize from JSON returned by C++ bridge.
  factory RAGResult.fromJson(Map<String, dynamic> json) => RAGResult(
        answer: json['answer'] as String? ?? '',
        retrievedChunks: (json['retrievedChunks'] as List<dynamic>?)
                ?.map((c) =>
                    RAGSearchResult.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [],
        contextUsed: _nonEmpty(json['contextUsed'] as String?),
        retrievalTimeMs: (json['retrievalTimeMs'] as num?)?.toDouble() ?? 0.0,
        generationTimeMs:
            (json['generationTimeMs'] as num?)?.toDouble() ?? 0.0,
        totalTimeMs: (json['totalTimeMs'] as num?)?.toDouble() ?? 0.0,
      );

  @override
  String toString() {
    final preview = answer.length > 50 ? answer.substring(0, 50) : answer;
    return 'RAGResult(answer: "$preview...", chunks: ${retrievedChunks.length}, '
        'totalTimeMs: $totalTimeMs)';
  }
}

// MARK: - RAGStatistics

/// Pipeline statistics returned by ragGetStatistics().
///
/// Matches React Native's RAG statistics output.
class RAGStatistics {
  /// Raw JSON string from the C pipeline.
  final String statsJson;

  const RAGStatistics({required this.statsJson});

  /// Deserialize from a JSON string.
  factory RAGStatistics.fromJsonString(String json) =>
      RAGStatistics(statsJson: json);

  @override
  String toString() => 'RAGStatistics($statsJson)';
}

// MARK: - Helpers

/// Returns null for null or empty strings.
String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;
