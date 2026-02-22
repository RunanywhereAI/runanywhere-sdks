import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/features/vision/vlm_camera_view.dart';

/// VisionHubView (mirroring iOS VisionHubView)
///
/// Hub navigation for Vision AI features: VLM camera chat and image generation
class VisionHubView extends StatelessWidget {
  const VisionHubView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vision'),
      ),
      body: ListView(
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.large,
              AppSpacing.large,
              AppSpacing.large,
              AppSpacing.smallMedium,
            ),
            child: Text(
              'Vision AI',
              style: AppTypography.caption(context).copyWith(
                color: AppColors.textSecondary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // Vision Chat - Navigate to VLM camera
          ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryPurple,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.center_focus_strong,
                color: Colors.white,
              ),
            ),
            title: const Text('Vision Chat'),
            subtitle: const Text('Chat with images using your camera or photos'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              unawaited(
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (context) => const VLMCameraView(),
                  ),
                ),
              );
            },
          ),

          // Image Generation - Disabled/grayed (coming soon)
          ListTile(
            enabled: false,
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.indigo.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.auto_awesome,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            title: Text(
              'Image Generation',
              style: TextStyle(
                color: AppColors.textSecondary(context).withValues(alpha: 0.5),
              ),
            ),
            subtitle: Text(
              'Create images with Stable Diffusion',
              style: TextStyle(
                color: AppColors.textSecondary(context).withValues(alpha: 0.5),
              ),
            ),
          ),

          // Section footer
          Padding(
            padding: const EdgeInsets.all(AppSpacing.large),
            child: Text(
              'Understand and create visual content with AI',
              style: AppTypography.caption(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
