/**
 * ModelsScreen.tsx
 *
 * Models management screen matching Swift SDK's SimplifiedModelsView pattern.
 * Shows available frameworks and models organized by framework.
 *
 * Reference: sdk/runanywhere-swift/examples/ios/RunAnywhereAI/Features/Models/SimplifiedModelsView.swift
 */

import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  Alert,
} from 'react-native';
import { RunAnywhere, LLMFramework, ModelCategory } from 'runanywhere-react-native';

// Extended ModelInfo interface that includes all catalog properties
// The SDK's ModelInfo type may need to be rebuilt, but at runtime these properties exist
interface CatalogModelInfo {
  id: string;
  name: string;
  category: ModelCategory | string;
  format?: string;
  downloadURL?: string;
  localPath?: string;
  downloadSize?: number;
  memoryRequired?: number;
  compatibleFrameworks?: LLMFramework[];
  preferredFramework?: LLMFramework;
  contextLength?: number;
  supportsThinking?: boolean;
  isDownloaded?: boolean;
  isAvailable?: boolean;
  metadata?: { description?: string; author?: string; license?: string; tags?: string[] };
}

// Use the extended type for models
type ModelInfo = CatalogModelInfo;

interface FrameworkDisplayInfo {
  displayName: string;
  description: string;
  icon: string;
}

// Framework display information (matching Swift SDK)
// Using a simple object to allow partial definitions
const FRAMEWORK_DISPLAY_INFO: { [key: string]: FrameworkDisplayInfo } = {
  [LLMFramework.LlamaCpp]: {
    displayName: 'llama.cpp',
    description: 'GGUF/GGML quantized models',
    icon: '🦙',
  },
  [LLMFramework.ONNX]: {
    displayName: 'ONNX Runtime',
    description: 'Cross-platform ONNX models',
    icon: '⚡',
  },
  [LLMFramework.MediaPipe]: {
    displayName: 'MediaPipe',
    description: "Google's ML framework",
    icon: '🧠',
  },
  [LLMFramework.FoundationModels]: {
    displayName: 'Foundation Models',
    description: "Apple's system models (iOS 18+)",
    icon: '🍎',
  },
  [LLMFramework.CoreML]: {
    displayName: 'Core ML',
    description: "Apple's Core ML framework",
    icon: '🔷',
  },
  [LLMFramework.WhisperKit]: {
    displayName: 'WhisperKit',
    description: 'Speech recognition models',
    icon: '🎙️',
  },
  [LLMFramework.SystemTTS]: {
    displayName: 'System TTS',
    description: 'Built-in text-to-speech',
    icon: '🔊',
  },
};

// Helper to get framework info with defaults
const getFrameworkInfo = (framework: LLMFramework): FrameworkDisplayInfo => {
  return FRAMEWORK_DISPLAY_INFO[framework] || {
    displayName: framework,
    description: 'Machine learning framework',
    icon: '📦',
  };
};

export const ModelsScreen: React.FC = () => {
  const [availableFrameworks, setAvailableFrameworks] = useState<LLMFramework[]>([]);
  const [expandedFramework, setExpandedFramework] = useState<LLMFramework | null>(null);
  const [allModels, setAllModels] = useState<ModelInfo[]>([]);
  const [frameworkModels, setFrameworkModels] = useState<ModelInfo[]>([]);
  const [loadingFrameworks, setLoadingFrameworks] = useState(true);
  const [loadingModels, setLoadingModels] = useState(false);
  const [downloadingModelId, setDownloadingModelId] = useState<string | null>(null);
  const [downloadProgress, setDownloadProgress] = useState<number>(0);

  useEffect(() => {
    loadData();
  }, []);

  // Load both models and extract frameworks from them
  const loadData = async () => {
    try {
      setLoadingFrameworks(true);

      // First, try to get models from the SDK
      // Cast to our extended type since the runtime models have these properties
      const models = (await RunAnywhere.getAvailableModels()) as ModelInfo[];
      console.log('[ModelsScreen] All models:', models.length);
      setAllModels(models);

      // Extract unique frameworks from models (more reliable than getAvailableFrameworks)
      // This ensures we always show frameworks that have models
      const frameworksFromModels = new Set<LLMFramework>();
      for (const model of models) {
        // Add preferred framework
        if (model.preferredFramework) {
          frameworksFromModels.add(model.preferredFramework as LLMFramework);
        }
        // Add all compatible frameworks
        if (model.compatibleFrameworks) {
          for (const fw of model.compatibleFrameworks) {
            frameworksFromModels.add(fw as LLMFramework);
          }
        }
      }

      // Also try to get frameworks from registered providers
      try {
        // Cast to any since the method may not be in the compiled types yet
        const sdk = RunAnywhere as any;
        if (typeof sdk.getAvailableFrameworks === 'function') {
          const registeredFrameworks = sdk.getAvailableFrameworks() as LLMFramework[];
          console.log('[ModelsScreen] Registered frameworks:', registeredFrameworks);
          for (const fw of registeredFrameworks) {
            frameworksFromModels.add(fw);
          }
        }
      } catch (e) {
        console.log('[ModelsScreen] getAvailableFrameworks error (non-critical):', e);
      }

      const frameworks = Array.from(frameworksFromModels);
      console.log('[ModelsScreen] Final frameworks:', frameworks);
      setAvailableFrameworks(frameworks);

    } catch (error) {
      console.error('[ModelsScreen] Failed to load data:', error);
      setAllModels([]);
      setAvailableFrameworks([]);
    } finally {
      setLoadingFrameworks(false);
    }
  };

  const handleFrameworkTap = (framework: LLMFramework) => {
    if (expandedFramework === framework) {
      // Collapse
      setExpandedFramework(null);
      setFrameworkModels([]);
    } else {
      // Expand and filter models for this framework from the already-loaded models
      setExpandedFramework(framework);

      // Filter models that are compatible with this framework
      const models = allModels.filter(m =>
        m.preferredFramework === framework ||
        (m.compatibleFrameworks && m.compatibleFrameworks.includes(framework))
      );
      console.log(`[ModelsScreen] Models for ${framework}:`, models.length);
      setFrameworkModels(models);
    }
  };

  const renderFrameworkSection = () => {
    if (loadingFrameworks) {
      return (
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="small" color="#007AFF" />
          <Text style={styles.loadingText}>Loading frameworks...</Text>
        </View>
      );
    }

    if (availableFrameworks.length === 0) {
      return (
        <View style={styles.emptyContainer}>
          <Text style={styles.emptyText}>No framework adapters are currently registered.</Text>
          <Text style={styles.emptySubtext}>
            Register framework adapters to see available frameworks.
          </Text>
        </View>
      );
    }

    return availableFrameworks.map((framework) => {
      const info = getFrameworkInfo(framework);
      const isExpanded = expandedFramework === framework;
      // Count models for this framework
      const modelCount = allModels.filter(m =>
        m.preferredFramework === framework ||
        (m.compatibleFrameworks && m.compatibleFrameworks.includes(framework))
      ).length;

      return (
        <View key={framework} style={styles.frameworkContainer}>
          <TouchableOpacity
            style={styles.frameworkRow}
            onPress={() => handleFrameworkTap(framework)}
            activeOpacity={0.7}
          >
            <Text style={styles.frameworkIcon}>{info.icon}</Text>
            <View style={styles.frameworkInfo}>
              <Text style={styles.frameworkName}>{info.displayName}</Text>
              <Text style={styles.frameworkDescription}>
                {info.description} • {modelCount} model{modelCount !== 1 ? 's' : ''}
              </Text>
            </View>
            <Text style={styles.chevron}>{isExpanded ? '▼' : '▶'}</Text>
          </TouchableOpacity>

          {isExpanded && renderModelsForFramework()}
        </View>
      );
    });
  };

  const renderModelsForFramework = () => {
    if (loadingModels) {
      return (
        <View style={styles.modelsLoadingContainer}>
          <ActivityIndicator size="small" color="#007AFF" />
          <Text style={styles.modelsLoadingText}>Loading models...</Text>
        </View>
      );
    }

    if (frameworkModels.length === 0) {
      return (
        <View style={styles.noModelsContainer}>
          <Text style={styles.noModelsText}>No models available for this framework</Text>
          <Text style={styles.noModelsSubtext}>Tap 'Add Model' to add a model from URL</Text>
        </View>
      );
    }

    return (
      <View style={styles.modelsContainer}>
        {frameworkModels.map((model) => renderModelRow(model))}
      </View>
    );
  };

  const renderModelRow = (model: ModelInfo) => {
    const isDownloaded = !!model.localPath || model.isDownloaded;
    const sizeInMB = model.downloadSize
      ? (model.downloadSize / (1024 * 1024)).toFixed(0)
      : model.memoryRequired
        ? (model.memoryRequired / (1024 * 1024)).toFixed(0)
        : '?';
    const formatLabel = model.format ? String(model.format).toUpperCase() : 'GGUF';

    return (
      <View key={model.id} style={styles.modelRow}>
        <View style={styles.modelInfo}>
          <Text style={styles.modelName}>{model.name}</Text>
          <View style={styles.modelMeta}>
            <View style={styles.badge}>
              <Text style={styles.badgeText}>{sizeInMB}MB</Text>
            </View>
            <View style={styles.badge}>
              <Text style={styles.badgeText}>{formatLabel}</Text>
            </View>
            {isDownloaded && (
              <View style={[styles.badge, styles.downloadedBadge]}>
                <Text style={styles.downloadedBadgeText}>✓ Downloaded</Text>
              </View>
            )}
          </View>
        </View>
        {!isDownloaded && downloadingModelId !== model.id && (
          <TouchableOpacity
            style={styles.downloadButton}
            onPress={() => handleDownload(model)}
            activeOpacity={0.7}
          >
            <Text style={styles.downloadButtonText}>Download</Text>
          </TouchableOpacity>
        )}
        {!isDownloaded && downloadingModelId === model.id && (
          <View style={styles.progressContainer}>
            <ActivityIndicator size="small" color="#007AFF" />
            <Text style={styles.progressText}>{(downloadProgress * 100).toFixed(0)}%</Text>
          </View>
        )}
        {isDownloaded && (
          <TouchableOpacity
            style={styles.loadButton}
            onPress={() => handleLoad(model)}
            activeOpacity={0.7}
          >
            <Text style={styles.loadButtonText}>Load</Text>
          </TouchableOpacity>
        )}
      </View>
    );
  };

  const handleDownload = async (model: ModelInfo) => {
    if (downloadingModelId) {
      Alert.alert('Download in Progress', 'Please wait for the current download to complete.');
      return;
    }

    Alert.alert(
      'Download Model',
      `Download ${model.name}? This may take a while depending on model size.`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Download',
          onPress: async () => {
            try {
              console.log('[ModelsScreen] Starting download for model:', model.id);
              setDownloadingModelId(model.id);
              setDownloadProgress(0);

              const localPath = await RunAnywhere.downloadModel(model.id, (progress) => {
                console.log(`[ModelsScreen] Download progress: ${(progress.progress * 100).toFixed(1)}%`);
                setDownloadProgress(progress.progress);
              });

              console.log('[ModelsScreen] Download completed:', localPath);
              setDownloadingModelId(null);
              setDownloadProgress(0);

              // Refresh the models list
              await loadData();

              Alert.alert('Success', `${model.name} downloaded successfully!`);
            } catch (error) {
              console.error('[ModelsScreen] Download error:', error);
              setDownloadingModelId(null);
              setDownloadProgress(0);
              Alert.alert('Download Failed', `Failed to download ${model.name}: ${error}`);
            }
          },
        },
      ]
    );
  };

  const handleLoad = (model: ModelInfo) => {
    if (!model.localPath) {
      Alert.alert('Error', 'Model not downloaded');
      return;
    }

    Alert.alert(
      'Load Model',
      `Load ${model.name}?`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Load',
          onPress: async () => {
            try {
              console.log('[ModelsScreen] Loading model:', model.id, 'from:', model.localPath);
              const success = await RunAnywhere.loadTextModel(model.localPath!);
              if (success) {
                Alert.alert('Success', `${model.name} loaded successfully`);
              } else {
                Alert.alert('Error', 'Failed to load model');
              }
            } catch (error) {
              console.error('[ModelsScreen] Load error:', error);
              Alert.alert('Error', `Failed to load model: ${error}`);
            }
          },
        },
      ]
    );
  };

  return (
    <View style={styles.container}>
      <ScrollView style={styles.scrollView} contentContainerStyle={styles.contentContainer}>
        {/* Frameworks Section */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Available Frameworks</Text>
          {renderFrameworkSection()}
        </View>

        {/* Models Summary */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Models Summary</Text>
          <View style={styles.summaryContainer}>
            <Text style={styles.summaryText}>Total Models: {allModels.length}</Text>
            <Text style={styles.summaryText}>
              Language Models: {allModels.filter(m => m.category === ModelCategory.Language).length}
            </Text>
            <Text style={styles.summaryText}>Frameworks: {availableFrameworks.length}</Text>
          </View>
        </View>
      </ScrollView>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#F2F2F7',
  },
  scrollView: {
    flex: 1,
  },
  contentContainer: {
    padding: 16,
    paddingBottom: 32,
  },
  section: {
    marginBottom: 24,
  },
  sectionTitle: {
    fontSize: 22,
    fontWeight: '600',
    color: '#000',
    marginBottom: 12,
  },
  loadingContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 16,
    backgroundColor: '#FFF',
    borderRadius: 12,
  },
  loadingText: {
    marginLeft: 12,
    fontSize: 16,
    color: '#8E8E93',
  },
  emptyContainer: {
    padding: 20,
    backgroundColor: '#FFF',
    borderRadius: 12,
  },
  emptyText: {
    fontSize: 16,
    color: '#000',
    marginBottom: 8,
  },
  emptySubtext: {
    fontSize: 14,
    color: '#8E8E93',
  },
  frameworkContainer: {
    marginBottom: 12,
    backgroundColor: '#FFF',
    borderRadius: 12,
    overflow: 'hidden',
  },
  frameworkRow: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 16,
  },
  frameworkIcon: {
    fontSize: 32,
    marginRight: 16,
  },
  frameworkInfo: {
    flex: 1,
  },
  frameworkName: {
    fontSize: 18,
    fontWeight: '600',
    color: '#000',
    marginBottom: 4,
  },
  frameworkDescription: {
    fontSize: 14,
    color: '#8E8E93',
  },
  chevron: {
    fontSize: 16,
    color: '#8E8E93',
    marginLeft: 8,
  },
  modelsLoadingContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 16,
    paddingTop: 0,
  },
  modelsLoadingText: {
    marginLeft: 12,
    fontSize: 14,
    color: '#8E8E93',
  },
  noModelsContainer: {
    padding: 16,
    paddingTop: 0,
  },
  noModelsText: {
    fontSize: 14,
    color: '#8E8E93',
    marginBottom: 4,
  },
  noModelsSubtext: {
    fontSize: 12,
    color: '#007AFF',
  },
  modelsContainer: {
    paddingHorizontal: 16,
    paddingBottom: 12,
    borderTopWidth: 1,
    borderTopColor: '#E5E5EA',
  },
  modelRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#F2F2F7',
  },
  modelInfo: {
    flex: 1,
  },
  modelName: {
    fontSize: 16,
    fontWeight: '500',
    color: '#000',
    marginBottom: 6,
  },
  modelMeta: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
  },
  badge: {
    paddingHorizontal: 8,
    paddingVertical: 3,
    backgroundColor: '#E5E5EA',
    borderRadius: 4,
  },
  badgeText: {
    fontSize: 11,
    fontWeight: '600',
    color: '#8E8E93',
  },
  downloadedBadge: {
    backgroundColor: '#D1F2EB',
  },
  downloadedBadgeText: {
    fontSize: 11,
    fontWeight: '600',
    color: '#00B894',
  },
  downloadButton: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    backgroundColor: '#007AFF',
    borderRadius: 8,
    marginLeft: 12,
  },
  downloadButtonText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#FFF',
  },
  progressContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginLeft: 12,
    minWidth: 60,
  },
  progressText: {
    marginLeft: 8,
    fontSize: 12,
    fontWeight: '600',
    color: '#007AFF',
  },
  loadButton: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    backgroundColor: '#34C759',
    borderRadius: 8,
    marginLeft: 12,
  },
  loadButtonText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#FFF',
  },
  summaryContainer: {
    padding: 16,
    backgroundColor: '#FFF',
    borderRadius: 12,
  },
  summaryText: {
    fontSize: 16,
    color: '#000',
    marginBottom: 8,
  },
});
