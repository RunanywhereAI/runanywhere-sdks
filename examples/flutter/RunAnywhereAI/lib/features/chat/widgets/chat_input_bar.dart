import 'package:flutter/material.dart';
import 'package:runanywhere_ai/core/theme/app_spacing.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.isGenerating,
    required this.hasModel,
    required this.onSend,
    required this.onCancel,
  });

  final bool isGenerating;
  final bool hasModel;
  final ValueChanged<String> onSend;
  final VoidCallback onCancel;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  bool get _canSend =>
      _controller.text.trim().isNotEmpty && !widget.isGenerating;

  void _handleSend() {
    if (!_canSend) return;
    final text = _controller.text.trim();
    _controller.clear();
    widget.onSend(text);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

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
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              enabled: widget.hasModel,
              decoration: InputDecoration(
                hintText: widget.hasModel
                    ? 'Type a message...'
                    : 'Load a model first',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.sm,
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _handleSend(),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          widget.isGenerating
              ? IconButton.filled(
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.stop_rounded, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                )
              : IconButton.filled(
                  onPressed: _canSend ? _handleSend : null,
                  icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                ),
        ],
      ),
    );
  }
}
