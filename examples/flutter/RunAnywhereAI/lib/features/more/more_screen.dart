import 'package:flutter/material.dart' hide Icon;
import 'package:go_router/go_router.dart';
import 'package:tabler_icons_next/tabler_icons_next.dart' as tabler;
import 'package:runanywhere_ai/core/theme/app_spacing.dart';
import 'package:runanywhere_ai/core/theme/app_typography.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
      ),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          _SectionHeader(title: 'Voice & Audio', theme: theme),
          const SizedBox(height: AppSpacing.sm),
          _FeatureTile(
            icon: tabler.Microphone(color: theme.colorScheme.primary),
            title: 'Speech to Text',
            subtitle: 'Transcribe audio in batch or live mode',
            onTap: () => context.go('/home/more/stt'),
          ),
          _FeatureTile(
            icon: tabler.Volume(color: theme.colorScheme.tertiary),
            title: 'Text to Speech',
            subtitle: 'Generate speech from text with playback controls',
            onTap: () => context.go('/home/more/tts'),
          ),
          _FeatureTile(
            icon: tabler.Headphones(color: theme.colorScheme.secondary),
            title: 'Voice Assistant',
            subtitle: 'Full STT \u2192 LLM \u2192 TTS conversation pipeline',
            onTap: () => context.go('/home/more/voice'),
          ),
          const SizedBox(height: AppSpacing.xxl),
          _SectionHeader(title: 'Knowledge', theme: theme),
          const SizedBox(height: AppSpacing.sm),
          _FeatureTile(
            icon: tabler.FileText(color: theme.colorScheme.error),
            title: 'Document Q&A (RAG)',
            subtitle: 'Ask questions about PDF and JSON documents',
            onTap: () => context.go('/home/more/rag'),
          ),
          const SizedBox(height: AppSpacing.xxl),
          _SectionHeader(title: 'Models & Output', theme: theme),
          const SizedBox(height: AppSpacing.sm),
          _FeatureTile(
            icon: tabler.Box(color: theme.colorScheme.primary),
            title: 'Models',
            subtitle: 'Browse, download, and load AI models',
            onTap: () => context.go('/home/more/models'),
          ),
          _FeatureTile(
            icon: tabler.BracketsContain(color: theme.colorScheme.tertiary),
            title: 'Structured Output',
            subtitle: 'Generate JSON responses with schema templates',
            onTap: () => context.go('/home/chat/structured-output'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.theme});

  final String title;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTypography.labelLarge.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Widget icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: SizedBox(width: 28, height: 28, child: icon),
        title: Text(
          title,
          style: AppTypography.titleMedium.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: AppTypography.bodySmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: 20,
            height: 20,
            child: tabler.ChevronRight(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        onTap: onTap,
      ),
    );
  }
}
