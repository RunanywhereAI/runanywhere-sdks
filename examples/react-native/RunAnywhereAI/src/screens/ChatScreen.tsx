/**
 * ChatScreen - Tab 0: Language Model Chat
 *
 * Provides LLM-powered chat interface with conversation management.
 * Matches iOS ChatInterfaceView architecture and patterns.
 *
 * Features:
 * - Conversation management (create, switch, delete)
 * - Streaming LLM text generation
 * - Message analytics (tokens/sec, generation time)
 * - Model selection sheet
 * - Model status banner (shows loaded model)
 *
 * Architecture:
 * - Uses ConversationStore for state management (matches iOS)
 * - Separates UI from business logic (View + ViewModel pattern)
 * - Model loading via RunAnywhere.models.load(id)
 * - Text generation via RunAnywhere.llm.generateStream(prompt, options?)
 *   and RunAnywhere.llm.generate(prompt, options?)
 *
 * Reference: iOS examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Chat/Views/ChatInterfaceView.swift
 */

import React, { useState, useRef, useCallback, useEffect } from 'react';
import {
  View,
  Text,
  FlatList,
  StyleSheet,
  TouchableOpacity,
  Alert,
  Modal,
} from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import Icon from 'react-native-vector-icons/Ionicons';
import {
  SafeAreaView,
  useSafeAreaInsets,
} from 'react-native-safe-area-context';
import {
  typography,
  useTheme,
  useThemedStyles,
  type ColorScheme,
} from '../theme/system';
import { ModelRequiredOverlay } from '../components/common';
import { ChatHeader } from '../features/chat/components/ChatHeader';
import { PromptSuggestions } from '../features/chat/components/PromptSuggestions';
import {
  MessageBubble,
  ChatInput,
  ToolCallingBadge,
  LoRASheet,
} from '../components/chat';
import { ChatAnalyticsScreen } from './ChatAnalyticsScreen';
import { ConversationListScreen } from './ConversationListScreen';
import type { Message, Conversation } from '../types/chat';
import { MessageRole } from '../types/chat';
import { useConversationStore } from '../stores/conversationStore';
import {
  ModelSelectionSheet,
  ModelSelectionContext,
} from '../components/model';
import { APP_STORAGE_KEYS, GENERATION_SETTINGS_KEYS } from '../types/settings';
import { getPrimaryFramework, isModelDownloaded } from '../utils/modelDisplay';
import { registerDemoTools } from '../utils/chatSampleTools';

// Import RunAnywhere SDK (Multi-Package Architecture)
import {
  RunAnywhere,
  formatFramework,
  generateWithTools,
} from '@runanywhere/core';
import type {
  FinishReason,
  GenerationResult,
  LlmOptions,
  ReasoningOptions,
  ToolCallingResult,
} from '@runanywhere/core';
import { FinishReason as ProtoFinishReason } from '@runanywhere/proto-ts/finish_reason';
import { TokenUsage } from '@runanywhere/proto-ts/token_usage';
import {
  ToolCallingExecutionPolicy,
  ToolCallingModelPolicy,
  ToolCallingRoute,
} from '../features/chat/ToolCallingModelPolicy';
import {
  ModelCategory,
  type ModelInfo as SDKModelInfo,
} from '@runanywhere/proto-ts/model_types';
import { logDiagnostic } from '../utils/diagnostics';
import { isModelLoadedForCategory } from '../utils/runAnywhereLifecycle';
import { listVisibleCatalogModels } from '../services/ModelRegistryQueries';
import type { MessageAnalytics, ToolCallInfo } from '../types/chat';

/**
 * Map public GenerationResult fields that already come from commons TokenUsage.
 * Prefill / content-rate / batchBuffered / countsEstimated are not on the
 * public surface — omit them (proto defaults via fromPartial), never invent.
 */
function usageFromGenerationResult(
  result: GenerationResult | null | undefined
): TokenUsage | undefined {
  if (!result) return undefined;
  return TokenUsage.fromPartial({
    inputTokens: result.inputTokens,
    outputTokens: result.outputTokens,
    totalTokens: result.inputTokens + result.outputTokens,
    decodeTokensPerSecond: result.tokensPerSecond,
    ttftMs: result.timeToFirstTokenMs,
  });
}

/** Analytics shell from terminal commons metrics only — no wall-clock latency. */
function analyticsFromResult(
  result: GenerationResult | null | undefined,
  extras: Pick<
    MessageAnalytics,
    'completionStatus' | 'wasThinkingMode' | 'wasInterrupted' | 'retryCount'
  >
): MessageAnalytics {
  const usage = usageFromGenerationResult(result);
  return {
    performance: {
      // generationTimeMs is not on public GenerationResult — leave 0, do not
      // substitute Date.now() wall latency.
      latencyMs: 0,
      memoryBytes: 0,
      ...(usage ? { usage } : {}),
    },
    ...(result && result.timeToFirstTokenMs > 0
      ? { timeToFirstToken: result.timeToFirstTokenMs }
      : {}),
    ...extras,
  };
}

// Generate unique ID
const generateId = () => Math.random().toString(36).substring(2, 15);

interface GenerationSettings {
  temperature: number;
  maxTokens: number;
  systemPrompt?: string;
  thinkingModeEnabled: boolean;
}

// The explicit tool-calling loop reports both the call and its execution
// result, so the detail sheet can show arguments, output, and success.
function makeToolCallInfo(result: ToolCallingResult): ToolCallInfo | undefined {
  const firstCall = result.toolCalls[0];
  if (!firstCall) return undefined;
  const toolResult = result.toolResults.find((r) => r.name === firstCall.name);
  return {
    toolName: firstCall.name,
    arguments: firstCall.argumentsJson || '{}',
    ...(toolResult?.resultJson ? { result: toolResult.resultJson } : {}),
    success: toolResult ? !toolResult.isError : true,
    ...(toolResult?.error ? { error: toolResult.error } : {}),
  };
}

/** Map commons `FinishReason` onto the public union — never invent from toolCalls.length. */
function mapToolFinishReason(raw: ProtoFinishReason): FinishReason {
  switch (raw) {
    case ProtoFinishReason.FINISH_REASON_TOOL_CALLS:
      return 'toolCalls';
    case ProtoFinishReason.FINISH_REASON_LENGTH:
    case ProtoFinishReason.FINISH_REASON_CONTEXT_OVERFLOW:
      return 'length';
    case ProtoFinishReason.FINISH_REASON_CANCELLED:
      return 'cancelled';
    case ProtoFinishReason.FINISH_REASON_ERROR:
      return 'unknown';
    default:
      return 'stop';
  }
}

// Map the explicit tool-loop result onto the GenerationResult the finalizer
// already knows how to render.
function toGenerationResult(
  result: ToolCallingResult,
  model: string
): GenerationResult {
  return {
    text: result.text,
    ...(result.thinkingContent ? { thinkingText: result.thinkingContent } : {}),
    toolCalls: result.toolCalls,
    finishReason: mapToolFinishReason(result.finishReason),
    inputTokens: result.usage?.inputTokens ?? 0,
    outputTokens: result.usage?.outputTokens ?? 0,
    timeToFirstTokenMs: result.usage?.ttftMs ?? 0,
    tokensPerSecond: result.usage?.decodeTokensPerSecond ?? 0,
    requestId: '',
    model,
  };
}

export const ChatScreen: React.FC = () => {
  const { colors } = useTheme();
  const styles = useThemedStyles(createStyles);
  // Conversation store
  const {
    conversations,
    currentConversation,
    initialize: initializeStore,
    createConversation,
    setCurrentConversation,
    addMessage,
    updateMessage,
    updateConversation,
  } = useConversationStore();

  // Local state
  const [inputText, setInputText] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [isModelLoading, setIsModelLoading] = useState(false);
  const [currentModel, setCurrentModel] = useState<SDKModelInfo | null>(null);
  const [_availableModels, setAvailableModels] = useState<SDKModelInfo[]>([]);
  const [showAnalytics, setShowAnalytics] = useState(false);
  const [showConversationList, setShowConversationList] = useState(false);
  const [showModelSelection, setShowModelSelection] = useState(false);
  const [isInitialized, setIsInitialized] = useState(false);
  const [registeredToolCount, setRegisteredToolCount] = useState(0);
  const [toolsEnabled, setToolsEnabled] = useState(false);
  // LoRA adapter management (mirrors iOS LLMViewModel.loraAdapters).
  const [showLoRASheet, setShowLoRASheet] = useState(false);
  const [loraAdapterCount, setLoraAdapterCount] = useState(0);

  // Refs
  const flatListRef = useRef<FlatList>(null);
  // Cancelling a v3 stream means returning its iterator; there is no separate
  // cancelGeneration() verb.
  const generationIteratorRef = useRef<AsyncIterator<unknown> | null>(null);
  const wasStoppedRef = useRef(false);

  // Safe area insets for header status bar handling
  const insets = useSafeAreaInsets();

  // Initialize conversation store and create first conversation
  useEffect(() => {
    const init = async () => {
      await initializeStore();
      setIsInitialized(true);
    };
    init();
  }, [initializeStore]);

  // Create initial conversation if none exists
  useEffect(() => {
    if (isInitialized && conversations.length === 0 && !currentConversation) {
      createConversation();
    } else if (
      isInitialized &&
      !currentConversation &&
      conversations.length > 0
    ) {
      // Set most recent conversation as current
      setCurrentConversation(conversations[0] || null);
    }
  }, [
    isInitialized,
    conversations,
    currentConversation,
    createConversation,
    setCurrentConversation,
  ]);

  // Check for loaded model and load available models on mount
  useEffect(() => {
    checkModelStatus();
    loadAvailableModels();
    // Reflect whatever tools Settings has already registered (badge only).
    RunAnywhere.llm.tools
      .list()
      .then((tools) => setRegisteredToolCount(tools.length));
  }, []);

  // Messages from current conversation
  const messages = currentConversation?.messages || [];

  /**
   * Get generation options from AsyncStorage
   * Reads user-configured temperature, maxTokens, and systemPrompt
   */
  const getGenerationOptions = async (): Promise<GenerationSettings> => {
    const tempStr = await AsyncStorage.getItem(
      GENERATION_SETTINGS_KEYS.TEMPERATURE
    );
    const maxStr = await AsyncStorage.getItem(
      GENERATION_SETTINGS_KEYS.MAX_TOKENS
    );
    const sysStr = await AsyncStorage.getItem(
      GENERATION_SETTINGS_KEYS.SYSTEM_PROMPT
    );
    const thinkingStr = await AsyncStorage.getItem(
      GENERATION_SETTINGS_KEYS.THINKING_MODE_ENABLED
    );

    const temperature =
      tempStr !== null && !Number.isNaN(parseFloat(tempStr))
        ? parseFloat(tempStr)
        : 0.7;
    const maxTokens = maxStr ? parseInt(maxStr, 10) : 1000;
    const systemPrompt = sysStr && sysStr.trim() !== '' ? sysStr : undefined;
    const thinkingModeEnabled = thinkingStr === 'true';

    // eslint-disable-next-line no-console -- demo settings diagnostic
    console.log(
      `[PARAMS] App getGenerationOptions: temperature=${temperature}, maxTokens=${maxTokens}, systemPrompt=${systemPrompt ? `set(${systemPrompt.length} chars)` : 'nil'}, thinkingMode=${thinkingModeEnabled}`
    );

    return { temperature, maxTokens, systemPrompt, thinkingModeEnabled };
  };

  /**
   * Load available LLM models from catalog
   */
  const loadAvailableModels = async () => {
    try {
      const allModels = await listVisibleCatalogModels();
      const llmModels = allModels.filter(
        (m: SDKModelInfo) =>
          m.category === ModelCategory.MODEL_CATEGORY_LANGUAGE
      );
      setAvailableModels(llmModels);
      logDiagnostic(
        '[ChatScreen] Available LLM models:',
        llmModels.map(
          (m: SDKModelInfo) =>
            `${m.id} (${isModelDownloaded(m) ? 'downloaded' : 'not downloaded'})`
        )
      );
    } catch (error) {
      console.warn('[ChatScreen] Error loading models:', error);
    }
  };

  /**
   * Check if a model is loaded from a previous session.
   *
   * The SDK can confirm a model is loaded but doesn't expose which one, so we
   * intentionally leave `currentModel` as null and let the model-required empty
   * state prompt the user to pick one (required anyway for tool-call format
   * detection). No stand-in model entry is inserted.
   */
  const checkModelStatus = async () => {
    try {
      const isLoaded = await isModelLoadedForCategory(
        ModelCategory.MODEL_CATEGORY_LANGUAGE
      );
      logDiagnostic('[ChatScreen] Text model loaded:', isLoaded);
    } catch (error) {
      console.warn('[ChatScreen] Error checking model status:', error);
    }
  };

  /**
   * Handle model selection - opens the model selection sheet
   */
  const handleSelectModel = useCallback(() => {
    setShowModelSelection(true);
  }, []);

  /**
   * Handle model selected from the sheet
   */
  const handleModelSelected = useCallback(async (model: SDKModelInfo) => {
    // The sheet shows its own Loading spinner during the await; once the model
    // is loaded we close it so the user lands directly in the chat.
    await loadModel(model);
    setShowModelSelection(false);
  }, []);

  /**
   * Load a model using the SDK
   *
   * Path-first loading was removed in V2 — model ID is the canonical handle
   * and the native registry resolves the artifact path internally.
   */
  const loadModel = async (model: SDKModelInfo) => {
    try {
      setIsModelLoading(true);
      logDiagnostic(
        `[ChatScreen] Loading model: ${model.id} (registry will resolve path)`
      );

      if (!isModelDownloaded(model)) {
        Alert.alert(
          'Error',
          'Model has not been downloaded. Open the model picker to download it first.'
        );
        return;
      }

      await RunAnywhere.models.load(model.id);

      // Set the model info preserving the actual framework from the SDK model
      const fw = getPrimaryFramework(model);
      const modelInfo: SDKModelInfo = {
        ...model,
        category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
        framework: model.framework || fw,
        preferredFramework: fw,
        isAvailable: true,
        supportsThinking: model.supportsThinking ?? false,
      };
      setCurrentModel(modelInfo);

      // Reflect the tool count that Settings has registered (read-only here).
      const tools = await RunAnywhere.llm.tools.list();
      setRegisteredToolCount(tools.length);
    } catch (error) {
      console.error('[ChatScreen] Error loading model:', error);
      Alert.alert('Error', `Failed to load model: ${error}`);
    } finally {
      setIsModelLoading(false);
    }
  };

  // Tool-calling toggle (mirrors Android viewModel.toolsEnabled). Persisted so
  // it survives navigation; the input bar's tool button flips it.
  useEffect(() => {
    void (async () => {
      const enabled =
        (await AsyncStorage.getItem(APP_STORAGE_KEYS.TOOL_CALLING_ENABLED)) ===
        'true';
      setToolsEnabled(enabled);
      // The native tool registry is per-session, so a persisted "on" flag has
      // no tools after a relaunch. Re-register the demo tools when enabled but
      // the registry is empty, matching iOS ToolSettingsViewModel's
      // enable-on-init behavior; without this the chat routes to standard
      // generation and tool calling silently never runs.
      if (enabled) {
        const existing = await RunAnywhere.llm.tools.list();
        if (existing.length === 0) {
          await registerDemoTools();
        }
        setRegisteredToolCount((await RunAnywhere.llm.tools.list()).length);
      }
    })();
  }, []);

  const handleToggleTools = useCallback(async () => {
    const next = !toolsEnabled;
    setToolsEnabled(next);
    await AsyncStorage.setItem(
      APP_STORAGE_KEYS.TOOL_CALLING_ENABLED,
      next ? 'true' : 'false'
    );
    try {
      // The chat toggle must own registration too — flipping only the flag
      // leaves the registry empty, so preflight routes to standard generation
      // and tools never run. Mirror SettingsScreen: register on, clear off.
      if (next) {
        await registerDemoTools();
      } else {
        await RunAnywhere.llm.tools.clear();
      }
      setRegisteredToolCount((await RunAnywhere.llm.tools.list()).length);
    } catch (error) {
      console.error('[ChatScreen] Failed to update tool registration:', error);
    }
  }, [toolsEnabled]);

  /**
   * Send a message and stream the response token-by-token.
   * Uses RunAnywhere.llm.generateStream() for real-time streaming UI.
   *
   * With tools enabled the SDK owns the tool loop, so that path uses the
   * one-shot RunAnywhere.llm.generate(). An optional prompt override lets
   * prompt-suggestion pills send their text directly.
   */
  const handleSend = useCallback(
    async (promptOverride?: string) => {
      const text = (
        typeof promptOverride === 'string' ? promptOverride : inputText
      ).trim();
      if (isLoading || !text || !currentConversation) return;

      const userMessage: Message = {
        id: generateId(),
        role: MessageRole.User,
        content: text,
        timestamp: new Date(),
      };

      // Add user message to conversation
      await addMessage(userMessage, currentConversation.id);
      const prompt = text;
      setInputText('');
      setIsLoading(true);

      const assistantMessageId = generateId();
      let assistantMessageInserted = false;

      setTimeout(() => {
        flatListRef.current?.scrollToEnd({ animated: true });
      }, 100);

      try {
        // Get user-configured generation options
        const options = await getGenerationOptions();

        // eslint-disable-next-line no-console -- demo generation diagnostic
        console.log(
          '[ChatScreen] Starting streaming generation for:',
          prompt,
          'model:',
          currentModel?.id
        );

        const registeredTools = await RunAnywhere.llm.tools.list();
        // Route by the same tool/model gate the Android example uses: tool
        // generation only when tools are on, registered, and the model has a
        // large enough context window; otherwise standard generation, or a
        // blocked notice that falls back to standard.
        const toolPreflight = ToolCallingModelPolicy.preflight(
          toolsEnabled,
          registeredTools.length,
          currentModel
        );
        const shouldUseTools =
          toolPreflight.route === ToolCallingRoute.ToolGeneration;
        if (toolPreflight.route === ToolCallingRoute.Blocked) {
          Alert.alert(
            'Web & tools unavailable',
            toolPreflight.availability.message ??
              'Web & tools are unavailable for the current model.'
          );
        }
        const supportsThinking = currentModel?.supportsThinking ?? false;
        const wasThinkingMode = supportsThinking && options.thinkingModeEnabled;
        // Thought tokens only surface when reasoning.includeInOutput is set,
        // so the "show thinking" toggle maps to it. Non-thinking models get no
        // reasoning message at all — the no-think directive leaks as literal
        // prompt text on models like Llama.
        const reasoning: ReasoningOptions | undefined = !supportsThinking
          ? undefined
          : options.thinkingModeEnabled
            ? { mode: 'on', includeInOutput: true }
            : { mode: 'off' };
        wasStoppedRef.current = false;

        const llmOptions: LlmOptions = {
          maxOutputTokens: options.maxTokens,
          temperature: options.temperature,
          ...(options.systemPrompt
            ? { systemPrompt: options.systemPrompt }
            : {}),
          ...(reasoning ? { reasoning } : {}),
          // Tools registered from Settings are picked up automatically, so the
          // chat toggle has to opt out explicitly.
          ...(shouldUseTools ? {} : { toolChoice: 'none' as const }),
        };

        const frameworkName = formatFramework(
          currentModel?.preferredFramework ?? currentModel?.framework
        );

        const messageModelInfo = {
          modelId: currentModel?.id || 'unknown',
          modelName: currentModel?.name || 'Unknown Model',
          framework: frameworkName,
          frameworkDisplayName: frameworkName,
        };

        // Insert the initial empty assistant message once (matches iOS two-phase pattern).
        const initialAssistantMessage: Message = {
          id: assistantMessageId,
          role: MessageRole.Assistant,
          content: '',
          timestamp: new Date(),
          isStreaming: true,
          modelInfo: messageModelInfo,
        };
        await addMessage(initialAssistantMessage, currentConversation.id);
        assistantMessageInserted = true;

        let result: GenerationResult | null = null;
        let toolCallInfo: ToolCallInfo | undefined;
        let streamedText = '';
        let streamedThoughts = '';

        if (shouldUseTools) {
          // Explicit tool-calling API: the SDK owns the run loop; we bound it
          // with the same execution budget as the Android example (max 2 calls,
          // 96-token synthesis, greedy sampling, thinking off, parallel calls,
          // 45s ceiling).
          updateMessage(
            {
              id: assistantMessageId,
              role: MessageRole.Assistant,
              content: ToolCallingExecutionPolicy.PROGRESS_MESSAGE,
              timestamp: new Date(),
              isStreaming: true,
              modelInfo: messageModelInfo,
            },
            currentConversation.id
          );
          const plan = ToolCallingExecutionPolicy.plan(
            registeredTools,
            options.maxTokens
          );
          const controller = new AbortController();
          let timedOut = false;
          const timer = setTimeout(() => {
            timedOut = true;
            controller.abort();
          }, ToolCallingExecutionPolicy.TIMEOUT_MILLIS);
          try {
            const toolResult = await generateWithTools(
              prompt,
              plan.toolOptions,
              {
                llmOptions: plan.llmOptions,
                signal: controller.signal,
              }
            );
            if (!timedOut) {
              result = toGenerationResult(toolResult, currentModel?.id ?? '');
              toolCallInfo = makeToolCallInfo(toolResult);
            }
          } catch (error) {
            if (!timedOut) throw error;
          } finally {
            clearTimeout(timer);
          }
          if (timedOut) {
            const timeoutSeconds =
              ToolCallingExecutionPolicy.TIMEOUT_MILLIS / 1000;
            streamedText =
              `${currentModel?.name ?? 'The model'} did not finish the Web & tools ` +
              `request within ${timeoutSeconds} seconds. Try a shorter request or another model.`;
          }
        } else {
          // Hermes cannot `for await...of` a Nitro async iterable — drive the
          // iterator by hand and return() it to cancel the native work.
          const iterator = RunAnywhere.llm
            .generateStream(prompt, llmOptions)
            [Symbol.asyncIterator]();
          generationIteratorRef.current = iterator;
          try {
            let step = await iterator.next();
            while (!step.done) {
              const event = step.value;
              if (event.type === 'token') {
                if (event.kind === 'thought') {
                  streamedThoughts += event.text;
                } else {
                  streamedText += event.text;
                  updateMessage(
                    {
                      id: assistantMessageId,
                      role: MessageRole.Assistant,
                      content: streamedText,
                      timestamp: new Date(),
                      isStreaming: true,
                      modelInfo: messageModelInfo,
                    },
                    currentConversation.id
                  );
                  flatListRef.current?.scrollToEnd({ animated: false });
                  await new Promise<void>((resolve) => setTimeout(resolve, 0));
                }
              } else if (event.type === 'completed') {
                result = event.result;
              }
              step = await iterator.next();
            }
          } finally {
            await iterator.return?.();
            generationIteratorRef.current = null;
          }
        }

        const wasStopped = wasStoppedRef.current;
        const finalContent = result?.text || streamedText;
        const thinkingContent = result?.thinkingText || streamedThoughts;

        // Build the final message with analytics and persist to disk once
        // (mirrors iOS finalizeGeneration / updateConversation).
        const finalMessage: Message = {
          id: assistantMessageId,
          role: MessageRole.Assistant,
          content: finalContent || '—',
          ...(thinkingContent ? { thinkingContent } : {}),
          timestamp: new Date(),
          modelInfo: messageModelInfo,
          ...(toolCallInfo ? { toolCallInfo } : {}),
          analytics: analyticsFromResult(result, {
            completionStatus: wasStopped ? 'interrupted' : 'completed',
            wasThinkingMode,
            wasInterrupted: wasStopped,
            retryCount: 0,
          }),
        };

        // Apply analytics fields in-memory first, then persist once.
        updateMessage(finalMessage, currentConversation.id);
        const latestConversation = useConversationStore
          .getState()
          .conversations.find((c) => c.id === currentConversation.id);
        if (latestConversation) {
          await updateConversation(latestConversation);
        }

        // Final scroll to bottom
        setTimeout(() => {
          flatListRef.current?.scrollToEnd({ animated: true });
        }, 100);
      } catch (error) {
        console.error('[ChatScreen] Generation error:', error);

        const wasStopped = wasStoppedRef.current;
        const errorContent = wasStopped
          ? 'Generation stopped.'
          : `Error: ${error}\n\nThis likely means no LLM model is loaded. Load a model first.`;
        const errorMessage: Message = {
          id: assistantMessageId,
          role: MessageRole.Assistant,
          content: errorContent,
          timestamp: new Date(),
          analytics: analyticsFromResult(null, {
            completionStatus: wasStopped ? 'interrupted' : 'error',
            wasThinkingMode: false,
            wasInterrupted: wasStopped,
            retryCount: 0,
          }),
        };
        if (assistantMessageInserted) {
          updateMessage(errorMessage, currentConversation.id);
        } else {
          await addMessage(errorMessage, currentConversation.id);
        }
      } finally {
        generationIteratorRef.current = null;
        setIsLoading(false);
      }
    },
    [
      isLoading,
      inputText,
      currentConversation,
      currentModel,
      toolsEnabled,
      addMessage,
      updateMessage,
      updateConversation,
    ]
  );

  const handleStopGeneration = useCallback(() => {
    wasStoppedRef.current = true;
    // Returning the iterator cancels the native generation; the loop then ends
    // normally and finalizes whatever was streamed so far.
    void generationIteratorRef.current?.return?.();
  }, []);

  /**
   * Create a new conversation (clears current chat)
   */
  const handleNewChat = useCallback(async () => {
    await createConversation();
  }, [createConversation]);

  // Expose test helpers for E2E automation via Hermes debugger
  useEffect(() => {
    if (__DEV__) {
      const g = globalThis as unknown as Record<string, unknown>;
      g.__testNewChat = handleNewChat;
      g.__testSend = handleSend;
      g.__testSetInput = setInputText;
    }
  }, [handleNewChat, handleSend]);

  /**
   * Handle selecting a conversation from the list
   */
  const handleSelectConversation = useCallback(
    (conversation: Conversation) => {
      setCurrentConversation(conversation);
    },
    [setCurrentConversation]
  );

  /**
   * Render a message
   */
  const renderMessage = ({ item }: { item: Message }) => (
    <MessageBubble message={item} />
  );

  /**
   * Render empty state
   */
  const renderEmptyState = () => (
    <View style={styles.emptyState}>
      <View style={styles.emptyIconContainer}>
        <Icon
          name="chatbubble-ellipses-outline"
          size={48}
          color={colors.outline}
        />
      </View>
      <Text style={styles.emptyTitle}>Start a conversation</Text>
      <Text style={styles.emptySubtitle}>
        Type a message below to begin chatting with the AI
      </Text>
    </View>
  );

  /**
   * Handle opening analytics
   */
  const handleShowAnalytics = useCallback(() => {
    setShowAnalytics(true);
  }, []);

  /**
   * Render header with actions
   */
  const renderHeader = () => (
    <ChatHeader
      modelName={currentModel?.name}
      ready={!!currentModel}
      generating={isLoading}
      hasMessages={messages.length > 0}
      onModelPress={handleSelectModel}
      onAnalytics={handleShowAnalytics}
      onHistory={() => setShowConversationList(true)}
      onNewChat={handleNewChat}
    />
  );

  const showOverlay = !currentModel && !isModelLoading;

  return (
    <SafeAreaView style={styles.container} edges={['left', 'right']}>
      {renderHeader()}

      {showOverlay ? (
        <ModelRequiredOverlay
          modality="llm"
          onSelectModel={handleSelectModel}
        />
      ) : (
        <>
          {/* Messages List */}
          <FlatList
            ref={flatListRef}
            style={styles.list}
            data={messages}
            renderItem={renderMessage}
            keyExtractor={(item) => item.id}
            contentContainerStyle={[
              styles.messagesList,
              messages.length === 0 && styles.emptyList,
            ]}
            ListEmptyComponent={renderEmptyState}
            showsVerticalScrollIndicator={false}
          />

          {/* Tool Calling Badge (shows when tools are enabled) */}
          {currentModel && registeredToolCount > 0 && (
            <ToolCallingBadge toolCount={registeredToolCount} />
          )}

          {/* LoRA pill (mirrors iOS ChatMessageListView's LoRA row above input) */}
          {currentModel && (
            <View style={styles.loraRow}>
              <TouchableOpacity
                style={[
                  styles.loraPill,
                  loraAdapterCount > 0 && styles.loraPillActive,
                ]}
                onPress={() => setShowLoRASheet(true)}
              >
                <Icon
                  name="sparkles"
                  size={14}
                  color={
                    loraAdapterCount > 0 ? colors.onPrimary : colors.primary
                  }
                />
                <Text
                  style={[
                    styles.loraPillText,
                    loraAdapterCount > 0 && styles.loraPillTextActive,
                  ]}
                >
                  {loraAdapterCount > 0
                    ? `LoRA x${loraAdapterCount}`
                    : '+ LoRA'}
                </Text>
              </TouchableOpacity>
            </View>
          )}

          {/* Example prompts (mode follows tool/LoRA state), shown on an empty chat */}
          {currentModel && messages.length === 0 && (
            <PromptSuggestions
              toolsEnabled={toolsEnabled}
              loraActive={loraAdapterCount > 0}
              onSelect={(p) => void handleSend(p)}
            />
          )}

          {/* Input Area */}
          <ChatInput
            value={inputText}
            onChangeText={setInputText}
            onSend={handleSend}
            onStop={handleStopGeneration}
            disabled={!currentModel || !currentConversation}
            isLoading={isLoading}
            toolsEnabled={toolsEnabled}
            onToggleTools={currentModel ? handleToggleTools : undefined}
            placeholder={
              currentModel
                ? 'Type a message...'
                : 'Select a model to start chatting'
            }
          />
        </>
      )}

      {/* Analytics Modal */}
      <Modal
        visible={showAnalytics}
        animationType="slide"
        presentationStyle="pageSheet"
        onRequestClose={() => setShowAnalytics(false)}
      >
        <ChatAnalyticsScreen
          messages={messages}
          onClose={() => setShowAnalytics(false)}
        />
      </Modal>

      {/* LoRA Adapter Management Sheet */}
      <LoRASheet
        visible={showLoRASheet}
        modelId={currentModel?.id ?? null}
        onClose={() => setShowLoRASheet(false)}
        onAdaptersChanged={(adapters) => setLoraAdapterCount(adapters.length)}
      />

      {/* Conversation history sheet */}
      <ConversationListScreen
        visible={showConversationList}
        onClose={() => setShowConversationList(false)}
        onSelectConversation={handleSelectConversation}
      />

      {/* Model Selection Sheet */}
      <ModelSelectionSheet
        visible={showModelSelection}
        context={ModelSelectionContext.LLM}
        activeModelId={currentModel?.id ?? null}
        onClose={() => setShowModelSelection(false)}
        onModelSelected={handleModelSelected}
      />
    </SafeAreaView>
  );
};

const createStyles = (colors: ColorScheme) =>
  StyleSheet.create({
    container: {
      flex: 1,
      backgroundColor: colors.background,
    },
    list: {
      flex: 1,
    },
    messagesList: {
      paddingVertical: 10,
    },
    emptyList: {
      flexGrow: 1,
      justifyContent: 'center',
    },
    emptyState: {
      alignItems: 'center',
      padding: 40,
    },
    emptyIconContainer: {
      width: 80,
      height: 80,
      borderRadius: 40,
      backgroundColor: colors.surfaceContainer,
      justifyContent: 'center',
      alignItems: 'center',
      marginBottom: 16,
    },
    emptyTitle: {
      ...typography.titleLarge,
      color: colors.onSurface,
      marginBottom: 6,
    },
    emptySubtitle: {
      ...typography.bodyLarge,
      color: colors.onSurfaceVariant,
      textAlign: 'center',
      maxWidth: 280,
    },
    loraRow: {
      flexDirection: 'row',
      paddingHorizontal: 16,
      paddingTop: 2,
      paddingBottom: 6,
    },
    loraPill: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 4,
      borderWidth: 1,
      borderColor: colors.primary,
      borderRadius: 14,
      paddingHorizontal: 12,
      paddingVertical: 4,
    },
    loraPillActive: {
      backgroundColor: colors.primary,
    },
    loraPillText: {
      ...typography.labelSmall,
      color: colors.primary,
    },
    loraPillTextActive: {
      color: colors.onPrimary,
    },
  });

export default ChatScreen;
