import 'dart:async';

import 'package:flutter/material.dart';

import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/core/models/app_types.dart';
import 'package:runanywhere_ai/core/services/device_info_service.dart';
import 'package:runanywhere_ai/features/models/add_model_from_url_view.dart';
import 'package:runanywhere_ai/features/models/model_components.dart';
import 'package:runanywhere_ai/features/models/model_list_view_model.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';

/// ModelsView (mirroring iOS SimplifiedModelsView.swift)
///
/// Main models view for managing AI models.
class ModelsView extends StatefulWidget {
  const ModelsView({super.key});

  @override
  State<ModelsView> createState() => _ModelsViewState();
}

class _ModelsViewState extends State<ModelsView> {
  final ModelListViewModel _viewModel = ModelListViewModel.shared;
  final DeviceInfoService _deviceInfo = DeviceInfoService.shared;

  ModelInfo? _selectedModel;
  LLMFramework? _expandedFramework;

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Models'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddModelSheet,
            tooltip: 'Add Model',
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          if (_viewModel.isLoading && _viewModel.availableModels.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: _loadInitialData,
            child: ListView(
              children: [
                _buildDeviceStatusSection(),
                _buildFrameworksSection(),
                if (_expandedFramework != null) _buildModelsSection(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDeviceStatusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Device Status'),
        ListenableBuilder(
          listenable: _deviceInfo,
          builder: (context, _) {
            final device = _deviceInfo.deviceInfo;
            if (device == null) {
              return _buildLoadingRow('Loading device info...');
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

  Widget _buildFrameworksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Available Frameworks'),
        if (_viewModel.availableFrameworks.isEmpty)
          _buildLoadingRow('Loading frameworks...')
        else
          ..._viewModel.availableFrameworks.map((framework) {
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

  Widget _buildModelsSection() {
    final framework = _expandedFramework;
    if (framework == null) return const SizedBox.shrink();

    final filteredModels = _viewModel.modelsForFramework(framework);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Models for ${framework.displayName}'),
        if (filteredModels.isEmpty)
          _buildEmptyModelsMessage()
        else
          ...filteredModels.map((model) {
            return ModelRow(
              model: model,
              isSelected: _selectedModel?.id == model.id,
              onDownloadCompleted: () async {
                await _viewModel.loadModels();
              },
              onSelectModel: () async {
                await _selectModel(model);
              },
              onModelUpdated: () async {
                await _viewModel.loadModels();
              },
            );
          }),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
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

  Widget _buildLoadingRow(String message) {
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

  Widget _buildEmptyModelsMessage() {
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
          const SizedBox(height: AppSpacing.smallMedium),
          Text(
            "Tap 'Add Model' to add a model from URL",
            style: AppTypography.caption2(context).copyWith(
              color: AppColors.statusBlue,
            ),
          ),
        ],
      ),
    );
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

  Future<void> _selectModel(ModelInfo model) async {
    setState(() {
      _selectedModel = model;
    });

    await _viewModel.selectModel(model);
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
