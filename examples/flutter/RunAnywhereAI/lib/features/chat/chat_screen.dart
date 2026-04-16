import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runanywhere_ai/core/theme/app_spacing.dart';
import 'package:runanywhere_ai/core/types/model_selection_context.dart';
import 'package:runanywhere_ai/core/widgets/model_selection_sheet.dart';
import 'package:runanywhere_ai/features/chat/chat_controller.dart';
import 'package:runanywhere_ai/features/chat/widgets/chat_input_bar.dart';
import 'package:runanywhere_ai/features/chat/widgets/message_bubble.dart';
import 'package:runanywhere_ai/features/chat/widgets/model_status_banner.dart';
import 'package:runanywhere_ai/features/chat/widgets/streaming_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatControllerProvider);

    ref.listen(chatControllerProvider.select((s) => s.messages.length), (prev, next) {
      _scrollToBottom();
    });

    ref.listen(chatControllerProvider.select((s) => s.streamingContent), (prev, next) {
      _scrollToBottom();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          if (chatState.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: ref.read(chatControllerProvider.notifier).clearChat,
            ),
        ],
      ),
      body: Column(
        children: [
          ModelStatusBanner(
            modelName: chatState.loadedModelName,
            framework: chatState.loadedFramework,
            onSelectModel: () async {
              final model = await showModelSelectionSheet(
                context,
                ref,
                selectionContext: ModelSelectionContext.llm,
              );
              if (model != null) {
                ref.read(chatControllerProvider.notifier).refreshModelState();
              }
            },
          ),
          if (chatState.errorMessage != null)
            _ErrorBanner(
              message: chatState.errorMessage!,
              onDismiss: ref.read(chatControllerProvider.notifier).clearError,
            ),
          Expanded(
            child: chatState.messages.isEmpty && !chatState.isGenerating
                ? const _EmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    itemCount: chatState.messages.length +
                        (chatState.isGenerating ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index < chatState.messages.length) {
                        return MessageBubble(
                          message: chatState.messages[index],
                        );
                      }
                      return StreamingBubble(
                        content: chatState.streamingContent,
                      );
                    },
                  ),
          ),
          ChatInputBar(
            isGenerating: chatState.isGenerating,
            hasModel: chatState.hasModel,
            onSend: (text) =>
                ref.read(chatControllerProvider.notifier).sendMessage(text),
            onCancel:
                ref.read(chatControllerProvider.notifier).cancelGeneration,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: AppSpacing.iconHuge,
            color: theme.colorScheme.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Start a conversation',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Type a message below to begin',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      color: theme.colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
