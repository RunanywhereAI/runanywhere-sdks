import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere/runanywhere.dart'
    show ToolCallingOptions, ToolCallFormatName;
import 'package:runanywhere_ai/core/services/conversation_store.dart';
import 'package:runanywhere_ai/core/utilities/constants.dart';
import 'package:runanywhere_ai/features/chat/tool_call_views.dart';
import 'package:runanywhere_ai/features/settings/tool_settings_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chat message UI model. Persisted through [ConversationStore] as [Message].
class ChatMessage {
  final String id;
  final sdk.MessageRole role;
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
    sdk.MessageRole? role,
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

  /// Convert to the [ConversationStore] persistence model. Tool-call
  /// details are transient UI state and are not persisted (iOS parity).
  Message toStoreMessage() => Message(
    id: id,
    role: role,
    content: content,
    thinkingContent: thinkingContent,
    timestamp: timestamp,
    analytics: analytics,
  );

  factory ChatMessage.fromStoreMessage(Message message) => ChatMessage(
    id: message.id,
    role: message.role,
    content: message.content,
    thinkingContent: message.thinkingContent,
    timestamp: message.timestamp,
    analytics: message.analytics,
  );
}

/// ChatViewModel (mirroring iOS `LLMViewModel`).
///
/// Owns all chat state and SDK interaction: message list, generation
/// (streaming, non-streaming, tool calling), model lifecycle sync,
/// conversation persistence, and LoRA adapter management. The view is a
/// pure [ListenableBuilder] consumer.
class ChatViewModel extends ChangeNotifier {
  ChatViewModel({ConversationStore? store})
    : _store = store ?? ConversationStore.shared;

  final ConversationStore _store;

  // --- Message state -------------------------------------------------------

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  bool _isGenerating = false;
  bool get isGenerating => _isGenerating;

  bool _useStreaming = true;
  bool get useStreaming => _useStreaming;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // --- Model state synced from the SDK -------------------------------------

  String? _loadedModelId;
  String? _loadedModelName;
  sdk.InferenceFramework? _loadedFramework;
  bool _loadedModelSupportsThinking = false;
  bool _loadedModelSupportsLora = false;

  String? get loadedModelName => _loadedModelName;
  sdk.InferenceFramework? get loadedFramework => _loadedFramework;
  bool get loadedModelSupportsLora => _loadedModelSupportsLora;
  bool get isModelLoaded => sdk.RunAnywhere.llm.isLoaded;

  // --- LoRA adapter state ---------------------------------------------------

  List<sdk.LoraAdapterCatalogEntry> _availableAdapters = [];
  List<sdk.LoRAAdapterInfo> _loraAdapters = [];
  bool _isLoadingLoRA = false;

  List<sdk.LoraAdapterCatalogEntry> get availableAdapters =>
      List.unmodifiable(_availableAdapters);
  List<sdk.LoRAAdapterInfo> get loraAdapters =>
      List.unmodifiable(_loraAdapters);
  bool get isLoadingLoRA => _isLoadingLoRA;

  // --- Private state --------------------------------------------------------

  Conversation? _currentConversation;
  DateTime? _generationStartTime;
  double? _timeToFirstToken;
  StreamSubscription<sdk.ModelLifecycleChange>? _lifecycleSubscription;
  bool _initialized = false;

  // --- Lifecycle ------------------------------------------------------------

  /// Subscribe to SDK model-lifecycle events and apply stored settings.
  /// Idempotent — safe to call from the view's `initState`.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    _useStreaming = prefs.getBool(PreferenceKeys.useStreaming) ?? true;
    notifyListeners();

    // Model lifecycle flows through the SDK event bus (iOS parity:
    // LLMViewModel.subscribeToModelLifecycle).
    _lifecycleSubscription = sdk.RunAnywhere.events.modelLifecycle.listen((
      change,
    ) {
      // iOS parity (LLMViewModel.handleModelLifecycle): only react to LLM
      // component changes and ignore lifecycle events for other modalities.
      if (change.component != sdk.SDKComponent.SDK_COMPONENT_LLM &&
          change.event.category != sdk.EventCategory.EVENT_CATEGORY_LLM) {
        return;
      }
      // Re-sync only on an actual transition; duplicate loaded/unloaded
      // events carry no new snapshot state.
      final loaded = change.kind == sdk.ModelLifecycleChangeKind.loaded;
      if (loaded && change.modelId == _loadedModelId) return;
      if (!loaded && _loadedModelId == null) return;
      unawaited(syncModelState());
    });

    // Reconcile against the SDK's authoritative snapshot in case a model
    // was loaded before this ViewModel subscribed.
    await syncModelState();
  }

  @override
  void dispose() {
    unawaited(_lifecycleSubscription?.cancel());
    if (_isGenerating) {
      sdk.RunAnywhere.llm.cancelGeneration();
    }
    super.dispose();
  }

  /// Sync loaded-model state from the SDK snapshot.
  Future<void> syncModelState() async {
    final model = await sdk.RunAnywhere.llm.currentModel();
    _loadedModelId = model?.id;
    _loadedModelName = model?.name;
    _loadedFramework = model?.framework;
    _loadedModelSupportsThinking = model?.supportsThinking ?? false;
    _loadedModelSupportsLora = model?.supportsLora ?? false;
    notifyListeners();

    if (_loadedModelSupportsLora) {
      await refreshAvailableAdapters();
      await refreshAppliedAdapters();
    } else if (_availableAdapters.isNotEmpty || _loraAdapters.isNotEmpty) {
      _availableAdapters = [];
      _loraAdapters = [];
      notifyListeners();
    }
  }

  // --- Sending --------------------------------------------------------------

  bool canSend(String text) =>
      text.isNotEmpty && !_isGenerating && sdk.RunAnywhere.llm.isLoaded;

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> sendMessage(String userMessage) async {
    if (!canSend(userMessage)) return;

    // Create the conversation lazily on the first message (iOS parity).
    _currentConversation ??= _store.createConversation();

    final userChatMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: sdk.MessageRole.MESSAGE_ROLE_USER,
      content: userMessage,
      timestamp: DateTime.now(),
    );
    _messages.add(userChatMessage);
    _persistMessage(userChatMessage);

    _isGenerating = true;
    _errorMessage = null;
    _generationStartTime = DateTime.now();
    _timeToFirstToken = null;
    notifyListeners();

    try {
      // Generation options from settings (same keys as the settings view).
      final prefs = await SharedPreferences.getInstance();
      final temperature =
          prefs.getDouble(PreferenceKeys.defaultTemperature) ?? 0.7;
      final maxTokens = prefs.getInt(PreferenceKeys.defaultMaxTokens) ?? 1000;
      final systemPrompt =
          prefs.getString(PreferenceKeys.defaultSystemPrompt) ?? '';
      final thinkingModeEnabled =
          prefs.getBool(PreferenceKeys.thinkingModeEnabled) ?? true;
      final disableThinking =
          _loadedModelSupportsThinking && !thinkingModeEnabled;

      debugPrint(
        '[PARAMS] App sendMessage: temperature=$temperature, maxTokens=$maxTokens, systemPrompt=set(${systemPrompt.length} chars)',
      );

      final toolSettings = ToolSettingsViewModel.shared;
      final useToolCalling =
          toolSettings.toolCallingEnabled &&
          toolSettings.registeredTools.isNotEmpty;

      if (useToolCalling) {
        await _generateWithToolCalling(
          userMessage,
          maxTokens,
          temperature,
          systemPrompt,
          disableThinking,
        );
      } else {
        final options = sdk.LLMGenerationOptions(
          maxTokens: maxTokens,
          temperature: temperature,
          systemPrompt: systemPrompt,
          disableThinking: disableThinking,
        );

        if (_useStreaming) {
          await _generateStreaming(userMessage, options);
        } else {
          await _generateNonStreaming(userMessage, options);
        }
      }
    } catch (e) {
      _errorMessage = 'Generation failed: $e';
      _isGenerating = false;
      notifyListeners();
    }
  }

  /// Stop the in-flight generation (mirrors iOS `stopGeneration`).
  void stopGeneration() {
    sdk.RunAnywhere.llm.cancelGeneration();
    _isGenerating = false;
    notifyListeners();
  }

  /// Clear the chat and start a fresh conversation (persisted on first
  /// message, iOS parity).
  void clearChat() {
    if (_isGenerating) {
      sdk.RunAnywhere.llm.cancelGeneration();
    }
    _messages.clear();
    _errorMessage = null;
    _isGenerating = false;
    _currentConversation = _store.createConversation();
    notifyListeners();
  }

  /// Restore a persisted conversation into the chat.
  void loadConversation(Conversation conversation) {
    if (_isGenerating) {
      sdk.RunAnywhere.llm.cancelGeneration();
      _isGenerating = false;
    }
    _currentConversation = conversation;
    _messages
      ..clear()
      ..addAll(conversation.messages.map(ChatMessage.fromStoreMessage));
    _errorMessage = null;
    notifyListeners();
  }

  // --- Generation paths -----------------------------------------------------

  /// Determines the optimal tool calling format based on the model name/ID.
  /// Different models are trained on different tool calling formats.
  ToolCallFormatName _detectToolCallFormat(String? modelName) {
    if (modelName == null) {
      return ToolCallFormatName.TOOL_CALL_FORMAT_NAME_JSON;
    }
    final name = modelName.toLowerCase();

    // LFM2-Tool models use the LFM2 function-call format:
    // <|tool_call_start|>[func(args)]<|tool_call_end|>
    if (name.contains('lfm2') && name.contains('tool')) {
      return ToolCallFormatName.TOOL_CALL_FORMAT_NAME_LFM2;
    }

    // Default JSON format for general-purpose models
    return ToolCallFormatName.TOOL_CALL_FORMAT_NAME_JSON;
  }

  Future<void> _generateWithToolCalling(
    String prompt,
    int maxTokens,
    double temperature,
    String systemPrompt,
    bool disableThinking,
  ) async {
    final modelName = _loadedModelName;
    final format = _detectToolCallFormat(modelName);
    debugPrint(
      'Using tool calling with format: ${format.name} for model: ${modelName ?? "unknown"}',
    );

    final assistantMessage = _appendEmptyAssistantMessage();
    final messageIndex = _messages.length - 1;

    try {
      final result = await sdk.RunAnywhere.tools.generateWithTools(
        prompt,
        options: ToolCallingOptions(
          maxToolCalls: 3,
          autoExecute: true,
          format: format,
          maxTokens: maxTokens,
          temperature: temperature,
          systemPrompt: systemPrompt,
          disableThinking: disableThinking,
        ),
      );

      final totalTime = _elapsedGenerationSeconds();

      // Create ToolCallInfo from the result if tools were called
      ToolCallInfo? toolCallInfo;
      if (result.toolCalls.isNotEmpty) {
        final lastCall = result.toolCalls.last;
        final lastResult = result.toolResults.isNotEmpty
            ? result.toolResults.last
            : null;
        final hasError = lastResult != null && lastResult.error.isNotEmpty;
        toolCallInfo = ToolCallInfo(
          toolName: lastCall.name,
          arguments: lastCall.argumentsJson,
          result: (lastResult != null && lastResult.resultJson.isNotEmpty)
              ? lastResult.resultJson
              : null,
          success: lastResult != null && !hasError,
          error: hasError ? lastResult.error : null,
        );
      }

      final analytics = MessageAnalytics(
        messageId: assistantMessage.id,
        modelName: modelName,
        totalGenerationTime: totalTime,
      );

      final finalMessage = _messages[messageIndex].copyWith(
        content: result.text,
        thinkingContent: result.thinkingContent,
        analytics: analytics,
        toolCallInfo: toolCallInfo,
      );
      _messages[messageIndex] = finalMessage;
      _isGenerating = false;
      _persistMessage(finalMessage);
      notifyListeners();
    } catch (e) {
      _messages.removeLast();
      _errorMessage = 'Tool calling failed: $e';
      _isGenerating = false;
      notifyListeners();
    }
  }

  Future<void> _generateStreaming(
    String prompt,
    sdk.LLMGenerationOptions options,
  ) async {
    final modelName = _loadedModelName;
    final assistantMessage = _appendEmptyAssistantMessage();
    final messageIndex = _messages.length - 1;

    try {
      final result = await sdk.RunAnywhere.aggregateStream(
        prompt: prompt,
        events: sdk.RunAnywhere.llm.generateStream(prompt, options),
        onToken: (aggregated) async {
          if (_timeToFirstToken == null && _generationStartTime != null) {
            _timeToFirstToken =
                DateTime.now()
                    .difference(_generationStartTime!)
                    .inMilliseconds /
                1000.0;
          }
          _messages[messageIndex] = _messages[messageIndex].copyWith(
            content: aggregated,
          );
          notifyListeners();
        },
      );

      if (result.errorMessage.isNotEmpty) {
        throw Exception(result.errorMessage);
      }

      final analytics = MessageAnalytics(
        messageId: assistantMessage.id,
        modelName: modelName,
        timeToFirstToken: _timeToFirstToken,
        totalGenerationTime: _elapsedGenerationSeconds(),
        outputTokens: result.tokensGenerated,
        tokensPerSecond: result.tokensPerSecond,
        wasThinkingMode: result.thinkingContent.isNotEmpty,
      );

      final finalMessage = _messages[messageIndex].copyWith(
        content: result.text,
        thinkingContent: result.thinkingContent.isNotEmpty
            ? result.thinkingContent
            : null,
        analytics: analytics,
      );
      _messages[messageIndex] = finalMessage;
      _isGenerating = false;
      _persistMessage(finalMessage);
      notifyListeners();
    } catch (e) {
      _messages.removeLast();
      _errorMessage = 'Streaming failed: $e';
      _isGenerating = false;
      notifyListeners();
    }
  }

  Future<void> _generateNonStreaming(
    String prompt,
    sdk.LLMGenerationOptions options,
  ) async {
    final modelName = _loadedModelName;

    try {
      final result = await sdk.RunAnywhere.llm.generate(prompt, options);

      final analytics = MessageAnalytics(
        messageId: DateTime.now().millisecondsSinceEpoch.toString(),
        modelName: modelName,
        totalGenerationTime: _elapsedGenerationSeconds(),
        outputTokens: result.tokensGenerated,
        tokensPerSecond: result.tokensPerSecond,
        wasThinkingMode: result.thinkingContent.isNotEmpty,
      );

      final assistantMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: sdk.MessageRole.MESSAGE_ROLE_ASSISTANT,
        content: result.text,
        thinkingContent: result.thinkingContent,
        timestamp: DateTime.now(),
        analytics: analytics,
      );
      _messages.add(assistantMessage);
      _isGenerating = false;
      _persistMessage(assistantMessage);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Generation failed: $e';
      _isGenerating = false;
      notifyListeners();
    }
  }

  // --- LoRA adapter management (mirrors iOS LLMViewModel LoRA section) -------

  /// Refresh catalog adapters compatible with the loaded model.
  Future<void> refreshAvailableAdapters() async {
    final modelId = _loadedModelId;
    if (modelId == null) {
      _availableAdapters = [];
      notifyListeners();
      return;
    }
    try {
      final result = await sdk.RunAnywhere.lora.queryCatalog(
        sdk.LoraAdapterCatalogQuery(modelId: modelId),
      );
      if (!result.success) {
        throw Exception(
          result.errorMessage.isEmpty
              ? 'LoRA catalog query failed'
              : result.errorMessage,
        );
      }
      _availableAdapters = result.entries.toList();
    } catch (e) {
      debugPrint('Failed to refresh LoRA catalog: $e');
      _availableAdapters = [];
    }
    notifyListeners();
  }

  /// Refresh the currently applied adapters from the SDK.
  Future<void> refreshAppliedAdapters() async {
    try {
      final state = await sdk.RunAnywhere.lora.list();
      if (state.errorMessage.isNotEmpty) {
        throw Exception(state.errorMessage);
      }
      _loraAdapters = state.loadedAdapters.toList();
    } catch (e) {
      debugPrint('Failed to refresh applied LoRA adapters: $e');
    }
    notifyListeners();
  }

  String? localPathFor(sdk.LoraAdapterCatalogEntry adapter) {
    if (!adapter.isDownloaded || adapter.localPath.isEmpty) return null;
    return File(adapter.localPath).existsSync() ? adapter.localPath : null;
  }

  bool isAdapterDownloaded(sdk.LoraAdapterCatalogEntry adapter) =>
      localPathFor(adapter) != null;

  bool isAdapterApplied(sdk.LoraAdapterCatalogEntry adapter) =>
      _loraAdapters.any(
        (a) =>
            a.adapterId == adapter.id ||
            (adapter.localPath.isNotEmpty &&
                a.adapterPath == adapter.localPath),
      );

  /// Download (if needed) and apply a catalog adapter. One SDK call owns
  /// registration, transfer, placement, and catalog completion.
  Future<void> downloadAndApplyAdapter(
    sdk.LoraAdapterCatalogEntry adapter,
  ) async {
    _isLoadingLoRA = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final localPath =
          localPathFor(adapter) ?? await sdk.RunAnywhere.lora.download(adapter);

      final scale = adapter.hasDefaultScale() && adapter.defaultScale > 0
          ? adapter.defaultScale
          : 1.0;
      final result = await sdk.RunAnywhere.lora.applyCatalogAdapter(
        adapter,
        localPath: localPath,
        scale: scale,
      );
      if (!result.success) {
        throw Exception(
          result.errorMessage.isEmpty
              ? 'LoRA apply failed'
              : result.errorMessage,
        );
      }
      _loraAdapters = result.adapters.toList();
      await refreshAvailableAdapters();
    } catch (e) {
      _errorMessage = 'LoRA adapter failed: $e';
    }
    _isLoadingLoRA = false;
    notifyListeners();
  }

  /// Remove one applied adapter by path.
  Future<void> removeAdapter(String adapterPath) async {
    try {
      final state = await sdk.RunAnywhere.lora.remove(
        sdk.LoRARemoveRequest(adapterPaths: [adapterPath]),
      );
      if (state.errorMessage.isNotEmpty) {
        throw Exception(state.errorMessage);
      }
      _loraAdapters = state.loadedAdapters.toList();
    } catch (e) {
      _errorMessage = 'Failed to remove LoRA adapter: $e';
    }
    notifyListeners();
  }

  /// Remove all applied adapters.
  Future<void> clearAdapters() async {
    try {
      final state = await sdk.RunAnywhere.lora.remove(
        sdk.LoRARemoveRequest(clearAll: true),
      );
      if (state.errorMessage.isNotEmpty) {
        throw Exception(state.errorMessage);
      }
      _loraAdapters = state.loadedAdapters.toList();
    } catch (e) {
      _errorMessage = 'Failed to clear LoRA adapters: $e';
    }
    notifyListeners();
  }

  // --- Helpers ----------------------------------------------------------------

  ChatMessage _appendEmptyAssistantMessage() {
    final assistantMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: sdk.MessageRole.MESSAGE_ROLE_ASSISTANT,
      content: '',
      timestamp: DateTime.now(),
    );
    _messages.add(assistantMessage);
    notifyListeners();
    return assistantMessage;
  }

  double _elapsedGenerationSeconds() => _generationStartTime != null
      ? DateTime.now().difference(_generationStartTime!).inMilliseconds / 1000.0
      : 0.0;

  void _persistMessage(ChatMessage message) {
    final conversation = _currentConversation;
    if (conversation == null) return;
    _currentConversation = _store.addMessage(
      message.toStoreMessage(),
      conversation,
    );
  }
}
