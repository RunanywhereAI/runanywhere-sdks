import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/core/services/conversation_store.dart';
import 'package:runanywhere_ai/features/chat/chat_lora_sheet.dart';
import 'package:runanywhere_ai/features/chat/chat_view_model.dart';
import 'package:runanywhere_ai/features/chat/tool_call_views.dart';
import 'package:runanywhere_ai/features/models/model_selection_sheet.dart';
import 'package:runanywhere_ai/features/models/model_status_components.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';
import 'package:runanywhere_ai/features/rag/rag_demo_view.dart';
import 'package:runanywhere_ai/features/settings/tool_settings_view_model.dart';

/// ChatInterfaceView
///
/// Full chat interface with streaming, analytics, and model status.
/// UI-only: all chat/model/LoRA state lives in [ChatViewModel].
class ChatInterfaceView extends StatefulWidget {
  const ChatInterfaceView({super.key});

  @override
  State<ChatInterfaceView> createState() => _ChatInterfaceViewState();
}

class _ChatInterfaceViewState extends State<ChatInterfaceView> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  late final ChatViewModel _viewModel;
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _viewModel = ChatViewModel();
    _viewModel.addListener(_onViewModelChanged);
    unawaited(_viewModel.initialize());
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Keep the list pinned to the bottom while messages arrive or stream.
  void _onViewModelChanged() {
    final messageCount = _viewModel.messages.length;
    if (messageCount != _lastMessageCount || _viewModel.isGenerating) {
      _lastMessageCount = messageCount;
      _scrollToBottom();
    }
  }

  bool get _canSend => _viewModel.canSend(_controller.text);

  Future<void> _sendMessage() async {
    final text = _controller.text;
    if (!_viewModel.canSend(text)) return;
    _controller.clear();
    _scrollToBottom();
    await _viewModel.sendMessage(text);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        unawaited(
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: AppLayout.animationFast,
            curve: Curves.easeOut,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Chat'),
          actions: [
            IconButton(
              icon: const Icon(Icons.history),
              onPressed: _showConversationHistory,
              tooltip: 'Conversation history',
            ),
            if (_viewModel.loadedModelSupportsLora)
              IconButton(
                icon: const Icon(Icons.auto_awesome),
                onPressed: _showLoRASheet,
                tooltip: 'LoRA adapters',
              ),
            Semantics(
              label: 'Document Q&A',
              button: true,
              child: IconButton(
                icon: const Icon(Icons.article_outlined),
                onPressed: () {
                  unawaited(
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (context) => const RagDemoView(),
                      ),
                    ),
                  );
                },
                tooltip: 'Document Q&A',
              ),
            ),
            if (_viewModel.messages.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _viewModel.clearChat,
                tooltip: 'Clear chat',
              ),
          ],
        ),
        body: Column(
          children: [
            // Model status banner (state synced from SDK by the ViewModel)
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
            if (_viewModel.errorMessage != null) _buildErrorBanner(),

            // Typing indicator
            if (_viewModel.isGenerating) _buildTypingIndicator(),

            // Input area
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  void _showModelSelectionSheet() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => ModelSelectionSheet(
          context: ModelSelectionContext.llm,
          onModelSelected: (model) async {
            // Model loaded by ModelSelectionSheet via SDK
            await _viewModel.syncModelState();
          },
        ),
      ),
    );
  }

  /// Show the LoRA adapter sheet (visible when the loaded model supports LoRA).
  void _showLoRASheet() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => ChatLoRASheet(viewModel: _viewModel),
      ),
    );
  }

  /// Show conversation history bottom sheet driven by ConversationStore.
  void _showConversationHistory() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => _ConversationListSheet(
          store: ConversationStore.shared,
          onNewChat: () {
            Navigator.of(sheetContext).pop();
            _viewModel.clearChat();
          },
          onSelect: (conversation) {
            Navigator.of(sheetContext).pop();
            _viewModel.loadConversation(conversation);
          },
        ),
      ),
    );
  }

  /// Map SDK InferenceFramework to LLMFramework (identity — both are the same type).
  LLMFramework _mapInferenceFramework(sdk.InferenceFramework? framework) =>
      framework ?? LLMFramework.INFERENCE_FRAMEWORK_UNKNOWN;

  Widget _buildModelStatusBanner() {
    if (_viewModel.isUsingHostedModel) {
      final state = _viewModel.connectState;
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusCard),
          ),
          tileColor: AppColors.backgroundGray6(context),
          leading: const Icon(Icons.desktop_windows_outlined),
          title: Text(
            state.activeModel?.displayName ?? 'Hosted model',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            'Host · ${state.activeHost?.displayName ?? 'Connected'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: TextButton(
            onPressed: _showModelSelectionSheet,
            child: const Text('Change'),
          ),
        ),
      );
    }
    LLMFramework? framework;
    if (_viewModel.isModelLoaded && _viewModel.loadedFramework != null) {
      framework = _mapInferenceFramework(_viewModel.loadedFramework);
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: ModelStatusBanner(
        framework: framework,
        modelName: _viewModel.loadedModelName,
        isLoading: false,
        onSelectModel: _showModelSelectionSheet,
      ),
    );
  }

  Widget _buildMessagesArea() {
    final messages = _viewModel.messages;
    if (messages.isEmpty) {
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
            Text('Start a conversation', style: AppTypography.title2(context)),
            const SizedBox(height: AppSpacing.smallMedium),
            Text(
              'Type a message to begin',
              style: AppTypography.subheadline(
                context,
              ).copyWith(color: AppColors.textSecondary(context)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.large),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
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
              _viewModel.errorMessage!,
              style: AppTypography.subheadline(context),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _viewModel.clearError,
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return const TypingIndicatorView(statusText: 'AI is thinking...');
  }

  /// Heuristic check for small models (<= ~500M params) where tool
  /// calling tends to be unreliable. Used by the tool-calling reliability
  /// banner.
  bool _isLikelySmallModel(String? name) {
    if (name == null) return false;
    final n = name.toLowerCase();
    return n.contains('0.3b') ||
        n.contains('0.5b') ||
        n.contains('0.6b') ||
        n.contains('350m') ||
        n.contains('360m') ||
        n.contains('500m');
  }

  Widget _buildInputArea() {
    final toolSettings = ToolSettingsViewModel.shared;
    final showToolBadge =
        toolSettings.toolCallingEnabled &&
        toolSettings.registeredTools.isNotEmpty;
    final showSmallModelWarning =
        toolSettings.toolCallingEnabled &&
        _isLikelySmallModel(_viewModel.loadedModelName);

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tool-calling reliability banner for small models.
            if (showSmallModelWarning) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.smallMedium),
                margin: const EdgeInsets.only(bottom: AppSpacing.smallMedium),
                decoration: BoxDecoration(
                  color: AppColors.primaryOrange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(
                    AppSpacing.cornerRadiusRegular,
                  ),
                  border: Border.all(
                    color: AppColors.primaryOrange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: AppColors.primaryOrange,
                    ),
                    const SizedBox(width: AppSpacing.smallMedium),
                    Expanded(
                      child: Text(
                        'For reliable tool calling, use a 1.2B+ instruct-tuned model.',
                        style: AppTypography.caption(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Tool calling badge
            if (showToolBadge) ...[
              ToolCallingBadge(toolCount: toolSettings.registeredTools.length),
              const SizedBox(height: AppSpacing.smallMedium),
            ],
            Row(
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
                        borderRadius: BorderRadius.circular(
                          AppSpacing.cornerRadiusBubble,
                        ),
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
                  onPressed: _viewModel.isGenerating
                      ? _viewModel.stopGeneration
                      : (_canSend ? _sendMessage : null),
                  icon: _viewModel.isGenerating
                      ? const Icon(Icons.stop)
                      : const Icon(Icons.arrow_upward),
                ),
              ],
            ),
          ],
        ),
      ),
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
    final isUser = widget.message.role == sdk.MessageRole.MESSAGE_ROLE_USER;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.mediumLarge),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            // Tool call indicator (if present, matches iOS toolCallSection)
            if (widget.message.toolCallInfo != null && !isUser) ...[
              ToolCallIndicator(
                toolCallInfo: widget.message.toolCallInfo!,
                onTap: () => _showToolCallDetails(context),
              ),
              const SizedBox(height: AppSpacing.smallMedium),
            ],

            // Thinking section (if present)
            if (widget.message.thinkingContent != null &&
                widget.message.thinkingContent!.isNotEmpty)
              _buildThinkingSection(),

            // Main message bubble. Long-press an assistant bubble to
            // open an analytics sheet.
            GestureDetector(
              onLongPress: !isUser && widget.message.analytics != null
                  ? () => _showAnalyticsSheet(context)
                  : null,
              child: Container(
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
                  borderRadius: BorderRadius.circular(
                    AppSpacing.cornerRadiusBubble,
                  ),
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
                        style: AppTypography.body(
                          context,
                        ).copyWith(color: AppColors.textWhite),
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
            ),

            // Analytics summary (if present)
            if (widget.message.analytics != null && !isUser)
              _buildAnalyticsSummary(),
          ],
        ),
      ),
    );
  }

  void _showToolCallDetails(BuildContext context) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, scrollController) =>
              ToolCallDetailSheet(toolCallInfo: widget.message.toolCallInfo!),
        ),
      ),
    );
  }

  /// Show a bottom sheet of message analytics.
  void _showAnalyticsSheet(BuildContext context) {
    final analytics = widget.message.analytics;
    if (analytics == null) return;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: false,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(AppSpacing.large),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Generation analytics',
                style: AppTypography.title3(context),
              ),
              const SizedBox(height: AppSpacing.mediumLarge),
              if (analytics.modelName != null)
                _analyticsRow('Model', analytics.modelName!),
              if (analytics.timeToFirstToken != null)
                _analyticsRow(
                  'Time to first token',
                  '${analytics.timeToFirstToken!.toStringAsFixed(2)} s',
                ),
              if (analytics.totalGenerationTime != null)
                _analyticsRow(
                  'Total time',
                  '${analytics.totalGenerationTime!.toStringAsFixed(2)} s',
                ),
              if (analytics.outputTokens > 0)
                _analyticsRow('Output tokens', '${analytics.outputTokens}'),
              if (analytics.tokensPerSecond != null)
                _analyticsRow(
                  'Throughput',
                  '${analytics.tokensPerSecond!.toStringAsFixed(1)} tok/s',
                ),
              if (analytics.wasThinkingMode)
                _analyticsRow('Thinking mode', 'Yes'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _analyticsRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(value, style: AppTypography.body(context)),
      ],
    ),
  );

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
                  style: AppTypography.caption(
                    context,
                  ).copyWith(color: AppColors.primaryPurple),
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
                borderRadius: BorderRadius.circular(
                  AppSpacing.cornerRadiusRegular,
                ),
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
              style: AppTypography.caption(
                context,
              ).copyWith(color: AppColors.textSecondary(context)),
            ),
          if (analytics.tokensPerSecond != null) ...[
            const SizedBox(width: AppSpacing.smallMedium),
            Text(
              '${analytics.tokensPerSecond!.toStringAsFixed(1)} tok/s',
              style: AppTypography.caption(
                context,
              ).copyWith(color: AppColors.textSecondary(context)),
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

/// Bottom sheet listing past conversations from [ConversationStore].
///
/// Provides a "New chat" FAB, per-row delete affordance, and row tap to
/// restore a persisted conversation into the chat.
class _ConversationListSheet extends StatefulWidget {
  final ConversationStore store;
  final VoidCallback onNewChat;
  final ValueChanged<Conversation> onSelect;

  const _ConversationListSheet({
    required this.store,
    required this.onNewChat,
    required this.onSelect,
  });

  @override
  State<_ConversationListSheet> createState() => _ConversationListSheetState();
}

class _ConversationListSheetState extends State<_ConversationListSheet> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final conversations = widget.store.conversations;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Scaffold(
        appBar: AppBar(
          title: const Text('Conversations'),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        body: conversations.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No conversations yet.\nStart chatting to build history.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.builder(
                controller: scrollController,
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final conv = conversations[index];
                  return ListTile(
                    onTap: () => widget.onSelect(conv),
                    title: Text(
                      conv.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      conv.lastMessagePreview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete conversation',
                      onPressed: () => widget.store.deleteConversation(conv),
                    ),
                  );
                },
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: widget.onNewChat,
          icon: const Icon(Icons.add),
          label: const Text('New chat'),
        ),
      ),
    );
  }
}
