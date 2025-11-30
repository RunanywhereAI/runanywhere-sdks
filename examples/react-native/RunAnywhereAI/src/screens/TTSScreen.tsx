/**
 * TTSScreen - Tab 2: Text-to-Speech
 *
 * Reference: iOS Features/Voice/TextToSpeechView.swift
 */

import React, { useState, useCallback, useEffect } from 'react';
import {
  View,
  Text,
  TextInput,
  StyleSheet,
  SafeAreaView,
  TouchableOpacity,
  ScrollView,
  Alert,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding, BorderRadius, IconSize, ButtonHeight, Layout } from '../theme/spacing';
import { ModelStatusBanner, ModelRequiredOverlay } from '../components/common';
import { ModelInfo, ModelModality } from '../types/model';

// Import RunAnywhere SDK
import {
  RunAnywhere,
  type TTSConfiguration as SDKTTSConfiguration,
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

  // Character count
  const charCount = text.length;
  const maxChars = 1000;

  // Load available models and check for loaded model on mount
  useEffect(() => {
    const initialize = async () => {
      try {
        // Get available TTS models from catalog
        const allModels = await RunAnywhere.getAvailableModels();
        const ttsModels = allModels.filter((m) => m.modality === 'tts');
        setAvailableModels(ttsModels);
        console.log('[TTSScreen] Available TTS models:', ttsModels.map(m => m.id));

        // Check if model is already loaded
        const isLoaded = await RunAnywhere.isTTSModelLoaded();
        if (isLoaded) {
          setCurrentModel({
            id: 'tts-model',
            name: 'TTS Model (Loaded)',
          } as ModelInfo);
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
    // Get downloaded TTS models
    const downloadedModels = availableModels.filter((m) => m.isDownloaded);

    if (downloadedModels.length === 0) {
      Alert.alert(
        'No Models Downloaded',
        'Please download a text-to-speech model from the Settings tab first.',
        [{ text: 'OK' }]
      );
      return;
    }

    const buttons = downloadedModels.map((model) => ({
      text: model.name,
      onPress: () => loadModel(model),
    }));
    buttons.push({ text: 'Cancel', onPress: () => {} });

    Alert.alert('Select TTS Model', 'Choose a downloaded text-to-speech model', buttons as any);
  }, [availableModels]);

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
          setCurrentModel({
            id: model.id,
            name: model.name,
          } as ModelInfo);
          console.log(`[TTSScreen] Model ${model.name} loaded successfully`);
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
   * Generate speech
   */
  const handleGenerate = useCallback(async () => {
    if (!text.trim() || !currentModel) return;

    setIsGenerating(true);
    setAudioGenerated(false);

    try {
      // Check if model is loaded
      const isLoaded = await RunAnywhere.isTTSModelLoaded();
      if (!isLoaded) {
        Alert.alert('Model Not Loaded', 'Please load a TTS model first.');
        setIsGenerating(false);
        return;
      }

      const sdkConfig: SDKTTSConfiguration = {
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
      setLastGeneratedAudio(result.audio);
      setAudioGenerated(true);

      // Show info about the audio data
      Alert.alert(
        'Audio Generated',
        `Duration: ${audioDuration.toFixed(2)}s\n` +
          `Sample Rate: ${result.sampleRate} Hz\n` +
          `Samples: ${result.numSamples.toLocaleString()}\n\n` +
          'To enable audio playback:\n' +
          '1. Add react-native-audio-recorder-player or expo-av\n' +
          '2. Use the audio data (base64 PCM) for playback',
        [{ text: 'OK' }]
      );

      // Note: Actual audio playback would require a library like:
      // - react-native-audio-recorder-player
      // - expo-av
      // - react-native-sound
      // The audio data is base64 encoded PCM float samples
    } catch (error) {
      console.error('[TTSScreen] Synthesis error:', error);
      Alert.alert('Error', `Failed to generate speech: ${error}`);
    } finally {
      setIsGenerating(false);
    }
  }, [text, speed, pitch, volume, currentModel]);

  /**
   * Toggle playback
   * TODO: Implement actual audio playback
   */
  const handleTogglePlayback = useCallback(() => {
    if (!audioGenerated) return;
    setIsPlaying(!isPlaying);
  }, [audioGenerated, isPlaying]);

  /**
   * Stop playback
   */
  const handleStop = useCallback(() => {
    setIsPlaying(false);
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
            <View style={styles.playbackInfo}>
              <Icon name="musical-notes" size={20} color={Colors.textSecondary} />
              <Text style={styles.durationText}>
                Duration: {duration.toFixed(1)}s
              </Text>
            </View>
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
