import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Alert,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { FlashList } from '@shopify/flash-list';
import type { FlashListRef } from '@shopify/flash-list';
import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { AppIcon } from '../components/common/AppIcon';
import { useTheme } from '../theme';
import { Typography } from '../theme/typography';
import { IconSize, Padding, Spacing } from '../theme/spacing';
import type { ThemeColors } from '../theme/colors';
import { ModelRequiredOverlay, ModelStatusBanner } from '../components/common';
import {
  ChatInput,
  MessageBubble,
  ToolCallingBadge,
  TypingIndicator,
} from '../components/chat';
import type { Message, ToolCallInfo } from '../types/chat';
import { MessageRole } from '../types/chat';
import type { ModelInfo } from '../types/model';
import { LLMFramework, ModelCategory, ModelModality } from '../types/model';
import { useConversationStore } from '../stores/conversationStore';
import {
  ModelSelectionContext,
  ModelSelectionSheet,
} from '../components/model';
import { GENERATION_SETTINGS_KEYS } from '../types/settings';
import {
  RunAnywhere,
  type GenerationOptions,
  type ModelInfo as SDKModelInfo,
} from '@runanywhere/core';
import { safeEvaluateExpression } from '../utils/mathParser';
import type { RootStackParamList } from '../types';

type ChatNavigationProp = NativeStackNavigationProp<RootStackParamList>;

const generateId = () =>
  `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;

const detectToolCallFormat = (
  modelId: string | undefined,
  modelName: string | undefined
): string => {
  const lowerId = modelId?.toLowerCase() ?? '';
  const lowerName = modelName?.toLowerCase() ?? '';
  if (
    (lowerId.includes('lfm2') && lowerId.includes('tool')) ||
    (lowerName.includes('lfm2') && lowerName.includes('tool'))
  ) {
    return 'lfm2';
  }
  return 'default';
};

const registerChatTools = () => {
  RunAnywhere.clearTools();

  RunAnywhere.registerTool(
    {
      name: 'get_weather',
      description: 'Gets the current weather for a city or location',
      parameters: [
        {
          name: 'location',
          type: 'string',
          description: 'City name or location (e.g., "Tokyo", "New York")',
          required: true,
        },
      ],
    },
    async (args) => {
      const location = (args.location || args.city) as string;
      try {
        const url = `https://wttr.in/${encodeURIComponent(location)}?format=j1`;
        const response = await fetch(url);
        if (!response.ok) return { error: `Weather API error: ${response.status}` };
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
        return { error: error instanceof Error ? error.message : String(error) };
      }
    }
  );

  RunAnywhere.registerTool(
    {
      name: 'get_current_time',
      description: 'Gets the current date and time',
      parameters: [],
    },
    async () => {
      const now = new Date();
      return {
        date: now.toLocaleDateString(),
        time: now.toLocaleTimeString(),
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      };
    }
  );

  RunAnywhere.registerTool(
    {
      name: 'calculate',
      description: 'Performs math calculations. Supports +, -, *, / and parentheses',
      parameters: [
        {
          name: 'expression',
          type: 'string',
          description: 'Math expression (e.g., "2 + 2 * 3")',
          required: true,
        },
      ],
    },
    async (args) => {
      const expression = (args.expression || args.input) as string;
      try {
        const result = safeEvaluateExpression(expression);
        return { expression, result };
      } catch (error) {
        return {
          error:
            error instanceof Error
              ? `Failed to calculate: ${error.message}`
              : 'Failed to calculate',
        };
      }
    }
  );
};

async function readGenerationOptions(): Promise<GenerationOptions> {
  const [tempStr, maxStr, sysStr] = await Promise.all([
    AsyncStorage.getItem(GENERATION_SETTINGS_KEYS.TEMPERATURE),
    AsyncStorage.getItem(GENERATION_SETTINGS_KEYS.MAX_TOKENS),
    AsyncStorage.getItem(GENERATION_SETTINGS_KEYS.SYSTEM_PROMPT),
  ]);
  const temperature =
    tempStr !== null && !Number.isNaN(parseFloat(tempStr))
      ? parseFloat(tempStr)
      : 0.7;
  const maxTokens = maxStr ? parseInt(maxStr, 10) : 1000;
  const systemPrompt = sysStr && sysStr.trim() !== '' ? sysStr : undefined;
  return { temperature, maxTokens, systemPrompt };
}

const renderItem = ({ item }: { item: Message }) => (
  <MessageBubble message={item} />
);

export const ChatScreen: React.FC = () => {
  const { colors } = useTheme();
  const navigation = useNavigation<ChatNavigationProp>();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const {
    conversations,
    currentConversation,
    initialize: initializeStore,
    createConversation,
    setCurrentConversation,
    addMessage,
    updateMessage,
  } = useConversationStore();

  const [inputText, setInputText] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [isModelLoading, setIsModelLoading] = useState(false);
  const [currentModel, setCurrentModel] = useState<ModelInfo | null>(null);
  const [showModelSelection, setShowModelSelection] = useState(false);
  const [isInitialized, setIsInitialized] = useState(false);
  const [registeredToolCount, setRegisteredToolCount] = useState(0);

  const listRef = useRef<FlashListRef<Message>>(null);

  useEffect(() => {
    initializeStore().finally(() => setIsInitialized(true));
  }, [initializeStore]);

  useEffect(() => {
    if (!isInitialized) return;
    if (conversations.length === 0 && !currentConversation) {
      createConversation();
    } else if (!currentConversation && conversations.length > 0) {
      setCurrentConversation(conversations[0] || null);
    }
  }, [
    isInitialized,
    conversations,
    currentConversation,
    createConversation,
    setCurrentConversation,
  ]);

  const checkModelStatus = useCallback(async () => {
    try {
      const isLoaded = await RunAnywhere.isModelLoaded();
      if (isLoaded) {
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
        registerChatTools();
        setRegisteredToolCount(RunAnywhere.getRegisteredTools().length);
      }
    } catch (error) {
      console.warn('[ChatScreen] model-status check failed', error);
    }
  }, []);

  useEffect(() => {
    checkModelStatus();
  }, [checkModelStatus]);

  const messages = currentConversation?.messages ?? [];

  const handleSelectModel = useCallback(() => {
    setShowModelSelection(true);
  }, []);

  const loadModel = useCallback(async (model: SDKModelInfo) => {
    try {
      setIsModelLoading(true);
      if (!model.localPath) {
        Alert.alert('Error', 'Model path not found. Please re-download the model.');
        return;
      }
      const success = await RunAnywhere.loadModel(model.localPath);
      if (!success) {
        const lastError = await RunAnywhere.getLastError();
        Alert.alert('Error', `Failed to load model: ${lastError || 'Unknown error'}`);
        return;
      }
      const fw =
        (model.preferredFramework as unknown as LLMFramework) ??
        LLMFramework.LlamaCpp;
      setCurrentModel({
        id: model.id,
        name: model.name,
        category: ModelCategory.Language,
        compatibleFrameworks:
          (model.compatibleFrameworks as unknown as LLMFramework[]) ?? [fw],
        preferredFramework: fw,
        isDownloaded: true,
        isAvailable: true,
        supportsThinking: false,
      });
      registerChatTools();
      setRegisteredToolCount(RunAnywhere.getRegisteredTools().length);
    } catch (error) {
      console.error('[ChatScreen] loadModel failed', error);
      Alert.alert('Error', `Failed to load model: ${error}`);
    } finally {
      setIsModelLoading(false);
    }
  }, []);

  const handleModelSelected = useCallback(
    async (model: SDKModelInfo) => {
      setShowModelSelection(false);
      await loadModel(model);
    },
    [loadModel]
  );

  const handleSend = useCallback(async () => {
    if (!inputText.trim() || !currentConversation) return;

    const userMessage: Message = {
      id: generateId(),
      role: MessageRole.User,
      content: inputText.trim(),
      timestamp: new Date(),
    };
    await addMessage(userMessage, currentConversation.id);
    const prompt = inputText.trim();
    setInputText('');
    setIsLoading(true);

    const assistantMessageId = generateId();
    await addMessage(
      {
        id: assistantMessageId,
        role: MessageRole.Assistant,
        content: 'Thinking…',
        timestamp: new Date(),
      },
      currentConversation.id
    );
    setTimeout(() => listRef.current?.scrollToEnd({ animated: true }), 100);

    try {
      const format = detectToolCallFormat(currentModel?.id, currentModel?.name);
      const options = await readGenerationOptions();
      const result = await RunAnywhere.generateWithTools(prompt, {
        autoExecute: true,
        maxToolCalls: 3,
        maxTokens: options.maxTokens,
        temperature: options.temperature,
        systemPrompt: options.systemPrompt,
        format,
      });

      const finalContent = result.text || '(No response generated)';
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
      }

      updateMessage(
        {
          id: assistantMessageId,
          role: MessageRole.Assistant,
          content: finalContent,
          timestamp: new Date(),
          toolCallInfo,
          modelInfo: {
            modelId: currentModel?.id || 'unknown',
            modelName: currentModel?.name || 'Unknown Model',
            framework: currentModel?.preferredFramework || 'unknown',
            frameworkDisplayName: currentModel?.preferredFramework || 'unknown',
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
        },
        currentConversation.id
      );
      setTimeout(() => listRef.current?.scrollToEnd({ animated: true }), 100);
    } catch (error) {
      console.error('[ChatScreen] generate failed', error);
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

  const handleNewChat = useCallback(() => {
    createConversation();
  }, [createConversation]);

  const handleShowAnalytics = useCallback(() => {
    navigation.navigate('ChatAnalytics');
  }, [navigation]);

  const handleShowConversations = useCallback(() => {
    navigation.navigate('ConversationList');
  }, [navigation]);

  const headerView = (
    <View style={styles.header}>
      <TouchableOpacity
        style={styles.headerButton}
        onPress={handleShowConversations}
        hitSlop={8}
      >
        <AppIcon name="list" size={22} color={colors.primary} />
      </TouchableOpacity>
      <View style={styles.titleContainer}>
        <Text style={[Typography.title2, { color: colors.text }]}>Chat</Text>
        {conversations.length > 1 ? (
          <Text style={[Typography.caption2, { color: colors.textTertiary }]}>
            {conversations.length} conversations
          </Text>
        ) : null}
      </View>
      <View style={styles.headerActions}>
        <TouchableOpacity
          style={styles.headerButton}
          onPress={handleNewChat}
          hitSlop={8}
        >
          <AppIcon name="add" size={24} color={colors.primary} />
        </TouchableOpacity>
        <TouchableOpacity
          style={[
            styles.headerButton,
            messages.length === 0 && styles.headerButtonDisabled,
          ]}
          onPress={handleShowAnalytics}
          disabled={messages.length === 0}
          hitSlop={8}
        >
          <AppIcon
            name="information-circle-outline"
            size={22}
            color={messages.length > 0 ? colors.primary : colors.textTertiary}
          />
        </TouchableOpacity>
      </View>
    </View>
  );

  if (!currentModel && !isModelLoading) {
    return (
      <SafeAreaView
        edges={['top']}
        style={[styles.container, { backgroundColor: colors.background }]}
      >
        {headerView}
        <ModelRequiredOverlay
          modality={ModelModality.LLM}
          onSelectModel={handleSelectModel}
        />
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
    <SafeAreaView
      edges={['top']}
      style={[styles.container, { backgroundColor: colors.background }]}
    >
      {headerView}
      <ModelStatusBanner
        modelName={currentModel?.name}
        framework={currentModel?.preferredFramework}
        isLoading={isModelLoading}
        onSelectModel={handleSelectModel}
      />
      <FlashList
        ref={listRef}
        data={messages}
        renderItem={renderItem}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.messagesList}
        showsVerticalScrollIndicator={false}
        ListEmptyComponent={
          <View style={styles.emptyState}>
            <View
              style={[
                styles.emptyIconContainer,
                { backgroundColor: colors.primarySoft },
              ]}
            >
              <AppIcon
                name="chatbubble-ellipses-outline"
                size={IconSize.large}
                color={colors.primary}
              />
            </View>
            <Text style={[Typography.title3, { color: colors.text }]}>
              Start a conversation
            </Text>
            <Text
              style={[
                Typography.body,
                styles.emptySubtitle,
                { color: colors.textSecondary },
              ]}
            >
              Type a message below to begin chatting with the AI
            </Text>
          </View>
        }
      />
      {isLoading ? <TypingIndicator /> : null}
      {currentModel && registeredToolCount > 0 ? (
        <ToolCallingBadge toolCount={registeredToolCount} />
      ) : null}
      <ChatInput
        value={inputText}
        onChangeText={setInputText}
        onSend={handleSend}
        disabled={!currentModel || !currentConversation}
        isLoading={isLoading}
        placeholder={
          currentModel ? 'Type a message…' : 'Select a model to start chatting'
        }
      />
      <ModelSelectionSheet
        visible={showModelSelection}
        context={ModelSelectionContext.LLM}
        onClose={() => setShowModelSelection(false)}
        onModelSelected={handleModelSelected}
      />
    </SafeAreaView>
  );
};

const createStyles = (colors: ThemeColors) =>
  StyleSheet.create({
    container: { flex: 1 },
    header: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      paddingHorizontal: Padding.padding16,
      paddingVertical: Padding.padding12,
      borderBottomWidth: StyleSheet.hairlineWidth,
      borderBottomColor: colors.border,
    },
    titleContainer: { alignItems: 'center' },
    headerActions: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: Spacing.small,
    },
    headerButton: { padding: Spacing.small },
    headerButtonDisabled: { opacity: 0.5 },
    messagesList: {
      paddingVertical: Spacing.medium,
    },
    emptyState: {
      alignItems: 'center',
      padding: Padding.padding40,
    },
    emptyIconContainer: {
      width: 84,
      height: 84,
      borderRadius: 42,
      justifyContent: 'center',
      alignItems: 'center',
      marginBottom: Spacing.large,
    },
    emptySubtitle: {
      textAlign: 'center',
      maxWidth: 280,
      marginTop: Spacing.small,
    },
  });

export default ChatScreen;
