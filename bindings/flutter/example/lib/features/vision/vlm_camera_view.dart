import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/features/models/model_selection_sheet.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';
import 'package:runanywhere_ai/features/vision/vlm_view_model.dart';

/// VLMCameraView - Vision Language Model screen.
///
/// Mirrors the Android Kotlin VisionScreen: the user supplies an image from the
/// device gallery or the device camera app (via the OS picker — no in-app
/// camera preview), enters a prompt, and runs a streamed description over the
/// loaded VLM model. Styled with the app design system so it stays consistent
/// with the chat screen (theme-driven surfaces, no hardcoded black/white).
class VLMCameraView extends StatefulWidget {
  const VLMCameraView({super.key});

  @override
  State<VLMCameraView> createState() => _VLMCameraViewState();
}

class _VLMCameraViewState extends State<VLMCameraView> {
  late final VLMViewModel _viewModel;
  final ImagePicker _picker = ImagePicker();
  late final TextEditingController _promptController;

  @override
  void initState() {
    super.initState();
    _viewModel = VLMViewModel();
    _promptController = TextEditingController(text: _viewModel.prompt);
    _viewModel.addListener(_onViewModelChanged);
    unawaited(_viewModel.checkModelStatus());
  }

  void _onViewModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _viewModel.isModelLoaded
          ? _buildMainContent()
          : _buildModelRequiredContent(),
    );
  }

  // MARK: - AppBar

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Vision AI'),
      actions: [
        if (_viewModel.loadedModelName != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.small),
              child: Text(
                _viewModel.loadedModelName!,
                style: AppTypography.caption(context)
                    .copyWith(color: AppColors.textSecondary(context)),
              ),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.swap_horiz),
          tooltip: 'Change model',
          onPressed: _onSelectModel,
        ),
      ],
    );
  }

  // MARK: - Main Content

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildImagePreview(),
          const SizedBox(height: AppSpacing.large),
          _buildSourceButtons(),
          const SizedBox(height: AppSpacing.large),
          _buildPromptField(),
          const SizedBox(height: AppSpacing.mediumLarge),
          _buildDescribeButton(),
          const SizedBox(height: AppSpacing.large),
          _buildResult(),
        ],
      ),
    );
  }

  // MARK: - Image Preview

  Widget _buildImagePreview() {
    final path = _viewModel.selectedImagePath;
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.backgroundGray6(context),
          borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusModal),
          border: Border.all(color: AppColors.separator(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: path != null
            ? Image.file(File(path), fit: BoxFit.cover, width: double.infinity)
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.image_outlined,
                      size: 56,
                      color: AppColors.textSecondary(context),
                    ),
                    const SizedBox(height: AppSpacing.smallMedium),
                    Text(
                      'Pick or capture an image',
                      style: AppTypography.subheadline(context)
                          .copyWith(color: AppColors.textSecondary(context)),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // MARK: - Source Buttons (gallery + device camera)

  Widget _buildSourceButtons() {
    final disabled = _viewModel.isProcessing;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: disabled ? null : () => _pickImage(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Gallery'),
            style: OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(vertical: AppSpacing.mediumLarge),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.mediumLarge),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: disabled ? null : () => _pickImage(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Camera'),
            style: OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(vertical: AppSpacing.mediumLarge),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final xFile = await _picker.pickImage(source: source);
      if (xFile != null) {
        _viewModel.setSelectedImage(xFile.path);
      }
    } catch (e) {
      if (mounted) {
        unawaited(
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Failed to pick image: $e')))
              .closed
              .then((_) => null),
        );
      }
    }
  }

  // MARK: - Prompt

  Widget _buildPromptField() {
    return TextField(
      controller: _promptController,
      onChanged: (value) => _viewModel.prompt = value,
      minLines: 1,
      maxLines: 3,
      decoration: InputDecoration(
        hintText: 'Describe this image…',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusBubble),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.large,
          vertical: AppSpacing.mediumLarge,
        ),
      ),
    );
  }

  // MARK: - Describe / Stop

  Widget _buildDescribeButton() {
    final isProcessing = _viewModel.isProcessing;
    final canDescribe = _viewModel.selectedImagePath != null && !isProcessing;
    return FilledButton.icon(
      onPressed: isProcessing
          ? () => unawaited(_viewModel.cancelGeneration())
          : (canDescribe
              ? () => unawaited(_viewModel.describeSelectedImage())
              : null),
      icon: Icon(isProcessing ? Icons.stop : Icons.auto_awesome),
      label: Text(isProcessing ? 'Stop' : 'Describe'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.mediumLarge),
      ),
    );
  }

  // MARK: - Result

  Widget _buildResult() {
    if (_viewModel.error != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.large),
        decoration: BoxDecoration(
          color: AppColors.primaryRed.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusModal),
          border: Border.all(color: AppColors.primaryRed.withValues(alpha: 0.3)),
        ),
        child: Text(
          _viewModel.error!,
          style: AppTypography.caption(context)
              .copyWith(color: AppColors.primaryRed),
        ),
      );
    }

    if (_viewModel.isProcessing && _viewModel.currentDescription.isEmpty) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.smallMedium),
          Text(
            'Analyzing image…',
            style: AppTypography.subheadline(context),
          ),
        ],
      );
    }

    if (_viewModel.currentDescription.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.backgroundGray6(context),
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusModal),
        border: Border.all(color: AppColors.separator(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Description',
                style: AppTypography.headline(context)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                color: AppColors.textSecondary(context),
                visualDensity: VisualDensity.compact,
                onPressed: _copyDescription,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.smallMedium),
          Text(
            _viewModel.currentDescription,
            style: AppTypography.body(context),
          ),
        ],
      ),
    );
  }

  void _copyDescription() {
    unawaited(
        Clipboard.setData(ClipboardData(text: _viewModel.currentDescription)));
    unawaited(
      ScaffoldMessenger.of(context)
          .showSnackBar(
            const SnackBar(
              content: Text('Description copied to clipboard'),
              duration: Duration(seconds: 2),
            ),
          )
          .closed
          .then((_) => null),
    );
  }

  // MARK: - Model Selection

  Future<void> _onSelectModel() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ModelSelectionSheet(
        context: ModelSelectionContext.vlm,
        onModelSelected: (model) async {
          await _viewModel.onModelSelected(model.id, model.name, this.context);
        },
      ),
    );
  }

  // MARK: - Model Required Content

  Widget _buildModelRequiredContent() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.center_focus_strong,
              size: 60,
              color: AppColors.textSecondary(context),
            ),
            const SizedBox(height: AppSpacing.xLarge),
            Text(
              'Vision AI',
              style: AppTypography.titleBold(context),
            ),
            const SizedBox(height: AppSpacing.smallMedium),
            Text(
              'Select a vision model to describe images',
              style: AppTypography.subheadline(context)
                  .copyWith(color: AppColors.textSecondary(context)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xxLarge),
            FilledButton.icon(
              onPressed: _onSelectModel,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Select Model'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxLarge,
                  vertical: AppSpacing.mediumLarge,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
