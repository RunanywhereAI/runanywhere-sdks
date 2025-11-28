import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart';
import '../../core/design_system/app_colors.dart';
import '../../core/design_system/app_spacing.dart';
import '../../core/design_system/typography.dart';

/// Voice Assistant View
class VoiceAssistantView extends StatefulWidget {
  const VoiceAssistantView({super.key});

  @override
  State<VoiceAssistantView> createState() => _VoiceAssistantViewState();
}

class _VoiceAssistantViewState extends State<VoiceAssistantView> {
  bool _isListening = false;
  bool _isProcessing = false;
  String _transcription = '';
  String _response = '';
  String? _error;

  Future<void> _startListening() async {
    setState(() {
      _isListening = true;
      _error = null;
    });

    // TODO: Implement actual audio recording
    // For now, show a placeholder
    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      _isListening = false;
      _isProcessing = true;
    });

    try {
      // Placeholder: In production, record audio and transcribe
      // final audioData = await _recordAudio();
      // final transcription = await RunAnywhere.transcribe(audioData);

      // For demo purposes, simulate transcription
      final transcription = 'Hello, how are you?';

      setState(() {
        _transcription = transcription;
        _isProcessing = false;
      });

      // Generate response
      final response = await RunAnywhere.chat(transcription);
      setState(() {
        _response = response;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isProcessing = false;
      });
    }
  }

  void _stopListening() {
    setState(() {
      _isListening = false;
    });
  }

  void _clear() {
    setState(() {
      _transcription = '';
      _response = '';
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Assistant'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.padding16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_transcription.isNotEmpty) ...[
                    Text(
                      'You said:',
                     // style: AppTypography.headlineSemibold,
                    ),
                    const SizedBox(height: AppSpacing.padding8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.padding16),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary(context),
                        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
                      ),
                      child: Text(
                        _transcription,
                        style: AppTypography.body(context),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.padding24),
                  ],
                  if (_response.isNotEmpty) ...[
                    Text(
                      'Assistant:',
                      //style: AppTypography.headlineSemibold,
                    ),
                    const SizedBox(height: AppSpacing.padding8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.padding16),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
                      ),
                      child: Text(
                        _response,
                        style: AppTypography.body(context),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.padding16),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.padding16),
                      decoration: BoxDecoration(
                        color: AppColors.primaryRed.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
                      ),
                      child: Text(
                        'Error: $_error',
                        style: AppTypography.body(context).copyWith(color: AppColors.primaryRed),
                      ),
                    ),
                  ],
                  if (_transcription.isEmpty && _response.isEmpty && _error == null)
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.mic,
                            size: AppSpacing.iconXXLarge,
                            color: AppColors.primaryBlue,
                          ),
                          const SizedBox(height: AppSpacing.large),
                          Text(
                            'Tap to start voice conversation',
                            style: AppTypography.title2(context),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(AppSpacing.padding24),
            decoration: BoxDecoration(
              color: AppColors.backgroundPrimary(context),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_transcription.isNotEmpty || _response.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: _clear,
                    tooltip: 'Clear',
                  ),
                const SizedBox(width: AppSpacing.padding16),
                GestureDetector(
                  onTapDown: (_) => _startListening(),
                  onTapUp: (_) => _stopListening(),
                  onTapCancel: _stopListening,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: _isListening
                          ? AppColors.primaryRed
                          : AppColors.primaryBlue,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
                if (_isProcessing)
                  const Padding(
                    padding: EdgeInsets.only(left: AppSpacing.padding16),
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
