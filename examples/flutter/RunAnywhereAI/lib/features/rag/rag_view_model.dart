// RAG View Model
//
// Coordinates document extraction, SDK pipeline lifecycle, and query state.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart' hide ModelInfo;
import 'package:runanywhere/runanywhere_protos.dart' as proto;

import 'package:runanywhere_ai/features/models/model_types.dart';
import 'package:runanywhere_ai/features/rag/document_service.dart';

/// A single message in the RAG conversation.
///
/// User messages contain only text. Assistant messages also carry
/// the [RAGResult] for displaying retrieved chunks and timing info.
class RAGMessage {
  final proto.MessageRole role;
  final String text;

  /// The RAG result associated with this assistant message.
  /// Null for user messages and error messages.
  final RAGResult? result;

  const RAGMessage({
    required this.role,
    required this.text,
    this.result,
  });
}

/// ViewModel managing the full RAG pipeline lifecycle, document state, and query flow.
///
/// Exposes observable state via ChangeNotifier for ListenableBuilder.
class RAGViewModel extends ChangeNotifier {
  String? _documentName;
  String? get documentName => _documentName;

  bool _isDocumentLoaded = false;
  bool get isDocumentLoaded => _isDocumentLoaded;

  bool _isLoadingDocument = false;
  bool get isLoadingDocument => _isLoadingDocument;

  List<RAGMessage> _messages = [];
  List<RAGMessage> get messages => List.unmodifiable(_messages);

  bool _isQuerying = false;
  bool get isQuerying => _isQuerying;

  /// Settable from the view layer to surface file-picker failures.
  String? _error;
  String? get error => _error;
  set error(String? value) {
    _error = value;
    notifyListeners();
  }

  String _currentQuestion = '';
  String get currentQuestion => _currentQuestion;
  set currentQuestion(String value) {
    _currentQuestion = value;
    notifyListeners();
  }

  RAGResult? _lastResult;
  RAGResult? get lastResult => _lastResult;

  bool get canAskQuestion =>
      _isDocumentLoaded && !_isQuerying && _currentQuestion.trim().isNotEmpty;

  /// Load a document: extract text, create RAG pipeline, ingest text.
  ///
  /// [filePath] - Absolute path to the document (PDF or JSON).
  /// [embeddingModel] - Registry model selected for embeddings.
  /// [llmModel] - Registry model selected for answer generation.
  Future<void> loadDocument(
    String filePath,
    ModelInfo embeddingModel,
    ModelInfo llmModel,
  ) async {
    _isLoadingDocument = true;
    _error = null;
    notifyListeners();

    try {
      final extractedText = await DocumentService.extractText(filePath);

      await RunAnywhere.rag.ragCreatePipelineForModels(
        embeddingModel: embeddingModel,
        llmModel: llmModel,
      );
      await RunAnywhere.rag.ingest(extractedText);

      _documentName = File(filePath).uri.pathSegments.last;
      _isDocumentLoaded = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingDocument = false;
      notifyListeners();
    }
  }

  /// Query the loaded document with the current question.
  ///
  /// Appends the user question and the assistant answer to [messages].
  /// Guards against empty questions and unloaded documents.
  Future<void> askQuestion() async {
    final question = _currentQuestion.trim();
    if (question.isEmpty) return;
    if (!_isDocumentLoaded) return;

    _messages = [
      ..._messages,
      RAGMessage(role: proto.MessageRole.MESSAGE_ROLE_USER, text: question)
    ];
    _currentQuestion = '';
    _isQuerying = true;
    _error = null;
    notifyListeners();

    try {
      final result = await RunAnywhere.rag.query(question);

      _messages = [
        ..._messages,
        RAGMessage(
            role: proto.MessageRole.MESSAGE_ROLE_ASSISTANT,
            text: result.answer,
            result: result),
      ];
      _lastResult = result;
    } catch (e) {
      _error = e.toString();
      _messages = [
        ..._messages,
        RAGMessage(
            role: proto.MessageRole.MESSAGE_ROLE_ASSISTANT, text: 'Error: $e'),
      ];
    } finally {
      _isQuerying = false;
      notifyListeners();
    }
  }

  /// Clear the loaded document and destroy the RAG pipeline.
  ///
  /// Resets all document and conversation state.
  Future<void> clearDocument() async {
    await RunAnywhere.rag.destroyPipeline();

    _documentName = null;
    _isDocumentLoaded = false;
    _messages = [];
    _error = null;
    _currentQuestion = '';
    _lastResult = null;
    notifyListeners();
  }
}
