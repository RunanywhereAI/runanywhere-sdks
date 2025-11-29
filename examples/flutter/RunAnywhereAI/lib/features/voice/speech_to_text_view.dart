import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/design_system/app_colors.dart';
import '../../core/design_system/app_spacing.dart';
import '../../core/design_system/typography.dart';

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
  bool _isLiveMode = true;
  String _transcribedText = '';
  String _partialText = '';
  double _audioLevel = 0.0;

  // Model state
  String? _selectedModel;
  bool _isModelLoaded = false;

  // Error state
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkMicrophonePermission();
    _loadModel();
  }

  Future<void> _checkMicrophonePermission() async {
    final status = await Permission.microphone.status;
    if (!status.isGranted) {
      await Permission.microphone.request();
    }
  }

  Future<void> _loadModel() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // TODO: Load STT model via RunAnywhere SDK
      // await RunAnywhere.loadSTTModel('whisper-base');
      await Future.delayed(const Duration(milliseconds: 500)); // Simulate

      setState(() {
        _selectedModel = 'whisper-base';
        _isModelLoaded = true;
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
      _partialText = '';
    });

    if (_isLiveMode) {
      // TODO: Implement live transcription via RunAnywhere SDK
      // Start audio stream and process in real-time
      _simulateLiveTranscription();
    } else {
      // TODO: Implement batch transcription
      // Record audio and transcribe when stopped
    }
  }

  Future<void> _stopRecording() async {
    setState(() {
      _isRecording = false;
    });

    if (!_isLiveMode && _partialText.isEmpty) {
      // Process batch recording
      setState(() {
        _isProcessing = true;
      });

      try {
        // TODO: Transcribe recorded audio via RunAnywhere SDK
        await Future.delayed(const Duration(seconds: 1)); // Simulate

        setState(() {
          _transcribedText += '\n[Transcribed audio]';
          _isProcessing = false;
        });
      } catch (e) {
        setState(() {
          _errorMessage = 'Transcription failed: $e';
          _isProcessing = false;
        });
      }
    } else {
      // Live mode - just stop recording, text is already captured
      if (_partialText.isNotEmpty) {
        setState(() {
          _transcribedText += '\n$_partialText';
          _partialText = '';
        });
      }
    }
  }

  void _simulateLiveTranscription() {
    // Simulated live transcription for demo
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_isRecording) {
        timer.cancel();
        return;
      }

      setState(() {
        _partialText = 'Listening...';
        _audioLevel = 0.5;
      });
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
      body: Column(
        children: [
          // Model status banner
          _buildModelStatusBanner(),

          // Mode selector
          _buildModeSelector(),

          // Transcription area
          Expanded(
            child: _buildTranscriptionArea(),
          ),

          // Audio level indicator (when recording)
          if (_isRecording) _buildAudioLevelIndicator(),

          // Error message
          if (_errorMessage != null) _buildErrorBanner(),

          // Recording controls
          _buildRecordingControls(),
        ],
      ),
    );
  }

  Widget _buildModelStatusBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.mediumLarge),
      color: _isModelLoaded
          ? AppColors.badgeGreen
          : AppColors.badgeOrange,
      child: Row(
        children: [
          Icon(
            _isModelLoaded ? Icons.check_circle : Icons.info,
            size: AppSpacing.iconRegular,
            color: _isModelLoaded
                ? AppColors.statusGreen
                : AppColors.statusOrange,
          ),
          const SizedBox(width: AppSpacing.smallMedium),
          Text(
            _isModelLoaded
                ? 'Model: $_selectedModel'
                : 'Loading model...',
            style: AppTypography.subheadline(context),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
            value: true,
            label: Text('Live'),
            icon: Icon(Icons.stream),
          ),
          ButtonSegment(
            value: false,
            label: Text('Batch'),
            icon: Icon(Icons.mic),
          ),
        ],
        selected: {_isLiveMode},
        onSelectionChanged: _isRecording
            ? null
            : (Set<bool> selection) {
                setState(() {
                  _isLiveMode = selection.first;
                });
              },
      ),
    );
  }

  Widget _buildTranscriptionArea() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.large),
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.backgroundGray6(context),
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusCard),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_transcribedText.isEmpty && _partialText.isEmpty)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.graphic_eq,
                      size: AppSpacing.iconXLarge,
                      color: AppColors.textSecondary(context),
                    ),
                    const SizedBox(height: AppSpacing.large),
                    Text(
                      'Tap the microphone to start',
                      style: AppTypography.subheadline(context).copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
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
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAudioLevelIndicator() {
    return Container(
      height: 4,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.large),
      child: LinearProgressIndicator(
        value: _audioLevel,
        backgroundColor: AppColors.backgroundGray5(context),
        valueColor: AlwaysStoppedAnimation(AppColors.primaryBlue),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.mediumLarge),
      margin: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.badgeRed,
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
      ),
      child: Row(
        children: [
          const Icon(Icons.error, color: Colors.red),
          const SizedBox(width: AppSpacing.smallMedium),
          Expanded(
            child: Text(
              _errorMessage!,
              style: AppTypography.subheadline(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingControls() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xLarge),
      child: Column(
        children: [
          // Recording button
          GestureDetector(
            onTap: _isModelLoaded && !_isProcessing ? _toggleRecording : null,
            child: Container(
              width: AppSpacing.buttonHeightLarge,
              height: AppSpacing.buttonHeightLarge,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRecording
                    ? AppColors.primaryRed
                    : _isModelLoaded
                        ? AppColors.primaryBlue
                        : AppColors.statusGray,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadowMedium,
                    blurRadius: AppSpacing.shadowLarge,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _isProcessing
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
                      size: AppSpacing.iconMedium,
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.mediumLarge),
          Text(
            _isRecording
                ? 'Tap to stop'
                : _isProcessing
                    ? 'Processing...'
                    : 'Tap to record',
            style: AppTypography.caption(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}
