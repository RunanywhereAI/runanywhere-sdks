/**
 * ChatScreen - Tab 0: Language Model Chat
 *
 * Reference: iOS Features/Chat/ChatInterfaceView.swift
 *
 * Now includes LLM models in the catalog (Qwen2, TinyLlama, SmolLM).
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
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding, BorderRadius, IconSize } from '../theme/spacing';
import { ModelStatusBanner, ModelRequiredOverlay } from '../components/common';
import { MessageBubble, TypingIndicator, ChatInput } from '../components/chat';
import { Message, MessageRole } from '../types/chat';
import { ModelInfo, ModelModality, LLMFramework, ModelCategory } from '../types/model';

// Import actual RunAnywhere SDK
import { RunAnywhere, type ModelInfo as SDKModelInfo } from 'runanywhere-react-native';

// Generate unique ID
const generateId = () => Math.random().toString(36).substring(2, 15);

export const ChatScreen: React.FC = () => {
  // State
  const [messages, setMessages] = useState<Message[]>([]);
  const [inputText, setInputText] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [isModelLoading, setIsModelLoading] = useState(false);
  const [currentModel, setCurrentModel] = useState<ModelInfo | null>(null);
  const [availableModels, setAvailableModels] = useState<SDKModelInfo[]>([]);
  const [backendInfo, setBackendInfo] = useState<Record<string, unknown>>({});

  // Refs
  const flatListRef = useRef<FlatList>(null);

  // Check for loaded model and backend info on mount
  useEffect(() => {
    checkModelStatus();
    loadBackendInfo();
    loadAvailableModels();
  }, []);

  /**
   * Load available LLM models from catalog
   */
  const loadAvailableModels = async () => {
    try {
      const allModels = await RunAnywhere.getAvailableModels();
      const llmModels = allModels.filter((m) => m.modality === 'llm');
      setAvailableModels(llmModels);
      console.log('[ChatScreen] Available LLM models:', llmModels.map(m => `${m.id}(${m.isDownloaded ? 'downloaded' : 'not downloaded'})`));
    } catch (error) {
      console.log('[ChatScreen] Error loading models:', error);
    }
  };

  /**
   * Load backend info
   */
  const loadBackendInfo = async () => {
    try {
      const info = await RunAnywhere.getBackendInfo();
      setBackendInfo(info);
      console.log('[ChatScreen] Backend info:', info);
    } catch (error) {
      console.log('[ChatScreen] Error getting backend info:', error);
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
        // Model is loaded - create a placeholder model info
        setCurrentModel({
          id: 'loaded-model',
          name: 'Loaded Model',
          category: ModelCategory.Language,
          compatibleFrameworks: [LLMFramework.LlamaCpp],
          preferredFramework: LLMFramework.LlamaCpp,
          isDownloaded: true,
          isAvailable: true,
        });
      }
    } catch (error) {
      console.log('[ChatScreen] Error checking model status:', error);
    }
  };

  /**
   * Handle model selection - shows available downloaded LLM models
   */
  const handleSelectModel = useCallback(async () => {
    // Get downloaded LLM models
    const downloadedModels = availableModels.filter((m) => m.isDownloaded);

    if (downloadedModels.length === 0) {
      // No downloaded LLM models, show info about available models
      Alert.alert(
        'Download an LLM Model',
        'Go to the Settings tab to download a language model.\n\n' +
          'Available models:\n' +
          '• SmolLM 135M (~150MB) - Fast responses\n' +
          '• Qwen2 0.5B (~400MB) - Balanced\n' +
          '• TinyLlama 1.1B (~670MB) - Best quality\n\n' +
          'Or use Demo Mode to test the interface.',
        [
          { text: 'Try Demo Mode', onPress: () => enableDemoMode() },
          { text: 'OK' },
        ]
      );
      return;
    }

    // Show available models
    const buttons: { text: string; onPress?: () => void; style?: string }[] = downloadedModels.map((model) => ({
      text: model.name,
      onPress: () => { loadModel(model); },
    }));
    buttons.push({ text: 'Demo Mode', onPress: enableDemoMode });
    buttons.push({ text: 'Cancel', style: 'cancel' });

    Alert.alert('Select LLM Model', 'Choose a downloaded language model', buttons as any);
  }, [availableModels]);

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
    if (!inputText.trim()) return;

    const userMessage: Message = {
      id: generateId(),
      role: MessageRole.User,
      content: inputText.trim(),
      timestamp: new Date(),
    };

    // Add user message
    setMessages((prev) => [...prev, userMessage]);
    const prompt = inputText.trim();
    setInputText('');
    setIsLoading(true);

    // Scroll to bottom
    setTimeout(() => {
      flatListRef.current?.scrollToEnd({ animated: true });
    }, 100);

    try {
      console.log('[ChatScreen] Generating response for:', prompt);

      // Check if we're in demo mode
      const isDemoMode = currentModel?.id === 'demo-model';

      if (isDemoMode) {
        // Simulate a delay and provide a demo response
        await new Promise((resolve) => setTimeout(resolve, 1000));

        const demoResponses = [
          "I'm running in demo mode! To use real AI generation, you'll need to provide a GGUF model file. The RunAnywhere SDK supports LLM inference through the ONNX backend.",
          "This is a simulated response. The SDK is fully initialized and ready for real inference once you provide a model. Check the Settings tab for backend info!",
          "Demo mode is active. The RunAnywhere React Native SDK can perform on-device AI inference for STT, TTS, and LLM when models are available.",
        ];

        const assistantMessage: Message = {
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

        setMessages((prev) => [...prev, assistantMessage]);
      } else {
        // Use the real SDK generate method
        const result = await RunAnywhere.generate(prompt, {
          maxTokens: 1000,
          temperature: 0.7,
        });

        console.log('[ChatScreen] Generation result:', result);

        // Check if there's an error in the result
        if (result.text?.includes('error')) {
          throw new Error(result.text);
        }

        const assistantMessage: Message = {
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

        setMessages((prev) => [...prev, assistantMessage]);
      }

      // Scroll to bottom
      setTimeout(() => {
        flatListRef.current?.scrollToEnd({ animated: true });
      }, 100);
    } catch (error) {
      console.error('[ChatScreen] Generation error:', error);

      // Add an error message to the chat
      const errorMessage: Message = {
        id: generateId(),
        role: MessageRole.Assistant,
        content: `Error: ${error}\n\nThis likely means no LLM model is loaded. Use demo mode to test the interface, or provide a GGUF model.`,
        timestamp: new Date(),
      };
      setMessages((prev) => [...prev, errorMessage]);
    } finally {
      setIsLoading(false);
    }
  }, [inputText, currentModel, messages.length]);

  /**
   * Clear chat
   */
  const handleClearChat = useCallback(() => {
    Alert.alert(
      'Clear Chat',
      'Are you sure you want to clear all messages?',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Clear',
          style: 'destructive',
          onPress: () => setMessages([]),
        },
      ]
    );
  }, []);

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
   * Render header with actions
   */
  const renderHeader = () => (
    <View style={styles.header}>
      <Text style={styles.title}>Chat</Text>
      <View style={styles.headerActions}>
        {messages.length > 0 && (
          <TouchableOpacity
            style={styles.headerButton}
            onPress={handleClearChat}
          >
            <Icon name="trash-outline" size={22} color={Colors.primaryRed} />
          </TouchableOpacity>
        )}
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
        disabled={!currentModel}
        isLoading={isLoading}
        placeholder={
          currentModel
            ? 'Type a message...'
            : 'Select a model to start chatting'
        }
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
  title: {
    ...Typography.title2,
    color: Colors.textPrimary,
  },
  headerActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.medium,
  },
  headerButton: {
    padding: Spacing.small,
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
