import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/features/models/model_selection_sheet.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';
import 'package:runanywhere_ai/features/vision/vlm_view_model.dart';

/// VLMCameraView - Camera view for Vision Language Model
///
/// Mirrors iOS VLMCameraView.swift exactly:
/// - Camera preview (45% screen height)
/// - Description panel with streaming text
/// - Control bar with 4 buttons (Photos, Main action, Live, Model)
/// - Model-required screen when no model loaded
/// - Auto-streaming with 2.5s interval
/// - Single capture and gallery modes
class VLMCameraView extends StatefulWidget {
  const VLMCameraView({super.key});

  @override
  State<VLMCameraView> createState() => _VLMCameraViewState();
}

class _VLMCameraViewState extends State<VLMCameraView> {
  late VLMViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = VLMViewModel();

    // Listen to view model changes
    _viewModel.addListener(_onViewModelChanged);

    // Initialize
    _initializeAsync();
  }

  void _initializeAsync() {
    unawaited(
      _viewModel.checkModelStatus().then((_) async {
        if (mounted) {
          await _viewModel.checkCameraAuthorization(context);
          if (_viewModel.isCameraAuthorized) {
            unawaited(_viewModel.initializeCamera());
          }
        }
      }),
    );
  }

  void _onViewModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _viewModel.stopAutoStreaming();
    _viewModel.disposeCamera();
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          if (_viewModel.isModelLoaded) _buildMainContent() else _buildModelRequiredContent(),
        ],
      ),
    );
  }

  // MARK: - AppBar

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Vision AI'),
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      actions: [
        if (_viewModel.loadedModelName != null)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.large),
            child: Center(
              child: Text(
                _viewModel.loadedModelName!,
                style: AppTypography.caption(context).copyWith(
                  color: Colors.grey,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // MARK: - Main Content

  Widget _buildMainContent() {
    return Column(
      children: [
        // Camera preview (45% screen height)
        _buildCameraPreview(),

        // Description panel (flexible)
        Expanded(child: _buildDescriptionPanel()),

        // Control bar (fixed at bottom)
        _buildControlBar(),
      ],
    );
  }

  // MARK: - Camera Preview

  Widget _buildCameraPreview() {
    final screenHeight = MediaQuery.of(context).size.height;
    final cameraHeight = screenHeight * 0.45;

    return SizedBox(
      height: cameraHeight,
      child: Stack(
        children: [
          // Camera preview or permission view
          if (_viewModel.isCameraAuthorized) _buildCameraPreviewContent() else _buildCameraPermissionView(),

          // Processing overlay
          if (_viewModel.isProcessing) _buildProcessingOverlay(),
        ],
      ),
    );
  }

  Widget _buildCameraPreviewContent() {
    if (!_viewModel.isCameraInitialized || _viewModel.cameraController == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Container(
      color: Colors.black,
      child: CameraPreview(_viewModel.cameraController!),
    );
  }

  Widget _buildCameraPermissionView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.camera_alt, size: 60, color: Colors.grey),
          const SizedBox(height: AppSpacing.mediumLarge),
          Text(
            'Camera Access Required',
            style: AppTypography.headline(context).copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.mediumLarge),
          ElevatedButton(
            onPressed: () {
              unawaited(
                _viewModel.checkCameraAuthorization(context).then((_) {
                  if (_viewModel.isCameraAuthorized) {
                    unawaited(_viewModel.initializeCamera());
                  }
                }),
              );
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    return Positioned(
      bottom: AppSpacing.large,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.large,
            vertical: AppSpacing.mediumLarge,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusModal),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: AppSpacing.smallMedium),
              Text(
                'Analyzing...',
                style: AppTypography.subheadline(context).copyWith(
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // MARK: - Description Panel

  Widget _buildDescriptionPanel() {
    return Container(
      color: AppColors.backgroundPrimary(context),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.large,
        vertical: AppSpacing.regular,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: "Description" + LIVE indicator + Copy button
          Row(
            children: [
              Text(
                'Description',
                style: AppTypography.headline(context).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: AppSpacing.small),
              if (_viewModel.isAutoStreamingEnabled) _buildLiveIndicator(),
              const Spacer(),
              if (_viewModel.currentDescription.isNotEmpty) _buildCopyButton(),
            ],
          ),
          const SizedBox(height: AppSpacing.mediumLarge),

          // Scrollable description text
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                _viewModel.currentDescription.isEmpty
                    ? 'Tap the button to describe what your camera sees'
                    : _viewModel.currentDescription,
                style: AppTypography.body(context).copyWith(
                  color: _viewModel.currentDescription.isEmpty
                      ? AppColors.textSecondary(context)
                      : AppColors.textPrimary(context),
                ),
              ),
            ),
          ),

          // Error text
          if (_viewModel.error != null) ...[
            const SizedBox(height: AppSpacing.mediumLarge),
            Text(
              _viewModel.error!,
              style: AppTypography.caption(context).copyWith(
                color: Colors.red,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          'LIVE',
          style: AppTypography.caption2Bold(context).copyWith(
            color: Colors.green,
          ),
        ),
      ],
    );
  }

  Widget _buildCopyButton() {
    return IconButton(
      icon: const Icon(Icons.copy, size: 18),
      color: AppColors.textSecondary(context),
      onPressed: () {
        unawaited(Clipboard.setData(ClipboardData(text: _viewModel.currentDescription)));
        unawaited(
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Description copied to clipboard'),
              duration: Duration(seconds: 2),
            ),
          ).closed.then((_) => null),
        );
      },
    );
  }

  // MARK: - Control Bar

  Widget _buildControlBar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.large),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildPhotosButton(),
          const SizedBox(width: 32),
          _buildMainActionButton(),
          const SizedBox(width: 32),
          _buildLiveToggleButton(),
          const SizedBox(width: 32),
          _buildModelButton(),
        ],
      ),
    );
  }

  Widget _buildPhotosButton() {
    return GestureDetector(
      onTap: _onPhotosButtonTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo, size: 28, color: Colors.white),
          const SizedBox(height: 4),
          Text(
            'Photos',
            style: AppTypography.caption2(context).copyWith(
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onPhotosButtonTap() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery);
    if (xFile != null) {
      await _viewModel.describePickedImage(xFile.path);
    }
  }

  Widget _buildMainActionButton() {
    final isProcessing = _viewModel.isProcessing;
    final isAutoStreaming = _viewModel.isAutoStreamingEnabled;
    final isDisabled = isProcessing && !isAutoStreaming;

    Color buttonColor;
    if (isAutoStreaming) {
      buttonColor = Colors.red;
    } else if (isProcessing) {
      buttonColor = Colors.grey;
    } else {
      buttonColor = Colors.orange;
    }

    return GestureDetector(
      onTap: isDisabled ? null : _onMainActionButtonTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: buttonColor,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: isProcessing
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  isAutoStreaming ? Icons.stop : Icons.auto_awesome,
                  color: Colors.white,
                  size: isAutoStreaming ? 28 : 32,
                ),
        ),
      ),
    );
  }

  Future<void> _onMainActionButtonTap() async {
    if (_viewModel.isAutoStreamingEnabled) {
      _viewModel.stopAutoStreaming();
    } else {
      await _viewModel.describeCurrentFrame();
    }
  }

  Widget _buildLiveToggleButton() {
    final isActive = _viewModel.isAutoStreamingEnabled;
    final color = isActive ? Colors.green : Colors.white;

    return GestureDetector(
      onTap: () {
        _viewModel.toggleAutoStreaming();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 28, color: color),
          const SizedBox(height: 4),
          Text(
            'Live',
            style: AppTypography.caption2(context).copyWith(
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelButton() {
    return GestureDetector(
      onTap: _onModelButtonTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.view_in_ar, size: 28, color: Colors.white),
          const SizedBox(height: 4),
          Text(
            'Model',
            style: AppTypography.caption2(context).copyWith(
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onModelButtonTap() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ModelSelectionSheet(
        context: ModelSelectionContext.vlm,
        onModelSelected: (model) async {
          await _viewModel.onModelSelected(model.id, model.name, this.context);
          // Initialize camera if authorized after model is loaded
          if (_viewModel.isCameraAuthorized && !_viewModel.isCameraInitialized) {
            unawaited(_viewModel.initializeCamera());
          }
        },
      ),
    );
  }

  // MARK: - Model Required Content

  Widget _buildModelRequiredContent() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.center_focus_strong,
            size: 60,
            color: Colors.orange,
          ),
          const SizedBox(height: AppSpacing.xLarge),
          Text(
            'Vision AI',
            style: AppTypography.titleBold(context).copyWith(
              color: Colors.white,
            ),
          ),
          const SizedBox(height: AppSpacing.mediumLarge),
          Text(
            'Select a vision model to describe images',
            style: AppTypography.subheadline(context).copyWith(
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: AppSpacing.xxLarge),
          ElevatedButton.icon(
            onPressed: _onModelButtonTap,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Select Model'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxLarge,
                vertical: AppSpacing.mediumLarge,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
