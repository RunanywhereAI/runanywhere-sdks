import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/features/chat/chat_view_model.dart';

/// Minimal LoRA adapter bottom sheet (mirrors iOS `ChatLoRASheets.swift`
/// at MVP level): catalog adapters with download/apply actions and applied
/// adapters with remove/clear actions. All SDK work lives in [ChatViewModel].
class ChatLoRASheet extends StatefulWidget {
  final ChatViewModel viewModel;

  const ChatLoRASheet({super.key, required this.viewModel});

  @override
  State<ChatLoRASheet> createState() => _ChatLoRASheetState();
}

class _ChatLoRASheetState extends State<ChatLoRASheet> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.viewModel.refreshAvailableAdapters());
    unawaited(widget.viewModel.refreshAppliedAdapters());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final viewModel = widget.viewModel;

        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Scaffold(
            appBar: AppBar(
              title: const Text('LoRA Adapters'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            body: ListView(
              controller: scrollController,
              padding: const EdgeInsets.only(bottom: AppSpacing.large),
              children: [
                if (viewModel.availableAdapters.isEmpty &&
                    viewModel.loraAdapters.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No LoRA adapters available for this model.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (viewModel.availableAdapters.isNotEmpty) ...[
                  _sectionHeader(context, 'Available for This Model'),
                  ...viewModel.availableAdapters.map(
                    (adapter) => _availableAdapterTile(context, adapter),
                  ),
                ],
                if (viewModel.loraAdapters.isNotEmpty) ...[
                  _sectionHeader(context, 'Loaded Adapters'),
                  ...viewModel.loraAdapters.map(
                    (adapter) => _loadedAdapterTile(context, adapter),
                  ),
                  TextButton.icon(
                    onPressed: () => unawaited(viewModel.clearAdapters()),
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text(
                      'Clear All Adapters',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionHeader(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.large,
          AppSpacing.large,
          AppSpacing.large,
          AppSpacing.smallMedium,
        ),
        child: Text(title, style: AppTypography.title3(context)),
      );

  Widget _availableAdapterTile(
    BuildContext context,
    sdk.LoraAdapterCatalogEntry adapter,
  ) {
    final viewModel = widget.viewModel;
    final isApplied = viewModel.isAdapterApplied(adapter);
    final isDownloaded = viewModel.isAdapterDownloaded(adapter);

    return ListTile(
      title: Text(adapter.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (adapter.description.isNotEmpty) adapter.description,
          if (adapter.sizeBytes > 0) _formatBytes(adapter.sizeBytes.toInt()),
        ].join(' • '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isApplied
          ? const Chip(
              label: Text('Applied'),
              avatar: Icon(Icons.check_circle, color: Colors.green, size: 18),
            )
          : FilledButton.tonal(
              onPressed: viewModel.isLoadingLoRA
                  ? null
                  : () => unawaited(viewModel.downloadAndApplyAdapter(adapter)),
              child: viewModel.isLoadingLoRA
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isDownloaded ? 'Apply' : 'Download'),
            ),
    );
  }

  Widget _loadedAdapterTile(
    BuildContext context,
    sdk.LoRAAdapterInfo adapter,
  ) {
    final fileName = adapter.adapterPath.split('/').last;

    return ListTile(
      title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('Scale: ${adapter.scale.toStringAsFixed(1)}'),
      trailing: IconButton(
        icon: const Icon(Icons.cancel_outlined),
        tooltip: 'Remove adapter',
        onPressed: () =>
            unawaited(widget.viewModel.removeAdapter(adapter.adapterPath)),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}
