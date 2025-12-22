import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:runanywhere/runanywhere.dart' hide LLMFramework;
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/core/services/conversation_store.dart';
import 'package:runanywhere_ai/core/services/model_manager.dart';
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
  // TODO: Use when SDK supports thinking content in streaming
  // ignore:unused_field
  String _currentThinkingContent = '';

  // State
  bool _isGenerating = false;
  bool _useStreaming = true;
  String? _errorMessage;

  // Analytics
  DateTime? _generationStartTime;
  double? _timeToFirstToken;
  int _tokenCount = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
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

  bool get _canSend =>
      _controller.text.isNotEmpty &&
      !_isGenerating &&
      context.read<ModelManager>().isModelLoaded;

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

      final options = RunAnywhereGenerationOptions(
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
    RunAnywhereGenerationOptions options,
  ) async {
    // Capture model name before async gap to avoid context issues
    final modelName = context.read<ModelManager>().loadedModelName;

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

    try {
      // TODO: Use RunAnywhere.generateStream with thinking support
      // final stream = RunAnywhere.generateStream(prompt, options: options);
      // await for (final token in stream) { ... }

      // Placeholder streaming simulation
      final stream = RunAnywhere.generateStream(prompt, options: options);

      await for (final token in stream) {
        if (_timeToFirstToken == null && _generationStartTime != null) {
          _timeToFirstToken =
              DateTime.now().difference(_generationStartTime!).inMilliseconds /
                  1000.0;
        }

        _tokenCount++;
        // ignore: use_string_buffers, simpler for streaming UI updates
        _currentStreamingContent += token;

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
    RunAnywhereGenerationOptions options,
  ) async {
    // Capture model name before async gap to avoid context issues
    final modelName = context.read<ModelManager>().loadedModelName;

    try {
      final result = await RunAnywhere.generate(prompt, options: options);

      final totalTime = _generationStartTime != null
          ? DateTime.now().difference(_generationStartTime!).inMilliseconds /
              1000.0
          : 0.0;

      final analytics = MessageAnalytics(
        messageId: DateTime.now().millisecondsSinceEpoch.toString(),
        modelName: modelName,
        totalGenerationTime: totalTime,
        // TODO: Extract token counts from result
      );

      setState(() {
        _messages.add(ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          role: MessageRole.assistant,
          content: result.text,
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
    final modelManager = context.watch<ModelManager>();

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
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // TODO: Show chat settings
            },
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          // Model status banner
          _buildModelStatusBanner(modelManager),

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
          _buildInputArea(modelManager),
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
          // Model is loaded by ModelSelectionSheet via SDK
          // UI will update via ModelManager listener
        },
      ),
    ));
  }

  Widget _buildModelStatusBanner(ModelManager modelManager) {
    // Map ModelManager state to LLMFramework for the shared component
    LLMFramework? framework;
    if (modelManager.isModelLoaded) {
      // TODO: Get actual framework from ModelManager when SDK provides it
      framework = LLMFramework.llamaCpp;
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: ModelStatusBanner(
        framework: framework,
        modelName: modelManager.loadedModelName,
        isLoading: modelManager.isLoading,
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

  Widget _buildInputArea(ModelManager modelManager) {
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
