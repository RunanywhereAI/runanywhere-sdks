/**
 * ChatScreen - Tab 0: Language Model Chat
 *
 * Reference: iOS Features/Chat/ChatInterfaceView.swift
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
import MockSDK from '../services/MockSDK';

// Generate unique ID
const generateId = () => Math.random().toString(36).substring(2, 15);

export const ChatScreen: React.FC = () => {
  // State
  const [messages, setMessages] = useState<Message[]>([]);
  const [inputText, setInputText] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [isModelLoading, setIsModelLoading] = useState(false);
  const [currentModel, setCurrentModel] = useState<ModelInfo | null>(null);

  // Refs
  const flatListRef = useRef<FlatList>(null);

  // Check for loaded model on mount
  useEffect(() => {
    const model = MockSDK.getCurrentLLMModel();
    setCurrentModel(model);
  }, []);

  /**
   * Handle model selection
   * TODO: Open ModelSelectionModal
   */
  const handleSelectModel = useCallback(async () => {
    // TODO: Replace with actual model selection modal
    Alert.alert(
      'Select Model',
      'Choose a language model',
      [
        {
          text: 'SmolLM2 360M',
          onPress: () => loadModel('smollm2-360m'),
        },
        {
          text: 'Qwen 2.5 0.5B',
          onPress: () => loadModel('qwen-2.5-0.5b'),
        },
        { text: 'Cancel', style: 'cancel' },
      ]
    );
  }, []);

  /**
   * Load a model
   * TODO: Replace with RunAnywhere.loadModel()
   */
  const loadModel = async (modelId: string) => {
    try {
      setIsModelLoading(true);
      await MockSDK.loadModel(modelId);
      const model = MockSDK.getCurrentLLMModel();
      setCurrentModel(model);
    } catch (error) {
      Alert.alert('Error', `Failed to load model: ${error}`);
    } finally {
      setIsModelLoading(false);
    }
  };

  /**
   * Send a message
   * TODO: Replace with RunAnywhere.generate() or RunAnywhere.generateStream()
   */
  const handleSend = useCallback(async () => {
    if (!inputText.trim() || !currentModel) return;

    const userMessage: Message = {
      id: generateId(),
      role: MessageRole.User,
      content: inputText.trim(),
      timestamp: new Date(),
    };

    // Add user message
    setMessages((prev) => [...prev, userMessage]);
    setInputText('');
    setIsLoading(true);

    // Scroll to bottom
    setTimeout(() => {
      flatListRef.current?.scrollToEnd({ animated: true });
    }, 100);

    try {
      // TODO: Replace with actual SDK call
      const result = await MockSDK.generate(inputText, {
        maxTokens: 1000,
        temperature: 0.7,
      });

      const assistantMessage: Message = {
        id: generateId(),
        role: MessageRole.Assistant,
        content: result.text,
        timestamp: new Date(),
        modelInfo: {
          modelId: currentModel.id,
          modelName: currentModel.name,
          framework: currentModel.preferredFramework?.toString() || 'Unknown',
          frameworkDisplayName:
            currentModel.preferredFramework
              ? (require('../types/model').FrameworkDisplayNames[currentModel.preferredFramework] || currentModel.preferredFramework)
              : 'Unknown',
        },
        analytics: {
          totalGenerationTime: result.latencyMs,
          inputTokens: inputText.split(' ').length,
          outputTokens: result.tokensUsed,
          averageTokensPerSecond: result.tokensPerSecond,
          completionStatus: 'completed',
          wasThinkingMode: false,
          wasInterrupted: false,
          retryCount: 0,
        },
      };

      setMessages((prev) => [...prev, assistantMessage]);

      // Scroll to bottom
      setTimeout(() => {
        flatListRef.current?.scrollToEnd({ animated: true });
      }, 100);
    } catch (error) {
      Alert.alert('Error', `Failed to generate response: ${error}`);
    } finally {
      setIsLoading(false);
    }
  }, [inputText, currentModel]);

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
