import 'dart:io';

import 'package:flutter/material.dart';

import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';

/// AdaptiveLayout (mirroring iOS AdaptiveLayout.swift)
///
/// Cross-platform layout helpers for adapting UI across different platforms.

/// Provides platform-aware adaptive colors
class AdaptiveColors {
  static Color adaptiveBackground(BuildContext context) =>
      AppColors.backgroundPrimary(context);

  static Color adaptiveSecondaryBackground(BuildContext context) =>
      AppColors.backgroundSecondary(context);

  static Color adaptiveTertiaryBackground(BuildContext context) =>
      AppColors.backgroundTertiary(context);

  static Color adaptiveGroupedBackground(BuildContext context) =>
      AppColors.backgroundGrouped(context);

  static Color adaptiveSeparator(BuildContext context) =>
      AppColors.separator(context);

  static Color adaptiveLabel(BuildContext context) =>
      AppColors.textPrimary(context);

  static Color adaptiveSecondaryLabel(BuildContext context) =>
      AppColors.textSecondary(context);
}

/// Adaptive sheet/modal wrapper
class AdaptiveSheet extends StatelessWidget {
  final Widget child;

  const AdaptiveSheet({
    super.key,
    required this.child,
  });

  /// Show an adaptive sheet/modal
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget Function(BuildContext) builder,
    bool isDismissible = true,
    bool useRootNavigator = true,
  }) {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      // Desktop: Use dialog with specific sizing
      return showDialog<T>(
        context: context,
        barrierDismissible: isDismissible,
        useRootNavigator: useRootNavigator,
        builder: (context) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: AppLayout.sheetMinWidth,
              maxWidth: AppLayout.sheetMaxWidth,
              minHeight: AppLayout.sheetMinHeight,
              maxHeight: AppLayout.sheetMaxHeight,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusModal),
              child: builder(context),
            ),
          ),
        ),
      );
    } else {
      // Mobile: Use bottom sheet
      return showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        isDismissible: isDismissible,
        useRootNavigator: useRootNavigator,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.cornerRadiusModal),
          ),
        ),
        builder: builder,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

/// Adaptive navigation wrapper
class AdaptiveNavigation extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? leading;

  const AdaptiveNavigation({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS) {
      // macOS: Custom title bar
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.large),
            decoration: BoxDecoration(
              color: AdaptiveColors.adaptiveBackground(context),
              border: Border(
                bottom: BorderSide(
                  color: AdaptiveColors.adaptiveSeparator(context),
                ),
              ),
            ),
            child: Row(
              children: [
                if (leading != null) leading!,
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                if (actions != null) ...actions!,
              ],
            ),
          ),
          Expanded(child: child),
        ],
      );
    } else {
      // iOS/Android: Standard AppBar
      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: leading,
          actions: actions,
        ),
        body: child,
      );
    }
  }
}

/// Adaptive button style
class AdaptiveButtonStyle {
  static ButtonStyle primary(BuildContext context) {
    return ElevatedButton.styleFrom(
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Theme.of(context).colorScheme.onPrimary,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.large,
        vertical: AppSpacing.mediumLarge,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
      ),
    );
  }

  static ButtonStyle secondary(BuildContext context) {
    return OutlinedButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.primary,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.mediumLarge,
        vertical: AppSpacing.smallMedium,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
      ),
    );
  }
}

/// Adaptive text field
class AdaptiveTextField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final String? hintText;
  final bool isURL;
  final bool isSecure;
  final bool isNumeric;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;

  const AdaptiveTextField({
    super.key,
    required this.label,
    this.controller,
    this.hintText,
    this.isURL = false,
    this.isSecure = false,
    this.isNumeric = false,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: isSecure,
      maxLines: isSecure ? 1 : maxLines,
      keyboardType: isURL
          ? TextInputType.url
          : isNumeric
              ? TextInputType.number
              : TextInputType.text,
      autocorrect: !isURL,
      textCapitalization:
          isURL ? TextCapitalization.none : TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        border: const OutlineInputBorder(),
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted != null ? (_) => onSubmitted!() : null,
    );
  }
}

/// Adaptive frame for desktop sizing
class AdaptiveFrame extends StatelessWidget {
  final Widget child;

  const AdaptiveFrame({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppLayout.macOSMinWidth,
          maxWidth: AppLayout.macOSMaxWidth,
          minHeight: AppLayout.macOSMinHeight,
          maxHeight: AppLayout.macOSMaxHeight,
        ),
        child: child,
      );
    }
    return child;
  }
}

/// Platform detection utilities
class PlatformUtils {
  static bool get isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  static bool get isMobile => Platform.isIOS || Platform.isAndroid;

  static bool get isIOS => Platform.isIOS;

  static bool get isAndroid => Platform.isAndroid;

  static bool get isMacOS => Platform.isMacOS;

  static bool get isWindows => Platform.isWindows;

  static bool get isLinux => Platform.isLinux;
}
