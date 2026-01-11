import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;

import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/core/models/app_types.dart';
import 'package:runanywhere_ai/core/services/permission_service.dart';
import 'package:runanywhere_ai/features/models/model_selection_sheet.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';

/// VoiceAssistantView (mirroring iOS VoiceAssistantView.swift)
///
/// Main voice assistant UI with conversational interface.
/// Orchestrates STT -> LLM -> TTS pipeline using SDK's VoiceSession API.
class VoiceAssistantView extends StatefulWidget {
  const VoiceAssistantView({super.key});

  @override
  State<VoiceAssistantView> createState() => _VoiceAssistantViewState();
}

class _VoiceAssistantViewState extends State<VoiceAssistantView>
    with SingleTickerProviderStateMixin {
  // Session state
  VoiceSessionState _sessionState = VoiceSessionState.disconnected;
  sdk.VoiceSessionHandle? _voiceSession;
  StreamSubscription<sdk.VoiceSessionEvent>? _eventSubscription;

  // Conversation
  final List<_ConversationTurn> _conversation = [];
  String _currentTranscript = '';
  String _assistantResponse = '';

  // Audio level for visualization
  double _audioLevel = 0.0;
  bool _isSpeechDetected = false;

  // Model state - tracks which models are loaded
  AppModelLoadState _sttModelState = AppModelLoadState.notLoaded;
  AppModelLoadState _llmModelState = AppModelLoadState.notLoaded;
  AppModelLoadState _ttsModelState = AppModelLoadState.notLoaded;

  // Current model names
  String _currentSTTModel = 'Not loaded';
  String _currentLLMModel = 'Not loaded';
  String _currentTTSModel = 'Not loaded';

  // UI state
  bool _showModelInfo = false;

  // Error state
  String? _errorMessage;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool get _allModelsLoaded =>
      _sttModelState == AppModelLoadState.loaded &&
      _llmModelState == AppModelLoadState.loaded &&
      _ttsModelState == AppModelLoadState.loaded;

  bool get _isActive =>
      _sessionState != VoiceSessionState.disconnected &&
      _sessionState != VoiceSessionState.error;

  bool get _isListening =>
      _sessionState == VoiceSessionState.listening ||
      _sessionState == VoiceSessionState.connected;

  bool get _isProcessing =>
      _sessionState == VoiceSessionState.processing ||
      _sessionState == VoiceSessionState.connecting;

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
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _cleanup();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _refreshComponentStates();
  }

  /// Refresh model states from SDK (matches Swift VoiceAgentViewModel pattern)
  /// NOTE: Voice agent API is not yet fully implemented in SDK
  Future<void> _refreshComponentStates() async {
    try {
      // Use SDK public API to check loaded states (matches Swift pattern)
      final currentModelId = sdk.RunAnywhere.currentModelId;
      final sttModelId = sdk.RunAnywhere.currentSTTModelId;
      final ttsVoiceId = sdk.RunAnywhere.currentTTSVoiceId;

      if (!mounted) return;
      setState(() {
        _sttModelState = sttModelId != null
            ? AppModelLoadState.loaded
            : AppModelLoadState.notLoaded;
        _llmModelState = currentModelId != null
            ? AppModelLoadState.loaded
            : AppModelLoadState.notLoaded;
        _ttsModelState = ttsVoiceId != null
            ? AppModelLoadState.loaded
            : AppModelLoadState.notLoaded;

        _currentSTTModel = sttModelId ?? 'Not loaded';
        _currentLLMModel = currentModelId ?? 'Not loaded';
        _currentTTSModel = ttsVoiceId ?? 'Not loaded';
      });
    } catch (e) {
      debugPrint('Failed to get component states: $e');
    }
  }

  Future<void> _startConversation() async {
    // Request STT permissions before starting
    final hasPermission =
        await PermissionService.shared.requestSTTPermissions(context);
    if (!hasPermission) {
      setState(() {
        _sessionState = VoiceSessionState.error;
        _errorMessage = 'Microphone permission is required for voice assistant';
      });
      return;
    }

    setState(() {
      _sessionState = VoiceSessionState.connecting;
      _errorMessage = null;
    });

    try {
      // Check if voice agent is ready using SDK API
      if (!sdk.RunAnywhere.isVoiceAgentReady) {
        setState(() {
          _sessionState = VoiceSessionState.error;
          _errorMessage = 'Please load STT, LLM, and TTS models first';
        });
        return;
      }

      // Use SDK's startVoiceSession API (matches Swift: RunAnywhere.startVoiceSession())
      _voiceSession = await sdk.RunAnywhere.startVoiceSession(
        config: const sdk.VoiceSessionConfig(),
      );

      // Listen to session events
      _eventSubscription = _voiceSession!.events.listen(
        _handleSessionEvent,
        onError: (Object error) {
          setState(() {
            _sessionState = VoiceSessionState.error;
            _errorMessage = 'Voice session error: $error';
          });
        },
      );

      setState(() {
        _sessionState = VoiceSessionState.connected;
      });

      // Start pulse animation
      unawaited(_pulseController.repeat(reverse: true));
    } catch (e) {
      setState(() {
        _sessionState = VoiceSessionState.error;
        _errorMessage = 'Failed to start voice session: $e';
      });
    }
  }

  void _handleSessionEvent(sdk.VoiceSessionEvent event) {
    if (event is sdk.VoiceSessionListening) {
      setState(() {
        _sessionState = VoiceSessionState.listening;
        _audioLevel = event.audioLevel;
        // Update speech detected based on audio level threshold
        _isSpeechDetected = event.audioLevel > 0.1;
      });
    } else if (event is sdk.VoiceSessionSpeechStarted) {
      setState(() {
        _isSpeechDetected = true;
      });
    } else if (event is sdk.VoiceSessionTranscribed) {
      setState(() {
        _currentTranscript = event.text;
        _sessionState = VoiceSessionState.processing;
      });
    } else if (event is sdk.VoiceSessionResponded) {
      setState(() {
        _assistantResponse = event.text;
      });
    } else if (event is sdk.VoiceSessionSpeaking) {
      setState(() {
        _sessionState = VoiceSessionState.speaking;
      });
    } else if (event is sdk.VoiceSessionTurnCompleted) {
      // Add completed turn to conversation
      if (event.transcript.isNotEmpty) {
        setState(() {
          _conversation.add(_ConversationTurn(
            role: ConversationRole.user,
            text: event.transcript,
          ));
          if (event.response.isNotEmpty) {
            _conversation.add(_ConversationTurn(
              role: ConversationRole.assistant,
              text: event.response,
            ));
          }
          _currentTranscript = '';
          _assistantResponse = '';
          _sessionState = VoiceSessionState.listening;
        });
      }
    } else if (event is sdk.VoiceSessionError) {
      setState(() {
        _sessionState = VoiceSessionState.error;
        _errorMessage = event.message;
      });
    } else if (event is sdk.VoiceSessionStopped) {
      // Properly clean up subscriptions and controllers instead of just setting state
      unawaited(_stopConversation());
    }
  }

  Future<void> _stopConversation() async {
    _pulseController.stop();
    _pulseController.reset();

    await _eventSubscription?.cancel();
    _eventSubscription = null;

    _voiceSession?.stop();
    _voiceSession = null;

    setState(() {
      _sessionState = VoiceSessionState.disconnected;
      _currentTranscript = '';
      _assistantResponse = '';
      _audioLevel = 0.0;
      _isSpeechDetected = false;
    });
  }

  void _toggleListening() {
    if (_isActive) {
      unawaited(_stopConversation());
    } else {
      unawaited(_startConversation());
    }
  }

  void _cleanup() {
    unawaited(_stopConversation());
  }

  void _showSTTModelSelection() {
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ModelSelectionSheet(
        context: ModelSelectionContext.stt,
        onModelSelected: (model) async {
          await _refreshComponentStates();
        },
      ),
    ));
  }

  void _showLLMModelSelection() {
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ModelSelectionSheet(
        context: ModelSelectionContext.llm,
        onModelSelected: (model) async {
          await _refreshComponentStates();
        },
      ),
    ));
  }

  void _showTTSModelSelection() {
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ModelSelectionSheet(
        context: ModelSelectionContext.tts,
        onModelSelected: (model) async {
          await _refreshComponentStates();
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Show setup view when models aren't all loaded
    if (!_allModelsLoaded) {
      return _buildSetupView();
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header with model controls
            _buildHeader(),

            // Model info (expandable)
            if (_showModelInfo) _buildModelInfoSection(),

            // Conversation area
            Expanded(child: _buildConversationArea()),

            // Error message
            if (_errorMessage != null) _buildErrorBanner(),

            // Audio level indicator
            if (_isListening) _buildAudioLevelIndicator(),

            // Control area
            _buildControlArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupView() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Assistant Setup'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.xLarge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'Configure Voice Pipeline',
              style: AppTypography.title(context),
            ),
            const SizedBox(height: AppSpacing.smallMedium),
            Text(
              'Select models for each component to enable voice conversations.',
              style: AppTypography.body(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: AppSpacing.xxLarge),

            // STT Model
            _buildModelConfigRow(
              icon: Icons.graphic_eq,
              label: 'Speech-to-Text',
              modelName: _currentSTTModel,
              state: _sttModelState,
              color: AppColors.statusGreen,
              onTap: _showSTTModelSelection,
            ),
            const SizedBox(height: AppSpacing.large),

            // LLM Model
            _buildModelConfigRow(
              icon: Icons.psychology,
              label: 'Language Model',
              modelName: _currentLLMModel,
              state: _llmModelState,
              color: AppColors.primaryBlue,
              onTap: _showLLMModelSelection,
            ),
            const SizedBox(height: AppSpacing.large),

            // TTS Model
            _buildModelConfigRow(
              icon: Icons.volume_up,
              label: 'Text-to-Speech',
              modelName: _currentTTSModel,
              state: _ttsModelState,
              color: AppColors.primaryPurple,
              onTap: _showTTSModelSelection,
            ),

            const Spacer(),

            // Start button (enabled when all models loaded)
            if (_allModelsLoaded)
              Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Refresh to transition to main UI
                    setState(() {});
                  },
                  icon: const Icon(Icons.mic),
                  label: const Text('Start Voice Assistant'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xLarge,
                      vertical: AppSpacing.mediumLarge,
                    ),
                  ),
                ),
              ),

            const SizedBox(height: AppSpacing.xxLarge),
          ],
        ),
      ),
    );
  }

  Widget _buildModelConfigRow({
    required IconData icon,
    required String label,
    required String modelName,
    required AppModelLoadState state,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isLoaded = state == AppModelLoadState.loaded;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.large),
        decoration: BoxDecoration(
          color: isLoaded
              ? color.withValues(alpha: 0.1)
              : AppColors.backgroundGray5(context),
          borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
          border: Border.all(
            color: isLoaded ? color.withValues(alpha: 0.3) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: AppSpacing.mediumLarge),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.subheadline(context)),
                  const SizedBox(height: 2),
                  Text(
                    modelName,
                    style: AppTypography.caption(context).copyWith(
                      color:
                          isLoaded ? color : AppColors.textSecondary(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              isLoaded ? Icons.check_circle : Icons.add_circle_outline,
              color: isLoaded ? color : AppColors.textSecondary(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.large,
        vertical: AppSpacing.mediumLarge,
      ),
      child: Row(
        children: [
          // Model selection button
          IconButton(
            onPressed: () {
              // Show model selection options
              unawaited(showModalBottomSheet<void>(
                context: context,
                builder: (context) => _buildModelSelectionMenu(),
              ));
            },
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.backgroundGray5(context),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.view_in_ar, size: 18),
            ),
          ),

          const Spacer(),

          // Status indicator
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _getStatusColor(),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _sessionState.name,
                style: AppTypography.caption(context).copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
            ],
          ),

          const Spacer(),

          // Model info toggle
          IconButton(
            onPressed: () => setState(() => _showModelInfo = !_showModelInfo),
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.backgroundGray5(context),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _showModelInfo ? Icons.info : Icons.info_outline,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelSelectionMenu() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Voice Models', style: AppTypography.headline(context)),
          const SizedBox(height: AppSpacing.large),
          ListTile(
            leading: const Icon(Icons.graphic_eq, color: AppColors.statusGreen),
            title: const Text('Speech-to-Text'),
            subtitle: Text(_currentSTTModel),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pop(context);
              _showSTTModelSelection();
            },
          ),
          ListTile(
            leading: const Icon(Icons.psychology, color: AppColors.primaryBlue),
            title: const Text('Language Model'),
            subtitle: Text(_currentLLMModel),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pop(context);
              _showLLMModelSelection();
            },
          ),
          ListTile(
            leading:
                const Icon(Icons.volume_up, color: AppColors.primaryPurple),
            title: const Text('Text-to-Speech'),
            subtitle: Text(_currentTTSModel),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pop(context);
              _showTTSModelSelection();
            },
          ),
          const SizedBox(height: AppSpacing.large),
        ],
      ),
    );
  }

  Widget _buildModelInfoSection() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.large,
        vertical: AppSpacing.mediumLarge,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ModelBadge(
            icon: Icons.psychology,
            label: 'LLM',
            value: _currentLLMModel,
            color: AppColors.primaryBlue,
          ),
          _ModelBadge(
            icon: Icons.graphic_eq,
            label: 'STT',
            value: _currentSTTModel,
            color: AppColors.statusGreen,
          ),
          _ModelBadge(
            icon: Icons.volume_up,
            label: 'TTS',
            value: _currentTTSModel,
            color: AppColors.primaryPurple,
          ),
        ],
      ),
    );
  }

  Widget _buildConversationArea() {
    if (_conversation.isEmpty &&
        _currentTranscript.isEmpty &&
        _assistantResponse.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.mic_none,
              size: 48,
              color: AppColors.textSecondary(context).withValues(alpha: 0.3),
            ),
            const SizedBox(height: AppSpacing.mediumLarge),
            Text(
              'Tap the microphone to start',
              style: AppTypography.subheadline(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.large),
      children: [
        // Past conversation turns
        ..._conversation.map(_buildConversationBubble),

        // Current transcription (in progress)
        if (_currentTranscript.isNotEmpty)
          _buildConversationBubble(_ConversationTurn(
            role: ConversationRole.user,
            text: _currentTranscript,
          )),

        // Current assistant response (in progress)
        if (_assistantResponse.isNotEmpty)
          _buildConversationBubble(_ConversationTurn(
            role: ConversationRole.assistant,
            text: _assistantResponse,
          )),
      ],
    );
  }

  Widget _buildConversationBubble(_ConversationTurn turn) {
    final isUser = turn.role == ConversationRole.user;
    final speaker = isUser ? 'You' : 'Assistant';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.large),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            speaker,
            style: AppTypography.caption(context).copyWith(
              color: AppColors.textSecondary(context),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(AppSpacing.mediumLarge),
            decoration: BoxDecoration(
              color: isUser
                  ? AppColors.backgroundGray5(context)
                  : AppColors.primaryBlue.withValues(alpha: 0.08),
              borderRadius:
                  BorderRadius.circular(AppSpacing.cornerRadiusBubble),
            ),
            child: Text(
              turn.text,
              style: AppTypography.body(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioLevelIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.large,
        vertical: AppSpacing.smallMedium,
      ),
      child: Column(
        children: [
          // Recording badge
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.smallMedium,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: AppColors.statusRed.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.statusRed,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'RECORDING',
                  style: AppTypography.caption2(context).copyWith(
                    color: AppColors.statusRed,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.smallMedium),

          // Audio level bars
          SizedBox(
            height: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(20, (index) {
                final threshold = index / 20;
                final isActive = _audioLevel > threshold;
                return Container(
                  width: 4,
                  height: 24 * (isActive ? _audioLevel : 0.2),
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.statusGreen
                        : AppColors.statusGray.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
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
          const Icon(Icons.error, color: AppColors.statusRed),
          const SizedBox(width: AppSpacing.smallMedium),
          Expanded(
            child: Text(
              _errorMessage!,
              style: AppTypography.subheadline(context),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _errorMessage = null),
          ),
        ],
      ),
    );
  }

  Widget _buildControlArea() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xLarge),
      child: Column(
        children: [
          // Mic button
          Center(
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _isListening ? _pulseAnimation.value : 1.0,
                  child: GestureDetector(
                    onTap: _toggleListening,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _getMicButtonColor(),
                        boxShadow: [
                          BoxShadow(
                            color: _getMicButtonColor().withValues(alpha: 0.3),
                            blurRadius: _isListening ? 20 : 10,
                            spreadRadius: _isListening ? 5 : 0,
                          ),
                        ],
                      ),
                      child: _isProcessing
                          ? const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            )
                          : Icon(
                              _getMicButtonIcon(),
                              color: Colors.white,
                              size: 28,
                            ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: AppSpacing.mediumLarge),

          // Instruction text
          Text(
            _getInstructionText(),
            style: AppTypography.caption2(context).copyWith(
              color: AppColors.textSecondary(context).withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    switch (_sessionState) {
      case VoiceSessionState.disconnected:
        return AppColors.statusGray;
      case VoiceSessionState.connecting:
        return AppColors.statusBlue;
      case VoiceSessionState.connected:
      case VoiceSessionState.listening:
        return AppColors.statusGreen;
      case VoiceSessionState.processing:
        return AppColors.statusBlue;
      case VoiceSessionState.speaking:
        return AppColors.primaryPurple;
      case VoiceSessionState.error:
        return AppColors.statusRed;
    }
  }

  Color _getMicButtonColor() {
    if (_isActive) {
      return AppColors.primaryRed;
    }
    return AppColors.primaryBlue;
  }

  IconData _getMicButtonIcon() {
    switch (_sessionState) {
      case VoiceSessionState.disconnected:
      case VoiceSessionState.error:
        return Icons.mic;
      case VoiceSessionState.connected:
      case VoiceSessionState.listening:
        return Icons.stop;
      case VoiceSessionState.speaking:
        return Icons.volume_up;
      default:
        return Icons.mic;
    }
  }

  String _getInstructionText() {
    switch (_sessionState) {
      case VoiceSessionState.disconnected:
        return 'Tap to start voice conversation';
      case VoiceSessionState.connecting:
        return 'Connecting...';
      case VoiceSessionState.connected:
      case VoiceSessionState.listening:
        return _isSpeechDetected ? 'Listening...' : 'Speak now';
      case VoiceSessionState.processing:
        return 'Processing...';
      case VoiceSessionState.speaking:
        return 'Assistant is speaking';
      case VoiceSessionState.error:
        return 'Tap to retry';
    }
  }
}

// MARK: - Supporting Widgets

class _ModelBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _ModelBadge({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.smallMedium,
        vertical: AppSpacing.xSmall,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTypography.caption2(context).copyWith(
                  color: AppColors.textSecondary(context),
                  fontSize: 9,
                ),
              ),
              Text(
                value,
                style: AppTypography.caption2(context).copyWith(
                  fontWeight: FontWeight.w500,
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// MARK: - Helper Classes

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
