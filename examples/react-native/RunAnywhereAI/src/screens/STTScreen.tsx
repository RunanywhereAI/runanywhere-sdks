/**
 * STTScreen - Tab 1: Speech-to-Text
 *
 * Reference: iOS Features/Voice/SpeechToTextView.swift
 *
 * Uses RunAnywhere SDK for on-device speech recognition.
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
import { Spacing, Padding, BorderRadius, IconSize, ButtonHeight } from '../theme/spacing';
import { ModelStatusBanner, ModelRequiredOverlay } from '../components/common';
import { ModelInfo, ModelModality, ModelCategory } from '../types/model';
import { STTMode, STTResult } from '../types/voice';

// Import RunAnywhere SDK
import {
  RunAnywhere,
  type ModelInfo as SDKModelInfo,
} from 'runanywhere-react-native';

// STT Model IDs
const STT_MODEL_IDS = ['whisper-tiny-en', 'whisper-base-en'];

export const STTScreen: React.FC = () => {
  // State
  const [mode, setMode] = useState<STTMode>(STTMode.Batch);
  const [isRecording, setIsRecording] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [transcript, setTranscript] = useState('');
  const [confidence, setConfidence] = useState<number | null>(null);
  const [currentModel, setCurrentModel] = useState<ModelInfo | null>(null);
  const [isModelLoading, setIsModelLoading] = useState(false);
  const [availableModels, setAvailableModels] = useState<SDKModelInfo[]>([]);

  // Load available models and check for loaded model on mount
  useEffect(() => {
    const initialize = async () => {
      try {
        // Get available STT models from catalog
        const allModels = await RunAnywhere.getAvailableModels();
        const sttModels = allModels.filter((m) => m.modality === 'stt');
        setAvailableModels(sttModels);
        console.log('[STTScreen] Available STT models:', sttModels.map(m => m.id));

        // Check if model is already loaded
        const isLoaded = await RunAnywhere.isSTTModelLoaded();
        if (isLoaded) {
          setCurrentModel({
            id: 'stt-model',
            name: 'STT Model (Loaded)',
          } as ModelInfo);
        }
      } catch (error) {
        console.log('[STTScreen] Error initializing:', error);
      }
    };
    initialize();
  }, []);

  /**
   * Handle model selection - shows available downloaded models
   */
  const handleSelectModel = useCallback(async () => {
    // Get downloaded STT models
    const downloadedModels = availableModels.filter((m) => m.isDownloaded);

    if (downloadedModels.length === 0) {
      Alert.alert(
        'No Models Downloaded',
        'Please download a speech recognition model from the Settings tab first.',
        [{ text: 'OK' }]
      );
      return;
    }

    const buttons = downloadedModels.map((model) => ({
      text: model.name,
      onPress: () => loadModel(model),
    }));
    buttons.push({ text: 'Cancel', onPress: () => {} });

    Alert.alert('Select STT Model', 'Choose a downloaded speech recognition model', buttons as any);
  }, [availableModels]);

  /**
   * Load a model from its info
   */
  const loadModel = async (model: SDKModelInfo) => {
    try {
      setIsModelLoading(true);
      console.log(`[STTScreen] Loading model: ${model.id} from ${model.localPath}`);

      if (!model.localPath) {
        Alert.alert('Error', 'Model path not found. Please re-download the model.');
        return;
      }

      // Load using the actual local path
      const success = await RunAnywhere.loadSTTModel(model.localPath, model.modelType || 'whisper');

      if (success) {
        const isLoaded = await RunAnywhere.isSTTModelLoaded();
        if (isLoaded) {
          setCurrentModel({
            id: model.id,
            name: model.name,
          } as ModelInfo);
          console.log(`[STTScreen] Model ${model.name} loaded successfully`);
        }
      } else {
        const error = await RunAnywhere.getLastError();
        Alert.alert('Error', `Failed to load model: ${error || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('[STTScreen] Error loading model:', error);
      Alert.alert('Error', `Failed to load model: ${error}`);
    } finally {
      setIsModelLoading(false);
    }
  };

  /**
   * Refresh available models
   */
  const refreshModels = useCallback(async () => {
    try {
      const allModels = await RunAnywhere.getAvailableModels();
      const sttModels = allModels.filter((m) => m.modality === 'stt');
      setAvailableModels(sttModels);
    } catch (error) {
      console.log('[STTScreen] Error refreshing models:', error);
    }
  }, []);

  /**
   * Toggle recording
   * Note: In a real app, you would implement actual audio recording
   * using react-native-audio-recorder-player or similar library.
   * For this demo, we show a placeholder message since audio recording
   * requires additional native dependencies.
   */
  const handleToggleRecording = useCallback(async () => {
    if (isRecording) {
      // Stop recording and process
      setIsRecording(false);
      setIsProcessing(true);

      try {
        // Check if model is loaded
        const isLoaded = await RunAnywhere.isSTTModelLoaded();
        if (!isLoaded) {
          Alert.alert('Model Not Loaded', 'Please load an STT model first.');
          setIsProcessing(false);
          return;
        }

        // In a real implementation, you would:
        // 1. Use react-native-audio-recorder-player to record audio
        // 2. Convert the audio file to base64
        // 3. Pass it to RunAnywhere.transcribe()

        // For now, show a demo message
        Alert.alert(
          'Audio Recording Required',
          'This demo requires audio recording capability.\n\n' +
            'To enable real transcription:\n' +
            '1. Add react-native-audio-recorder-player to package.json\n' +
            '2. Run pod install\n' +
            '3. Record audio and pass to RunAnywhere.transcribe()\n\n' +
            'The STT model is loaded and ready to transcribe audio when provided.',
          [{ text: 'OK' }]
        );

        // For demo purposes, show the transcription API works by passing empty audio
        // which will fail gracefully
        setTranscript('(Audio recording not available in demo)');
        setConfidence(null);
      } catch (error) {
        console.error('[STTScreen] Transcription error:', error);
        Alert.alert('Error', `Transcription failed: ${error}`);
      } finally {
        setIsProcessing(false);
      }
    } else {
      // Start recording
      if (!currentModel) {
        Alert.alert('Model Required', 'Please select an STT model first.');
        return;
      }
      setIsRecording(true);
      setTranscript('');
      setConfidence(null);
    }
  }, [isRecording, currentModel]);

  /**
   * Clear transcript
   */
  const handleClear = useCallback(() => {
    setTranscript('');
    setConfidence(null);
  }, []);

  /**
   * Render mode selector
   */
  const renderModeSelector = () => (
    <View style={styles.modeSelector}>
      <TouchableOpacity
        style={[
          styles.modeButton,
          mode === STTMode.Batch && styles.modeButtonActive,
        ]}
        onPress={() => setMode(STTMode.Batch)}
        activeOpacity={0.7}
      >
        <Text
          style={[
            styles.modeButtonText,
            mode === STTMode.Batch && styles.modeButtonTextActive,
          ]}
        >
          Batch
        </Text>
      </TouchableOpacity>
      <TouchableOpacity
        style={[
          styles.modeButton,
          mode === STTMode.Live && styles.modeButtonActive,
        ]}
        onPress={() => setMode(STTMode.Live)}
        activeOpacity={0.7}
      >
        <Text
          style={[
            styles.modeButtonText,
            mode === STTMode.Live && styles.modeButtonTextActive,
          ]}
        >
          Live
        </Text>
      </TouchableOpacity>
    </View>
  );

  /**
   * Render mode description
   */
  const renderModeDescription = () => (
    <View style={styles.modeDescription}>
      <Icon
        name={mode === STTMode.Batch ? 'document-text-outline' : 'pulse-outline'}
        size={20}
        color={Colors.primaryBlue}
      />
      <Text style={styles.modeDescriptionText}>
        {mode === STTMode.Batch
          ? 'Record audio, then transcribe all at once for best accuracy.'
          : 'See transcription in real-time as you speak.'}
      </Text>
    </View>
  );

  /**
   * Render header
   */
  const renderHeader = () => (
    <View style={styles.header}>
      <Text style={styles.title}>Speech to Text</Text>
      {transcript && (
        <TouchableOpacity style={styles.clearButton} onPress={handleClear}>
          <Icon name="close-circle" size={22} color={Colors.textSecondary} />
        </TouchableOpacity>
      )}
    </View>
  );

  // Show model required overlay if no model
  if (!currentModel && !isModelLoading) {
    return (
      <SafeAreaView style={styles.container}>
        {renderHeader()}
        <ModelRequiredOverlay
          modality={ModelModality.STT}
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
        placeholder="Select a speech model"
      />

      {/* Mode Selector */}
      {renderModeSelector()}

      {/* Mode Description */}
      {renderModeDescription()}

      {/* Transcription Area */}
      <ScrollView style={styles.transcriptContainer} contentContainerStyle={styles.transcriptContent}>
        {transcript ? (
          <>
            <Text style={styles.transcriptText}>{transcript}</Text>
            {confidence !== null && (
              <View style={styles.confidenceContainer}>
                <Text style={styles.confidenceLabel}>Confidence:</Text>
                <Text style={styles.confidenceValue}>
                  {Math.round(confidence * 100)}%
                </Text>
              </View>
            )}
          </>
        ) : isProcessing ? (
          <View style={styles.processingContainer}>
            <Icon name="hourglass-outline" size={24} color={Colors.textSecondary} />
            <Text style={styles.processingText}>Processing audio...</Text>
          </View>
        ) : isRecording ? (
          <View style={styles.recordingContainer}>
            <View style={styles.recordingIndicator} />
            <Text style={styles.recordingText}>Listening...</Text>
          </View>
        ) : (
          <View style={styles.emptyState}>
            <Icon name="mic-outline" size={40} color={Colors.textTertiary} />
            <Text style={styles.emptyText}>Tap the microphone to start</Text>
          </View>
        )}
      </ScrollView>

      {/* Record Button */}
      <View style={styles.controlsContainer}>
        <TouchableOpacity
          style={[
            styles.recordButton,
            isRecording && styles.recordButtonActive,
          ]}
          onPress={handleToggleRecording}
          disabled={isProcessing}
          activeOpacity={0.8}
        >
          <Icon
            name={isRecording ? 'stop' : 'mic'}
            size={32}
            color={Colors.textWhite}
          />
        </TouchableOpacity>
        <Text style={styles.recordButtonLabel}>
          {isRecording ? 'Tap to stop' : 'Tap to record'}
        </Text>
      </View>
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
  clearButton: {
    padding: Spacing.small,
  },
  modeSelector: {
    flexDirection: 'row',
    marginHorizontal: Padding.padding16,
    marginTop: Spacing.medium,
    backgroundColor: Colors.backgroundSecondary,
    borderRadius: BorderRadius.regular,
    padding: Spacing.xSmall,
  },
  modeButton: {
    flex: 1,
    paddingVertical: Spacing.smallMedium,
    alignItems: 'center',
    borderRadius: BorderRadius.small,
  },
  modeButtonActive: {
    backgroundColor: Colors.backgroundPrimary,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  modeButtonText: {
    ...Typography.subheadline,
    color: Colors.textSecondary,
  },
  modeButtonTextActive: {
    color: Colors.textPrimary,
    fontWeight: '600',
  },
  modeDescription: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.smallMedium,
    marginHorizontal: Padding.padding16,
    marginTop: Spacing.medium,
    padding: Padding.padding12,
    backgroundColor: Colors.badgeBlue,
    borderRadius: BorderRadius.regular,
  },
  modeDescriptionText: {
    ...Typography.footnote,
    color: Colors.primaryBlue,
    flex: 1,
  },
  transcriptContainer: {
    flex: 1,
    marginHorizontal: Padding.padding16,
    marginTop: Spacing.large,
  },
  transcriptContent: {
    flex: 1,
  },
  transcriptText: {
    ...Typography.body,
    color: Colors.textPrimary,
    lineHeight: 26,
  },
  confidenceContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.small,
    marginTop: Spacing.medium,
    paddingTop: Spacing.medium,
    borderTopWidth: 1,
    borderTopColor: Colors.borderLight,
  },
  confidenceLabel: {
    ...Typography.footnote,
    color: Colors.textSecondary,
  },
  confidenceValue: {
    ...Typography.footnote,
    color: Colors.primaryGreen,
    fontWeight: '600',
  },
  processingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    gap: Spacing.medium,
  },
  processingText: {
    ...Typography.body,
    color: Colors.textSecondary,
  },
  recordingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    gap: Spacing.medium,
  },
  recordingIndicator: {
    width: 16,
    height: 16,
    borderRadius: 8,
    backgroundColor: Colors.primaryRed,
  },
  recordingText: {
    ...Typography.body,
    color: Colors.textPrimary,
  },
  emptyState: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    gap: Spacing.medium,
  },
  emptyText: {
    ...Typography.body,
    color: Colors.textSecondary,
  },
  controlsContainer: {
    alignItems: 'center',
    paddingVertical: Padding.padding20,
    paddingBottom: Padding.padding40,
  },
  recordButton: {
    width: ButtonHeight.large,
    height: ButtonHeight.large,
    borderRadius: ButtonHeight.large / 2,
    backgroundColor: Colors.primaryBlue,
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: Colors.primaryBlue,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 8,
  },
  recordButtonActive: {
    backgroundColor: Colors.primaryRed,
    shadowColor: Colors.primaryRed,
  },
  recordButtonLabel: {
    ...Typography.footnote,
    color: Colors.textSecondary,
    marginTop: Spacing.smallMedium,
  },
});

export default STTScreen;
