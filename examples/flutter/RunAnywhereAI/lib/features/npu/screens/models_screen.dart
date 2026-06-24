import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere/runanywhere_protos.dart' as ra;

import '../npu_catalog.dart';
import '../theme.dart';
import '../widgets.dart';

/// The curated NPU (QHexRT) catalog from `runanywhere/genie-npu-models`
/// (Hugging Face, npu-tagged). Lists only NPU Hexagon bundles — not the generic
/// SDK registry — and wires download + load through the core SDK.
class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  final Set<String> _downloaded = {};
  final Map<String, double> _progress = {};
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final models = await RunAnywhere.models.available();
      final have = models
          .where((m) => m.isDownloaded || m.localPath.isNotEmpty)
          .map((m) => m.id)
          .toSet();
      setState(() => _downloaded
        ..clear()
        ..addAll(have));
    } catch (_) {
      // Registry not reachable — list still renders as not-downloaded.
    }
  }

  void _download(NpuModel m) {
    setState(() {
      _progress[m.id] = 0;
      _error = null;
    });
    try {
      RunAnywhere.downloads.start(m.id).listen(
        (p) {
          setState(() => _progress[m.id] = p.overallProgress);
          if (p.state == ra.DownloadState.DOWNLOAD_STATE_COMPLETED) {
            setState(() {
              _progress.remove(m.id);
              _downloaded.add(m.id);
              _status = 'Downloaded ${m.name}';
            });
          } else if (p.state == ra.DownloadState.DOWNLOAD_STATE_FAILED) {
            setState(() {
              _progress.remove(m.id);
              _error = p.errorMessage.isEmpty ? 'Download failed' : p.errorMessage;
            });
          }
        },
        onError: (e) => setState(() {
          _progress.remove(m.id);
          _error = '$e';
        }),
      );
    } catch (e) {
      setState(() {
        _progress.remove(m.id);
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('NPU Models')),
      body: ResponsiveBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${npuModels.length} NPU bundles · runanywhere/genie-npu-models',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (_status != null) ...[
              const SizedBox(height: 8),
              Text(_status!, style: TextStyle(color: raSuccess)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
            const SizedBox(height: 12),
            for (final m in npuModels) ...[
              _ModelCard(
                model: m,
                downloaded: _downloaded.contains(m.id),
                progress: _progress[m.id],
                onDownload: () => _download(m),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.model,
    required this.downloaded,
    required this.onDownload,
    this.progress,
  });

  final NpuModel model;
  final bool downloaded;
  final double? progress;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SectionCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(model.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text('${model.detail} · ${formatBytes(model.sizeBytes)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 6),
                StatusPill(label: downloaded ? 'Downloaded' : 'NPU', color: downloaded ? raSuccess : cs.primary),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (progress != null)
            Text('${(progress!.clamp(0, 1) * 100).toInt()}%',
                style: metricTextStyle.copyWith(color: cs.primary))
          else if (downloaded)
            const FilledButton(onPressed: null, child: Text('Ready'))
          else
            FilledButton(onPressed: onDownload, child: const Text('Download')),
        ],
      ),
    );
  }
}
