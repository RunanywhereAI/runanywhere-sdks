/**
 * STTScreen - Tab 1: Speech-to-Text
 *
 * Reference: iOS Features/Voice/SpeechToTextView.swift
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
import MockSDK from '../services/MockSDK';

export const STTScreen: React.FC = () => {
  // State
  const [mode, setMode] = useState<STTMode>(STTMode.Batch);
  const [isRecording, setIsRecording] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [transcript, setTranscript] = useState('');
  const [confidence, setConfidence] = useState<number | null>(null);
  const [currentModel, setCurrentModel] = useState<ModelInfo | null>(null);
  const [isModelLoading, setIsModelLoading] = useState(false);

  // Check for loaded model on mount
  useEffect(() => {
    const model = MockSDK.getCurrentSTTModel();
    setCurrentModel(model);
  }, []);

  /**
   * Handle model selection
   * TODO: Open ModelSelectionModal with STT filter
   */
  const handleSelectModel = useCallback(async () => {
    Alert.alert(
      'Select STT Model',
      'Choose a speech recognition model',
      [
        {
          text: 'Whisper Tiny',
          onPress: () => loadModel('whisper-tiny'),
        },
        { text: 'Cancel', style: 'cancel' },
      ]
    );
  }, []);

  /**
   * Load a model
   * TODO: Replace with RunAnywhere.loadSTTModel()
   */
  const loadModel = async (modelId: string) => {
    try {
      setIsModelLoading(true);
      await MockSDK.loadModel(modelId);
      const model = MockSDK.getCurrentSTTModel();
      setCurrentModel(model);
    } catch (error) {
      Alert.alert('Error', `Failed to load model: ${error}`);
    } finally {
      setIsModelLoading(false);
    }
  };

  /**
   * Toggle recording
   * TODO: Implement actual audio recording
   */
  const handleToggleRecording = useCallback(async () => {
    if (isRecording) {
      // Stop recording and process
      setIsRecording(false);
      setIsProcessing(true);

      try {
        // TODO: Replace with actual audio data
        const result = await MockSDK.transcribe('mock_audio_data');
        setTranscript(result.text);
        setConfidence(result.confidence);
      } catch (error) {
        Alert.alert('Error', `Transcription failed: ${error}`);
      } finally {
        setIsProcessing(false);
      }
    } else {
      // Start recording
      // TODO: Request microphone permissions
      // TODO: Start actual audio recording
      setIsRecording(true);
      setTranscript('');
      setConfidence(null);
    }
  }, [isRecording]);

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
