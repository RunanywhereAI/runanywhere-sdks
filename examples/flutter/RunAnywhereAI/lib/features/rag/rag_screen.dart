import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:runanywhere_ai/core/theme/app_spacing.dart';
import 'package:runanywhere_ai/core/theme/app_typography.dart';
import 'package:runanywhere_ai/core/types/model_selection_context.dart';
import 'package:runanywhere_ai/core/widgets/model_selection_sheet.dart';
import 'package:runanywhere_ai/data/models/chat_message.dart';
import 'package:runanywhere_ai/features/rag/rag_controller.dart';

class RagScreen extends ConsumerStatefulWidget {
  const RagScreen({super.key});

  @override
  ConsumerState<RagScreen> createState() => _RagScreenState();
}

class _RagScreenState extends ConsumerState<RagScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _inputController.dispose();
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

  Future<void> _selectEmbeddingModel() async {
    final model = await showModelSelectionSheet(
      context,
      ref,
      selectionContext: ModelSelectionContext.embedding,
    );
    if (model != null) {
      ref.read(ragControllerProvider.notifier).setEmbeddingModel(model);
    }
  }

  Future<void> _selectLlmModel() async {
    final model = await showModelSelectionSheet(
      context,
      ref,
      selectionContext: ModelSelectionContext.llm,
    );
    if (model != null) {
      ref.read(ragControllerProvider.notifier).setLlmModel(model);
    }
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'json', 'txt'],
    );
    if (result != null && result.files.single.path != null) {
      final file = result.files.single;
      await ref
          .read(ragControllerProvider.notifier)
          .loadDocument(file.path!, file.name);
    }
  }

  void _sendQuery() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    ref.read(ragControllerProvider.notifier).query(text);
  }

  @override
  Widget build(BuildContext context) {
    final ragState = ref.watch(ragControllerProvider);
    final theme = Theme.of(context);

    ref.listen(ragControllerProvider.select((s) => s.messages.length),
        (prev, next) {
      _scrollToBottom();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Q&A'),
        actions: [
          if (ragState.hasDocument)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Clear document',
              onPressed:
                  ref.read(ragControllerProvider.notifier).clearDocument,
            ),
          if (ragState.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed:
                  ref.read(ragControllerProvider.notifier).clearChat,
            ),
        ],
      ),
      body: Column(
        children: [
          // Setup section when models/document not ready
          if (!ragState.hasModels || !ragState.hasDocument)
            _SetupSection(
              ragState: ragState,
              onSelectEmbedding: _selectEmbeddingModel,
              onSelectLlm: _selectLlmModel,
              onPickDocument: _pickDocument,
              theme: theme,
            ),
          // Document info banner
          if (ragState.hasDocument)
            _DocumentBanner(
              documentName: ragState.documentName,
              chunkCount: ragState.chunkCount,
              theme: theme,
            ),
          // Error banner
          if (ragState.errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              color: theme.colorScheme.errorContainer,
              child: Text(
                ragState.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          // Messages
          Expanded(
            child: ragState.messages.isEmpty && !ragState.isQuerying
                ? _EmptyState(
                    hasDocument: ragState.hasDocument, theme: theme)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    itemCount: ragState.messages.length +
                        (ragState.isQuerying ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index < ragState.messages.length) {
                        return _MessageBubble(
                          message: ragState.messages[index],
                          theme: theme,
                        );
                      }
                      // Processing indicator
                      return _ProcessingIndicator(
                        statusText: ragState.statusText,
                        theme: theme,
                      );
                    },
                  ),
          ),
          // Input bar
          _InputBar(
            controller: _inputController,
            isQuerying: ragState.isQuerying,
            hasDocument: ragState.hasDocument,
            onSend: _sendQuery,
          ),
        ],
      ),
    );
  }
}

class _SetupSection extends StatelessWidget {
  const _SetupSection({
    required this.ragState,
    required this.onSelectEmbedding,
    required this.onSelectLlm,
    required this.onPickDocument,
    required this.theme,
  });

  final RagState ragState;
  final VoidCallback onSelectEmbedding;
  final VoidCallback onSelectLlm;
  final VoidCallback onPickDocument;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      color: theme.colorScheme.surfaceContainerHighest
          .withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RAG Pipeline Setup',
              style: AppTypography.labelLarge
                  .copyWith(color: theme.colorScheme.onSurface)),
          const SizedBox(height: AppSpacing.md),
          _SetupRow(
            label: 'Embedding Model',
            value: ragState.embeddingModelName,
            onTap: onSelectEmbedding,
            theme: theme,
          ),
          const SizedBox(height: AppSpacing.sm),
          _SetupRow(
            label: 'LLM Model',
            value: ragState.llmModelName,
            onTap: onSelectLlm,
            theme: theme,
          ),
          if (ragState.hasModels && !ragState.hasDocument) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: ragState.documentStatus ==
                        RagDocumentStatus.loading
                    ? null
                    : onPickDocument,
                icon: ragState.documentStatus ==
                        RagDocumentStatus.loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_rounded),
                label: Text(
                  ragState.documentStatus == RagDocumentStatus.loading
                      ? (ragState.statusText ?? 'Loading...')
                      : 'Load Document (PDF, JSON, TXT)',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SetupRow extends StatelessWidget {
  const _SetupRow({
    required this.label,
    required this.value,
    required this.onTap,
    required this.theme,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(
              value != null
                  ? Icons.check_circle
                  : Icons.circle_outlined,
              size: 18,
              color: value != null
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: AppTypography.labelSmall.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  Text(
                    value ?? 'Tap to select',
                    style: AppTypography.bodySmall.copyWith(
                      color: value != null
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _DocumentBanner extends StatelessWidget {
  const _DocumentBanner({
    required this.documentName,
    required this.chunkCount,
    required this.theme,
  });

  final String? documentName;
  final int chunkCount;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Row(
        children: [
          Icon(Icons.description_outlined,
              size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '${documentName ?? "Document"} \u2022 $chunkCount chunks indexed',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasDocument, required this.theme});

  final bool hasDocument;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasDocument
                ? Icons.question_answer_outlined
                : Icons.description_outlined,
            size: AppSpacing.iconHuge,
            color:
                theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            hasDocument
                ? 'Ask a question about your document'
                : 'Set up models and load a document',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.theme});

  final ChatMessage message;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.82,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: isUser
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                message.content,
                style: AppTypography.bodyMedium.copyWith(
                  color: isUser
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                ),
              ),
              if (!isUser && message.analytics?.totalGenerationMs != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${(message.analytics!.totalGenerationMs! / 1000).toStringAsFixed(1)}s',
                  style: AppTypography.labelSmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProcessingIndicator extends StatelessWidget {
  const _ProcessingIndicator({
    required this.statusText,
    required this.theme,
  });

  final String? statusText;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                statusText ?? 'Thinking...',
                style: AppTypography.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.isQuerying,
    required this.hasDocument,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isQuerying;
  final bool hasDocument;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.sm,
        top: AppSpacing.sm,
        bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: hasDocument && !isQuerying,
              decoration: InputDecoration(
                hintText: hasDocument
                    ? 'Ask about your document...'
                    : 'Load a document first',
                border: InputBorder.none,
                filled: false,
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          IconButton.filled(
            onPressed: hasDocument && !isQuerying ? onSend : null,
            icon: isQuerying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_upward_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}
