import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;

import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/core/models/app_types.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';

/// FrameworkRow (mirroring iOS FrameworkRow)
///
/// A row displaying a framework with expand/collapse functionality.
class FrameworkRow extends StatelessWidget {
  final LLMFramework framework;
  final bool isExpanded;
  final VoidCallback onTap;

  const FrameworkRow({
    super.key,
    required this.framework,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.large,
          vertical: AppSpacing.mediumLarge,
        ),
        child: Row(
          children: [
            Icon(
              _frameworkIcon,
              color: _frameworkColor,
              size: AppSpacing.iconMedium,
            ),
            const SizedBox(width: AppSpacing.mediumLarge),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    framework.displayName,
                    style: AppTypography.headline(context),
                  ),
                  const SizedBox(height: AppSpacing.xxSmall),
                  Text(
                    _frameworkDescription,
                    style: AppTypography.caption(context).copyWith(
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              color: AppColors.textSecondary(context),
              size: AppSpacing.iconSmall,
            ),
          ],
        ),
      ),
    );
  }

  IconData get _frameworkIcon {
    switch (framework) {
      case LLMFramework.foundationModels:
        return Icons.apple;
      case LLMFramework.mediaPipe:
        return Icons.psychology;
      case LLMFramework.llamaCpp:
        return Icons.memory;
      case LLMFramework.whisperKit:
        return Icons.mic;
      case LLMFramework.onnxRuntime:
        return Icons.developer_board;
      case LLMFramework.systemTTS:
        return Icons.volume_up;
      default:
        return Icons.memory;
    }
  }

  Color get _frameworkColor {
    switch (framework) {
      case LLMFramework.foundationModels:
        return Colors.black;
      case LLMFramework.mediaPipe:
        return AppColors.statusBlue;
      case LLMFramework.whisperKit:
        return AppColors.statusGreen;
      default:
        return AppColors.statusGray;
    }
  }

  String get _frameworkDescription {
    switch (framework) {
      case LLMFramework.foundationModels:
        return "Apple's pre-installed system models";
      case LLMFramework.mediaPipe:
        return "Google's cross-platform ML framework";
      case LLMFramework.llamaCpp:
        return 'Fast C++ inference for GGUF models';
      case LLMFramework.whisperKit:
        return 'OpenAI Whisper for speech recognition';
      case LLMFramework.onnxRuntime:
        return 'Microsoft ONNX inference runtime';
      case LLMFramework.systemTTS:
        return 'Built-in system text-to-speech';
      default:
        return 'Machine learning framework';
    }
  }
}

/// ModelRow (mirroring iOS ModelRow)
///
/// A row displaying a model with download/load options.
class ModelRow extends StatefulWidget {
  final ModelInfo model;
  final bool isSelected;
  final VoidCallback onDownloadCompleted;
  final VoidCallback onSelectModel;
  final VoidCallback? onModelUpdated;

  const ModelRow({
    super.key,
    required this.model,
    required this.isSelected,
    required this.onDownloadCompleted,
    required this.onSelectModel,
    this.onModelUpdated,
  });

  @override
  State<ModelRow> createState() => _ModelRowState();
}

class _ModelRowState extends State<ModelRow> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.large,
        vertical: AppSpacing.smallMedium,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.model.name,
                  style: AppTypography.subheadline(context).copyWith(
                    fontWeight:
                        widget.isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: AppSpacing.xSmall),
                _buildModelInfo(context),
                const SizedBox(height: AppSpacing.xSmall),
                _buildDownloadStatus(context),
              ],
            ),
          ),
          _buildActionButton(context),
        ],
      ),
    );
  }

  Widget _buildModelInfo(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.smallMedium,
      runSpacing: AppSpacing.xSmall,
      children: [
        if (widget.model.memoryRequired != null &&
            widget.model.memoryRequired! > 0)
          _buildInfoChip(
            context,
            Icons.memory,
            widget.model.memoryRequired!.formattedFileSize,
          ),
        _buildBadge(
          context,
          widget.model.format.rawValue.toUpperCase(),
          AppColors.badgeGray,
          AppColors.textSecondary(context),
        ),
        if (widget.model.supportsThinking)
          _buildBadge(
            context,
            'THINKING',
            AppColors.badgePurple,
            AppColors.primaryPurple,
            icon: Icons.psychology,
          ),
      ],
    );
  }

  Widget _buildInfoChip(BuildContext context, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: AppColors.textSecondary(context),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTypography.caption2(context).copyWith(
            color: AppColors.textSecondary(context),
          ),
        ),
      ],
    );
  }

  Widget _buildBadge(
    BuildContext context,
    String label,
    Color backgroundColor,
    Color textColor, {
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.small,
        vertical: AppSpacing.xxSmall,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: textColor),
            const SizedBox(width: 2),
          ],
          Text(
            label,
            style: AppTypography.caption2(context).copyWith(color: textColor),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadStatus(BuildContext context) {
    if (widget.model.downloadURL != null) {
      if (widget.model.localPath == null) {
        if (_isDownloading) {
          return Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(value: _downloadProgress),
              ),
              const SizedBox(width: AppSpacing.smallMedium),
              Text(
                '${(_downloadProgress * 100).toInt()}%',
                style: AppTypography.caption2(context).copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
            ],
          );
        } else {
          return Text(
            'Available for download',
            style: AppTypography.caption2(context).copyWith(
              color: AppColors.statusBlue,
            ),
          );
        }
      } else {
        return Row(
          children: [
            const Icon(
              Icons.check_circle,
              size: 12,
              color: AppColors.statusGreen,
            ),
            const SizedBox(width: AppSpacing.xSmall),
            Text(
              'Downloaded',
              style: AppTypography.caption2(context).copyWith(
                color: AppColors.statusGreen,
              ),
            ),
          ],
        );
      }
    }
    return const SizedBox.shrink();
  }

  Widget _buildActionButton(BuildContext context) {
    if (widget.model.downloadURL != null && widget.model.localPath == null) {
      // Model needs to be downloaded
      if (_isDownloading) {
        return Column(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            if (_downloadProgress > 0) ...[
              const SizedBox(height: AppSpacing.xSmall),
              Text(
                '${(_downloadProgress * 100).toInt()}%',
                style: AppTypography.caption2(context).copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
            ],
          ],
        );
      } else {
        return ElevatedButton(
          onPressed: _downloadModel,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.mediumLarge,
              vertical: AppSpacing.smallMedium,
            ),
          ),
          child: Text(
            'Download',
            style: AppTypography.caption(context),
          ),
        );
      }
    } else if (widget.model.localPath != null) {
      // Model is downloaded
      if (widget.isSelected) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle,
              color: AppColors.statusGreen,
              size: 16,
            ),
            const SizedBox(width: AppSpacing.xSmall),
            Text(
              'Loaded',
              style: AppTypography.caption2(context).copyWith(
                color: AppColors.statusGreen,
              ),
            ),
          ],
        );
      } else {
        return ElevatedButton(
          onPressed: widget.onSelectModel,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.mediumLarge,
              vertical: AppSpacing.smallMedium,
            ),
          ),
          child: Text(
            'Load',
            style: AppTypography.caption(context),
          ),
        );
      }
    }
    return const SizedBox.shrink();
  }

  Future<void> _downloadModel() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      debugPrint('📥 Starting download for model: ${widget.model.name}');

      // Start the actual download using SDK
      final progressStream = sdk.RunAnywhere.downloadModel(widget.model.id);

      // Listen to real download progress
      await for (final progress in progressStream) {
        if (!mounted) return;

        final progressValue = progress.percentage;

        setState(() {
          _downloadProgress = progressValue;
        });

        // Check if completed or failed
        if (progress.state.isCompleted) {
          debugPrint('✅ Download completed for model: ${widget.model.name}');
          break;
        } else if (progress.state.isFailed) {
          debugPrint('❌ Download failed for model: ${widget.model.name}');
          throw Exception('Download failed');
        }
      }

      if (!mounted) return;
      setState(() {
        _isDownloading = false;
      });
      widget.onDownloadCompleted();
    } catch (e) {
      debugPrint('❌ Download error: $e');
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _downloadProgress = 0.0;
      });

      // Show error to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }
}

/// DeviceInfoRow widget
class DeviceInfoRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;

  const DeviceInfoRow({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.large,
        vertical: AppSpacing.smallMedium,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: AppSpacing.iconSmall,
            color: AppColors.primaryBlue,
          ),
          const SizedBox(width: AppSpacing.mediumLarge),
          Text(
            label,
            style: AppTypography.body(context),
          ),
          const Spacer(),
          Text(
            value,
            style: AppTypography.body(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// NeuralEngineRow widget
class NeuralEngineRow extends StatelessWidget {
  const NeuralEngineRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.large,
        vertical: AppSpacing.smallMedium,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.psychology,
            size: AppSpacing.iconSmall,
            color: AppColors.primaryBlue,
          ),
          const SizedBox(width: AppSpacing.mediumLarge),
          Text(
            'Neural Engine',
            style: AppTypography.body(context),
          ),
          const Spacer(),
          const Icon(
            Icons.check_circle,
            size: AppSpacing.iconSmall,
            color: AppColors.statusGreen,
          ),
        ],
      ),
    );
  }
}
