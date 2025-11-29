import 'package:flutter/material.dart';

import '../../core/design_system/app_colors.dart';
import '../../core/design_system/app_spacing.dart';
import '../../core/design_system/typography.dart';

/// TextToSpeechView (mirroring iOS TextToSpeechView.swift)
///
/// Dedicated TTS view with speech generation and playback controls.
class TextToSpeechView extends StatefulWidget {
  const TextToSpeechView({super.key});

  @override
  State<TextToSpeechView> createState() => _TextToSpeechViewState();
}

class _TextToSpeechViewState extends State<TextToSpeechView> {
  final TextEditingController _textController = TextEditingController();

  // Playback state
  bool _isGenerating = false;
  bool _isPlaying = false;
  bool _hasAudio = false;
  double _playbackProgress = 0.0;

  // Voice settings
  double _speed = 1.0;
  double _pitch = 1.0;
  String _selectedVoice = 'System Default';

  // Model state
  String? _selectedModel;
  bool _isModelLoaded = false;

  // Error state
  String? _errorMessage;

  // Character limit
  static const int _maxCharacters = 5000;

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadModel() async {
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      // TODO: Load TTS model via RunAnywhere SDK
      // await RunAnywhere.loadTTSModel('system');
      await Future.delayed(const Duration(milliseconds: 500)); // Simulate

      setState(() {
        _selectedModel = 'System TTS';
        _isModelLoaded = true;
        _isGenerating = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load model: $e';
        _isGenerating = false;
      });
    }
  }

  Future<void> _generateSpeech() async {
    if (_textController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter text to speak';
      });
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _hasAudio = false;
    });

    try {
      // TODO: Generate speech via RunAnywhere SDK
      // final output = await RunAnywhere.synthesize(
      //   _textController.text,
      //   language: 'en-US',
      //   speed: _speed,
      //   pitch: _pitch,
      // );
      await Future.delayed(const Duration(seconds: 1)); // Simulate

      setState(() {
        _isGenerating = false;
        _hasAudio = true;
        _isPlaying = true; // Auto-play for system TTS
      });

      // Simulate playback
      _simulatePlayback();
    } catch (e) {
      setState(() {
        _errorMessage = 'Speech generation failed: $e';
        _isGenerating = false;
      });
    }
  }

  void _simulatePlayback() async {
    final duration = _textController.text.length * 50; // Rough estimate
    final steps = 20;
    final stepDuration = duration / steps;

    for (var i = 0; i <= steps; i++) {
      if (!_isPlaying) break;

      await Future.delayed(Duration(milliseconds: stepDuration.toInt()));

      if (mounted) {
        setState(() {
          _playbackProgress = i / steps;
        });
      }
    }

    if (mounted) {
      setState(() {
        _isPlaying = false;
        _playbackProgress = 0;
      });
    }
  }

  void _togglePlayback() {
    if (_isPlaying) {
      setState(() {
        _isPlaying = false;
      });
    } else if (_hasAudio) {
      setState(() {
        _isPlaying = true;
        _playbackProgress = 0;
      });
      _simulatePlayback();
    }
  }

  void _stopPlayback() {
    setState(() {
      _isPlaying = false;
      _playbackProgress = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final characterCount = _textController.text.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Text to Speech'),
      ),
      body: Column(
        children: [
          // Model status banner
          _buildModelStatusBanner(),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.large),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Text input
                  _buildTextInput(characterCount),
                  const SizedBox(height: AppSpacing.large),

                  // Voice settings
                  _buildVoiceSettings(),
                  const SizedBox(height: AppSpacing.large),

                  // Error message
                  if (_errorMessage != null) _buildErrorBanner(),

                  // Playback controls
                  if (_hasAudio) _buildPlaybackControls(),
                ],
              ),
            ),
          ),

          // Generate button
          _buildGenerateButton(),
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
                ? 'Voice: $_selectedModel'
                : 'Loading...',
            style: AppTypography.subheadline(context),
          ),
        ],
      ),
    );
  }

  Widget _buildTextInput(int characterCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter text to speak',
          style: AppTypography.headlineSemibold(context),
        ),
        const SizedBox(height: AppSpacing.smallMedium),
        Container(
          decoration: BoxDecoration(
            color: AppColors.backgroundGray6(context),
            borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusCard),
          ),
          child: TextField(
            controller: _textController,
            maxLines: 8,
            maxLength: _maxCharacters,
            decoration: InputDecoration(
              hintText: 'Type or paste text here...',
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(AppSpacing.large),
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: AppSpacing.xSmall),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '$characterCount / $_maxCharacters',
            style: AppTypography.caption(context).copyWith(
              color: characterCount > _maxCharacters
                  ? AppColors.primaryRed
                  : AppColors.textSecondary(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Voice Settings',
              style: AppTypography.subheadlineSemibold(context),
            ),
            const SizedBox(height: AppSpacing.large),

            // Speed slider
            Row(
              children: [
                SizedBox(
                  width: 60,
                  child: Text(
                    'Speed',
                    style: AppTypography.subheadline(context),
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: _speed,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    label: '${_speed.toStringAsFixed(1)}x',
                    onChanged: (value) {
                      setState(() {
                        _speed = value;
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${_speed.toStringAsFixed(1)}x',
                    style: AppTypography.caption(context),
                  ),
                ),
              ],
            ),

            // Pitch slider
            Row(
              children: [
                SizedBox(
                  width: 60,
                  child: Text(
                    'Pitch',
                    style: AppTypography.subheadline(context),
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: _pitch,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    label: '${_pitch.toStringAsFixed(1)}x',
                    onChanged: (value) {
                      setState(() {
                        _pitch = value;
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${_pitch.toStringAsFixed(1)}x',
                    style: AppTypography.caption(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.mediumLarge),
      margin: const EdgeInsets.only(bottom: AppSpacing.large),
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

  Widget _buildPlaybackControls() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Playback',
              style: AppTypography.subheadlineSemibold(context),
            ),
            const SizedBox(height: AppSpacing.mediumLarge),

            // Progress bar
            LinearProgressIndicator(
              value: _playbackProgress,
              backgroundColor: AppColors.backgroundGray5(context),
            ),
            const SizedBox(height: AppSpacing.mediumLarge),

            // Playback buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(
                    _isPlaying ? Icons.pause_circle : Icons.play_circle,
                  ),
                  iconSize: AppSpacing.iconLarge,
                  color: AppColors.primaryBlue,
                  onPressed: _togglePlayback,
                ),
                const SizedBox(width: AppSpacing.large),
                IconButton(
                  icon: const Icon(Icons.stop_circle),
                  iconSize: AppSpacing.iconLarge,
                  color: AppColors.primaryRed,
                  onPressed: _stopPlayback,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenerateButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.large),
      child: FilledButton.icon(
        onPressed: _isModelLoaded &&
                !_isGenerating &&
                _textController.text.isNotEmpty
            ? _generateSpeech
            : null,
        icon: _isGenerating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.volume_up),
        label: Text(_isGenerating ? 'Generating...' : 'Speak'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, AppSpacing.buttonHeightRegular),
        ),
      ),
    );
  }
}
