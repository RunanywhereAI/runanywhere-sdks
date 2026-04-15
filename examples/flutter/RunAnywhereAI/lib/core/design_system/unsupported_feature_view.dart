import 'package:flutter/material.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';

class UnsupportedFeatureView extends StatelessWidget {
  final String title;
  final String message;

  const UnsupportedFeatureView({
    super.key,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, size: 40),
            const SizedBox(height: AppSpacing.mediumLarge),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.smallMedium),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
