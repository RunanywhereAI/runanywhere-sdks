/**
 * VoiceAssistantScreen - Tab 3: Voice Assistant
 *
 * Complete voice AI pipeline combining speech recognition, language model, and synthesis.
 * Uses the SDK's VoiceSession API which handles all the complexity internally:
 * - Audio capture with VAD (Voice Activity Detection)
 * - Automatic speech end detection
 * - STT → LLM → TTS pipeline
 * - Audio playback
 *
 * Reference: iOS examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Voice/VoiceAssistantView.swift
 */

import React, { useState, useCallback, useEffect, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  SafeAreaView,
  TouchableOpacity,
  ScrollView,
  Alert,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding, BorderRadius } from '../theme/spacing';
import {
  ModelSelectionSheet,
  ModelSelectionContext,
} from '../components/model';
import type { ModelInfo } from '../types/model';
import { LLMFramework } from '../types/model';
import type { VoiceConversationEntry } from '../types/voice';
import { VoicePipelineStatus } from '../types/voice';

// Import RunAnywhere SDK
import {
  RunAnywhere,
  type ModelInfo as SDKModelInfo,
  type VoiceSessionHandle,
  type VoiceSessionEvent,
} from '@runanywhere/core';

// Generate unique ID
const generateId = () => Math.random().toString(36).substring(2, 15);

export const VoiceAssistantScreen: React.FC = () => {
  // Model states
  const [sttModel, setSTTModel] = useState<ModelInfo | null>(null);
  const [llmModel, setLLMModel] = useState<ModelInfo | null>(null);
  const [ttsModel, setTTSModel] = useState<ModelInfo | null>(null);
  const [_availableModels, setAvailableModels] = useState<SDKModelInfo[]>([]);

  // Session state
  const [status, setStatus] = useState<VoicePipelineStatus>(VoicePipelineStatus.Idle);
  const [conversation, setConversation] = useState<VoiceConversationEntry[]>([]);
  const [audioLevel, setAudioLevel] = useState(0);
  const [isSessionActive, setIsSessionActive] = useState(false);
  const [showModelInfo, setShowModelInfo] = useState(true);
  const [showModelSelection, setShowModelSelection] = useState(false);
  const [modelSelectionType, setModelSelectionType] = useState<'stt' | 'llm' | 'tts'>('stt');

  // Voice session handle ref
  const sessionRef = useRef<VoiceSessionHandle | null>(null);

  // Check if all models are loaded
  const allModelsLoaded = sttModel && llmModel && ttsModel;

  // Check model status on mount
  useEffect(() => {
    checkModelStatus();
    loadAvailableModels();
  }, []);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (sessionRef.current) {
        sessionRef.current.stop();
        sessionRef.current = null;
      }
    };
  }, []);

  /**
   * Load available models from catalog
   */
  const loadAvailableModels = async () => {
    try {
      const models = await RunAnywhere.getAvailableModels();
      setAvailableModels(models);
    } catch (error) {
      console.warn('[VoiceAssistant] Error loading models:', error);
    }
  };

  /**
   * Check which models are already loaded
   */
  const checkModelStatus = async () => {
    try {
      const sttLoaded = await RunAnywhere.isSTTModelLoaded();
      const llmLoaded = await RunAnywhere.isModelLoaded();
      const ttsLoaded = await RunAnywhere.isTTSModelLoaded();

      if (sttLoaded) {
        setSTTModel({ id: 'stt-loaded', name: 'STT Model (Loaded)' } as ModelInfo);
      }
      if (llmLoaded) {
        setLLMModel({ id: 'llm-loaded', name: 'LLM Model (Loaded)' } as ModelInfo);
      }
      if (ttsLoaded) {
        setTTSModel({ id: 'tts-loaded', name: 'TTS Model (Loaded)' } as ModelInfo);
      }
    } catch (error) {
      console.warn('[VoiceAssistant] Error checking model status:', error);
    }
  };

  /**
   * Handle voice session events from the SDK
   */
  const handleVoiceEvent = useCallback((event: VoiceSessionEvent) => {
    switch (event.type) {
      case 'listening':
        setStatus(VoicePipelineStatus.Listening);
        setAudioLevel(event.audioLevel ?? 0);
        break;

      case 'speechStarted':
        console.warn('[VoiceAssistant] 🎙️ Speech started');
        break;

      case 'speechEnded':
        console.warn('[VoiceAssistant] 🔇 Speech ended - processing...');
        break;

      case 'processing':
        setStatus(VoicePipelineStatus.Processing);
        break;

      case 'transcribed':
        if (event.transcription) {
          console.warn('[VoiceAssistant] User said:', event.transcription);
          const userEntry: VoiceConversationEntry = {
            id: generateId(),
            speaker: 'user',
            text: event.transcription,
            timestamp: new Date(),
          };
          setConversation(prev => [...prev, userEntry]);
        }
        setStatus(VoicePipelineStatus.Thinking);
        break;

      case 'responded':
        if (event.response) {
          console.warn('[VoiceAssistant] Assistant:', event.response);
          const assistantEntry: VoiceConversationEntry = {
            id: generateId(),
            speaker: 'assistant',
            text: event.response,
            timestamp: new Date(),
          };
          setConversation(prev => [...prev, assistantEntry]);
        }
        break;

      case 'speaking':
        setStatus(VoicePipelineStatus.Speaking);
        break;

      case 'turnCompleted':
        console.warn('[VoiceAssistant] ✅ Turn completed');
        setStatus(VoicePipelineStatus.Listening);
        break;

      case 'stopped':
        console.warn('[VoiceAssistant] Session stopped');
        setStatus(VoicePipelineStatus.Idle);
        setIsSessionActive(false);
        setAudioLevel(0);
        break;

      case 'error':
        console.error('[VoiceAssistant] Error:', event.error);
        setStatus(VoicePipelineStatus.Error);
        Alert.alert('Error', event.error || 'An error occurred');
        setTimeout(() => setStatus(VoicePipelineStatus.Idle), 2000);
        setIsSessionActive(false);
        break;
    }
  }, []);

  /**
   * Start or stop the voice session
   */
  const handleToggleSession = useCallback(async () => {
    if (isSessionActive) {
      // Stop the session
      if (sessionRef.current) {
        sessionRef.current.stop();
        sessionRef.current = null;
      }
      setIsSessionActive(false);
      setStatus(VoicePipelineStatus.Idle);
    } else {
      // Start the session
      if (!allModelsLoaded) {
        Alert.alert(
          'Models Required',
          'Please load all required models (STT, LLM, TTS) to use the voice assistant.'
        );
        return;
      }

      try {
        console.warn('[VoiceAssistant] Starting voice session...');

        // Use the SDK's voice session API
        const session = await RunAnywhere.startVoiceSession({
          silenceDuration: 1.5,
          speechThreshold: 0.1,
          autoPlayTTS: true,
          continuousMode: true,
          language: 'en',
          onEvent: handleVoiceEvent,
        });

        sessionRef.current = session;
        setIsSessionActive(true);
        setStatus(VoicePipelineStatus.Listening);

        console.warn('[VoiceAssistant] Voice session started');
      } catch (error) {
        console.error('[VoiceAssistant] Failed to start session:', error);
        Alert.alert('Error', `Failed to start voice session: ${error}`);
      }
    }
  }, [isSessionActive, allModelsLoaded, handleVoiceEvent]);

  /**
   * Handle model selection - opens model selection sheet
   */
  const handleSelectModel = useCallback((type: 'stt' | 'llm' | 'tts') => {
    setModelSelectionType(type);
    setShowModelSelection(true);
  }, []);

  /**
   * Get context for model selection
   */
  const getSelectionContext = (type: 'stt' | 'llm' | 'tts'): ModelSelectionContext => {
    switch (type) {
      case 'stt': return ModelSelectionContext.STT;
      case 'llm': return ModelSelectionContext.LLM;
      case 'tts': return ModelSelectionContext.TTS;
    }
  };

  /**
   * Handle model selected from the sheet
   */
  const handleModelSelected = useCallback(async (model: SDKModelInfo) => {
    setShowModelSelection(false);

    try {
      switch (modelSelectionType) {
        case 'stt':
          if (model.localPath) {
            const sttSuccess = await RunAnywhere.loadSTTModel(model.localPath, model.category || 'whisper');
            if (sttSuccess) {
              setSTTModel({ id: model.id, name: model.name, preferredFramework: LLMFramework.ONNX } as ModelInfo);
            }
          }
          break;
        case 'llm':
          if (model.localPath) {
            const llmSuccess = await RunAnywhere.loadModel(model.localPath);
            if (llmSuccess) {
              setLLMModel({ id: model.id, name: model.name, preferredFramework: LLMFramework.LlamaCpp } as ModelInfo);
            }
          }
          break;
        case 'tts':
          if (model.localPath) {
            const ttsSuccess = await RunAnywhere.loadTTSModel(model.localPath, model.category || 'piper');
            if (ttsSuccess) {
              setTTSModel({ id: model.id, name: model.name, preferredFramework: LLMFramework.PiperTTS } as ModelInfo);
            }
          }
          break;
      }
    } catch (error) {
      Alert.alert('Error', `Failed to load model: ${error}`);
    }
  }, [modelSelectionType]);

  /**
   * Clear conversation
   */
  const handleClear = useCallback(() => {
    setConversation([]);
  }, []);

  /**
   * Render model badge
   */
  const renderModelBadge = (
    icon: string,
    label: string,
    model: ModelInfo | null,
    color: string,
    onPress: () => void
  ) => (
    <TouchableOpacity
      style={[styles.modelBadge, { borderColor: model ? color : Colors.borderLight }]}
      onPress={onPress}
      activeOpacity={0.7}
    >
      <View style={[styles.modelBadgeIcon, { backgroundColor: `${color}20` }]}>
        <Icon name={icon} size={16} color={color} />
      </View>
      <View style={styles.modelBadgeContent}>
        <Text style={styles.modelBadgeLabel}>{label}</Text>
        <Text style={styles.modelBadgeValue} numberOfLines={1}>
          {model?.name || 'Not selected'}
        </Text>
      </View>
      <Icon
        name={model ? 'checkmark-circle' : 'add-circle-outline'}
        size={20}
        color={model ? Colors.primaryGreen : Colors.textTertiary}
      />
    </TouchableOpacity>
  );

  /**
   * Render status indicator
   */
  const renderStatusIndicator = () => {
    const statusConfig = {
      [VoicePipelineStatus.Idle]: { color: Colors.statusGray, text: 'Ready' },
      [VoicePipelineStatus.Listening]: { color: Colors.statusGreen, text: 'Listening...' },
      [VoicePipelineStatus.Processing]: { color: Colors.statusOrange, text: 'Processing...' },
      [VoicePipelineStatus.Thinking]: { color: Colors.primaryBlue, text: 'Thinking...' },
      [VoicePipelineStatus.Speaking]: { color: Colors.primaryPurple, text: 'Speaking...' },
      [VoicePipelineStatus.Error]: { color: Colors.statusRed, text: 'Error' },
    };

    const config = statusConfig[status];

    return (
      <View style={styles.statusContainer}>
        <View style={[styles.statusDot, { backgroundColor: config.color }]} />
        <Text style={[styles.statusText, { color: config.color }]}>{config.text}</Text>
      </View>
    );
  };

  /**
   * Render conversation bubble
   */
  const renderConversationBubble = (entry: VoiceConversationEntry) => {
    const isUser = entry.speaker === 'user';
    return (
      <View
        key={entry.id}
        style={[styles.conversationBubble, isUser ? styles.userBubble : styles.assistantBubble]}
      >
        <Text style={styles.speakerLabel}>{isUser ? 'You' : 'AI'}</Text>
        <Text style={styles.bubbleText}>{entry.text}</Text>
      </View>
    );
  };

  /**
   * Render setup view (when models not loaded)
   */
  const renderSetupView = () => (
    <View style={styles.setupContainer}>
      <View style={styles.setupHeader}>
        <Icon name="mic-circle-outline" size={60} color={Colors.primaryBlue} />
        <Text style={styles.setupTitle}>Voice Assistant Setup</Text>
        <Text style={styles.setupSubtitle}>
          Load all required models to enable voice conversations
        </Text>
      </View>

      <View style={styles.modelsContainer}>
        {renderModelBadge('mic-outline', 'Speech Recognition', sttModel, Colors.primaryGreen, () => handleSelectModel('stt'))}
        {renderModelBadge('chatbubble-outline', 'Language Model', llmModel, Colors.primaryBlue, () => handleSelectModel('llm'))}
        {renderModelBadge('volume-high-outline', 'Text-to-Speech', ttsModel, Colors.primaryPurple, () => handleSelectModel('tts'))}
      </View>

      <View style={styles.experimentalBadge}>
        <Icon name="flask-outline" size={16} color={Colors.primaryOrange} />
        <Text style={styles.experimentalText}>Experimental Feature</Text>
      </View>
    </View>
  );

  return (
    <SafeAreaView style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.title}>Voice Assistant</Text>
        <View style={styles.headerActions}>
          {allModelsLoaded && (
            <TouchableOpacity style={styles.headerButton} onPress={() => setShowModelInfo(!showModelInfo)}>
              <Icon name={showModelInfo ? 'information-circle' : 'information-circle-outline'} size={24} color={Colors.primaryBlue} />
            </TouchableOpacity>
          )}
          {conversation.length > 0 && (
            <TouchableOpacity style={styles.headerButton} onPress={handleClear}>
              <Icon name="trash-outline" size={22} color={Colors.primaryRed} />
            </TouchableOpacity>
          )}
        </View>
      </View>

      {/* Status Indicator */}
      {allModelsLoaded && renderStatusIndicator()}

      {/* Model Info (collapsible) */}
      {allModelsLoaded && showModelInfo && (
        <View style={styles.modelInfoContainer}>
          {renderModelBadge('mic-outline', 'STT', sttModel, Colors.primaryGreen, () => handleSelectModel('stt'))}
          {renderModelBadge('chatbubble-outline', 'LLM', llmModel, Colors.primaryBlue, () => handleSelectModel('llm'))}
          {renderModelBadge('volume-high-outline', 'TTS', ttsModel, Colors.primaryPurple, () => handleSelectModel('tts'))}
        </View>
      )}

      {/* Main Content */}
      {!allModelsLoaded ? (
        renderSetupView()
      ) : (
        <>
          {/* Conversation */}
          <ScrollView style={styles.conversationContainer} contentContainerStyle={styles.conversationContent}>
            {conversation.length === 0 ? (
              <View style={styles.emptyConversation}>
                <Icon name="mic-outline" size={40} color={Colors.textTertiary} />
                <Text style={styles.emptyText}>Tap the microphone to start a conversation</Text>
              </View>
            ) : (
              conversation.map(renderConversationBubble)
            )}
          </ScrollView>

          {/* Microphone Control */}
          <View style={styles.controlsContainer}>
            {isSessionActive && (
              <View style={styles.recordingInfo}>
                {/* Audio Level Indicator */}
                <View style={styles.audioLevelContainer}>
                  <View
                    style={[
                      styles.audioLevelBar,
                      {
                        width: `${Math.round(audioLevel * 100)}%`,
                        backgroundColor: audioLevel > 0.1 ? Colors.primaryGreen : Colors.primaryBlue,
                      },
                    ]}
                  />
                </View>
                <Text style={styles.vadStatus}>
                  {status === VoicePipelineStatus.Listening
                    ? audioLevel > 0.1 ? '🎙️ Speaking...' : '👂 Listening...'
                    : status === VoicePipelineStatus.Processing ? '⚙️ Processing...'
                    : status === VoicePipelineStatus.Thinking ? '💭 Thinking...'
                    : status === VoicePipelineStatus.Speaking ? '🔊 Speaking...'
                    : ''}
                </Text>
              </View>
            )}
            <TouchableOpacity
              style={[
                styles.micButton,
                isSessionActive && styles.micButtonRecording,
                status !== VoicePipelineStatus.Idle && status !== VoicePipelineStatus.Listening && styles.micButtonDisabled,
              ]}
              onPress={handleToggleSession}
              disabled={status !== VoicePipelineStatus.Idle && status !== VoicePipelineStatus.Listening}
              activeOpacity={0.8}
            >
              <Icon name={isSessionActive ? 'stop' : 'mic'} size={36} color={Colors.textWhite} />
            </TouchableOpacity>
            <Text style={styles.micLabel}>
              {isSessionActive ? 'Tap to stop (auto-detects silence)' : 'Tap to speak'}
            </Text>
          </View>
        </>
      )}

      {/* Model Selection Sheet */}
      <ModelSelectionSheet
        visible={showModelSelection}
        context={getSelectionContext(modelSelectionType)}
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
  statusContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: Spacing.small,
    paddingVertical: Spacing.smallMedium,
    backgroundColor: Colors.backgroundSecondary,
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  statusText: {
    ...Typography.footnote,
    fontWeight: '600',
  },
  modelInfoContainer: {
    paddingHorizontal: Padding.padding16,
    paddingVertical: Spacing.medium,
    gap: Spacing.small,
    backgroundColor: Colors.backgroundSecondary,
  },
  modelBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.medium,
    padding: Padding.padding12,
    backgroundColor: Colors.backgroundPrimary,
    borderRadius: BorderRadius.medium,
    borderWidth: 1,
  },
  modelBadgeIcon: {
    width: 32,
    height: 32,
    borderRadius: 16,
    justifyContent: 'center',
    alignItems: 'center',
  },
  modelBadgeContent: {
    flex: 1,
  },
  modelBadgeLabel: {
    ...Typography.caption,
    color: Colors.textSecondary,
  },
  modelBadgeValue: {
    ...Typography.subheadline,
    color: Colors.textPrimary,
    fontWeight: '500',
  },
  setupContainer: {
    flex: 1,
    padding: Padding.padding24,
  },
  setupHeader: {
    alignItems: 'center',
    marginBottom: Spacing.xxLarge,
  },
  setupTitle: {
    ...Typography.title2,
    color: Colors.textPrimary,
    marginTop: Spacing.large,
  },
  setupSubtitle: {
    ...Typography.body,
    color: Colors.textSecondary,
    textAlign: 'center',
    marginTop: Spacing.small,
  },
  modelsContainer: {
    gap: Spacing.medium,
  },
  experimentalBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: Spacing.small,
    marginTop: Spacing.xxLarge,
    padding: Padding.padding12,
    backgroundColor: Colors.badgeOrange,
    borderRadius: BorderRadius.regular,
  },
  experimentalText: {
    ...Typography.footnote,
    color: Colors.primaryOrange,
    fontWeight: '600',
  },
  conversationContainer: {
    flex: 1,
  },
  conversationContent: {
    padding: Padding.padding16,
    flexGrow: 1,
  },
  emptyConversation: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    gap: Spacing.medium,
  },
  emptyText: {
    ...Typography.body,
    color: Colors.textSecondary,
    textAlign: 'center',
  },
  conversationBubble: {
    marginBottom: Spacing.medium,
    padding: Padding.padding14,
    borderRadius: BorderRadius.xLarge,
    maxWidth: '80%',
  },
  userBubble: {
    alignSelf: 'flex-end',
    backgroundColor: Colors.primaryBlue,
    borderBottomRightRadius: BorderRadius.small,
  },
  assistantBubble: {
    alignSelf: 'flex-start',
    backgroundColor: Colors.backgroundSecondary,
    borderBottomLeftRadius: BorderRadius.small,
  },
  speakerLabel: {
    ...Typography.caption,
    color: 'rgba(255, 255, 255, 0.7)',
    marginBottom: Spacing.xSmall,
  },
  bubbleText: {
    ...Typography.body,
    color: Colors.textWhite,
  },
  controlsContainer: {
    alignItems: 'center',
    paddingVertical: Padding.padding24,
    paddingBottom: Padding.padding40,
  },
  recordingInfo: {
    alignItems: 'center',
    marginBottom: Spacing.medium,
    width: '100%',
  },
  audioLevelContainer: {
    width: 200,
    height: 8,
    backgroundColor: Colors.backgroundGray5,
    borderRadius: 4,
    overflow: 'hidden',
    marginBottom: Spacing.small,
  },
  audioLevelBar: {
    height: '100%',
    borderRadius: 4,
  },
  vadStatus: {
    ...Typography.footnote,
    color: Colors.textSecondary,
  },
  micButton: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: Colors.primaryBlue,
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: Colors.primaryBlue,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 8,
  },
  micButtonRecording: {
    backgroundColor: Colors.primaryRed,
    shadowColor: Colors.primaryRed,
  },
  micButtonDisabled: {
    backgroundColor: Colors.backgroundGray5,
    shadowOpacity: 0,
  },
  micLabel: {
    ...Typography.footnote,
    color: Colors.textSecondary,
    marginTop: Spacing.medium,
  },
});

export default VoiceAssistantScreen;
