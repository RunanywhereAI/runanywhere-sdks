/**
 * TTSScreen - Tab 2: Text-to-Speech
 *
 * Provides on-device text-to-speech with voice selection. Mirrors the
 * iOS `TextToSpeechView` architecture: the SDK owns both synthesis and
 * playback through `RunAnywhere.speak()`, so the screen is just a thin
 * input form + Speak/Stop control surface.
 *
 * Architecture:
 * - Model loading via `RunAnywhere.loadModel(ModelLoadRequest)`
 * - ONNX/Sherpa TTS plays via `RunAnywhere.speak(text, options)` —
 *   the SDK handles PCM->WAV encoding and playback internally so no
 *   hand-rolled RIFF header or native audio module lives here.
 *
 * Reference: iOS examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Voice/TextToSpeechView.swift
 */

import React, { useState, useCallback, useEffect } from 'react';
import {
  View,
  Text,
  TextInput,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  Alert,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import Slider from '@react-native-community/slider';
import {
  SafeAreaView,
  useSafeAreaInsets,
} from 'react-native-safe-area-context';
import { useFocusEffect } from '@react-navigation/native';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import {
  Spacing,
  Padding,
  BorderRadius,
  ButtonHeight,
  Layout,
} from '../theme/spacing';
import { ModelStatusBanner, ModelRequiredOverlay } from '../components/common';
import {
  ModelSelectionSheet,
  ModelSelectionContext,
} from '../components/model';

// Import RunAnywhere SDK (Multi-Package Architecture)
import { RunAnywhere } from '@runanywhere/core';
import {
  AudioFormat,
  InferenceFramework,
  ModelCategory,
  ModelLoadRequest,
  type ModelInfo as SDKModelInfo,
} from '@runanywhere/proto-ts/model_types';
import {
  isModelLoadedForCategory,
  unloadModelsForCategory,
} from '../utils/runAnywhereLifecycle';

// Canonical SDK methods (Swift parity).
const listModels = async (): Promise<SDKModelInfo[]> =>
  (await RunAnywhere.listModels()).models?.models ?? [];
const loadModelWithRequest = RunAnywhere.loadModel;

export const TTSScreen: React.FC = () => {
  // State
  const [text, setText] = useState('');
  const [speed, setSpeed] = useState(1.0);
  // Pitch slider is currently commented out (see renderSlider below); setter kept for future re-enable.
  const [pitch, _setPitch] = useState(1.0);
  const [volume, setVolume] = useState(1.0);
  const [isSpeaking, setIsSpeaking] = useState(false);
  const [currentModel, setCurrentModel] = useState<SDKModelInfo | null>(null);
  const [isModelLoading, setIsModelLoading] = useState(false);
  const [_availableModels, setAvailableModels] = useState<SDKModelInfo[]>([]);
  const [showModelSelection, setShowModelSelection] = useState(false);

  // Safe area insets for header status bar handling
  const insets = useSafeAreaInsets();

  // Character count
  const charCount = text.length;
  const maxChars = 1000;

  // Cleanup on unmount — make sure no audio keeps playing.
  useEffect(() => {
    return () => {
      RunAnywhere.stopSpeaking().catch(() => {});
    };
  }, []);

  /**
   * Load available models and check for loaded model
   * Called on mount and when screen comes into focus
   */
  const loadModels = useCallback(async () => {
    try {
      // Get available TTS models from catalog
      const allModels = await listModels();
      // Filter by category (speech-synthesis) matching SDK's ModelCategory
      const ttsModels = allModels.filter(
        (m: SDKModelInfo) =>
          m.category === ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
      );
      setAvailableModels(ttsModels);

      // Ask the SDK for the loaded TTS model directly so the banner
      // reflects the actual loaded model name (no fabricated stand-in).
      if (!currentModel) {
        const loaded = await RunAnywhere.modelInfoForCategory(
          ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
        );
        if (loaded) {
          setCurrentModel(loaded);
          console.warn('[TTSScreen] Loaded TTS model:', loaded.name);
        }
      }
    } catch (error) {
      console.warn('[TTSScreen] Error loading models:', error);
    }
  }, [currentModel]);

  // Refresh models when screen comes into focus
  useFocusEffect(
    useCallback(() => {
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
   * Load a model from its info
   */
  const loadModel = useCallback(async (model: SDKModelInfo) => {
    try {
      setIsModelLoading(true);

      if (!model.isDownloaded && !model.localPath) {
        Alert.alert(
          'Error',
          'Model has not been downloaded. Open the model picker to download it first.'
        );
        return;
      }

      // Unload any existing TTS model first
      try {
        const wasLoaded = await isModelLoadedForCategory(
          ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
        );
        if (wasLoaded) {
          await unloadModelsForCategory(
            ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
          );
        }
      } catch (unloadError) {
        console.warn(
          '[TTSScreen] Error unloading previous model (ignoring):',
          unloadError
        );
      }

      // Path-first loading was removed in V2 — model ID is the canonical
      // handle and the native registry resolves the artifact path.
      const result = await loadModelWithRequest(
        ModelLoadRequest.fromPartial({
          modelId: model.id,
          category: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
          forceReload: false,
          validateAvailability: true,
        })
      );

      if (result.success) {
        const loaded = await RunAnywhere.modelInfoForCategory(
          ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
        );
        setCurrentModel(
          loaded ?? {
            ...model,
            preferredFramework: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
          }
        );
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
      console.error('[TTSScreen] Error loading model:', error);
      Alert.alert('Error', `Failed to load model: ${error}`);
    } finally {
      setIsModelLoading(false);
    }
  }, []);

  /**
   * Handle model selected from the sheet
   */
  const handleModelSelected = useCallback(
    async (model: SDKModelInfo) => {
      setShowModelSelection(false);
      await loadModel(model);
    },
    [loadModel]
  );

  /**
   * Speak the entered text. Mirrors iOS `TTSViewModel.speak(text:)`:
   * delegate synthesis + playback to the SDK in one call so the
   * example does not own PCM/WAV bytes or playback chrome.
   */
  const handleSpeak = useCallback(async () => {
    if (!text.trim() || !currentModel) return;

    // Cancel any in-flight speech.
    await RunAnywhere.stopSpeaking().catch(() => {});

    // ONNX-backed TTS: ensure the model is actually loaded first.
    const isLoaded = await isModelLoadedForCategory(
      ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
    );
    if (!isLoaded) {
      Alert.alert('Model Not Loaded', 'Please load a TTS model first.');
      return;
    }

    setIsSpeaking(true);
    try {
      // Proto-canonical TTSOptions (aligned to
      // @runanywhere/proto-ts/tts_options).
      const sdkConfig = {
        voice: 'default',
        languageCode: '',
        speakingRate: speed,
        pitch,
        volume,
        enableSsml: false,
        audioFormat: AudioFormat.AUDIO_FORMAT_PCM,
      };
      const result = await RunAnywhere.speak(text, sdkConfig);
      console.warn('[TTSScreen] Speech complete:', {
        sampleRate: result.sampleRate,
        durationMs: result.durationMs,
        audioSizeBytes: result.audioSizeBytes,
      });
    } catch (error) {
      console.error('[TTSScreen] Speech error:', error);
      Alert.alert('Error', `Failed to speak: ${error}`);
    } finally {
      setIsSpeaking(false);
    }
  }, [text, speed, pitch, volume, currentModel]);

  /**
   * Stop in-flight speech.
   */
  const handleStop = useCallback(async () => {
    await RunAnywhere.stopSpeaking().catch(() => {});
    setIsSpeaking(false);
  }, []);

  /**
   * Clear text
   */
  const handleClear = useCallback(() => {
    setText('');
    setIsSpeaking(false);
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
      <Slider
        style={styles.slider}
        value={value}
        onValueChange={(v: number) =>
          onValueChange(Math.round(v / step) * step)
        }
        minimumValue={min}
        maximumValue={max}
        step={step}
        minimumTrackTintColor={Colors.primaryBlue}
        maximumTrackTintColor={Colors.backgroundGray5}
        thumbTintColor={Colors.primaryBlue}
      />
    </View>
  );

  /**
   * Render header
   */
  const renderHeader = () => (
    <View
      style={[styles.header, { paddingTop: insets.top + Padding.padding12 }]}
    >
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
          modality="tts"
          onSelectModel={handleSelectModel}
        />
        {/* Model Selection Sheet */}
        <ModelSelectionSheet
          visible={showModelSelection}
          context={ModelSelectionContext.TTS}
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
          {/* Pitch slider - Commented out for now as it is not implemented in the current TTS models */}
          {/* {renderSlider('Pitch', pitch, setPitch)} */}
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
      </ScrollView>

      {/* Speak / Stop button (mirrors iOS one-shot speak control). */}
      <View style={styles.footer}>
        <TouchableOpacity
          style={[
            styles.generateButton,
            !text.trim() && !isSpeaking && styles.generateButtonDisabled,
          ]}
          onPress={isSpeaking ? handleStop : handleSpeak}
          disabled={!text.trim() && !isSpeaking}
          activeOpacity={0.8}
        >
          {isSpeaking ? (
            <>
              <Icon name="stop" size={20} color={Colors.textWhite} />
              <Text style={styles.generateButtonText}>Stop Speaking</Text>
            </>
          ) : (
            <>
              <Icon name="volume-high" size={20} color={Colors.textWhite} />
              <Text style={styles.generateButtonText}>Speak</Text>
            </>
          )}
        </TouchableOpacity>
      </View>

      {/* Model Selection Sheet */}
      <ModelSelectionSheet
        visible={showModelSelection}
        context={ModelSelectionContext.TTS}
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
  slider: {
    width: '100%',
    height: 36,
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
