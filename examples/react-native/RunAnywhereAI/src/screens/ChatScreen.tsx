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
import { getPrimaryFramework } from '../utils/modelDisplay';

// Import RunAnywhere SDK (Multi-Package Architecture)
import { RunAnywhere, formatFramework } from '@runanywhere/core';
import type {
  GenerationResult,
  LlmOptions,
  ReasoningOptions,
} from '@runanywhere/core';
import {
  ModelCategory,
  type ModelInfo as SDKModelInfo,
} from '@runanywhere/proto-ts/model_types';
import { logDiagnostic } from '../utils/diagnostics';
import { isModelLoadedForCategory } from '../utils/runAnywhereLifecycle';
import { listVisibleCatalogModels } from '../services/ModelRegistryQueries';
import type { ToolCallInfo } from '../types/chat';

// Generate unique ID
const generateId = () => Math.random().toString(36).substring(2, 15);

interface GenerationSettings {
  temperature: number;
  maxTokens: number;
  systemPrompt?: string;
  thinkingModeEnabled: boolean;
}

// The v3 GenerationResult reports the calls the model made; per-call execution
// results are no longer surfaced, so the detail sheet shows arguments only.
function makeToolCallInfo(result: GenerationResult): ToolCallInfo | undefined {
  const firstCall = result.toolCalls[0];
  if (!firstCall) return undefined;

  return {
    toolName: firstCall.name,
    arguments: firstCall.argumentsJson || '{}',
    success: true,
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
            `${m.id} (${m.isDownloaded || m.localPath ? 'downloaded' : 'not downloaded'})`
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

      if (!model.isDownloaded && !model.localPath) {
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
        isDownloaded: true,
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
    AsyncStorage.getItem(APP_STORAGE_KEYS.TOOL_CALLING_ENABLED).then((v) =>
      setToolsEnabled(v === 'true')
    );
  }, []);

  const handleToggleTools = useCallback(() => {
    setToolsEnabled((prev) => {
      const next = !prev;
      void AsyncStorage.setItem(
        APP_STORAGE_KEYS.TOOL_CALLING_ENABLED,
        next ? 'true' : 'false'
      );
      return next;
    });
  }, []);

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
        const shouldUseTools = toolsEnabled && registeredTools.length > 0;
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
        const generationStartMs = Date.now();
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
        let streamedText = '';
        let streamedThoughts = '';

        if (shouldUseTools) {
          // The SDK runs the tool loop itself and reports what it called on the
          // result, so there is nothing to sequence here.
          result = await RunAnywhere.llm.generate(prompt, llmOptions);
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
        const finalContent =
          result?.text || streamedText || '(No response generated)';
        const thinkingContent = result?.thinkingText || streamedThoughts;

        // Build the final message with analytics and persist to disk once
        // (mirrors iOS finalizeGeneration / updateConversation).
        const finalMessage: Message = {
          id: assistantMessageId,
          role: MessageRole.Assistant,
          content: finalContent,
          ...(thinkingContent ? { thinkingContent } : {}),
          timestamp: new Date(),
          modelInfo: messageModelInfo,
          ...(result ? { toolCallInfo: makeToolCallInfo(result) } : {}),
          analytics: {
            performance: {
              latencyMs: Date.now() - generationStartMs,
              memoryBytes: 0,
              throughputTokensPerSec: result?.tokensPerSecond ?? 0,
              inputTokens: result?.inputTokens ?? 0,
              outputTokens: result?.outputTokens ?? 0,
            },
            ...(result ? { timeToFirstToken: result.timeToFirstTokenMs } : {}),
            completionStatus: wasStopped ? 'interrupted' : 'completed',
            wasThinkingMode,
            wasInterrupted: wasStopped,
            retryCount: 0,
          },
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
          analytics: {
            performance: {
              latencyMs: 0,
              memoryBytes: 0,
              throughputTokensPerSec: 0,
              inputTokens: 0,
              outputTokens: 0,
            },
            completionStatus: wasStopped ? 'interrupted' : 'error',
            wasThinkingMode: false,
            wasInterrupted: wasStopped,
            retryCount: 0,
          },
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
