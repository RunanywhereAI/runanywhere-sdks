import 'package:flutter/material.dart';

/// App Typography (mirroring iOS Typography.swift)
class AppTypography {
  // MARK: - Large titles and displays
  static TextStyle largeTitle(BuildContext context) =>
      Theme.of(context).textTheme.displayLarge ?? const TextStyle(fontSize: 34);
  static TextStyle title(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge ?? const TextStyle(fontSize: 28);
  static TextStyle title2(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium ?? const TextStyle(fontSize: 22);
  static TextStyle title3(BuildContext context) =>
      Theme.of(context).textTheme.titleSmall ?? const TextStyle(fontSize: 20);

  // MARK: - Headers
  static TextStyle headline(BuildContext context) =>
      Theme.of(context).textTheme.headlineSmall ??
      const TextStyle(fontSize: 17, fontWeight: FontWeight.w600);
  static TextStyle subheadline(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 15);

  // MARK: - Body text
  static TextStyle body(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge ?? const TextStyle(fontSize: 17);
  static TextStyle callout(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 16);
  static TextStyle footnote(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 13);

  // MARK: - Small text
  static TextStyle caption(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall ?? const TextStyle(fontSize: 12);
  static TextStyle caption2(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall ?? const TextStyle(fontSize: 11);

  // MARK: - Custom sizes (static, no context needed)
  static const TextStyle system9 = TextStyle(fontSize: 9);
  static const TextStyle system10 = TextStyle(fontSize: 10);
  static const TextStyle system11 = TextStyle(fontSize: 11);
  static const TextStyle system12 = TextStyle(fontSize: 12);
  static const TextStyle system14 = TextStyle(fontSize: 14);
  static const TextStyle system18 = TextStyle(fontSize: 18);
  static const TextStyle system28 = TextStyle(fontSize: 28);
  static const TextStyle system48 = TextStyle(fontSize: 48);
  static const TextStyle system60 = TextStyle(fontSize: 60);
  static const TextStyle system80 = TextStyle(fontSize: 80);

  // MARK: - With weights
  static TextStyle headlineSemibold(BuildContext context) =>
      headline(context).copyWith(fontWeight: FontWeight.w600);
  static TextStyle subheadlineMedium(BuildContext context) =>
      subheadline(context).copyWith(fontWeight: FontWeight.w500);
  static TextStyle subheadlineSemibold(BuildContext context) =>
      subheadline(context).copyWith(fontWeight: FontWeight.w600);
  static TextStyle captionMedium(BuildContext context) =>
      caption(context).copyWith(fontWeight: FontWeight.w500);
  static TextStyle caption2Medium(BuildContext context) =>
      caption2(context).copyWith(fontWeight: FontWeight.w500);
  static TextStyle caption2Bold(BuildContext context) =>
      caption2(context).copyWith(fontWeight: FontWeight.bold);
  static TextStyle titleBold(BuildContext context) =>
      title(context).copyWith(fontWeight: FontWeight.bold);
  static TextStyle title2Semibold(BuildContext context) =>
      title2(context).copyWith(fontWeight: FontWeight.w600);
  static TextStyle title3Medium(BuildContext context) =>
      title3(context).copyWith(fontWeight: FontWeight.w500);
  static TextStyle largeTitleBold(BuildContext context) =>
      largeTitle(context).copyWith(fontWeight: FontWeight.bold);

  // MARK: - Design variants
  static const TextStyle monospaced = TextStyle(
    fontFamily: 'monospace',
  );
  static const TextStyle monospacedCaption = TextStyle(
    fontSize: 9,
    fontWeight: FontWeight.bold,
    fontFamily: 'monospace',
  );
  static const TextStyle rounded10 = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
  );
  static const TextStyle rounded11 = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
  );
}
