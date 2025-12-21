/**
 * VoiceAssistantScreen - Tab 3: Voice Assistant
 *
 * Multi-modal pipeline: STT + LLM + TTS
 *
 * Reference: iOS Features/Voice/VoiceAssistantView.swift
 *
 * Note: This is an experimental feature that demonstrates the pipeline.
 * Full functionality requires downloaded STT, LLM, and TTS models.
 */

import React, { useState, useCallback, useEffect } from 'react';
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
import { ModelSelectionSheet, ModelSelectionContext } from '../components/model';
import { ModelInfo, LLMFramework } from '../types/model';
import { VoicePipelineStatus, VoiceConversationEntry } from '../types/voice';

// Import actual RunAnywhere SDK
import { RunAnywhere, type ModelInfo as SDKModelInfo } from 'runanywhere-react-native';

// Generate unique ID
const generateId = () => Math.random().toString(36).substring(2, 15);

export const VoiceAssistantScreen: React.FC = () => {
  // Model states
  const [sttModel, setSTTModel] = useState<ModelInfo | null>(null);
  const [llmModel, setLLMModel] = useState<ModelInfo | null>(null);
  const [ttsModel, setTTSModel] = useState<ModelInfo | null>(null);
  const [availableModels, setAvailableModels] = useState<SDKModelInfo[]>([]);
  const [demoMode, setDemoMode] = useState(false);

  // Pipeline state
  const [status, setStatus] = useState<VoicePipelineStatus>(VoicePipelineStatus.Idle);
  const [conversation, setConversation] = useState<VoiceConversationEntry[]>([]);
  const [currentTranscript, setCurrentTranscript] = useState('');
  const [isRecording, setIsRecording] = useState(false);
  const [recordingDuration, setRecordingDuration] = useState(0);
  const [showModelInfo, setShowModelInfo] = useState(true);
  const [showModelSelection, setShowModelSelection] = useState(false);
  const [modelSelectionType, setModelSelectionType] = useState<'stt' | 'llm' | 'tts'>('stt');

  // Check if all models are loaded (or demo mode is enabled)
  const allModelsLoaded = demoMode || (sttModel && llmModel && ttsModel);

  // Check model status on mount
  useEffect(() => {
    checkModelStatus();
    loadAvailableModels();
  }, []);

  /**
   * Load available models from catalog
   */
  const loadAvailableModels = async () => {
    try {
      const models = await RunAnywhere.getAvailableModels();
      setAvailableModels(models);
      console.log('[VoiceAssistant] Available models:', models.map(m => `${m.id}(${m.isDownloaded ? 'downloaded' : 'not downloaded'})`));
    } catch (error) {
      console.log('[VoiceAssistant] Error loading models:', error);
    }
  };

  /**
   * Check which models are already loaded
   */
  const checkModelStatus = async () => {
    try {
      const sttLoaded = await RunAnywhere.isSTTModelLoaded();
      const llmLoaded = await RunAnywhere.isTextModelLoaded();
      const ttsLoaded = await RunAnywhere.isTTSModelLoaded();

      console.log('[VoiceAssistant] Model status - STT:', sttLoaded, 'LLM:', llmLoaded, 'TTS:', ttsLoaded);

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
      console.log('[VoiceAssistant] Error checking model status:', error);
    }
  };

  /**
   * Enable demo mode for testing the UI
   */
  const enableDemoMode = () => {
    setDemoMode(true);
    setSTTModel({ id: 'demo-stt', name: 'Demo STT' } as ModelInfo);
    setLLMModel({ id: 'demo-llm', name: 'Demo LLM' } as ModelInfo);
    setTTSModel({ id: 'demo-tts', name: 'Demo TTS' } as ModelInfo);
  };

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
      case 'stt':
        return ModelSelectionContext.STT;
      case 'llm':
        return ModelSelectionContext.LLM;
      case 'tts':
        return ModelSelectionContext.TTS;
    }
  };

  /**
   * Handle model selected from the sheet
   */
  const handleModelSelected = useCallback(async (model: SDKModelInfo) => {
    // Close the modal first to prevent UI issues
    setShowModelSelection(false);

    try {
      console.log(`[VoiceAssistant] Loading ${modelSelectionType} model:`, model.id, model.localPath);

      switch (modelSelectionType) {
        case 'stt':
          if (model.localPath) {
            const sttSuccess = await RunAnywhere.loadSTTModel(model.localPath, model.category || 'whisper');
            if (sttSuccess) {
              setSTTModel({
                id: model.id,
                name: model.name,
                preferredFramework: LLMFramework.ONNX,
              } as ModelInfo);
            }
          }
          break;
        case 'llm':
          if (model.localPath) {
            const llmSuccess = await RunAnywhere.loadTextModel(model.localPath);
            if (llmSuccess) {
              setLLMModel({
                id: model.id,
                name: model.name,
                preferredFramework: LLMFramework.LlamaCpp,
              } as ModelInfo);
            }
          }
          break;
        case 'tts':
          if (model.localPath) {
            const ttsSuccess = await RunAnywhere.loadTTSModel(model.localPath, model.category || 'piper');
            if (ttsSuccess) {
              setTTSModel({
                id: model.id,
                name: model.name,
                preferredFramework: LLMFramework.PiperTTS,
              } as ModelInfo);
            }
          }
          break;
      }
    } catch (error) {
      Alert.alert('Error', `Failed to load model: ${error}`);
    }
  }, [modelSelectionType]);

  /**
   * Start/stop recording
   * Note: In a real implementation, you would use react-native-audio-recorder-player
   * or similar library to capture actual audio and pass it to the SDK.
   */
  const handleToggleRecording = useCallback(async () => {
    if (isRecording) {
      // Stop recording
      setIsRecording(false);
      setStatus(VoicePipelineStatus.Processing);
      setRecordingDuration(0);

      try {
        // In demo mode or when audio recording is not available,
        // we simulate the pipeline
        const mockUserText = currentTranscript || 'Hello, how are you?';

        // Add user message
        const userEntry: VoiceConversationEntry = {
          id: generateId(),
          speaker: 'user',
          text: mockUserText,
          timestamp: new Date(),
        };
        setConversation((prev) => [...prev, userEntry]);
        setCurrentTranscript('');

        setStatus(VoicePipelineStatus.Thinking);

        let responseText: string;

        if (demoMode) {
          // Simulate LLM response in demo mode
          await new Promise((resolve) => setTimeout(resolve, 1000));
          const demoResponses = [
            "Hello! I'm the demo voice assistant. The full pipeline requires STT, LLM, and TTS models to be downloaded and loaded.",
            "In demo mode, I provide simulated responses. Download models from the Settings tab for real AI responses!",
            "The RunAnywhere SDK supports on-device STT, LLM, and TTS. This demo shows the pipeline flow.",
          ];
          responseText = demoResponses[conversation.length % demoResponses.length] || demoResponses[0]!;
        } else {
          // Try real LLM generation
          try {
            const result = await RunAnywhere.generate(mockUserText, {
              maxTokens: 500,
              temperature: 0.7,
            });
            responseText = result.text || '(No response generated)';
          } catch (err) {
            console.error('[VoiceAssistant] LLM error:', err);
            responseText = `Error generating response: ${err}`;
          }
        }

        const assistantEntry: VoiceConversationEntry = {
          id: generateId(),
          speaker: 'assistant',
          text: responseText,
          timestamp: new Date(),
        };
        setConversation((prev) => [...prev, assistantEntry]);

        setStatus(VoicePipelineStatus.Speaking);

        // In a real implementation with actual TTS:
        // 1. Call RunAnywhere.synthesize(responseText)
        // 2. Play the resulting audio
        // 3. Set status to Idle when playback completes

        // For now, simulate TTS playback duration
        const estimatedDuration = Math.min(responseText.length * 50, 3000);
        setTimeout(() => {
          setStatus(VoicePipelineStatus.Idle);
        }, estimatedDuration);
      } catch (error) {
        console.error('[VoiceAssistant] Pipeline error:', error);
        Alert.alert('Error', `Pipeline failed: ${error}`);
        setStatus(VoicePipelineStatus.Error);
        setTimeout(() => setStatus(VoicePipelineStatus.Idle), 2000);
      }
    } else {
      // Start recording
      if (!allModelsLoaded) {
        Alert.alert(
          'Models Required',
          'Please load all required models first, or enable Demo Mode.',
          [
            { text: 'Enable Demo Mode', onPress: enableDemoMode },
            { text: 'Cancel', style: 'cancel' },
          ]
        );
        return;
      }
      setIsRecording(true);
      setStatus(VoicePipelineStatus.Listening);

      // In demo mode, use placeholder transcript
      // In real mode, audio recording would populate this
      setCurrentTranscript('Hello, how can you help me today?');

      // Start duration timer
      let duration = 0;
      const timerRef = setInterval(() => {
        duration += 1;
        setRecordingDuration(duration);
      }, 1000);

      // Auto-stop after 10 seconds in demo mode
      setTimeout(() => {
        clearInterval(timerRef);
        if (demoMode) {
          // Will trigger processing in demo mode
        }
      }, 10000);
    }
  }, [isRecording, allModelsLoaded, currentTranscript, demoMode, conversation.length]);

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
