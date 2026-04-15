import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runanywhere_ai/core/theme/app_colors.dart';
import 'package:runanywhere_ai/core/theme/app_spacing.dart';
import 'package:runanywhere_ai/core/theme/app_typography.dart';
import 'package:runanywhere_ai/features/voice/stt_controller.dart';

class SttScreen extends ConsumerWidget {
  const SttScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sttState = ref.watch(sttControllerProvider);
    final controller = ref.read(sttControllerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Speech to Text'),
        actions: [
          if (sttState.transcription.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy_rounded),
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: sttState.transcription),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              },
            ),
          if (sttState.transcription.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: controller.clearTranscription,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: SegmentedButton<SttMode>(
              segments: const [
                ButtonSegment(value: SttMode.batch, label: Text('Batch')),
                ButtonSegment(value: SttMode.live, label: Text('Live')),
              ],
              selected: {sttState.mode},
              onSelectionChanged: (s) => controller.setMode(s.first),
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              margin: AppSpacing.pagePadding,
              padding: AppSpacing.cardPadding,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: sttState.transcription.isEmpty
                  ? Center(
                      child: Text(
                        sttState.isTranscribing
                            ? 'Transcribing...'
                            : 'Tap the mic to start recording',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      child: SelectableText(
                        sttState.transcription,
                        style: AppTypography.bodyLarge.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
            ),
          ),
          if (sttState.errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                sttState.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.xxl,
              top: AppSpacing.lg,
            ),
            child: _RecordButton(
              isRecording: sttState.isRecording,
              isTranscribing: sttState.isTranscribing,
              isModelLoaded: sttState.isModelLoaded,
              onPressed: controller.toggleRecording,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.isRecording,
    required this.isTranscribing,
    required this.isModelLoaded,
    required this.onPressed,
  });

  final bool isRecording;
  final bool isTranscribing;
  final bool isModelLoaded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 72,
      height: 72,
      child: FilledButton(
        onPressed: isTranscribing || !isModelLoaded ? null : onPressed,
        style: FilledButton.styleFrom(
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
          backgroundColor:
              isRecording ? AppColors.error : theme.colorScheme.primary,
        ),
        child: isTranscribing
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.onPrimary,
                ),
              )
            : Icon(
                isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                size: AppSpacing.iconLg,
              ),
      ),
    );
  }
}
