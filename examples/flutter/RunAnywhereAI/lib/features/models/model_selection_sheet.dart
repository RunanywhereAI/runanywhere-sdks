import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;

import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/core/models/app_types.dart';
import 'package:runanywhere_ai/core/services/device_info_service.dart';
import 'package:runanywhere_ai/features/models/add_model_from_url_view.dart';
import 'package:runanywhere_ai/features/models/model_components.dart';
import 'package:runanywhere_ai/features/models/model_list_view_model.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';

/// ModelSelectionSheet (mirroring iOS ModelSelectionSheet.swift)
///
/// Reusable model selection sheet that can be used across the app.
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
  LLMFramework? _expandedFramework;
  bool _isLoadingModel = false;
  String _loadingProgress = '';

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
                        _buildFrameworksSection(context),
                        if (_expandedFramework != null)
                          _buildModelsSection(context),
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
          TextButton(
            onPressed: _isLoadingModel ? null : _showAddModelSheet,
            child: const Text('Add'),
          ),
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
                DeviceInfoRow(
                  label: 'Model',
                  icon: Icons.phone_iphone,
                  value: device.modelName,
                ),
                DeviceInfoRow(
                  label: 'Chip',
                  icon: Icons.memory,
                  value: device.chipName,
                ),
                DeviceInfoRow(
                  label: 'Memory',
                  icon: Icons.storage,
                  value: device.totalMemory.formattedFileSize,
                ),
                if (device.neuralEngineAvailable) const NeuralEngineRow(),
              ],
            );
          },
        ),
        const Divider(),
      ],
    );
  }

  Widget _buildFrameworksSection(BuildContext context) {
    // Filter frameworks based on context
    final relevantFrameworks =
        _viewModel.availableFrameworks.where(_shouldShowFramework).toList();

    // Add system TTS for TTS context
    if (widget.context == ModelSelectionContext.tts &&
        !relevantFrameworks.contains(LLMFramework.systemTTS)) {
      relevantFrameworks.insert(0, LLMFramework.systemTTS);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Available Frameworks'),
        if (relevantFrameworks.isEmpty)
          _buildLoadingRow(context, 'Loading frameworks...')
        else
          ...relevantFrameworks.map((framework) {
            return FrameworkRow(
              framework: framework,
              isExpanded: _expandedFramework == framework,
              onTap: () => _toggleFramework(framework),
            );
          }),
        const Divider(),
      ],
    );
  }

  Widget _buildModelsSection(BuildContext context) {
    final framework = _expandedFramework;
    if (framework == null) return const SizedBox.shrink();

    // Special handling for System TTS
    if (framework == LLMFramework.systemTTS) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(context, 'System TTS'),
          _buildSystemTTSRow(context),
        ],
      );
    }

    // Filter models based on framework AND context
    final filteredModels = _viewModel.availableModels.where((model) {
      final frameworkMatch = framework == LLMFramework.foundationModels
          ? model.preferredFramework == LLMFramework.foundationModels
          : model.compatibleFrameworks.contains(framework);

      final categoryMatch =
          widget.context.relevantCategories.contains(model.category);

      return frameworkMatch && categoryMatch;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Models for ${framework.displayName}'),

        // Foundation Models notice
        if (framework == LLMFramework.foundationModels)
          _buildFoundationModelsNotice(context),

        if (filteredModels.isEmpty)
          _buildEmptyModelsMessage(context)
        else
          ...filteredModels.map((model) {
            return _SelectableModelRow(
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
    );
  }

  Widget _buildSystemTTSRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Default System Voice',
                  style: AppTypography.subheadline(context),
                ),
                const SizedBox(height: AppSpacing.xSmall),
                Row(
                  children: [
                    Icon(
                      Icons.volume_up,
                      size: 12,
                      color: AppColors.textSecondary(context),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Built-in',
                      style: AppTypography.caption2(context).copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.smallMedium),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.small,
                        vertical: AppSpacing.xxSmall,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.badgeGray,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.cornerRadiusSmall),
                      ),
                      child: Text(
                        'TTS',
                        style: AppTypography.caption2(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xSmall),
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 12,
                      color: AppColors.statusGreen,
                    ),
                    const SizedBox(width: AppSpacing.xSmall),
                    Text(
                      'Always available',
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
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }

  Widget _buildFoundationModelsNotice(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.large,
        vertical: AppSpacing.smallMedium,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info,
            size: 14,
            color: AppColors.statusBlue,
          ),
          const SizedBox(width: AppSpacing.smallMedium),
          Expanded(
            child: Text(
              'iOS 26+ with Apple Intelligence',
              style: AppTypography.caption(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
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
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No models available for this framework',
            style: AppTypography.caption(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
          if (_expandedFramework != LLMFramework.foundationModels) ...[
            const SizedBox(height: AppSpacing.smallMedium),
            Text(
              "Tap 'Add' to add a model from URL",
              style: AppTypography.caption2(context).copyWith(
                color: AppColors.statusBlue,
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _shouldShowFramework(LLMFramework framework) {
    final modelsForFramework = _viewModel.availableModels.where((model) {
      if (framework == LLMFramework.foundationModels) {
        return model.preferredFramework == LLMFramework.foundationModels;
      }
      return model.compatibleFrameworks.contains(framework);
    });

    return modelsForFramework.any(
        (model) => widget.context.relevantCategories.contains(model.category));
  }

  void _toggleFramework(LLMFramework framework) {
    setState(() {
      if (_expandedFramework == framework) {
        _expandedFramework = null;
      } else {
        _expandedFramework = framework;
      }
    });
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
      // ModelManager will automatically update via SDK events (observer pattern)
      switch (widget.context) {
        case ModelSelectionContext.llm:
          debugPrint('🎯 Loading LLM model: ${model.id}');
          // SDK will publish events, ModelManager listens and updates automatically
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

  void _showAddModelSheet() {
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => AddModelFromURLView(
        onModelAdded: (model) async {
          // Capture navigator before async gap
          final navigator = Navigator.of(sheetContext);
          await _viewModel.addImportedModel(model);
          if (mounted) navigator.pop();
        },
      ),
    ));
  }
}

/// Selectable model row for the selection sheet
class _SelectableModelRow extends StatefulWidget {
  final ModelInfo model;
  final bool isSelected;
  final bool isLoading;
  final VoidCallback onDownloadCompleted;
  final VoidCallback onSelectModel;
  final VoidCallback? onModelUpdated;

  const _SelectableModelRow({
    required this.model,
    required this.isSelected,
    required this.isLoading,
    required this.onDownloadCompleted,
    required this.onSelectModel,
    this.onModelUpdated,
  });

  @override
  State<_SelectableModelRow> createState() => _SelectableModelRowState();
}

class _SelectableModelRowState extends State<_SelectableModelRow> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

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
                  Text(
                    widget.model.name,
                    style: AppTypography.subheadline(context).copyWith(
                      fontWeight: widget.isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xSmall),
                  _buildModelInfo(context),
                  const SizedBox(height: AppSpacing.xSmall),
                  _buildStatus(context),
                ],
              ),
            ),
            _buildActionButton(context),
          ],
        ),
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
            ],
          ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.small,
            vertical: AppSpacing.xxSmall,
          ),
          decoration: BoxDecoration(
            color: AppColors.badgeGray,
            borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusSmall),
          ),
          child: Text(
            widget.model.format.rawValue.toUpperCase(),
            style: AppTypography.caption2(context),
          ),
        ),
        if (widget.model.supportsThinking)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.small,
              vertical: AppSpacing.xxSmall,
            ),
            decoration: BoxDecoration(
              color: AppColors.badgePurple,
              borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusSmall),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.psychology,
                    size: 10, color: AppColors.primaryPurple),
                const SizedBox(width: 2),
                Text(
                  'THINKING',
                  style: AppTypography.caption2(context).copyWith(
                    color: AppColors.primaryPurple,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStatus(BuildContext context) {
    if (widget.model.preferredFramework == LLMFramework.foundationModels) {
      return Row(
        children: [
          const Icon(
            Icons.check_circle,
            size: 12,
            color: AppColors.statusGreen,
          ),
          const SizedBox(width: AppSpacing.xSmall),
          Text(
            'Built-in',
            style: AppTypography.caption2(context).copyWith(
              color: AppColors.statusGreen,
            ),
          ),
        ],
      );
    }

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
        }
        return Text(
          'Available for download',
          style: AppTypography.caption2(context).copyWith(
            color: AppColors.statusBlue,
          ),
        );
      }
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
    return const SizedBox.shrink();
  }

  Widget _buildActionButton(BuildContext context) {
    if (widget.model.preferredFramework == LLMFramework.foundationModels) {
      return ElevatedButton(
        onPressed:
            widget.isLoading || widget.isSelected ? null : widget.onSelectModel,
        child: const Text('Select'),
      );
    }

    if (widget.model.downloadURL != null && widget.model.localPath == null) {
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
      }
      return ElevatedButton(
        onPressed: widget.isLoading ? null : _downloadModel,
        child: const Text('Download'),
      );
    }

    if (widget.model.localPath != null) {
      return ElevatedButton(
        onPressed:
            widget.isLoading || widget.isSelected ? null : widget.onSelectModel,
        child: const Text('Select'),
      );
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

      // Get the download service from SDK
      final downloadService = sdk.RunAnywhere.serviceContainer.downloadService;

      // Get the SDK model by ID
      final sdkModels = await sdk.RunAnywhere.availableModels();
      final sdkModel = sdkModels.firstWhere(
        (m) => m.id == widget.model.id,
        orElse: () =>
            throw Exception('Model not found in registry: ${widget.model.id}'),
      );

      // Start the actual download using SDK
      final downloadTask = await downloadService.downloadModel(sdkModel);

      // Listen to real download progress
      await for (final progress in downloadTask.progress) {
        if (!mounted) return;

        final progressValue = progress.totalBytes > 0
            ? progress.bytesDownloaded / progress.totalBytes
            : 0.0;

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
