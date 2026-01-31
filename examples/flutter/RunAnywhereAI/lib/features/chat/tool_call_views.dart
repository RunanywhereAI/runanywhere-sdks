import 'package:flutter/material.dart';
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';

/// Tool Call Info model (mirroring iOS ToolCallInfo)
class ToolCallInfo {
  final String toolName;
  final String arguments; // JSON string for display
  final String? result; // JSON string for display
  final bool success;
  final String? error;

  const ToolCallInfo({
    required this.toolName,
    required this.arguments,
    this.result,
    required this.success,
    this.error,
  });
}

/// Tool Call Indicator (mirroring iOS ToolCallIndicator)
///
/// A tappable badge that shows tool call status and opens detail sheet.
class ToolCallIndicator extends StatelessWidget {
  final ToolCallInfo toolCallInfo;
  final VoidCallback onTap;

  const ToolCallIndicator({
    super.key,
    required this.toolCallInfo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSuccess = toolCallInfo.success;
    final accentColor =
        isSuccess ? AppColors.primaryAccent : AppColors.primaryOrange;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: accentColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: accentColor.withOpacity(0.3),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSuccess ? Icons.build_outlined : Icons.warning_amber,
              size: 12,
              color: accentColor,
            ),
            const SizedBox(width: 6),
            Text(
              toolCallInfo.toolName,
              style: AppTypography.caption2(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tool Call Detail Sheet (mirroring iOS ToolCallDetailSheet)
///
/// Shows full details of a tool call.
class ToolCallDetailSheet extends StatelessWidget {
  final ToolCallInfo toolCallInfo;

  const ToolCallDetailSheet({
    super.key,
    required this.toolCallInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundPrimary(context),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: AppColors.separator(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(AppSpacing.large),
            child: Row(
              children: [
                Text(
                  'Tool Call',
                  style: AppTypography.headline(context),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.large),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status section
                  _buildStatusSection(context),

                  const SizedBox(height: AppSpacing.xLarge),

                  // Tool name
                  _buildDetailSection(
                    context,
                    title: 'Tool',
                    content: toolCallInfo.toolName,
                  ),

                  const SizedBox(height: AppSpacing.xLarge),

                  // Arguments
                  _buildCodeSection(
                    context,
                    title: 'Arguments',
                    code: toolCallInfo.arguments,
                  ),

                  // Result (if present)
                  if (toolCallInfo.result != null) ...[
                    const SizedBox(height: AppSpacing.xLarge),
                    _buildCodeSection(
                      context,
                      title: 'Result',
                      code: toolCallInfo.result!,
                    ),
                  ],

                  // Error (if present)
                  if (toolCallInfo.error != null) ...[
                    const SizedBox(height: AppSpacing.xLarge),
                    _buildDetailSection(
                      context,
                      title: 'Error',
                      content: toolCallInfo.error!,
                      isError: true,
                    ),
                  ],

                  const SizedBox(height: AppSpacing.xxLarge),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSection(BuildContext context) {
    final isSuccess = toolCallInfo.success;
    final statusColor =
        isSuccess ? AppColors.statusGreen : AppColors.primaryRed;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isSuccess ? Icons.check_circle : Icons.cancel,
            size: 24,
            color: statusColor,
          ),
          const SizedBox(width: 10),
          Text(
            isSuccess ? 'Success' : 'Failed',
            style: AppTypography.headline(context),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSection(
    BuildContext context, {
    required String title,
    required String content,
    bool isError = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.caption(context).copyWith(
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: AppTypography.body(context).copyWith(
            color: isError ? AppColors.primaryRed : null,
          ),
        ),
      ],
    );
  }

  Widget _buildCodeSection(
    BuildContext context, {
    required String title,
    required String code,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.caption(context).copyWith(
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            code,
            style: AppTypography.monospaced,
          ),
        ),
      ],
    );
  }
}

/// Tool Calling Active Indicator (mirroring iOS ToolCallingActiveIndicator)
///
/// Shows "Calling tool..." with animated gear icon.
class ToolCallingActiveIndicator extends StatefulWidget {
  const ToolCallingActiveIndicator({super.key});

  @override
  State<ToolCallingActiveIndicator> createState() =>
      _ToolCallingActiveIndicatorState();
}

class _ToolCallingActiveIndicatorState extends State<ToolCallingActiveIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RotationTransition(
            turns: _controller,
            child: const Icon(
              Icons.settings,
              size: 12,
              color: AppColors.primaryBlue,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Calling tool...',
            style: AppTypography.caption2(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tool Calling Badge (mirroring iOS toolCallingBadge)
///
/// Shows "Tools enabled" badge above chat input.
class ToolCallingBadge extends StatelessWidget {
  final int toolCount;

  const ToolCallingBadge({
    super.key,
    required this.toolCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.build_outlined,
            size: 10,
            color: AppColors.primaryBlue,
          ),
          const SizedBox(width: 6),
          Text(
            'Tools enabled ($toolCount)',
            style: AppTypography.caption2(context).copyWith(
              color: AppColors.primaryAccent,
            ),
          ),
        ],
      ),
    );
  }
}
