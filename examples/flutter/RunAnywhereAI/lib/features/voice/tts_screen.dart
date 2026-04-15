import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runanywhere_ai/core/theme/app_spacing.dart';
import 'package:runanywhere_ai/core/theme/app_typography.dart';
import 'package:runanywhere_ai/features/voice/tts_controller.dart';

class TtsScreen extends ConsumerStatefulWidget {
  const TtsScreen({super.key});

  @override
  ConsumerState<TtsScreen> createState() => _TtsScreenState();
}

class _TtsScreenState extends ConsumerState<TtsScreen> {
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ttsState = ref.watch(ttsControllerProvider);
    final controller = ref.read(ttsControllerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Text to Speech')),
      body: Padding(
        padding: AppSpacing.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                maxLength: 5000,
                decoration: const InputDecoration(
                  hintText: 'Enter text to speak...',
                  alignLabelWithHint: true,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Text(
                  'Rate: ${ttsState.speechRate.toStringAsFixed(1)}x',
                  style: AppTypography.labelLarge,
                ),
                Expanded(
                  child: Slider(
                    value: ttsState.speechRate,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    onChanged: controller.setSpeechRate,
                  ),
                ),
              ],
            ),
            if (ttsState.hasAudio) ...[
              const SizedBox(height: AppSpacing.sm),
              _AudioInfo(
                durationMs: ttsState.durationMs,
                sampleRate: ttsState.sampleRate,
                theme: theme,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (ttsState.errorMessage != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                ttsState.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: ttsState.isSynthesizing || !ttsState.isModelLoaded
                        ? null
                        : () => controller.synthesize(_textController.text),
                    icon: ttsState.isSynthesizing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.record_voice_over_rounded),
                    label: Text(
                      ttsState.isSynthesizing ? 'Generating...' : 'Generate',
                    ),
                  ),
                ),
                if (ttsState.hasAudio) ...[
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filled(
                    onPressed: controller.togglePlayback,
                    icon: Icon(
                      ttsState.isPlaying
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(
              height: MediaQuery.paddingOf(context).bottom + AppSpacing.sm,
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioInfo extends StatelessWidget {
  const _AudioInfo({
    required this.durationMs,
    required this.sampleRate,
    required this.theme,
  });

  final int? durationMs;
  final int? sampleRate;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (durationMs != null) {
      final secs = durationMs! / 1000;
      parts.add('${secs.toStringAsFixed(1)}s');
    }
    if (sampleRate != null) {
      parts.add('${sampleRate! ~/ 1000}kHz');
    }

    return Text(
      parts.join(' \u2022 '),
      style: AppTypography.bodySmall.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
