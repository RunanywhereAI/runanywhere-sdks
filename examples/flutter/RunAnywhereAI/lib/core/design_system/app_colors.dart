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
          .withOpacity(0.6);
  static const Color textWhite = Colors.white;

  // MARK: - Background Colors
  static Color backgroundPrimary(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;
  static Color backgroundSecondary(BuildContext context) =>
      Theme.of(context).cardColor;
  static Color backgroundTertiary(BuildContext context) =>
      Theme.of(context).colorScheme.surface;
  static Color backgroundGrouped(BuildContext context) =>
      Theme.of(context).colorScheme.surface;
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
  static Color get badgeBlue => Colors.blue.withOpacity(0.2);
  static Color get badgeGreen => Colors.green.withOpacity(0.2);
  static Color get badgePurple => Colors.purple.withOpacity(0.2);
  static Color get badgeOrange => Colors.orange.withOpacity(0.2);
  static Color get badgeRed => Colors.red.withOpacity(0.2);
  static Color get badgeGray => Colors.grey.withOpacity(0.2);

  // MARK: - Model info colors
  static Color get modelFrameworkBg => Colors.blue.withOpacity(0.1);
  static Color get modelThinkingBg => Colors.purple.withOpacity(0.1);

  // MARK: - Chat bubble colors
  static Color get userBubbleGradientStart => Colors.blue;
  static Color get userBubbleGradientEnd => Colors.blue.withOpacity(0.9);
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
  static Color get shadowDefault => Colors.black.withOpacity(0.1);
  static Color get shadowLight => Colors.black.withOpacity(0.1);
  static Color get shadowMedium => Colors.black.withOpacity(0.12);
  static Color get shadowDark => Colors.black.withOpacity(0.3);

  // MARK: - Overlay colors
  static Color get overlayLight => Colors.black.withOpacity(0.3);
  static Color get overlayMedium => Colors.black.withOpacity(0.4);

  // MARK: - Border colors
  static Color get borderLight => Colors.white.withOpacity(0.3);
  static Color get borderMedium => Colors.black.withOpacity(0.05);
}
