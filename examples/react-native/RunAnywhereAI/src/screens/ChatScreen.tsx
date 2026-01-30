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
 * - Model loading via RunAnywhere.loadModel()
 * - Text generation via RunAnywhere.generate()
 *
 * Reference: iOS examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Chat/Views/ChatInterfaceView.swift
 */

import React, { useState, useRef, useCallback, useEffect } from 'react';
import {
  View,
  Text,
  FlatList,
  StyleSheet,
  SafeAreaView,
  TouchableOpacity,
  Alert,
  Modal,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding, IconSize } from '../theme/spacing';
import { ModelStatusBanner, ModelRequiredOverlay } from '../components/common';
import { MessageBubble, TypingIndicator, ChatInput, ToolCallingBadge } from '../components/chat';
import { ChatAnalyticsScreen } from './ChatAnalyticsScreen';
import { ConversationListScreen } from './ConversationListScreen';
import type { Message, Conversation, ToolCallInfo } from '../types/chat';
import { MessageRole } from '../types/chat';
import type { ModelInfo } from '../types/model';
import { ModelModality, LLMFramework, ModelCategory } from '../types/model';
import { useConversationStore } from '../stores/conversationStore';
import {
  ModelSelectionSheet,
  ModelSelectionContext,
} from '../components/model';

// Import RunAnywhere SDK (Multi-Package Architecture)
import { RunAnywhere, type ModelInfo as SDKModelInfo } from '@runanywhere/core';

// Generate unique ID
const generateId = () => Math.random().toString(36).substring(2, 15);

// =============================================================================
// TOOL CALLING SETUP - Weather API Example
// =============================================================================

/**
 * Register tools for the chat. This enables the LLM to call external APIs.
 * Users just chat normally - tool calls happen transparently.
 */
const registerChatTools = () => {
  // Clear any existing tools
  RunAnywhere.clearTools();

  // Weather tool - Real API (wttr.in - no key needed)
  RunAnywhere.registerTool(
    {
      name: 'get_weather',
      description: 'Gets the current weather for a city or location',
      parameters: [
        {
          name: 'location',
          type: 'string',
          description: 'City name or location (e.g., "Tokyo", "New York", "London")',
          required: true,
        },
      ],
    },
    async (args) => {
      // Handle both 'location' and 'city' parameter names (models vary)
      const location = (args.location || args.city) as string;
      console.log('[Tool] get_weather called for:', location);

      try {
        const url = `https://wttr.in/${encodeURIComponent(location)}?format=j1`;
        const response = await fetch(url);

        if (!response.ok) {
          return { error: `Weather API error: ${response.status}` };
        }

        const data = await response.json();
        const current = data.current_condition[0];
        const area = data.nearest_area?.[0];

        return {
          location: area?.areaName?.[0]?.value || location,
          country: area?.country?.[0]?.value || '',
          temperature_f: parseInt(current.temp_F, 10),
          temperature_c: parseInt(current.temp_C, 10),
          condition: current.weatherDesc[0].value,
          humidity: `${current.humidity}%`,
          wind_mph: `${current.windspeedMiles} mph`,
          feels_like_f: parseInt(current.FeelsLikeF, 10),
        };
      } catch (error) {
        const msg = error instanceof Error ? error.message : String(error);
        console.error('[Tool] Weather fetch failed:', msg);
        return { error: msg };
      }
    }
  );

  // Current time tool
  RunAnywhere.registerTool(
    {
      name: 'get_current_time',
      description: 'Gets the current date and time',
      parameters: [],
    },
    async () => {
      console.log('[Tool] get_current_time called');
      const now = new Date();
      return {
        date: now.toLocaleDateString(),
        time: now.toLocaleTimeString(),
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      };
    }
  );

  // Calculator tool - Math evaluation
  RunAnywhere.registerTool(
    {
      name: 'calculate',
      description: 'Performs math calculations. Supports +, -, *, /, and parentheses',
      parameters: [
        {
          name: 'expression',
          type: 'string',
          description: 'Math expression (e.g., "2 + 2 * 3", "(10 + 5) / 3")',
          required: true,
        },
      ],
    },
    async (args) => {
      const expression = (args.expression || args.input) as string;
      console.log('[Tool] calculate called for:', expression);
      try {
        // Simple and safe math evaluation
        const sanitized = expression.replace(/[^0-9+\-*/().% ]/g, '');
        // eslint-disable-next-line no-eval
        const result = eval(sanitized);
        return {
          expression: sanitized,
          result: result,
        };
      } catch (error) {
        const msg = error instanceof Error ? error.message : String(error);
        return { error: `Failed to calculate: ${msg}` };
      }
    }
  );

  console.log('[ChatScreen] Tools registered: get_weather, get_current_time, calculate');
};

/**
 * Detect tool call format based on model ID and name
 * LFM2-Tool models use Pythonic format, others use JSON format
 * 
 * Matches iOS: LLMViewModel+ToolCalling.swift detectToolCallFormat()
 * Checks both ID and name since model might be identified by either
 */
const detectToolCallFormat = (modelId: string | undefined, modelName: string | undefined): string => {
  // Check model ID first (more reliable - e.g., "lfm2-1.2b-tool-q4_k_m")
  if (modelId) {
    const id = modelId.toLowerCase();
    if (id.includes('lfm2') && id.includes('tool')) {
      return 'lfm2';
    }
  }

  // Also check model name (e.g., "LiquidAI LFM2 1.2B Tool Q4_K_M")
  if (modelName) {
    const name = modelName.toLowerCase();
    if (name.includes('lfm2') && name.includes('tool')) {
      return 'lfm2';
    }
  }

  // Default JSON format for general-purpose models
  return 'default';
};

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
  } = useConversationStore();

  // Local state
  const [inputText, setInputText] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [isModelLoading, setIsModelLoading] = useState(false);
  const [currentModel, setCurrentModel] = useState<ModelInfo | null>(null);
  const [_availableModels, setAvailableModels] = useState<SDKModelInfo[]>([]);
  const [showAnalytics, setShowAnalytics] = useState(false);
  const [showConversationList, setShowConversationList] = useState(false);
  const [showModelSelection, setShowModelSelection] = useState(false);
  const [isInitialized, setIsInitialized] = useState(false);
  const [registeredToolCount, setRegisteredToolCount] = useState(0);

  // Refs
  const flatListRef = useRef<FlatList>(null);

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
  }, []);

  // Messages from current conversation
  const messages = currentConversation?.messages || [];

  /**
   * Load available LLM models from catalog
   */
  const loadAvailableModels = async () => {
    try {
      const allModels = await RunAnywhere.getAvailableModels();
      const llmModels = allModels.filter(
        (m: SDKModelInfo) => m.category === ModelCategory.Language
      );
      setAvailableModels(llmModels);
      console.warn(
        '[ChatScreen] Available LLM models:',
        llmModels.map(
          (m: SDKModelInfo) =>
            `${m.id} (${m.isDownloaded ? 'downloaded' : 'not downloaded'})`
        )
      );
    } catch (error) {
      console.warn('[ChatScreen] Error loading models:', error);
    }
  };

  /**
   * Check if a model is loaded
   * Note: If a model is already loaded from a previous session, we set a placeholder.
   * For proper tool calling format detection, the user should select a model through the UI.
   */
  const checkModelStatus = async () => {
    try {
      const isLoaded = await RunAnywhere.isModelLoaded();
      console.warn('[ChatScreen] Text model loaded:', isLoaded);
      if (isLoaded) {
        // Model is loaded but we don't know which one - set placeholder
        // User should select a model through UI for proper format detection
        setCurrentModel({
          id: 'loaded-model',
          name: 'Loaded Model (select model for tool calling)',
          category: ModelCategory.Language,
          compatibleFrameworks: [LLMFramework.LlamaCpp],
          preferredFramework: LLMFramework.LlamaCpp,
          isDownloaded: true,
          isAvailable: true,
          supportsThinking: false,
        });
        // Register tools if model already loaded
        registerChatTools();
        const tools = RunAnywhere.getRegisteredTools();
        setRegisteredToolCount(tools.length);
        console.warn('[ChatScreen] Model loaded from previous session. For LFM2 tool calling, please select the model again.');
      }
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
   */
  const loadModel = async (model: SDKModelInfo) => {
    try {
      setIsModelLoading(true);
      console.warn(
        `[ChatScreen] Loading model: ${model.id} from ${model.localPath}`
      );

      if (!model.localPath) {
        Alert.alert(
          'Error',
          'Model path not found. Please re-download the model.'
        );
        return;
      }

      const success = await RunAnywhere.loadModel(model.localPath);

      if (success) {
        // Set the model info with actual ID and name for format detection
        const modelInfo = {
          id: model.id,
          name: model.name,
          category: ModelCategory.Language,
          compatibleFrameworks: [LLMFramework.LlamaCpp],
          preferredFramework: LLMFramework.LlamaCpp,
          isDownloaded: true,
          isAvailable: true,
          supportsThinking: false,
        };
        setCurrentModel(modelInfo);
        
        // Log model info for format detection debugging
        const format = detectToolCallFormat(model.id, model.name);
        console.warn(`[ChatScreen] Model loaded: id="${model.id}", name="${model.name}", detected format="${format}"`);
        
        // Register tools when model loads
        registerChatTools();
        const tools = RunAnywhere.getRegisteredTools();
        setRegisteredToolCount(tools.length);
        console.warn('[ChatScreen] Tools registered:', tools.length, 'tools');
      } else {
        const lastError = await RunAnywhere.getLastError();
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
   * Send a message using the real SDK with tool calling support
   * Uses RunAnywhere.generateWithTools() for AI that can take actions
   *
   * Example: "What's the weather in Tokyo?"
   * → LLM calls get_weather tool → Real API call → Final response
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

    // Create placeholder assistant message
    const assistantMessageId = generateId();
    const assistantMessage: Message = {
      id: assistantMessageId,
      role: MessageRole.Assistant,
      content: 'Thinking...',
      timestamp: new Date(),
    };
    await addMessage(assistantMessage, currentConversation.id);

    // Scroll to bottom
    setTimeout(() => {
      flatListRef.current?.scrollToEnd({ animated: true });
    }, 100);

    try {
      // Detect tool call format based on loaded model (matches iOS LLMViewModel+ToolCalling.swift)
      const format = detectToolCallFormat(currentModel?.id, currentModel?.name);
      console.log('[ChatScreen] Starting generation with tools for:', prompt, 'model:', currentModel?.id, 'format:', format);

      // Use tool-enabled generation
      // If the LLM needs to call a tool (like weather API), it happens automatically
      const result = await RunAnywhere.generateWithTools(prompt, {
        autoExecute: true,
        maxToolCalls: 3,
        maxTokens: 1000,
        temperature: 0.7,
        format: format,
      });

      // Log tool usage for debugging
      if (result.toolCalls.length > 0) {
        console.log('[ChatScreen] Tools used:', result.toolCalls.map(t => t.toolName));
        console.log('[ChatScreen] Tool results:', result.toolResults);
      }

      // Build final message content
      let finalContent = result.text || '(No response generated)';

      // Extract tool call info from result (matching iOS implementation)
      let toolCallInfo: ToolCallInfo | undefined;
      if (result.toolCalls.length > 0) {
        const lastToolCall = result.toolCalls[result.toolCalls.length - 1];
        const lastToolResult = result.toolResults[result.toolResults.length - 1];
        
        toolCallInfo = {
          toolName: lastToolCall.toolName,
          arguments: JSON.stringify(lastToolCall.arguments, null, 2),
          result: lastToolResult?.success 
            ? JSON.stringify(lastToolResult.result, null, 2)
            : undefined,
          success: lastToolResult?.success ?? false,
          error: lastToolResult?.error,
        };
        
        console.log('[ChatScreen] Created toolCallInfo:', toolCallInfo.toolName, 'success:', toolCallInfo.success);
      }

      // Update with final message
      const finalMessage: Message = {
        id: assistantMessageId,
        role: MessageRole.Assistant,
        content: finalContent,
        timestamp: new Date(),
        toolCallInfo, // Attach tool call info to message
        modelInfo: {
          modelId: currentModel?.id || 'unknown',
          modelName: currentModel?.name || 'Unknown Model',
          framework: 'llama.cpp',
          frameworkDisplayName: 'llama.cpp',
        },
        analytics: {
          totalGenerationTime: 0,
          inputTokens: Math.ceil(prompt.length / 4),
          outputTokens: Math.ceil(finalContent.length / 4),
          averageTokensPerSecond: 0,
          completionStatus: 'completed',
          wasThinkingMode: false,
          wasInterrupted: false,
          retryCount: 0,
        },
      };

      updateMessage(finalMessage, currentConversation.id);

      // Final scroll to bottom
      setTimeout(() => {
        flatListRef.current?.scrollToEnd({ animated: true });
      }, 100);
    } catch (error) {
      console.error('[ChatScreen] Generation error:', error);

      // Update the placeholder message with error
      updateMessage(
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
  }, [inputText, currentConversation, currentModel, addMessage, updateMessage]);

  /**
   * Create a new conversation (clears current chat)
   */
  const handleNewChat = useCallback(async () => {
    await createConversation();
  }, [createConversation]);

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
    <View style={styles.header}>
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
          modality={ModelModality.LLM}
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
    paddingVertical: Padding.padding12,
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
