/**
 * ImageGenerationScreen - Text-to-image (Diffusion, iOS only)
 *
 * Model selection, download, load, prompt input, generate, display image.
 * Uses @runanywhere/diffusion. On Android shows an "iOS only" message.
 *
 * Reference: iOS Features/Diffusion/ImageGenerationView.swift, DiffusionViewModel.swift
 */

import React, { useState, useCallback, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  SafeAreaView,
  ScrollView,
  TouchableOpacity,
  TextInput,
  Image,
  ActivityIndicator,
  Platform,
  Alert,
} from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding, BorderRadius, ButtonHeight } from '../theme/spacing';
import {
  RunAnywhere,
  ModelCategory,
  type ModelInfo as SDKModelInfo,
} from '@runanywhere/core';

// Diffusion is iOS-only; require only on iOS to avoid Android native load
const getDiffusion = (): typeof import('@runanywhere/diffusion').Diffusion | null =>
  Platform.OS === 'ios'
    ? require('@runanywhere/diffusion').Diffusion
    : null;

const SAMPLE_PROMPTS = [
  'A serene mountain landscape at sunset with golden light',
  'A futuristic city with flying cars and neon lights',
  'A cute corgi puppy wearing a tiny astronaut helmet',
  'An ancient library filled with magical floating books',
  'A cozy coffee shop on a rainy day, warm lighting',
];

export const ImageGenerationScreen: React.FC = () => {
  const [availableModels, setAvailableModels] = useState<SDKModelInfo[]>([]);
  const [selectedModel, setSelectedModel] = useState<SDKModelInfo | null>(null);
  const [isModelLoaded, setIsModelLoaded] = useState(false);
  const [isLoadingModels, setIsLoadingModels] = useState(true);
  const [isLoadingModel, setIsLoadingModel] = useState(false);
  const [isDownloading, setIsDownloading] = useState(false);
  const [downloadProgress, setDownloadProgress] = useState(0);
  const [downloadStatus, setDownloadStatus] = useState('');
  const [isGenerating, setIsGenerating] = useState(false);
  const [statusMessage, setStatusMessage] = useState('Ready');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [prompt, setPrompt] = useState(SAMPLE_PROMPTS[0] ?? '');
  const [generatedImageBase64, setGeneratedImageBase64] = useState<string | null>(null);
  const [showModelPicker, setShowModelPicker] = useState(false);

  const loadModels = useCallback(async (): Promise<SDKModelInfo[]> => {
    if (Platform.OS !== 'ios') return [];
    setIsLoadingModels(true);
    setErrorMessage(null);
    try {
      const all = await RunAnywhere.getAvailableModels();
      const diffusion = all.filter(
        (m) => m.category === ModelCategory.ImageGeneration
      );
      setAvailableModels(diffusion);
      const downloaded = diffusion.find((m) => m.isDownloaded);
      if (downloaded) setSelectedModel(downloaded);
      else if (diffusion.length > 0) setSelectedModel(diffusion[0] ?? null);
      return diffusion;
    } catch (e) {
      setErrorMessage(e instanceof Error ? e.message : 'Failed to load models');
      return [];
    } finally {
      setIsLoadingModels(false);
    }
  }, []);

  const checkLoaded = useCallback(async () => {
    if (Platform.OS !== 'ios') return;
    const Diffusion = getDiffusion();
    if (!Diffusion) return;
    try {
      const loaded = await Diffusion.isModelLoaded();
      setIsModelLoaded(loaded);
      if (!loaded) setStatusMessage('No model loaded');
    } catch {
      setIsModelLoaded(false);
    }
  }, []);

  useFocusEffect(
    useCallback(() => {
      loadModels();
      checkLoaded();
    }, [loadModels, checkLoaded])
  );

  const downloadModel = useCallback(
    async (model: SDKModelInfo) => {
      if (Platform.OS !== 'ios') return;
      setIsDownloading(true);
      setErrorMessage(null);
      setDownloadProgress(0);
      setDownloadStatus('Starting...');
      try {
        await RunAnywhere.downloadModel(model.id, (progress) => {
          const pct = progress.progress;
          setDownloadProgress(pct);
          setDownloadStatus(`Downloading: ${Math.round(pct * 100)}%`);
        });
        const updated = await loadModels();
        setSelectedModel(updated.find((m) => m.id === model.id) ?? model);
      } catch (e) {
        setErrorMessage(e instanceof Error ? e.message : 'Download failed');
      } finally {
        setIsDownloading(false);
        setDownloadStatus('');
      }
    },
    [loadModels]
  );

  const loadSelectedModel = useCallback(async () => {
    if (Platform.OS !== 'ios' || !selectedModel) return;
    if (!selectedModel.isDownloaded) {
      setErrorMessage('Download the model first');
      return;
    }
    const path = await RunAnywhere.getModelPath(selectedModel.id);
    if (!path) {
      setErrorMessage('Model path not found');
      return;
    }
    const Diffusion = getDiffusion();
    if (!Diffusion) return;
    setIsLoadingModel(true);
    setErrorMessage(null);
    setStatusMessage('Loading model...');
    try {
      await Diffusion.configure({
        modelVariant: 'sd15',
        enableSafetyChecker: true,
        reduceMemory: true,
      });
      await Diffusion.loadModel(
        path,
        selectedModel.id,
        selectedModel.name
      );
      setIsModelLoaded(true);
      setStatusMessage('Model loaded');
    } catch (e) {
      setErrorMessage(e instanceof Error ? e.message : 'Load failed');
      setStatusMessage('Failed');
    } finally {
      setIsLoadingModel(false);
    }
  }, [selectedModel]);

  const generateImage = useCallback(async () => {
    if (Platform.OS !== 'ios' || !prompt.trim() || !isModelLoaded) return;
    const Diffusion = getDiffusion();
    if (!Diffusion) return;
    setIsGenerating(true);
    setErrorMessage(null);
    setGeneratedImageBase64(null);
    setStatusMessage('Generating...');
    try {
      const result = await Diffusion.generateImage(prompt, {
        width: 512,
        height: 512,
        steps: 28,
        guidanceScale: 7.5,
      });
      setGeneratedImageBase64(result.imageBase64 ?? null);
      setStatusMessage(`Done in ${result.generationTimeMs ?? 0}ms`);
    } catch (e) {
      setErrorMessage(e instanceof Error ? e.message : 'Generation failed');
      setStatusMessage('Failed');
    } finally {
      setIsGenerating(false);
    }
  }, [prompt, isModelLoaded]);

  if (Platform.OS !== 'ios') {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.iosOnlyWrap}>
          <Icon name="image-outline" size={48} color={Colors.textSecondary} />
          <Text style={styles.iosOnlyTitle}>Image Generation</Text>
          <Text style={styles.iosOnlyText}>
            Image generation (Stable Diffusion) is available on iOS only. On
            Android we show VLM (Vision) only.
          </Text>
        </View>
      </SafeAreaView>
    );
  }

  const canGenerate = prompt.trim().length > 0 && isModelLoaded && !isGenerating;

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView
        style={styles.scroll}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {/* Model status */}
        <View style={styles.section}>
          <View style={styles.statusRow}>
            <View
              style={[
                styles.statusDot,
                isModelLoaded ? styles.statusDotGreen : styles.statusDotOrange,
              ]}
            />
            <View style={styles.statusTextWrap}>
              <Text style={styles.statusLabel}>
                {isDownloading
                  ? 'Downloading model...'
                  : isModelLoaded
                    ? selectedModel?.name ?? 'Model loaded'
                    : 'No model loaded'}
              </Text>
              <Text style={styles.statusSub}>
                {isDownloading ? downloadStatus : statusMessage}
              </Text>
              {isDownloading ? (
                <View style={styles.progressBarBg}>
                  <View
                    style={[
                      styles.progressBarFill,
                      { width: `${downloadProgress * 100}%` },
                    ]}
                  />
                </View>
              ) : null}
            </View>
            <TouchableOpacity
              style={[styles.changeButton, isDownloading && styles.changeButtonDisabled]}
              onPress={() => setShowModelPicker(true)}
              disabled={isDownloading}
            >
              <Text style={styles.changeButtonText}>
                {isModelLoaded ? 'Change' : 'Load Model'}
              </Text>
            </TouchableOpacity>
          </View>
        </View>

        {/* Image display */}
        <View style={styles.imageSection}>
          <View style={styles.imagePlaceholder}>
            {generatedImageBase64 ? (
              <Image
                source={{ uri: `data:image/png;base64,${generatedImageBase64}` }}
                style={styles.generatedImage}
                resizeMode="contain"
              />
            ) : isGenerating ? (
              <ActivityIndicator size="large" color={Colors.primaryBlue} />
            ) : (
              <Icon
                name="image-outline"
                size={64}
                color={Colors.textTertiary}
              />
            )}
          </View>
        </View>

        {/* Prompt */}
        <View style={styles.section}>
          <Text style={styles.label}>Prompt</Text>
          <TextInput
            style={styles.input}
            value={prompt}
            onChangeText={setPrompt}
            placeholder="Describe the image..."
            placeholderTextColor={Colors.textTertiary}
            multiline
            editable={!isGenerating}
          />
        </View>

        {/* Quick prompts */}
        <View style={styles.section}>
          <Text style={styles.label}>Quick prompts</Text>
          <ScrollView horizontal showsHorizontalScrollIndicator={false}>
            {SAMPLE_PROMPTS.map((p) => (
              <TouchableOpacity
                key={p}
                style={styles.chip}
                onPress={() => setPrompt(p)}
              >
                <Text style={styles.chipText} numberOfLines={1}>
                  {p}
                </Text>
              </TouchableOpacity>
            ))}
          </ScrollView>
        </View>

        {/* Error */}
        {errorMessage ? (
          <View style={styles.errorWrap}>
            <Text style={styles.errorText}>{errorMessage}</Text>
          </View>
        ) : null}

        {/* Generate */}
        <TouchableOpacity
          style={[
            styles.generateButton,
            !canGenerate && styles.generateButtonDisabled,
          ]}
          onPress={generateImage}
          disabled={!canGenerate}
        >
          {isGenerating ? (
            <ActivityIndicator size="small" color={Colors.textWhite} />
          ) : (
            <Text style={styles.generateButtonText}>Generate Image</Text>
          )}
        </TouchableOpacity>
      </ScrollView>

      {/* Model picker modal (iOS: keep open during download, show progress) */}
      {showModelPicker && (
        <View style={styles.modalOverlay}>
          <View style={styles.modal}>
            <Text style={styles.modalTitle}>Select model</Text>
            {isLoadingModels ? (
              <ActivityIndicator color={Colors.primaryBlue} />
            ) : (
              <ScrollView style={styles.modalList}>
                {availableModels.map((m) => (
                  <TouchableOpacity
                    key={m.id}
                    style={[styles.modalRow, isDownloading && styles.modalRowDisabled]}
                    onPress={async () => {
                      setSelectedModel(m);
                      if (m.isDownloaded) {
                        await loadSelectedModel();
                        setShowModelPicker(false);
                      } else {
                        await downloadModel(m);
                      }
                    }}
                    disabled={isDownloading}
                  >
                    <Text style={styles.modalRowTitle}>{m.name}</Text>
                    <Text style={styles.modalRowSub}>
                      {m.isDownloaded ? 'Tap to load' : 'Tap to download'}
                    </Text>
                  </TouchableOpacity>
                ))}
              </ScrollView>
            )}
            {isDownloading ? (
              <View style={styles.modalProgressWrap}>
                <View style={styles.progressBarBg}>
                  <View
                    style={[
                      styles.progressBarFill,
                      { width: `${downloadProgress * 100}%` },
                    ]}
                  />
                </View>
                <Text style={styles.modalProgressText}>{downloadStatus}</Text>
              </View>
            ) : null}
            <TouchableOpacity
              style={styles.modalClose}
              onPress={() => setShowModelPicker(false)}
            >
              <Text style={styles.modalCloseText}>Close</Text>
            </TouchableOpacity>
          </View>
        </View>
      )}
    </SafeAreaView>
  );
};

export default ImageGenerationScreen;

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.backgroundPrimary,
  },
  scroll: { flex: 1 },
  scrollContent: {
    padding: Padding.padding16,
    paddingBottom: Padding.padding48,
  },
  section: {
    marginBottom: Spacing.large,
  },
  statusRow: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.backgroundSecondary,
    borderRadius: BorderRadius.large,
    padding: Spacing.mediumLarge,
  },
  statusDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    marginRight: Spacing.medium,
  },
  statusDotGreen: { backgroundColor: Colors.primaryGreen },
  statusDotOrange: { backgroundColor: Colors.primaryOrange },
  statusTextWrap: { flex: 1 },
  statusLabel: {
    ...Typography.subheadline,
    color: Colors.textSecondary,
  },
  statusSub: {
    ...Typography.caption2,
    color: Colors.textTertiary,
    marginTop: 2,
  },
  changeButton: {
    paddingHorizontal: Spacing.medium,
    paddingVertical: Spacing.small,
    backgroundColor: Colors.primaryBlue,
    borderRadius: BorderRadius.medium,
  },
  changeButtonDisabled: {
    opacity: 0.6,
  },
  progressBarBg: {
    height: 6,
    backgroundColor: Colors.borderLight,
    borderRadius: 3,
    overflow: 'hidden',
    marginTop: Spacing.small,
  },
  progressBarFill: {
    height: '100%',
    backgroundColor: Colors.primaryBlue,
    borderRadius: 3,
  },
  changeButtonText: {
    ...Typography.caption1,
    color: Colors.textWhite,
  },
  imageSection: { marginBottom: Spacing.large },
  imagePlaceholder: {
    minHeight: 280,
    backgroundColor: Colors.backgroundSecondary,
    borderRadius: BorderRadius.large,
    justifyContent: 'center',
    alignItems: 'center',
  },
  generatedImage: {
    width: '100%',
    height: 280,
    borderRadius: BorderRadius.large,
  },
  label: {
    ...Typography.caption1,
    color: Colors.textSecondary,
    marginBottom: Spacing.small,
  },
  input: {
    ...Typography.body,
    color: Colors.textPrimary,
    backgroundColor: Colors.backgroundSecondary,
    borderRadius: BorderRadius.medium,
    padding: Spacing.medium,
    minHeight: 80,
  },
  chip: {
    paddingHorizontal: Spacing.medium,
    paddingVertical: Spacing.small,
    backgroundColor: Colors.backgroundSecondary,
    borderRadius: BorderRadius.large,
    marginRight: Spacing.small,
  },
  chipText: {
    ...Typography.caption1,
    color: Colors.textPrimary,
    maxWidth: 160,
  },
  errorWrap: {
    marginBottom: Spacing.medium,
    padding: Spacing.small,
    backgroundColor: Colors.badgeRed,
    borderRadius: BorderRadius.small,
  },
  errorText: {
    ...Typography.caption1,
    color: Colors.primaryRed,
  },
  generateButton: {
    height: ButtonHeight.primary,
    backgroundColor: Colors.primaryBlue,
    borderRadius: BorderRadius.medium,
    justifyContent: 'center',
    alignItems: 'center',
  },
  generateButtonDisabled: {
    opacity: 0.5,
  },
  generateButtonText: {
    ...Typography.headline,
    color: Colors.textWhite,
  },
  iosOnlyWrap: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: Padding.padding24,
  },
  iosOnlyTitle: {
    ...Typography.title2,
    color: Colors.textPrimary,
    marginTop: Spacing.medium,
    marginBottom: Spacing.small,
  },
  iosOnlyText: {
    ...Typography.body,
    color: Colors.textSecondary,
    textAlign: 'center',
  },
  modalOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: Colors.overlayMedium,
    justifyContent: 'center',
    padding: Padding.padding24,
  },
  modal: {
    backgroundColor: Colors.backgroundPrimary,
    borderRadius: BorderRadius.large,
    maxHeight: 400,
  },
  modalTitle: {
    ...Typography.headline,
    color: Colors.textPrimary,
    padding: Spacing.mediumLarge,
  },
  modalList: { maxHeight: 280 },
  modalRow: {
    padding: Spacing.mediumLarge,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  modalRowTitle: {
    ...Typography.body,
    color: Colors.textPrimary,
  },
  modalRowSub: {
    ...Typography.caption1,
    color: Colors.textSecondary,
    marginTop: 2,
  },
  modalRowDisabled: {
    opacity: 0.6,
  },
  modalProgressWrap: {
    padding: Spacing.mediumLarge,
    backgroundColor: Colors.backgroundSecondary,
    marginHorizontal: Spacing.mediumLarge,
    marginBottom: Spacing.small,
    borderRadius: BorderRadius.medium,
  },
  modalProgressText: {
    ...Typography.caption1,
    color: Colors.textSecondary,
    marginTop: Spacing.small,
    textAlign: 'center',
  },
  modalClose: {
    padding: Spacing.mediumLarge,
    alignItems: 'center',
  },
  modalCloseText: {
    ...Typography.headline,
    color: Colors.primaryBlue,
  },
});
