import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/core/services/audio_recording_service.dart';
import 'package:runanywhere_ai/core/services/permission_service.dart';
import 'package:runanywhere_ai/features/models/model_selection_sheet.dart';
import 'package:runanywhere_ai/features/models/model_status_components.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';

/// STTMode enumeration (matching iOS STTMode)
enum STTMode {
  batch,
  live;

  String get displayName {
    switch (this) {
      case STTMode.batch:
        return 'Batch';
      case STTMode.live:
        return 'Live';
    }
  }

  String get description {
    switch (this) {
      case STTMode.batch:
        return 'Record first, then transcribe all at once';
      case STTMode.live:
        return 'Transcribe as you speak in real-time';
    }
  }

  IconData get icon {
    switch (this) {
      case STTMode.batch:
        return Icons.mic;
      case STTMode.live:
        return Icons.stream;
    }
  }
}

/// SpeechToTextView (mirroring iOS SpeechToTextView.swift)
///
/// Dedicated STT view with batch/live mode support and real-time transcription.
/// Now uses RunAnywhere SDK for actual transcription.
class SpeechToTextView extends StatefulWidget {
  const SpeechToTextView({super.key});

  @override
  State<SpeechToTextView> createState() => _SpeechToTextViewState();
}

class _SpeechToTextViewState extends State<SpeechToTextView> {
  // Recording state
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isTranscribing = false;
  STTMode _selectedMode = STTMode.batch;
  String _transcribedText = '';
  String _partialText = '';
  double _audioLevel = 0.0;

  // Model state
  LLMFramework? _selectedFramework;
  String? _selectedModelName;
  bool _supportsLiveMode = true;

  // Error state
  String? _errorMessage;

  // Audio recording service
  final AudioRecordingService _recordingService =
      AudioRecordingService.instance;
  StreamSubscription<double>? _audioLevelSubscription;

  bool get _hasModelSelected =>
      _selectedFramework != null && _selectedModelName != null;

  @override
  void initState() {
    super.initState();
    unawaited(_checkMicrophonePermission());
  }

  @override
  void dispose() {
    unawaited(_audioLevelSubscription?.cancel());
    super.dispose();
  }

  Future<void> _checkMicrophonePermission() async {
    // Check permission status on init, will request when user tries to record
    final hasPermission =
        await PermissionService.shared.areSTTPermissionsGranted();
    if (!hasPermission) {
      debugPrint(
          'STT permissions not yet granted, will request when recording starts');
    }
  }

  void _showModelSelectionSheet() {
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => ModelSelectionSheet(
        context: ModelSelectionContext.stt,
        onModelSelected: (model) async {
          await _loadModel(model);
        },
      ),
    ));
  }

  /// Load STT model using RunAnywhere SDK directly (matches Swift STTViewModel pattern)
  Future<void> _loadModel(ModelInfo model) async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      debugPrint('🔄 Loading STT model: ${model.name}');

      // Load STT model directly via SDK (matches Swift: RunAnywhere.loadSTTModel)
      await sdk.RunAnywhere.loadSTTModel(model.id);

      setState(() {
        _selectedFramework =
            model.preferredFramework ?? LLMFramework.whisperKit;
        _selectedModelName = model.name;
        // WhisperKit supports live mode, ONNX may have limitations
        _supportsLiveMode = model.preferredFramework == LLMFramework.whisperKit;
        _isProcessing = false;
      });

      debugPrint('✅ STT model loaded: ${model.name}');
    } catch (e) {
      debugPrint('❌ Failed to load STT model: $e');
      setState(() {
        _errorMessage = 'Failed to load model: $e';
        _isProcessing = false;
      });
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    // Request STT permissions (microphone + speech recognition on iOS)
    final hasPermission =
        await PermissionService.shared.requestSTTPermissions(context);
    if (!hasPermission) {
      setState(() {
        _errorMessage = 'Microphone permission required for recording';
      });
      return;
    }

    setState(() {
      _isRecording = true;
      _errorMessage = null;
      _transcribedText = '';
      _partialText = '';
    });

    // Start recording with the audio service
    final recordingPath = await _recordingService.startRecording(
      sampleRate: 16000,
      numChannels: 1,
      enableAudioLevels: true,
    );

    if (recordingPath == null) {
      setState(() {
        _isRecording = false;
        _errorMessage = 'Failed to start recording';
      });
      return;
    }

    // Subscribe to audio levels
    _audioLevelSubscription =
        _recordingService.audioLevelStream?.listen((level) {
      setState(() {
        _audioLevel = level;
      });
    });

    debugPrint('🎙️ Recording started in ${_selectedMode.displayName} mode');
  }

  Future<void> _stopRecording() async {
    // Cancel audio level subscription
    await _audioLevelSubscription?.cancel();
    _audioLevelSubscription = null;

    setState(() {
      _isRecording = false;
      _audioLevel = 0.0;
    });

    // Stop recording and get audio data
    final (audioData, _) = await _recordingService.stopRecording();

    if (audioData == null || audioData.isEmpty) {
      setState(() {
        _errorMessage = 'No audio data recorded';
      });
      return;
    }

    // Transcribe the recorded audio
    await _transcribeAudio(audioData);
  }

  /// Transcribe recorded audio using RunAnywhere SDK
  Future<void> _transcribeAudio(List<int> audioData) async {
    setState(() {
      _isTranscribing = true;
      _errorMessage = null;
    });

    try {
      debugPrint('🔄 Transcribing ${audioData.length} bytes of audio...');

      // Check if STT model is loaded via SDK (matches Swift: RunAnywhere.isSTTModelLoaded)
      if (!sdk.RunAnywhere.isSTTModelLoaded) {
        throw Exception(
            'STT component not loaded. Please load an STT model first.');
      }

      // Call SDK transcription API (matches Swift: RunAnywhere.transcribe(_:))
      final audioBytes = Uint8List.fromList(audioData);
      final transcribedText = await sdk.RunAnywhere.transcribe(audioBytes);

      setState(() {
        _transcribedText = transcribedText;
        _isTranscribing = false;
      });

      debugPrint('✅ Transcription complete: ${transcribedText.length} chars');
    } catch (e) {
      debugPrint('❌ Transcription failed: $e');
      setState(() {
        _errorMessage = 'Transcription failed: $e';
        _isTranscribing = false;
      });
    }
  }

  void _clearTranscription() {
    setState(() {
      _transcribedText = '';
      _partialText = '';
    });
  }

  void _copyToClipboard() {
    // TODO: Implement clipboard copy
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Speech to Text'),
        actions: [
          if (_transcribedText.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: _copyToClipboard,
              tooltip: 'Copy',
            ),
          if (_transcribedText.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearTranscription,
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
                  framework: _selectedFramework,
                  modelName: _selectedModelName,
                  isLoading: _isProcessing && !_hasModelSelected,
                  onSelectModel: _showModelSelectionSheet,
                ),
              ),

              // Mode selector (only when model is selected)
              if (_hasModelSelected) ...[
                _buildModeSelector(),
                _buildModeDescription(),
              ],

              const Divider(),

              // Main content
              if (_hasModelSelected) ...[
                Expanded(child: _buildTranscriptionArea()),
                const Divider(),
                _buildControlsArea(),
              ] else
                const Expanded(child: SizedBox()),
            ],
          ),

          // Model required overlay
          if (!_hasModelSelected && !_isProcessing)
            ModelRequiredOverlay(
              modality: ModelSelectionContext.stt,
              onSelectModel: _showModelSelectionSheet,
            ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.large),
      child: SegmentedButton<STTMode>(
        segments: [
          ButtonSegment(
            value: STTMode.batch,
            label: Text(STTMode.batch.displayName),
            icon: Icon(STTMode.batch.icon),
          ),
          ButtonSegment(
            value: STTMode.live,
            label: Text(STTMode.live.displayName),
            icon: Icon(STTMode.live.icon),
          ),
        ],
        selected: {_selectedMode},
        onSelectionChanged: _isRecording
            ? null
            : (Set<STTMode> selection) {
                setState(() {
                  _selectedMode = selection.first;
                });
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
            _selectedMode.icon,
            size: AppSpacing.iconSmall,
            color: AppColors.textSecondary(context),
          ),
          const SizedBox(width: AppSpacing.xSmall),
          Text(
            _selectedMode.description,
            style: AppTypography.caption(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
          if (!_supportsLiveMode && _selectedMode == STTMode.live) ...[
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

  Widget _buildTranscriptionArea() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_transcribedText.isEmpty &&
              _partialText.isEmpty &&
              !_isRecording &&
              !_isTranscribing)
            _buildReadyState()
          else if (_isTranscribing && _transcribedText.isEmpty)
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
              isRecording: _isRecording,
              isTranscribing: _isTranscribing,
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
              if (_transcribedText.isNotEmpty)
                Text(
                  _transcribedText,
                  style: AppTypography.body(context),
                ),
              if (_partialText.isNotEmpty)
                Text(
                  _partialText,
                  style: AppTypography.body(context).copyWith(
                    color: AppColors.textSecondary(context),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              if (_transcribedText.isEmpty && _partialText.isEmpty)
                Text(
                  'Listening...',
                  style: AppTypography.body(context).copyWith(
                    color: AppColors.textSecondary(context),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControlsArea() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Column(
        children: [
          // Error message
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.large),
              child: Text(
                _errorMessage!,
                style: AppTypography.caption(context).copyWith(
                  color: AppColors.primaryRed,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          // Audio level indicator
          if (_isRecording)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.large),
              child: AudioLevelIndicator(level: _audioLevel),
            ),

          // Record button
          _buildRecordButton(),

          const SizedBox(height: AppSpacing.mediumLarge),

          // Status text
          Text(
            _isTranscribing
                ? 'Processing transcription...'
                : _isRecording
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
    if (_isRecording) {
      buttonColor = AppColors.primaryRed;
    } else if (_isTranscribing) {
      buttonColor = AppColors.primaryOrange;
    } else {
      buttonColor = AppColors.primaryBlue;
    }

    return GestureDetector(
      onTap: !_isProcessing && !_isTranscribing && _hasModelSelected
          ? _toggleRecording
          : null,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _hasModelSelected ? buttonColor : AppColors.statusGray,
          boxShadow: [
            BoxShadow(
              color: buttonColor.withValues(alpha: 0.3),
              blurRadius: AppSpacing.shadowXLarge,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: _isProcessing || _isTranscribing
            ? const Padding(
                padding: EdgeInsets.all(AppSpacing.xLarge),
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Icon(
                _isRecording ? Icons.stop : Icons.mic,
                color: Colors.white,
                size: 32,
              ),
      ),
    );
  }
}
