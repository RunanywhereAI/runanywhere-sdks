/**
 * VoiceAssistantScreen - Tab 3: Voice Assistant
 *
 * Complete voice AI pipeline combining speech recognition, language model, and synthesis.
 * Matches iOS VoiceAssistantView architecture and patterns.
 *
 * Pipeline:
 * 1. STT: Voice → Text (Whisper model)
 * 2. LLM: Text → Response (LlamaCPP model)
 * 3. TTS: Response → Speech (Piper model)
 *
 * Features:
 * - Push-to-talk voice interaction
 * - Real-time conversation display
 * - Model status indicators for each stage
 * - Audio level visualization
 *
 * Architecture:
 * - Orchestrates STT, LLM, and TTS capabilities
 * - Sequential pipeline execution
 * - Error handling at each stage
 * - Requires all three models to be loaded
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
import * as AudioService from '../utils/AudioService';

// Import RunAnywhere SDK (Multi-Package Architecture)
import { RunAnywhere, type ModelInfo as SDKModelInfo } from '@runanywhere/core';

// Generate unique ID
const generateId = () => Math.random().toString(36).substring(2, 15);

export const VoiceAssistantScreen: React.FC = () => {
  // Model states
  const [sttModel, setSTTModel] = useState<ModelInfo | null>(null);
  const [llmModel, setLLMModel] = useState<ModelInfo | null>(null);
  const [ttsModel, setTTSModel] = useState<ModelInfo | null>(null);
  const [_availableModels, setAvailableModels] = useState<SDKModelInfo[]>([]);

  // Pipeline state
  const [status, setStatus] = useState<VoicePipelineStatus>(
    VoicePipelineStatus.Idle
  );
  const [conversation, setConversation] = useState<VoiceConversationEntry[]>(
    []
  );
  const [currentTranscript, setCurrentTranscript] = useState('');
  const [isRecording, setIsRecording] = useState(false);
  const [recordingDuration, setRecordingDuration] = useState(0);
  const [showModelInfo, setShowModelInfo] = useState(true);
  const [showModelSelection, setShowModelSelection] = useState(false);
  const [modelSelectionType, setModelSelectionType] = useState<
    'stt' | 'llm' | 'tts'
  >('stt');

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
      // Stop recording if still in progress
      if (isRecording) {
        AudioService.stopRecording().catch(() => {});
      }
      // Clear any timers
      if (timerRef.current) {
        clearTimeout(timerRef.current as unknown as number);
        timerRef.current = null;
      }
    };
  }, [isRecording]);

  /**
   * Load available models from catalog
   */
  const loadAvailableModels = async () => {
    try {
      const models = await RunAnywhere.getAvailableModels();
      setAvailableModels(models);
      console.log(
        '[VoiceAssistant] Available models:',
        models.map(
          (m) => `${m.id}(${m.isDownloaded ? 'downloaded' : 'not downloaded'})`
        )
      );
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
      const llmLoaded = await RunAnywhere.isModelLoaded();
      const ttsLoaded = await RunAnywhere.isTTSModelLoaded();

      console.log(
        '[VoiceAssistant] Model status - STT:',
        sttLoaded,
        'LLM:',
        llmLoaded,
        'TTS:',
        ttsLoaded
      );

      if (sttLoaded) {
        setSTTModel({
          id: 'stt-loaded',
          name: 'STT Model (Loaded)',
        } as ModelInfo);
      }
      if (llmLoaded) {
        setLLMModel({
          id: 'llm-loaded',
          name: 'LLM Model (Loaded)',
        } as ModelInfo);
      }
      if (ttsLoaded) {
        setTTSModel({
          id: 'tts-loaded',
          name: 'TTS Model (Loaded)',
        } as ModelInfo);
      }
    } catch (error) {
      console.log('[VoiceAssistant] Error checking model status:', error);
    }
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
  const getSelectionContext = (
    type: 'stt' | 'llm' | 'tts'
  ): ModelSelectionContext => {
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
  const handleModelSelected = useCallback(
    async (model: SDKModelInfo) => {
      // Close the modal first to prevent UI issues
      setShowModelSelection(false);

      try {
        console.log(
          `[VoiceAssistant] Loading ${modelSelectionType} model:`,
          model.id,
          model.localPath
        );

        switch (modelSelectionType) {
          case 'stt':
            if (model.localPath) {
              const sttSuccess = await RunAnywhere.loadSTTModel(
                model.localPath,
                model.category || 'whisper'
              );
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
              const llmSuccess = await RunAnywhere.loadModel(model.localPath);
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
              const ttsSuccess = await RunAnywhere.loadTTSModel(
                model.localPath,
                model.category || 'piper'
              );
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
    },
    [modelSelectionType]
  );

  // Timer ref for recording duration
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  /**
   * Start/stop recording using AudioService
   * Implements the full voice pipeline: Record → STT → LLM → TTS
   */
  const handleToggleRecording = useCallback(async () => {
    if (isRecording) {
      // Stop recording and process pipeline
      setIsRecording(false);
      setStatus(VoicePipelineStatus.Processing);

      // Clear duration timer
      if (timerRef.current) {
        clearInterval(timerRef.current);
        timerRef.current = null;
      }
      setRecordingDuration(0);

      try {
        // Step 1: Stop recording and get audio file
        console.log('[VoiceAssistant] Stopping recording...');
        const { uri: audioPath } = await AudioService.stopRecording();
        console.log('[VoiceAssistant] Recording stopped:', audioPath);

        // Step 2: Transcribe audio using STT
        setStatus(VoicePipelineStatus.Processing);
        console.log('[VoiceAssistant] Transcribing audio...');

        const sttResult = await RunAnywhere.transcribeFile(audioPath, {
          language: 'en',
        });
        const userText = sttResult.text?.trim() || '';

        if (!userText) {
          console.log('[VoiceAssistant] No speech detected');
          Alert.alert('No Speech', 'No speech was detected. Please try again.');
          setStatus(VoicePipelineStatus.Idle);
          return;
        }

        // Add user message to conversation
        const userEntry: VoiceConversationEntry = {
          id: generateId(),
          speaker: 'user',
          text: userText,
          timestamp: new Date(),
        };
        setConversation((prev) => [...prev, userEntry]);
        setCurrentTranscript('');
        console.log('[VoiceAssistant] User said:', userText);

        // Step 3: Generate LLM response
        setStatus(VoicePipelineStatus.Thinking);
        console.log('[VoiceAssistant] Generating response...');

        let responseText: string;
        try {
          const result = await RunAnywhere.generate(userText, {
            maxTokens: 500,
            temperature: 0.7,
          });
          responseText = result.text || '(No response generated)';
        } catch (err) {
          console.error('[VoiceAssistant] LLM error:', err);
          responseText = `I apologize, but I encountered an error: ${err}`;
        }

        // Add assistant message to conversation
        const assistantEntry: VoiceConversationEntry = {
          id: generateId(),
          speaker: 'assistant',
          text: responseText,
          timestamp: new Date(),
        };
        setConversation((prev) => [...prev, assistantEntry]);
        console.log('[VoiceAssistant] Assistant:', responseText);

        // Step 4: Synthesize TTS and play audio
        setStatus(VoicePipelineStatus.Speaking);
        console.log('[VoiceAssistant] Synthesizing speech...');

        try {
          const ttsResult = await RunAnywhere.synthesize(responseText);

          if (ttsResult.audio) {
            // Play the synthesized audio
            // The audio is base64 encoded, need to save to file and play
            console.log('[VoiceAssistant] Playing TTS audio...');
            // For now, estimate duration based on text length
            // TODO: Play actual audio using AudioService
            const estimatedDuration = Math.min(responseText.length * 50, 5000);
            await new Promise((resolve) =>
              setTimeout(resolve, estimatedDuration)
            );
          }
        } catch (ttsErr) {
          console.warn('[VoiceAssistant] TTS failed, skipping audio:', ttsErr);
          // TTS failure is non-fatal, just log and continue
        }

        setStatus(VoicePipelineStatus.Idle);
        console.log('[VoiceAssistant] Pipeline complete');
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
          'Please load all required models (STT, LLM, TTS) to use the voice assistant.'
        );
        return;
      }

      try {
        // Request microphone permission
        const hasPermission = await AudioService.requestAudioPermission();
        if (!hasPermission) {
          Alert.alert(
            'Permission Required',
            'Microphone permission is required to record audio.'
          );
          return;
        }

        // Start recording
        console.log('[VoiceAssistant] Starting recording...');
        await AudioService.startRecording({
          onProgress: (currentPositionMs, metering) => {
            setRecordingDuration(Math.floor(currentPositionMs / 1000));
            // metering is in dB, normalize to 0-1 for display
            if (metering !== undefined) {
              const normalizedLevel = Math.max(
                0,
                Math.min(1, (metering + 60) / 60)
              );
              // Could use this for audio level visualization
              console.log(
                '[VoiceAssistant] Audio level:',
                normalizedLevel.toFixed(2)
              );
            }
          },
        });

        setIsRecording(true);
        setStatus(VoicePipelineStatus.Listening);
        setCurrentTranscript('');
        console.log('[VoiceAssistant] Recording started');

        // Auto-stop after 30 seconds
        timerRef.current = setTimeout(async () => {
          if (isRecording) {
            console.log('[VoiceAssistant] Auto-stopping after 30 seconds');
            await handleToggleRecording();
          }
        }, 30000) as unknown as ReturnType<typeof setInterval>;
      } catch (error) {
        console.error('[VoiceAssistant] Failed to start recording:', error);
        Alert.alert('Error', `Failed to start recording: ${error}`);
      }
    }
  }, [isRecording, allModelsLoaded]);

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
      style={[
        styles.modelBadge,
        { borderColor: model ? color : Colors.borderLight },
      ]}
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
      [VoicePipelineStatus.Listening]: {
        color: Colors.statusGreen,
        text: 'Listening...',
      },
      [VoicePipelineStatus.Processing]: {
        color: Colors.statusOrange,
        text: 'Processing...',
      },
      [VoicePipelineStatus.Thinking]: {
        color: Colors.primaryBlue,
        text: 'Thinking...',
      },
      [VoicePipelineStatus.Speaking]: {
        color: Colors.primaryPurple,
        text: 'Speaking...',
      },
      [VoicePipelineStatus.Error]: { color: Colors.statusRed, text: 'Error' },
    };

    const config = statusConfig[status];

    return (
      <View style={styles.statusContainer}>
        <View style={[styles.statusDot, { backgroundColor: config.color }]} />
        <Text style={[styles.statusText, { color: config.color }]}>
          {config.text}
        </Text>
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
                name={
                  showModelInfo
                    ? 'information-circle'
                    : 'information-circle-outline'
                }
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
                <Icon
                  name="mic-outline"
                  size={40}
                  color={Colors.textTertiary}
                />
                <Text style={styles.emptyText}>
                  Tap the microphone to start a conversation
                </Text>
              </View>
            ) : (
              conversation.map(renderConversationBubble)
            )}

            {/* Current transcript (while recording) */}
            {isRecording && currentTranscript && (
              <View
                style={[
                  styles.conversationBubble,
                  styles.userBubble,
                  styles.transcriptBubble,
                ]}
              >
                <Text style={styles.speakerLabel}>You</Text>
                <Text style={styles.bubbleText}>{currentTranscript}</Text>
              </View>
            )}
          </ScrollView>

          {/* Microphone Control */}
          <View style={styles.controlsContainer}>
            {isRecording && (
              <Text style={styles.recordingTime}>
                {Math.floor(recordingDuration / 60)}:
                {(recordingDuration % 60).toString().padStart(2, '0')}
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
