import 'package:runanywhere_ai/data/models/chat_message.dart';

class ChatState {
  const ChatState({
    this.messages = const [],
    this.isGenerating = false,
    this.streamingContent = '',
    this.thinkingContent = '',
    this.errorMessage,
    this.loadedModelName,
    this.loadedFramework,
    this.useStreaming = true,
    this.systemPrompt = 'You are a helpful AI assistant.',
    this.temperature = 0.8,
    this.maxTokens = 512,
  });

  final List<ChatMessage> messages;
  final bool isGenerating;
  final String streamingContent;
  final String thinkingContent;
  final String? errorMessage;
  final String? loadedModelName;
  final String? loadedFramework;
  final bool useStreaming;
  final String systemPrompt;
  final double temperature;
  final int maxTokens;

  bool get hasModel => loadedModelName != null;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isGenerating,
    String? streamingContent,
    String? thinkingContent,
    String? errorMessage,
    String? loadedModelName,
    String? loadedFramework,
    bool? useStreaming,
    String? systemPrompt,
    double? temperature,
    int? maxTokens,
    bool clearError = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isGenerating: isGenerating ?? this.isGenerating,
      streamingContent: streamingContent ?? this.streamingContent,
      thinkingContent: thinkingContent ?? this.thinkingContent,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      loadedModelName: loadedModelName ?? this.loadedModelName,
      loadedFramework: loadedFramework ?? this.loadedFramework,
      useStreaming: useStreaming ?? this.useStreaming,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
    );
  }
}
