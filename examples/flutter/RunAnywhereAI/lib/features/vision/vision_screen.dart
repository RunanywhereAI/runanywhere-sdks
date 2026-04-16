import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runanywhere_ai/core/theme/app_colors.dart';
import 'package:runanywhere_ai/core/theme/app_spacing.dart';
import 'package:runanywhere_ai/core/theme/app_typography.dart';
import 'package:runanywhere_ai/core/types/model_selection_context.dart';
import 'package:runanywhere_ai/core/widgets/model_selection_sheet.dart';
import 'package:runanywhere_ai/features/vision/vision_controller.dart';
import 'package:runanywhere_ai/features/vision/vision_state.dart';

class VisionScreen extends ConsumerStatefulWidget {
  const VisionScreen({super.key});

  @override
  ConsumerState<VisionScreen> createState() => _VisionScreenState();
}

class _VisionScreenState extends ConsumerState<VisionScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(visionControllerProvider.notifier).initCamera();
    });
  }

  @override
  Widget build(BuildContext context) {
    final visionState = ref.watch(visionControllerProvider);
    final cam = ref.watch(cameraControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vision'),
        actions: [
          if (visionState.isAutoStreaming)
            Container(
              margin: const EdgeInsets.only(right: AppSpacing.md),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'LIVE',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: !visionState.isModelLoaded
          ? _NoModelView(
              theme: theme,
              onSelectModel: () async {
                final model = await showModelSelectionSheet(
                  context,
                  ref,
                  selectionContext: ModelSelectionContext.vlm,
                );
                if (model != null) {
                  ref.read(visionControllerProvider.notifier).refreshModelState();
                }
              },
            )
          : Column(
              children: [
                Expanded(
                  flex: 5,
                  child: _CameraPreview(cam: cam, theme: theme),
                ),
                Expanded(
                  flex: 4,
                  child: _DescriptionPanel(
                    description: visionState.description,
                    isProcessing: visionState.isProcessing,
                    theme: theme,
                  ),
                ),
                _ControlBar(
                  visionState: visionState,
                  controller:
                      ref.read(visionControllerProvider.notifier),
                  theme: theme,
                ),
              ],
            ),
    );
  }
}

class _NoModelView extends StatelessWidget {
  const _NoModelView({required this.theme, required this.onSelectModel});

  final ThemeData theme;
  final VoidCallback onSelectModel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.visibility_off_outlined,
            size: AppSpacing.iconHuge,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'No VLM model loaded',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Select a vision model to start',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          FilledButton.icon(
            onPressed: onSelectModel,
            icon: const Icon(Icons.view_in_ar),
            label: const Text('Select Model'),
          ),
        ],
      ),
    );
  }
}

class _CameraPreview extends StatelessWidget {
  const _CameraPreview({required this.cam, required this.theme});

  final CameraController? cam;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (cam == null || !cam!.value.isInitialized) {
      return ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }

    return ClipRect(child: CameraPreview(cam!));
  }
}

class _DescriptionPanel extends StatelessWidget {
  const _DescriptionPanel({
    required this.description,
    required this.isProcessing,
    required this.theme,
  });

  final String description;
  final bool isProcessing;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: AppSpacing.pagePadding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: description.isEmpty && !isProcessing
          ? Center(
              child: Text(
                'Tap capture to describe what the camera sees',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            )
          : SingleChildScrollView(
              child: isProcessing && description.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xxl),
                        child: CircularProgressIndicator(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    )
                  : Text(
                      description,
                      style: AppTypography.bodyMedium.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
            ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.visionState,
    required this.controller,
    required this.theme,
  });

  final VisionState visionState;
  final VisionController controller;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.xxl,
        right: AppSpacing.xxl,
        top: AppSpacing.md,
        bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            onPressed: controller.pickFromGallery,
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: 'Gallery',
          ),
          SizedBox(
            width: 64,
            height: 64,
            child: FilledButton(
              onPressed: visionState.isProcessing
                  ? null
                  : controller.captureAndDescribe,
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
              ),
              child: Icon(
                visionState.isProcessing
                    ? Icons.hourglass_top_rounded
                    : Icons.camera_alt_rounded,
                size: AppSpacing.iconLg,
              ),
            ),
          ),
          IconButton(
            onPressed: controller.toggleAutoStreaming,
            icon: Icon(
              visionState.isAutoStreaming
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle_outline,
            ),
            tooltip: visionState.isAutoStreaming ? 'Stop live' : 'Start live',
            color: visionState.isAutoStreaming ? AppColors.error : null,
          ),
        ],
      ),
    );
  }
}
