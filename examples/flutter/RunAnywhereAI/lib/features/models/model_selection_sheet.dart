import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;

import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/core/models/app_types.dart';
import 'package:runanywhere_ai/core/services/device_info_service.dart';
import 'package:runanywhere_ai/features/models/model_list_view_model.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';

/// ModelSelectionSheet (mirroring iOS ModelSelectionSheet.swift)
///
/// Reusable model selection sheet with flat list of models (no framework expansion).
/// Models are filtered by context and sorted by availability (built-in first,
/// then downloaded, then available for download).
class ModelSelectionSheet extends StatefulWidget {
  final ModelSelectionContext context;
  final Future<void> Function(ModelInfo) onModelSelected;

  const ModelSelectionSheet({
    super.key,
    this.context = ModelSelectionContext.llm,
    required this.onModelSelected,
  });

  @override
  State<ModelSelectionSheet> createState() => _ModelSelectionSheetState();
}

class _ModelSelectionSheetState extends State<ModelSelectionSheet> {
  final ModelListViewModel _viewModel = ModelListViewModel.shared;
  final DeviceInfoService _deviceInfo = DeviceInfoService.shared;

  ModelInfo? _selectedModel;
  bool _isLoadingModel = false;
  String _loadingProgress = '';

  /// Get all models relevant to this context, sorted by availability
  List<ModelInfo> get _availableModels {
    final models = _viewModel.availableModels.where((model) {
      return widget.context.relevantCategories.contains(model.category);
    }).toList();

    // Sort: Foundation Models first (built-in), then downloaded, then not downloaded
    models.sort((a, b) {
      final aPriority = a.preferredFramework == LLMFramework.foundationModels
          ? 0
          : (a.localPath != null ? 1 : 2);
      final bPriority = b.preferredFramework == LLMFramework.foundationModels
          ? 0
          : (b.localPath != null ? 1 : 2);
      if (aPriority != bPriority) {
        return aPriority.compareTo(bPriority);
      }
      return a.name.compareTo(b.name);
    });

    return models;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadInitialData());
  }

  Future<void> _loadInitialData() async {
    await _viewModel.loadModels();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: AppColors.backgroundPrimary(context),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSpacing.cornerRadiusXLarge),
        ),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: ListenableBuilder(
                  listenable: _viewModel,
                  builder: (context, _) {
                    if (_viewModel.isLoading &&
                        _viewModel.availableModels.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    return ListView(
                      children: [
                        _buildDeviceStatusSection(context),
                        _buildModelsListSection(context),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          if (_isLoadingModel) _buildLoadingOverlay(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.separator(context),
          ),
        ),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: _isLoadingModel ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          Expanded(
            child: Text(
              widget.context.title,
              style: AppTypography.headline(context),
              textAlign: TextAlign.center,
            ),
          ),
          // Spacer to balance the Cancel button
          const SizedBox(width: 70),
        ],
      ),
    );
  }

  Widget _buildDeviceStatusSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Device Status'),
        ListenableBuilder(
          listenable: _deviceInfo,
          builder: (context, _) {
            final device = _deviceInfo.deviceInfo;
            if (device == null) {
              return _buildLoadingRow(context, 'Loading device info...');
            }
            return Column(
              children: [
                _buildDeviceInfoRow(
                  context,
                  label: 'Model',
                  icon: Icons.phone_iphone,
                  value: device.modelName,
                ),
                _buildDeviceInfoRow(
                  context,
                  label: 'Chip',
                  icon: Icons.memory,
                  value: device.chipName,
                ),
                _buildDeviceInfoRow(
                  context,
                  label: 'Memory',
                  icon: Icons.storage,
                  value: device.totalMemory.formattedFileSize,
                ),
                if (device.neuralEngineAvailable)
                  _buildDeviceInfoRow(
                    context,
                    label: 'Neural Engine',
                    icon: Icons.psychology,
                    value: '',
                    trailing: const Icon(
                      Icons.check_circle,
                      color: AppColors.statusGreen,
                      size: 18,
                    ),
                  ),
              ],
            );
          },
        ),
        const Divider(),
      ],
    );
  }

  Widget _buildDeviceInfoRow(
    BuildContext context, {
    required String label,
    required IconData icon,
    required String value,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.large,
        vertical: AppSpacing.smallMedium,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary(context)),
          const SizedBox(width: AppSpacing.smallMedium),
          Text(label, style: AppTypography.body(context)),
          const Spacer(),
          if (trailing != null)
            trailing
          else
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

  /// Flat list of all available models with framework badges (matches iOS)
  Widget _buildModelsListSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Choose a Model'),

        if (_availableModels.isEmpty)
          _buildEmptyModelsMessage(context)
        else ...[
          // System TTS option for TTS context
          if (widget.context == ModelSelectionContext.tts)
            _buildSystemTTSRow(context),

          // All models in a flat list
          ..._availableModels.map((model) {
            return _FlatModelRow(
              model: model,
              isSelected: _selectedModel?.id == model.id,
              isLoading: _isLoadingModel,
              onDownloadCompleted: () async {
                await _viewModel.loadModels();
              },
              onSelectModel: () async {
                await _selectAndLoadModel(model);
              },
              onModelUpdated: () async {
                await _viewModel.loadModels();
              },
            );
          }),
        ],

        // Footer text
        Padding(
          padding: const EdgeInsets.all(AppSpacing.large),
          child: Text(
            'All models run privately on your device. Larger models may '
            'provide better quality but use more memory.',
            style: AppTypography.caption(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSystemTTSRow(BuildContext context) {
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
                // Name with badge
                Row(
                  children: [
                    Text(
                      'System Voice',
                      style: AppTypography.subheadline(context).copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.smallMedium),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.small,
                        vertical: AppSpacing.xxSmall,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.textPrimary(context)
                            .withValues(alpha: 0.1),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.cornerRadiusSmall),
                      ),
                      child: Text(
                        'System',
                        style: AppTypography.caption2(context).copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xSmall),
                // Status
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 12,
                      color: AppColors.statusGreen,
                    ),
                    const SizedBox(width: AppSpacing.xxSmall),
                    Text(
                      'Built-in • Always available',
                      style: AppTypography.caption2(context).copyWith(
                        color: AppColors.statusGreen,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _isLoadingModel ? null : _selectSystemTTS,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.mediumLarge,
                vertical: AppSpacing.small,
              ),
            ),
            child: const Text('Use'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay(BuildContext context) {
    return Container(
      color: AppColors.overlayMedium,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xxLarge),
          decoration: BoxDecoration(
            color: AppColors.backgroundPrimary(context),
            borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusXLarge),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowDark,
                blurRadius: AppSpacing.shadowXLarge,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.xLarge),
              Text(
                'Loading Model',
                style: AppTypography.headline(context),
              ),
              const SizedBox(height: AppSpacing.smallMedium),
              Text(
                _loadingProgress,
                style: AppTypography.subheadline(context).copyWith(
                  color: AppColors.textSecondary(context),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.large,
        AppSpacing.large,
        AppSpacing.large,
        AppSpacing.smallMedium,
      ),
      child: Text(
        title,
        style: AppTypography.caption(context).copyWith(
          color: AppColors.textSecondary(context),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildLoadingRow(BuildContext context, String message) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.mediumLarge),
          Text(
            message,
            style: AppTypography.body(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyModelsMessage(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xLarge),
      child: Center(
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.mediumLarge),
            Text(
              'Loading available models...',
              style: AppTypography.subheadline(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectSystemTTS() async {
    setState(() {
      _isLoadingModel = true;
      _loadingProgress = 'Configuring System TTS...';
    });

    // Create pseudo ModelInfo for System TTS
    const systemTTSModel = ModelInfo(
      id: 'system-tts',
      name: 'System TTS',
      category: ModelCategory.speechSynthesis,
      format: ModelFormat.unknown,
      compatibleFrameworks: [LLMFramework.systemTTS],
      preferredFramework: LLMFramework.systemTTS,
    );

    await Future<void>.delayed(const Duration(milliseconds: 300));

    setState(() {
      _loadingProgress = 'System TTS ready!';
    });

    await Future<void>.delayed(const Duration(milliseconds: 200));

    await widget.onModelSelected(systemTTSModel);

    if (mounted) {
      setState(() {
        _isLoadingModel = false;
      });
      Navigator.pop(context);
    }
  }

  Future<void> _selectAndLoadModel(ModelInfo model) async {
    // Foundation Models don't need local path check
    if (model.preferredFramework != LLMFramework.foundationModels) {
      if (model.localPath == null) {
        return; // Model not downloaded yet
      }
    }

    setState(() {
      _isLoadingModel = true;
      _loadingProgress = 'Initializing ${model.name}...';
      _selectedModel = model;
    });

    try {
      setState(() {
        _loadingProgress = 'Loading model into memory...';
      });

      // Load model based on context/modality using real SDK
      switch (widget.context) {
        case ModelSelectionContext.llm:
          debugPrint('🎯 Loading LLM model: ${model.id}');
          await sdk.RunAnywhere.loadModel(model.id);
          break;
        case ModelSelectionContext.stt:
          debugPrint('🎯 Loading STT model: ${model.id}');
          await sdk.RunAnywhere.loadSTTModel(model.id);
          break;
        case ModelSelectionContext.tts:
          debugPrint('🎯 Loading TTS voice: ${model.id}');
          await sdk.RunAnywhere.loadTTSVoice(model.id);
          break;
        case ModelSelectionContext.voice:
          // Determine based on model category
          if (model.category == ModelCategory.speechRecognition) {
            debugPrint('🎯 Loading Voice STT model: ${model.id}');
            await sdk.RunAnywhere.loadSTTModel(model.id);
          } else if (model.category == ModelCategory.speechSynthesis) {
            debugPrint('🎯 Loading Voice TTS voice: ${model.id}');
            await sdk.RunAnywhere.loadTTSVoice(model.id);
          } else {
            debugPrint('🎯 Loading Voice LLM model: ${model.id}');
            await sdk.RunAnywhere.loadModel(model.id);
          }
          break;
      }

      setState(() {
        _loadingProgress = 'Model loaded successfully!';
      });

      await Future<void>.delayed(const Duration(milliseconds: 300));

      await _viewModel.selectModel(model);
      await widget.onModelSelected(model);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('❌ Failed to load model: $e');
      setState(() {
        _isLoadingModel = false;
        _loadingProgress = '';
        _selectedModel = null;
      });

      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load model: $e')),
        );
      }
    }
  }
}

/// Flat model row for the selection sheet (matches iOS FlatModelRow)
class _FlatModelRow extends StatefulWidget {
  final ModelInfo model;
  final bool isSelected;
  final bool isLoading;
  final VoidCallback onDownloadCompleted;
  final VoidCallback onSelectModel;
  final VoidCallback? onModelUpdated;

  const _FlatModelRow({
    required this.model,
    required this.isSelected,
    required this.isLoading,
    required this.onDownloadCompleted,
    required this.onSelectModel,
    this.onModelUpdated,
  });

  @override
  State<_FlatModelRow> createState() => _FlatModelRowState();
}

class _FlatModelRowState extends State<_FlatModelRow> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  Color get _frameworkColor {
    final framework = widget.model.preferredFramework;
    if (framework == null) return Colors.grey;
    switch (framework) {
      case LLMFramework.llamaCpp:
        return AppColors.primaryBlue;
      case LLMFramework.onnxRuntime:
        return Colors.purple;
      case LLMFramework.foundationModels:
        return Colors.grey;
      case LLMFramework.whisperKit:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String get _frameworkName {
    final framework = widget.model.preferredFramework;
    if (framework == null) return 'Unknown';
    switch (framework) {
      case LLMFramework.llamaCpp:
        return 'Fast';
      case LLMFramework.onnxRuntime:
        return 'ONNX';
      case LLMFramework.foundationModels:
        return 'Apple';
      case LLMFramework.whisperKit:
        return 'Whisper';
      default:
        return framework.displayName;
    }
  }

  IconData get _statusIcon {
    if (widget.model.preferredFramework == LLMFramework.foundationModels) {
      return Icons.check_circle;
    } else if (widget.model.localPath != null) {
      return Icons.check_circle;
    } else {
      return Icons.download;
    }
  }

  Color get _statusColor {
    if (widget.model.preferredFramework == LLMFramework.foundationModels ||
        widget.model.localPath != null) {
      return AppColors.statusGreen;
    } else {
      return AppColors.primaryBlue;
    }
  }

  String get _statusText {
    if (widget.model.preferredFramework == LLMFramework.foundationModels) {
      return 'Built-in';
    } else if (widget.model.localPath != null) {
      return 'Ready';
    } else {
      return 'Download';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.isLoading && !widget.isSelected ? 0.6 : 1.0,
      child: Padding(
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
                  // Model name with framework badge inline
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.model.name,
                          style: AppTypography.subheadline(context).copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.smallMedium),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.small,
                          vertical: AppSpacing.xxSmall,
                        ),
                        decoration: BoxDecoration(
                          color: _frameworkColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(
                              AppSpacing.cornerRadiusSmall),
                        ),
                        child: Text(
                          _frameworkName,
                          style: AppTypography.caption2(context).copyWith(
                            fontWeight: FontWeight.w500,
                            color: _frameworkColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xSmall),
                  // Size and status row
                  Row(
                    children: [
                      // Size badge
                      if (widget.model.memoryRequired != null &&
                          widget.model.memoryRequired! > 0) ...[
                        Icon(
                          Icons.memory,
                          size: 12,
                          color: AppColors.textSecondary(context),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.model.memoryRequired!.formattedFileSize,
                          style: AppTypography.caption2(context).copyWith(
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.smallMedium),
                      ],
                      // Status indicator
                      if (_isDownloading) ...[
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: _downloadProgress > 0
                                ? _downloadProgress
                                : null,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xSmall),
                        Text(
                          '${(_downloadProgress * 100).toInt()}%',
                          style: AppTypography.caption2(context).copyWith(
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ] else ...[
                        Icon(
                          _statusIcon,
                          size: 12,
                          color: _statusColor,
                        ),
                        const SizedBox(width: AppSpacing.xxSmall),
                        Text(
                          _statusText,
                          style: AppTypography.caption2(context).copyWith(
                            color: _statusColor,
                          ),
                        ),
                      ],
                      // Thinking support indicator
                      if (widget.model.supportsThinking) ...[
                        const SizedBox(width: AppSpacing.smallMedium),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.small,
                            vertical: AppSpacing.xxSmall,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.badgePurple,
                            borderRadius: BorderRadius.circular(
                                AppSpacing.cornerRadiusSmall),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.psychology,
                                size: 10,
                                color: AppColors.primaryPurple,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                'Smart',
                                style: AppTypography.caption2(context).copyWith(
                                  color: AppColors.primaryPurple,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.mediumLarge),
            _buildActionButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context) {
    if (widget.model.preferredFramework == LLMFramework.foundationModels) {
      // Foundation Models are built-in
      return ElevatedButton(
        onPressed:
            widget.isLoading || widget.isSelected ? null : widget.onSelectModel,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.mediumLarge,
            vertical: AppSpacing.small,
          ),
        ),
        child: const Text('Use'),
      );
    }

    if (widget.model.localPath == null) {
      // Model needs to be downloaded
      if (_isDownloading) {
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      }
      return OutlinedButton.icon(
        onPressed: widget.isLoading ? null : _downloadModel,
        icon: const Icon(Icons.download, size: 16),
        label: const Text('Get'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.mediumLarge,
            vertical: AppSpacing.small,
          ),
        ),
      );
    }

    // Model is downloaded - ready to use
    return ElevatedButton(
      onPressed:
          widget.isLoading || widget.isSelected ? null : widget.onSelectModel,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.mediumLarge,
          vertical: AppSpacing.small,
        ),
      ),
      child: const Text('Use'),
    );
  }

  Future<void> _downloadModel() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      debugPrint('📥 Starting download for model: ${widget.model.name}');

      // Get the SDK model by ID
      final sdkModels = await sdk.RunAnywhere.availableModels();
      final sdkModel = sdkModels.firstWhere(
        (m) => m.id == widget.model.id,
        orElse: () =>
            throw Exception('Model not found in registry: ${widget.model.id}'),
      );

      // Start the actual download using SDK's downloadModel
      final downloadProgress = sdk.RunAnywhere.downloadModel(sdkModel.id);

      // Listen to real download progress
      await for (final progress in downloadProgress) {
        if (!mounted) return;

        final progressValue = progress.totalBytes > 0
            ? progress.bytesDownloaded / progress.totalBytes
            : 0.0;

        setState(() {
          _downloadProgress = progressValue;
        });

        // Check if completed or failed
        if (progress.state == sdk.DownloadProgressState.completed) {
          debugPrint('✅ Download completed for model: ${widget.model.name}');
          break;
        } else if (progress.state == sdk.DownloadProgressState.failed) {
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

/// Helper function to show model selection sheet
Future<ModelInfo?> showModelSelectionSheet(
  BuildContext context, {
  ModelSelectionContext modelContext = ModelSelectionContext.llm,
}) async {
  ModelInfo? selectedModel;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => ModelSelectionSheet(
      context: modelContext,
      onModelSelected: (model) async {
        selectedModel = model;
      },
    ),
  );

  return selectedModel;
}
