import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/design_system/app_colors.dart';
import '../../core/design_system/app_spacing.dart';
import '../../core/design_system/typography.dart';
import '../models/model_selection_sheet.dart';
import '../models/model_status_components.dart';
import '../models/model_types.dart';

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

  // Timer for audio level simulation
  Timer? _audioLevelTimer;

  bool get _hasModelSelected =>
      _selectedFramework != null && _selectedModelName != null;

  @override
  void initState() {
    super.initState();
    _checkMicrophonePermission();
  }

  @override
  void dispose() {
    _audioLevelTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkMicrophonePermission() async {
    final status = await Permission.microphone.status;
    if (!status.isGranted) {
      await Permission.microphone.request();
    }
  }

  void _showModelSelectionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => ModelSelectionSheet(
        context: ModelSelectionContext.stt,
        onModelSelected: (model) async {
          await _loadModel(model);
        },
      ),
    );
  }

  Future<void> _loadModel(ModelInfo model) async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // TODO: Load STT model via RunAnywhere SDK
      // await RunAnywhere.loadSTTModel(model.id);
      await Future.delayed(const Duration(milliseconds: 500)); // Simulate

      setState(() {
        _selectedFramework = model.preferredFramework ?? LLMFramework.whisperKit;
        _selectedModelName = model.name;
        // TODO: Check if model supports live mode via SDK
        _supportsLiveMode = model.preferredFramework == LLMFramework.whisperKit;
        _isProcessing = false;
      });
    } catch (e) {
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
    final status = await Permission.microphone.status;
    if (!status.isGranted) {
      final result = await Permission.microphone.request();
      if (!result.isGranted) {
        setState(() {
          _errorMessage = 'Microphone permission required';
        });
        return;
      }
    }

    setState(() {
      _isRecording = true;
      _errorMessage = null;
      _transcribedText = '';
      _partialText = '';
    });

    // Start audio level simulation
    _startAudioLevelSimulation();

    if (_selectedMode == STTMode.live) {
      // TODO: Implement live transcription via RunAnywhere SDK
      // Start audio stream and process in real-time
      _simulateLiveTranscription();
    } else {
      // TODO: Implement batch recording
      // Record audio and transcribe when stopped
    }
  }

  Future<void> _stopRecording() async {
    _audioLevelTimer?.cancel();

    setState(() {
      _isRecording = false;
      _audioLevel = 0.0;
    });

    if (_selectedMode == STTMode.batch && _partialText.isEmpty) {
      // Process batch recording
      setState(() {
        _isTranscribing = true;
      });

      try {
        // TODO: Transcribe recorded audio via RunAnywhere SDK
        // final result = await RunAnywhere.transcribe(audioData);
        await Future.delayed(const Duration(seconds: 1)); // Simulate

        setState(() {
          _transcribedText = 'This is a sample transcription from the batch recording. '
              'The actual transcription will come from the STT model.';
          _isTranscribing = false;
        });
      } catch (e) {
        setState(() {
          _errorMessage = 'Transcription failed: $e';
          _isTranscribing = false;
        });
      }
    } else if (_selectedMode == STTMode.live) {
      // Live mode - finalize the transcription
      if (_partialText.isNotEmpty) {
        setState(() {
          _transcribedText = _partialText;
          _partialText = '';
        });
      }
    }
  }

  void _startAudioLevelSimulation() {
    _audioLevelTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isRecording) {
        timer.cancel();
        return;
      }

      setState(() {
        // Simulate audio level fluctuation
        _audioLevel = 0.3 + (DateTime.now().millisecondsSinceEpoch % 700) / 1000;
      });
    });
  }

  void _simulateLiveTranscription() {
    // Simulated live transcription for demo
    final words = [
      'Hello,',
      ' this',
      ' is',
      ' a',
      ' live',
      ' transcription',
      ' demo.',
    ];
    int wordIndex = 0;

    Timer.periodic(const Duration(milliseconds: 400), (timer) {
      if (!_isRecording || wordIndex >= words.length) {
        timer.cancel();
        return;
      }

      setState(() {
        _partialText += words[wordIndex];
      });
      wordIndex++;
    });
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

        // TODO: Add metadata display when SDK provides it
        // metadataRow(icon: Icons.timer, label: 'Processing', value: '120ms'),
        // metadataRow(icon: Icons.graphic_eq, label: 'Audio Duration', value: '3.5s'),
        // metadataRow(icon: Icons.speed, label: 'Real-time Factor', value: '0.25x'),
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
