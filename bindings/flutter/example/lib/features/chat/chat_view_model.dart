import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere_ai/core/services/conversation_store.dart';
import 'package:runanywhere_ai/core/utilities/constants.dart';
import 'package:runanywhere_ai/features/chat/tool_call_views.dart';
import 'package:runanywhere_ai/features/chat/tool_calling_policy.dart';
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

  sdk.ModelInfo? _loadedModel;
  String? _loadedModelId;
  String? _loadedModelName;
  sdk.InferenceFramework? _loadedFramework;
  bool _loadedModelSupportsThinking = false;
  sdk.ThinkingTagPattern? _loadedModelThinkingPattern;
  bool _loadedModelSupportsLora = false;

  String? get loadedModelName => _loadedModelName;
  sdk.InferenceFramework? get loadedFramework => _loadedFramework;
  bool get loadedModelSupportsLora => _loadedModelSupportsLora;
  bool get isModelLoaded => _loadedModelId != null;

  // --- LoRA adapter state ---------------------------------------------------

  List<sdk.LoraAdapterCatalogEntry> _availableAdapters = [];
  List<sdk.AppliedAdapter> _loraAdapters = [];
  bool _isLoadingLoRA = false;

  List<sdk.LoraAdapterCatalogEntry> get availableAdapters =>
      List.unmodifiable(_availableAdapters);
  List<sdk.AppliedAdapter> get loraAdapters =>
      List.unmodifiable(_loraAdapters);
  bool get isLoadingLoRA => _isLoadingLoRA;

  // --- Private state --------------------------------------------------------

  Conversation? _currentConversation;
  DateTime? _generationStartTime;
  StreamSubscription<sdk.SdkEvent>? _lifecycleSubscription;
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

    // Model lifecycle flows through the SDK event stream.
    _lifecycleSubscription = sdk.RunAnywhere.events.listen((event) {
      if (event is sdk.SdkModelLoaded) {
        if (event.category != sdk.ModelCategory.MODEL_CATEGORY_LANGUAGE) return;
        if (event.id == _loadedModelId) return;
        unawaited(syncModelState());
      } else if (event is sdk.SdkModelUnloaded) {
        if (_loadedModelId == null) return;
        unawaited(syncModelState());
      }
    });

    // Reconcile against the SDK's authoritative snapshot in case a model
    // was loaded before this ViewModel subscribed.
    await syncModelState();
  }

  @override
  void dispose() {
    unawaited(_lifecycleSubscription?.cancel());
    if (_isGenerating) {
      sdk.RunAnywhere.llm.cancel();
    }
    super.dispose();
  }

  /// Sync loaded-model state from the SDK snapshot.
  Future<void> syncModelState() async {
    final state = await sdk.RunAnywhere.models.state();
    final model = state.loaded[sdk.ModelCategory.MODEL_CATEGORY_LANGUAGE];
    _loadedModel = model;
    _loadedModelId = model?.id;
    _loadedModelName = model?.name;
    _loadedFramework = model?.framework;
    _loadedModelSupportsThinking = model?.supportsThinking ?? false;
    _loadedModelThinkingPattern = (model != null && model.hasThinkingPattern())
        ? model.thinkingPattern
        : null;
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
      text.isNotEmpty && !_isGenerating && _loadedModelId != null;

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

      debugPrint(
        '[PARAMS] App sendMessage: temperature=$temperature, maxOutputTokens=$maxTokens, systemPrompt=set(${systemPrompt.length} chars)',
      );

      final toolSettings = ToolSettingsViewModel.shared;
      final registeredTools = toolSettings.toolCallingEnabled
          ? sdk.RunAnywhere.llm.tools.list()
          : const <sdk.ToolDefinition>[];

      final options = sdk.LlmOptions(
        maxOutputTokens: maxTokens,
        temperature: temperature,
        systemPrompt: systemPrompt.isEmpty ? null : systemPrompt,
        reasoning: _reasoningOptions(thinkingModeEnabled),
        maxToolCalls: 3,
      );

      final preflight = ToolCallingModelPolicy.preflight(
        toolsRequested: toolSettings.toolCallingEnabled,
        registeredToolCount: registeredTools.length,
        model: _loadedModel,
      );
      switch (preflight.route) {
        case ToolCallingRoute.toolGeneration:
          await _generateWithToolCalling(userMessage, options, registeredTools);
        case ToolCallingRoute.blocked:
          _errorMessage = preflight.availability.message ??
              'Web & tools are unavailable for the current model.';
          notifyListeners();
          if (_useStreaming) {
            await _generateStreaming(userMessage, options);
          } else {
            await _generateNonStreaming(userMessage, options);
          }
        case ToolCallingRoute.standardGeneration:
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
    sdk.RunAnywhere.llm.cancel();
    _isGenerating = false;
    notifyListeners();
  }

  /// Clear the chat and start a fresh conversation (persisted on first
  /// message, iOS parity).
  void clearChat() {
    if (_isGenerating) {
      sdk.RunAnywhere.llm.cancel();
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
      sdk.RunAnywhere.llm.cancel();
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

  /// Only thinking-capable models get a reasoning config — the runtime's
  /// no-think prefill leaks as literal text on non-thinking models. Thought
  /// tokens only emit when includeInOutput is set, so the "show thinking"
  /// toggle maps to it (Android/iOS example parity).
  sdk.ReasoningOptions? _reasoningOptions(bool thinkingModeEnabled) {
    if (!_loadedModelSupportsThinking) return null;
    if (!thinkingModeEnabled) {
      return const sdk.ReasoningOptions(
        mode: sdk.ReasoningMode.REASONING_MODE_OFF,
      );
    }
    return sdk.ReasoningOptions(
      includeInOutput: true,
      pattern: _loadedModelThinkingPattern?.openTag,
    );
  }

  Future<void> _generateWithToolCalling(
    String prompt,
    sdk.LlmOptions options,
    List<sdk.ToolDefinition> registeredTools,
  ) async {
    final modelName = _loadedModelName;
    final assistantMessage = _appendEmptyAssistantMessage();
    final messageIndex = _messages.length - 1;
    _messages[messageIndex] = _messages[messageIndex].copyWith(
      content: ToolCallingExecutionPolicy.progressMessage,
    );
    notifyListeners();

    final plan = ToolCallingExecutionPolicy.plan(
      options.toProto(),
      registeredTools,
    );

    try {
      final result = await sdk.RunAnywhereTools.shared
          .generateWithTools(
            prompt,
            llmOptions: plan.generationOptions,
            options: plan.toolOptions,
          )
          .timeout(
            const Duration(
              milliseconds: ToolCallingExecutionPolicy.timeoutMillis,
            ),
          );

      if (result.hasErrorMessage() && result.errorMessage.isNotEmpty) {
        throw StateError(result.errorMessage);
      }

      // Create ToolCallInfo from the result if tools were called.
      ToolCallInfo? toolCallInfo;
      if (result.toolCalls.isNotEmpty) {
        final lastCall = result.toolCalls.last;
        final lastResult = result.toolResults.isNotEmpty
            ? result.toolResults.last
            : null;
        final hasError = lastResult != null && lastResult.hasError();
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
        totalGenerationTime: _elapsedGenerationSeconds(),
        outputTokens: result.usage.outputTokens,
        tokensPerSecond: result.usage.decodeTokensPerSecond,
      );

      final finalMessage = _messages[messageIndex].copyWith(
        content: result.text,
        thinkingContent:
            result.hasThinkingContent() && result.thinkingContent.isNotEmpty
            ? result.thinkingContent
            : null,
        analytics: analytics,
        toolCallInfo: toolCallInfo,
      );
      _messages[messageIndex] = finalMessage;
      _isGenerating = false;
      _persistMessage(finalMessage);
      notifyListeners();
    } on TimeoutException {
      sdk.RunAnywhereTools.shared.cancelGeneration();
      const timeoutSeconds = ToolCallingExecutionPolicy.timeoutMillis ~/ 1000;
      final finalMessage = _messages[messageIndex].copyWith(
        content:
            '${modelName ?? 'The model'} did not finish the Web & tools '
            'request within $timeoutSeconds seconds. Try a shorter request or '
            'another model.',
        thinkingContent: null,
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
    sdk.LlmOptions options,
  ) async {
    final modelName = _loadedModelName;
    final assistantMessage = _appendEmptyAssistantMessage();
    final messageIndex = _messages.length - 1;

    final answer = StringBuffer();
    final thoughts = StringBuffer();
    try {
      sdk.GenerationResult? result;
      await for (final event in sdk.RunAnywhere.llm.generateStream(
        prompt,
        options: options,
      )) {
        switch (event) {
          case sdk.GenerationTextDelta(:final text):
            answer.write(text);
            _messages[messageIndex] = _messages[messageIndex].copyWith(
              content: answer.toString(),
              thinkingContent: thoughts.isEmpty ? null : thoughts.toString(),
            );
            notifyListeners();
          case sdk.GenerationReasoningDelta(:final text):
            thoughts.write(text);
            _messages[messageIndex] = _messages[messageIndex].copyWith(
              content: answer.toString(),
              thinkingContent: thoughts.isEmpty ? null : thoughts.toString(),
            );
            notifyListeners();
          case sdk.GenerationCompleted(result: final completed):
            result = completed;
          case sdk.GenerationFailed(error: final error):
            throw error;
          case sdk.GenerationStarted():
          case sdk.GenerationToolCallAdded():
          case sdk.GenerationUsage():
          case sdk.GenerationCancelled():
          // Deprecated v3 shapes — no longer emitted by generateStream.
          // ignore: deprecated_member_use
          case sdk.GenerationToken():
          // ignore: deprecated_member_use
          case sdk.GenerationToolCall():
            break;
        }
      }

      final analytics = MessageAnalytics(
        messageId: assistantMessage.id,
        modelName: modelName,
        timeToFirstToken: result != null && result.timeToFirstTokenMs > 0
            ? result.timeToFirstTokenMs / 1000.0
            : null,
        totalGenerationTime: _elapsedGenerationSeconds(),
        outputTokens: result?.outputTokens ?? 0,
        tokensPerSecond: result?.tokensPerSecond ?? 0,
        wasThinkingMode: thoughts.isNotEmpty,
      );

      final thinking = result?.thinkingText ??
          (thoughts.isEmpty ? null : thoughts.toString());
      final finalMessage = _messages[messageIndex].copyWith(
        content: result?.text ?? answer.toString(),
        thinkingContent: thinking,
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
    sdk.LlmOptions options,
  ) async {
    final modelName = _loadedModelName;

    try {
      final result = await sdk.RunAnywhere.llm.generate(prompt, options: options);

      final analytics = MessageAnalytics(
        messageId: DateTime.now().millisecondsSinceEpoch.toString(),
        modelName: modelName,
        timeToFirstToken: result.timeToFirstTokenMs > 0
            ? result.timeToFirstTokenMs / 1000.0
            : null,
        totalGenerationTime: _elapsedGenerationSeconds(),
        outputTokens: result.outputTokens,
        tokensPerSecond: result.tokensPerSecond,
        wasThinkingMode: result.thinkingText != null,
      );

      final assistantMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: sdk.MessageRole.MESSAGE_ROLE_ASSISTANT,
        content: result.text,
        thinkingContent: result.thinkingText,
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
      _availableAdapters = await sdk.RunAnywhere.lora.catalog(
        modelId: modelId,
      );
    } catch (e) {
      debugPrint('Failed to refresh LoRA catalog: $e');
      _availableAdapters = [];
    }
    notifyListeners();
  }

  /// Refresh the currently applied adapters from the SDK.
  Future<void> refreshAppliedAdapters() async {
    try {
      _loraAdapters = (await sdk.RunAnywhere.lora.list()).applied;
    } catch (e) {
      debugPrint('Failed to refresh applied LoRA adapters: $e');
    }
    notifyListeners();
  }

  String? localPathFor(sdk.LoraAdapterCatalogEntry adapter) {
    // `isDownloaded` was deleted; `localPath` non-empty is now the proto's
    // own documented sole authority for "is this downloaded".
    if (adapter.localPath.isEmpty) return null;
    return File(adapter.localPath).existsSync() ? adapter.localPath : null;
  }

  /// Stable model-registry id for a LoRA adapter's downloadable artifact.
  /// `LoraAdapterCatalogEntry` no longer carries url/filename/size
  /// (idl/lora_options.proto), so its bytes are described by a companion
  /// [sdk.ModelInfo] artifact keyed by this id — the same
  /// `lora-adapter:{id}` convention [ModelCatalogBootstrap] used to register
  /// it, and that the iOS/Web SDK reference LoRA extensions use internally.
  String _loraArtifactModelId(String adapterId) => 'lora-adapter:$adapterId';

  bool isAdapterDownloaded(sdk.LoraAdapterCatalogEntry adapter) =>
      localPathFor(adapter) != null;

  bool isAdapterApplied(sdk.LoraAdapterCatalogEntry adapter) =>
      _loraAdapters.any(
        (a) =>
            a.id == adapter.id ||
            (adapter.localPath.isNotEmpty && a.id == adapter.localPath),
      );

  /// Download (if needed) and apply a catalog adapter. One SDK call owns
  /// transfer, placement, and catalog completion; the caller only supplies
  /// the companion [sdk.ModelInfo] artifact describing where to fetch the
  /// adapter bytes — [ModelCatalogBootstrap] already registered that artifact
  /// under `lora-adapter:{id}` when it seeded the catalog, so the lookup
  /// below just reads it back from the registry.
  Future<void> downloadAndApplyAdapter(
    sdk.LoraAdapterCatalogEntry adapter,
  ) async {
    _isLoadingLoRA = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (localPathFor(adapter) == null) {
        final artifact = await sdk.RunAnywhere.models.get(
          _loraArtifactModelId(adapter.id),
        );
        if (artifact == null) {
          throw sdk.SDKException.modelNotFound(adapter.id);
        }
        await sdk.RunAnywhere.lora.download(adapter, artifact);
      }
      await sdk.RunAnywhere.lora.apply(adapter.id);
      _loraAdapters = (await sdk.RunAnywhere.lora.list()).applied;
      await refreshAvailableAdapters();
    } catch (e) {
      _errorMessage = 'LoRA adapter failed: $e';
    }
    _isLoadingLoRA = false;
    notifyListeners();
  }

  /// Remove one applied adapter.
  Future<void> removeAdapter(String adapterId) async {
    try {
      await sdk.RunAnywhere.lora.remove(adapterId);
      _loraAdapters = (await sdk.RunAnywhere.lora.list()).applied;
    } catch (e) {
      _errorMessage = 'Failed to remove LoRA adapter: $e';
    }
    notifyListeners();
  }

  /// Remove all applied adapters.
  Future<void> clearAdapters() async {
    try {
      await sdk.RunAnywhere.lora.remove();
      _loraAdapters = (await sdk.RunAnywhere.lora.list()).applied;
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
