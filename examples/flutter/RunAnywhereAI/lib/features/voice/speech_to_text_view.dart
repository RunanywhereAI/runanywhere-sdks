import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/core/services/permission_service.dart';
import 'package:runanywhere_ai/features/models/model_selection_sheet.dart';
import 'package:runanywhere_ai/features/models/model_status_components.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';
import 'package:runanywhere_ai/features/voice/stt_view_model.dart';

/// SpeechToTextView (mirroring iOS SpeechToTextView.swift)
///
/// Dedicated STT view with batch/live/hybrid mode support and real-time
/// transcription. Purely UI — all business logic lives in [STTViewModel].
class SpeechToTextView extends StatefulWidget {
  const SpeechToTextView({super.key});

  @override
  State<SpeechToTextView> createState() => _SpeechToTextViewState();
}

class _SpeechToTextViewState extends State<SpeechToTextView> {
  final STTViewModel _viewModel = STTViewModel();

  // Cloud-config text fields are view-owned controllers seeded from the
  // ViewModel defaults; edits are pushed back via onChanged.
  late final TextEditingController _cloudProviderController;
  late final TextEditingController _cloudModelController;
  late final TextEditingController _cloudProviderIdController;
  late final TextEditingController _cloudApiKeyController;
  late final TextEditingController _cloudLanguageController;

  @override
  void initState() {
    super.initState();
    _cloudProviderController =
        TextEditingController(text: _viewModel.cloudProvider);
    _cloudModelController = TextEditingController(text: _viewModel.cloudModel);
    _cloudProviderIdController =
        TextEditingController(text: _viewModel.cloudProviderId);
    _cloudApiKeyController = TextEditingController(text: _viewModel.cloudApiKey);
    _cloudLanguageController =
        TextEditingController(text: _viewModel.cloudLanguageCode);
    unawaited(_viewModel.initialize());
  }

  @override
  void dispose() {
    _cloudProviderController.dispose();
    _cloudModelController.dispose();
    _cloudProviderIdController.dispose();
    _cloudApiKeyController.dispose();
    _cloudLanguageController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _showModelSelectionSheet() {
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => ModelSelectionSheet(
        context: ModelSelectionContext.stt,
        onModelSelected: (model) async {
          await _viewModel.loadModelFromSelection(model);
          // Surface load failures via SnackBar so the user sees them even if
          // the inline error text is below the fold or behind a sheet
          // animation.
          final error = _viewModel.errorMessage;
          if (error != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('STT load failed: $error'),
                duration: const Duration(seconds: 6),
              ),
            );
          }
        },
      ),
    ));
  }

  Future<void> _toggleRecording() async {
    if (!_viewModel.isRecording) {
      // Request STT permissions (microphone + speech recognition on iOS)
      // before starting — permission UI needs a BuildContext, so it stays in
      // the view.
      final hasPermission =
          await PermissionService.shared.requestSTTPermissions(context);
      if (!hasPermission) {
        _viewModel
            .reportError('Microphone permission required for recording');
        return;
      }
    }
    await _viewModel.toggleRecording();
  }

  void _copyToClipboard() {
    if (_viewModel.transcription.isEmpty) return;
    unawaited(
        Clipboard.setData(ClipboardData(text: _viewModel.transcription)));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final hasModelSelected = _viewModel.hasModelSelected;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Speech to Text'),
            actions: [
              if (_viewModel.transcription.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: _copyToClipboard,
                  tooltip: 'Copy',
                ),
              if (_viewModel.transcription.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _viewModel.clearTranscription,
                  tooltip: 'Clear',
                ),
            ],
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  // Model Status Banner
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.large),
                    child: ModelStatusBanner(
                      framework: _viewModel.selectedFramework,
                      modelName: _viewModel.selectedModelName,
                      isLoading: _viewModel.isProcessing && !hasModelSelected,
                      onSelectModel: _showModelSelectionSheet,
                    ),
                  ),

                  // Mode selector (only when model is selected)
                  if (hasModelSelected) ...[
                    _buildModeSelector(),
                    _buildModeDescription(),
                    if (_viewModel.selectedMode == STTMode.hybrid)
                      _buildHybridConfigurationSection(),
                  ],

                  const Divider(),

                  // Main content
                  if (hasModelSelected) ...[
                    Expanded(child: _buildTranscriptionArea()),
                    const Divider(),
                    _buildControlsArea(),
                  ] else
                    const Expanded(child: SizedBox()),
                ],
              ),

              // Model required overlay
              if (!hasModelSelected && !_viewModel.isProcessing)
                ModelRequiredOverlay(
                  modality: ModelSelectionContext.stt,
                  onSelectModel: _showModelSelectionSheet,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.large),
      child: SegmentedButton<STTMode>(
        segments: [
          for (final mode in STTMode.values)
            ButtonSegment(
              value: mode,
              label: Text(mode.displayName),
              icon: Icon(mode.icon),
            ),
        ],
        selected: {_viewModel.selectedMode},
        onSelectionChanged: _viewModel.isRecording
            ? null
            : (Set<STTMode> selection) {
                _viewModel.selectedMode = selection.first;
              },
      ),
    );
  }

  Widget _buildModeDescription() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _viewModel.selectedMode.icon,
            size: AppSpacing.iconSmall,
            color: AppColors.textSecondary(context),
          ),
          const SizedBox(width: AppSpacing.xSmall),
          Text(
            _viewModel.selectedMode.description,
            style: AppTypography.caption(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
          if (!_viewModel.supportsLiveMode &&
              _viewModel.selectedMode == STTMode.live) ...[
            const SizedBox(width: AppSpacing.smallMedium),
            Text(
              '(will use batch)',
              style: AppTypography.caption(context).copyWith(
                color: AppColors.statusOrange,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Cloud routing configuration form (mirrors the iOS
  /// `hybridConfigurationSection`).
  Widget _buildHybridConfigurationSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.large),
      padding: const EdgeInsets.all(AppSpacing.mediumLarge),
      decoration: BoxDecoration(
        color: AppColors.backgroundGray6(context),
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _cloudTextField(
                  controller: _cloudProviderController,
                  hint: 'provider',
                  onChanged: (v) => _viewModel.cloudProvider = v,
                ),
              ),
              const SizedBox(width: AppSpacing.smallMedium),
              Expanded(
                child: _cloudTextField(
                  controller: _cloudModelController,
                  hint: 'model',
                  onChanged: (v) => _viewModel.cloudModel = v,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.smallMedium),
          _cloudTextField(
            controller: _cloudProviderIdController,
            hint: 'cloud registry id',
            onChanged: (v) => _viewModel.cloudProviderId = v,
          ),
          const SizedBox(height: AppSpacing.smallMedium),
          _cloudTextField(
            controller: _cloudApiKeyController,
            hint: 'cloud API key',
            obscureText: true,
            onChanged: (v) => _viewModel.cloudApiKey = v,
          ),
          const SizedBox(height: AppSpacing.smallMedium),
          _cloudTextField(
            controller: _cloudLanguageController,
            hint: 'language',
            onChanged: (v) => _viewModel.cloudLanguageCode = v,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text('Prefer online', style: AppTypography.caption(context)),
            value: _viewModel.hybridPreferOnline,
            onChanged: (v) => _viewModel.hybridPreferOnline = v,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title:
                Text('Require network', style: AppTypography.caption(context)),
            value: _viewModel.hybridRequireNetwork,
            onChanged: (v) => _viewModel.hybridRequireNetwork = v,
          ),
          Text(
            'Fallback threshold '
            '${_viewModel.hybridConfidenceThreshold.toStringAsFixed(2)}',
            style: AppTypography.caption(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
          Slider(
            value: _viewModel.hybridConfidenceThreshold,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            onChanged: (v) => _viewModel.hybridConfidenceThreshold = v,
          ),
        ],
      ),
    );
  }

  Widget _cloudTextField({
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
    bool obscureText = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: AppTypography.caption(context),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smallMedium,
          vertical: AppSpacing.smallMedium,
        ),
      ),
      onChanged: onChanged,
    );
  }

  Widget _buildTranscriptionArea() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_viewModel.transcription.isEmpty &&
              _viewModel.partialText.isEmpty &&
              !_viewModel.isRecording &&
              !_viewModel.isTranscribing)
            _buildReadyState()
          else if (_viewModel.isTranscribing &&
              _viewModel.transcription.isEmpty)
            _buildProcessingState()
          else
            _buildTranscriptionContent(),
        ],
      ),
    );
  }

  Widget _buildReadyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: AppSpacing.xxxLarge),
          Icon(
            Icons.mic,
            size: 64,
            color: AppColors.statusGreen.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppSpacing.large),
          Text(
            'Ready to transcribe',
            style: AppTypography.headline(context),
          ),
          const SizedBox(height: AppSpacing.smallMedium),
          Text(
            'Tap the microphone button to start recording',
            style: AppTypography.subheadline(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: AppSpacing.xxxLarge),
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: AppSpacing.large),
          Text(
            'Processing audio...',
            style: AppTypography.headline(context),
          ),
          const SizedBox(height: AppSpacing.smallMedium),
          Text(
            'Transcribing your recording',
            style: AppTypography.subheadline(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptionContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with status badge
        Row(
          children: [
            Text(
              'Transcription',
              style: AppTypography.headline(context),
            ),
            const Spacer(),
            RecordingStatusBadge(
              isRecording: _viewModel.isRecording,
              isTranscribing: _viewModel.isTranscribing,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.mediumLarge),

        // Transcription text area
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.large),
          decoration: BoxDecoration(
            color: AppColors.backgroundGray6(context),
            borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_viewModel.transcription.isNotEmpty)
                Text(
                  _viewModel.transcription,
                  style: AppTypography.body(context),
                ),
              if (_viewModel.partialText.isNotEmpty)
                Text(
                  _viewModel.partialText,
                  style: AppTypography.body(context).copyWith(
                    color: AppColors.textSecondary(context),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              if (_viewModel.transcription.isEmpty &&
                  _viewModel.partialText.isEmpty)
                Text(
                  'Listening...',
                  style: AppTypography.body(context).copyWith(
                    color: AppColors.textSecondary(context),
                  ),
                ),
            ],
          ),
        ),

        // Hybrid routing badge (where the transcript came from)
        if (_viewModel.hybridRouting != null) ...[
          const SizedBox(height: AppSpacing.mediumLarge),
          _buildHybridRoutingSummary(_viewModel.hybridRouting!),
        ],
      ],
    );
  }

  /// Routing decision summary (mirrors the iOS `hybridRoutingSummary`).
  Widget _buildHybridRoutingSummary(sdk.HybridRoutedMetadata routing) {
    final caption = AppTypography.caption(context).copyWith(
      color: AppColors.textSecondary(context),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.mediumLarge),
      decoration: BoxDecoration(
        color: AppColors.backgroundGray5(context),
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Routing',
            style: AppTypography.captionMedium(context),
          ),
          const SizedBox(height: AppSpacing.xSmall),
          Text(
            'Chosen: '
            '${routing.chosenModelId.isEmpty ? "unknown" : routing.chosenModelId}',
            style: caption,
          ),
          Text(
            'Fallback: ${routing.wasFallback ? "yes" : "no"}',
            style: caption,
          ),
          if (routing.primaryErrorMessage.isNotEmpty)
            Text(
              'Primary: ${routing.primaryErrorMessage}',
              style: caption,
            ),
        ],
      ),
    );
  }

  Widget _buildControlsArea() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Column(
        children: [
          // Error message
          if (_viewModel.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.large),
              child: Text(
                _viewModel.errorMessage!,
                style: AppTypography.caption(context).copyWith(
                  color: AppColors.primaryRed,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          // Audio level indicator
          if (_viewModel.isRecording)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.large),
              child: AudioLevelIndicator(level: _viewModel.audioLevel),
            ),

          // Record button
          _buildRecordButton(),

          const SizedBox(height: AppSpacing.mediumLarge),

          // Status text
          Text(
            _viewModel.isTranscribing
                ? 'Processing transcription...'
                : _viewModel.isRecording
                    ? 'Tap to stop recording'
                    : 'Tap to start recording',
            style: AppTypography.caption(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordButton() {
    final Color buttonColor;
    if (_viewModel.isRecording) {
      buttonColor = AppColors.primaryRed;
    } else if (_viewModel.isTranscribing) {
      buttonColor = AppColors.primaryOrange;
    } else {
      buttonColor = AppColors.primaryBlue;
    }

    return GestureDetector(
      onTap: !_viewModel.isProcessing &&
              !_viewModel.isTranscribing &&
              _viewModel.hasModelSelected
          ? _toggleRecording
          : null,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _viewModel.hasModelSelected ? buttonColor : AppColors.statusGray,
          boxShadow: [
            BoxShadow(
              color: buttonColor.withValues(alpha: 0.3),
              blurRadius: AppSpacing.shadowXLarge,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: _viewModel.isProcessing || _viewModel.isTranscribing
            ? const Padding(
                padding: EdgeInsets.all(AppSpacing.xLarge),
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Icon(
                _viewModel.isRecording ? Icons.stop : Icons.mic,
                color: Colors.white,
                size: 32,
              ),
      ),
    );
  }
}
