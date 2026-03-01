// RAG View Model
//
// ViewModel for the RAG feature. Orchestrates document loading,
// text extraction, SDK pipeline lifecycle, and query flow.
// Mirrors iOS RAGViewModel.swift adapted for Flutter ChangeNotifier pattern.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:runanywhere/public/extensions/runanywhere_rag.dart';
import 'package:runanywhere/public/types/rag_types.dart';

import 'package:runanywhere_ai/features/rag/document_service.dart';

// MARK: - Message Role

enum RAGMessageRole { user, assistant }

// MARK: - RAG Message

/// A single message in the RAG conversation.
///
/// User messages contain only text. Assistant messages also carry
/// the [RAGResult] for displaying retrieved chunks and timing info.
class RAGMessage {
  final RAGMessageRole role;
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

// MARK: - RAG View Model

/// ViewModel managing the full RAG pipeline lifecycle, document state, and query flow.
///
/// Mirrors iOS RAGViewModel.swift. Exposes observable state via ChangeNotifier
/// for use with Flutter's ListenableBuilder / ChangeNotifierProvider.
class RAGViewModel extends ChangeNotifier {
  // MARK: - Document State

  String? _documentName;
  String? get documentName => _documentName;

  bool _isDocumentLoaded = false;
  bool get isDocumentLoaded => _isDocumentLoaded;

  bool _isLoadingDocument = false;
  bool get isLoadingDocument => _isLoadingDocument;

  // MARK: - Query State

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

  // MARK: - Input

  String _currentQuestion = '';
  String get currentQuestion => _currentQuestion;
  set currentQuestion(String value) {
    _currentQuestion = value;
    notifyListeners();
  }

  // MARK: - Last Result

  RAGResult? _lastResult;
  RAGResult? get lastResult => _lastResult;

  // MARK: - Computed Properties

  bool get canAskQuestion =>
      _isDocumentLoaded &&
      !_isQuerying &&
      _currentQuestion.trim().isNotEmpty;

  // MARK: - Public Methods

  /// Load a document: extract text, create RAG pipeline, ingest text.
  ///
  /// [filePath] - Absolute path to the document (PDF or JSON).
  /// [config] - RAG pipeline configuration with model paths and tuning parameters.
  Future<void> loadDocument(String filePath, RAGConfiguration config) async {
    _isLoadingDocument = true;
    _error = null;
    notifyListeners();

    try {
      final extractedText = await DocumentService.extractText(filePath);

      await RunAnywhereRAG.ragCreatePipeline(config);
      await RunAnywhereRAG.ragIngest(extractedText);

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

    _messages = [..._messages, RAGMessage(role: RAGMessageRole.user, text: question)];
    _currentQuestion = '';
    _isQuerying = true;
    _error = null;
    notifyListeners();

    try {
      final result = await RunAnywhereRAG.ragQuery(question);

      _messages = [
        ..._messages,
        RAGMessage(role: RAGMessageRole.assistant, text: result.answer, result: result),
      ];
      _lastResult = result;
    } catch (e) {
      _error = e.toString();
      _messages = [
        ..._messages,
        RAGMessage(role: RAGMessageRole.assistant, text: 'Error: $e'),
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
    await RunAnywhereRAG.ragDestroyPipeline();

    _documentName = null;
    _isDocumentLoaded = false;
    _messages = [];
    _error = null;
    _currentQuestion = '';
    _lastResult = null;
    notifyListeners();
  }
}
