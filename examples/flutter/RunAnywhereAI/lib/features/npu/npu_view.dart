import 'package:flutter/material.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/features/voice/speech_to_text_view.dart';
import 'package:runanywhere_ai/features/voice/text_to_speech_view.dart';
import 'package:runanywhere_qhexrt/runanywhere_qhexrt.dart';

/// NPU (QHexRT) — Qualcomm Hexagon NPU detection + status.
///
/// Runs the pre-flight capability probe (no QNN load) and reports whether the
/// device is supported (Hexagon v79/v81). Once a QHexRT model is loaded, the
/// app's existing Chat/Vision/Transcribe/Speak flows route through the NPU.
class NpuView extends StatefulWidget {
  const NpuView({super.key});

  @override
  State<NpuView> createState() => _NpuViewState();
}

class _NpuViewState extends State<NpuView> {
  late final NpuInfo _npu = QHexRT.probeNpu();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final supported = _npu.supported;
    final toneColor = supported ? Colors.green.shade600 : cs.error;

    return Scaffold(
      appBar: AppBar(title: const Text('NPU (QHexRT)')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.large),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.large),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Pill(
                        label: supported ? 'NPU supported' : 'Unsupported',
                        color: toneColor,
                      ),
                      const SizedBox(height: AppSpacing.medium),
                      _MetricRow('SoC model', _npu.socModel.isEmpty ? 'Unknown SoC' : _npu.socModel),
                      _MetricRow('Hexagon arch', _npu.arch),
                      _MetricRow('SoC id', _npu.socId >= 0 ? '${_npu.socId}' : '—'),
                      if (!supported) ...[
                        const SizedBox(height: AppSpacing.medium),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.medium),
                          decoration: BoxDecoration(
                            color: cs.errorContainer.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: cs.error),
                          ),
                          child: Text(
                            'QHexRT requires a Hexagon v79 or v81 NPU (Snapdragon 8 Elite / 8 Gen 3 '
                            'class). This device reports ${_npu.arch} — NPU inference may be '
                            'unavailable; the SDK falls back to other backends.',
                            style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.large),
              Text('Run on the NPU', style: AppTypography.subheadlineSemibold(context)),
              const SizedBox(height: AppSpacing.smallMedium),
              Text(
                'Load a QHexRT model, then use any modality below — it routes through the NPU backend.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.medium),
              _NavRow(
                icon: Icons.graphic_eq,
                title: 'Speech to Text',
                subtitle: 'Transcribe audio',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (_) => const SpeechToTextView()),
                ),
              ),
              _NavRow(
                icon: Icons.volume_up,
                title: 'Text to Speech',
                subtitle: 'Synthesize speech',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (_) => const TextToSpeechView()),
                ),
              ),
              const SizedBox(height: AppSpacing.medium),
              Text(
                'Chat (LLM) and Vision (VLM) live in the main tabs and also route through QHexRT '
                'once a QHexRT model is loaded.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
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
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: AppTypography.subheadlineSemibold(context)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
