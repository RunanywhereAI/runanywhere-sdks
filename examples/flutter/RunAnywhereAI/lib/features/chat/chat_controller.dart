import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere/public/types/generation_types.dart';
import 'package:runanywhere_ai/data/models/chat_message.dart';
import 'package:runanywhere_ai/features/chat/chat_state.dart';

final chatControllerProvider =
    NotifierProvider<ChatController, ChatState>(ChatController.new);

class ChatController extends Notifier<ChatState> {
  @override
  ChatState build() {
    _syncModelState();
    return const ChatState();
  }

  Future<void> _syncModelState() async {
    final model = await sdk.RunAnywhere.currentLLMModel();
    if (model != null) {
      state = state.copyWith(
        loadedModelName: model.name,
        loadedFramework: model.framework.name,
      );
    }
  }

  Future<void> refreshModelState() async => _syncModelState();

  void clearError() => state = state.copyWith(clearError: true);

  void clearChat() => state = state.copyWith(messages: []);

  void setStreaming({required bool enabled}) =>
      state = state.copyWith(useStreaming: enabled);

  void setSystemPrompt(String prompt) =>
      state = state.copyWith(systemPrompt: prompt);

  void setTemperature(double temp) =>
      state = state.copyWith(temperature: temp);

  void setMaxTokens(int tokens) =>
      state = state.copyWith(maxTokens: tokens);

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || state.isGenerating) return;

    final userMessage = ChatMessage(role: MessageRole.user, content: text);
    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isGenerating: true,
      streamingContent: '',
      thinkingContent: '',
      clearError: true,
    );

    try {
      if (state.useStreaming) {
        await _generateStreaming(text);
      } else {
        await _generateNonStreaming(text);
      }
    } on Exception catch (e) {
      state = state.copyWith(
        isGenerating: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _generateStreaming(String prompt) async {
    final stopwatch = Stopwatch()..start();
    double? timeToFirstToken;
    final buffer = StringBuffer();
    var tokenCount = 0;

    final options = LLMGenerationOptions(
      maxTokens: state.maxTokens,
      temperature: state.temperature,
      systemPrompt: state.systemPrompt,
      streamingEnabled: true,
    );

    final streamingResult = await sdk.RunAnywhere.generateStream(
      prompt,
      options: options,
    );

    await for (final token in streamingResult.stream) {
      tokenCount++;
      timeToFirstToken ??= stopwatch.elapsedMilliseconds.toDouble();
      buffer.write(token);
      state = state.copyWith(streamingContent: buffer.toString());
    }

    stopwatch.stop();
    final totalMs = stopwatch.elapsedMilliseconds.toDouble();
    final tokensPerSec = totalMs > 0 ? (tokenCount / totalMs) * 1000 : 0.0;

    final assistantMessage = ChatMessage(
      role: MessageRole.assistant,
      content: buffer.toString(),
      analytics: MessageAnalytics(
        timeToFirstTokenMs: timeToFirstToken,
        totalGenerationMs: totalMs,
        outputTokens: tokenCount,
        tokensPerSecond: tokensPerSec,
      ),
    );

    state = state.copyWith(
      messages: [...state.messages, assistantMessage],
      isGenerating: false,
      streamingContent: '',
    );
  }

  Future<void> _generateNonStreaming(String prompt) async {
    final options = LLMGenerationOptions(
      maxTokens: state.maxTokens,
      temperature: state.temperature,
      systemPrompt: state.systemPrompt,
    );

    final result = await sdk.RunAnywhere.generate(prompt, options: options);

    final assistantMessage = ChatMessage(
      role: MessageRole.assistant,
      content: result.text,
      thinkingContent: result.thinkingContent,
      analytics: MessageAnalytics(
        totalGenerationMs: result.latencyMs,
        outputTokens: result.tokensUsed,
        tokensPerSecond: result.tokensPerSecond,
      ),
    );

    state = state.copyWith(
      messages: [...state.messages, assistantMessage],
      isGenerating: false,
    );
  }

  Future<void> cancelGeneration() async {
    await sdk.RunAnywhere.cancelGeneration();
    state = state.copyWith(isGenerating: false);
  }
}
