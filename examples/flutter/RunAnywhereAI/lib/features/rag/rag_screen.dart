import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:runanywhere_ai/core/theme/app_spacing.dart';
import 'package:runanywhere_ai/core/theme/app_typography.dart';
import 'package:runanywhere_ai/data/models/chat_message.dart';
import 'package:runanywhere_ai/features/rag/rag_controller.dart';

class RagScreen extends ConsumerStatefulWidget {
  const RagScreen({super.key});

  @override
  ConsumerState<RagScreen> createState() => _RagScreenState();
}

class _RagScreenState extends ConsumerState<RagScreen> {
  final _inputController = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'json'],
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Q&A'),
        actions: [
          if (ragState.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: ref.read(ragControllerProvider.notifier).clearChat,
            ),
        ],
      ),
      body: Column(
        children: [
          _DocumentBanner(
            status: ragState.documentStatus,
            documentName: ragState.documentName,
            onPick: _pickDocument,
            theme: theme,
          ),
          Expanded(
            child: ragState.messages.isEmpty
                ? Center(
                    child: Text(
                      ragState.hasDocument
                          ? 'Ask a question about your document'
                          : 'Load a PDF or JSON document to start',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: ragState.messages.length,
                    itemBuilder: (context, index) {
                      final msg = ragState.messages[index];
                      return _RagBubble(message: msg, theme: theme);
                    },
                  ),
          ),
          _QueryInputBar(
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

class _DocumentBanner extends StatelessWidget {
  const _DocumentBanner({
    required this.status,
    required this.documentName,
    required this.onPick,
    required this.theme,
  });

  final RagDocumentStatus status;
  final String? documentName;
  final VoidCallback onPick;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      color: status == RagDocumentStatus.loaded
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
          : theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(
            status == RagDocumentStatus.loaded
                ? Icons.description_outlined
                : Icons.upload_file_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              documentName ?? 'No document loaded',
              style: AppTypography.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: status == RagDocumentStatus.loading ? null : onPick,
            child: Text(
              status == RagDocumentStatus.loaded ? 'Change' : 'Load',
            ),
          ),
        ],
      ),
    );
  }
}

class _RagBubble extends StatelessWidget {
  const _RagBubble({required this.message, required this.theme});

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
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: isUser
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Text(
            message.content,
            style: AppTypography.bodyMedium.copyWith(
              color: isUser
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _QueryInputBar extends StatelessWidget {
  const _QueryInputBar({
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
                hintText:
                    hasDocument ? 'Ask about your document...' : 'Load a document first',
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
