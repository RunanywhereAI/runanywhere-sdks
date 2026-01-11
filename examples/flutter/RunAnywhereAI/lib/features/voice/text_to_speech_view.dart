import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;

import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/core/services/audio_player_service.dart';
import 'package:runanywhere_ai/features/models/model_selection_sheet.dart';
import 'package:runanywhere_ai/features/models/model_status_components.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';

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
/// Now uses RunAnywhere SDK for actual speech synthesis.
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
  // ignore: unused_field - kept for future TTS implementation
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

  // Audio player service
  final AudioPlayerService _playerService = AudioPlayerService.instance;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<double>? _progressSubscription;

  // Character limit
  static const int _maxCharacters = 5000;

  bool get _hasModelSelected =>
      _selectedFramework != null && _selectedModelName != null;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeAudioPlayer());
  }

  @override
  void dispose() {
    _textController.dispose();
    unawaited(_playingSubscription?.cancel());
    unawaited(_progressSubscription?.cancel());
    super.dispose();
  }

  Future<void> _initializeAudioPlayer() async {
    await _playerService.initialize();

    // Subscribe to playing state
    _playingSubscription = _playerService.playingStream.listen((isPlaying) {
      if (mounted) {
        setState(() {
          _isPlaying = isPlaying;
        });
      }
    });

    // Subscribe to progress updates
    _progressSubscription = _playerService.progressStream.listen((progress) {
      if (mounted) {
        setState(() {
          _playbackProgress = progress;
          _currentTime = _duration * progress;
        });
      }
    });
  }

  void _showModelSelectionSheet() {
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => ModelSelectionSheet(
        context: ModelSelectionContext.tts,
        onModelSelected: (model) async {
          await _loadModel(model);
        },
      ),
    ));
  }

  /// Load TTS model using RunAnywhere SDK
  Future<void> _loadModel(ModelInfo model) async {
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      debugPrint('🔄 Loading TTS voice: ${model.name}');

      // Load TTS voice via RunAnywhere SDK
      await sdk.RunAnywhere.loadTTSVoice(model.id);

      setState(() {
        _selectedFramework = model.preferredFramework ?? LLMFramework.systemTTS;
        _selectedModelName = model.name;
        _isSystemTTS = model.preferredFramework == LLMFramework.systemTTS;
        _isGenerating = false;
      });

      debugPrint('✅ TTS model loaded: ${model.name}');
    } catch (e) {
      debugPrint('❌ Failed to load TTS model: $e');
      setState(() {
        _errorMessage = 'Failed to load model: $e';
        _isGenerating = false;
      });
    }
  }

  /// Generate speech using RunAnywhere SDK
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
      debugPrint('🔊 Generating speech with SDK...');

      // Check if TTS voice is loaded via SDK (matches Swift: RunAnywhere.isTTSVoiceLoaded)
      if (!sdk.RunAnywhere.isTTSVoiceLoaded) {
        throw Exception(
            'TTS component not loaded. Please load a TTS voice first.');
      }

      // Call SDK TTS synthesis API (matches Swift: RunAnywhere.synthesize(_:))
      final result = await sdk.RunAnywhere.synthesize(
        _textController.text,
        rate: _speechRate,
        pitch: _pitch,
        volume: 1.0,
      );

      debugPrint(
          '✅ TTS synthesis complete: ${result.samples.length} samples, ${result.sampleRate} Hz, ${result.durationMs}ms');

      setState(() {
        _isGenerating = false;
        _hasAudio = result.samples.isNotEmpty;
        _duration = result.durationSeconds;
        _metadata = TTSMetadata(
          durationMs: result.durationMs.toDouble(),
          audioSize: result.samples.length * 4, // 4 bytes per float sample
          sampleRate: result.sampleRate,
        );
      });

      // Auto-play if audio was generated
      if (result.samples.isNotEmpty) {
        await _playFloatAudio(result.samples, result.sampleRate);
      }
    } catch (e) {
      debugPrint('❌ Speech generation failed: $e');
      setState(() {
        _errorMessage = 'Speech generation failed: $e';
        _isGenerating = false;
      });
    }
  }

  /// Play audio from Float32List samples (TTS output)
  Future<void> _playFloatAudio(Float32List samples, int sampleRate) async {
    try {
      // Convert Float32 PCM samples to Int16 PCM bytes
      // TTS returns samples in range [-1.0, 1.0], we convert to Int16 range [-32768, 32767]
      final pcmData = ByteData(samples.length * 2); // 2 bytes per Int16 sample
      for (var i = 0; i < samples.length; i++) {
        // Clamp and scale to Int16 range
        final sample = (samples[i].clamp(-1.0, 1.0) * 32767).round();
        pcmData.setInt16(i * 2, sample, Endian.little);
      }

      await _playerService.playFromBytes(
        pcmData.buffer.asUint8List(),
        volume: 1.0,
        rate: 1.0, // Rate is already applied in TTS synthesis
        sampleRate: sampleRate,
        numChannels: 1, // Mono audio
      );
      debugPrint(
          '🔊 Playing TTS audio: ${samples.length} samples at $sampleRate Hz');
    } catch (e) {
      debugPrint('❌ Failed to play TTS audio: $e');
      setState(() {
        _errorMessage = 'Failed to play audio: $e';
      });
    }
  }

  /// Play audio using the audio player service (for Int16 PCM data)
  // ignore: unused_element - kept for alternative audio formats
  Future<void> _playAudio(List<int> audioData) async {
    try {
      // Convert List<int> to Uint8List
      final audioBytes = Uint8List.fromList(audioData);

      // The TTS component returns PCM16 data at 22050 Hz mono
      // We need to pass the sample rate so the audio player can create proper WAV headers
      await _playerService.playFromBytes(
        audioBytes,
        volume: 1.0, // Use full volume (pitch controls are in TTS synthesis)
        rate: _speechRate,
        sampleRate: 22050, // Piper TTS default sample rate
        numChannels: 1, // Mono audio
      );
      debugPrint('🔊 Playing audio...');
    } catch (e) {
      debugPrint('❌ Failed to play audio: $e');
      setState(() {
        _errorMessage = 'Failed to play audio: $e';
      });
    }
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _stopPlayback();
    }
  }

  Future<void> _stopPlayback() async {
    await _playerService.stop();
    debugPrint('⏹️ Playback stopped');
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
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.primaryPurple),
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

              // Stop button (when playing)
              if (_isPlaying)
                FilledButton.icon(
                  onPressed: _togglePlayback,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryRed,
                    minimumSize: const Size(140, 50),
                  ),
                ),
            ],
          ),

          const SizedBox(height: AppSpacing.mediumLarge),

          // Status text
          Text(
            _isGenerating
                ? 'Generating speech...'
                : _isPlaying
                    ? 'Playing...'
                    : 'Ready',
            style: AppTypography.caption(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}
