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
 * - Model loading via RunAnywhere.loadModel(ModelLoadRequest)
 * - Text generation via RunAnywhere.generate(prompt, options?)
 *   and RunAnywhere.generateStream(prompt, options?) (proto-canonical signatures)
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
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding, IconSize } from '../theme/spacing';
import { ModelStatusBanner, ModelRequiredOverlay } from '../components/common';
import {
  MessageBubble,
  TypingIndicator,
  ChatInput,
  ToolCallingBadge,
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
import { GENERATION_SETTINGS_KEYS } from '../types/settings';
import {
  getFrameworkDisplayName,
  getPrimaryFramework,
} from '../utils/modelDisplay';

// Import RunAnywhere SDK (Multi-Package Architecture)
import { RunAnywhere } from '@runanywhere/core';
import { LLMGenerationOptions } from '@runanywhere/proto-ts/llm_options';
import {
  InferenceFramework,
  ModelCategory,
  ModelLoadRequest,
  type ModelInfo as SDKModelInfo,
} from '@runanywhere/proto-ts/model_types';
import { logDiagnostic } from '../utils/diagnostics';
import { isModelLoadedForCategory } from '../utils/runAnywhereLifecycle';

// Canonical SDK methods (Swift parity).
const listModels = async (): Promise<SDKModelInfo[]> =>
  (await RunAnywhere.listModels()).models?.models ?? [];
const loadModelWithRequest = RunAnywhere.loadModel;

// Generate unique ID
const generateId = () => Math.random().toString(36).substring(2, 15);

interface GenerationSettings {
  temperature: number;
  maxTokens: number;
  systemPrompt?: string;
}

export const ChatScreen: React.FC = () => {
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

  // Refs
  const flatListRef = useRef<FlatList>(null);

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
    RunAnywhere.getRegisteredTools().then((tools) =>
      setRegisteredToolCount(tools.length)
    );
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

    const temperature =
      tempStr !== null && !Number.isNaN(parseFloat(tempStr))
        ? parseFloat(tempStr)
        : 0.7;
    const maxTokens = maxStr ? parseInt(maxStr, 10) : 1000;
    const systemPrompt = sysStr && sysStr.trim() !== '' ? sysStr : undefined;

    // eslint-disable-next-line no-console -- demo settings diagnostic
    console.log(
      `[PARAMS] App getGenerationOptions: temperature=${temperature}, maxTokens=${maxTokens}, systemPrompt=${systemPrompt ? `set(${systemPrompt.length} chars)` : 'nil'}`
    );

    return { temperature, maxTokens, systemPrompt };
  };

  /**
   * Load available LLM models from catalog
   */
  const loadAvailableModels = async () => {
    try {
      const allModels = await listModels();
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
    // Close the modal first to prevent UI issues
    setShowModelSelection(false);
    // Then load the model
    await loadModel(model);
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

      const result = await loadModelWithRequest(
        ModelLoadRequest.fromPartial({
          modelId: model.id,
          category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
          forceReload: false,
          validateAvailability: true,
        })
      );

      if (result.success) {
        // Set the model info preserving the actual framework from the SDK model
        const fw = getPrimaryFramework(
          model,
          InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP
        );
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
        const tools = await RunAnywhere.getRegisteredTools();
        setRegisteredToolCount(tools.length);
      } else {
        const lastError =
          result.errorMessage ||
          'Native model lifecycle returned an unsuccessful load result';
        Alert.alert(
          'Error',
          `Failed to load model: ${lastError || 'Unknown error'}`
        );
      }
    } catch (error) {
      console.error('[ChatScreen] Error loading model:', error);
      Alert.alert('Error', `Failed to load model: ${error}`);
    } finally {
      setIsModelLoading(false);
    }
  };

  /**
   * Send a message and stream the response token-by-token.
   * Uses RunAnywhere.generateStream() for real-time streaming UI.
   *
   * generateWithTools() is still available on RunAnywhere for callers
   * that genuinely need the batch tool-calling form.
   */
  const handleSend = useCallback(async () => {
    if (!inputText.trim() || !currentConversation) return;

    const userMessage: Message = {
      id: generateId(),
      role: MessageRole.User,
      content: inputText.trim(),
      timestamp: new Date(),
    };

    // Add user message to conversation
    await addMessage(userMessage, currentConversation.id);
    const prompt = inputText.trim();
    setInputText('');
    setIsLoading(true);

    const assistantMessageId = generateId();

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

      let accumulatedText = '';

      const genOptions = LLMGenerationOptions.fromPartial({
        maxTokens: options.maxTokens ?? 512,
        temperature: options.temperature ?? 0.7,
        topP: 1.0,
        topK: 0,
        repetitionPenalty: 1.0,
        stopSequences: [],
        streamingEnabled: true,
        preferredFramework:
          currentModel?.preferredFramework ??
          currentModel?.framework ??
          InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED,
        systemPrompt: options.systemPrompt,
        enableRealTimeTracking: false,
        seed: 0,
        frequencyPenalty: 0,
        presencePenalty: 0,
        repeatLastN: 0,
        minP: 0,
        echoPrompt: false,
        nThreads: 0,
      });

      const frameworkName = getFrameworkDisplayName(
        currentModel?.preferredFramework ?? currentModel?.framework
      );

      // Insert the initial empty assistant message once (matches iOS two-phase pattern).
      const initialAssistantMessage: Message = {
        id: assistantMessageId,
        role: MessageRole.Assistant,
        content: '',
        timestamp: new Date(),
        modelInfo: {
          modelId: currentModel?.id || 'unknown',
          modelName: currentModel?.name || 'Unknown Model',
          framework: frameworkName,
          frameworkDisplayName: frameworkName,
        },
      };
      await addMessage(initialAssistantMessage, currentConversation.id);

      // Stream tokens as they arrive — canonical cross-SDK path. We drive
      // the SDK's `aggregateStream(prompt, events, onToken)` helper exactly
      // like iOS LLMViewModel+Generation.swift: it consumes the
      // `generateStream` AsyncIterable, accumulates the transcript, and
      // invokes `onToken` with the full text so far for live UI updates.
      //
      // `updateMessage` is a synchronous in-memory store write (no per-token
      // disk write). Because the whole stream resolves on the microtask
      // queue, we must hand a macrotask back to React inside `onToken`
      // (`setTimeout(0)`) so it can paint each token into the assistant
      // bubble — otherwise the synchronous-update loop runs to completion
      // before React ever re-renders and the bubble appears empty mid-stream.
      const eventStream = RunAnywhere.generateStream(prompt, genOptions);
      const result = await RunAnywhere.aggregateStream(
        prompt,
        eventStream,
        async (transcript) => {
          accumulatedText = transcript;
          updateMessage(
            {
              id: assistantMessageId,
              role: MessageRole.Assistant,
              content: accumulatedText,
              timestamp: new Date(),
              modelInfo: {
                modelId: currentModel?.id || 'unknown',
                modelName: currentModel?.name || 'Unknown Model',
                framework: frameworkName,
                frameworkDisplayName: frameworkName,
              },
            },
            currentConversation.id
          );
          flatListRef.current?.scrollToEnd({ animated: false });
          // Yield a macrotask so React flushes this token to the screen.
          await new Promise<void>((resolve) => setTimeout(resolve, 0));
        }
      );

      const finalContent =
        result.text || accumulatedText || '(No response generated)';

      // Build the final message with analytics and persist to disk once
      // (mirrors iOS finalizeGeneration / updateConversation).
      const finalMessage: Message = {
        id: assistantMessageId,
        role: MessageRole.Assistant,
        content: finalContent,
        timestamp: new Date(),
        modelInfo: {
          modelId: currentModel?.id || 'unknown',
          modelName: currentModel?.name || 'Unknown Model',
          framework: frameworkName,
          frameworkDisplayName: frameworkName,
        },
        analytics: {
          performance: {
            latencyMs: result.generationTimeMs,
            memoryBytes: 0,
            throughputTokensPerSec: result.tokensPerSecond,
            promptTokens: result.inputTokens,
            completionTokens: result.tokensGenerated,
          },
          timeToFirstToken: result.ttftMs,
          completionStatus: 'completed',
          wasThinkingMode: false,
          wasInterrupted: false,
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

      await addMessage(
        {
          id: assistantMessageId,
          role: MessageRole.Assistant,
          content: `Error: ${error}\n\nThis likely means no LLM model is loaded. Load a model first.`,
          timestamp: new Date(),
        },
        currentConversation.id
      );
    } finally {
      setIsLoading(false);
    }
  }, [inputText, currentConversation, currentModel, addMessage, updateMessage, updateConversation]);

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
          size={IconSize.large}
          color={Colors.textTertiary}
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
    <View
      style={[styles.header, { paddingTop: insets.top + Padding.padding12 }]}
    >
      {/* Conversations list button */}
      <TouchableOpacity
        style={styles.headerButton}
        onPress={() => setShowConversationList(true)}
      >
        <Icon name="list" size={22} color={Colors.primaryBlue} />
      </TouchableOpacity>

      {/* Title with conversation count */}
      <View style={styles.titleContainer}>
        <Text style={styles.title}>Chat</Text>
        {conversations.length > 1 && (
          <Text style={styles.conversationCount}>
            {conversations.length} conversations
          </Text>
        )}
      </View>

      <View style={styles.headerActions}>
        {/* New chat button */}
        <TouchableOpacity style={styles.headerButton} onPress={handleNewChat}>
          <Icon name="add" size={24} color={Colors.primaryBlue} />
        </TouchableOpacity>

        {/* Info button for chat analytics */}
        <TouchableOpacity
          style={[
            styles.headerButton,
            messages.length === 0 && styles.headerButtonDisabled,
          ]}
          onPress={handleShowAnalytics}
          disabled={messages.length === 0}
        >
          <Icon
            name="information-circle-outline"
            size={22}
            color={
              messages.length > 0 ? Colors.primaryBlue : Colors.textTertiary
            }
          />
        </TouchableOpacity>
      </View>
    </View>
  );

  // Show model required overlay if no model
  if (!currentModel && !isModelLoading) {
    return (
      <SafeAreaView style={styles.container}>
        {renderHeader()}
        <ModelRequiredOverlay
          modality="llm"
          onSelectModel={handleSelectModel}
        />

        {/* Conversation List Modal */}
        <Modal
          visible={showConversationList}
          animationType="slide"
          presentationStyle="pageSheet"
          onRequestClose={() => setShowConversationList(false)}
        >
          <ConversationListScreen
            onClose={() => setShowConversationList(false)}
            onSelectConversation={handleSelectConversation}
          />
        </Modal>

        {/* Model Selection Sheet */}
        <ModelSelectionSheet
          visible={showModelSelection}
          context={ModelSelectionContext.LLM}
          onClose={() => setShowModelSelection(false)}
          onModelSelected={handleModelSelected}
        />
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      {renderHeader()}

      {/* Model Status Banner */}
      <ModelStatusBanner
        modelName={currentModel?.name}
        framework={currentModel?.preferredFramework}
        isLoading={isModelLoading}
        onSelectModel={handleSelectModel}
      />

      {/* Messages List */}
      <FlatList
        ref={flatListRef}
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

      {/* Typing Indicator */}
      {isLoading && <TypingIndicator />}

      {/* Tool Calling Badge (shows when tools are enabled) */}
      {currentModel && registeredToolCount > 0 && (
        <ToolCallingBadge toolCount={registeredToolCount} />
      )}

      {/* Input Area */}
      <ChatInput
        value={inputText}
        onChangeText={setInputText}
        onSend={handleSend}
        disabled={!currentModel || !currentConversation}
        isLoading={isLoading}
        placeholder={
          currentModel
            ? 'Type a message...'
            : 'Select a model to start chatting'
        }
      />

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

      {/* Conversation List Modal */}
      <Modal
        visible={showConversationList}
        animationType="slide"
        presentationStyle="pageSheet"
        onRequestClose={() => setShowConversationList(false)}
      >
        <ConversationListScreen
          onClose={() => setShowConversationList(false)}
          onSelectConversation={handleSelectConversation}
        />
      </Modal>

      {/* Model Selection Sheet */}
      <ModelSelectionSheet
        visible={showModelSelection}
        context={ModelSelectionContext.LLM}
        onClose={() => setShowModelSelection(false)}
        onModelSelected={handleModelSelected}
      />
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.backgroundPrimary,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: Padding.padding16,
    paddingTop: 0,
    paddingBottom: Padding.padding12,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  titleContainer: {
    alignItems: 'center',
  },
  title: {
    ...Typography.title2,
    color: Colors.textPrimary,
  },
  conversationCount: {
    ...Typography.caption2,
    color: Colors.textTertiary,
    marginTop: 2,
  },
  headerActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.small,
  },
  headerButton: {
    padding: Spacing.small,
  },
  headerButtonDisabled: {
    opacity: 0.5,
  },
  messagesList: {
    paddingVertical: Spacing.medium,
  },
  emptyList: {
    flex: 1,
    justifyContent: 'center',
  },
  emptyState: {
    alignItems: 'center',
    padding: Padding.padding40,
  },
  emptyIconContainer: {
    width: IconSize.huge,
    height: IconSize.huge,
    borderRadius: IconSize.huge / 2,
    backgroundColor: Colors.backgroundSecondary,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: Spacing.large,
  },
  emptyTitle: {
    ...Typography.title3,
    color: Colors.textPrimary,
    marginBottom: Spacing.small,
  },
  emptySubtitle: {
    ...Typography.body,
    color: Colors.textSecondary,
    textAlign: 'center',
    maxWidth: 280,
  },
});

export default ChatScreen;
