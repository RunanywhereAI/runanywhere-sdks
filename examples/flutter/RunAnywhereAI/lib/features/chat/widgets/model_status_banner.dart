import 'package:flutter/material.dart';
import 'package:runanywhere_ai/core/theme/app_spacing.dart';

class ModelStatusBanner extends StatelessWidget {
  const ModelStatusBanner({
    super.key,
    required this.modelName,
    this.framework,
    this.onSelectModel,
  });

  final String? modelName;
  final String? framework;
  final VoidCallback? onSelectModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (modelName == null) {
      return GestureDetector(
        onTap: onSelectModel,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'No model loaded — tap to select',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
              if (onSelectModel != null)
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onSelectModel,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 14,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                modelName!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (framework != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  framework!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            if (onSelectModel != null)
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}
