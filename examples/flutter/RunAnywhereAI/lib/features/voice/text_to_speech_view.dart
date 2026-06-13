import 'dart:async';

import 'package:flutter/material.dart';

import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/features/models/model_selection_sheet.dart';
import 'package:runanywhere_ai/features/models/model_status_components.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';
import 'package:runanywhere_ai/features/voice/tts_view_model.dart';

/// TextToSpeechView (mirroring iOS TextToSpeechView.swift)
///
/// Dedicated TTS view with speech generation and playback controls.
/// Purely UI — all business logic lives in [TTSViewModel].
class TextToSpeechView extends StatefulWidget {
  const TextToSpeechView({super.key});

  @override
  State<TextToSpeechView> createState() => _TextToSpeechViewState();
}

class _TextToSpeechViewState extends State<TextToSpeechView> {
  final TTSViewModel _viewModel = TTSViewModel();

  final TextEditingController _textController = TextEditingController(
    text: 'Hello! This is a text to speech test.',
  );

  // Character limit
  static const int _maxCharacters = 5000;

  @override
  void initState() {
    super.initState();
    unawaited(_viewModel.initialize());
  }

  @override
  void dispose() {
    _textController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _showModelSelectionSheet() {
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => ModelSelectionSheet(
        context: ModelSelectionContext.tts,
        onModelSelected: (model) async {
          await _viewModel.loadModelFromSelection(model);
          // Surface TTS load failures via SnackBar in addition to the
          // inline error text.
          final error = _viewModel.errorMessage;
          if (error != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('TTS load failed: $error'),
                duration: const Duration(seconds: 6),
              ),
            );
          }
        },
      ),
    ));
  }

  String _formatTime(double seconds) {
    final mins = seconds.floor() ~/ 60;
    final secs = seconds.floor() % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  String _formatBytes(int bytes) {
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    } else {
      return '${(kb / 1024).toStringAsFixed(1)} MB';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final hasModelSelected = _viewModel.hasModelSelected;
        final characterCount = _textController.text.length;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Text to Speech'),
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  // Model Status Banner
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.large),
                    child: ModelStatusBanner(
                      framework: _viewModel.selectedFramework,
                      modelName: _viewModel.selectedModelName,
                      isLoading: _viewModel.isGenerating && !hasModelSelected,
                      onSelectModel: _showModelSelectionSheet,
                    ),
                  ),

                  const Divider(),

                  // Main content (only when model is selected)
                  if (hasModelSelected) ...[
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.large),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Text input section
                            _buildTextInputSection(characterCount),
                            const SizedBox(height: AppSpacing.xLarge),

                            // Voice settings section
                            _buildVoiceSettingsSection(),
                            const SizedBox(height: AppSpacing.xLarge),

                            // Audio metadata (when available)
                            if (_viewModel.metadata != null)
                              _buildAudioInfoSection(),

                            // Error message
                            if (_viewModel.errorMessage != null)
                              _buildErrorBanner(),
                          ],
                        ),
                      ),
                    ),

                    const Divider(),

                    // Controls section
                    _buildControlsSection(),
                  ] else
                    const Expanded(child: SizedBox()),
                ],
              ),

              // Model required overlay
              if (!hasModelSelected && !_viewModel.isGenerating)
                ModelRequiredOverlay(
                  modality: ModelSelectionContext.tts,
                  onSelectModel: _showModelSelectionSheet,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTextInputSection(int characterCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter Text',
          style: AppTypography.headlineSemibold(context),
        ),
        const SizedBox(height: AppSpacing.mediumLarge),
        Container(
          decoration: BoxDecoration(
            color: AppColors.backgroundGray6(context),
            borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusCard),
            border: Border.all(
              color: AppColors.borderMedium,
              width: 1,
            ),
          ),
          child: TextField(
            controller: _textController,
            maxLines: 6,
            maxLength: _maxCharacters,
            decoration: const InputDecoration(
              hintText: 'Type or paste text here...',
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(AppSpacing.large),
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: AppSpacing.xSmall),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '$characterCount characters',
            style: AppTypography.caption(context).copyWith(
              color: characterCount > _maxCharacters
                  ? AppColors.primaryRed
                  : AppColors.textSecondary(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceSettingsSection() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.backgroundGray6(context),
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Voice Settings',
            style: AppTypography.headlineSemibold(context),
          ),
          const SizedBox(height: AppSpacing.large),

          // Speech rate slider
          _buildSliderRow(
            label: 'Speed',
            value: _viewModel.speechRate,
            min: 0.5,
            max: 2.0,
            color: AppColors.primaryBlue,
            onChanged: (value) => _viewModel.speechRate = value,
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: AppTypography.subheadline(context),
            ),
            Text(
              '${value.toStringAsFixed(1)}x',
              style: AppTypography.subheadline(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: ((max - min) * 10).toInt(),
          activeColor: color,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildAudioInfoSection() {
    final metadata = _viewModel.metadata!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      margin: const EdgeInsets.only(bottom: AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.backgroundGray6(context),
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Audio Info',
            style: AppTypography.headlineSemibold(context),
          ),
          const SizedBox(height: AppSpacing.mediumLarge),
          _buildMetadataRow(
            icon: Icons.graphic_eq,
            label: 'Duration',
            value: '${(metadata.durationMs / 1000).toStringAsFixed(2)}s',
          ),
          const SizedBox(height: AppSpacing.smallMedium),
          _buildMetadataRow(
            icon: Icons.description,
            label: 'Size',
            value: _formatBytes(metadata.audioSize),
          ),
          const SizedBox(height: AppSpacing.smallMedium),
          _buildMetadataRow(
            icon: Icons.volume_up,
            label: 'Sample Rate',
            value: '${metadata.sampleRate} Hz',
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: AppColors.textSecondary(context),
        ),
        const SizedBox(width: AppSpacing.smallMedium),
        Text(
          '$label:',
          style: AppTypography.caption(context).copyWith(
            color: AppColors.textSecondary(context),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: AppTypography.captionMedium(context),
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.mediumLarge),
      margin: const EdgeInsets.only(bottom: AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.badgeRed,
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
      ),
      child: Row(
        children: [
          const Icon(Icons.error, color: AppColors.primaryRed),
          const SizedBox(width: AppSpacing.smallMedium),
          Expanded(
            child: Text(
              _viewModel.errorMessage!,
              style: AppTypography.subheadline(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsSection() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Column(
        children: [
          // Playback progress (when playing)
          if (_viewModel.isPlaying)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.large),
              child: Row(
                children: [
                  Text(
                    _formatTime(_viewModel.currentTime),
                    style: AppTypography.caption(context).copyWith(
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.smallMedium),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: _viewModel.playbackProgress,
                      backgroundColor: AppColors.backgroundGray5(context),
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.primaryPurple),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.smallMedium),
                  Text(
                    _formatTime(_viewModel.duration),
                    style: AppTypography.caption(context).copyWith(
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Generate/Speak button
              FilledButton.icon(
                onPressed: _textController.text.isNotEmpty &&
                        !_viewModel.isGenerating &&
                        _viewModel.hasModelSelected
                    ? () => unawaited(_viewModel.speak(_textController.text))
                    : null,
                icon: _viewModel.isGenerating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(_viewModel.isSystemTTS
                        ? Icons.volume_up
                        : Icons.graphic_eq),
                label: Text(_viewModel.isSystemTTS ? 'Speak' : 'Generate'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  minimumSize: const Size(140, 50),
                ),
              ),

              const SizedBox(width: AppSpacing.xLarge),

              // Stop button (when playing)
              if (_viewModel.isPlaying)
                FilledButton.icon(
                  onPressed: () => unawaited(_viewModel.stopSpeaking()),
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryRed,
                    minimumSize: const Size(140, 50),
                  ),
                ),
            ],
          ),

          const SizedBox(height: AppSpacing.mediumLarge),

          // Status text
          Text(
            _viewModel.isGenerating
                ? 'Generating speech...'
                : _viewModel.isPlaying
                    ? 'Playing...'
                    : 'Ready',
            style: AppTypography.caption(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}
