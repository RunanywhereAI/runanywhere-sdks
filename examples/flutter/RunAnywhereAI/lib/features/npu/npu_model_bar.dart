import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere/runanywhere_protos.dart' as ra;
import 'package:runanywhere_qhexrt/runanywhere_qhexrt.dart';

import 'npu_catalog.dart';
import 'theme.dart';
import 'widgets.dart';

/// NpuModelBar — inline model picker shown at the top of each NPU modality
/// screen (Chat / Vision / STT / TTS).
///
/// Mirrors the Android `NpuModelBar` and the React Native port: a compact card
/// that shows the model currently resident in NPU memory for the screen's
/// modality and expands to a list of arch-matching bundles with
/// Download / Load / In-memory states and live download progress. This replaces
/// the standalone Models tab — each modality screen now self-serves its own
/// download + load.
class NpuModelBar extends StatefulWidget {
  const NpuModelBar({super.key, required this.modality, this.onLoadedChange});

  final NpuModality modality;

  /// Notifies the host screen when a model becomes resident (enables inference).
  final ValueChanged<String?>? onLoadedChange;

  @override
  State<NpuModelBar> createState() => _NpuModelBarState();
}

class _NpuModelBarState extends State<NpuModelBar> {
  NpuInfo _npu = NpuInfo.unknown;
  final Set<String> _downloaded = {};
  String? _loadedId;
  String? _busyId;
  double _progress = 0;
  String? _error;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    try {
      _npu = QHexRT.probeNpu();
    } catch (_) {
      _npu = NpuInfo.unknown;
    }
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final models = await RunAnywhere.models.available();
      final have = models
          .where((m) => m.isDownloaded || m.localPath.isNotEmpty)
          .map((m) => m.id)
          .toSet();
      if (mounted) {
        setState(() => _downloaded
          ..clear()
          ..addAll(have));
      }
    } catch (_) {
      // registry unreachable — rows render as not-downloaded.
    }
    try {
      // Reflect a model already resident in NPU memory for this modality (e.g.
      // loaded on a previous visit) so the host screen enables inference
      // without a redundant Load tap. Mirrors the Android reload() probe.
      final current =
          await RunAnywhere.modelInfoForCategory(modalityCategory(widget.modality));
      final id = current?.id;
      if (mounted) setState(() => _loadedId = id);
      widget.onLoadedChange?.call(id);
    } catch (_) {
      // lifecycle unreachable — leave loaded state as-is.
    }
  }

  /// The catalog authors the QHexRT manifest (`.json`) as the first file; pin it
  /// as PRIMARY so commons loads it as the entry point. The filename heuristic
  /// would otherwise tag every unmatched `.bin` weight as PRIMARY too, leaving
  /// commons to pick the wrong manifest. Mirrors the RN/Android registration.
  List<ModelFileDescriptor> _descriptors(NpuModel m) {
    return m.files.asMap().entries.map((e) {
      return ModelFileDescriptor(
        filename: e.value.filename,
        url: e.value.url,
        isRequired: true,
        role: e.key == 0
            ? ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL
            : ModelFileRole.MODEL_FILE_ROLE_COMPANION,
      );
    }).toList();
  }

  Future<void> _act(NpuModel m) async {
    setState(() {
      _busyId = m.id;
      _error = null;
      _progress = 0;
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
        await _refresh();
      }

      await RunAnywhere.models.loadModel(info);
      if (!mounted) return;
      setState(() {
        _loadedId = m.id;
        _expanded = false;
      });
      widget.onLoadedChange?.call(m.id);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() {
          _busyId = null;
          _progress = 0;
        });
      }
    }
  }

  /// Streams a multi-file bundle to completion. Resolves on COMPLETED, throws on
  /// FAILED so [_act] surfaces the error and skips loadModel.
  Future<void> _downloadBundle(NpuModel m, ModelInfo info) async {
    final completer = Completer<void>();
    final sub = RunAnywhere.downloads.start(info.id).listen(
      (p) {
        if (!mounted) return;
        final pct = p.overallProgress > 0 ? p.overallProgress : p.stageProgress;
        setState(() => _progress = pct);
        if (p.state == ra.DownloadState.DOWNLOAD_STATE_COMPLETED) {
          setState(() => _downloaded.add(m.id));
          if (!completer.isCompleted) completer.complete();
        } else if (p.state == ra.DownloadState.DOWNLOAD_STATE_FAILED) {
          if (!completer.isCompleted) {
            completer.completeError(
              p.errorMessage.isEmpty ? 'Download failed' : p.errorMessage,
            );
          }
        }
      },
      onError: (Object e) {
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
    final models = npuModels
        .where((m) =>
            m.modality == widget.modality && (!archKnown || m.arch == _npu.arch))
        .toList();
    NpuModel? loaded;
    for (final m in models) {
      if (m.id == _loadedId) {
        loaded = m;
        break;
      }
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loaded != null ? loaded.name : 'Select a model',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        loaded != null
                            ? loaded.detail
                            : 'Tap to download or load a ${modalityLabel(widget.modality)} model',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(
                  label: loaded != null ? 'Loaded' : 'Choose',
                  color: loaded != null ? raSuccess : cs.primary,
                ),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                    color: cs.onSurfaceVariant),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            if (!archKnown)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('NPU not detected — showing all architectures.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ),
            if (models.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                    'No ${modalityLabel(widget.modality)} model available for Hexagon ${_npu.arch} yet.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
              )
            else
              for (final m in models)
                _ModelRow(
                  model: m,
                  downloaded: _downloaded.contains(m.id),
                  loaded: _loadedId == m.id,
                  busy: _busyId == m.id,
                  progress: _busyId == m.id ? _progress : null,
                  anyBusy: _busyId != null,
                  onAct: () => _act(m),
                ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.error)),
            ],
          ],
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.model,
    required this.downloaded,
    required this.loaded,
    required this.busy,
    required this.anyBusy,
    required this.onAct,
    this.progress,
  });

  final NpuModel model;
  final bool downloaded;
  final bool loaded;
  final bool busy;
  final bool anyBusy;
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
                Text(model.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(model.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: loaded
                ? Text('In memory',
                    textAlign: TextAlign.center,
                    style: metricTextStyle.copyWith(color: raSuccess))
                : busy
                    ? Column(
                        children: [
                          const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                          if (!downloaded && progress != null) ...[
                            const SizedBox(height: 4),
                            Text('${(progress!.clamp(0, 1) * 100).toInt()}%',
                                style:
                                    metricTextStyle.copyWith(color: cs.primary)),
                          ],
                        ],
                      )
                    : FilledButton(
                        onPressed: anyBusy ? null : onAct,
                        child: Text(downloaded ? 'Load' : 'Download'),
                      ),
          ),
        ],
      ),
    );
  }
}
