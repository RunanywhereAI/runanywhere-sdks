import 'dart:async';

import 'package:flutter/material.dart';

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

  /// Get all models relevant to this context, sorted by availability.
  /// Filtering (category + framework allow-list + supporting-file
  /// exclusion) is the shared `ModelSelectionContext.includes` predicate,
  /// mirroring iOS `ModelSelectionSheet.availableModels`.
  List<ModelInfo> get _availableModels {
    final models =
        _viewModel.availableModels.where(widget.context.includes).toList();

    // Sort: built-in models first (Foundation Models / System TTS), then
    // downloaded, then not downloaded. On-disk readiness is `localPath`; the
    // built-in cases are handled explicitly below (see
    // ExampleModelInfoView.isReadyOnDevice in model_types.dart).
    int priorityFor(ModelInfo m) {
      if (m.preferredFramework ==
              LLMFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS ||
          m.preferredFramework ==
              LLMFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS) {
        return 0;
      }
      return m.localPath.isNotEmpty ? 1 : 2;
    }

    models.sort((a, b) {
      final aPriority = priorityFor(a);
      final bPriority = priorityFor(b);
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
                if (device.totalMemory > 0)
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
          // System TTS is registered in runanywhere_ai_app.dart on Apple
          // platforms with framework=INFERENCE_FRAMEWORK_SYSTEM_TTS, so it
          // flows through the regular _FlatModelRow path below (treated as
          // built-in alongside Foundation Models). A second manual row would
          // produce duplicate entries on iOS/macOS.
          ..._availableModels.map((model) {
            return _FlatModelRow(
              model: model,
              isSelected: _selectedModel?.id == model.id,
              isLoading: _isLoadingModel,
              onSelectModel: () async {
                await _selectAndLoadModel(model);
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

  Future<void> _selectAndLoadModel(ModelInfo model) async {
    // Built-in models (Foundation Models, System TTS) have no local file and
    // must skip the localPath readiness gate; both flow through the regular
    // category-aware load path (e.g. SYSTEM_TTS -> RunAnywhere.tts.loadVoice
    // in ModelListViewModel.loadModel). Other frameworks still require a
    // downloaded artifact before we attempt to load them.
    //
    // Gate on `isReadyOnDevice` (localPath + built-in), NOT the proto
    // `isDownloaded` field — the C++ registry sets localPath on download but
    // leaves the proto flag false, so `model.isDownloaded` would always be
    // false here and silently no-op the load.
    if (!model.isReadyOnDevice) {
      return; // Model not downloaded yet
    }

    setState(() {
      _isLoadingModel = true;
      _loadingProgress = 'Initializing ${model.name}...';
      _selectedModel = model;
    });

    try {
      // Contexts where the generic ModelListViewModel preload must be skipped:
      //  - RAG contexts record the selection only; the RAG pipeline loads
      //    models on demand when documents are ingested.
      //  - VLM context: ModelListViewModel.loadModel only knows about LLM /
      //    STT / TTS, so multimodal entries fall through to RunAnywhere.llm.load.
      //    The VLM `onModelSelected` callback (VLMViewModel) loads via
      //    RunAnywhere.vlm.load, which is the only correct lifecycle here.
      final skipPreload =
          widget.context == ModelSelectionContext.ragEmbedding ||
              widget.context == ModelSelectionContext.ragLLM ||
              widget.context == ModelSelectionContext.vlm;

      if (!skipPreload) {
        // Update view model selection state (loads the model into memory)
        await _viewModel.selectModel(model);
      }

      // Call the callback - this is where the actual model loading happens
      // The callback knows the correct context and how to load the model
      debugPrint('🎯 Model selected: ${model.id}, calling callback to load');
      await widget.onModelSelected(model);

      if (mounted) {
        // Defer Navigator.pop until after the current frame completes
        // This prevents the !_debugLocked assertion when the callback triggers
        // navigation (e.g., loading a VLM model may trigger state changes)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.pop(context);
          }
        });
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
class _FlatModelRow extends StatelessWidget {
  final ModelInfo model;
  final bool isSelected;
  final bool isLoading;
  final VoidCallback onSelectModel;

  const _FlatModelRow({
    required this.model,
    required this.isSelected,
    required this.isLoading,
    required this.onSelectModel,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ModelListViewModel.shared,
      builder: (context, _) {
        final vm = ModelListViewModel.shared;
        final isDownloading = vm.isDownloading(model.id);
        final downloadProgress = vm.downloadProgress[model.id] ?? 0.0;
        return _FlatModelRowContent(
          model: model,
          isSelected: isSelected,
          isLoading: isLoading,
          isDownloading: isDownloading,
          downloadProgress: downloadProgress,
          onSelectModel: onSelectModel,
          onDownload: () {
            unawaited(
              ModelListViewModel.shared.downloadModel(model, (_) {}),
            );
          },
        );
      },
    );
  }
}

class _FlatModelRowContent extends StatelessWidget {
  final ModelInfo model;
  final bool isSelected;
  final bool isLoading;
  final bool isDownloading;
  final double downloadProgress;
  final VoidCallback onSelectModel;
  final VoidCallback onDownload;

  const _FlatModelRowContent({
    required this.model,
    required this.isSelected,
    required this.isLoading,
    required this.isDownloading,
    required this.downloadProgress,
    required this.onSelectModel,
    required this.onDownload,
  });

  Color get _frameworkColor {
    final framework = model.preferredFramework;
    switch (framework) {
      case LLMFramework.INFERENCE_FRAMEWORK_LLAMA_CPP:
        return AppColors.primaryBlue;
      case LLMFramework.INFERENCE_FRAMEWORK_ONNX:
        return Colors.purple;
      case LLMFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS:
        return Colors.grey;
      case LLMFramework.INFERENCE_FRAMEWORK_UNKNOWN:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String get _frameworkName {
    final framework = model.preferredFramework;
    switch (framework) {
      case LLMFramework.INFERENCE_FRAMEWORK_LLAMA_CPP:
        return 'Fast';
      case LLMFramework.INFERENCE_FRAMEWORK_ONNX:
        return 'ONNX';
      case LLMFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS:
        return 'Apple';
      case LLMFramework.INFERENCE_FRAMEWORK_UNKNOWN:
        return 'Whisper';
      default:
        return framework.displayName;
    }
  }

  bool get _isBuiltIn =>
      model.preferredFramework ==
          LLMFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS ||
      model.preferredFramework ==
          LLMFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS;

  IconData get _statusIcon {
    if (_isBuiltIn || model.localPath.isNotEmpty) {
      return Icons.check_circle;
    }
    return Icons.download;
  }

  Color get _statusColor {
    if (_isBuiltIn || model.localPath.isNotEmpty) {
      return AppColors.statusGreen;
    }
    return AppColors.primaryBlue;
  }

  String get _statusText {
    if (_isBuiltIn) {
      return 'Built-in';
    } else if (model.localPath.isNotEmpty) {
      return 'Ready';
    } else {
      return 'Download';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isLoading && !isSelected ? 0.6 : 1.0,
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
                          model.name,
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
                      if (model.memoryRequired != null &&
                          model.memoryRequired! > 0) ...[
                        Icon(
                          Icons.memory,
                          size: 12,
                          color: AppColors.textSecondary(context),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          model.memoryRequired!.formattedFileSize,
                          style: AppTypography.caption2(context).copyWith(
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.smallMedium),
                      ],
                      // Status indicator
                      if (isDownloading) ...[
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: downloadProgress > 0
                                ? downloadProgress
                                : null,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xSmall),
                        Text(
                          '${(downloadProgress * 100).toInt()}%',
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
                      if (model.supportsThinking) ...[
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
    // Built-in models (Foundation Models, System TTS) are always loadable —
    // they have no downloadable artifact, so show a Use button instead of a
    // Get/download action. Mirrors Swift's FlatModelRow which treats both
    // .foundationModels and .systemTts as `isBuiltIn`.
    if (_isBuiltIn) {
      return ElevatedButton(
        onPressed: isLoading || isSelected ? null : onSelectModel,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.mediumLarge,
            vertical: AppSpacing.small,
          ),
        ),
        child: const Text('Use'),
      );
    }

    if (model.localPath.isEmpty) {
      // Model needs to be downloaded
      if (isDownloading) {
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      }
      return OutlinedButton.icon(
        onPressed: isLoading ? null : onDownload,
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
      onPressed: isLoading || isSelected ? null : onSelectModel,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.mediumLarge,
          vertical: AppSpacing.small,
        ),
      ),
      child: const Text('Use'),
    );
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
