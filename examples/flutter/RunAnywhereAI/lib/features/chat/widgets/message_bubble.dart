import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:runanywhere_ai/core/theme/app_colors.dart';
import 'package:runanywhere_ai/core/theme/app_spacing.dart';
import 'package:runanywhere_ai/core/theme/app_typography.dart';
import 'package:runanywhere_ai/data/models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});

  final ChatMessage message;

  bool get _isUser => message.role == MessageRole.user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Align(
        alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.82,
          ),
          child: Column(
            crossAxisAlignment:
                _isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: _isUser
                      ? (brightness == Brightness.light
                          ? AppColors.userBubbleLight
                          : AppColors.userBubbleDark)
                      : (brightness == Brightness.light
                          ? AppColors.assistantBubbleLight
                          : AppColors.assistantBubbleDark),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(AppSpacing.radiusLg),
                    topRight: const Radius.circular(AppSpacing.radiusLg),
                    bottomLeft: Radius.circular(
                      _isUser ? AppSpacing.radiusLg : AppSpacing.xs,
                    ),
                    bottomRight: Radius.circular(
                      _isUser ? AppSpacing.xs : AppSpacing.radiusLg,
                    ),
                  ),
                ),
                child: _isUser
                    ? Text(
                        message.content,
                        style: AppTypography.bodyMedium.copyWith(
                          color: Colors.white,
                        ),
                      )
                    : MarkdownBody(
                        data: message.content,
                        selectable: true,
                        styleSheet: MarkdownStyleSheet(
                          p: AppTypography.bodyMedium.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                          code: AppTypography.mono.copyWith(
                            color: theme.colorScheme.primary,
                            backgroundColor:
                                theme.colorScheme.primaryContainer
                                    .withValues(alpha: 0.3),
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                          ),
                        ),
                      ),
              ),
              if (message.analytics != null) _AnalyticsRow(message.analytics!),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalyticsRow extends StatelessWidget {
  const _AnalyticsRow(this.analytics);

  final MessageAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = AppTypography.labelSmall.copyWith(
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
      fontSize: 10,
    );

    final parts = <String>[];
    if (analytics.tokensPerSecond != null && analytics.tokensPerSecond! > 0) {
      parts.add('${analytics.tokensPerSecond!.toStringAsFixed(1)} tok/s');
    }
    if (analytics.outputTokens != null) {
      parts.add('${analytics.outputTokens} tokens');
    }
    if (analytics.totalGenerationMs != null) {
      final secs = analytics.totalGenerationMs! / 1000;
      parts.add('${secs.toStringAsFixed(1)}s');
    }

    if (parts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(parts.join(' \u2022 '), style: style),
    );
  }
}
