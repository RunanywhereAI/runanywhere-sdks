// RAG View Model
//
// Coordinates document extraction, SDK pipeline lifecycle, and query state.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart' hide ModelInfo;
import 'package:runanywhere/runanywhere_protos.dart' as proto;
import 'package:runanywhere_ai/core/utilities/constants.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';
import 'package:runanywhere_ai/features/rag/document_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A single message in the RAG conversation.
///
/// User messages contain only text. Assistant messages also carry
/// the [RagResult] for displaying retrieved chunks and metrics.
class RAGMessage {
  final proto.MessageRole role;
  final String text;

  /// The RAG result associated with this assistant message.
  /// Null for user messages and error messages.
  final RagResult? result;

  const RAGMessage({required this.role, required this.text, this.result});
}

/// ViewModel managing the full RAG pipeline lifecycle, document state, and query flow.
///
/// Exposes observable state via ChangeNotifier for ListenableBuilder.
class RAGViewModel extends ChangeNotifier {
  String? _documentName;
  String? get documentName => _documentName;

  bool _isDocumentLoaded = false;
  bool get isDocumentLoaded => _isDocumentLoaded;
  bool _llmSupportsThinking = false;

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

  RagResult? _lastResult;
  RagResult? get lastResult => _lastResult;

  RagSession? _session;


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

      await _session?.close();
      final session = await RunAnywhere.rag.open(
        embeddingModel: ModelRef(embeddingModel.id),
        llmModel: ModelRef(llmModel.id),
      );
      _session = session;
      await session.ingest(RagDocument(extractedText));

      _documentName = File(filePath).uri.pathSegments.last;
      _isDocumentLoaded = true;
      _llmSupportsThinking = llmModel.supportsThinking;
    } catch (e) {
      _error = e.toString();
      // Tear down any partially-created session so a failed ingest doesn't
      // leave an orphaned native index behind.
      await _session?.close();
      _session = null;
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
      RAGMessage(role: proto.MessageRole.MESSAGE_ROLE_USER, text: question),
    ];
    _currentQuestion = '';
    _isQuerying = true;
    _error = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final thinkingModeEnabled =
          prefs.getBool(PreferenceKeys.thinkingModeEnabled) ?? true;
      // RAG answers never render thinking, so a thinking-capable model with
      // the toggle off gets reasoning explicitly switched off; otherwise the
      // pipeline defaults apply (thoughts stripped from the answer).
      final session = _session;
      if (session == null) {
        throw StateError('No RAG session is open');
      }
      final result = await session.query(
        question,
        options: _llmSupportsThinking && !thinkingModeEnabled
            ? LlmOptions(
                reasoning: const ReasoningOptions(
                  mode: ReasoningMode.REASONING_MODE_OFF,
                ),
              )
            : null,
      );

      _messages = [
        ..._messages,
        RAGMessage(
          role: proto.MessageRole.MESSAGE_ROLE_ASSISTANT,
          text: result.answer,
          result: result,
        ),
      ];
      _lastResult = result;
    } catch (e) {
      _error = e.toString();
      _messages = [
        ..._messages,
        RAGMessage(
          role: proto.MessageRole.MESSAGE_ROLE_ASSISTANT,
          text: 'Error: $e',
        ),
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
    await _session?.close();
    _session = null;

    _documentName = null;
    _isDocumentLoaded = false;
    _messages = [];
    _error = null;
    _currentQuestion = '';
    _lastResult = null;
    _llmSupportsThinking = false;
    notifyListeners();
  }

  @override
  void dispose() {
    // Close the session so its native index isn't leaked when the screen is
    // popped without an explicit clearDocument(). dispose() is sync.
    unawaited(_session?.close());
    _session = null;
    super.dispose();
  }
}
