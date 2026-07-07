import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere_protos.dart' as proto;

import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/core/models/app_types.dart';
import 'package:runanywhere_ai/core/services/permission_service.dart';
import 'package:runanywhere_ai/features/models/model_selection_sheet.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';
import 'package:runanywhere_ai/features/voice/voice_agent_view_model.dart';

/// VoiceAssistantView
///
/// Main voice assistant UI with conversational interface. Purely UI — the
/// STT -> LLM -> TTS session state machine lives in [VoiceAgentViewModel].
class VoiceAssistantView extends StatefulWidget {
  const VoiceAssistantView({super.key});

  @override
  State<VoiceAssistantView> createState() => _VoiceAssistantViewState();
}

class _VoiceAssistantViewState extends State<VoiceAssistantView>
    with SingleTickerProviderStateMixin {
  final VoiceAgentViewModel _viewModel = VoiceAgentViewModel();

  // UI state
  bool _showModelInfo = false;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Keeps the conversation pinned to the newest message.
  final ScrollController _scrollController = ScrollController();

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
    // Drive the pulse animation from the ViewModel's session state.
    _viewModel.addListener(_syncPulseAnimation);
    unawaited(_viewModel.initialize());
  }

  @override
  void dispose() {
    _viewModel.removeListener(_syncPulseAnimation);
    _viewModel.dispose();
    _pulseController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Pin the conversation list to the newest message after the frame paints.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        unawaited(
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          ),
        );
      }
    });
  }

  void _syncPulseAnimation() {
    if (_viewModel.isActive) {
      if (!_pulseController.isAnimating) {
        unawaited(_pulseController.repeat(reverse: true));
      }
    } else if (_pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  Future<void> _startConversation() async {
    // Permission UI needs a BuildContext, so the request stays in the view.
    final hasPermission = await PermissionService.shared.requestSTTPermissions(
      context,
    );
    if (!hasPermission) {
      _viewModel.reportPermissionDenied();
      return;
    }
    await _viewModel.startConversation();
  }

  void _toggleListening() {
    if (_viewModel.isActive) {
      unawaited(_viewModel.stopConversation());
    } else {
      unawaited(_startConversation());
    }
  }

  void _showSTTModelSelection() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => ModelSelectionSheet(
          context: ModelSelectionContext.stt,
          onModelSelected: (model) async {
            await _viewModel.refreshComponentStates();
          },
        ),
      ),
    );
  }

  void _showLLMModelSelection() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => ModelSelectionSheet(
          context: ModelSelectionContext.llm,
          onModelSelected: (model) async {
            await _viewModel.refreshComponentStates();
          },
        ),
      ),
    );
  }

  void _showTTSModelSelection() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => ModelSelectionSheet(
          context: ModelSelectionContext.tts,
          onModelSelected: (model) async {
            await _viewModel.refreshComponentStates();
          },
        ),
      ),
    );
  }

  void _showVADModelSelection() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => ModelSelectionSheet(
          context: ModelSelectionContext.vad,
          onModelSelected: (model) async {
            await _viewModel.refreshComponentStates();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        // Show setup view when models aren't all loaded
        if (!_viewModel.allModelsLoaded) {
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
                if (_viewModel.errorMessage != null) _buildErrorBanner(),

                // Audio level indicator
                if (_viewModel.isListening) _buildAudioLevelIndicator(),

                // Control area
                _buildControlArea(),
              ],
            ),
          ),
        );
      },
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
              style: AppTypography.body(
                context,
              ).copyWith(color: AppColors.textSecondary(context)),
            ),
            const SizedBox(height: AppSpacing.xxLarge),

            // STT Model
            _buildModelConfigRow(
              icon: Icons.graphic_eq,
              label: 'Speech-to-Text',
              modelName: _viewModel.currentSTTModel,
              state: _viewModel.sttModelState,
              color: AppColors.statusGreen,
              onTap: _showSTTModelSelection,
            ),
            const SizedBox(height: AppSpacing.large),

            // LLM Model
            _buildModelConfigRow(
              icon: Icons.psychology,
              label: 'Language Model',
              modelName: _viewModel.currentLLMModel,
              state: _viewModel.llmModelState,
              color: AppColors.primaryBlue,
              onTap: _showLLMModelSelection,
            ),
            const SizedBox(height: AppSpacing.large),

            // TTS Model
            _buildModelConfigRow(
              icon: Icons.volume_up,
              label: 'Text-to-Speech',
              modelName: _viewModel.currentTTSModel,
              state: _viewModel.ttsModelState,
              color: AppColors.primaryPurple,
              onTap: _showTTSModelSelection,
            ),
            const SizedBox(height: AppSpacing.large),

            // VAD Model
            _buildModelConfigRow(
              icon: Icons.hearing,
              label: 'Voice Activity (VAD)',
              modelName: _viewModel.currentVADModel,
              state: _viewModel.vadModelState,
              color: AppColors.statusOrange,
              onTap: _showVADModelSelection,
            ),
            const SizedBox(height: AppSpacing.smallMedium),

            const Spacer(),

            // Start button (enabled when all models loaded)
            if (_viewModel.allModelsLoaded)
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
    required UiModelLoadState state,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isLoaded = state == UiModelLoadState.loaded;

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
                      color: isLoaded
                          ? color
                          : AppColors.textSecondary(context),
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
              unawaited(
                showModalBottomSheet<void>(
                  context: context,
                  builder: (context) => _buildModelSelectionMenu(),
                ),
              );
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
                _viewModel.sessionState.name,
                style: AppTypography.caption(
                  context,
                ).copyWith(color: AppColors.textSecondary(context)),
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
            subtitle: Text(_viewModel.currentSTTModel),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pop(context);
              _showSTTModelSelection();
            },
          ),
          ListTile(
            leading: const Icon(Icons.psychology, color: AppColors.primaryBlue),
            title: const Text('Language Model'),
            subtitle: Text(_viewModel.currentLLMModel),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pop(context);
              _showLLMModelSelection();
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.volume_up,
              color: AppColors.primaryPurple,
            ),
            title: const Text('Text-to-Speech'),
            subtitle: Text(_viewModel.currentTTSModel),
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
            value: _viewModel.currentLLMModel,
            color: AppColors.primaryBlue,
          ),
          _ModelBadge(
            icon: Icons.graphic_eq,
            label: 'STT',
            value: _viewModel.currentSTTModel,
            color: AppColors.statusGreen,
          ),
          _ModelBadge(
            icon: Icons.volume_up,
            label: 'TTS',
            value: _viewModel.currentTTSModel,
            color: AppColors.primaryPurple,
          ),
        ],
      ),
    );
  }

  Widget _buildConversationArea() {
    if (_viewModel.conversation.isEmpty &&
        _viewModel.currentTranscript.isEmpty &&
        _viewModel.assistantResponse.isEmpty) {
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
              style: AppTypography.subheadline(
                context,
              ).copyWith(color: AppColors.textSecondary(context)),
            ),
          ],
        ),
      );
    }

    _scrollToBottom();

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.large),
      children: [
        // Past conversation turns
        ..._viewModel.conversation.map(_buildConversationBubble),

        // Current transcription (in progress)
        if (_viewModel.currentTranscript.isNotEmpty)
          _buildConversationBubble(
            ConversationTurn(
              role: proto.MessageRole.MESSAGE_ROLE_USER,
              text: _viewModel.currentTranscript,
            ),
          ),

        // Current assistant response (in progress)
        if (_viewModel.assistantResponse.isNotEmpty)
          _buildConversationBubble(
            ConversationTurn(
              role: proto.MessageRole.MESSAGE_ROLE_ASSISTANT,
              text: _viewModel.assistantResponse,
            ),
          ),
      ],
    );
  }

  Widget _buildConversationBubble(ConversationTurn turn) {
    final isUser = turn.role == proto.MessageRole.MESSAGE_ROLE_USER;
    const radius = AppSpacing.cornerRadiusBubble;

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.76,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.large,
          vertical: AppSpacing.mediumLarge,
        ),
        decoration: BoxDecoration(
          gradient: isUser
              ? LinearGradient(
                  colors: [
                    AppColors.userBubbleGradientStart,
                    AppColors.userBubbleGradientEnd,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isUser ? null : AppColors.assistantBubbleBg(context),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(radius),
            topRight: const Radius.circular(radius),
            bottomLeft: Radius.circular(isUser ? radius : 4),
            bottomRight: Radius.circular(isUser ? 4 : radius),
          ),
        ),
        child: Text(
          turn.text,
          style: AppTypography.body(context).copyWith(
            color: isUser ? Colors.white : AppColors.textPrimary(context),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mediumLarge),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [bubble],
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
                final isActive = _viewModel.audioLevel > threshold;
                return Container(
                  width: 4,
                  height: 24 * (isActive ? _viewModel.audioLevel : 0.2),
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
              _viewModel.errorMessage!,
              style: AppTypography.subheadline(context),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _viewModel.clearError,
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
                  scale:
                      _viewModel.isListening ? _pulseAnimation.value : 1.0,
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
                            blurRadius: _viewModel.isListening ? 20 : 10,
                            spreadRadius: _viewModel.isListening ? 5 : 0,
                          ),
                        ],
                      ),
                      child: _viewModel.isProcessing
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
    switch (_viewModel.sessionState) {
      case UiVoiceSessionState.disconnected:
        return AppColors.statusGray;
      case UiVoiceSessionState.connecting:
        return AppColors.statusBlue;
      case UiVoiceSessionState.connected:
      case UiVoiceSessionState.listening:
        return AppColors.statusGreen;
      case UiVoiceSessionState.processing:
        return AppColors.statusBlue;
      case UiVoiceSessionState.speaking:
        return AppColors.primaryPurple;
      case UiVoiceSessionState.error:
        return AppColors.statusRed;
    }
  }

  Color _getMicButtonColor() {
    if (_viewModel.isActive) {
      return AppColors.primaryRed;
    }
    return AppColors.primaryBlue;
  }

  IconData _getMicButtonIcon() {
    switch (_viewModel.sessionState) {
      case UiVoiceSessionState.disconnected:
      case UiVoiceSessionState.error:
        return Icons.mic;
      case UiVoiceSessionState.connected:
      case UiVoiceSessionState.listening:
        return Icons.stop;
      case UiVoiceSessionState.speaking:
        return Icons.volume_up;
      default:
        return Icons.mic;
    }
  }

  String _getInstructionText() {
    switch (_viewModel.sessionState) {
      case UiVoiceSessionState.disconnected:
        return 'Tap to start voice conversation';
      case UiVoiceSessionState.connecting:
        return 'Connecting...';
      case UiVoiceSessionState.connected:
      case UiVoiceSessionState.listening:
        return _viewModel.isSpeechDetected ? 'Listening...' : 'Speak now';
      case UiVoiceSessionState.processing:
        return 'Processing...';
      case UiVoiceSessionState.speaking:
        return 'Assistant is speaking';
      case UiVoiceSessionState.error:
        return 'Tap to retry';
    }
  }
}

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
                style: AppTypography.caption2(
                  context,
                ).copyWith(fontWeight: FontWeight.w500, fontSize: 10),
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
