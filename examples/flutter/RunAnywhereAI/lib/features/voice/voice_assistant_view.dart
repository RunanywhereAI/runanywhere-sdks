import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:runanywhere/runanywhere.dart';

import '../../core/design_system/app_colors.dart';
import '../../core/design_system/app_spacing.dart';
import '../../core/design_system/typography.dart';
import '../../core/models/app_types.dart';
import '../../core/services/model_manager.dart';

/// VoiceAssistantView (mirroring iOS VoiceAssistantView.swift)
///
/// Main voice assistant UI with conversational interface.
class VoiceAssistantView extends StatefulWidget {
  const VoiceAssistantView({super.key});

  @override
  State<VoiceAssistantView> createState() => _VoiceAssistantViewState();
}

class _VoiceAssistantViewState extends State<VoiceAssistantView>
    with SingleTickerProviderStateMixin {
  // Session state
  VoiceSessionState _sessionState = VoiceSessionState.disconnected;
  bool _isSpeechDetected = false;

  // Conversation
  final List<_ConversationTurn> _conversation = [];
  String _currentTranscription = '';

  // Model state
  String? _sttModel;
  String? _llmModel;
  String? _ttsModel;
  ModelLoadState _sttModelState = ModelLoadState.notLoaded;
  ModelLoadState _llmModelState = ModelLoadState.notLoaded;
  ModelLoadState _ttsModelState = ModelLoadState.notLoaded;

  // Error state
  String? _errorMessage;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initialize();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    // Request microphone permission
    final status = await Permission.microphone.status;
    if (!status.isGranted) {
      await Permission.microphone.request();
    }

    // Check model states
    // TODO: Subscribe to model lifecycle via RunAnywhere SDK
    // await _subscribeToModelLifecycle();

    setState(() {
      // Placeholder - in production, get actual model states
      _sttModelState = ModelLoadState.notLoaded;
      _llmModelState = ModelLoadState.notLoaded;
      _ttsModelState = ModelLoadState.notLoaded;
    });
  }

  Future<void> _startConversation() async {
    setState(() {
      _sessionState = VoiceSessionState.connecting;
      _errorMessage = null;
    });

    try {
      // TODO: Create ModularVoicePipeline via RunAnywhere SDK
      // final config = ModularPipelineConfig(
      //   components: [.vad, .stt, .llm, .tts],
      //   vad: VADConfig(energyThreshold: 0.005),
      //   stt: VoiceSTTConfig(modelId: 'whisper-base'),
      //   llm: VoiceLLMConfig(modelId: 'default', systemPrompt: '...'),
      //   tts: VoiceTTSConfig(voice: 'system'),
      // );
      // _voicePipeline = await RunAnywhere.createVoicePipeline(config);
      // _voicePipeline.events.listen(_handlePipelineEvent);
      // await _voicePipeline.start();

      // Placeholder: Simulate connection
      await Future.delayed(const Duration(milliseconds: 500));

      setState(() {
        _sessionState = VoiceSessionState.connected;
      });

      // Start listening animation
      _pulseController.repeat(reverse: true);
    } catch (e) {
      setState(() {
        _sessionState = VoiceSessionState.error;
        _errorMessage = 'Failed to start voice pipeline: $e';
      });
    }
  }

  Future<void> _stopConversation() async {
    _pulseController.stop();
    _pulseController.reset();

    // TODO: Stop voice pipeline
    // await _voicePipeline?.stop();

    setState(() {
      _sessionState = VoiceSessionState.disconnected;
      _currentTranscription = '';
    });
  }

  void _toggleListening() {
    if (_sessionState == VoiceSessionState.disconnected ||
        _sessionState == VoiceSessionState.error) {
      _startConversation();
    } else {
      _stopConversation();
    }
  }

  Future<void> _processTurn() async {
    if (_currentTranscription.isEmpty) return;

    setState(() {
      _sessionState = VoiceSessionState.processing;
      _conversation.add(_ConversationTurn(
        role: ConversationRole.user,
        text: _currentTranscription,
      ));
    });

    try {
      // TODO: Use voice pipeline for end-to-end processing
      // For now, use simple chat API
      final response = await RunAnywhere.chat(_currentTranscription);

      setState(() {
        _conversation.add(_ConversationTurn(
          role: ConversationRole.assistant,
          text: response,
        ));
        _sessionState = VoiceSessionState.speaking;
        _currentTranscription = '';
      });

      // TODO: Play TTS audio
      // await _voicePipeline?.speak(response);

      // Simulate speaking
      await Future.delayed(const Duration(seconds: 2));

      setState(() {
        _sessionState = VoiceSessionState.connected;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to process: $e';
        _sessionState = VoiceSessionState.connected;
      });
    }
  }

  void _clearConversation() {
    setState(() {
      _conversation.clear();
      _currentTranscription = '';
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Assistant'),
        actions: [
          if (_conversation.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearConversation,
              tooltip: 'Clear conversation',
            ),
        ],
      ),
      body: Column(
        children: [
          // Model info banner
          _buildModelInfoBanner(),

          // Conversation area
          Expanded(
            child: _buildConversationArea(),
          ),

          // Status indicator
          _buildStatusIndicator(),

          // Error message
          if (_errorMessage != null) _buildErrorBanner(),

          // Microphone button
          _buildMicrophoneButton(),
        ],
      ),
    );
  }

  Widget _buildModelInfoBanner() {
    final allLoaded = _sttModelState == ModelLoadState.loaded &&
        _llmModelState == ModelLoadState.loaded &&
        _ttsModelState == ModelLoadState.loaded;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.mediumLarge),
      color: allLoaded ? AppColors.badgeGreen : AppColors.badgeOrange,
      child: Row(
        children: [
          Icon(
            allLoaded ? Icons.check_circle : Icons.info,
            size: AppSpacing.iconRegular,
            color: allLoaded ? AppColors.statusGreen : AppColors.statusOrange,
          ),
          const SizedBox(width: AppSpacing.smallMedium),
          Expanded(
            child: Text(
              allLoaded
                  ? 'Voice pipeline ready'
                  : 'Voice pipeline not configured',
              style: AppTypography.subheadline(context),
            ),
          ),
          TextButton(
            onPressed: () {
              // TODO: Show model selection sheet
            },
            child: const Text('Configure'),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationArea() {
    if (_conversation.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.mic,
              size: AppSpacing.iconXXLarge,
              color: AppColors.textSecondary(context),
            ),
            const SizedBox(height: AppSpacing.large),
            Text(
              'Tap to start voice conversation',
              style: AppTypography.title2(context),
            ),
            const SizedBox(height: AppSpacing.smallMedium),
            Text(
              'Speak naturally and the AI will respond',
              style: AppTypography.subheadline(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.large),
      itemCount: _conversation.length,
      itemBuilder: (context, index) {
        final turn = _conversation[index];
        return _buildConversationBubble(turn);
      },
    );
  }

  Widget _buildConversationBubble(_ConversationTurn turn) {
    final isUser = turn.role == ConversationRole.user;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.mediumLarge),
        padding: const EdgeInsets.all(AppSpacing.large),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          gradient: isUser
              ? LinearGradient(
                  colors: [
                    AppColors.userBubbleGradientStart,
                    AppColors.userBubbleGradientEnd,
                  ],
                )
              : null,
          color: isUser ? null : AppColors.backgroundGray5(context),
          borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusBubble),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowLight,
              blurRadius: AppSpacing.shadowSmall,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          turn.text,
          style: AppTypography.body(context).copyWith(
            color: isUser ? AppColors.textWhite : AppColors.textPrimary(context),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator() {
    String statusText;
    Color statusColor;

    switch (_sessionState) {
      case VoiceSessionState.disconnected:
        statusText = 'Tap microphone to start';
        statusColor = AppColors.statusGray;
        break;
      case VoiceSessionState.connecting:
        statusText = 'Connecting...';
        statusColor = AppColors.statusBlue;
        break;
      case VoiceSessionState.connected:
        statusText = 'Listening...';
        statusColor = AppColors.statusGreen;
        break;
      case VoiceSessionState.listening:
        statusText = 'Speak now...';
        statusColor = AppColors.statusGreen;
        break;
      case VoiceSessionState.processing:
        statusText = 'Processing...';
        statusColor = AppColors.statusBlue;
        break;
      case VoiceSessionState.speaking:
        statusText = 'Speaking...';
        statusColor = AppColors.statusPurple;
        break;
      case VoiceSessionState.error:
        statusText = 'Error occurred';
        statusColor = AppColors.statusRed;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.large,
        vertical: AppSpacing.smallMedium,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.smallMedium),
          Text(
            statusText,
            style: AppTypography.caption(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.all(AppSpacing.large),
      padding: const EdgeInsets.all(AppSpacing.mediumLarge),
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

  Widget _buildMicrophoneButton() {
    final isActive = _sessionState != VoiceSessionState.disconnected &&
        _sessionState != VoiceSessionState.error;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xLarge),
      decoration: BoxDecoration(
        color: AppColors.backgroundPrimary(context),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowMedium,
            blurRadius: AppSpacing.shadowLarge,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Center(
        child: AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: isActive ? _pulseAnimation.value : 1.0,
              child: GestureDetector(
                onTap: _toggleListening,
                child: Container(
                  width: AppSpacing.buttonHeightLarge,
                  height: AppSpacing.buttonHeightLarge,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? AppColors.primaryRed
                        : AppColors.primaryBlue,
                    boxShadow: [
                      BoxShadow(
                        color: (isActive
                                ? AppColors.primaryRed
                                : AppColors.primaryBlue)
                            .withValues(alpha: 0.3),
                        blurRadius: isActive ? 20 : 10,
                        spreadRadius: isActive ? 5 : 0,
                      ),
                    ],
                  ),
                  child: Icon(
                    _getButtonIcon(),
                    color: Colors.white,
                    size: AppSpacing.iconMedium,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  IconData _getButtonIcon() {
    switch (_sessionState) {
      case VoiceSessionState.disconnected:
      case VoiceSessionState.error:
        return Icons.mic;
      case VoiceSessionState.connecting:
      case VoiceSessionState.processing:
        return Icons.hourglass_empty;
      case VoiceSessionState.connected:
      case VoiceSessionState.listening:
        return Icons.mic;
      case VoiceSessionState.speaking:
        return Icons.volume_up;
    }
  }
}

// Helper classes

enum ConversationRole { user, assistant }

class _ConversationTurn {
  final ConversationRole role;
  final String text;
  final DateTime timestamp;

  _ConversationTurn({
    required this.role,
    required this.text,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
