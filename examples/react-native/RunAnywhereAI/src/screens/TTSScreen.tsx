/**
 * TTSScreen - Tab 2: Text-to-Speech
 *
 * Reference: iOS Features/Voice/TextToSpeechView.swift
 */

import React, { useState, useCallback, useEffect, useRef } from 'react';
import {
  View,
  Text,
  TextInput,
  StyleSheet,
  SafeAreaView,
  TouchableOpacity,
  ScrollView,
  Alert,
  Platform,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import AudioRecorderPlayer from 'react-native-audio-recorder-player';
import RNFS from 'react-native-fs';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding, BorderRadius, IconSize, ButtonHeight, Layout } from '../theme/spacing';
import { ModelStatusBanner, ModelRequiredOverlay } from '../components/common';
import { ModelInfo, ModelModality, LLMFramework } from '../types/model';

// Import RunAnywhere SDK
import {
  RunAnywhere,
  type ModelInfo as SDKModelInfo,
} from 'runanywhere-react-native';

export const TTSScreen: React.FC = () => {
  // State
  const [text, setText] = useState('');
  const [speed, setSpeed] = useState(1.0);
  const [pitch, setPitch] = useState(1.0);
  const [volume, setVolume] = useState(1.0);
  const [isGenerating, setIsGenerating] = useState(false);
  const [isPlaying, setIsPlaying] = useState(false);
  const [audioGenerated, setAudioGenerated] = useState(false);
  const [duration, setDuration] = useState(0);
  const [currentModel, setCurrentModel] = useState<ModelInfo | null>(null);
  const [isModelLoading, setIsModelLoading] = useState(false);
  const [availableModels, setAvailableModels] = useState<SDKModelInfo[]>([]);
  const [lastGeneratedAudio, setLastGeneratedAudio] = useState<string | null>(null);
  const [currentTime, setCurrentTime] = useState(0);
  const [playbackProgress, setPlaybackProgress] = useState(0);
  const [audioFilePath, setAudioFilePath] = useState<string | null>(null);
  const [sampleRate, setSampleRate] = useState(22050);

  // Audio player ref
  const audioRecorderPlayer = useRef(new AudioRecorderPlayer()).current;

  // Character count
  const charCount = text.length;
  const maxChars = 1000;

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      audioRecorderPlayer.stopPlayer().catch(() => {});
      audioRecorderPlayer.removePlayBackListener();
      // Clean up temp audio file
      if (audioFilePath) {
        RNFS.unlink(audioFilePath).catch(() => {});
      }
    };
  }, [audioFilePath]);

  // Load available models and check for loaded model on mount
  useEffect(() => {
    const initialize = async () => {
      try {
        // Get available TTS models from catalog
        const allModels = await RunAnywhere.getAvailableModels();
        const ttsModels = allModels.filter((m) => m.modality === 'tts');
        setAvailableModels(ttsModels);
        console.log('[TTSScreen] Available TTS models:', ttsModels.map(m => `${m.id} (downloaded: ${m.isDownloaded})`));

        // Check if model is already loaded
        const isLoaded = await RunAnywhere.isTTSModelLoaded();
        console.log('[TTSScreen] Init - isTTSModelLoaded:', isLoaded, 'currentModel:', currentModel);
        if (isLoaded && !currentModel) {
          // Try to find which model is loaded from downloaded models
          const downloadedTts = ttsModels.filter(m => m.isDownloaded);
          if (downloadedTts.length > 0) {
            // Use the first downloaded model as the likely loaded one
            setCurrentModel({
              id: downloadedTts[0]!.id,
              name: downloadedTts[0]!.name,
              preferredFramework: LLMFramework.ONNX,
            } as ModelInfo);
            console.log('[TTSScreen] Init - Set currentModel from downloaded:', downloadedTts[0]!.name);
          } else {
            setCurrentModel({
              id: 'tts-model',
              name: 'TTS Model (Loaded)',
              preferredFramework: LLMFramework.ONNX,
            } as ModelInfo);
            console.log('[TTSScreen] Init - Set currentModel as generic TTS Model');
          }
        }
      } catch (error) {
        console.log('[TTSScreen] Error initializing:', error);
      }
    };
    initialize();
  }, []);

  /**
   * Handle model selection - shows available downloaded models
   */
  const handleSelectModel = useCallback(async () => {
    // Refresh models list to get latest download status
    try {
      const allModels = await RunAnywhere.getAvailableModels();
      const ttsModels = allModels.filter((m) => m.modality === 'tts');
      setAvailableModels(ttsModels);

      // Get downloaded TTS models
      const downloadedModels = ttsModels.filter((m) => m.isDownloaded);
      console.log('[TTSScreen] Downloaded TTS models:', downloadedModels.map(m => m.name));

      if (downloadedModels.length === 0) {
        Alert.alert(
          'No Models Downloaded',
          'Please download a text-to-speech model from the Settings tab first.',
          [{ text: 'OK' }]
        );
        return;
      }

      const buttons = downloadedModels.map((model) => ({
        text: currentModel?.id === model.id ? `${model.name} (Current)` : model.name,
        onPress: () => { loadModel(model); },
      }));
      buttons.push({ text: 'Cancel', onPress: () => { /* no-op */ } });

      Alert.alert('Select TTS Model', 'Choose a downloaded text-to-speech model', buttons as any);
    } catch (error) {
      console.error('[TTSScreen] Error refreshing models:', error);
      Alert.alert('Error', 'Failed to load model list');
    }
  }, [currentModel]);

  /**
   * Load a model from its info
   */
  const loadModel = async (model: SDKModelInfo) => {
    try {
      setIsModelLoading(true);
      console.log(`[TTSScreen] Loading model: ${model.id} from ${model.localPath}`);

      if (!model.localPath) {
        Alert.alert('Error', 'Model path not found. Please re-download the model.');
        return;
      }

      // Load using the actual local path
      const success = await RunAnywhere.loadTTSModel(model.localPath, model.modelType || 'piper');

      if (success) {
        const isLoaded = await RunAnywhere.isTTSModelLoaded();
        if (isLoaded) {
          // Set model with framework so ModelStatusBanner shows it properly
          // Use ONNX since TTS uses Sherpa-ONNX (ONNX Runtime)
          setCurrentModel({
            id: model.id,
            name: model.name,
            preferredFramework: LLMFramework.ONNX,
          } as ModelInfo);
          console.log(`[TTSScreen] Model ${model.name} loaded successfully, currentModel set`);
        } else {
          console.log(`[TTSScreen] Model reported success but isTTSModelLoaded() returned false`);
        }
      } else {
        const error = await RunAnywhere.getLastError();
        Alert.alert('Error', `Failed to load model: ${error || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('[TTSScreen] Error loading model:', error);
      Alert.alert('Error', `Failed to load model: ${error}`);
    } finally {
      setIsModelLoading(false);
    }
  };

  /**
   * Convert base64 PCM float32 audio to WAV file
   * The audio data from TTS is base64-encoded float32 PCM samples
   */
  const createWavFile = async (
    audioBase64: string,
    audioSampleRate: number
  ): Promise<string> => {
    // Decode base64 to get raw bytes
    const binaryString = atob(audioBase64);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i);
    }

    // Convert float32 samples to int16
    const floatView = new Float32Array(bytes.buffer);
    const numSamples = floatView.length;
    const int16Samples = new Int16Array(numSamples);

    for (let i = 0; i < numSamples; i++) {
      // Clamp and convert to int16 range
      const sample = Math.max(-1, Math.min(1, floatView[i]!));
      int16Samples[i] = sample < 0 ? sample * 0x8000 : sample * 0x7fff;
    }

    // Create WAV header
    const wavDataSize = int16Samples.length * 2;
    const wavBuffer = new ArrayBuffer(44 + wavDataSize);
    const wavView = new DataView(wavBuffer);

    // RIFF header
    wavView.setUint8(0, 0x52); // R
    wavView.setUint8(1, 0x49); // I
    wavView.setUint8(2, 0x46); // F
    wavView.setUint8(3, 0x46); // F
    wavView.setUint32(4, 36 + wavDataSize, true); // File size - 8
    wavView.setUint8(8, 0x57); // W
    wavView.setUint8(9, 0x41); // A
    wavView.setUint8(10, 0x56); // V
    wavView.setUint8(11, 0x45); // E

    // fmt chunk
    wavView.setUint8(12, 0x66); // f
    wavView.setUint8(13, 0x6d); // m
    wavView.setUint8(14, 0x74); // t
    wavView.setUint8(15, 0x20); // (space)
    wavView.setUint32(16, 16, true); // fmt chunk size
    wavView.setUint16(20, 1, true); // Audio format (PCM = 1)
    wavView.setUint16(22, 1, true); // Number of channels (mono = 1)
    wavView.setUint32(24, audioSampleRate, true); // Sample rate
    wavView.setUint32(28, audioSampleRate * 2, true); // Byte rate
    wavView.setUint16(32, 2, true); // Block align
    wavView.setUint16(34, 16, true); // Bits per sample

    // data chunk
    wavView.setUint8(36, 0x64); // d
    wavView.setUint8(37, 0x61); // a
    wavView.setUint8(38, 0x74); // t
    wavView.setUint8(39, 0x61); // a
    wavView.setUint32(40, wavDataSize, true); // Data size

    // Copy audio data
    const wavBytes = new Uint8Array(wavBuffer);
    const int16Bytes = new Uint8Array(int16Samples.buffer);
    for (let i = 0; i < int16Bytes.length; i++) {
      wavBytes[44 + i] = int16Bytes[i]!;
    }

    // Convert to base64 and write to file
    let wavBase64 = '';
    for (let i = 0; i < wavBytes.length; i++) {
      wavBase64 += String.fromCharCode(wavBytes[i]!);
    }
    wavBase64 = btoa(wavBase64);

    const fileName = `tts_${Date.now()}.wav`;
    const filePath = `${RNFS.DocumentDirectoryPath}/${fileName}`;
    await RNFS.writeFile(filePath, wavBase64, 'base64');

    return filePath;
  };

  /**
   * Generate speech
   */
  const handleGenerate = useCallback(async () => {
    if (!text.trim() || !currentModel) return;

    setIsGenerating(true);
    setAudioGenerated(false);

    // Stop any existing playback
    try {
      await audioRecorderPlayer.stopPlayer();
      audioRecorderPlayer.removePlayBackListener();
    } catch {
      // Ignore errors if not playing
    }

    try {
      // Check if model is loaded
      const isLoaded = await RunAnywhere.isTTSModelLoaded();
      if (!isLoaded) {
        Alert.alert('Model Not Loaded', 'Please load a TTS model first.');
        setIsGenerating(false);
        return;
      }

      // SDK uses simple TTSConfiguration with rate/pitch/volume
      const sdkConfig = {
        voice: 'default',
        rate: speed,
        pitch: pitch,
        volume: volume,
      };

      console.log('[TTSScreen] Synthesizing text:', text.substring(0, 50) + '...');

      // SDK returns TTSResult with audio, sampleRate, numSamples, duration
      const result = await RunAnywhere.synthesize(text, sdkConfig);

      console.log('[TTSScreen] Synthesis result:', {
        sampleRate: result.sampleRate,
        numSamples: result.numSamples,
        duration: result.duration,
        audioLength: result.audio?.length || 0,
      });

      // Use actual duration from result, or estimate if not available
      const audioDuration = result.duration || (result.numSamples / result.sampleRate) || text.length * 0.05;
      setDuration(audioDuration);
      setSampleRate(result.sampleRate || 22050);
      setLastGeneratedAudio(result.audio);

      // Convert to WAV and save to file for playback
      if (result.audio && result.audio.length > 0) {
        try {
          // Clean up previous file
          if (audioFilePath) {
            await RNFS.unlink(audioFilePath).catch(() => {});
          }

          const wavPath = await createWavFile(result.audio, result.sampleRate || 22050);
          setAudioFilePath(wavPath);
          setAudioGenerated(true);
          setCurrentTime(0);
          setPlaybackProgress(0);
          setIsPlaying(false);

          console.log('[TTSScreen] WAV file created:', wavPath);
        } catch (wavError) {
          console.error('[TTSScreen] Error creating WAV file:', wavError);
          Alert.alert(
            'Audio Generated',
            `Duration: ${audioDuration.toFixed(2)}s\n` +
              `Sample Rate: ${result.sampleRate} Hz\n` +
              `Samples: ${result.numSamples.toLocaleString()}\n\n` +
              'Audio file creation failed. Tap play to try again.',
            [{ text: 'OK' }]
          );
          setAudioGenerated(true);
        }
      }
    } catch (error) {
      console.error('[TTSScreen] Synthesis error:', error);
      Alert.alert('Error', `Failed to generate speech: ${error}`);
    } finally {
      setIsGenerating(false);
    }
  }, [text, speed, pitch, volume, currentModel, audioFilePath]);

  /**
   * Format time for display (MM:SS)
   */
  const formatTime = (seconds: number): string => {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  /**
   * Toggle playback - plays or pauses audio
   */
  const handleTogglePlayback = useCallback(async () => {
    console.log('[TTSScreen] handleTogglePlayback called', {
      audioGenerated,
      audioFilePath,
      isPlaying,
      currentTime,
      playbackProgress,
    });

    if (!audioGenerated || !audioFilePath) {
      console.log('[TTSScreen] No audio to play - audioGenerated:', audioGenerated, 'audioFilePath:', audioFilePath);
      Alert.alert('No Audio', 'Please generate speech first.');
      return;
    }

    // Verify file exists
    try {
      const fileExists = await RNFS.exists(audioFilePath);
      console.log('[TTSScreen] Audio file exists:', fileExists, 'path:', audioFilePath);
      if (!fileExists) {
        Alert.alert('File Not Found', 'Audio file was not found. Please regenerate.');
        return;
      }
      const fileStat = await RNFS.stat(audioFilePath);
      console.log('[TTSScreen] Audio file size:', fileStat.size, 'bytes');
    } catch (statError) {
      console.error('[TTSScreen] Error checking file:', statError);
    }

    try {
      if (isPlaying) {
        // Pause playback
        console.log('[TTSScreen] Pausing playback...');
        await audioRecorderPlayer.pausePlayer();
        setIsPlaying(false);
        console.log('[TTSScreen] Playback paused');
      } else {
        // Start or resume playback
        console.log('[TTSScreen] Setting up playback listener...');
        audioRecorderPlayer.addPlayBackListener((e) => {
          const currentSec = e.currentPosition / 1000;
          const totalSec = e.duration / 1000;

          setCurrentTime(currentSec);
          if (totalSec > 0) {
            setPlaybackProgress(currentSec / totalSec);
          }

          // Log playback progress periodically
          if (Math.floor(currentSec) !== Math.floor(currentSec - 0.1)) {
            console.log('[TTSScreen] Playback progress:', currentSec.toFixed(1), '/', totalSec.toFixed(1));
          }

          // Check if playback finished
          if (e.currentPosition >= e.duration && e.duration > 0) {
            console.log('[TTSScreen] Playback finished');
            audioRecorderPlayer.stopPlayer();
            audioRecorderPlayer.removePlayBackListener();
            setIsPlaying(false);
            setCurrentTime(0);
            setPlaybackProgress(0);
          }
        });

        // Check if we need to start fresh or resume
        if (currentTime === 0 || playbackProgress === 0) {
          // Start from beginning
          // IMPORTANT: react-native-audio-recorder-player requires file:// prefix on iOS
          // Without it, it mangles the path by prepending Library/Caches/
          const fileUri = `file://${audioFilePath}`;
          console.log('[TTSScreen] Starting playback from beginning, URI:', fileUri);
          const result = await audioRecorderPlayer.startPlayer(fileUri);
          console.log('[TTSScreen] startPlayer result:', result);
          await audioRecorderPlayer.setVolume(volume);
          console.log('[TTSScreen] Volume set to:', volume);
        } else {
          // Resume from current position
          console.log('[TTSScreen] Resuming playback from:', currentTime);
          await audioRecorderPlayer.resumePlayer();
        }

        setIsPlaying(true);
        console.log('[TTSScreen] Playback started successfully');
      }
    } catch (error) {
      console.error('[TTSScreen] Playback error:', error);
      Alert.alert('Playback Error', `Failed to play audio: ${error}`);
      setIsPlaying(false);
    }
  }, [audioGenerated, audioFilePath, isPlaying, currentTime, playbackProgress, volume]);

  /**
   * Stop playback completely
   */
  const handleStop = useCallback(async () => {
    try {
      await audioRecorderPlayer.stopPlayer();
      audioRecorderPlayer.removePlayBackListener();
      setIsPlaying(false);
      setCurrentTime(0);
      setPlaybackProgress(0);
    } catch (error) {
      console.error('[TTSScreen] Stop error:', error);
    }
  }, []);

  /**
   * Clear text
   */
  const handleClear = useCallback(() => {
    setText('');
    setAudioGenerated(false);
    setIsPlaying(false);
  }, []);

  /**
   * Render slider with label
   */
  const renderSlider = (
    label: string,
    value: number,
    onValueChange: (value: number) => void,
    min: number = 0.5,
    max: number = 2.0,
    step: number = 0.1,
    formatValue: (v: number) => string = (v) => `${v.toFixed(1)}x`
  ) => (
    <View style={styles.sliderContainer}>
      <View style={styles.sliderHeader}>
        <Text style={styles.sliderLabel}>{label}</Text>
        <Text style={styles.sliderValue}>{formatValue(value)}</Text>
      </View>
      {/* TODO: Add @react-native-community/slider package */}
      <View style={styles.sliderTrack}>
        <View
          style={[
            styles.sliderFill,
            { width: `${((value - min) / (max - min)) * 100}%` },
          ]}
        />
        <TouchableOpacity
          style={[
            styles.sliderThumb,
            { left: `${((value - min) / (max - min)) * 100}%` },
          ]}
          onPress={() => {
            // Simple increment for demo
            const newValue = value + step > max ? min : value + step;
            onValueChange(Math.round(newValue * 10) / 10);
          }}
        />
      </View>
    </View>
  );

  /**
   * Render header
   */
  const renderHeader = () => (
    <View style={styles.header}>
      <Text style={styles.title}>Text to Speech</Text>
      {text && (
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
          modality={ModelModality.TTS}
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
        placeholder="Select a voice model"
      />

      <ScrollView style={styles.content} showsVerticalScrollIndicator={false}>
        {/* Text Input */}
        <View style={styles.inputSection}>
          <Text style={styles.sectionLabel}>Text to speak</Text>
          <TextInput
            style={styles.textInput}
            value={text}
            onChangeText={setText}
            placeholder="Enter text to convert to speech..."
            placeholderTextColor={Colors.textTertiary}
            multiline
            maxLength={maxChars}
          />
          <Text style={styles.charCount}>
            {charCount}/{maxChars} characters
          </Text>
        </View>

        {/* Voice Settings */}
        <View style={styles.settingsSection}>
          <Text style={styles.sectionLabel}>Voice Settings</Text>
          {renderSlider('Speed', speed, setSpeed)}
          {renderSlider('Pitch', pitch, setPitch)}
          {renderSlider(
            'Volume',
            volume,
            setVolume,
            0,
            1,
            0.1,
            (v) => `${Math.round(v * 100)}%`
          )}
        </View>

        {/* Playback Controls */}
        {audioGenerated && (
          <View style={styles.playbackSection}>
            <Text style={styles.sectionLabel}>Generated Audio</Text>

            {/* Progress bar */}
            <View style={styles.progressContainer}>
              <Text style={styles.timeText}>{formatTime(currentTime)}</Text>
              <View style={styles.progressBar}>
                <View
                  style={[
                    styles.progressFill,
                    { width: `${Math.max(0, Math.min(100, playbackProgress * 100))}%` },
                  ]}
                />
              </View>
              <Text style={styles.timeText}>{formatTime(duration)}</Text>
            </View>

            {/* Audio info */}
            <View style={styles.playbackInfo}>
              <Icon name="musical-notes" size={20} color={Colors.textSecondary} />
              <Text style={styles.durationText}>
                {duration.toFixed(1)}s @ {sampleRate} Hz
              </Text>
            </View>

            {/* Playback controls */}
            <View style={styles.playbackControls}>
              <TouchableOpacity
                style={[
                  styles.controlButton,
                  isPlaying && styles.controlButtonActive,
                ]}
                onPress={handleTogglePlayback}
              >
                <Icon
                  name={isPlaying ? 'pause' : 'play'}
                  size={24}
                  color={isPlaying ? Colors.textWhite : Colors.primaryBlue}
                />
              </TouchableOpacity>
              <TouchableOpacity
                style={styles.controlButton}
                onPress={handleStop}
              >
                <Icon name="stop" size={24} color={Colors.primaryBlue} />
              </TouchableOpacity>
            </View>
          </View>
        )}
      </ScrollView>

      {/* Generate Button */}
      <View style={styles.footer}>
        <TouchableOpacity
          style={[
            styles.generateButton,
            (!text.trim() || isGenerating) && styles.generateButtonDisabled,
          ]}
          onPress={handleGenerate}
          disabled={!text.trim() || isGenerating}
          activeOpacity={0.8}
        >
          {isGenerating ? (
            <>
              <Icon name="hourglass" size={20} color={Colors.textWhite} />
              <Text style={styles.generateButtonText}>Generating...</Text>
            </>
          ) : (
            <>
              <Icon name="volume-high" size={20} color={Colors.textWhite} />
              <Text style={styles.generateButtonText}>Generate Speech</Text>
            </>
          )}
        </TouchableOpacity>
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
  content: {
    flex: 1,
    paddingHorizontal: Padding.padding16,
  },
  inputSection: {
    marginTop: Spacing.large,
  },
  sectionLabel: {
    ...Typography.headline,
    color: Colors.textPrimary,
    marginBottom: Spacing.smallMedium,
  },
  textInput: {
    backgroundColor: Colors.backgroundSecondary,
    borderRadius: BorderRadius.medium,
    padding: Padding.padding14,
    minHeight: Layout.textAreaMinHeight,
    ...Typography.body,
    color: Colors.textPrimary,
    textAlignVertical: 'top',
  },
  charCount: {
    ...Typography.caption,
    color: Colors.textTertiary,
    textAlign: 'right',
    marginTop: Spacing.small,
  },
  settingsSection: {
    marginTop: Spacing.xLarge,
  },
  sliderContainer: {
    marginBottom: Spacing.large,
  },
  sliderHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: Spacing.small,
  },
  sliderLabel: {
    ...Typography.subheadline,
    color: Colors.textPrimary,
  },
  sliderValue: {
    ...Typography.subheadline,
    color: Colors.primaryBlue,
    fontWeight: '600',
  },
  sliderTrack: {
    height: 6,
    backgroundColor: Colors.backgroundGray5,
    borderRadius: 3,
    position: 'relative',
  },
  sliderFill: {
    height: '100%',
    backgroundColor: Colors.primaryBlue,
    borderRadius: 3,
  },
  sliderThumb: {
    position: 'absolute',
    top: -7,
    width: 20,
    height: 20,
    borderRadius: 10,
    backgroundColor: Colors.backgroundPrimary,
    borderWidth: 2,
    borderColor: Colors.primaryBlue,
    marginLeft: -10,
  },
  playbackSection: {
    marginTop: Spacing.xLarge,
    padding: Padding.padding16,
    backgroundColor: Colors.backgroundSecondary,
    borderRadius: BorderRadius.medium,
  },
  progressContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.smallMedium,
    marginBottom: Spacing.medium,
    paddingVertical: Spacing.smallMedium,
  },
  timeText: {
    ...Typography.caption,
    color: Colors.textSecondary,
    minWidth: 40,
    textAlign: 'center',
  },
  progressBar: {
    flex: 1,
    height: 4,
    backgroundColor: Colors.backgroundGray5,
    borderRadius: 2,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    backgroundColor: Colors.primaryBlue,
    borderRadius: 2,
  },
  playbackInfo: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.smallMedium,
    marginBottom: Spacing.medium,
  },
  durationText: {
    ...Typography.subheadline,
    color: Colors.textSecondary,
  },
  playbackControls: {
    flexDirection: 'row',
    gap: Spacing.medium,
  },
  controlButton: {
    width: ButtonHeight.regular,
    height: ButtonHeight.regular,
    borderRadius: ButtonHeight.regular / 2,
    backgroundColor: Colors.backgroundPrimary,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 2,
    borderColor: Colors.primaryBlue,
  },
  controlButtonActive: {
    backgroundColor: Colors.primaryBlue,
    borderColor: Colors.primaryBlue,
  },
  footer: {
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding16,
    paddingBottom: Padding.padding30,
    borderTopWidth: 1,
    borderTopColor: Colors.borderLight,
  },
  generateButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: Spacing.smallMedium,
    backgroundColor: Colors.primaryBlue,
    height: ButtonHeight.regular,
    borderRadius: BorderRadius.large,
  },
  generateButtonDisabled: {
    backgroundColor: Colors.backgroundGray5,
  },
  generateButtonText: {
    ...Typography.headline,
    color: Colors.textWhite,
  },
});

export default TTSScreen;
