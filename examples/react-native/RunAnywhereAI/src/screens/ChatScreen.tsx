/**
 * ChatScreen - Tab 0: Language Model Chat
 *
 * Reference: iOS Features/Chat/ChatInterfaceView.swift
 *
 * Features:
 * - Conversation management (create, switch, delete)
 * - Streaming LLM text generation
 * - Message analytics
 * - Model selection
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
import { Spacing, Padding, BorderRadius, IconSize } from '../theme/spacing';
import { ModelStatusBanner, ModelRequiredOverlay } from '../components/common';
import { MessageBubble, TypingIndicator, ChatInput } from '../components/chat';
import { ChatAnalyticsScreen } from './ChatAnalyticsScreen';
import { ConversationListScreen } from './ConversationListScreen';
import { Message, MessageRole, Conversation } from '../types/chat';
import { ModelInfo, ModelModality, LLMFramework, ModelCategory } from '../types/model';
import { useConversationStore } from '../stores/conversationStore';
import { ModelSelectionSheet, ModelSelectionContext } from '../components/model';

// Import actual RunAnywhere SDK
import { RunAnywhere, type ModelInfo as SDKModelInfo } from 'runanywhere-react-native';

// Generate unique ID
const generateId = () => Math.random().toString(36).substring(2, 15);

export const ChatScreen: React.FC = () => {
  // Conversation store
  const {
    conversations,
    currentConversation,
    initialize: initializeStore,
    createConversation,
    setCurrentConversation,
    addMessage,
  } = useConversationStore();

  // Local state
  const [inputText, setInputText] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [isModelLoading, setIsModelLoading] = useState(false);
  const [currentModel, setCurrentModel] = useState<ModelInfo | null>(null);
  const [availableModels, setAvailableModels] = useState<SDKModelInfo[]>([]);
  const [showAnalytics, setShowAnalytics] = useState(false);
  const [showConversationList, setShowConversationList] = useState(false);
  const [showModelSelection, setShowModelSelection] = useState(false);
  const [isInitialized, setIsInitialized] = useState(false);

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
    } else if (isInitialized && !currentConversation && conversations.length > 0) {
      // Set most recent conversation as current
      setCurrentConversation(conversations[0] || null);
    }
  }, [isInitialized, conversations, currentConversation, createConversation, setCurrentConversation]);

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
      const llmModels = allModels.filter((m: SDKModelInfo) => m.category === ModelCategory.Language);
      setAvailableModels(llmModels);
      console.log('[ChatScreen] Available LLM models:', llmModels.map((m: SDKModelInfo) => `${m.id} (${m.isDownloaded ? 'downloaded' : 'not downloaded'})`));
    } catch (error) {
      console.log('[ChatScreen] Error loading models:', error);
    }
  };

  /**
   * Check if a model is loaded
   */
  const checkModelStatus = async () => {
    try {
      const isLoaded = await RunAnywhere.isTextModelLoaded();
      console.log('[ChatScreen] Text model loaded:', isLoaded);
      if (isLoaded) {
        setCurrentModel({
          id: 'loaded-model',
          name: 'Loaded Model',
          category: ModelCategory.Language,
          compatibleFrameworks: [LLMFramework.LlamaCpp],
          preferredFramework: LLMFramework.LlamaCpp,
          isDownloaded: true,
          isAvailable: true,
          supportsThinking: false,
        });
      }
    } catch (error) {
      console.log('[ChatScreen] Error checking model status:', error);
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
   * Enable demo mode - simulates having a loaded model
   */
  const enableDemoMode = () => {
    console.log('[ChatScreen] Enabling demo mode');
    setCurrentModel({
      id: 'demo-model',
      name: 'Demo Mode (Simulated)',
      category: ModelCategory.Language,
      compatibleFrameworks: [LLMFramework.LlamaCpp],
      preferredFramework: LLMFramework.LlamaCpp,
      isDownloaded: true,
      isAvailable: true,
      supportsThinking: false,
    });
  };

  /**
   * Load a model using the real SDK
   */
  const loadModel = async (model: SDKModelInfo) => {
    try {
      setIsModelLoading(true);
      console.log(`[ChatScreen] Loading model: ${model.id} from ${model.localPath}`);

      if (!model.localPath) {
        Alert.alert('Error', 'Model path not found. Please re-download the model.');
        return;
      }

      const success = await RunAnywhere.loadTextModel(model.localPath);

      if (success) {
        setCurrentModel({
          id: model.id,
          name: model.name,
          category: ModelCategory.Language,
          compatibleFrameworks: [LLMFramework.LlamaCpp],
          preferredFramework: LLMFramework.LlamaCpp,
          isDownloaded: true,
          isAvailable: true,
          supportsThinking: false,
        });
        console.log('[ChatScreen] Model loaded successfully');
      } else {
        const lastError = await RunAnywhere.getLastError();
        Alert.alert('Error', `Failed to load model: ${lastError || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('[ChatScreen] Error loading model:', error);
      Alert.alert('Error', `Failed to load model: ${error}`);
    } finally {
      setIsModelLoading(false);
    }
  };

  /**
   * Send a message using the real SDK
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

    // Scroll to bottom
    setTimeout(() => {
      flatListRef.current?.scrollToEnd({ animated: true });
    }, 100);

    try {
      console.log('[ChatScreen] Generating response for:', prompt);
      const isDemoMode = currentModel?.id === 'demo-model';

      let assistantMessage: Message;

      if (isDemoMode) {
        // Simulate a delay and provide a demo response
        await new Promise((resolve) => setTimeout(resolve, 1000));

        const demoResponses = [
          "I'm running in demo mode! To use real AI generation, you'll need to provide a GGUF model file. The RunAnywhere SDK supports LLM inference through the ONNX backend.",
          "This is a simulated response. The SDK is fully initialized and ready for real inference once you provide a model. Check the Settings tab for backend info!",
          "Demo mode is active. The RunAnywhere React Native SDK can perform on-device AI inference for STT, TTS, and LLM when models are available.",
        ];

        assistantMessage = {
          id: generateId(),
          role: MessageRole.Assistant,
          content: demoResponses[messages.length % demoResponses.length] || demoResponses[0]!,
          timestamp: new Date(),
          modelInfo: {
            modelId: 'demo',
            modelName: 'Demo Mode',
            framework: 'simulated',
            frameworkDisplayName: 'Simulated',
          },
          analytics: {
            totalGenerationTime: 1000,
            inputTokens: prompt.split(' ').length,
            outputTokens: 50,
            averageTokensPerSecond: 50,
            completionStatus: 'completed',
            wasThinkingMode: false,
            wasInterrupted: false,
            retryCount: 0,
          },
        };
      } else {
        // Use the real SDK generate method
        const result = await RunAnywhere.generate(prompt, {
          maxTokens: 1000,
          temperature: 0.7,
        });

        console.log('[ChatScreen] Generation result:', result);

        if (result.text?.includes('error')) {
          throw new Error(result.text);
        }

        assistantMessage = {
          id: generateId(),
          role: MessageRole.Assistant,
          content: result.text || '(No response generated)',
          timestamp: new Date(),
          modelInfo: {
            modelId: result.modelUsed || 'unknown',
            modelName: result.modelUsed || 'Unknown Model',
            framework: result.framework || 'llama.cpp',
            frameworkDisplayName: 'llama.cpp',
          },
          analytics: {
            totalGenerationTime: result.latencyMs,
            inputTokens: prompt.split(' ').length,
            outputTokens: result.tokensUsed,
            averageTokensPerSecond: result.performanceMetrics?.tokensPerSecond || 0,
            completionStatus: 'completed',
            wasThinkingMode: false,
            wasInterrupted: false,
            retryCount: 0,
          },
        };
      }

      // Add assistant message to conversation
      await addMessage(assistantMessage, currentConversation.id);

      // Scroll to bottom
      setTimeout(() => {
        flatListRef.current?.scrollToEnd({ animated: true });
      }, 100);
    } catch (error) {
      console.error('[ChatScreen] Generation error:', error);

      const errorMessage: Message = {
        id: generateId(),
        role: MessageRole.Assistant,
        content: `Error: ${error}\n\nThis likely means no LLM model is loaded. Use demo mode to test the interface, or provide a GGUF model.`,
        timestamp: new Date(),
      };
      await addMessage(errorMessage, currentConversation.id);
    } finally {
      setIsLoading(false);
    }
  }, [inputText, currentModel, currentConversation, addMessage, messages.length]);

  /**
   * Create a new conversation (clears current chat)
   */
  const handleNewChat = useCallback(async () => {
    await createConversation();
  }, [createConversation]);

  /**
   * Handle selecting a conversation from the list
   */
  const handleSelectConversation = useCallback((conversation: Conversation) => {
    setCurrentConversation(conversation);
  }, [setCurrentConversation]);

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
        <TouchableOpacity
          style={styles.headerButton}
          onPress={handleNewChat}
        >
          <Icon name="add" size={24} color={Colors.primaryBlue} />
        </TouchableOpacity>

        {/* Info button for chat analytics */}
        <TouchableOpacity
          style={[styles.headerButton, messages.length === 0 && styles.headerButtonDisabled]}
          onPress={handleShowAnalytics}
          disabled={messages.length === 0}
        >
          <Icon
            name="information-circle-outline"
            size={22}
            color={messages.length > 0 ? Colors.primaryBlue : Colors.textTertiary}
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
