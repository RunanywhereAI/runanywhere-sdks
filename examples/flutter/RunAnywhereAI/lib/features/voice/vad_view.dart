import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/features/models/model_selection_sheet.dart';
import 'package:runanywhere_ai/features/models/model_status_components.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';

class VADView extends StatefulWidget {
  const VADView({super.key});

  @override
  State<VADView> createState() => _VADViewState();
}

class _VADViewState extends State<VADView> {
  final sdk.AudioCaptureManager _capture = sdk.AudioCaptureManager();
  StreamSubscription<sdk.VADResult>? _vadSubscription;
  StreamSubscription<double>? _levelSubscription;

  bool _isLoadingModel = false;
  bool _isListening = false;
  String? _modelName;
  sdk.InferenceFramework? _framework;
  String? _errorMessage;
  bool _isSpeech = false;
  double _confidence = 0;
  double _energy = 0;
  int _frameCount = 0;
  double _audioLevel = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_syncModelState());
  }

  @override
  void dispose() {
    unawaited(_vadSubscription?.cancel());
    unawaited(_levelSubscription?.cancel());
    unawaited(_capture.dispose());
    super.dispose();
  }

  Future<void> _syncModelState() async {
    final model = await sdk.RunAnywhere.vad.currentModel();
    if (!mounted) return;
    setState(() {
      _modelName = model?.name;
      _framework = model?.framework;
    });
  }

  Future<void> _loadModel(ModelInfo model) async {
    setState(() {
      _isLoadingModel = true;
      _errorMessage = null;
    });

    try {
      await sdk.RunAnywhere.vad.loadModel(model.id);
      if (!mounted) return;
      setState(() {
        _modelName = model.name;
        _framework = model.framework;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Failed to load VAD model: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingModel = false);
      }
    }
  }

  void _showModelSelectionSheet() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => ModelSelectionSheet(
          context: ModelSelectionContext.vad,
          onModelSelected: _loadModel,
        ),
      ),
    );
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!sdk.RunAnywhere.vad.isModelLoaded) {
      setState(() => _errorMessage = 'Select a VAD model first');
      return;
    }

    final chunks = await _capture.startRecording(
      sampleRate: 16000,
      numChannels: 1,
    );
    if (chunks == null) {
      setState(() => _errorMessage = 'Microphone capture failed');
      return;
    }

    await _levelSubscription?.cancel();
    _levelSubscription = _capture.audioLevelStream?.listen((level) {
      if (!mounted) return;
      setState(() => _audioLevel = level);
    });

    _vadSubscription = sdk.RunAnywhere.vad
        .streamVAD(chunks)
        .listen(
          (result) {
            if (!mounted) return;
            if (result.errorMessage.isNotEmpty) {
              setState(() {
                _errorMessage = result.errorMessage;
                _isListening = false;
              });
              unawaited(_capture.cancel());
              return;
            }
            setState(() {
              _isSpeech = result.isSpeech;
              _confidence = result.confidence;
              _energy = result.energy;
              _frameCount += 1;
            });
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() {
              _errorMessage = 'VAD failed: $e';
              _isListening = false;
            });
          },
          onDone: () {
            if (!mounted) return;
            setState(() => _isListening = false);
          },
        );

    setState(() {
      _isListening = true;
      _errorMessage = null;
      _frameCount = 0;
    });
  }

  Future<void> _stopListening() async {
    await _vadSubscription?.cancel();
    _vadSubscription = null;
    await _levelSubscription?.cancel();
    _levelSubscription = null;
    await _capture.stopRecording();
    if (!mounted) return;
    setState(() {
      _isListening = false;
      _audioLevel = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Activity')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.large),
        children: [
          ModelStatusBanner(
            framework: _framework,
            modelName: _modelName,
            isLoading: _isLoadingModel,
            onSelectModel: _showModelSelectionSheet,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: AppSpacing.large),
            _ErrorBanner(message: _errorMessage!),
          ],
          const SizedBox(height: AppSpacing.large),
          _StatusCard(
            isListening: _isListening,
            isSpeech: _isSpeech,
            confidence: _confidence,
            energy: _energy,
            audioLevel: _audioLevel,
            frameCount: _frameCount,
          ),
          const SizedBox(height: AppSpacing.large),
          SizedBox(
            height: AppSpacing.buttonHeightRegular,
            child: FilledButton.icon(
              onPressed: _isLoadingModel ? null : _toggleListening,
              icon: Icon(_isListening ? Icons.stop : Icons.mic),
              label: Text(_isListening ? 'Stop' : 'Start'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.isListening,
    required this.isSpeech,
    required this.confidence,
    required this.energy,
    required this.audioLevel,
    required this.frameCount,
  });

  final bool isListening;
  final bool isSpeech;
  final double confidence;
  final double energy;
  final double audioLevel;
  final int frameCount;

  @override
  Widget build(BuildContext context) {
    final statusColor = isSpeech ? AppColors.statusGreen : AppColors.statusGray;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSpeech ? Icons.record_voice_over : Icons.hearing,
                  color: statusColor,
                ),
                const SizedBox(width: AppSpacing.smallMedium),
                Text(
                  isSpeech ? 'Speech detected' : 'Listening for speech',
                  style: AppTypography.headlineSemibold(
                    context,
                  ).copyWith(color: statusColor),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.large),
            _MetricRow(
              label: 'Mic Level',
              value: audioLevel,
              color: AppColors.primaryBlue,
            ),
            _MetricRow(
              label: 'Confidence',
              value: confidence,
              color: statusColor,
            ),
            _MetricRow(
              label: 'Energy',
              value: energy,
              color: AppColors.primaryPurple,
            ),
            const Divider(),
            Text(
              isListening ? 'Frames: $frameCount' : 'Not listening',
              style: AppTypography.caption(
                context,
              ).copyWith(color: AppColors.textSecondary(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mediumLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: AppTypography.subheadline(context)),
              Text(
                clamped.toStringAsFixed(2),
                style: AppTypography.caption(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xSmall),
          LinearProgressIndicator(
            value: clamped,
            color: color,
            backgroundColor: AppColors.backgroundGray5(context),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.mediumLarge),
      decoration: BoxDecoration(
        color: AppColors.badgeRed,
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.primaryRed),
          const SizedBox(width: AppSpacing.smallMedium),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
