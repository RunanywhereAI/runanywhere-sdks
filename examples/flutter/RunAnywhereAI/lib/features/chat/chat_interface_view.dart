import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:runanywhere/public/types/tool_calling_types.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/core/models/app_types.dart';
import 'package:runanywhere_ai/core/services/conversation_store.dart';
import 'package:runanywhere_ai/core/utilities/constants.dart';
import 'package:runanywhere_ai/features/chat/tool_call_views.dart';
import 'package:runanywhere_ai/features/models/model_selection_sheet.dart';
import 'package:runanywhere_ai/features/models/model_status_components.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';
import 'package:runanywhere_ai/features/rag/rag_demo_view.dart';
import 'package:runanywhere_ai/features/settings/tool_settings_view_model.dart';
import 'package:runanywhere_ai/features/structured_output/structured_output_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ChatInterfaceView (mirroring iOS ChatInterfaceView.swift)
///
/// Full chat interface with streaming, analytics, and model status.
class ChatInterfaceView extends StatefulWidget {
  const ChatInterfaceView({super.key});

  @override
  State<ChatInterfaceView> createState() => _ChatInterfaceViewState();
}

class _ChatInterfaceViewState extends State<ChatInterfaceView> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // Messages
  final List<ChatMessage> _messages = [];
  String _currentStreamingContent = '';
  String _currentThinkingContent = '';

  // State
  bool _isGenerating = false;
  bool _useStreaming = true;
  String? _errorMessage;
  final bool _isLoading = false;

  // Model state (from SDK - matches Swift pattern)
  String? _loadedModelName;
  sdk.InferenceFramework? _loadedFramework;

  // Analytics
  DateTime? _generationStartTime;
  double? _timeToFirstToken;
  int _tokenCount = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
    unawaited(_syncModelState());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useStreaming = prefs.getBool(PreferenceKeys.useStreaming) ?? true;
    });
  }

  /// Sync model state from SDK (v4.0 API).
  Future<void> _syncModelState() async {
    final model = await sdk.RunAnywhereSDK.instance.llm.currentModel();
    if (mounted) {
      setState(() {
        _loadedModelName = model?.name;
        _loadedFramework = model?.framework;
      });
    }
  }

  bool get _canSend =>
      _controller.text.isNotEmpty &&
      !_isGenerating &&
      sdk.RunAnywhereSDK.instance.llm.isLoaded;

  Future<void> _sendMessage() async {
    if (!_canSend) return;

    final userMessage = _controller.text;
    _controller.clear();

    setState(() {
      _messages.add(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.user,
        content: userMessage,
        timestamp: DateTime.now(),
      ));
      _isGenerating = true;
      _errorMessage = null;
      _currentStreamingContent = '';
      _currentThinkingContent = '';
      _generationStartTime = DateTime.now();
      _timeToFirstToken = null;
      _tokenCount = 0;
    });

    _scrollToBottom();

    try {
      // Get generation options from settings
      final prefs = await SharedPreferences.getInstance();
      final temperature =
          prefs.getDouble(PreferenceKeys.defaultTemperature) ?? 0.7;
      final maxTokens = prefs.getInt(PreferenceKeys.defaultMaxTokens) ?? 500;
      // B-FL-4-002 / B-FL-5-001: fall back to a sane default system
      // prompt when the user hasn't customised one. Without it, smaller
      // 0.5-1B models tend to ramble or echo the prompt verbatim.
      final systemPromptRaw =
          prefs.getString(PreferenceKeys.defaultSystemPrompt) ?? '';
      const defaultSystemPrompt =
          'You are a helpful, concise assistant. Keep replies brief unless asked otherwise.';
      final systemPrompt =
          systemPromptRaw.isNotEmpty ? systemPromptRaw : defaultSystemPrompt;

      debugPrint('[PARAMS] App _sendMessage: temperature=$temperature, maxTokens=$maxTokens, systemPrompt=set(${systemPrompt.length} chars)');

      // Check if tool calling is enabled and has registered tools
      final toolSettings = ToolSettingsViewModel.shared;
      final useToolCalling = toolSettings.toolCallingEnabled &&
          toolSettings.registeredTools.isNotEmpty;

      if (useToolCalling) {
        await _generateWithToolCalling(userMessage, maxTokens, temperature);
      } else {
        // Streaming now runs in a background isolate, so no ANR concerns
        final options = sdk.LLMGenerationOptions(
          maxTokens: maxTokens,
          temperature: temperature,
          systemPrompt: systemPrompt,
        );

        if (_useStreaming) {
          await _generateStreaming(userMessage, options);
        } else {
          await _generateNonStreaming(userMessage, options);
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Generation failed: $e';
        _isGenerating = false;
      });
    }
  }

  /// Determines the optimal tool calling format based on the model name/ID.
  /// Different models are trained on different tool calling formats.
  /// Returns format name string (C++ is single source of truth for valid formats).
  String _detectToolCallFormat(String? modelName) {
    if (modelName == null) return ToolCallFormatName.defaultFormat;
    final name = modelName.toLowerCase();

    // LFM2-Tool models use Pythonic format: <|tool_call_start|>[func(args)]<|tool_call_end|>
    if (name.contains('lfm2') && name.contains('tool')) {
      return ToolCallFormatName.lfm2;
    }

    // Default JSON format for general-purpose models
    return ToolCallFormatName.defaultFormat;
  }

  Future<void> _generateWithToolCalling(
    String prompt,
    int maxTokens,
    double temperature,
  ) async {
    // Capture model name from local state (matches Swift pattern)
    final modelName = _loadedModelName;

    // Auto-detect the tool calling format based on the loaded model
    final format = _detectToolCallFormat(modelName);
    debugPrint('Using tool calling with format: $format for model: ${modelName ?? "unknown"}');

    // Add empty assistant message
    final assistantMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(assistantMessage);
    });

    final messageIndex = _messages.length - 1;

    try {
      final result = await sdk.RunAnywhereSDK.instance.tools.generateWithTools(
        prompt,
        options: ToolCallingOptions(
          maxToolCalls: 3,
          autoExecute: true,
          formatName: format,
          maxTokens: maxTokens,
          temperature: temperature,
        ),
      );

      final totalTime = _generationStartTime != null
          ? DateTime.now().difference(_generationStartTime!).inMilliseconds /
              1000.0
          : 0.0;

      // Create ToolCallInfo from the result if tools were called
      ToolCallInfo? toolCallInfo;
      debugPrint('📊 Tool calling result: toolCalls=${result.toolCalls.length}, toolResults=${result.toolResults.length}');
      if (result.toolCalls.isNotEmpty) {
        final lastCall = result.toolCalls.last;
        final lastResult = result.toolResults.isNotEmpty
            ? result.toolResults.last
            : null;
        debugPrint('📊 Creating ToolCallInfo for: ${lastCall.toolName}');

        toolCallInfo = ToolCallInfo(
          toolName: lastCall.toolName,
          arguments: _formatToolValueMapToJson(lastCall.arguments),
          result: lastResult?.result != null
              ? _formatToolValueMapToJson(lastResult!.result!)
              : null,
          success: lastResult?.success ?? false,
          error: lastResult?.error,
        );
        debugPrint('📊 ToolCallInfo created: ${toolCallInfo.toolName}, success=${toolCallInfo.success}');
      } else {
        debugPrint('📊 No tool calls in result - badge will NOT show');
      }

      final analytics = MessageAnalytics(
        messageId: assistantMessage.id,
        modelName: modelName,
        totalGenerationTime: totalTime,
      );

      if (!mounted) return;
      setState(() {
        _messages[messageIndex] = _messages[messageIndex].copyWith(
          content: result.text,
          analytics: analytics,
          toolCallInfo: toolCallInfo,
        );
        _isGenerating = false;
      });

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.removeLast();
        _errorMessage = 'Tool calling failed: $e';
        _isGenerating = false;
      });
    }
  }

  String _formatToolValueMapToJson(Map<String, ToolValue> map) {
    try {
      final jsonMap = <String, dynamic>{};
      for (final entry in map.entries) {
        jsonMap[entry.key] = _toolValueToJson(entry.value);
      }
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(jsonMap);
    } catch (e) {
      return map.toString();
    }
  }

  dynamic _toolValueToJson(ToolValue value) {
    if (value is StringToolValue) return value.value;
    if (value is NumberToolValue) return value.value;
    if (value is BoolToolValue) return value.value;
    if (value is NullToolValue) return null;
    if (value is ArrayToolValue) {
      return value.value.map(_toolValueToJson).toList();
    }
    if (value is ObjectToolValue) {
      final result = <String, dynamic>{};
      for (final entry in value.value.entries) {
        result[entry.key] = _toolValueToJson(entry.value);
      }
      return result;
    }
    return value.toString();
  }

  Future<void> _generateStreaming(
    String prompt,
    sdk.LLMGenerationOptions options,
  ) async {
    // Capture model name from local state (matches Swift pattern)
    final modelName = _loadedModelName;

    // Add empty assistant message for streaming
    final assistantMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(assistantMessage);
    });

    final messageIndex = _messages.length - 1;
    final contentBuffer = StringBuffer();

    try {
      // v2 close-out Phase G-2: generateStream returns Stream<LLMStreamEvent>;
      // collect token text off each non-terminal event.
      final eventStream = sdk.RunAnywhereSDK.instance.llm
          .generateStream(prompt, options);

      await for (final event in eventStream) {
        if (event.isFinal) {
          if (event.errorMessage.isNotEmpty) {
            throw Exception(event.errorMessage);
          }
          break;
        }
        final token = event.token;
        if (token.isEmpty) continue;

        if (_timeToFirstToken == null && _generationStartTime != null) {
          _timeToFirstToken =
              DateTime.now().difference(_generationStartTime!).inMilliseconds /
                  1000.0;
        }

        _tokenCount++;
        contentBuffer.write(token);
        _currentStreamingContent = contentBuffer.toString();

        setState(() {
          _messages[messageIndex] = _messages[messageIndex].copyWith(
            content: _currentStreamingContent,
          );
        });

        _scrollToBottom();
      }

      // Calculate final analytics
      final totalTime = _generationStartTime != null
          ? DateTime.now().difference(_generationStartTime!).inMilliseconds /
              1000.0
          : 0.0;

      final analytics = MessageAnalytics(
        messageId: assistantMessage.id,
        modelName: modelName,
        timeToFirstToken: _timeToFirstToken,
        totalGenerationTime: totalTime,
        outputTokens: _tokenCount,
        tokensPerSecond: totalTime > 0 ? _tokenCount / totalTime : 0,
      );

      if (!mounted) return;
      setState(() {
        _messages[messageIndex] = _messages[messageIndex].copyWith(
          thinkingContent: _currentThinkingContent.isNotEmpty
              ? _currentThinkingContent
              : null,
          analytics: analytics,
        );
        _isGenerating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.removeLast();
        _errorMessage = 'Streaming failed: $e';
        _isGenerating = false;
      });
    }
  }

  Future<void> _generateNonStreaming(
    String prompt,
    sdk.LLMGenerationOptions options,
  ) async {
    // Capture model name from local state (matches Swift pattern)
    final modelName = _loadedModelName;

    try {
      final result = await sdk.RunAnywhereSDK.instance.llm
          .generate(prompt, options);

      final totalTime = _generationStartTime != null
          ? DateTime.now().difference(_generationStartTime!).inMilliseconds /
              1000.0
          : 0.0;

      // Extract token counts from SDK result
      final outputTokens = result.tokensGenerated;
      final tokensPerSecond = result.tokensPerSecond;

      final analytics = MessageAnalytics(
        messageId: DateTime.now().millisecondsSinceEpoch.toString(),
        modelName: modelName,
        totalGenerationTime: totalTime,
        outputTokens: outputTokens,
        tokensPerSecond: tokensPerSecond,
      );

      setState(() {
        _messages.add(ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          role: MessageRole.assistant,
          content: result.text,
          thinkingContent: result.thinkingContent,
          timestamp: DateTime.now(),
          analytics: analytics,
        ));
        _isGenerating = false;
      });

      _scrollToBottom();
    } catch (e) {
      setState(() {
        _errorMessage = 'Generation failed: $e';
        _isGenerating = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        unawaited(_scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: AppLayout.animationFast,
          curve: Curves.easeOut,
        ));
      }
    });
  }

  void _clearChat() {
    setState(() {
      _messages.clear();
      _errorMessage = null;
      _currentStreamingContent = '';
      _currentThinkingContent = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
      actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _showConversationHistory,
            tooltip: 'Conversation history',
          ),
          IconButton(
            icon: const Icon(Icons.article_outlined),
            onPressed: () {
              unawaited(
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (context) => const RagDemoView(),
                  ),
                ),
              );
            },
            tooltip: 'Document Q&A',
          ),
          IconButton(
            icon: const Icon(Icons.data_object),
            onPressed: () {
              unawaited(
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (context) => const StructuredOutputView(),
                  ),
                ),
              );
            },
            tooltip: 'Structured Output Examples',
          ),
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearChat,
              tooltip: 'Clear chat',
            ),
        ],
      ),
      body: Column(
        children: [
          // Model status banner (uses local state from SDK)
          _buildModelStatusBanner(),

          // Messages area - tap to dismiss keyboard
          Expanded(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.opaque,
              child: _buildMessagesArea(),
            ),
          ),

          // Error banner
          if (_errorMessage != null) _buildErrorBanner(),

          // Typing indicator
          if (_isGenerating) _buildTypingIndicator(),

          // Input area
          _buildInputArea(),
        ],
      ),
    );
  }

  void _showModelSelectionSheet() {
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => ModelSelectionSheet(
        context: ModelSelectionContext.llm,
        onModelSelected: (model) async {
          // Model loaded by ModelSelectionSheet via SDK
          // Sync local state after model load
          await _syncModelState();
        },
      ),
    ));
  }

  /// Show conversation history bottom sheet driven by ConversationStore.
  void _showConversationHistory() {
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _ConversationListSheet(
        store: ConversationStore.shared,
        onNewChat: () {
          Navigator.of(sheetContext).pop();
          _clearChat();
        },
      ),
    ));
  }

  /// Map SDK InferenceFramework to LLMFramework (identity — both are the same type).
  LLMFramework _mapInferenceFramework(sdk.InferenceFramework? framework) =>
      framework ?? LLMFramework.unknown;

  Widget _buildModelStatusBanner() {
    // Use local state synced from SDK (matches Swift pattern)
    LLMFramework? framework;
    if (sdk.RunAnywhereSDK.instance.llm.isLoaded && _loadedFramework != null) {
      framework = _mapInferenceFramework(_loadedFramework);
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: ModelStatusBanner(
        framework: framework,
        modelName: _loadedModelName,
        isLoading: _isLoading,
        onSelectModel: _showModelSelectionSheet,
      ),
    );
  }

  Widget _buildMessagesArea() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.psychology,
              size: AppSpacing.iconXXLarge,
              color: AppColors.textSecondary(context),
            ),
            const SizedBox(height: AppSpacing.large),
            Text(
              'Start a conversation',
              style: AppTypography.title2(context),
            ),
            const SizedBox(height: AppSpacing.smallMedium),
            Text(
              'Type a message to begin',
              style: AppTypography.subheadline(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.large),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _MessageBubble(message: message);
      },
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
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() {
                _errorMessage = null;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return const TypingIndicatorView(
      statusText: 'AI is thinking...',
    );
  }

  /// Heuristic check for small models (<= ~500M params) where tool
  /// calling tends to be unreliable. Used by the tool-calling reliability
  /// banner (B-FL-6-003).
  bool _isLikelySmallModel(String? name) {
    if (name == null) return false;
    final n = name.toLowerCase();
    return n.contains('0.3b') ||
        n.contains('0.5b') ||
        n.contains('0.6b') ||
        n.contains('350m') ||
        n.contains('360m') ||
        n.contains('500m');
  }

  Widget _buildInputArea() {
    final toolSettings = ToolSettingsViewModel.shared;
    final showToolBadge = toolSettings.toolCallingEnabled &&
        toolSettings.registeredTools.isNotEmpty;
    final showSmallModelWarning = toolSettings.toolCallingEnabled &&
        _isLikelySmallModel(_loadedModelName);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.backgroundPrimary(context),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: AppSpacing.shadowLarge,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tool-calling reliability banner for small models (B-FL-6-003).
            if (showSmallModelWarning) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.smallMedium),
                margin: const EdgeInsets.only(bottom: AppSpacing.smallMedium),
                decoration: BoxDecoration(
                  color: AppColors.primaryOrange.withValues(alpha: 0.1),
                  borderRadius:
                      BorderRadius.circular(AppSpacing.cornerRadiusRegular),
                  border: Border.all(
                    color: AppColors.primaryOrange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: AppColors.primaryOrange),
                    const SizedBox(width: AppSpacing.smallMedium),
                    Expanded(
                      child: Text(
                        'For reliable tool calling, use a 1.2B+ instruct-tuned model.',
                        style: AppTypography.caption(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Tool calling badge (matches iOS)
            if (showToolBadge) ...[
              ToolCallingBadge(toolCount: toolSettings.registeredTools.length),
              const SizedBox(height: AppSpacing.smallMedium),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.cornerRadiusBubble),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.large,
                        vertical: AppSpacing.mediumLarge,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: AppSpacing.smallMedium),
                IconButton.filled(
                  onPressed: _canSend ? _sendMessage : null,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.arrow_upward),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Chat message model
class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final String? thinkingContent;
  final DateTime timestamp;
  final MessageAnalytics? analytics;
  final ToolCallInfo? toolCallInfo;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.thinkingContent,
    required this.timestamp,
    this.analytics,
    this.toolCallInfo,
  });

  ChatMessage copyWith({
    String? id,
    MessageRole? role,
    String? content,
    String? thinkingContent,
    DateTime? timestamp,
    MessageAnalytics? analytics,
    ToolCallInfo? toolCallInfo,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      thinkingContent: thinkingContent ?? this.thinkingContent,
      timestamp: timestamp ?? this.timestamp,
      analytics: analytics ?? this.analytics,
      toolCallInfo: toolCallInfo ?? this.toolCallInfo,
    );
  }
}

/// Message bubble widget
class _MessageBubble extends StatefulWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _showThinking = false;

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == MessageRole.user;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.mediumLarge),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Tool call indicator (if present, matches iOS toolCallSection)
            if (widget.message.toolCallInfo != null && !isUser) ...[
              ToolCallIndicator(
                toolCallInfo: widget.message.toolCallInfo!,
                onTap: () => _showToolCallDetails(context),
              ),
              const SizedBox(height: AppSpacing.smallMedium),
            ],

            // Thinking section (if present)
            if (widget.message.thinkingContent != null &&
                widget.message.thinkingContent!.isNotEmpty)
              _buildThinkingSection(),

            // Main message bubble. Long-press an assistant bubble to
            // open an analytics sheet (B-FL-9-001).
            GestureDetector(
              onLongPress: !isUser && widget.message.analytics != null
                  ? () => _showAnalyticsSheet(context)
                  : null,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.mediumLarge),
                decoration: BoxDecoration(
                  gradient: isUser
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.userBubbleGradientStart,
                            AppColors.userBubbleGradientEnd,
                          ],
                        )
                      : null,
                  color: isUser ? null : AppColors.backgroundGray5(context),
                  borderRadius:
                      BorderRadius.circular(AppSpacing.cornerRadiusBubble),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadowLight,
                      blurRadius: AppSpacing.shadowSmall,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: isUser
                    ? Text(
                        widget.message.content,
                        style: AppTypography.body(context).copyWith(
                          color: AppColors.textWhite,
                        ),
                      )
                    : MarkdownBody(
                        data: widget.message.content,
                        styleSheet: MarkdownStyleSheet(
                          p: AppTypography.body(context),
                          code: AppTypography.monospaced.copyWith(
                            backgroundColor: AppColors.backgroundGray6(context),
                          ),
                        ),
                      ),
              ),
            ),

            // Analytics summary (if present)
            if (widget.message.analytics != null && !isUser)
              _buildAnalyticsSummary(),
          ],
        ),
      ),
    );
  }

  void _showToolCallDetails(BuildContext context) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, scrollController) =>
              ToolCallDetailSheet(toolCallInfo: widget.message.toolCallInfo!),
        ),
      ),
    );
  }

  /// Show a bottom sheet of message analytics (B-FL-9-001).
  void _showAnalyticsSheet(BuildContext context) {
    final analytics = widget.message.analytics;
    if (analytics == null) return;
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: false,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Generation analytics', style: AppTypography.title3(context)),
            const SizedBox(height: AppSpacing.mediumLarge),
            if (analytics.modelName != null)
              _analyticsRow('Model', analytics.modelName!),
            if (analytics.timeToFirstToken != null)
              _analyticsRow('Time to first token',
                  '${analytics.timeToFirstToken!.toStringAsFixed(2)} s'),
            if (analytics.totalGenerationTime != null)
              _analyticsRow('Total time',
                  '${analytics.totalGenerationTime!.toStringAsFixed(2)} s'),
            if (analytics.outputTokens > 0)
              _analyticsRow('Output tokens', '${analytics.outputTokens}'),
            if (analytics.tokensPerSecond != null)
              _analyticsRow('Throughput',
                  '${analytics.tokensPerSecond!.toStringAsFixed(1)} tok/s'),
            if (analytics.wasThinkingMode)
              _analyticsRow('Thinking mode', 'Yes'),
          ],
        ),
      ),
    ));
  }

  Widget _analyticsRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value, style: AppTypography.body(context)),
          ],
        ),
      );

  Widget _buildThinkingSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.smallMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _showThinking = !_showThinking;
              });
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lightbulb,
                  size: AppSpacing.iconRegular,
                  color: AppColors.primaryPurple,
                ),
                const SizedBox(width: AppSpacing.xSmall),
                Text(
                  _showThinking ? 'Hide reasoning' : 'Show reasoning',
                  style: AppTypography.caption(context).copyWith(
                    color: AppColors.primaryPurple,
                  ),
                ),
                Icon(
                  _showThinking
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: AppSpacing.iconRegular,
                  color: AppColors.primaryPurple,
                ),
              ],
            ),
          ),
          if (_showThinking)
            Container(
              margin: const EdgeInsets.only(top: AppSpacing.smallMedium),
              padding: const EdgeInsets.all(AppSpacing.mediumLarge),
              decoration: BoxDecoration(
                color: AppColors.modelThinkingBg,
                borderRadius:
                    BorderRadius.circular(AppSpacing.cornerRadiusRegular),
              ),
              child: Text(
                widget.message.thinkingContent!,
                style: AppTypography.caption(context),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsSummary() {
    final analytics = widget.message.analytics!;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xSmall),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (analytics.totalGenerationTime != null)
            Text(
              '${analytics.totalGenerationTime!.toStringAsFixed(1)}s',
              style: AppTypography.caption(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          if (analytics.tokensPerSecond != null) ...[
            const SizedBox(width: AppSpacing.smallMedium),
            Text(
              '${analytics.tokensPerSecond!.toStringAsFixed(1)} tok/s',
              style: AppTypography.caption(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
          if (analytics.wasThinkingMode) ...[
            const SizedBox(width: AppSpacing.smallMedium),
            const Icon(
              Icons.lightbulb,
              size: 12,
              color: AppColors.primaryPurple,
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom sheet listing past conversations from [ConversationStore].
///
/// Provides a "New chat" FAB and per-row delete affordance. Tapping a
/// row currently just dismisses the sheet (full message restoration is
/// out of scope for this screen — ChatInterfaceView is in-memory only).
class _ConversationListSheet extends StatefulWidget {
  final ConversationStore store;
  final VoidCallback onNewChat;

  const _ConversationListSheet({
    required this.store,
    required this.onNewChat,
  });

  @override
  State<_ConversationListSheet> createState() => _ConversationListSheetState();
}

class _ConversationListSheetState extends State<_ConversationListSheet> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final conversations = widget.store.conversations;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Scaffold(
        appBar: AppBar(
          title: const Text('Conversations'),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        body: conversations.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No conversations yet.\nStart chatting to build history.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.builder(
                controller: scrollController,
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final conv = conversations[index];
                  return ListTile(
                    title: Text(
                      conv.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      conv.lastMessagePreview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete conversation',
                      onPressed: () => widget.store.deleteConversation(conv),
                    ),
                  );
                },
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: widget.onNewChat,
          icon: const Icon(Icons.add),
          label: const Text('New chat'),
        ),
      ),
    );
  }
}
