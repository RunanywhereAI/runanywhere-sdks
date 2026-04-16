import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runanywhere_ai/core/theme/app_colors.dart';
import 'package:runanywhere_ai/core/theme/app_spacing.dart';
import 'package:runanywhere_ai/core/theme/app_typography.dart';
import 'package:runanywhere_ai/core/types/model_selection_context.dart';
import 'package:runanywhere_ai/core/widgets/model_selection_sheet.dart';
import 'package:runanywhere_ai/features/voice/voice_assistant_controller.dart';

class VoiceAssistantScreen extends ConsumerWidget {
  const VoiceAssistantScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vaState = ref.watch(voiceAssistantControllerProvider);
    final controller = ref.read(voiceAssistantControllerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Voice Assistant')),
      body: Column(
        children: [
          if (!vaState.allModelsReady)
            _ModelSetupBanner(
              state: vaState,
              theme: theme,
              onSelectSTT: () async {
                final model = await showModelSelectionSheet(
                  context,
                  ref,
                  selectionContext: ModelSelectionContext.stt,
                );
                if (model != null) controller.refreshModels();
              },
              onSelectLLM: () async {
                final model = await showModelSelectionSheet(
                  context,
                  ref,
                  selectionContext: ModelSelectionContext.llm,
                );
                if (model != null) controller.refreshModels();
              },
              onSelectTTS: () async {
                final model = await showModelSelectionSheet(
                  context,
                  ref,
                  selectionContext: ModelSelectionContext.tts,
                );
                if (model != null) controller.refreshModels();
              },
            ),
          if (vaState.errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              color: theme.colorScheme.errorContainer,
              child: Text(
                vaState.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          Expanded(
            child: vaState.conversation.isEmpty
                ? Center(
                    child: Text(
                      'Tap the mic to start a voice conversation',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: AppSpacing.pagePadding,
                    itemCount: vaState.conversation.length,
                    itemBuilder: (context, index) {
                      final turn = vaState.conversation[index];
                      final isUser =
                          turn.role == ConversationRole.user;
                      return _ConversationBubble(
                        text: turn.text,
                        isUser: isUser,
                        theme: theme,
                      );
                    },
                  ),
          ),
          _StatusIndicator(sessionState: vaState.sessionState, theme: theme),
          Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.xxl,
              top: AppSpacing.lg,
            ),
            child: _MicButton(
              sessionState: vaState.sessionState,
              allModelsReady: vaState.allModelsReady,
              onPressed: controller.toggleSession,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelSetupBanner extends StatelessWidget {
  const _ModelSetupBanner({
    required this.state,
    required this.theme,
    required this.onSelectSTT,
    required this.onSelectLLM,
    required this.onSelectTTS,
  });

  final VoiceAssistantState state;
  final ThemeData theme;
  final VoidCallback onSelectSTT;
  final VoidCallback onSelectLLM;
  final VoidCallback onSelectTTS;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tap to select required models:',
            style: AppTypography.labelLarge.copyWith(
              color: theme.colorScheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _modelRow('STT (Speech to Text)', state.sttReady, onSelectSTT),
          _modelRow('LLM (Language Model)', state.llmReady, onSelectLLM),
          _modelRow('TTS (Text to Speech)', state.ttsReady, onSelectTTS),
        ],
      ),
    );
  }

  Widget _modelRow(String name, bool ready, VoidCallback onTap) {
    return InkWell(
      onTap: ready ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Icon(
              ready ? Icons.check_circle : Icons.circle_outlined,
              size: 16,
              color: ready
                  ? AppColors.success
                  : theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                name,
                style: AppTypography.bodySmall.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ),
            if (!ready)
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.onTertiaryContainer,
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.sessionState, required this.theme});

  final VoiceSessionState sessionState;
  final ThemeData theme;

  String get _label => switch (sessionState) {
        VoiceSessionState.idle => '',
        VoiceSessionState.connecting => 'Connecting...',
        VoiceSessionState.listening => 'Listening...',
        VoiceSessionState.processing => 'Thinking...',
        VoiceSessionState.speaking => 'Speaking...',
        VoiceSessionState.error => 'Error',
      };

  @override
  Widget build(BuildContext context) {
    if (sessionState == VoiceSessionState.idle) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Text(
        _label,
        style: AppTypography.labelLarge.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.sessionState,
    required this.allModelsReady,
    required this.onPressed,
  });

  final VoiceSessionState sessionState;
  final bool allModelsReady;
  final VoidCallback onPressed;

  bool get _isActive => sessionState != VoiceSessionState.idle &&
      sessionState != VoiceSessionState.error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 80,
      height: 80,
      child: FilledButton(
        onPressed: allModelsReady ? onPressed : null,
        style: FilledButton.styleFrom(
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
          backgroundColor: _isActive
              ? AppColors.error
              : theme.colorScheme.primary,
        ),
        child: Icon(
          _isActive ? Icons.stop_rounded : Icons.mic_rounded,
          size: AppSpacing.iconXl,
        ),
      ),
    );
  }
}

class _ConversationBubble extends StatelessWidget {
  const _ConversationBubble({
    required this.text,
    required this.isUser,
    required this.theme,
  });

  final String text;
  final bool isUser;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.8,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: isUser
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          child: Text(
            text,
            style: AppTypography.bodyMedium.copyWith(
              color: isUser
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
