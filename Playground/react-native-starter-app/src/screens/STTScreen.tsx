/**
 * STTScreen - Tab 1: Speech-to-Text
 *
 * Provides on-device speech recognition with real-time transcription.
 * Matches iOS SpeechToTextView architecture and patterns.
 *
 * Features:
 * - Batch mode: Record first, then transcribe
 * - Live mode: Real-time transcription (streaming)
 * - Model selection sheet
 * - Audio level visualization
 * - Model status banner
 *
 * Architecture:
 * - Uses native audio recording (AudioService)
 * - Model loading via RunAnywhere.loadSTTModel()
 * - Transcription via RunAnywhere.transcribeAudio()
 * - Supports ONNX-based Whisper models
 *
 * Reference: iOS examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Voice/SpeechToTextView.swift
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
import RNFS from 'react-native-fs';
import { check, request, PERMISSIONS, RESULTS } from 'react-native-permissions';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding, BorderRadius, ButtonHeight } from '../theme/spacing';
import { ModelStatusBanner, ModelRequiredOverlay } from '../components/common';
import {
  ModelSelectionSheet,
  ModelSelectionContext,
} from '../components/model';
import type { ModelInfo } from '../types/model';
import { ModelModality, LLMFramework } from '../types/model';
import { STTMode } from '../types/voice';

// Import RunAnywhere SDK (Multi-Package Architecture)
import { RunAnywhere, type ModelInfo as SDKModelInfo } from '@runanywhere/core';

// STT Model IDs (kept for reference, uses SDK model registry)
const _STT_MODEL_IDS = ['whisper-tiny-en', 'whisper-base-en'];

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
  const [_availableModels, setAvailableModels] = useState<SDKModelInfo[]>([]);
  const [recordingDuration, setRecordingDuration] = useState(0);
  const [audioLevel, setAudioLevel] = useState(0);
  const [showModelSelection, setShowModelSelection] = useState(false);

  // Audio recording path ref (for batch mode only)
  const recordingPath = useRef<string | null>(null);

  // Live mode accumulated transcript ref
  const accumulatedTranscriptRef = useRef('');

  // Live mode interval-based recording refs
  const liveRecordingIntervalRef = useRef<NodeJS.Timeout | null>(null);
  const isLiveRecordingRef = useRef(false);
  const liveChunkCountRef = useRef(0);

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
      // Stop live recording if active
      isLiveRecordingRef.current = false;
      if (liveRecordingIntervalRef.current) {
        clearTimeout(liveRecordingIntervalRef.current);
        liveRecordingIntervalRef.current = null;
      }
      // Stop SDK streaming if active (method may not be exposed on public API)
      const sdk = RunAnywhere as unknown as Record<string, unknown>;
      if (typeof sdk.stopStreamingSTT === 'function') {
        (sdk.stopStreamingSTT as () => Promise<boolean>)().catch(() => {});
      }
      // Stop batch mode recorder
      RunAnywhere.Audio.cleanup().catch(() => {});
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
      const sttModels = allModels.filter(
        (m: SDKModelInfo) => m.category === 'speech-recognition'
      );
      setAvailableModels(sttModels);

      // Log downloaded status for debugging
      const downloadedModels = sttModels.filter((m) => m.isDownloaded);
      console.warn(
        '[STTScreen] Available STT models:',
        sttModels.map((m) => `${m.id} (downloaded: ${m.isDownloaded})`)
      );
      console.warn(
        '[STTScreen] Downloaded STT models:',
        downloadedModels.map((m) => m.id)
      );

      // Check if model is already loaded
      const isLoaded = await RunAnywhere.isSTTModelLoaded();
      console.warn('[STTScreen] isSTTModelLoaded:', isLoaded);
      if (isLoaded && !currentModel) {
        // Try to find which model is loaded from downloaded models
        const downloadedStt = sttModels.filter((m) => m.isDownloaded);
        if (downloadedStt.length > 0) {
          const firstModel = downloadedStt[0];
          if (firstModel) {
            setCurrentModel({
              id: firstModel.id,
              name: firstModel.name,
              preferredFramework: LLMFramework.ONNX,
            } as ModelInfo);
            console.warn(
              '[STTScreen] Set currentModel from downloaded:',
              firstModel.name
            );
          }
        } else {
          setCurrentModel({
            id: 'stt-model',
            name: 'STT Model (Loaded)',
            preferredFramework: LLMFramework.ONNX,
          } as ModelInfo);
          console.warn('[STTScreen] Set currentModel as generic STT Model');
        }
      }
    } catch (error) {
      console.warn('[STTScreen] Error loading models:', error);
    }
  }, [currentModel]);

  // Refresh models when screen comes into focus
  // This ensures we pick up any models downloaded in the Settings tab
  useFocusEffect(
    useCallback(() => {
      console.warn('[STTScreen] Screen focused - refreshing models');
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
    // Close the modal first to prevent UI issues
    setShowModelSelection(false);
    // Then load the model
    await loadModel(model);
  }, []);

  /**
   * Load a model from its info
   */
  const loadModel = async (model: SDKModelInfo) => {
    try {
      setIsModelLoading(true);
      console.warn(
        `[STTScreen] Loading model: ${model.id} from ${model.localPath}`
      );

      if (!model.localPath) {
        Alert.alert(
          'Error',
          'Model path not found. Please re-download the model.'
        );
        return;
      }

      // Pass the path directly - C++ extractArchiveIfNeeded handles archive extraction
      // and finding the correct nested model folder
      const success = await RunAnywhere.loadSTTModel(
        model.localPath,
        model.category || 'whisper'
      );

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
          console.warn(
            `[STTScreen] Model ${model.name} loaded successfully, currentModel set`
          );
        } else {
          console.warn(
            `[STTScreen] Model reported success but isSTTModelLoaded() returned false`
          );
        }
      } else {
        const error = await RunAnywhere.getLastError();
        Alert.alert(
          'Error',
          `Failed to load model: ${error || 'Unknown error'}`
        );
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
        console.warn('[STTScreen] iOS microphone permission status:', status);

        if (status === RESULTS.GRANTED) {
          return true;
        }

        if (status === RESULTS.DENIED) {
          const result = await request(PERMISSIONS.IOS.MICROPHONE);
          console.warn(
            '[STTScreen] iOS microphone permission request result:',
            result
          );
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
            message:
              'RunAnywhereAI needs access to your microphone for speech-to-text.',
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
      console.warn('[STTScreen] Starting recording...');

      // Request microphone permission first
      const hasPermission = await requestMicrophonePermission();
      if (!hasPermission) {
        console.warn('[STTScreen] Microphone permission denied');
        return;
      }

      // Start recording using expo-av
      console.warn('[STTScreen] Starting recorder...');
      const uri = await RunAnywhere.Audio.startRecording({
        onProgress: (currentPositionMs, metering) => {
          setRecordingDuration(currentPositionMs);
          // Convert metering level to 0-1 range (metering is typically negative dB)
          const level = metering
            ? Math.max(0, Math.min(1, (metering + 60) / 60))
            : 0;
          setAudioLevel(level);
        },
      });

      // Store the returned URI as the recording path
      recordingPath.current = uri;
      console.warn('[STTScreen] Recording started at:', uri);

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
      console.warn('[STTScreen] Stopping recording...');

      // Stop recording
      const { uri } = await RunAnywhere.Audio.stopRecording();
      setIsRecording(false);
      setIsProcessing(true);

      console.warn('[STTScreen] Recording stopped, file at:', uri);

      // Use the URI returned by stopRecorder
      const filePath = uri || recordingPath.current;
      if (!filePath) {
        throw new Error('Recording path not found');
      }

      // Normalize path - remove file:// prefix for RNFS and native module
      const normalizedPath = filePath.startsWith('file://')
        ? filePath.substring(7)
        : filePath;

      console.warn('[STTScreen] Normalized path:', normalizedPath);

      const exists = await RNFS.exists(normalizedPath);
      if (!exists) {
        throw new Error('Recorded file not found at: ' + normalizedPath);
      }

      const stat = await RNFS.stat(normalizedPath);
      console.warn('[STTScreen] Recording file size:', stat.size, 'bytes');

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
      console.warn('[STTScreen] Starting transcription...');
      const result = await RunAnywhere.transcribeFile(normalizedPath, {
        language: 'en',
      });

      console.warn('[STTScreen] Transcription result:', result);

      if (result.text) {
        setTranscript(result.text);
        setConfidence(result.confidence);
      } else {
        setTranscript('(No speech detected)');
      }

      // Clean up temp file
      await RNFS.unlink(normalizedPath).catch(() => {});
      recordingPath.current = null;
    } catch (error: unknown) {
      console.error('[STTScreen] Transcription error:', error);
      const errorMessage =
        error instanceof Error ? error.message : String(error);
      Alert.alert('Transcription Error', errorMessage);
      setTranscript('');
    } finally {
      setIsProcessing(false);
      setRecordingDuration(0);
      setAudioLevel(0);
    }
  };

  /**
   * Start live transcription mode
   *
   * Implements pseudo-streaming for Whisper models (which are batch-only):
   * Records audio in intervals (3 seconds), transcribes each chunk, and
   * accumulates results for a live-like experience matching Swift SDK.
   */
  const startLiveTranscription = async () => {
    try {
      console.warn(
        '[STTScreen] Starting live transcription (pseudo-streaming)...'
      );

      // Request microphone permission first
      const hasPermission = await requestMicrophonePermission();
      if (!hasPermission) {
        console.warn('[STTScreen] Microphone permission denied');
        return;
      }

      // Check if model is loaded
      const isLoaded = await RunAnywhere.isSTTModelLoaded();
      if (!isLoaded) {
        Alert.alert('Model Not Loaded', 'Please load an STT model first.');
        return;
      }

      // Reset state
      accumulatedTranscriptRef.current = '';
      setTranscript('');
      setPartialTranscript('Listening...');
      setConfidence(null);
      setRecordingDuration(0);
      isLiveRecordingRef.current = true;
      liveChunkCountRef.current = 0;

      // Start initial recording chunk
      await startLiveChunk();
      setIsRecording(true);

      console.warn('[STTScreen] Live transcription started');
    } catch (error) {
      console.error('[STTScreen] Error starting live transcription:', error);
      Alert.alert(
        'Recording Error',
        `Failed to start live transcription: ${error}`
      );
      isLiveRecordingRef.current = false;
    }
  };

  /**
   * Start recording a live chunk (called repeatedly for pseudo-streaming)
   */
  const startLiveChunk = async () => {
    if (!isLiveRecordingRef.current) {
      console.warn(
        '[STTScreen] Live recording stopped, not starting new chunk'
      );
      return;
    }

    try {
      liveChunkCountRef.current++;
      const chunkNum = liveChunkCountRef.current;
      console.warn(`[STTScreen] Starting live chunk #${chunkNum}...`);

      // Record with expo-av
      const path = await RunAnywhere.Audio.startRecording({
        onProgress: (currentPositionMs, metering) => {
          const duration = Math.floor(currentPositionMs / 1000);
          setRecordingDuration(duration);
          // Update audio level from metering
          if (metering !== undefined) {
            const normalized = Math.max(0, Math.min(1, (metering + 60) / 60));
            setAudioLevel(normalized);
          }
        },
      });
      recordingPath.current = path;
      console.warn(`[STTScreen] Live chunk #${chunkNum} recording at:`, path);

      // Schedule transcription after interval (3 seconds for each chunk)
      liveRecordingIntervalRef.current = setTimeout(async () => {
        if (isLiveRecordingRef.current) {
          await transcribeLiveChunk();
        }
      }, 3000);
    } catch (error) {
      console.error('[STTScreen] Error starting live chunk:', error);
    }
  };

  /**
   * Transcribe the current live chunk and start the next one
   * Uses react-native-audio-api for audio decoding
   */
  const transcribeLiveChunk = async () => {
    if (!isLiveRecordingRef.current) {
      return;
    }

    try {
      console.warn('[STTScreen] Transcribing live chunk...');
      setPartialTranscript('Processing...');

      // Stop current recording
      const { uri: resultPath } = await RunAnywhere.Audio.stopRecording();

      // Get the path
      let audioPath = resultPath;
      if (audioPath.startsWith('file://')) {
        audioPath = audioPath.replace('file://', '');
      }

      // Check file exists
      const exists = await RNFS.exists(audioPath);
      if (!exists) {
        console.warn('[STTScreen] Live chunk file not found');
        setPartialTranscript('Listening...');
        if (isLiveRecordingRef.current) {
          await startLiveChunk();
        }
        return;
      }

      // Check file size (skip very small files)
      const stat = await RNFS.stat(audioPath);
      if (stat.size < 5000) {
        console.warn('[STTScreen] Chunk too small, skipping transcription');
        setPartialTranscript('Listening...');
        if (isLiveRecordingRef.current) {
          await startLiveChunk();
        }
        return;
      }

      // Transcribe using native module (handles audio decoding)
      const result = await RunAnywhere.transcribeFile(audioPath, {
        language: 'en',
      });
      console.warn('[STTScreen] Live chunk transcription:', result.text);

      // Append to accumulated transcript if we got text
      if (result.text && result.text.trim() && result.text.trim() !== '') {
        const newText = result.text.trim();
        if (accumulatedTranscriptRef.current) {
          accumulatedTranscriptRef.current += ' ' + newText;
        } else {
          accumulatedTranscriptRef.current = newText;
        }
        setTranscript(accumulatedTranscriptRef.current);
        setConfidence(result.confidence || null);
      }

      // Clean up chunk file
      await RNFS.unlink(audioPath).catch(() => {});

      // Update partial transcript for next chunk
      setPartialTranscript('Listening...');

      // Start next chunk if still recording
      if (isLiveRecordingRef.current) {
        await startLiveChunk();
      }
    } catch (error) {
      console.error('[STTScreen] Error transcribing live chunk:', error);
      setPartialTranscript('Listening...');
      // Try to continue with next chunk
      if (isLiveRecordingRef.current) {
        await startLiveChunk();
      }
    }
  };

  /**
   * Stop live transcription
   * Uses react-native-audio-api for final chunk decoding
   */
  const stopLiveTranscription = async () => {
    console.warn('[STTScreen] Stopping live transcription...');
    isLiveRecordingRef.current = false;

    // Clear any pending interval
    if (liveRecordingIntervalRef.current) {
      clearTimeout(liveRecordingIntervalRef.current);
      liveRecordingIntervalRef.current = null;
    }

    try {
      setIsProcessing(true);
      setPartialTranscript('Processing final chunk...');

      // Stop current recording
      const { uri: resultPath } = await RunAnywhere.Audio.stopRecording().catch(
        () => ({ uri: '', durationMs: 0 })
      );

      // Transcribe final chunk if there's audio
      if (resultPath && recordingPath.current) {
        let audioPath = resultPath;
        if (audioPath.startsWith('file://')) {
          audioPath = audioPath.replace('file://', '');
        }

        const exists = await RNFS.exists(audioPath);
        if (exists) {
          const stat = await RNFS.stat(audioPath);
          if (stat.size >= 5000) {
            console.warn('[STTScreen] Transcribing final live chunk...');
            // Transcribe using native module (handles audio decoding)
            const result = await RunAnywhere.transcribeFile(audioPath, {
              language: 'en',
            });
            if (result.text && result.text.trim()) {
              const newText = result.text.trim();
              if (accumulatedTranscriptRef.current) {
                accumulatedTranscriptRef.current += ' ' + newText;
              } else {
                accumulatedTranscriptRef.current = newText;
              }
              setTranscript(accumulatedTranscriptRef.current);
              setConfidence(result.confidence || null);
            }
          }
          await RNFS.unlink(audioPath).catch(() => {});
        }
      }

      console.warn('[STTScreen] Live transcription stopped');
      console.warn(
        '[STTScreen] Final transcript:',
        accumulatedTranscriptRef.current
      );
    } catch (error) {
      console.error('[STTScreen] Error stopping live transcription:', error);
    } finally {
      setIsRecording(false);
      setIsProcessing(false);
      setPartialTranscript('');
      setRecordingDuration(0);
      setAudioLevel(0);
      recordingPath.current = null;
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
    // eslint-disable-next-line react-hooks/exhaustive-deps
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
        name={
          mode === STTMode.Batch ? 'document-text-outline' : 'pulse-outline'
        }
        size={20}
        color={Colors.primaryBlue}
      />
      <Text style={styles.modeDescriptionText}>
        {mode === STTMode.Batch
          ? 'Record audio, then transcribe all at once for best accuracy.'
          : 'Transcribes every few seconds while you speak.'}
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
        <Text style={styles.recordingTime}>
          {formatDuration(recordingDuration)}
        </Text>
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
      <ScrollView
        style={styles.transcriptContainer}
        contentContainerStyle={styles.transcriptContent}
      >
        {transcript || partialTranscript ? (
          <>
            <Text style={styles.transcriptText}>
              {transcript}
              {partialTranscript ? (
                <Text style={styles.partialTranscript}>
                  {' '}
                  {partialTranscript}
                </Text>
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
            <Icon
              name="hourglass-outline"
              size={24}
              color={Colors.textSecondary}
            />
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
