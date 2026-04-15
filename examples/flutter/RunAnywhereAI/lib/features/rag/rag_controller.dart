import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runanywhere/public/extensions/runanywhere_rag.dart';
import 'package:runanywhere/public/types/rag_types.dart';
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere_ai/data/models/chat_message.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

enum RagDocumentStatus { none, loading, loaded, error }

class RagState {
  const RagState({
    this.documentStatus = RagDocumentStatus.none,
    this.documentName,
    this.chunkCount = 0,
    this.messages = const [],
    this.isQuerying = false,
    this.statusText,
    this.embeddingModelName,
    this.llmModelName,
    this.errorMessage,
  });

  final RagDocumentStatus documentStatus;
  final String? documentName;
  final int chunkCount;
  final List<ChatMessage> messages;
  final bool isQuerying;
  final String? statusText;
  final String? embeddingModelName;
  final String? llmModelName;
  final String? errorMessage;

  bool get hasDocument => documentStatus == RagDocumentStatus.loaded;
  bool get hasModels =>
      embeddingModelName != null && llmModelName != null;

  RagState copyWith({
    RagDocumentStatus? documentStatus,
    String? documentName,
    int? chunkCount,
    List<ChatMessage>? messages,
    bool? isQuerying,
    String? statusText,
    String? embeddingModelName,
    String? llmModelName,
    String? errorMessage,
    bool clearError = false,
    bool clearEmbedding = false,
    bool clearLlm = false,
  }) {
    return RagState(
      documentStatus: documentStatus ?? this.documentStatus,
      documentName: documentName ?? this.documentName,
      chunkCount: chunkCount ?? this.chunkCount,
      messages: messages ?? this.messages,
      isQuerying: isQuerying ?? this.isQuerying,
      statusText: statusText,
      embeddingModelName: clearEmbedding
          ? null
          : (embeddingModelName ?? this.embeddingModelName),
      llmModelName:
          clearLlm ? null : (llmModelName ?? this.llmModelName),
      errorMessage:
          clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final ragControllerProvider =
    NotifierProvider<RagController, RagState>(RagController.new);

class RagController extends Notifier<RagState> {
  ModelInfo? _embeddingModel;
  ModelInfo? _llmModel;

  @override
  RagState build() => const RagState();

  void setEmbeddingModel(ModelInfo model) {
    _embeddingModel = model;
    state = state.copyWith(embeddingModelName: model.name);
  }

  void setLlmModel(ModelInfo model) {
    _llmModel = model;
    state = state.copyWith(llmModelName: model.name);
  }

  Future<void> loadDocument(String path, String name) async {
    if (_embeddingModel == null || _llmModel == null) {
      state = state.copyWith(
        errorMessage: 'Select both an embedding model and an LLM first',
      );
      return;
    }

    state = state.copyWith(
      documentStatus: RagDocumentStatus.loading,
      statusText: 'Extracting text...',
      clearError: true,
    );

    try {
      final text = await _extractText(path);
      debugPrint('[RAG] Extracted ${text.length} chars from $name');

      state = state.copyWith(statusText: 'Creating RAG pipeline...');

      final embeddingPath =
          _embeddingModel!.localPath?.toFilePath() ?? '';
      final llmPath = _llmModel!.localPath?.toFilePath() ?? '';

      final config = RAGConfiguration(
        embeddingModelPath: embeddingPath,
        llmModelPath: llmPath,
      );

      await RunAnywhereRAG.ragCreatePipeline(config);
      debugPrint('[RAG] Pipeline created');

      state = state.copyWith(statusText: 'Ingesting document...');
      await RunAnywhereRAG.ragIngest(text);

      final count = await RunAnywhereRAG.ragDocumentCount();
      debugPrint('[RAG] Ingested $count chunks');

      state = state.copyWith(
        documentStatus: RagDocumentStatus.loaded,
        documentName: name,
        chunkCount: count,
        statusText: null,
      );
    } on Exception catch (e) {
      debugPrint('[RAG] Load failed: $e');
      state = state.copyWith(
        documentStatus: RagDocumentStatus.error,
        statusText: null,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> query(String question) async {
    if (question.trim().isEmpty || state.isQuerying) return;

    final userMsg =
        ChatMessage(role: MessageRole.user, content: question);
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isQuerying: true,
      clearError: true,
    );

    try {
      state = state.copyWith(statusText: 'Retrieving relevant chunks...');
      debugPrint('[RAG] Querying: $question');

      final result = await RunAnywhereRAG.ragQuery(question);
      debugPrint('[RAG] Answer: ${result.answer.substring(0, result.answer.length.clamp(0, 100))}');

      final assistantMsg = ChatMessage(
        role: MessageRole.assistant,
        content: result.answer,
        analytics: MessageAnalytics(
          totalGenerationMs: result.totalTimeMs,
        ),
      );
      state = state.copyWith(
        messages: [...state.messages, assistantMsg],
        isQuerying: false,
        statusText: null,
      );
    } on Exception catch (e) {
      debugPrint('[RAG] Query failed: $e');
      state = state.copyWith(
        isQuerying: false,
        statusText: null,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> clearDocument() async {
    try {
      await RunAnywhereRAG.ragDestroyPipeline();
    } on Exception catch (_) {}
    state = state.copyWith(
      documentStatus: RagDocumentStatus.none,
      documentName: null,
      chunkCount: 0,
      messages: [],
      clearError: true,
    );
  }

  void clearChat() => state = state.copyWith(messages: []);

  Future<String> _extractText(String path) async {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return _extractPdf(path);
      case 'json':
        return File(path).readAsString(encoding: utf8);
      case 'txt':
        return File(path).readAsString(encoding: utf8);
      default:
        throw UnsupportedError('Unsupported format: .$ext');
    }
  }

  Future<String> _extractPdf(String path) async {
    final bytes = await File(path).readAsBytes();
    final doc = PdfDocument(inputBytes: bytes);
    final extractor = PdfTextExtractor(doc);
    final buffer = StringBuffer();

    for (var i = 0; i < doc.pages.count; i++) {
      final text =
          extractor.extractText(startPageIndex: i, endPageIndex: i);
      if (text.trim().isNotEmpty) {
        if (buffer.isNotEmpty) buffer.write('\n');
        buffer.write(text);
      }
    }

    doc.dispose();
    final result = buffer.toString();
    if (result.isEmpty) {
      throw Exception('Could not extract text from PDF');
    }
    return result;
  }
}
