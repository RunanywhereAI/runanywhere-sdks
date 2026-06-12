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
 * - Uses the SDK's AudioCaptureManager (16kHz mono Int16 PCM chunks)
 * - Model loading via RunAnywhere.loadModel(ModelLoadRequest)
 * - Transcription via RunAnywhere.transcribe() with proto-canonical STT options
 * - Supports ONNX-based Whisper models
 *
 * Reference: iOS examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Voice/SpeechToTextView.swift
 */

import React, { useState, useCallback, useEffect, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  Alert,
  Platform,
  Animated,
  PermissionsAndroid,
  Linking,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import {
  SafeAreaView,
  useSafeAreaInsets,
} from 'react-native-safe-area-context';
import { useFocusEffect } from '@react-navigation/native';
import { check, request, PERMISSIONS, RESULTS } from 'react-native-permissions';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding, BorderRadius, ButtonHeight } from '../theme/spacing';
import { ModelStatusBanner, ModelRequiredOverlay } from '../components/common';
import {
  ModelSelectionSheet,
  ModelSelectionContext,
} from '../components/model';
import { STTMode } from '../types/voice';

// Import RunAnywhere SDK (Multi-Package Architecture)
import {
  RunAnywhere,
  AudioCaptureManager,
  createPushableAudioStream,
  type PushableAudioStream,
} from '@runanywhere/core';
import {
  AudioFormat,
  ModelCategory,
  ModelLoadRequest,
  type ModelInfo as SDKModelInfo,
} from '@runanywhere/proto-ts/model_types';
import {
  STTLanguage,
  type STTPartialResult,
} from '@runanywhere/proto-ts/stt_options';
import { isModelLoadedForCategory } from '../utils/runAnywhereLifecycle';

/** SDK capture emits 16kHz mono Int16 PCM. */
const CAPTURE_SAMPLE_RATE = 16000;
const CAPTURE_BYTES_PER_MS = (CAPTURE_SAMPLE_RATE * 2) / 1000;

/** Wrap raw 16kHz mono Int16 PCM bytes in a WAV container. */
function wrapPcm16InWav(pcmChunks: Uint8Array[]): Uint8Array {
  const dataSize = pcmChunks.reduce((sum, chunk) => sum + chunk.length, 0);
  const wav = new Uint8Array(44 + dataSize);
  const view = new DataView(wav.buffer);

  const writeString = (offset: number, str: string) => {
    for (let i = 0; i < str.length; i++) {
      view.setUint8(offset + i, str.charCodeAt(i));
    }
  };

  writeString(0, 'RIFF');
  view.setUint32(4, 36 + dataSize, true);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  view.setUint32(16, 16, true); // PCM fmt chunk size
  view.setUint16(20, 1, true); // PCM
  view.setUint16(22, 1, true); // mono
  view.setUint32(24, CAPTURE_SAMPLE_RATE, true);
  view.setUint32(28, CAPTURE_SAMPLE_RATE * 2, true); // byte rate
  view.setUint16(32, 2, true); // block align
  view.setUint16(34, 16, true); // bits per sample
  writeString(36, 'data');
  view.setUint32(40, dataSize, true);

  let offset = 44;
  for (const chunk of pcmChunks) {
    wav.set(chunk, offset);
    offset += chunk.length;
  }
  return wav;
}

async function transcribePcmChunks(pcmChunks: Uint8Array[]) {
  return RunAnywhere.transcribe(wrapPcm16InWav(pcmChunks), {
    language: STTLanguage.STT_LANGUAGE_EN,
    audioFormat: AudioFormat.AUDIO_FORMAT_WAV,
    sampleRate: CAPTURE_SAMPLE_RATE,
  });
}

// Canonical SDK methods (Swift parity).
const listModels = async (): Promise<SDKModelInfo[]> =>
  (await RunAnywhere.listModels()).models?.models ?? [];
const loadModelWithRequest = RunAnywhere.loadModel;

export const STTScreen: React.FC = () => {
  // State
  const [mode, setMode] = useState<STTMode>(STTMode.Batch);
  const [isRecording, setIsRecording] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [transcript, setTranscript] = useState('');
  const [partialTranscript, setPartialTranscript] = useState(''); // For live mode - current chunk
  const [confidence, setConfidence] = useState<number | null>(null);
  const [currentModel, setCurrentModel] = useState<SDKModelInfo | null>(null);
  const [isModelLoading, setIsModelLoading] = useState(false);
  const [_availableModels, setAvailableModels] = useState<SDKModelInfo[]>([]);
  const [recordingDuration, setRecordingDuration] = useState(0);
  const [audioLevel, setAudioLevel] = useState(0);
  const [showModelSelection, setShowModelSelection] = useState(false);

  // Safe area insets for header status bar handling
  const insets = useSafeAreaInsets();

  // SDK audio capture manager (one per screen instance)
  const captureManagerRef = useRef<AudioCaptureManager | null>(null);
  const getCaptureManager = (): AudioCaptureManager => {
    if (!captureManagerRef.current) {
      captureManagerRef.current = new AudioCaptureManager();
    }
    return captureManagerRef.current;
  };

  // Accumulated 16kHz mono Int16 PCM chunks for the in-flight recording
  const pcmChunksRef = useRef<Uint8Array[]>([]);
  const pcmBytesRef = useRef(0);

  // Live mode accumulated transcript ref
  const accumulatedTranscriptRef = useRef('');

  // Live mode streaming refs
  const liveAudioStreamRef = useRef<PushableAudioStream | null>(null);
  const liveTranscriptionTaskRef = useRef<Promise<void> | null>(null);
  const isLiveRecordingRef = useRef(false);

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
      liveAudioStreamRef.current?.close();
      liveAudioStreamRef.current = null;
      // Stop the SDK capture manager
      try {
        captureManagerRef.current?.stopRecording();
      } catch {
        // Ignore — capture may never have started
      }
      pcmChunksRef.current = [];
      pcmBytesRef.current = 0;
    };
  }, []);

  /**
   * Load available models and check for loaded model
   * Called on mount and when screen comes into focus
   */
  const loadModels = useCallback(async () => {
    try {
      // Get available STT models from catalog
      const allModels = await listModels();
      // Filter by category (speech-recognition) matching SDK's ModelCategory
      const sttModels = allModels.filter(
        (m: SDKModelInfo) =>
          m.category === ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
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

      // Ask the SDK for the loaded STT model directly.
      if (!currentModel) {
        const loaded = await RunAnywhere.modelInfoForCategory(
          ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
        );
        if (loaded) {
          setCurrentModel(loaded);
          console.warn('[STTScreen] Loaded STT model:', loaded.name);
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
   * Load a model from its info via the canonical lifecycle ABI.
   *
   * Path-first loading was removed in V2 — model ID is the canonical handle
   * and the native registry resolves the artifact path internally.
   */
  const loadModel = async (model: SDKModelInfo) => {
    try {
      setIsModelLoading(true);
      console.warn(
        `[STTScreen] Loading model: ${model.id} (registry will resolve path)`
      );

      if (!model.isDownloaded && !model.localPath) {
        Alert.alert(
          'Error',
          'Model has not been downloaded. Open the model picker to download it first.'
        );
        return;
      }

      const result = await loadModelWithRequest(
        ModelLoadRequest.fromPartial({
          modelId: model.id,
          category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
          forceReload: false,
          validateAvailability: true,
        })
      );

      if (result.success) {
        const isLoaded = await isModelLoadedForCategory(
          ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
        );
        if (isLoaded) {
          const loaded = await RunAnywhere.modelInfoForCategory(
            ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
          );
          setCurrentModel(loaded ?? model);
          console.warn(
            `[STTScreen] Model ${model.name} loaded successfully, currentModel set`
          );
        } else {
          console.warn(
            '[STTScreen] Model reported success but lifecycle currentModel() returned no STT model'
          );
        }
      } else {
        const error =
          result.errorMessage ||
          'Native model lifecycle returned an unsuccessful load result';
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
   * Begin SDK microphone capture, accumulating PCM chunks in memory.
   * Audio level + recording duration come straight from the capture stream.
   */
  const beginCapture = async (onChunk?: (chunk: Uint8Array) => void) => {
    const capture = getCaptureManager();
    pcmChunksRef.current = [];
    pcmBytesRef.current = 0;
    await capture.startRecording((chunk: Uint8Array) => {
      if (onChunk) {
        onChunk(chunk);
      } else {
        pcmChunksRef.current.push(chunk);
      }
      pcmBytesRef.current += chunk.length;
      setAudioLevel(capture.audioLevel);
      setRecordingDuration(pcmBytesRef.current / CAPTURE_BYTES_PER_MS);
    });
  };

  /**
   * Drain the accumulated PCM chunks (resets the buffer).
   */
  const drainCapturedChunks = (): Uint8Array[] => {
    const chunks = pcmChunksRef.current;
    pcmChunksRef.current = [];
    pcmBytesRef.current = 0;
    return chunks;
  };

  /**
   * Start recording audio (batch mode)
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

      console.warn('[STTScreen] Starting SDK audio capture...');
      await beginCapture();

      setIsRecording(true);
      setTranscript('');
      setConfidence(null);
    } catch (error) {
      console.error('[STTScreen] Error starting recording:', error);
      Alert.alert('Recording Error', `Failed to start recording: ${error}`);
    }
  };

  /**
   * Stop recording and transcribe the in-memory PCM buffer.
   */
  const stopRecordingAndTranscribe = async () => {
    try {
      console.warn('[STTScreen] Stopping recording...');

      getCaptureManager().stopRecording();
      setIsRecording(false);
      setIsProcessing(true);

      const chunks = drainCapturedChunks();
      const totalBytes = chunks.reduce((sum, c) => sum + c.length, 0);
      console.warn('[STTScreen] Recording size:', totalBytes, 'bytes');

      if (totalBytes < 1000) {
        throw new Error('Recording too short');
      }

      // Check if model is loaded
      const isLoaded = await isModelLoadedForCategory(
        ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
      );
      if (!isLoaded) {
        throw new Error('STT model not loaded');
      }

      console.warn('[STTScreen] Starting transcription...');
      const result = await transcribePcmChunks(chunks);

      console.warn('[STTScreen] Transcription result:', result);

      if (result.text) {
        setTranscript(result.text);
        setConfidence(result.confidence);
      } else {
        setTranscript('(No speech detected)');
      }
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
   */
  const startLiveTranscription = async () => {
    try {
      console.warn('[STTScreen] Starting live transcription stream...');

      const hasPermission = await requestMicrophonePermission();
      if (!hasPermission) {
        console.warn('[STTScreen] Microphone permission denied');
        return;
      }

      const isLoaded = await isModelLoadedForCategory(
        ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
      );
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

      const audioStream = createPushableAudioStream();
      liveAudioStreamRef.current = audioStream;
      const partials = RunAnywhere.transcribeStream(audioStream.iterable, {
        language: STTLanguage.STT_LANGUAGE_EN,
        audioFormat: AudioFormat.AUDIO_FORMAT_PCM,
        sampleRate: CAPTURE_SAMPLE_RATE,
      });
      liveTranscriptionTaskRef.current = consumeLiveTranscription(partials);

      await beginCapture((chunk) => audioStream.push(chunk));
      setIsRecording(true);

      console.warn('[STTScreen] Live transcription started');
    } catch (error) {
      console.error('[STTScreen] Error starting live transcription:', error);
      Alert.alert(
        'Recording Error',
        `Failed to start live transcription: ${error}`
      );
      isLiveRecordingRef.current = false;
      liveAudioStreamRef.current?.close();
    }
  };

  const consumeLiveTranscription = async (
    partials: AsyncIterable<STTPartialResult>
  ) => {
    const iterator = partials[Symbol.asyncIterator]();
    try {
      let step = await iterator.next();
      while (!step.done) {
        const partial = step.value;
        const finalText = partial.finalOutput?.text?.trim();
        const text = (finalText || partial.text || '').trim();
        if (text) {
          if (partial.isFinal || finalText) {
            accumulatedTranscriptRef.current = text;
            setTranscript(text);
            setPartialTranscript('');
            setConfidence(partial.finalOutput?.confidence ?? null);
          } else {
            setPartialTranscript(text);
          }
        }
        step = await iterator.next();
      }
    } catch (error) {
      console.error('[STTScreen] Live transcription stream error:', error);
    } finally {
      await iterator.return?.();
    }
  };

  /**
   * Stop live transcription and transcribe any remaining audio.
   */
  const stopLiveTranscription = async () => {
    console.warn('[STTScreen] Stopping live transcription...');
    isLiveRecordingRef.current = false;

    try {
      setIsProcessing(true);
      setPartialTranscript('Finalizing...');

      getCaptureManager().stopRecording();
      liveAudioStreamRef.current?.close();
      await liveTranscriptionTaskRef.current;
      liveAudioStreamRef.current = null;
      liveTranscriptionTaskRef.current = null;

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
    <View
      style={[styles.header, { paddingTop: insets.top + Padding.padding12 }]}
    >
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
          modality="stt"
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
    paddingTop: 0,
    paddingBottom: Padding.padding12,
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
