import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere_ai/core/theme/app_spacing.dart';
import 'package:runanywhere_ai/core/theme/app_typography.dart';
import 'package:runanywhere_ai/features/models/models_controller.dart';

class ModelsScreen extends ConsumerWidget {
  const ModelsScreen({super.key});

  void _confirmDelete(
    BuildContext context,
    ModelsController controller,
    ModelInfo model,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Model'),
        content: Text('Delete "${model.name}"? You can re-download it later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              controller.deleteModel(model);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modelsState = ref.watch(modelsControllerProvider);
    final controller = ref.read(modelsControllerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Models'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: controller.refresh,
          ),
        ],
      ),
      body: modelsState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : modelsState.models.isEmpty
              ? Center(
                  child: Text(
                    'No models available',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : Column(
                  children: [
                    if (modelsState.errorMessage != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        color: theme.colorScheme.errorContainer,
                        child: Text(
                          modelsState.errorMessage!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: controller.refresh,
                        child: ListView.builder(
                          padding: AppSpacing.pagePadding,
                          itemCount: modelsState.models.length,
                          itemBuilder: (context, index) {
                            final model = modelsState.models[index];
                            final download =
                                modelsState.downloads[model.id];
                            return _ModelCard(
                              model: model,
                              isLoading:
                                  modelsState.loadingModelId == model.id,
                              download: download,
                              onTap: () => controller.loadModel(model),
                              onDelete: model.isDownloaded
                                  ? () => _confirmDelete(
                                        context, controller, model)
                                  : null,
                              theme: theme,
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.model,
    required this.isLoading,
    required this.download,
    required this.onTap,
    required this.onDelete,
    required this.theme,
  });

  final ModelInfo model;
  final bool isLoading;
  final ModelDownloadInfo? download;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final ThemeData theme;

  String get _categoryLabel => switch (model.category) {
        ModelCategory.language => 'LLM',
        ModelCategory.multimodal => 'VLM',
        ModelCategory.speechRecognition => 'STT',
        ModelCategory.speechSynthesis => 'TTS',
        ModelCategory.embedding => 'Embed',
        _ => model.category.name,
      };

  Color get _categoryColor => switch (model.category) {
        ModelCategory.language => theme.colorScheme.primary,
        ModelCategory.multimodal => theme.colorScheme.tertiary,
        ModelCategory.speechRecognition => theme.colorScheme.secondary,
        ModelCategory.speechSynthesis => theme.colorScheme.error,
        _ => theme.colorScheme.onSurfaceVariant,
      };

  bool get _isDownloading => download != null;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xs,
            ),
            title: Text(
              model.name,
              style: AppTypography.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _categoryColor.withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(
                    _categoryLabel,
                    style: AppTypography.labelSmall.copyWith(
                      color: _categoryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  model.framework.name,
                  style: AppTypography.bodySmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (model.isDownloaded) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    Icons.check_circle,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ],
            ),
            trailing: _buildTrailing(),
          ),
          if (_isDownloading) _DownloadProgressBar(download: download!),
        ],
      ),
    );
  }

  Widget _buildTrailing() {
    if (isLoading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_isDownloading) {
      return Text(
        '${(download!.progress * 100).toInt()}%',
        style: AppTypography.labelLarge.copyWith(
          color: theme.colorScheme.primary,
        ),
      );
    }
    if (model.isDownloaded) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onDelete != null)
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 20,
                color: theme.colorScheme.error,
              ),
              onPressed: onDelete,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: onTap,
            child: const Text('Load'),
          ),
        ],
      );
    }
    return OutlinedButton(
      onPressed: onTap,
      child: const Text('Download'),
    );
  }
}

class _DownloadProgressBar extends StatelessWidget {
  const _DownloadProgressBar({required this.download});

  final ModelDownloadInfo download;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            child: LinearProgressIndicator(
              value: download.progress,
              minHeight: 4,
              backgroundColor:
                  theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            download.stageLabel,
            style: AppTypography.labelSmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
