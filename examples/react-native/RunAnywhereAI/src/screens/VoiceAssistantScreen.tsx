/**
 * VoiceAssistantScreen - Tab 3: Voice Assistant
 *
 * Multi-modal pipeline: STT + LLM + TTS
 *
 * Reference: iOS Features/Voice/VoiceAssistantView.swift
 */

import React, { useState, useCallback } from 'react';
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
import { Spacing, Padding, BorderRadius, IconSize, ButtonHeight } from '../theme/spacing';
import { ModelInfo, LLMFramework, FrameworkDisplayNames } from '../types/model';
import { VoicePipelineStatus, VoiceConversationEntry } from '../types/voice';
import MockSDK from '../services/MockSDK';

// Generate unique ID
const generateId = () => Math.random().toString(36).substring(2, 15);

export const VoiceAssistantScreen: React.FC = () => {
  // Model states
  const [sttModel, setSTTModel] = useState<ModelInfo | null>(null);
  const [llmModel, setLLMModel] = useState<ModelInfo | null>(null);
  const [ttsModel, setTTSModel] = useState<ModelInfo | null>(null);

  // Pipeline state
  const [status, setStatus] = useState<VoicePipelineStatus>(VoicePipelineStatus.Idle);
  const [conversation, setConversation] = useState<VoiceConversationEntry[]>([]);
  const [currentTranscript, setCurrentTranscript] = useState('');
  const [isRecording, setIsRecording] = useState(false);
  const [recordingDuration, setRecordingDuration] = useState(0);
  const [showModelInfo, setShowModelInfo] = useState(true);

  // Check if all models are loaded
  const allModelsLoaded = sttModel && llmModel && ttsModel;

  /**
   * Handle model selection
   * TODO: Open ModelSelectionModal with appropriate filter
   */
  const handleSelectModel = useCallback(
    (type: 'stt' | 'llm' | 'tts') => {
      const titles = {
        stt: 'Select Speech Model',
        llm: 'Select Language Model',
        tts: 'Select Voice Model',
      };

      const models = {
        stt: [{ id: 'whisper-tiny', name: 'Whisper Tiny' }],
        llm: [{ id: 'smollm2-360m', name: 'SmolLM2 360M' }],
        tts: [{ id: 'piper-en-us-lessac', name: 'Piper TTS - US English' }],
      };

      Alert.alert(titles[type], 'Choose a model', [
        {
          text: models[type][0].name,
          onPress: async () => {
            try {
              await MockSDK.loadModel(models[type][0].id);
              switch (type) {
                case 'stt':
                  setSTTModel(MockSDK.getCurrentSTTModel());
                  break;
                case 'llm':
                  setLLMModel(MockSDK.getCurrentLLMModel());
                  break;
                case 'tts':
                  setTTSModel(MockSDK.getCurrentTTSModel());
                  break;
              }
            } catch (error) {
              Alert.alert('Error', `Failed to load model: ${error}`);
            }
          },
        },
        { text: 'Cancel', style: 'cancel' },
      ]);
    },
    []
  );

  /**
   * Start/stop recording
   * TODO: Implement actual voice pipeline
   */
  const handleToggleRecording = useCallback(async () => {
    if (isRecording) {
      // Stop recording
      setIsRecording(false);
      setStatus(VoicePipelineStatus.Processing);

      // Simulate pipeline
      setTimeout(() => {
        // Add user message
        const userEntry: VoiceConversationEntry = {
          id: generateId(),
          speaker: 'user',
          text: currentTranscript || 'Hello, how are you?',
          timestamp: new Date(),
        };
        setConversation((prev) => [...prev, userEntry]);
        setCurrentTranscript('');

        setStatus(VoicePipelineStatus.Thinking);

        // Simulate LLM response
        setTimeout(() => {
          const assistantEntry: VoiceConversationEntry = {
            id: generateId(),
            speaker: 'assistant',
            text: "I'm doing well, thank you! How can I help you today?",
            timestamp: new Date(),
          };
          setConversation((prev) => [...prev, assistantEntry]);

          setStatus(VoicePipelineStatus.Speaking);

          // Simulate TTS playback
          setTimeout(() => {
            setStatus(VoicePipelineStatus.Idle);
          }, 2000);
        }, 1500);
      }, 1000);
    } else {
      // Start recording
      if (!allModelsLoaded) {
        Alert.alert('Models Required', 'Please load all required models first.');
        return;
      }
      setIsRecording(true);
      setStatus(VoicePipelineStatus.Listening);
      setCurrentTranscript('Hello, how are you?'); // Mock transcript

      // Start duration timer
      let duration = 0;
      const timer = setInterval(() => {
        duration += 1;
        setRecordingDuration(duration);
      }, 1000);

      // Store timer for cleanup
      setTimeout(() => clearInterval(timer), 10000);
    }
  }, [isRecording, allModelsLoaded, currentTranscript]);

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
        style={[
          styles.conversationBubble,
          isUser ? styles.userBubble : styles.assistantBubble,
        ]}
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
        {renderModelBadge(
          'mic-outline',
          'Speech Recognition',
          sttModel,
          Colors.primaryGreen,
          () => handleSelectModel('stt')
        )}
        {renderModelBadge(
          'chatbubble-outline',
          'Language Model',
          llmModel,
          Colors.primaryBlue,
          () => handleSelectModel('llm')
        )}
        {renderModelBadge(
          'volume-high-outline',
          'Text-to-Speech',
          ttsModel,
          Colors.primaryPurple,
          () => handleSelectModel('tts')
        )}
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
            <TouchableOpacity
              style={styles.headerButton}
              onPress={() => setShowModelInfo(!showModelInfo)}
            >
              <Icon
                name={showModelInfo ? 'information-circle' : 'information-circle-outline'}
                size={24}
                color={Colors.primaryBlue}
              />
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
          {renderModelBadge(
            'mic-outline',
            'STT',
            sttModel,
            Colors.primaryGreen,
            () => handleSelectModel('stt')
          )}
          {renderModelBadge(
            'chatbubble-outline',
            'LLM',
            llmModel,
            Colors.primaryBlue,
            () => handleSelectModel('llm')
          )}
          {renderModelBadge(
            'volume-high-outline',
            'TTS',
            ttsModel,
            Colors.primaryPurple,
            () => handleSelectModel('tts')
          )}
        </View>
      )}

      {/* Main Content */}
      {!allModelsLoaded ? (
        renderSetupView()
      ) : (
        <>
          {/* Conversation */}
          <ScrollView
            style={styles.conversationContainer}
            contentContainerStyle={styles.conversationContent}
          >
            {conversation.length === 0 ? (
              <View style={styles.emptyConversation}>
                <Icon name="mic-outline" size={40} color={Colors.textTertiary} />
                <Text style={styles.emptyText}>
                  Tap the microphone to start a conversation
                </Text>
              </View>
            ) : (
              conversation.map(renderConversationBubble)
            )}

            {/* Current transcript (while recording) */}
            {isRecording && currentTranscript && (
              <View style={[styles.conversationBubble, styles.userBubble, styles.transcriptBubble]}>
                <Text style={styles.speakerLabel}>You</Text>
                <Text style={styles.bubbleText}>{currentTranscript}</Text>
              </View>
            )}
          </ScrollView>

          {/* Microphone Control */}
          <View style={styles.controlsContainer}>
            {isRecording && (
              <Text style={styles.recordingTime}>
                {Math.floor(recordingDuration / 60)}:{(recordingDuration % 60).toString().padStart(2, '0')}
              </Text>
            )}
            <TouchableOpacity
              style={[
                styles.micButton,
                isRecording && styles.micButtonRecording,
                status !== VoicePipelineStatus.Idle &&
                  status !== VoicePipelineStatus.Listening &&
                  styles.micButtonDisabled,
              ]}
              onPress={handleToggleRecording}
              disabled={
                status !== VoicePipelineStatus.Idle &&
                status !== VoicePipelineStatus.Listening
              }
              activeOpacity={0.8}
            >
              <Icon
                name={isRecording ? 'stop' : 'mic'}
                size={36}
                color={Colors.textWhite}
              />
            </TouchableOpacity>
            <Text style={styles.micLabel}>
              {isRecording ? 'Tap to stop' : 'Tap to speak'}
            </Text>
          </View>
        </>
      )}
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
  transcriptBubble: {
    opacity: 0.7,
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
  recordingTime: {
    ...Typography.title3,
    color: Colors.primaryRed,
    marginBottom: Spacing.medium,
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
