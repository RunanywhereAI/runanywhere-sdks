import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:runanywhere/runanywhere.dart';
import '../../core/design_system/app_colors.dart';
import '../../core/design_system/app_spacing.dart';
import '../../core/design_system/typography.dart';
import '../../core/services/model_manager.dart';

/// Storage View - Manage downloaded models
class StorageView extends StatefulWidget {
  const StorageView({super.key});

  @override
  State<StorageView> createState() => _StorageViewState();
}

class _StorageViewState extends State<StorageView> {
  List<ModelInfo> _models = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final models = await RunAnywhere.availableModels();
      setState(() {
        _models = models;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadModel(ModelInfo model) async {
    try {
      final downloadTask = await RunAnywhere.serviceContainer.downloadService.downloadModel(model);

      // Show download progress
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _DownloadProgressDialog(
          model: model,
          downloadTask: downloadTask,
          onComplete: () {
            Navigator.of(context).pop();
            _loadModels();
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  Future<void> _loadModel(String modelId) async {
    try {
      await RunAnywhere.loadModel(modelId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Model loaded successfully')),
      );
      Provider.of<ModelManager>(context, listen: false).setCurrentModel(modelId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load model: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadModels,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Error: $_error', style: AppTypography.body(context)),
                          const SizedBox(height: AppSpacing.padding16),
                          ElevatedButton(
                            onPressed: _loadModels,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
              : _models.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.storage,
                            size: AppSpacing.iconXXLarge,
                            color: AppColors.primaryBlue,
                          ),
                          const SizedBox(height: AppSpacing.large),
                  Text(
                    'No models available',
                    style: AppTypography.title2(context),
                  ),
                  const SizedBox(height: AppSpacing.padding8),
                  Text(
                    'Models will appear here once registered',
                    style: AppTypography.body(context).copyWith(
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.padding16),
                      itemCount: _models.length,
                      itemBuilder: (context, index) {
                        final model = _models[index];
                        return _ModelCard(
                          model: model,
                          onDownload: () => _downloadModel(model),
                          onLoad: () => _loadModel(model.id),
                        );
                      },
                    ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  final ModelInfo model;
  final VoidCallback onDownload;
  final VoidCallback onLoad;

  const _ModelCard({
    required this.model,
    required this.onDownload,
    required this.onLoad,
  });

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final isDownloaded = model.localPath != null;
    final currentModel = Provider.of<ModelManager>(context).currentModelId;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.padding16),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.padding16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    model.name,
                    style: AppTypography.headlineSemibold(context),
                  ),
                ),
                if (currentModel == model.id)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.padding8,
                      vertical: AppSpacing.padding4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen,
                      borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusSmall),
                    ),
                    child: Text(
                      'Active',
                      style: AppTypography.captionMedium(context).copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.padding8),
            Text(
              'ID: ${model.id}',
              style: AppTypography.footnote(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: AppSpacing.padding4),
            Text(
              'Framework: ${model.framework}',
              style: AppTypography.footnote(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: AppSpacing.padding4),
            Text(
              'Size: ${_formatBytes(model.size)}',
              style: AppTypography.footnote(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: AppSpacing.padding16),
            Row(
              children: [
                if (!isDownloaded)
                  ElevatedButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download),
                    label: const Text('Download'),
                  ),
                if (isDownloaded && currentModel != model.id) ...[
                  const SizedBox(width: AppSpacing.padding8),
                  ElevatedButton.icon(
                    onPressed: onLoad,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Load'),
                  ),
                ],
                if (isDownloaded)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.padding8),
                    child: Icon(
                      Icons.check_circle,
                      color: AppColors.primaryGreen,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadProgressDialog extends StatefulWidget {
  final ModelInfo model;
  final DownloadTask downloadTask;
  final VoidCallback onComplete;

  const _DownloadProgressDialog({
    required this.model,
    required this.downloadTask,
    required this.onComplete,
  });

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double _progress = 0.0;
  String _status = 'Downloading...';

  @override
  void initState() {
    super.initState();
    _listenToProgress();
  }

  void _listenToProgress() async {
    await for (final progress in widget.downloadTask.progress) {
      if (!mounted) return;
      setState(() {
        _progress = progress.progress;
        switch (progress.state) {
          case DownloadState.downloading:
            _status = 'Downloading...';
            break;
          case DownloadState.completed:
            _status = 'Completed!';
            break;
          case DownloadState.failed:
            _status = 'Failed: ${progress.error ?? "Unknown error"}';
            break;
          case DownloadState.cancelled:
            _status = 'Cancelled';
            break;
        }
      });

      if (progress.state == DownloadState.completed) {
        await widget.downloadTask.result;
        widget.onComplete();
      } else if (progress.state == DownloadState.failed) {
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Downloading ${widget.model.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: AppSpacing.padding16),
          Text('${(_progress * 100).toStringAsFixed(1)}%'),
          const SizedBox(height: AppSpacing.padding8),
          Text(_status),
        ],
      ),
    );
  }
}
