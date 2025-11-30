import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/design_system/app_colors.dart';
import '../../core/design_system/app_spacing.dart';
import '../../core/design_system/typography.dart';
import '../models/model_selection_sheet.dart';
import '../models/model_status_components.dart';
import '../models/model_types.dart';

/// TTSMetadata (matching iOS TTSMetadata)
class TTSMetadata {
  final double durationMs;
  final int audioSize;
  final int sampleRate;

  const TTSMetadata({
    required this.durationMs,
    required this.audioSize,
    required this.sampleRate,
  });
}

/// TextToSpeechView (mirroring iOS TextToSpeechView.swift)
///
/// Dedicated TTS view with speech generation and playback controls.
class TextToSpeechView extends StatefulWidget {
  const TextToSpeechView({super.key});

  @override
  State<TextToSpeechView> createState() => _TextToSpeechViewState();
}

class _TextToSpeechViewState extends State<TextToSpeechView> {
  final TextEditingController _textController = TextEditingController(
    text: 'Hello! This is a text to speech test.',
  );

  // Playback state
  bool _isGenerating = false;
  bool _isPlaying = false;
  bool _hasAudio = false;
  double _currentTime = 0.0;
  double _duration = 0.0;
  double _playbackProgress = 0.0;

  // Voice settings
  double _speechRate = 1.0;
  double _pitch = 1.0;

  // Model state
  LLMFramework? _selectedFramework;
  String? _selectedModelName;
  bool _isSystemTTS = false;

  // Audio metadata
  TTSMetadata? _metadata;

  // Error state
  String? _errorMessage;

  // Timer for playback simulation
  Timer? _playbackTimer;

  // Character limit
  static const int _maxCharacters = 5000;

  bool get _hasModelSelected =>
      _selectedFramework != null && _selectedModelName != null;

  @override
  void dispose() {
    _textController.dispose();
    _playbackTimer?.cancel();
    super.dispose();
  }

  void _showModelSelectionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => ModelSelectionSheet(
        context: ModelSelectionContext.tts,
        onModelSelected: (model) async {
          await _loadModel(model);
        },
      ),
    );
  }

  Future<void> _loadModel(ModelInfo model) async {
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      // TODO: Load TTS model via RunAnywhere SDK
      // await RunAnywhere.loadTTSModel(model.id);
      await Future.delayed(const Duration(milliseconds: 500)); // Simulate

      setState(() {
        _selectedFramework = model.preferredFramework ?? LLMFramework.systemTTS;
        _selectedModelName = model.name;
        _isSystemTTS = model.preferredFramework == LLMFramework.systemTTS;
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
      _metadata = null;
    });

    try {
      // TODO: Generate speech via RunAnywhere SDK
      // final output = await RunAnywhere.synthesize(
      //   _textController.text,
      //   language: 'en-US',
      //   speed: _speechRate,
      //   pitch: _pitch,
      // );
      await Future.delayed(const Duration(seconds: 1)); // Simulate

      // Simulate metadata
      final textLength = _textController.text.length;
      final estimatedDuration = textLength * 50.0; // ~50ms per character
      final estimatedSize = textLength * 100; // ~100 bytes per character

      setState(() {
        _isGenerating = false;
        _hasAudio = !_isSystemTTS;
        _duration = estimatedDuration / 1000;
        _metadata = TTSMetadata(
          durationMs: estimatedDuration,
          audioSize: _isSystemTTS ? 0 : estimatedSize,
          sampleRate: 22050,
        );

        // System TTS plays directly
        if (_isSystemTTS) {
          _isPlaying = true;
          _simulatePlayback();
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Speech generation failed: $e';
        _isGenerating = false;
      });
    }
  }

  void _simulatePlayback() {
    _playbackTimer?.cancel();

    final totalMs = (_duration * 1000).toInt();
    const steps = 50;
    final stepDuration = totalMs ~/ steps;

    int currentStep = 0;

    _playbackTimer = Timer.periodic(
      Duration(milliseconds: stepDuration.clamp(50, 500)),
      (timer) {
        if (!_isPlaying || currentStep >= steps) {
          timer.cancel();
          if (mounted) {
            setState(() {
              _isPlaying = false;
              _playbackProgress = 0;
              _currentTime = 0;
            });
          }
          return;
        }

        currentStep++;
        if (mounted) {
          setState(() {
            _playbackProgress = currentStep / steps;
            _currentTime = _duration * _playbackProgress;
          });
        }
      },
    );
  }

  void _togglePlayback() {
    if (_isPlaying) {
      _stopPlayback();
    } else if (_hasAudio) {
      setState(() {
        _isPlaying = true;
        _playbackProgress = 0;
        _currentTime = 0;
      });
      _simulatePlayback();
    }
  }

  void _stopPlayback() {
    _playbackTimer?.cancel();
    setState(() {
      _isPlaying = false;
      _playbackProgress = 0;
      _currentTime = 0;
    });
  }

  String _formatTime(double seconds) {
    final mins = seconds.floor() ~/ 60;
    final secs = seconds.floor() % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  String _formatBytes(int bytes) {
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    } else {
      return '${(kb / 1024).toStringAsFixed(1)} MB';
    }
  }

  @override
  Widget build(BuildContext context) {
    final characterCount = _textController.text.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Text to Speech'),
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
                  isLoading: _isGenerating && !_hasModelSelected,
                  onSelectModel: _showModelSelectionSheet,
                ),
              ),

              const Divider(),

              // Main content (only when model is selected)
              if (_hasModelSelected) ...[
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.large),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Text input section
                        _buildTextInputSection(characterCount),
                        const SizedBox(height: AppSpacing.xLarge),

                        // Voice settings section
                        _buildVoiceSettingsSection(),
                        const SizedBox(height: AppSpacing.xLarge),

                        // Audio metadata (when available)
                        if (_metadata != null) _buildAudioInfoSection(),

                        // Error message
                        if (_errorMessage != null) _buildErrorBanner(),
                      ],
                    ),
                  ),
                ),

                const Divider(),

                // Controls section
                _buildControlsSection(),
              ] else
                const Expanded(child: SizedBox()),
            ],
          ),

          // Model required overlay
          if (!_hasModelSelected && !_isGenerating)
            ModelRequiredOverlay(
              modality: ModelSelectionContext.tts,
              onSelectModel: _showModelSelectionSheet,
            ),
        ],
      ),
    );
  }

  Widget _buildTextInputSection(int characterCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter Text',
          style: AppTypography.headlineSemibold(context),
        ),
        const SizedBox(height: AppSpacing.mediumLarge),
        Container(
          decoration: BoxDecoration(
            color: AppColors.backgroundGray6(context),
            borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusCard),
            border: Border.all(
              color: AppColors.borderMedium,
              width: 1,
            ),
          ),
          child: TextField(
            controller: _textController,
            maxLines: 6,
            maxLength: _maxCharacters,
            decoration: const InputDecoration(
              hintText: 'Type or paste text here...',
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(AppSpacing.large),
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: AppSpacing.xSmall),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '$characterCount characters',
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

  Widget _buildVoiceSettingsSection() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.backgroundGray6(context),
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Voice Settings',
            style: AppTypography.headlineSemibold(context),
          ),
          const SizedBox(height: AppSpacing.large),

          // Speech rate slider
          _buildSliderRow(
            label: 'Speed',
            value: _speechRate,
            min: 0.5,
            max: 2.0,
            color: AppColors.primaryBlue,
            onChanged: (value) {
              setState(() {
                _speechRate = value;
              });
            },
          ),
          const SizedBox(height: AppSpacing.mediumLarge),

          // Pitch slider
          _buildSliderRow(
            label: 'Pitch',
            value: _pitch,
            min: 0.5,
            max: 2.0,
            color: AppColors.primaryPurple,
            onChanged: (value) {
              setState(() {
                _pitch = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: AppTypography.subheadline(context),
            ),
            Text(
              '${value.toStringAsFixed(1)}x',
              style: AppTypography.subheadline(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: ((max - min) * 10).toInt(),
          activeColor: color,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildAudioInfoSection() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      margin: const EdgeInsets.only(bottom: AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.backgroundGray6(context),
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Audio Info',
            style: AppTypography.headlineSemibold(context),
          ),
          const SizedBox(height: AppSpacing.mediumLarge),
          _buildMetadataRow(
            icon: Icons.graphic_eq,
            label: 'Duration',
            value: '${(_metadata!.durationMs / 1000).toStringAsFixed(2)}s',
          ),
          const SizedBox(height: AppSpacing.smallMedium),
          _buildMetadataRow(
            icon: Icons.description,
            label: 'Size',
            value: _formatBytes(_metadata!.audioSize),
          ),
          const SizedBox(height: AppSpacing.smallMedium),
          _buildMetadataRow(
            icon: Icons.volume_up,
            label: 'Sample Rate',
            value: '${_metadata!.sampleRate} Hz',
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: AppColors.textSecondary(context),
        ),
        const SizedBox(width: AppSpacing.smallMedium),
        Text(
          '$label:',
          style: AppTypography.caption(context).copyWith(
            color: AppColors.textSecondary(context),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: AppTypography.captionMedium(context),
        ),
      ],
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
          const Icon(Icons.error, color: AppColors.primaryRed),
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

  Widget _buildControlsSection() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Column(
        children: [
          // Playback progress (when playing)
          if (_isPlaying)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.large),
              child: Row(
                children: [
                  Text(
                    _formatTime(_currentTime),
                    style: AppTypography.caption(context).copyWith(
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.smallMedium),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: _playbackProgress,
                      backgroundColor: AppColors.backgroundGray5(context),
                      valueColor: const AlwaysStoppedAnimation(AppColors.primaryPurple),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.smallMedium),
                  Text(
                    _formatTime(_duration),
                    style: AppTypography.caption(context).copyWith(
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Generate/Speak button
              FilledButton.icon(
                onPressed: _textController.text.isNotEmpty &&
                        !_isGenerating &&
                        _hasModelSelected
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
                    : Icon(_isSystemTTS ? Icons.volume_up : Icons.graphic_eq),
                label: Text(_isSystemTTS ? 'Speak' : 'Generate'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  minimumSize: const Size(140, 50),
                ),
              ),

              const SizedBox(width: AppSpacing.xLarge),

              // Play/Stop button (only for non-System TTS)
              FilledButton.icon(
                onPressed: _hasAudio && !_isSystemTTS ? _togglePlayback : null,
                icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                label: Text(_isPlaying ? 'Stop' : 'Play'),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      _hasAudio ? AppColors.statusGreen : AppColors.statusGray,
                  minimumSize: const Size(140, 50),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.mediumLarge),

          // Status text
          Text(
            _isSystemTTS
                ? (_isGenerating ? 'Speaking...' : 'System TTS plays directly')
                : (_isGenerating
                    ? 'Generating speech...'
                    : _isPlaying
                        ? 'Playing...'
                        : 'Ready'),
            style: AppTypography.caption(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}
