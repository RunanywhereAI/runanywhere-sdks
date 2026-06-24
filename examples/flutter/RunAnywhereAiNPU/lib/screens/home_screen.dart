import 'package:flutter/material.dart';
import 'package:runanywhere_qhexrt/runanywhere_qhexrt.dart';

import '../theme.dart';
import '../widgets.dart';
import 'llm_screen.dart';
import 'models_screen.dart';
import 'stt_screen.dart';
import 'tts_screen.dart';
import 'vlm_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.npu, required this.registered});

  final NpuInfo npu;
  final bool registered;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final supported = npu.supported;
    return Scaffold(
      appBar: AppBar(title: const Text('RunAnywhere NPU')),
      body: ResponsiveBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('RunAnywhere', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
            Text(
              'On-device Qualcomm Hexagon NPU runtime',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Device',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        npu.socModel.isEmpty ? 'Unknown SoC' : npu.socModel,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      StatusPill(
                        label: supported ? 'NPU ${npu.arch}' : 'Unsupported',
                        color: supported ? raSuccess : cs.tertiary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  MetricRow('Hexagon arch', npu.arch),
                  MetricRow('SoC id', npu.socId >= 0 ? '${npu.socId}' : '—'),
                  MetricRow('QHexRT engine', registered ? 'ready' : 'unavailable'),
                ],
              ),
            ),
            if (!supported) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.tertiary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.tertiary.withValues(alpha: 0.5)),
                ),
                child: Text(
                  'QHexRT requires a Hexagon v79 or v81 NPU (Snapdragon 8 Elite or newer). '
                  'Detected ${npu.arch} — this device is not supported.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.tertiary),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SectionCard(
              title: 'Run',
              child: Column(
                children: [
                  _NavRow('Chat', 'LLM text generation', () => const LlmScreen()),
                  const SizedBox(height: 8),
                  _NavRow('Vision', 'Image + prompt (VLM)', () => const VlmScreen()),
                  const SizedBox(height: 8),
                  _NavRow('Speech to Text', 'Transcribe audio (Whisper)', () => const SttScreen()),
                  const SizedBox(height: 8),
                  _NavRow('Text to Speech', 'Synthesize audio (MeloTTS)', () => const TtsScreen()),
                  const SizedBox(height: 8),
                  _NavRow('Models', 'Download + manage models', () => const ModelsScreen()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow(this.title, this.subtitle, this.builder);

  final String title;
  final String subtitle;
  final Widget Function() builder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => builder())),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
