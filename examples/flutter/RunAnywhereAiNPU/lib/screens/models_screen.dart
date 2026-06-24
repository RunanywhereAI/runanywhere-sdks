import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere/runanywhere_protos.dart' as ra;

import '../theme.dart';
import '../widgets.dart';

class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  List<ra.ModelInfo> _models = [];
  bool _loading = true;
  String? _error;
  String? _status;
  final Map<String, double> _progress = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final models = await RunAnywhere.models.available();
      setState(() => _models = models);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _download(ra.ModelInfo model) {
    setState(() => _progress[model.id] = 0);
    RunAnywhere.downloads.start(model.id).listen(
      (p) {
        setState(() => _progress[model.id] = p.overallProgress);
        if (p.state == ra.DownloadState.DOWNLOAD_STATE_COMPLETED) {
          setState(() {
            _progress.remove(model.id);
            _status = 'Downloaded ${model.name}';
          });
          _refresh();
        } else if (p.state == ra.DownloadState.DOWNLOAD_STATE_FAILED) {
          setState(() {
            _progress.remove(model.id);
            _error = p.errorMessage.isEmpty ? 'Download failed' : p.errorMessage;
          });
        }
      },
      onError: (e) => setState(() {
        _progress.remove(model.id);
        _error = '$e';
      }),
    );
  }

  Future<void> _load(ra.ModelInfo model) async {
    try {
      await RunAnywhere.models.loadModel(model);
      setState(() => _status = 'Loaded ${model.name}');
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Models')),
      body: ResponsiveBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_status != null) Text(_status!, style: TextStyle(color: raSuccess)),
            if (_error != null) Text(_error!, style: TextStyle(color: cs.error)),
            const SizedBox(height: 8),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (_models.isEmpty)
              SectionCard(
                child: Text(
                  'No models in the registry. Models are added via the SDK catalog '
                  'or register(); QHexRT bundles are arch-specific (v79/v81).',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              )
            else
              for (final model in _models) ...[
                _ModelCard(
                  model: model,
                  progress: _progress[model.id],
                  onDownload: () => _download(model),
                  onLoad: () => _load(model),
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
  const _ModelCard({required this.model, this.progress, required this.onDownload, required this.onLoad});

  final ra.ModelInfo model;
  final double? progress;
  final VoidCallback onDownload;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final downloaded = model.localPath.isNotEmpty || model.isDownloaded;
    final fw = model.framework.name.replaceFirst('INFERENCE_FRAMEWORK_', '').toLowerCase();
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(model.name.isEmpty ? model.id : model.name,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Row(children: [
                  _chip(context, fw, cs.primary),
                  const SizedBox(width: 4),
                  if (model.downloadSizeBytes.toInt() > 0)
                    _chip(context, _formatBytes(model.downloadSizeBytes.toInt()), cs.onSurfaceVariant),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (progress != null)
            Text('${(progress!.clamp(0, 1) * 100).toInt()}%',
                style: metricTextStyle.copyWith(color: cs.primary))
          else if (downloaded)
            FilledButton(onPressed: onLoad, child: const Text('Use'))
          else
            FilledButton(onPressed: onDownload, child: const Text('Download')),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '—';
    const units = ['B', 'KB', 'MB', 'GB'];
    var v = bytes.toDouble();
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return i == 0 ? '$bytes B' : '${v.toStringAsFixed(1)} ${units[i]}';
  }
}
