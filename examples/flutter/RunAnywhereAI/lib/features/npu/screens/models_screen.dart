import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere/runanywhere_protos.dart' as ra;
import 'package:runanywhere_qhexrt/runanywhere_qhexrt.dart';

import '../npu_catalog.dart';
import '../theme.dart';
import '../widgets.dart';

/// Models — the NPU (QHexRT) catalog of public HuggingFace multi-file bundles.
///
/// Rows are filtered to the Hexagon architecture probed on the device (a v81
/// phone only sees v81 bundles), then grouped by modality. Download registers a
/// multi-file model with the QHexRT framework and streams the bundle; Load
/// pulls it into memory for the matching modality screen.
class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

const List<NpuModality> _modalityOrder = [
  NpuModality.llm,
  NpuModality.vlm,
  NpuModality.stt,
  NpuModality.tts,
];

class _ModelsScreenState extends State<ModelsScreen> {
  final NpuInfo _npu = QHexRT.probeNpu();
  final Set<String> _downloaded = {};
  final Map<String, double> _progress = {};
  String? _busyId;
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
      if (!mounted) return;
      setState(() => _downloaded
        ..clear()
        ..addAll(have));
    } catch (_) {
      // registry unreachable — rows render as not-downloaded.
    }
  }

  List<ModelFileDescriptor> _descriptors(NpuModel m) {
    final modality = modalityCategory(m.modality);
    return m.files
        .map(
          (f) => ModelFileDescriptor(
            filename: f.filename,
            url: f.url,
            isRequired: true,
            role: RunAnywhere.models.inferModelFileRole(
              filename: f.filename,
              modality: modality,
            ),
          ),
        )
        .toList();
  }

  Future<void> _act(NpuModel m) async {
    setState(() {
      _busyId = m.id;
      _error = null;
      _status = null;
    });
    try {
      final info = await RunAnywhere.models.registerMultiFile(
        id: m.id,
        name: m.name,
        files: _descriptors(m),
        framework: ra.InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
        modality: modalityCategory(m.modality),
      );

      if (!_downloaded.contains(m.id)) {
        await _downloadBundle(m, info);
      }

      await RunAnywhere.models.loadModel(info);
      if (!mounted) return;
      setState(() => _status = 'Loaded ${m.name}');
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// Streams a multi-file bundle to completion. Resolves on COMPLETED, throws
  /// on FAILED so [_act] surfaces the error and skips loadModel.
  Future<void> _downloadBundle(NpuModel m, ModelInfo info) async {
    final completer = Completer<void>();
    setState(() => _progress[m.id] = 0);
    final sub = RunAnywhere.downloads.start(info.id).listen(
      (p) {
        if (!mounted) return;
        setState(() => _progress[m.id] = p.overallProgress);
        if (p.state == ra.DownloadState.DOWNLOAD_STATE_COMPLETED) {
          setState(() {
            _progress.remove(m.id);
            _downloaded.add(m.id);
          });
          if (!completer.isCompleted) completer.complete();
        } else if (p.state == ra.DownloadState.DOWNLOAD_STATE_FAILED) {
          setState(() => _progress.remove(m.id));
          if (!completer.isCompleted) {
            completer.completeError(
              p.errorMessage.isEmpty ? 'Download failed' : p.errorMessage,
            );
          }
        }
      },
      onError: (Object e) {
        if (mounted) setState(() => _progress.remove(m.id));
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
    );
    try {
      await completer.future;
    } finally {
      await sub.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final archKnown = _npu.arch != 'unknown';
    final visible =
        archKnown ? npuModels.where((m) => m.arch == _npu.arch).toList() : npuModels;

    return Scaffold(
      appBar: AppBar(title: const Text('NPU Models')),
      body: ResponsiveBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${visible.length} bundles${archKnown ? ' for Hexagon ${_npu.arch}' : ' (all architectures)'}',
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
            for (final modality in _modalityOrder) ...[
              if (visible.any((m) => m.modality == modality)) ...[
                SectionCard(
                  title: modalityLabel(modality),
                  child: Column(
                    children: [
                      for (final m in visible.where((m) => m.modality == modality)) ...[
                        _ModelRow(
                          model: m,
                          downloaded: _downloaded.contains(m.id),
                          progress: _progress[m.id],
                          busy: _busyId == m.id,
                          onAct: () => _act(m),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.model,
    required this.downloaded,
    required this.busy,
    required this.onAct,
    this.progress,
  });

  final NpuModel model;
  final bool downloaded;
  final bool busy;
  final double? progress;
  final VoidCallback onAct;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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
                  label: downloaded ? 'Downloaded' : model.modality.name.toUpperCase(),
                  color: downloaded ? raSuccess : cs.primary,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: progress != null
                ? Text('${(progress!.clamp(0, 1) * 100).toInt()}%',
                    textAlign: TextAlign.center,
                    style: metricTextStyle.copyWith(color: cs.primary))
                : FilledButton(
                    onPressed: busy ? null : onAct,
                    child: Text(busy ? '…' : (downloaded ? 'Load' : 'Download')),
                  ),
          ),
        ],
      ),
    );
  }
}
