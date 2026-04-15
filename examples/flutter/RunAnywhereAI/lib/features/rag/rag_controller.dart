import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runanywhere_ai/data/models/chat_message.dart';

enum RagDocumentStatus { none, loading, loaded, error }

class RagState {
  const RagState({
    this.documentStatus = RagDocumentStatus.none,
    this.documentName,
    this.messages = const [],
    this.isQuerying = false,
    this.streamingContent = '',
    this.errorMessage,
  });

  final RagDocumentStatus documentStatus;
  final String? documentName;
  final List<ChatMessage> messages;
  final bool isQuerying;
  final String streamingContent;
  final String? errorMessage;

  bool get hasDocument => documentStatus == RagDocumentStatus.loaded;

  RagState copyWith({
    RagDocumentStatus? documentStatus,
    String? documentName,
    List<ChatMessage>? messages,
    bool? isQuerying,
    String? streamingContent,
    String? errorMessage,
    bool clearError = false,
  }) {
    return RagState(
      documentStatus: documentStatus ?? this.documentStatus,
      documentName: documentName ?? this.documentName,
      messages: messages ?? this.messages,
      isQuerying: isQuerying ?? this.isQuerying,
      streamingContent: streamingContent ?? this.streamingContent,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final ragControllerProvider =
    NotifierProvider<RagController, RagState>(RagController.new);

class RagController extends Notifier<RagState> {
  @override
  RagState build() => const RagState();

  Future<void> loadDocument(String path, String name) async {
    state = state.copyWith(
      documentStatus: RagDocumentStatus.loading,
      clearError: true,
    );

    try {
      // SDK RAG document loading would go here
      state = state.copyWith(
        documentStatus: RagDocumentStatus.loaded,
        documentName: name,
      );
    } on Exception catch (e) {
      state = state.copyWith(
        documentStatus: RagDocumentStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> query(String question) async {
    if (question.trim().isEmpty || state.isQuerying) return;

    final userMsg = ChatMessage(role: MessageRole.user, content: question);
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isQuerying: true,
      streamingContent: '',
      clearError: true,
    );

    try {
      // SDK RAG query would go here
      // Placeholder until SDK wiring:
      final assistantMsg = ChatMessage(
        role: MessageRole.assistant,
        content: 'RAG query response will appear here once SDK is wired.',
      );
      state = state.copyWith(
        messages: [...state.messages, assistantMsg],
        isQuerying: false,
      );
    } on Exception catch (e) {
      state = state.copyWith(isQuerying: false, errorMessage: e.toString());
    }
  }

  void clearChat() => state = state.copyWith(messages: []);
}
