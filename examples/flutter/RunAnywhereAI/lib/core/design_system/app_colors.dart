import 'package:flutter/material.dart';

/// App Colors (mirroring iOS AppColors.swift)
class AppColors {
  // Semantic Colors
  static Color get primaryAccent => Colors.blue;
  static const Color primaryBlue = Colors.blue;
  static const Color primaryGreen = Colors.green;
  static const Color primaryRed = Colors.red;
  static const Color primaryOrange = Colors.orange;
  static const Color primaryPurple = Colors.purple;

  // Text Colors
  static Color textPrimary(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;
  static Color textSecondary(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey;
  static const Color textWhite = Colors.white;

  // Background Colors
  static Color backgroundPrimary(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;
  static Color backgroundSecondary(BuildContext context) =>
      Theme.of(context).cardColor;
  static Color backgroundTertiary(BuildContext context) =>
      Theme.of(context).colorScheme.surface;
  static Color backgroundGrouped(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceVariant;

  // Badge/Tag colors
  static Color get badgeBlue => Colors.blue.withOpacity(0.2);
  static Color get badgeGreen => Colors.green.withOpacity(0.2);
  static Color get badgePurple => Colors.purple.withOpacity(0.2);
  static Color get badgeOrange => Colors.orange.withOpacity(0.2);
  static Color get badgeRed => Colors.red.withOpacity(0.2);
  static Color badgeGray(BuildContext context) =>
      textSecondary(context).withOpacity(0.2);

  // Status colors
  static const Color statusGreen = Colors.green;
  static const Color statusOrange = Colors.orange;
  static const Color statusRed = Colors.red;
  static const Color statusGray = Colors.grey;
  static const Color statusBlue = Colors.blue;

  // Quiz specific
  static const Color quizTrue = Colors.green;
  static const Color quizFalse = Colors.red;

  // Separator
  static Color separator(BuildContext context) =>
      Theme.of(context).dividerColor;
}

