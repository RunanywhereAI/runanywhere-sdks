import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/features/npu/npu_view.dart';
import 'package:runanywhere_ai/features/rag/rag_demo_view.dart';
import 'package:runanywhere_ai/features/settings/storage_view.dart';
import 'package:runanywhere_ai/features/solutions/solutions_view.dart';
import 'package:runanywhere_ai/features/voice/speech_to_text_view.dart';
import 'package:runanywhere_ai/features/voice/text_to_speech_view.dart';
import 'package:runanywhere_ai/features/voice/vad_view.dart';

/// More hub matching the iOS app's secondary feature navigation.
class MoreView extends StatelessWidget {
  const MoreView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.large),
        children: [
          _MoreRow(
            icon: Icons.memory,
            title: 'NPU (QHexRT)',
            subtitle: 'Qualcomm Hexagon NPU status & detection',
            onTap: () => _push(context, const NpuView()),
          ),
          _MoreRow(
            icon: Icons.graphic_eq,
            title: 'Transcribe',
            subtitle: 'Speech to text',
            onTap: () => _push(context, const SpeechToTextView()),
          ),
          _MoreRow(
            icon: Icons.volume_up,
            title: 'Speak',
            subtitle: 'Text to speech',
            onTap: () => _push(context, const TextToSpeechView()),
          ),
          _MoreRow(
            icon: Icons.article_outlined,
            title: 'Document Q&A',
            subtitle: 'Retrieval augmented chat',
            onTap: () => _push(context, const RagDemoView()),
          ),
          _MoreRow(
            icon: Icons.multitrack_audio,
            title: 'Voice Activity',
            subtitle: 'Live VAD stream',
            onTap: () => _push(context, const VADView()),
          ),
          _MoreRow(
            icon: Icons.storage,
            title: 'Storage',
            subtitle: 'Model storage and cache',
            onTap: () => _push(context, const StorageView()),
          ),
          _MoreRow(
            icon: Icons.layers_outlined,
            title: 'Solutions',
            subtitle: 'YAML pipeline runner',
            onTap: () => _push(context, const SolutionsView()),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget view) {
    unawaited(
      Navigator.of(
        context,
      ).push<void>(MaterialPageRoute<void>(builder: (_) => view)),
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.large,
          vertical: AppSpacing.smallMedium,
        ),
        leading: CircleAvatar(
          backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.12),
          foregroundColor: AppColors.primaryBlue,
          child: Icon(icon),
        ),
        title: Text(title, style: AppTypography.subheadlineSemibold(context)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
