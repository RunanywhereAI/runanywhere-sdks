import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/features/models/model_selection_sheet.dart';
import 'package:runanywhere_ai/features/models/model_status_components.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';
import 'package:runanywhere_ai/features/voice/vad_view_model.dart';

/// Voice Activity Detection screen. Purely UI — all capture/VAD logic lives
/// in [VADViewModel].
class VADView extends StatefulWidget {
  const VADView({super.key});

  @override
  State<VADView> createState() => _VADViewState();
}

class _VADViewState extends State<VADView> {
  final VADViewModel _viewModel = VADViewModel();

  @override
  void initState() {
    super.initState();
    unawaited(_viewModel.initialize());
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  void _showModelSelectionSheet() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => ModelSelectionSheet(
          context: ModelSelectionContext.vad,
          onModelSelected: _viewModel.loadModelFromSelection,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Voice Activity')),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.large),
            children: [
              ModelStatusBanner(
                framework: _viewModel.selectedFramework,
                modelName: _viewModel.selectedModelName,
                isLoading: _viewModel.isProcessing,
                onSelectModel: _showModelSelectionSheet,
              ),
              if (_viewModel.errorMessage != null) ...[
                const SizedBox(height: AppSpacing.large),
                _ErrorBanner(message: _viewModel.errorMessage!),
              ],
              const SizedBox(height: AppSpacing.large),
              _StatusCard(
                isListening: _viewModel.isListening,
                isSpeech: _viewModel.isSpeech,
                confidence: _viewModel.confidence,
                energy: _viewModel.energy,
                audioLevel: _viewModel.audioLevel,
                frameCount: _viewModel.frameCount,
              ),
              const SizedBox(height: AppSpacing.large),
              SizedBox(
                height: AppSpacing.buttonHeightRegular,
                child: FilledButton.icon(
                  onPressed: _viewModel.isProcessing
                      ? null
                      : () => unawaited(_viewModel.toggleListening()),
                  icon: Icon(_viewModel.isListening ? Icons.stop : Icons.mic),
                  label: Text(_viewModel.isListening ? 'Stop' : 'Start'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.isListening,
    required this.isSpeech,
    required this.confidence,
    required this.energy,
    required this.audioLevel,
    required this.frameCount,
  });

  final bool isListening;
  final bool isSpeech;
  final double confidence;
  final double energy;
  final double audioLevel;
  final int frameCount;

  @override
  Widget build(BuildContext context) {
    final statusColor = isSpeech ? AppColors.statusGreen : AppColors.statusGray;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSpeech ? Icons.record_voice_over : Icons.hearing,
                  color: statusColor,
                ),
                const SizedBox(width: AppSpacing.smallMedium),
                Text(
                  isSpeech ? 'Speech detected' : 'Listening for speech',
                  style: AppTypography.headlineSemibold(
                    context,
                  ).copyWith(color: statusColor),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.large),
            _MetricRow(
              label: 'Mic Level',
              value: audioLevel,
              color: AppColors.primaryBlue,
            ),
            _MetricRow(
              label: 'Confidence',
              value: confidence,
              color: statusColor,
            ),
            _MetricRow(
              label: 'Energy',
              value: energy,
              color: AppColors.primaryPurple,
            ),
            const Divider(),
            Text(
              isListening ? 'Frames: $frameCount' : 'Not listening',
              style: AppTypography.caption(
                context,
              ).copyWith(color: AppColors.textSecondary(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mediumLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: AppTypography.subheadline(context)),
              Text(
                clamped.toStringAsFixed(2),
                style: AppTypography.caption(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xSmall),
          LinearProgressIndicator(
            value: clamped,
            color: color,
            backgroundColor: AppColors.backgroundGray5(context),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.mediumLarge),
      decoration: BoxDecoration(
        color: AppColors.badgeRed,
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.primaryRed),
          const SizedBox(width: AppSpacing.smallMedium),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
