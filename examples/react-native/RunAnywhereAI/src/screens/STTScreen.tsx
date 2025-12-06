/**
 * STTScreen - Tab 1: Speech-to-Text
 *
 * Reference: iOS Features/Voice/SpeechToTextView.swift
 *
 * Uses RunAnywhere SDK for on-device speech recognition.
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
  Platform,
  Animated,
  PermissionsAndroid,
  Linking,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { useFocusEffect } from '@react-navigation/native';
import AudioRecorderPlayer, {
  AudioEncoderAndroidType,
  AudioSourceAndroidType,
  AVEncoderAudioQualityIOSType,
  AVEncodingOption,
  OutputFormatAndroidType,
} from 'react-native-audio-recorder-player';
import RNFS from 'react-native-fs';
import { check, request, PERMISSIONS, RESULTS } from 'react-native-permissions';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding, BorderRadius, IconSize, ButtonHeight } from '../theme/spacing';
import { ModelStatusBanner, ModelRequiredOverlay } from '../components/common';
import { ModelSelectionSheet, ModelSelectionContext } from '../components/model';
import { ModelInfo, ModelModality, ModelCategory, LLMFramework } from '../types/model';
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
  const [partialTranscript, setPartialTranscript] = useState(''); // For live mode - current chunk
  const [confidence, setConfidence] = useState<number | null>(null);
  const [currentModel, setCurrentModel] = useState<ModelInfo | null>(null);
  const [isModelLoading, setIsModelLoading] = useState(false);
  const [availableModels, setAvailableModels] = useState<SDKModelInfo[]>([]);
  const [recordingDuration, setRecordingDuration] = useState(0);
  const [audioLevel, setAudioLevel] = useState(0);
  const [showModelSelection, setShowModelSelection] = useState(false);

  // Audio recorder ref (for batch mode only)
  const audioRecorderPlayer = useRef(new AudioRecorderPlayer()).current;
  const recordingPath = useRef<string | null>(null);

  // Live mode accumulated transcript ref
  const accumulatedTranscriptRef = useRef('');

  // Animation for recording indicator
  const pulseAnim = useRef(new Animated.Value(1)).current;

  // Start pulse animation when recording
  useEffect(() => {
    if (isRecording) {
      const pulse = Animated.loop(
        Animated.sequence([
          Animated.timing(pulseAnim, {
            toValue: 1.3,
            duration: 500,
            useNativeDriver: true,
          }),
          Animated.timing(pulseAnim, {
            toValue: 1,
            duration: 500,
            useNativeDriver: true,
          }),
        ])
      );
      pulse.start();
      return () => pulse.stop();
    } else {
      pulseAnim.setValue(1);
    }
  }, [isRecording, pulseAnim]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      // Stop SDK streaming if active
      RunAnywhere.stopStreamingSTT().catch(() => {});
      // Stop batch mode recorder
      audioRecorderPlayer.stopRecorder().catch(() => {});
      audioRecorderPlayer.removeRecordBackListener();
      // Clean up temp audio file
      if (recordingPath.current) {
        RNFS.unlink(recordingPath.current).catch(() => {});
      }
    };
  }, []);

  /**
   * Load available models and check for loaded model
   * Called on mount and when screen comes into focus
   */
  const loadModels = useCallback(async () => {
    try {
      // Get available STT models from catalog
      const allModels = await RunAnywhere.getAvailableModels();
      // Filter by category (speech-recognition) matching SDK's ModelCategory
      const sttModels = allModels.filter((m: any) => m.category === 'speech-recognition');
      setAvailableModels(sttModels);

      // Log downloaded status for debugging
      const downloadedModels = sttModels.filter(m => m.isDownloaded);
      console.log('[STTScreen] Available STT models:', sttModels.map(m => `${m.id} (downloaded: ${m.isDownloaded})`));
      console.log('[STTScreen] Downloaded STT models:', downloadedModels.map(m => m.id));

      // Check if model is already loaded
      const isLoaded = await RunAnywhere.isSTTModelLoaded();
      console.log('[STTScreen] isSTTModelLoaded:', isLoaded);
      if (isLoaded && !currentModel) {
        // Try to find which model is loaded from downloaded models
        const downloadedStt = sttModels.filter(m => m.isDownloaded);
        if (downloadedStt.length > 0) {
          setCurrentModel({
            id: downloadedStt[0]!.id,
            name: downloadedStt[0]!.name,
            preferredFramework: LLMFramework.ONNX,
          } as ModelInfo);
          console.log('[STTScreen] Set currentModel from downloaded:', downloadedStt[0]!.name);
        } else {
          setCurrentModel({
            id: 'stt-model',
            name: 'STT Model (Loaded)',
            preferredFramework: LLMFramework.ONNX,
          } as ModelInfo);
          console.log('[STTScreen] Set currentModel as generic STT Model');
        }
      }
    } catch (error) {
      console.log('[STTScreen] Error loading models:', error);
    }
  }, [currentModel]);

  // Refresh models when screen comes into focus
  // This ensures we pick up any models downloaded in the Settings tab
  useFocusEffect(
    useCallback(() => {
      console.log('[STTScreen] Screen focused - refreshing models');
      loadModels();
    }, [loadModels])
  );

  /**
   * Handle model selection - opens model selection sheet
   */
  const handleSelectModel = useCallback(() => {
    setShowModelSelection(true);
  }, []);

  /**
   * Handle model selected from the sheet
   */
  const handleModelSelected = useCallback(async (model: SDKModelInfo) => {
    await loadModel(model);
  }, []);

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
          // Set model with framework so ModelStatusBanner shows it properly
          // Use ONNX since STT uses Sherpa-ONNX (ONNX Runtime)
          setCurrentModel({
            id: model.id,
            name: model.name,
            preferredFramework: LLMFramework.ONNX,
          } as ModelInfo);
          console.log(`[STTScreen] Model ${model.name} loaded successfully, currentModel set`);
        } else {
          console.log(`[STTScreen] Model reported success but isSTTModelLoaded() returned false`);
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
   * Format duration in MM:SS
   */
  const formatDuration = (ms: number): string => {
    const totalSeconds = Math.floor(ms / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes}:${seconds.toString().padStart(2, '0')}`;
  };

  /**
   * Request microphone permission
   */
  const requestMicrophonePermission = async (): Promise<boolean> => {
    try {
      if (Platform.OS === 'ios') {
        const status = await check(PERMISSIONS.IOS.MICROPHONE);
        console.log('[STTScreen] iOS microphone permission status:', status);

        if (status === RESULTS.GRANTED) {
          return true;
        }

        if (status === RESULTS.DENIED) {
          const result = await request(PERMISSIONS.IOS.MICROPHONE);
          console.log('[STTScreen] iOS microphone permission request result:', result);
          return result === RESULTS.GRANTED;
        }

        if (status === RESULTS.BLOCKED) {
          Alert.alert(
            'Microphone Permission Required',
            'Please enable microphone access in Settings to use speech-to-text.',
            [
              { text: 'Cancel', style: 'cancel' },
              { text: 'Open Settings', onPress: () => Linking.openSettings() },
            ]
          );
          return false;
        }

        return false;
      } else {
        // Android
        const granted = await PermissionsAndroid.request(
          PermissionsAndroid.PERMISSIONS.RECORD_AUDIO,
          {
            title: 'Microphone Permission',
            message: 'RunAnywhereAI needs access to your microphone for speech-to-text.',
            buttonNeutral: 'Ask Me Later',
            buttonNegative: 'Cancel',
            buttonPositive: 'OK',
          }
        );
        return granted === PermissionsAndroid.RESULTS.GRANTED;
      }
    } catch (error) {
      console.error('[STTScreen] Permission request error:', error);
      return false;
    }
  };

  /**
   * Start recording audio
   */
  const startRecording = async () => {
    try {
      console.log('[STTScreen] Starting recording...');

      // Request microphone permission first
      const hasPermission = await requestMicrophonePermission();
      if (!hasPermission) {
        console.log('[STTScreen] Microphone permission denied');
        return;
      }

      // Let the library choose its own default path - this avoids file creation issues
      // Record audio with default settings - native module handles format conversion
      // iOS will record to M4A, which our native AudioDecoder can convert to PCM
      console.log('[STTScreen] Starting recorder with default settings...');
      
      // Use default path and settings - most reliable across platforms
      const uri = await audioRecorderPlayer.startRecorder(undefined, undefined, true);

      // Store the returned URI as the recording path
      recordingPath.current = uri;
      console.log('[STTScreen] Recording started at:', uri);

      // Set up progress listener
      audioRecorderPlayer.addRecordBackListener((e) => {
        setRecordingDuration(e.currentPosition);
        // Convert metering level to 0-1 range
        const level = e.currentMetering ? Math.max(0, (e.currentMetering + 60) / 60) : 0;
        setAudioLevel(level);
      });

      setIsRecording(true);
      setTranscript('');
      setConfidence(null);
    } catch (error) {
      console.error('[STTScreen] Error starting recording:', error);
      Alert.alert('Recording Error', `Failed to start recording: ${error}`);
    }
  };

  /**
   * Stop recording and transcribe
   * Native module handles audio format conversion using iOS AudioToolbox
   */
  const stopRecordingAndTranscribe = async () => {
    try {
      console.log('[STTScreen] Stopping recording...');

      // Stop recording
      const uri = await audioRecorderPlayer.stopRecorder();
      audioRecorderPlayer.removeRecordBackListener();
      setIsRecording(false);
      setIsProcessing(true);

      console.log('[STTScreen] Recording stopped, file at:', uri);

      // Use the URI returned by stopRecorder
      let filePath = uri || recordingPath.current;
      if (!filePath) {
        throw new Error('Recording path not found');
      }

      // Normalize path - remove file:// prefix for RNFS and native module
      const normalizedPath = filePath.startsWith('file://')
        ? filePath.substring(7)
        : filePath;

      console.log('[STTScreen] Normalized path:', normalizedPath);

      const exists = await RNFS.exists(normalizedPath);
      if (!exists) {
        throw new Error('Recorded file not found at: ' + normalizedPath);
      }

      const stat = await RNFS.stat(normalizedPath);
      console.log('[STTScreen] Recording file size:', stat.size, 'bytes');

      if (stat.size < 1000) {
        throw new Error('Recording too short');
      }

      // Check if model is loaded
      const isLoaded = await RunAnywhere.isSTTModelLoaded();
      if (!isLoaded) {
        throw new Error('STT model not loaded');
      }

      // Transcribe the audio file - native module handles format conversion
      // iOS AudioToolbox converts M4A/CAF/WAV to 16kHz mono float32 PCM
      console.log('[STTScreen] Starting transcription...');
      const result = await RunAnywhere.transcribeFile(normalizedPath, { language: 'en' });

      console.log('[STTScreen] Transcription result:', result);

      if (result.text) {
        setTranscript(result.text);
        setConfidence(result.confidence);
      } else {
        setTranscript('(No speech detected)');
      }

      // Clean up temp file
      await RNFS.unlink(normalizedPath).catch(() => {});
      recordingPath.current = null;

    } catch (error: any) {
      console.error('[STTScreen] Transcription error:', error);
      Alert.alert('Transcription Error', error.message || `${error}`);
      setTranscript('');
    } finally {
      setIsProcessing(false);
      setRecordingDuration(0);
      setAudioLevel(0);
    }
  };

  /**
   * Start live transcription mode using SDK streaming (AVAudioEngine-based)
   * This uses the native SDK's real-time audio capture, matching Swift SDK pattern
   */
  const startLiveTranscription = async () => {
    try {
      console.log('[STTScreen] Starting SDK streaming transcription...');

      // Request microphone permission first
      const hasPermission = await requestMicrophonePermission();
      if (!hasPermission) {
        console.log('[STTScreen] Microphone permission denied');
        return;
      }

      // Reset state
      accumulatedTranscriptRef.current = '';
      setTranscript('');
      setPartialTranscript('');
      setConfidence(null);

      // Start SDK streaming with callbacks
      const success = await RunAnywhere.startStreamingSTT(
        'en',
        // onPartial callback - show partial results as they come in
        (text: string, conf: number) => {
          console.log('[STTScreen] Partial result:', text, 'confidence:', conf);
          setPartialTranscript(text);
        },
        // onFinal callback - append final results to accumulated transcript
        (text: string, conf: number) => {
          console.log('[STTScreen] Final result:', text, 'confidence:', conf);
          if (text && text.trim()) {
            const newText = text.trim();
            if (accumulatedTranscriptRef.current) {
              accumulatedTranscriptRef.current += ' ' + newText;
            } else {
              accumulatedTranscriptRef.current = newText;
            }
            setTranscript(accumulatedTranscriptRef.current);
            setPartialTranscript('');
            setConfidence(conf);
          }
        },
        // onError callback
        (error: string) => {
          console.error('[STTScreen] Streaming STT error:', error);
          Alert.alert('Transcription Error', error);
        }
      );

      if (success) {
        setIsRecording(true);
        console.log('[STTScreen] SDK streaming started successfully');
      } else {
        const error = await RunAnywhere.getLastError();
        Alert.alert('Error', `Failed to start streaming: ${error || 'Unknown error'}`);
      }

    } catch (error) {
      console.error('[STTScreen] Error starting SDK streaming:', error);
      Alert.alert('Recording Error', `Failed to start live transcription: ${error}`);
    }
  };

  /**
   * Stop live transcription
   */
  const stopLiveTranscription = async () => {
    console.log('[STTScreen] Stopping SDK streaming transcription...');

    try {
      setIsProcessing(true);
      await RunAnywhere.stopStreamingSTT();
      console.log('[STTScreen] SDK streaming stopped');
    } catch (error) {
      console.error('[STTScreen] Error stopping SDK streaming:', error);
    } finally {
      setIsRecording(false);
      setIsProcessing(false);
      setPartialTranscript('');
      setRecordingDuration(0);
      setAudioLevel(0);
    }
  };

  /**
   * Toggle recording
   */
  const handleToggleRecording = useCallback(async () => {
    if (isRecording) {
      // Stop recording based on mode
      if (mode === STTMode.Live) {
        await stopLiveTranscription();
      } else {
        await stopRecordingAndTranscribe();
      }
    } else {
      if (!currentModel) {
        Alert.alert('Model Required', 'Please select an STT model first.');
        return;
      }
      // Start recording based on mode
      if (mode === STTMode.Live) {
        await startLiveTranscription();
      } else {
        await startRecording();
      }
    }
  }, [isRecording, currentModel, mode]);

  /**
   * Clear transcript
   */
  const handleClear = useCallback(() => {
    setTranscript('');
    setPartialTranscript('');
    setConfidence(null);
    accumulatedTranscriptRef.current = '';
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

  /**
   * Render audio level indicator
   */
  const renderAudioLevel = () => {
    if (!isRecording) return null;

    return (
      <View style={styles.audioLevelContainer}>
        <View style={styles.audioLevelTrack}>
          <View
            style={[
              styles.audioLevelFill,
              { width: `${Math.min(100, audioLevel * 100)}%` },
            ]}
          />
        </View>
        <Text style={styles.recordingTime}>{formatDuration(recordingDuration)}</Text>
      </View>
    );
  };

  // Show model required overlay if no model
  if (!currentModel && !isModelLoading) {
    return (
      <SafeAreaView style={styles.container}>
        {renderHeader()}
        <ModelRequiredOverlay
          modality={ModelModality.STT}
          onSelectModel={handleSelectModel}
        />
        {/* Model Selection Sheet */}
        <ModelSelectionSheet
          visible={showModelSelection}
          context={ModelSelectionContext.STT}
          onClose={() => setShowModelSelection(false)}
          onModelSelected={handleModelSelected}
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

      {/* Audio Level Indicator */}
      {renderAudioLevel()}

      {/* Transcription Area */}
      <ScrollView style={styles.transcriptContainer} contentContainerStyle={styles.transcriptContent}>
        {transcript || partialTranscript ? (
          <>
            <Text style={styles.transcriptText}>
              {transcript}
              {partialTranscript ? (
                <Text style={styles.partialTranscript}> {partialTranscript}</Text>
              ) : null}
            </Text>
            {confidence !== null && !isRecording && (
              <View style={styles.confidenceContainer}>
                <Text style={styles.confidenceLabel}>Confidence:</Text>
                <Text style={styles.confidenceValue}>
                  {Math.round(confidence * 100)}%
                </Text>
              </View>
            )}
            {isRecording && mode === STTMode.Live && (
              <View style={styles.liveIndicator}>
                <Animated.View
                  style={[
                    styles.liveDot,
                    { transform: [{ scale: pulseAnim }] },
                  ]}
                />
                <Text style={styles.liveText}>Live transcribing...</Text>
              </View>
            )}
          </>
        ) : isProcessing ? (
          <View style={styles.processingContainer}>
            <Icon name="hourglass-outline" size={24} color={Colors.textSecondary} />
            <Text style={styles.processingText}>Transcribing audio...</Text>
          </View>
        ) : isRecording ? (
          <View style={styles.recordingContainer}>
            <Animated.View
              style={[
                styles.recordingIndicator,
                { transform: [{ scale: pulseAnim }] },
              ]}
            />
            <Text style={styles.recordingText}>
              {mode === STTMode.Live ? 'Live transcribing...' : 'Listening...'}
            </Text>
            <Text style={styles.recordingHint}>
              {mode === STTMode.Live
                ? 'Text will appear as you speak'
                : 'Tap the button when done speaking'}
            </Text>
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

      {/* Model Selection Sheet */}
      <ModelSelectionSheet
        visible={showModelSelection}
        context={ModelSelectionContext.STT}
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
  audioLevelContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginHorizontal: Padding.padding16,
    marginTop: Spacing.medium,
    gap: Spacing.medium,
  },
  audioLevelTrack: {
    flex: 1,
    height: 4,
    backgroundColor: Colors.backgroundGray5,
    borderRadius: 2,
    overflow: 'hidden',
  },
  audioLevelFill: {
    height: '100%',
    backgroundColor: Colors.primaryGreen,
  },
  recordingTime: {
    ...Typography.caption,
    color: Colors.textSecondary,
    minWidth: 40,
    textAlign: 'right',
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
  partialTranscript: {
    color: Colors.textSecondary,
    fontStyle: 'italic',
  },
  liveIndicator: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.small,
    marginTop: Spacing.medium,
    paddingTop: Spacing.medium,
    borderTopWidth: 1,
    borderTopColor: Colors.borderLight,
  },
  liveDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: Colors.primaryRed,
  },
  liveText: {
    ...Typography.footnote,
    color: Colors.textSecondary,
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
    width: 20,
    height: 20,
    borderRadius: 10,
    backgroundColor: Colors.primaryRed,
  },
  recordingText: {
    ...Typography.body,
    color: Colors.textPrimary,
  },
  recordingHint: {
    ...Typography.footnote,
    color: Colors.textSecondary,
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
