import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/public/types/download_types.dart';
import 'package:runanywhere_ai/core/theme/app_spacing.dart';
import 'package:runanywhere_ai/core/theme/app_typography.dart';
import 'package:runanywhere_ai/core/types/model_selection_context.dart';

/// Shows a model selection bottom sheet filtered by [selectionContext].
///
/// Returns the selected [ModelInfo] or null if dismissed.
Future<ModelInfo?> showModelSelectionSheet(
  BuildContext context,
  WidgetRef ref, {
  required ModelSelectionContext selectionContext,
}) async {
  ModelInfo? selected;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ModelSelectionSheet(
      selectionContext: selectionContext,
      onModelSelected: (model) {
        selected = model;
        Navigator.pop(context);
      },
    ),
  );
  return selected;
}

class _ModelSelectionSheet extends ConsumerStatefulWidget {
  const _ModelSelectionSheet({
    required this.selectionContext,
    required this.onModelSelected,
  });

  final ModelSelectionContext selectionContext;
  final ValueChanged<ModelInfo> onModelSelected;

  @override
  ConsumerState<_ModelSelectionSheet> createState() =>
      _ModelSelectionSheetState();
}

class _ModelSelectionSheetState extends ConsumerState<_ModelSelectionSheet> {
  List<ModelInfo> _models = [];
  bool _isLoading = true;
  String? _loadingModelId;
  final Map<String, _DownloadState> _downloads = {};

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    setState(() => _isLoading = true);
    try {
      final all = await sdk.RunAnywhere.availableModels();
      final filtered = all
          .where((m) => widget.selectionContext.categories.contains(m.category))
          .toList()
        ..sort((a, b) {
          // Downloaded first
          final aPriority = a.isDownloaded ? 0 : 1;
          final bPriority = b.isDownloaded ? 0 : 1;
          if (aPriority != bPriority) return aPriority.compareTo(bPriority);
          return a.name.compareTo(b.name);
        });
      if (!mounted) return;
      setState(() {
        _models = filtered;
        _isLoading = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadModel(ModelInfo model) async {
    setState(() {
      _downloads[model.id] = const _DownloadState(progress: 0, stage: 'Queued');
    });

    try {
      await for (final progress in sdk.RunAnywhere.downloadModel(model.id)) {
        if (!mounted) return;
        setState(() {
          _downloads[model.id] = _DownloadState(
            progress: progress.overallProgress,
            stage: _stageLabel(progress.stage),
          );
        });
        if (progress.state.isCompleted || progress.state.isFailed) break;
      }

      if (!mounted) return;
      setState(() => _downloads.remove(model.id));
      await _loadModels();
    } on Exception {
      if (!mounted) return;
      setState(() => _downloads.remove(model.id));
    }
  }

  Future<void> _loadAndSelect(ModelInfo model) async {
    setState(() => _loadingModelId = model.id);
    try {
      debugPrint('[ModelSheet] Loading ${model.id} category=${model.category}');
      switch (model.category) {
        case ModelCategory.language:
          await sdk.RunAnywhere.loadModel(model.id);
        case ModelCategory.speechRecognition:
          await sdk.RunAnywhere.loadSTTModel(model.id);
        case ModelCategory.speechSynthesis:
          await sdk.RunAnywhere.loadTTSVoice(model.id);
        case ModelCategory.multimodal || ModelCategory.vision:
          await sdk.RunAnywhere.loadVLMModel(model.id);
        case ModelCategory.embedding:
          // Embedding models are loaded on-demand by the RAG pipeline,
          // not globally. Just confirm it's downloaded and return it.
          break;
        default:
          await sdk.RunAnywhere.loadModel(model.id);
      }
      debugPrint('[ModelSheet] Loaded ${model.id} successfully');
      if (!mounted) return;
      widget.onModelSelected(model);
    } on Object catch (e) {
      debugPrint('[ModelSheet] FAILED to load ${model.id}: $e');
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Failed to load: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingModelId = null);
    }
  }

  void _onModelTap(ModelInfo model) {
    debugPrint('[ModelSheet] Tapped ${model.id} downloaded=${model.isDownloaded} loading=$_loadingModelId');
    if (_loadingModelId != null) return;
    if (_downloads.containsKey(model.id)) return;

    if (!model.isDownloaded) {
      _downloadModel(model);
    } else {
      _loadAndSelect(model);
    }
  }

  String _stageLabel(DownloadProgressStage stage) => switch (stage) {
        DownloadProgressStage.queued => 'Queued',
        DownloadProgressStage.downloading => 'Downloading',
        DownloadProgressStage.extracting => 'Extracting',
        DownloadProgressStage.verifying => 'Verifying',
        DownloadProgressStage.completed => 'Complete',
        DownloadProgressStage.failed => 'Failed',
        DownloadProgressStage.cancelled => 'Cancelled',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                widget.selectionContext.title,
                style: AppTypography.titleLarge,
              ),
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _models.isEmpty
                      ? Center(
                          child: Text(
                            'No models available',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sm,
                          ),
                          itemCount: _models.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            indent: AppSpacing.lg,
                            endIndent: AppSpacing.lg,
                            color: theme.colorScheme.outlineVariant
                                .withValues(alpha: 0.5),
                          ),
                          itemBuilder: (context, index) {
                            final model = _models[index];
                            return _ModelRow(
                              model: model,
                              isLoading: _loadingModelId == model.id,
                              download: _downloads[model.id],
                              onTap: () => _onModelTap(model),
                              theme: theme,
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }
}

class _DownloadState {
  const _DownloadState({required this.progress, required this.stage});
  final double progress;
  final String stage;
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.model,
    required this.isLoading,
    required this.download,
    required this.onTap,
    required this.theme,
  });

  final ModelInfo model;
  final bool isLoading;
  final _DownloadState? download;
  final VoidCallback onTap;
  final ThemeData theme;

  bool get _isDownloading => download != null;

  Color get _frameworkColor => switch (model.framework) {
        InferenceFramework.llamaCpp => theme.colorScheme.primary,
        InferenceFramework.onnx => Colors.purple,
        InferenceFramework.genie => theme.colorScheme.tertiary,
        InferenceFramework.foundationModels => Colors.grey,
        _ => theme.colorScheme.onSurfaceVariant,
      };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name + framework badge
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              model.name,
                              style: AppTypography.titleMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _frameworkColor.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusSm),
                            ),
                            child: Text(
                              model.framework.displayName,
                              style: AppTypography.labelSmall.copyWith(
                                color: _frameworkColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      // Status row
                      Row(
                        children: [
                          if (model.downloadSize != null &&
                              model.downloadSize! > 0) ...[
                            Text(
                              _formatBytes(model.downloadSize!),
                              style: AppTypography.bodySmall.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                          ],
                          if (_isDownloading) ...[
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: download!.progress > 0
                                    ? download!.progress
                                    : null,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              '${download!.stage} ${(download!.progress * 100).toInt()}%',
                              style: AppTypography.bodySmall.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ] else if (model.isDownloaded) ...[
                            Icon(
                              Icons.check_circle,
                              size: 14,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              'Ready',
                              style: AppTypography.bodySmall.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ] else ...[
                            Icon(
                              Icons.download_rounded,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              'Tap to download',
                              style: AppTypography.bodySmall.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                _buildAction(),
              ],
            ),
            if (_isDownloading) ...[
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                child: LinearProgressIndicator(
                  value: download!.progress,
                  minHeight: 3,
                  backgroundColor:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAction() {
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
      return FilledButton.tonal(
        onPressed: onTap,
        child: const Text('Use'),
      );
    }
    return OutlinedButton(
      onPressed: onTap,
      child: const Text('Get'),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1000000000) {
      return '${(bytes / 1000000000).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1000000) {
      return '${(bytes / 1000000).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1000).toStringAsFixed(0)} KB';
  }
}
