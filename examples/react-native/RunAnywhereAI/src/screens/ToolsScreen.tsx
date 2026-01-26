/**
 * ToolsScreen - Tab 5: Tool Calling Demo
 *
 * Demonstrates the SDK's tool calling capabilities with a transparent,
 * educational view of how tools work.
 *
 * Features:
 * - List of registered tools
 * - Test input for trying tool-enabled queries
 * - Step-by-step execution log showing the entire flow
 * - Model status banner
 */

import React, { useState, useCallback, useEffect, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  SafeAreaView,
  TouchableOpacity,
  ScrollView,
  TextInput,
  ActivityIndicator,
  Alert,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { useFocusEffect } from '@react-navigation/native';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding, BorderRadius } from '../theme/spacing';
import { ModelStatusBanner } from '../components/common';
import {
  ModelSelectionSheet,
  ModelSelectionContext,
} from '../components/model';
import { LLMFramework } from '../types/model';

// Import RunAnywhere SDK
import {
  RunAnywhere,
  type ModelInfo as SDKModelInfo,
  type ToolDefinition,
} from '@runanywhere/core';

// =============================================================================
// Types
// =============================================================================

interface ExecutionStep {
  id: string;
  type: 'user' | 'llm_raw' | 'tool_call' | 'tool_exec' | 'tool_result' | 'final';
  title: string;
  content: string;
  timestamp: Date;
  icon: string;
  color: string;
}

interface LoadedModelState {
  id: string;
  name: string;
  framework: LLMFramework;
}

// =============================================================================
// Tool Registration (same as ChatScreen for demo purposes)
// =============================================================================

const registerDemoTools = () => {
  // Clear any existing tools first
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
          condition: current.weatherDesc?.[0]?.value || 'Unknown',
          humidity: parseInt(current.humidity, 10),
          wind_mph: parseInt(current.windspeedMiles, 10),
          feels_like_f: parseInt(current.FeelsLikeF, 10),
        };
      } catch (error) {
        console.error('[Tool] Weather fetch error:', error);
        return { error: 'Failed to fetch weather data' };
      }
    }
  );

  // Time tool - Local time
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

  console.log('[ToolsScreen] Demo tools registered: get_weather, get_current_time');
};

// =============================================================================
// Main Component
// =============================================================================

export const ToolsScreen: React.FC = () => {
  // State
  const [inputText, setInputText] = useState('');
  const [isProcessing, setIsProcessing] = useState(false);
  const [executionSteps, setExecutionSteps] = useState<ExecutionStep[]>([]);
  const [registeredTools, setRegisteredTools] = useState<ToolDefinition[]>([]);
  const [loadedModel, setLoadedModel] = useState<LoadedModelState | null>(null);
  const [isModelLoading, setIsModelLoading] = useState(false);
  const [showModelSelection, setShowModelSelection] = useState(false);

  const scrollViewRef = useRef<ScrollView>(null);

  // =============================================================================
  // Initialize tools on mount
  // =============================================================================

  useEffect(() => {
    registerDemoTools();
    refreshToolsList();
  }, []);

  // Refresh tools list when screen is focused
  useFocusEffect(
    useCallback(() => {
      refreshToolsList();
      checkCurrentModel();
    }, [])
  );

  const refreshToolsList = () => {
    const tools = RunAnywhere.getRegisteredTools();
    setRegisteredTools(tools);
  };

  const checkCurrentModel = async () => {
    try {
      const isLoaded = await RunAnywhere.isModelLoaded();
      if (isLoaded) {
        // If a model is loaded, set a placeholder state
        // The actual model name will be shown from the banner
        setLoadedModel({
          id: 'loaded-model',
          name: 'Loaded Model',
          framework: LLMFramework.LlamaCpp,
        });
      } else {
        setLoadedModel(null);
      }
    } catch (error) {
      console.error('[ToolsScreen] Error checking model status:', error);
    }
  };

  // =============================================================================
  // Add execution step
  // =============================================================================

  const addStep = useCallback(
    (
      type: ExecutionStep['type'],
      title: string,
      content: string,
      icon: string,
      color: string
    ) => {
      const step: ExecutionStep = {
        id: `step_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
        type,
        title,
        content,
        timestamp: new Date(),
        icon,
        color,
      };
      setExecutionSteps((prev) => [...prev, step]);

      // Scroll to bottom
      setTimeout(() => {
        scrollViewRef.current?.scrollToEnd({ animated: true });
      }, 100);
    },
    []
  );

  // =============================================================================
  // Handle test query
  // =============================================================================

  const handleTestQuery = useCallback(async () => {
    if (!inputText.trim()) {
      Alert.alert('Empty Input', 'Please enter a query to test tool calling.');
      return;
    }

    if (!loadedModel) {
      Alert.alert('No Model', 'Please load an LLM model first.');
      return;
    }

    setIsProcessing(true);
    setExecutionSteps([]); // Clear previous steps

    const query = inputText.trim();
    setInputText('');

    try {
      // Step 1: User Input
      addStep('user', '1. User Query', query, 'person', Colors.primaryBlue);

      // Step 2: Show registered tools
      const toolsList = registeredTools
        .map((t) => `• ${t.name}: ${t.description}`)
        .join('\n');
      addStep(
        'llm_raw',
        '2. Available Tools',
        `LLM sees these tools:\n\n${toolsList}`,
        'construct',
        Colors.primaryPurple
      );

      // Step 3: Generate with tools
      addStep(
        'llm_raw',
        '3. Generating...',
        'Waiting for LLM response...',
        'hourglass',
        Colors.textSecondary
      );

      const result = await RunAnywhere.generateWithTools(query, {
        maxToolCalls: 3,
        temperature: 0.7,
      });

      // Remove "Generating..." step and add actual results
      setExecutionSteps((prev) => prev.filter((s) => s.title !== '3. Generating...'));

      // If there were tool calls, show them
      if (result.toolCalls && result.toolCalls.length > 0) {
        for (let i = 0; i < result.toolCalls.length; i++) {
          const tc = result.toolCalls[i];
          const tr = result.toolResults?.[i];

          // Tool Call
          addStep(
            'tool_call',
            '3. Tool Call Detected',
            `<tool_call>\n${JSON.stringify(
              { tool: tc.toolName, arguments: tc.arguments },
              null,
              2
            )}\n</tool_call>`,
            'code-slash',
            Colors.primaryOrange
          );

          // Tool Execution
          addStep(
            'tool_exec',
            `4. Executing: ${tc.toolName}()`,
            `Arguments: ${JSON.stringify(tc.arguments, null, 2)}`,
            'flash',
            Colors.primaryGreen
          );

          // Tool Result
          if (tr) {
            const resultContent = tr.success
              ? JSON.stringify(tr.result, null, 2)
              : `Error: ${tr.error}`;
            addStep(
              'tool_result',
              '5. Tool Result',
              resultContent,
              tr.success ? 'checkmark-circle' : 'alert-circle',
              tr.success ? Colors.statusGreen : Colors.statusRed
            );
          }
        }
      } else {
        // No tool call
        addStep(
          'llm_raw',
          '3. No Tool Call',
          'LLM responded directly without using any tools',
          'information-circle',
          Colors.textSecondary
        );
      }

      // Final Response
      addStep(
        'final',
        `${result.toolCalls?.length ? '6' : '4'}. Final Response`,
        result.text || '(No text response)',
        'chatbubble-ellipses',
        Colors.primaryBlue
      );
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      addStep('final', 'Error', errorMessage, 'alert-circle', Colors.statusRed);
    } finally {
      setIsProcessing(false);
    }
  }, [inputText, loadedModel, registeredTools, addStep]);

  // =============================================================================
  // Clear log
  // =============================================================================

  const handleClearLog = useCallback(() => {
    setExecutionSteps([]);
  }, []);

  // =============================================================================
  // Model selection
  // =============================================================================

  const handleModelSelect = useCallback(async (model: SDKModelInfo) => {
    setIsModelLoading(true);
    try {
      // Unload current model if any
      await RunAnywhere.unloadModel();

      // Load new model
      await RunAnywhere.loadModel(model.id);
      setLoadedModel({
        id: model.id,
        name: model.name,
        framework: LLMFramework.LlamaCpp,
      });
    } catch (error) {
      console.error('[ToolsScreen] Model load error:', error);
      Alert.alert('Error', `Failed to load model: ${error}`);
    } finally {
      setIsModelLoading(false);
      setShowModelSelection(false);
    }
  }, []);

  // =============================================================================
  // Render
  // =============================================================================

  return (
    <SafeAreaView style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.title}>🔧 Tool Calling Demo</Text>
        <Text style={styles.subtitle}>
          See how LLMs use external tools step-by-step
        </Text>
      </View>

      {/* Model Banner */}
      <ModelStatusBanner
        modelName={loadedModel?.name}
        framework={loadedModel?.framework}
        isLoading={isModelLoading}
        onSelectModel={() => setShowModelSelection(true)}
        placeholder="Select an LLM model"
      />

      {/* Registered Tools Section */}
      <View style={styles.toolsSection}>
        <View style={styles.sectionHeader}>
          <Icon name="construct-outline" size={20} color={Colors.textPrimary} />
          <Text style={styles.sectionTitle}>Registered Tools</Text>
          <Text style={styles.toolCount}>{registeredTools.length}</Text>
        </View>
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.toolsScroll}
        >
          {registeredTools.map((tool) => (
            <View key={tool.name} style={styles.toolCard}>
              <Icon
                name={tool.name === 'get_weather' ? 'cloud-outline' : 'time-outline'}
                size={24}
                color={Colors.primaryBlue}
              />
              <Text style={styles.toolName}>{tool.name}</Text>
              <Text style={styles.toolDesc} numberOfLines={2}>
                {tool.description}
              </Text>
            </View>
          ))}
        </ScrollView>
      </View>

      {/* Input Section */}
      <View style={styles.inputSection}>
        <View style={styles.inputContainer}>
          <TextInput
            style={styles.input}
            placeholder="Try: 'What's the weather in Tokyo?'"
            placeholderTextColor={Colors.textTertiary}
            value={inputText}
            onChangeText={setInputText}
            editable={!isProcessing && !!loadedModel}
            returnKeyType="send"
            onSubmitEditing={handleTestQuery}
          />
          <TouchableOpacity
            style={[
              styles.sendButton,
              (!inputText.trim() || isProcessing || !loadedModel) &&
                styles.sendButtonDisabled,
            ]}
            onPress={handleTestQuery}
            disabled={!inputText.trim() || isProcessing || !loadedModel}
          >
            {isProcessing ? (
              <ActivityIndicator size="small" color={Colors.textWhite} />
            ) : (
              <Icon name="arrow-up" size={20} color={Colors.textWhite} />
            )}
          </TouchableOpacity>
        </View>
      </View>

      {/* Execution Log Section */}
      <View style={styles.logSection}>
        <View style={styles.logHeader}>
          <Icon name="list-outline" size={20} color={Colors.textPrimary} />
          <Text style={styles.sectionTitle}>Execution Log</Text>
          {executionSteps.length > 0 && (
            <TouchableOpacity onPress={handleClearLog} style={styles.clearButton}>
              <Icon name="trash-outline" size={16} color={Colors.textSecondary} />
              <Text style={styles.clearText}>Clear</Text>
            </TouchableOpacity>
          )}
        </View>

        <ScrollView
          ref={scrollViewRef}
          style={styles.logScroll}
          contentContainerStyle={styles.logContent}
        >
          {executionSteps.length === 0 ? (
            <View style={styles.emptyLog}>
              <Icon
                name="document-text-outline"
                size={48}
                color={Colors.textTertiary}
              />
              <Text style={styles.emptyText}>
                Enter a query above to see the tool calling flow
              </Text>
              <Text style={styles.emptyHint}>
                Try: "What's the weather in Paris?" or "What time is it?"
              </Text>
            </View>
          ) : (
            executionSteps.map((step) => (
              <View key={step.id} style={styles.stepCard}>
                <View style={[styles.stepIcon, { backgroundColor: step.color + '20' }]}>
                  <Icon name={step.icon} size={16} color={step.color} />
                </View>
                <View style={styles.stepContent}>
                  <Text style={styles.stepTitle}>{step.title}</Text>
                  <Text style={styles.stepText}>{step.content}</Text>
                  <Text style={styles.stepTime}>
                    {step.timestamp.toLocaleTimeString()}
                  </Text>
                </View>
              </View>
            ))
          )}
        </ScrollView>
      </View>

      {/* Model Selection Sheet */}
      <ModelSelectionSheet
        visible={showModelSelection}
        onClose={() => setShowModelSelection(false)}
        onModelSelected={handleModelSelect}
        context={ModelSelectionContext.LLM}
      />
    </SafeAreaView>
  );
};

// =============================================================================
// Styles
// =============================================================================

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.backgroundSecondary,
  },
  header: {
    padding: Padding.padding16,
    backgroundColor: Colors.backgroundPrimary,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  title: {
    ...Typography.title2,
    color: Colors.textPrimary,
  },
  subtitle: {
    ...Typography.caption,
    color: Colors.textSecondary,
    marginTop: 4,
  },

  // Tools Section
  toolsSection: {
    backgroundColor: Colors.backgroundPrimary,
    paddingVertical: Padding.padding8,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: Padding.padding16,
    marginBottom: Spacing.small,
  },
  sectionTitle: {
    ...Typography.headline,
    color: Colors.textPrimary,
    marginLeft: Spacing.small,
    flex: 1,
  },
  toolCount: {
    ...Typography.caption,
    color: Colors.textSecondary,
    backgroundColor: Colors.badgeGray,
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 10,
  },
  toolsScroll: {
    paddingHorizontal: Padding.padding16,
  },
  toolCard: {
    backgroundColor: Colors.backgroundSecondary,
    padding: Padding.padding8,
    borderRadius: BorderRadius.medium,
    marginRight: Spacing.small,
    width: 140,
    alignItems: 'center',
  },
  toolName: {
    ...Typography.subheadline,
    color: Colors.textPrimary,
    marginTop: Spacing.xSmall,
    fontWeight: '600',
  },
  toolDesc: {
    ...Typography.caption2,
    color: Colors.textSecondary,
    textAlign: 'center',
    marginTop: 2,
  },

  // Input Section
  inputSection: {
    backgroundColor: Colors.backgroundPrimary,
    padding: Padding.padding16,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  inputContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.backgroundSecondary,
    borderRadius: BorderRadius.large,
    paddingHorizontal: Padding.padding8,
  },
  input: {
    flex: 1,
    ...Typography.body,
    color: Colors.textPrimary,
    paddingVertical: 12,
    paddingHorizontal: Spacing.small,
  },
  sendButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: Colors.primaryBlue,
    justifyContent: 'center',
    alignItems: 'center',
  },
  sendButtonDisabled: {
    backgroundColor: Colors.textTertiary,
  },

  // Log Section
  logSection: {
    flex: 1,
    backgroundColor: Colors.backgroundPrimary,
  },
  logHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding8,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  clearButton: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: Spacing.xSmall,
  },
  clearText: {
    ...Typography.caption,
    color: Colors.textSecondary,
    marginLeft: 4,
  },
  logScroll: {
    flex: 1,
  },
  logContent: {
    padding: Padding.padding16,
  },
  emptyLog: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 60,
  },
  emptyText: {
    ...Typography.body,
    color: Colors.textSecondary,
    marginTop: Spacing.medium,
    textAlign: 'center',
  },
  emptyHint: {
    ...Typography.caption,
    color: Colors.textTertiary,
    marginTop: Spacing.small,
    textAlign: 'center',
  },

  // Step Card
  stepCard: {
    flexDirection: 'row',
    backgroundColor: Colors.backgroundSecondary,
    padding: Padding.padding8,
    borderRadius: BorderRadius.medium,
    marginBottom: Spacing.small,
  },
  stepIcon: {
    width: 32,
    height: 32,
    borderRadius: 16,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: Spacing.small,
  },
  stepContent: {
    flex: 1,
  },
  stepTitle: {
    ...Typography.subheadline,
    color: Colors.textPrimary,
    fontWeight: '600',
  },
  stepText: {
    ...Typography.caption,
    color: Colors.textSecondary,
    marginTop: 4,
    fontFamily: 'Menlo',
  },
  stepTime: {
    ...Typography.caption2,
    color: Colors.textTertiary,
    marginTop: 4,
  },
});

export default ToolsScreen;
