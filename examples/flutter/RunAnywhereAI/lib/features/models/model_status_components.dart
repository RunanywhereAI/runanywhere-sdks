import 'dart:async';

import 'package:flutter/material.dart';

import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/core/models/app_types.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';

/// ModelStatusBanner (mirroring iOS ModelStatusBanner)
///
/// A banner that shows the current model status (framework + model name) or prompts to select a model.
class ModelStatusBanner extends StatelessWidget {
  final LLMFramework? framework;
  final String? modelName;
  final bool isLoading;
  final VoidCallback onSelectModel;

  const ModelStatusBanner({
    super.key,
    required this.framework,
    required this.modelName,
    required this.isLoading,
    required this.onSelectModel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.large,
        vertical: AppSpacing.mediumLarge,
      ),
      decoration: BoxDecoration(
        color: AppColors.backgroundGray6(context),
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusCard),
      ),
      child: isLoading
          ? _buildLoadingState(context)
          : (framework != null && modelName != null)
              ? _buildLoadedState(context)
              : _buildNoModelState(context),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: AppSpacing.iconRegular,
          height: AppSpacing.iconRegular,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(width: AppSpacing.smallMedium),
        Text(
          'Loading model...',
          style: AppTypography.subheadline(context).copyWith(
            color: AppColors.textSecondary(context),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadedState(BuildContext context) {
    return Row(
      children: [
        Icon(
          _frameworkIcon(framework!),
          color: _frameworkColor(framework!),
          size: AppSpacing.iconRegular,
        ),
        const SizedBox(width: AppSpacing.smallMedium),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                framework!.displayName,
                style: AppTypography.caption2(context).copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
              Text(
                modelName!,
                style: AppTypography.subheadlineSemibold(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        OutlinedButton(
          onPressed: onSelectModel,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.mediumLarge,
              vertical: AppSpacing.xSmall,
            ),
            minimumSize: Size.zero,
          ),
          child: Text(
            'Change',
            style: AppTypography.captionMedium(context),
          ),
        ),
      ],
    );
  }

  Widget _buildNoModelState(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.warning,
          color: AppColors.statusOrange,
          size: AppSpacing.iconRegular,
        ),
        const SizedBox(width: AppSpacing.smallMedium),
        Expanded(
          child: Text(
            'No model selected',
            style: AppTypography.subheadline(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: onSelectModel,
          icon: const Icon(Icons.view_in_ar, size: AppSpacing.iconSmall),
          label: const Text('Select Model'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.mediumLarge,
              vertical: AppSpacing.xSmall,
            ),
          ),
        ),
      ],
    );
  }

  IconData _frameworkIcon(LLMFramework framework) {
    switch (framework) {
      case LLMFramework.llamaCpp:
        return Icons.memory;
      case LLMFramework.whisperKit:
        return Icons.graphic_eq;
      case LLMFramework.onnxRuntime:
        return Icons.developer_board;
      case LLMFramework.foundationModels:
        return Icons.apple;
      case LLMFramework.systemTTS:
        return Icons.volume_up;
      default:
        return Icons.view_in_ar;
    }
  }

  Color _frameworkColor(LLMFramework framework) {
    switch (framework) {
      case LLMFramework.llamaCpp:
        return AppColors.primaryBlue;
      case LLMFramework.whisperKit:
        return AppColors.primaryGreen;
      case LLMFramework.onnxRuntime:
        return AppColors.primaryPurple;
      case LLMFramework.foundationModels:
        return Colors.black;
      case LLMFramework.systemTTS:
        return AppColors.primaryOrange;
      default:
        return AppColors.statusGray;
    }
  }
}

/// ModelRequiredOverlay (mirroring iOS ModelRequiredOverlay)
///
/// An overlay that covers the screen when no model is selected, prompting the user to select one.
class ModelRequiredOverlay extends StatelessWidget {
  final ModelSelectionContext modality;
  final VoidCallback onSelectModel;

  const ModelRequiredOverlay({
    super.key,
    required this.modality,
    required this.onSelectModel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.backgroundPrimary(context).withValues(alpha: 0.95),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _modalityIcon,
              size: 64,
              color: AppColors.textSecondary(context).withValues(alpha: 0.5),
            ),
            const SizedBox(height: AppSpacing.xLarge),
            Text(
              _modalityTitle,
              style: AppTypography.title2Semibold(context),
            ),
            const SizedBox(height: AppSpacing.smallMedium),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _modalityDescription,
                style: AppTypography.body(context).copyWith(
                  color: AppColors.textSecondary(context),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppSpacing.xLarge),
            FilledButton.icon(
              onPressed: onSelectModel,
              icon: const Icon(Icons.view_in_ar),
              label: const Text('Select a Model'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xLarge,
                  vertical: AppSpacing.mediumLarge,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData get _modalityIcon {
    switch (modality) {
      case ModelSelectionContext.llm:
        return Icons.chat_bubble_outline;
      case ModelSelectionContext.stt:
        return Icons.graphic_eq;
      case ModelSelectionContext.tts:
        return Icons.volume_up;
      case ModelSelectionContext.voice:
        return Icons.mic;
    }
  }

  String get _modalityTitle {
    switch (modality) {
      case ModelSelectionContext.llm:
        return 'Start a Conversation';
      case ModelSelectionContext.stt:
        return 'Speech to Text';
      case ModelSelectionContext.tts:
        return 'Text to Speech';
      case ModelSelectionContext.voice:
        return 'Voice Assistant';
    }
  }

  String get _modalityDescription {
    switch (modality) {
      case ModelSelectionContext.llm:
        return 'Select a language model to start chatting. Choose from LLaMA.cpp, Foundation Models, or other frameworks.';
      case ModelSelectionContext.stt:
        return 'Select a speech recognition model to transcribe audio. Choose from WhisperKit or ONNX Runtime.';
      case ModelSelectionContext.tts:
        return 'Select a text-to-speech model to generate audio. Choose from Piper TTS or System TTS.';
      case ModelSelectionContext.voice:
        return 'Voice assistant requires multiple models. Let\'s set them up together.';
    }
  }
}

/// AudioLevelIndicator (mirroring iOS audio level visualization)
///
/// A 10-bar audio level visualization.
class AudioLevelIndicator extends StatelessWidget {
  final double level; // 0.0 to 1.0

  const AudioLevelIndicator({
    super.key,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    final activeBars = (level * 10).floor();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(10, (index) {
        final isActive = index < activeBars;
        return Container(
          width: 25,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.statusGreen
                : AppColors.statusGray.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}

/// RecordingStatusBadge (mirroring iOS status badges)
///
/// A badge showing recording or transcribing status.
class RecordingStatusBadge extends StatelessWidget {
  final bool isRecording;
  final bool isTranscribing;

  const RecordingStatusBadge({
    super.key,
    required this.isRecording,
    required this.isTranscribing,
  });

  @override
  Widget build(BuildContext context) {
    if (!isRecording && !isTranscribing) {
      return const SizedBox.shrink();
    }

    final Color bgColor;
    final Color textColor;
    final String text;
    final Widget leading;

    if (isRecording) {
      bgColor = AppColors.primaryRed.withValues(alpha: 0.1);
      textColor = AppColors.primaryRed;
      text = 'RECORDING';
      leading = Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: AppColors.primaryRed,
          shape: BoxShape.circle,
        ),
      );
    } else {
      bgColor = AppColors.primaryOrange.withValues(alpha: 0.1);
      textColor = AppColors.primaryOrange;
      text = 'TRANSCRIBING';
      leading = SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: textColor,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.smallMedium,
        vertical: AppSpacing.xSmall,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 6),
          Text(
            text,
            style: AppTypography.caption2(context).copyWith(
              color: textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// TypingIndicatorView (mirroring iOS TypingIndicatorView)
///
/// Professional typing indicator with animated dots.
class TypingIndicatorView extends StatefulWidget {
  final String? statusText;

  const TypingIndicatorView({
    super.key,
    this.statusText,
  });

  @override
  State<TypingIndicatorView> createState() => _TypingIndicatorViewState();
}

class _TypingIndicatorViewState extends State<TypingIndicatorView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    unawaited(_controller.repeat());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        const SizedBox(width: AppSpacing.padding60),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.mediumLarge,
            vertical: AppSpacing.smallMedium,
          ),
          decoration: BoxDecoration(
            color: AppColors.backgroundGray5(context),
            borderRadius: BorderRadius.circular(AppSpacing.large),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowLight,
                blurRadius: 3,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: AppColors.borderMedium,
              width: 1,
            ),
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (index) {
                  final delay = index * 0.2;
                  final value = ((_controller.value + delay) % 1.0);
                  final scale = 0.8 + (0.5 * (1 - (value - 0.5).abs() * 2));

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ),
        const SizedBox(width: AppSpacing.mediumLarge),
        Text(
          widget.statusText ?? 'AI is thinking...',
          style: AppTypography.caption(context).copyWith(
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(width: AppSpacing.padding60),
      ],
    );
  }
}

/// CompactModelIndicator (mirroring iOS CompactModelIndicator)
///
/// A compact indicator showing current model status for use in navigation bars/headers.
class CompactModelIndicator extends StatelessWidget {
  final LLMFramework? framework;
  final String? modelName;
  final bool isLoading;
  final VoidCallback onTap;

  const CompactModelIndicator({
    super.key,
    required this.framework,
    required this.modelName,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.mediumLarge,
          vertical: AppSpacing.xSmall,
        ),
        decoration: BoxDecoration(
          color: framework != null
              ? AppColors.primaryBlue.withValues(alpha: 0.1)
              : AppColors.statusOrange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              SizedBox(
                width: AppSpacing.iconSmall,
                height: AppSpacing.iconSmall,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.textSecondary(context),
                ),
              )
            else if (framework != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _frameworkColor(framework!),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.xSmall),
              Text(
                modelName ?? framework!.displayName,
                style: AppTypography.caption(context).copyWith(
                  color: AppColors.primaryBlue,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ] else ...[
              const Icon(
                Icons.view_in_ar,
                size: AppSpacing.iconSmall,
                color: AppColors.statusOrange,
              ),
              const SizedBox(width: AppSpacing.xSmall),
              Text(
                'Select Model',
                style: AppTypography.caption(context).copyWith(
                  color: AppColors.statusOrange,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _frameworkColor(LLMFramework framework) {
    switch (framework) {
      case LLMFramework.llamaCpp:
        return AppColors.primaryBlue;
      case LLMFramework.whisperKit:
        return AppColors.statusGreen;
      case LLMFramework.onnxRuntime:
        return AppColors.primaryPurple;
      case LLMFramework.foundationModels:
        return Colors.black;
      default:
        return AppColors.statusGray;
    }
  }
}

/// VoicePipelineSetupView (mirroring iOS VoicePipelineSetupView)
///
/// A setup view specifically for Voice Assistant which requires 3 models.
class VoicePipelineSetupView extends StatelessWidget {
  final (LLMFramework, String)? sttModel;
  final (LLMFramework, String)? llmModel;
  final (LLMFramework, String)? ttsModel;

  final AppModelLoadState sttLoadState;
  final AppModelLoadState llmLoadState;
  final AppModelLoadState ttsLoadState;

  final VoidCallback onSelectSTT;
  final VoidCallback onSelectLLM;
  final VoidCallback onSelectTTS;
  final VoidCallback onStartVoice;

  const VoicePipelineSetupView({
    super.key,
    required this.sttModel,
    required this.llmModel,
    required this.ttsModel,
    required this.sttLoadState,
    required this.llmLoadState,
    required this.ttsLoadState,
    required this.onSelectSTT,
    required this.onSelectLLM,
    required this.onSelectTTS,
    required this.onStartVoice,
  });

  bool get allModelsReady =>
      sttModel != null && llmModel != null && ttsModel != null;

  bool get allModelsLoaded =>
      sttLoadState == AppModelLoadState.loaded &&
      llmLoadState == AppModelLoadState.loaded &&
      ttsLoadState == AppModelLoadState.loaded;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        const SizedBox(height: AppSpacing.xLarge),
        const Icon(
          Icons.mic,
          size: 48,
          color: AppColors.primaryBlue,
        ),
        const SizedBox(height: AppSpacing.smallMedium),
        Text(
          'Voice Assistant Setup',
          style: AppTypography.title2Semibold(context),
        ),
        const SizedBox(height: AppSpacing.xSmall),
        Text(
          'Voice requires 3 models to work together',
          style: AppTypography.subheadline(context).copyWith(
            color: AppColors.textSecondary(context),
          ),
        ),

        const SizedBox(height: AppSpacing.xLarge),

        // Model setup cards
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.large),
          child: Column(
            children: [
              ModelSetupCard(
                step: 1,
                title: 'Speech Recognition',
                subtitle: 'Converts your voice to text',
                icon: Icons.graphic_eq,
                color: AppColors.statusGreen,
                selectedFramework: sttModel?.$1,
                selectedModel: sttModel?.$2,
                loadState: sttLoadState,
                onSelect: onSelectSTT,
              ),
              const SizedBox(height: AppSpacing.large),
              ModelSetupCard(
                step: 2,
                title: 'Language Model',
                subtitle: 'Processes and responds to your input',
                icon: Icons.psychology,
                color: AppColors.primaryBlue,
                selectedFramework: llmModel?.$1,
                selectedModel: llmModel?.$2,
                loadState: llmLoadState,
                onSelect: onSelectLLM,
              ),
              const SizedBox(height: AppSpacing.large),
              ModelSetupCard(
                step: 3,
                title: 'Text to Speech',
                subtitle: 'Converts responses to audio',
                icon: Icons.volume_up,
                color: AppColors.primaryPurple,
                selectedFramework: ttsModel?.$1,
                selectedModel: ttsModel?.$2,
                loadState: ttsLoadState,
                onSelect: onSelectTTS,
              ),
            ],
          ),
        ),

        const Spacer(),

        // Start button
        Padding(
          padding: const EdgeInsets.all(AppSpacing.large),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: allModelsLoaded ? onStartVoice : null,
              icon: const Icon(Icons.mic),
              label: const Text('Start Voice Assistant'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.large),
              ),
            ),
          ),
        ),

        // Status message
        if (!allModelsReady)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.mediumLarge),
            child: Text(
              'Select all 3 models to continue',
              style: AppTypography.caption(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          )
        else if (!allModelsLoaded)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.mediumLarge),
            child: Text(
              'Waiting for models to load...',
              style: AppTypography.caption(context).copyWith(
                color: AppColors.statusOrange,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.mediumLarge),
            child: Text(
              'All models loaded and ready!',
              style: AppTypography.caption(context).copyWith(
                color: AppColors.statusGreen,
              ),
            ),
          ),
      ],
    );
  }
}

/// ModelSetupCard (for Voice Pipeline setup)
class ModelSetupCard extends StatelessWidget {
  final int step;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final LLMFramework? selectedFramework;
  final String? selectedModel;
  final AppModelLoadState loadState;
  final VoidCallback onSelect;

  const ModelSetupCard({
    super.key,
    required this.step,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.selectedFramework,
    required this.selectedModel,
    required this.loadState,
    required this.onSelect,
  });

  bool get isConfigured => selectedFramework != null && selectedModel != null;
  bool get isLoaded => loadState == AppModelLoadState.loaded;
  bool get isLoading => loadState == AppModelLoadState.loading;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusCard),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.large),
        decoration: BoxDecoration(
          color: AppColors.backgroundGray6(context),
          borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusCard),
          border: Border.all(
            color: _borderColor,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            // Step indicator
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _stepIndicatorColor,
                shape: BoxShape.circle,
              ),
              child: isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : isLoaded
                      ? const Icon(
                          Icons.check_circle,
                          size: 20,
                          color: Colors.white,
                        )
                      : isConfigured
                          ? const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.white,
                            )
                          : Text(
                              '$step',
                              style: AppTypography.subheadlineSemibold(context)
                                  .copyWith(color: AppColors.statusGray),
                            ),
            ),
            const SizedBox(width: AppSpacing.large),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: color, size: AppSpacing.iconRegular),
                      const SizedBox(width: AppSpacing.xSmall),
                      Text(
                        title,
                        style: AppTypography.subheadlineSemibold(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xSmall),
                  if (isConfigured)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${selectedFramework!.displayName} • $selectedModel',
                            style: AppTypography.caption(context).copyWith(
                              color: AppColors.textSecondary(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isLoaded)
                          const Icon(
                            Icons.check_circle,
                            size: 12,
                            color: AppColors.statusGreen,
                          )
                        else if (isLoading)
                          Text(
                            'Loading...',
                            style: AppTypography.caption2(context).copyWith(
                              color: AppColors.statusOrange,
                            ),
                          ),
                      ],
                    )
                  else
                    Text(
                      subtitle,
                      style: AppTypography.caption(context).copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                ],
              ),
            ),

            // Action / Status
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (isLoaded)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle,
                    size: 16,
                    color: AppColors.statusGreen,
                  ),
                  const SizedBox(width: AppSpacing.xSmall),
                  Text(
                    'Loaded',
                    style: AppTypography.caption(context).copyWith(
                      color: AppColors.statusGreen,
                    ),
                  ),
                ],
              )
            else if (isConfigured)
              Text(
                'Change',
                style: AppTypography.caption(context).copyWith(
                  color: AppColors.primaryBlue,
                ),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Select',
                    style: AppTypography.captionMedium(context).copyWith(
                      color: AppColors.primaryBlue,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: AppColors.primaryBlue,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Color get _stepIndicatorColor {
    if (isLoading) return AppColors.statusOrange;
    if (isLoaded) return AppColors.statusGreen;
    if (isConfigured) return color;
    return AppColors.statusGray.withValues(alpha: 0.2);
  }

  Color get _borderColor {
    if (isLoaded) return AppColors.statusGreen.withValues(alpha: 0.5);
    if (isLoading) return AppColors.statusOrange.withValues(alpha: 0.5);
    if (isConfigured) return color.withValues(alpha: 0.5);
    return Colors.transparent;
  }
}
