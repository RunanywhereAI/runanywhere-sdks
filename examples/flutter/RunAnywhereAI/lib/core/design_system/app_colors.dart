import 'package:flutter/material.dart';

/// App Colors (mirroring iOS AppColors.swift)
class AppColors {
  // MARK: - Semantic Colors
  static Color get primaryAccent => Colors.blue;
  static const Color primaryBlue = Colors.blue;
  static const Color primaryGreen = Colors.green;
  static const Color primaryRed = Colors.red;
  static const Color primaryOrange = Colors.orange;
  static const Color primaryPurple = Colors.purple;

  // MARK: - Text Colors
  static Color textPrimary(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;
  static Color textSecondary(BuildContext context) =>
      (Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey)
          .withValues(alpha: 0.6);
  static const Color textWhite = Colors.white;

  // MARK: - Background Colors
  static Color backgroundPrimary(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;
  static Color backgroundSecondary(BuildContext context) =>
      Theme.of(context).cardColor;
  static Color backgroundTertiary(BuildContext context) =>
      Theme.of(context).colorScheme.surface;
  static Color backgroundGrouped(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerHighest;
  static Color backgroundGray5(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.grey.shade800
          : Colors.grey.shade200;
  static Color backgroundGray6(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.grey.shade900
          : Colors.grey.shade100;

  // MARK: - Separator
  static Color separator(BuildContext context) =>
      Theme.of(context).dividerColor;

  // MARK: - Badge/Tag colors
  static Color get badgeBlue => Colors.blue.withValues(alpha: 0.2);
  static Color get badgeGreen => Colors.green.withValues(alpha: 0.2);
  static Color get badgePurple => Colors.purple.withValues(alpha: 0.2);
  static Color get badgeOrange => Colors.orange.withValues(alpha: 0.2);
  static Color get badgeRed => Colors.red.withValues(alpha: 0.2);
  static Color get badgeGray => Colors.grey.withValues(alpha: 0.2);

  // MARK: - Model info colors
  static Color get modelFrameworkBg => Colors.blue.withValues(alpha: 0.1);
  static Color get modelThinkingBg => Colors.purple.withValues(alpha: 0.1);

  // MARK: - Chat bubble colors
  static Color get userBubbleGradientStart => Colors.blue;
  static Color get userBubbleGradientEnd => Colors.blue.withValues(alpha: 0.9);
  static Color assistantBubbleBg(BuildContext context) =>
      backgroundGray5(context);

  // MARK: - Status colors
  static const Color statusGreen = Colors.green;
  static const Color statusOrange = Colors.orange;
  static const Color statusRed = Colors.red;
  static const Color statusGray = Colors.grey;
  static const Color statusBlue = Colors.blue;
  static const Color statusPurple = Colors.purple;

  // MARK: - Shadow colors
  static Color get shadowDefault => Colors.black.withValues(alpha: 0.1);
  static Color get shadowLight => Colors.black.withValues(alpha: 0.1);
  static Color get shadowMedium => Colors.black.withValues(alpha: 0.12);
  static Color get shadowDark => Colors.black.withValues(alpha: 0.3);

  // MARK: - Overlay colors
  static Color get overlayLight => Colors.black.withValues(alpha: 0.3);
  static Color get overlayMedium => Colors.black.withValues(alpha: 0.4);

  // MARK: - Border colors
  static Color get borderLight => Colors.white.withValues(alpha: 0.3);
  static Color get borderMedium => Colors.black.withValues(alpha: 0.05);
}
