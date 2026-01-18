import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/core/services/conversation_store.dart';
import 'package:runanywhere_ai/core/utilities/constants.dart';
import 'package:runanywhere_ai/features/models/model_selection_sheet.dart';
import 'package:runanywhere_ai/features/models/model_status_components.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ChatInterfaceView (mirroring iOS ChatInterfaceView.swift)
///
/// Full chat interface with streaming, analytics, and model status.
class ChatInterfaceView extends StatefulWidget {
  const ChatInterfaceView({super.key});

  @override
  State<ChatInterfaceView> createState() => _ChatInterfaceViewState();
}

class _ChatInterfaceViewState extends State<ChatInterfaceView> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // Messages
  final List<ChatMessage> _messages = [];
  String _currentStreamingContent = '';
  String _currentThinkingContent = '';

  // State
  bool _isGenerating = false;
  bool _useStreaming = true;
  String? _errorMessage;
  bool _isLoading = false;

  // Model state (from SDK - matches Swift pattern)
  String? _loadedModelName;
  sdk.InferenceFramework? _loadedFramework;

  // Analytics
  DateTime? _generationStartTime;
  double? _timeToFirstToken;
  int _tokenCount = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
    unawaited(_syncModelState());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useStreaming = prefs.getBool(PreferenceKeys.useStreaming) ?? true;
    });
  }

  /// Sync model state from SDK (matches Swift pattern)
  Future<void> _syncModelState() async {
    final model = await sdk.RunAnywhere.currentLLMModel();
    if (mounted) {
      setState(() {
        _loadedModelName = model?.name;
        _loadedFramework = model?.framework;
      });
    }
  }

  bool get _canSend =>
      _controller.text.isNotEmpty &&
      !_isGenerating &&
      sdk.RunAnywhere.isModelLoaded;

  Future<void> _sendMessage() async {
    if (!_canSend) return;

    final userMessage = _controller.text;
    _controller.clear();

    setState(() {
      _messages.add(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.user,
        content: userMessage,
        timestamp: DateTime.now(),
      ));
      _isGenerating = true;
      _errorMessage = null;
      _currentStreamingContent = '';
      _currentThinkingContent = '';
      _generationStartTime = DateTime.now();
      _timeToFirstToken = null;
      _tokenCount = 0;
    });

    _scrollToBottom();

    try {
      // Get generation options from settings
      final prefs = await SharedPreferences.getInstance();
      final temperature =
          prefs.getDouble(PreferenceKeys.defaultTemperature) ?? 0.7;
      final maxTokens = prefs.getInt(PreferenceKeys.defaultMaxTokens) ?? 500;

      // Streaming now runs in a background isolate, so no ANR concerns
      final options = sdk.LLMGenerationOptions(
        maxTokens: maxTokens,
        temperature: temperature,
      );

      if (_useStreaming) {
        await _generateStreaming(userMessage, options);
      } else {
        await _generateNonStreaming(userMessage, options);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Generation failed: $e';
        _isGenerating = false;
      });
    }
  }

  Future<void> _generateStreaming(
    String prompt,
    sdk.LLMGenerationOptions options,
  ) async {
    // Capture model name from local state (matches Swift pattern)
    final modelName = _loadedModelName;

    // Add empty assistant message for streaming
    final assistantMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(assistantMessage);
    });

    final messageIndex = _messages.length - 1;
    final contentBuffer = StringBuffer();

    try {
      final streamingResult =
          await sdk.RunAnywhere.generateStream(prompt, options: options);

      await for (final token in streamingResult.stream) {
        if (_timeToFirstToken == null && _generationStartTime != null) {
          _timeToFirstToken =
              DateTime.now().difference(_generationStartTime!).inMilliseconds /
                  1000.0;
        }

        _tokenCount++;
        contentBuffer.write(token);
        _currentStreamingContent = contentBuffer.toString();

        setState(() {
          _messages[messageIndex] = _messages[messageIndex].copyWith(
            content: _currentStreamingContent,
          );
        });

        _scrollToBottom();
      }

      // Calculate final analytics
      final totalTime = _generationStartTime != null
          ? DateTime.now().difference(_generationStartTime!).inMilliseconds /
              1000.0
          : 0.0;

      final analytics = MessageAnalytics(
        messageId: assistantMessage.id,
        modelName: modelName,
        timeToFirstToken: _timeToFirstToken,
        totalGenerationTime: totalTime,
        outputTokens: _tokenCount,
        tokensPerSecond: totalTime > 0 ? _tokenCount / totalTime : 0,
      );

      if (!mounted) return;
      setState(() {
        _messages[messageIndex] = _messages[messageIndex].copyWith(
          thinkingContent: _currentThinkingContent.isNotEmpty
              ? _currentThinkingContent
              : null,
          analytics: analytics,
        );
        _isGenerating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.removeLast();
        _errorMessage = 'Streaming failed: $e';
        _isGenerating = false;
      });
    }
  }

  Future<void> _generateNonStreaming(
    String prompt,
    sdk.LLMGenerationOptions options,
  ) async {
    // Capture model name from local state (matches Swift pattern)
    final modelName = _loadedModelName;

    try {
      final result = await sdk.RunAnywhere.generate(prompt, options: options);

      final totalTime = _generationStartTime != null
          ? DateTime.now().difference(_generationStartTime!).inMilliseconds /
              1000.0
          : 0.0;

      // Extract token counts from SDK result
      final outputTokens = result.tokensUsed;
      final tokensPerSecond = result.tokensPerSecond;

      final analytics = MessageAnalytics(
        messageId: DateTime.now().millisecondsSinceEpoch.toString(),
        modelName: modelName,
        totalGenerationTime: totalTime,
        outputTokens: outputTokens,
        tokensPerSecond: tokensPerSecond,
      );

      setState(() {
        _messages.add(ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          role: MessageRole.assistant,
          content: result.text,
          thinkingContent: result.thinkingContent,
          timestamp: DateTime.now(),
          analytics: analytics,
        ));
        _isGenerating = false;
      });

      _scrollToBottom();
    } catch (e) {
      setState(() {
        _errorMessage = 'Generation failed: $e';
        _isGenerating = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        unawaited(_scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: AppLayout.animationFast,
          curve: Curves.easeOut,
        ));
      }
    });
  }

  void _clearChat() {
    setState(() {
      _messages.clear();
      _errorMessage = null;
      _currentStreamingContent = '';
      _currentThinkingContent = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearChat,
              tooltip: 'Clear chat',
            ),
        ],
      ),
      body: Column(
        children: [
          // Model status banner (uses local state from SDK)
          _buildModelStatusBanner(),

          // Messages area - tap to dismiss keyboard
          Expanded(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.opaque,
              child: _buildMessagesArea(),
            ),
          ),

          // Error banner
          if (_errorMessage != null) _buildErrorBanner(),

          // Typing indicator
          if (_isGenerating) _buildTypingIndicator(),

          // Input area
          _buildInputArea(),
        ],
      ),
    );
  }

  void _showModelSelectionSheet() {
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => ModelSelectionSheet(
        context: ModelSelectionContext.llm,
        onModelSelected: (model) async {
          // Model loaded by ModelSelectionSheet via SDK
          // Sync local state after model load
          await _syncModelState();
        },
      ),
    ));
  }

  /// Map SDK InferenceFramework enum to app framework enum
  LLMFramework _mapInferenceFramework(sdk.InferenceFramework? framework) {
    if (framework == null) return LLMFramework.llamaCpp;
    switch (framework) {
      case sdk.InferenceFramework.llamaCpp:
        return LLMFramework.llamaCpp;
      case sdk.InferenceFramework.foundationModels:
        return LLMFramework.foundationModels;
      case sdk.InferenceFramework.onnx:
        return LLMFramework.onnxRuntime;
      case sdk.InferenceFramework.systemTTS:
        return LLMFramework.systemTTS;
      default:
        return LLMFramework.llamaCpp;
    }
  }

  Widget _buildModelStatusBanner() {
    // Use local state synced from SDK (matches Swift pattern)
    LLMFramework? framework;
    if (sdk.RunAnywhere.isModelLoaded && _loadedFramework != null) {
      framework = _mapInferenceFramework(_loadedFramework);
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: ModelStatusBanner(
        framework: framework,
        modelName: _loadedModelName,
        isLoading: _isLoading,
        onSelectModel: _showModelSelectionSheet,
      ),
    );
  }

  Widget _buildMessagesArea() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.psychology,
              size: AppSpacing.iconXXLarge,
              color: AppColors.textSecondary(context),
            ),
            const SizedBox(height: AppSpacing.large),
            Text(
              'Start a conversation',
              style: AppTypography.title2(context),
            ),
            const SizedBox(height: AppSpacing.smallMedium),
            Text(
              'Type a message to begin',
              style: AppTypography.subheadline(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.large),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _MessageBubble(message: message);
      },
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.all(AppSpacing.large),
      padding: const EdgeInsets.all(AppSpacing.mediumLarge),
      decoration: BoxDecoration(
        color: AppColors.badgeRed,
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
      ),
      child: Row(
        children: [
          const Icon(Icons.error, color: Colors.red),
          const SizedBox(width: AppSpacing.smallMedium),
          Expanded(
            child: Text(
              _errorMessage!,
              style: AppTypography.subheadline(context),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() {
                _errorMessage = null;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return const TypingIndicatorView(
      statusText: 'AI is thinking...',
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.backgroundPrimary(context),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: AppSpacing.shadowLarge,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppSpacing.cornerRadiusBubble),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.large,
                    vertical: AppSpacing.mediumLarge,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: AppSpacing.smallMedium),
            IconButton.filled(
              onPressed: _canSend ? _sendMessage : null,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.arrow_upward),
            ),
          ],
        ),
      ),
    );
  }
}

/// Message role enum
enum MessageRole { system, user, assistant }

/// Chat message model
class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final String? thinkingContent;
  final DateTime timestamp;
  final MessageAnalytics? analytics;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.thinkingContent,
    required this.timestamp,
    this.analytics,
  });

  ChatMessage copyWith({
    String? id,
    MessageRole? role,
    String? content,
    String? thinkingContent,
    DateTime? timestamp,
    MessageAnalytics? analytics,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      thinkingContent: thinkingContent ?? this.thinkingContent,
      timestamp: timestamp ?? this.timestamp,
      analytics: analytics ?? this.analytics,
    );
  }
}

/// Message bubble widget
class _MessageBubble extends StatefulWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _showThinking = false;

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == MessageRole.user;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.mediumLarge),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Thinking section (if present)
            if (widget.message.thinkingContent != null &&
                widget.message.thinkingContent!.isNotEmpty)
              _buildThinkingSection(),

            // Main message bubble
            Container(
              padding: const EdgeInsets.all(AppSpacing.mediumLarge),
              decoration: BoxDecoration(
                gradient: isUser
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.userBubbleGradientStart,
                          AppColors.userBubbleGradientEnd,
                        ],
                      )
                    : null,
                color: isUser ? null : AppColors.backgroundGray5(context),
                borderRadius:
                    BorderRadius.circular(AppSpacing.cornerRadiusBubble),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadowLight,
                    blurRadius: AppSpacing.shadowSmall,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: isUser
                  ? Text(
                      widget.message.content,
                      style: AppTypography.body(context).copyWith(
                        color: AppColors.textWhite,
                      ),
                    )
                  : MarkdownBody(
                      data: widget.message.content,
                      styleSheet: MarkdownStyleSheet(
                        p: AppTypography.body(context),
                        code: AppTypography.monospaced.copyWith(
                          backgroundColor: AppColors.backgroundGray6(context),
                        ),
                      ),
                    ),
            ),

            // Analytics summary (if present)
            if (widget.message.analytics != null && !isUser)
              _buildAnalyticsSummary(),
          ],
        ),
      ),
    );
  }

  Widget _buildThinkingSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.smallMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _showThinking = !_showThinking;
              });
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lightbulb,
                  size: AppSpacing.iconRegular,
                  color: AppColors.primaryPurple,
                ),
                const SizedBox(width: AppSpacing.xSmall),
                Text(
                  _showThinking ? 'Hide reasoning' : 'Show reasoning',
                  style: AppTypography.caption(context).copyWith(
                    color: AppColors.primaryPurple,
                  ),
                ),
                Icon(
                  _showThinking
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: AppSpacing.iconRegular,
                  color: AppColors.primaryPurple,
                ),
              ],
            ),
          ),
          if (_showThinking)
            Container(
              margin: const EdgeInsets.only(top: AppSpacing.smallMedium),
              padding: const EdgeInsets.all(AppSpacing.mediumLarge),
              decoration: BoxDecoration(
                color: AppColors.modelThinkingBg,
                borderRadius:
                    BorderRadius.circular(AppSpacing.cornerRadiusRegular),
              ),
              child: Text(
                widget.message.thinkingContent!,
                style: AppTypography.caption(context),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsSummary() {
    final analytics = widget.message.analytics!;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xSmall),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (analytics.totalGenerationTime != null)
            Text(
              '${analytics.totalGenerationTime!.toStringAsFixed(1)}s',
              style: AppTypography.caption(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          if (analytics.tokensPerSecond != null) ...[
            const SizedBox(width: AppSpacing.smallMedium),
            Text(
              '${analytics.tokensPerSecond!.toStringAsFixed(1)} tok/s',
              style: AppTypography.caption(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
          if (analytics.wasThinkingMode) ...[
            const SizedBox(width: AppSpacing.smallMedium),
            const Icon(
              Icons.lightbulb,
              size: 12,
              color: AppColors.primaryPurple,
            ),
          ],
        ],
      ),
    );
  }
}
