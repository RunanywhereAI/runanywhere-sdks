import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere/runanywhere_protos.dart' as ra;

import '../npu_catalog.dart';
import '../theme.dart';
import '../widgets.dart';

/// NPU (QHexRT) catalog — Google-Drive-hosted ZIP bundles. Download registers
/// each as a ZIP archive; the SDK downloads + extracts it into the standard
/// model dir, then loads it like any other model.
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
      // registry unreachable — rows render as not-downloaded.
    }
  }

  ra.ModelCategory _modality(NpuModel m) => m.modality == NpuModality.vlm
      ? ra.ModelCategory.MODEL_CATEGORY_MULTIMODAL
      : ra.ModelCategory.MODEL_CATEGORY_LANGUAGE;

  Future<void> _download(NpuModel m) async {
    if (m.driveId.isEmpty) {
      setState(() => _error = '${m.name}: download link not configured yet.');
      return;
    }
    setState(() {
      _progress[m.id] = 0;
      _error = null;
    });
    try {
      // NOTE: framework is GENIE until the Flutter protos are regenerated with
      // INFERENCE_FRAMEWORK_QHEXRT (24); both route to the on-device NPU path.
      final info = await RunAnywhere.models.registerArchiveModel(
        archiveUrl: driveZipUrl(m.driveId),
        structure: ra.ArchiveStructure.ARCHIVE_STRUCTURE_DIRECTORY_BASED,
        id: m.id,
        name: m.name,
        framework: ra.InferenceFramework.INFERENCE_FRAMEWORK_GENIE,
        modality: _modality(m),
        archiveType: ra.ArchiveType.ARCHIVE_TYPE_ZIP,
      );
      RunAnywhere.downloads.start(info.id).listen(
        (p) {
          setState(() => _progress[m.id] = p.overallProgress);
          if (p.state == ra.DownloadState.DOWNLOAD_STATE_COMPLETED) {
            setState(() {
              _progress.remove(m.id);
              _downloaded.add(m.id);
              _status = 'Downloaded ${m.name}';
            });
            unawaited(RunAnywhere.models.loadModel(info));
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
            Text('${npuModels.length} NPU bundles',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
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
    final pending = model.driveId.isEmpty;
    return SectionCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(model.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(model.detail,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 6),
                StatusPill(
                  label: downloaded
                      ? 'Downloaded'
                      : pending
                          ? 'Link pending'
                          : model.modality.name.toUpperCase(),
                  color: downloaded ? raSuccess : (pending ? cs.tertiary : cs.primary),
                ),
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
            FilledButton(onPressed: pending ? null : onDownload, child: const Text('Download')),
        ],
      ),
    );
  }
}
