import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/core/models/app_types.dart';
import 'package:runanywhere_ai/features/models/model_list_view_model.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';

class StorageView extends StatefulWidget {
  const StorageView({super.key});

  @override
  State<StorageView> createState() => _StorageViewState();
}

class _StorageViewState extends State<StorageView> {
  bool _isLoading = false;
  int _totalUsageBytes = 0;
  int _availableBytes = 0;
  List<sdk.ModelInfo> _models = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (ModelListViewModel.shared.availableModels.isEmpty) {
        await ModelListViewModel.shared.loadModelsFromRegistry();
      }
      final state = await sdk.RunAnywhere.models.state();
      final models = await sdk.RunAnywhere.models.list(
        const sdk.ModelFilter(downloadedOnly: true),
      );
      if (!mounted) return;
      setState(() {
        _totalUsageBytes = state.storageUsedBytes;
        _availableBytes = state.storageFreeBytes;
        _models = models;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Failed to load storage: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteModel(sdk.ModelInfo model) async {
    await _runAction('${_modelDisplayName(model.id)} deleted', () async {
      await sdk.RunAnywhere.models.delete(model.id);
    });
  }

  Future<void> _runAction(
    String successMessage,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Storage action failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final modelBytes = _models.fold<int>(
      0,
      (total, model) => total + model.downloadSizeBytes.toInt(),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage'),
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.large),
        children: [
          if (_errorMessage != null) _ErrorBanner(message: _errorMessage!),
          _StorageSummaryCard(
            totalUsageBytes: _totalUsageBytes,
            availableBytes: _availableBytes,
            modelBytes: modelBytes,
            modelCount: _models.length,
          ),
          const SizedBox(height: AppSpacing.large),
          Text(
            'Downloaded Models',
            style: AppTypography.headlineSemibold(context),
          ),
          const SizedBox(height: AppSpacing.smallMedium),
          if (_models.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.large),
                child: Text('No models downloaded yet'),
              ),
            )
          else
            ..._models.map(
              (model) => _ModelStorageMetricsRow(
                model: model,
                onDelete: () => _deleteModel(model),
              ),
            ),
        ],
      ),
    );
  }
}

class _StorageSummaryCard extends StatelessWidget {
  const _StorageSummaryCard({
    required this.totalUsageBytes,
    required this.availableBytes,
    required this.modelBytes,
    required this.modelCount,
  });

  final int totalUsageBytes;
  final int availableBytes;
  final int modelBytes;
  final int modelCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          children: [
            _StorageRow(
              icon: Icons.storage,
              label: 'Total Usage',
              value: totalUsageBytes.formattedFileSize,
            ),
            const Divider(),
            _StorageRow(
              icon: Icons.memory,
              label: 'Models',
              value: modelBytes.formattedFileSize,
              valueColor: AppColors.primaryBlue,
            ),
            const Divider(),
            _StorageRow(
              icon: Icons.download_done,
              label: 'Downloaded',
              value: '$modelCount',
            ),
            const Divider(),
            _StorageRow(
              icon: Icons.add_circle_outline,
              label: 'Available',
              value: availableBytes.formattedFileSize,
              valueColor: AppColors.statusGreen,
            ),
          ],
        ),
      ),
    );
  }
}

class _StorageRow extends StatelessWidget {
  const _StorageRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.smallMedium),
      child: Row(
        children: [
          Icon(icon, size: AppSpacing.iconRegular),
          const SizedBox(width: AppSpacing.mediumLarge),
          Expanded(
            child: Text(label, style: AppTypography.subheadline(context)),
          ),
          Text(
            value,
            style: AppTypography.subheadlineSemibold(
              context,
            ).copyWith(color: valueColor),
          ),
        ],
      ),
    );
  }
}

class _ModelStorageMetricsRow extends StatefulWidget {
  const _ModelStorageMetricsRow({required this.model, required this.onDelete});

  final sdk.ModelInfo model;
  final Future<void> Function() onDelete;

  @override
  State<_ModelStorageMetricsRow> createState() =>
      _ModelStorageMetricsRowState();
}

class _ModelStorageMetricsRowState extends State<_ModelStorageMetricsRow> {
  bool _isDeleting = false;

  Future<void> _confirmDelete() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Model'),
        content: Text('Delete ${_modelDisplayName(widget.model.id)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.primaryRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      await widget.onDelete();
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogModel = _catalogModelFor(widget.model.id);
    final framework = catalogModel?.backendFramework;
    return Card(
      child: ListTile(
        title: Text(_modelDisplayName(widget.model.id)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.model.downloadSizeBytes.toInt().formattedFileSize),
            if (framework != null) ...[
              const SizedBox(height: AppSpacing.xxSmall),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    framework.backendIcon,
                    size: 12,
                    color: framework.backendColor,
                  ),
                  const SizedBox(width: AppSpacing.xxSmall),
                  Text(
                    framework.displayName,
                    style: AppTypography.caption2(
                      context,
                    ).copyWith(color: framework.backendColor),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: IconButton(
          icon: _isDeleting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_outline),
          color: AppColors.primaryRed,
          onPressed: _isDeleting ? null : _confirmDelete,
          tooltip: 'Delete model',
        ),
      ),
    );
  }
}

ModelInfo? _catalogModelFor(String modelId) {
  for (final model in ModelListViewModel.shared.availableModels) {
    if (model.id == modelId) return model;
  }
  return null;
}

String _modelDisplayName(String modelId) =>
    _catalogModelFor(modelId)?.name ?? modelId;

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.large),
      padding: const EdgeInsets.all(AppSpacing.mediumLarge),
      decoration: BoxDecoration(
        color: AppColors.badgeRed,
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.primaryRed),
          const SizedBox(width: AppSpacing.smallMedium),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
