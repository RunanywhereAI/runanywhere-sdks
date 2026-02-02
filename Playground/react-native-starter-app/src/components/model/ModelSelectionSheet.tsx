/**
 * ModelSelectionSheet - Reusable model selection component
 *
 * Reference: iOS Features/Models/ModelSelectionSheet.swift
 *
 * Features:
 * - Device status section
 * - Framework list with expansion
 * - Model list with download/select actions
 * - Loading overlay for model loading
 * - Context-based filtering (LLM, STT, TTS, Voice)
 */

import React, { useState, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  Modal,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  ActivityIndicator,
  SafeAreaView,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../../theme/colors';
import { Typography, FontWeight } from '../../theme/typography';
import { Spacing, Padding, BorderRadius } from '../../theme/spacing';
import type { DeviceInfo } from '../../types/model';
import {
  ModelCategory,
  LLMFramework,
  FrameworkDisplayNames,
} from '../../types/model';

// Import SDK types and values
// Import RunAnywhere SDK (Multi-Package Architecture)
import {
  RunAnywhere,
  type ModelInfo as SDKModelInfo,
  LLMFramework as SDKLLMFramework,
  ModelCategory as SDKModelCategory,
  requireDeviceInfoModule,
} from '@runanywhere/core';

/**
 * Context for filtering frameworks and models based on the current experience/modality
 */
export enum ModelSelectionContext {
  LLM = 'llm', // Chat experience - show LLM frameworks
  STT = 'stt', // Speech-to-Text - show STT frameworks
  TTS = 'tts', // Text-to-Speech - show TTS frameworks
  Voice = 'voice', // Voice Assistant - show all voice-related
}

/**
 * Get title for context
 */
const getContextTitle = (context: ModelSelectionContext): string => {
  switch (context) {
    case ModelSelectionContext.LLM:
      return 'Select LLM Model';
    case ModelSelectionContext.STT:
      return 'Select STT Model';
    case ModelSelectionContext.TTS:
      return 'Select TTS Model';
    case ModelSelectionContext.Voice:
      return 'Select Model';
  }
};

/**
 * Get relevant categories for context (kept for reference)
 */
const _getRelevantCategories = (
  context: ModelSelectionContext
): Set<ModelCategory> => {
  switch (context) {
    case ModelSelectionContext.LLM:
      return new Set([ModelCategory.Language, ModelCategory.Multimodal]);
    case ModelSelectionContext.STT:
      return new Set([ModelCategory.SpeechRecognition]);
    case ModelSelectionContext.TTS:
      return new Set([ModelCategory.SpeechSynthesis]);
    case ModelSelectionContext.Voice:
      return new Set([
        ModelCategory.Language,
        ModelCategory.Multimodal,
        ModelCategory.SpeechRecognition,
        ModelCategory.SpeechSynthesis,
      ]);
  }
};

/**
 * Get category string for SDK filtering (uses SDK's ModelCategory enum values)
 */
const getCategoryForContext = (
  context: ModelSelectionContext
): string | null => {
  switch (context) {
    case ModelSelectionContext.LLM:
      return SDKModelCategory.Language; // 'language'
    case ModelSelectionContext.STT:
      return SDKModelCategory.SpeechRecognition; // 'speech-recognition'
    case ModelSelectionContext.TTS:
      return SDKModelCategory.SpeechSynthesis; // 'speech-synthesis'
    case ModelSelectionContext.Voice:
      return null; // Show all
  }
};

/**
 * Framework info for display
 */
interface FrameworkDisplayInfo {
  framework: LLMFramework;
  displayName: string;
  iconName: string;
  color: string;
  modelCount: number;
}

/**
 * Get framework display info
 */
const getFrameworkInfo = (
  framework: LLMFramework,
  modelCount: number
): FrameworkDisplayInfo => {
  const colorMap: Record<LLMFramework, string> = {
    [LLMFramework.LlamaCpp]: Colors.frameworkLlamaCpp,
    [LLMFramework.WhisperKit]: Colors.frameworkWhisperKit,
    [LLMFramework.ONNX]: Colors.frameworkONNX,
    [LLMFramework.CoreML]: Colors.frameworkCoreML,
    [LLMFramework.FoundationModels]: Colors.frameworkFoundationModels,
    [LLMFramework.TensorFlowLite]: Colors.frameworkTFLite,
    [LLMFramework.PiperTTS]: Colors.frameworkPiperTTS,
    [LLMFramework.SystemTTS]: Colors.frameworkSystemTTS,
    [LLMFramework.MLX]: Colors.primaryPurple,
    [LLMFramework.SwiftTransformers]: Colors.primaryBlue,
    [LLMFramework.ExecuTorch]: Colors.primaryOrange,
    [LLMFramework.PicoLLM]: Colors.primaryGreen,
    [LLMFramework.MLC]: Colors.primaryBlue,
    [LLMFramework.MediaPipe]: Colors.primaryOrange,
    [LLMFramework.OpenAIWhisper]: Colors.primaryGreen,
  };

  const iconMap: Record<LLMFramework, string> = {
    [LLMFramework.LlamaCpp]: 'terminal-outline',
    [LLMFramework.WhisperKit]: 'mic-outline',
    [LLMFramework.ONNX]: 'cube-outline',
    [LLMFramework.CoreML]: 'hardware-chip-outline',
    [LLMFramework.FoundationModels]: 'sparkles-outline',
    [LLMFramework.TensorFlowLite]: 'layers-outline',
    [LLMFramework.PiperTTS]: 'volume-high-outline',
    [LLMFramework.SystemTTS]: 'megaphone-outline',
    [LLMFramework.MLX]: 'flash-outline',
    [LLMFramework.SwiftTransformers]: 'code-slash-outline',
    [LLMFramework.ExecuTorch]: 'flame-outline',
    [LLMFramework.PicoLLM]: 'radio-outline',
    [LLMFramework.MLC]: 'git-branch-outline',
    [LLMFramework.MediaPipe]: 'videocam-outline',
    [LLMFramework.OpenAIWhisper]: 'ear-outline',
  };

  return {
    framework,
    displayName: FrameworkDisplayNames[framework] || framework,
    iconName: iconMap[framework] || 'extension-puzzle-outline',
    color: colorMap[framework] || Colors.primaryBlue,
    modelCount,
  };
};

/**
 * Format bytes to human-readable string
 */
const formatBytes = (bytes: number): string => {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`;
};

interface ModelSelectionSheetProps {
  visible: boolean;
  context: ModelSelectionContext;
  onClose: () => void;
  onModelSelected: (model: SDKModelInfo) => Promise<void>;
}

export const ModelSelectionSheet: React.FC<ModelSelectionSheetProps> = ({
  visible,
  context,
  onClose,
  onModelSelected,
}) => {
  // State
  const [availableModels, setAvailableModels] = useState<SDKModelInfo[]>([]);
  const [expandedFramework, setExpandedFramework] =
    useState<LLMFramework | null>(null);
  const [isLoadingModel, setIsLoadingModel] = useState(false);
  const [loadingProgress, _setLoadingProgress] = useState('');
  const [selectedModelId, setSelectedModelId] = useState<string | null>(null);
  // Track multiple downloads: modelId -> progress (0-1)
  const [downloadingModels, setDownloadingModels] = useState<
    Record<string, number>
  >({});
  const [deviceInfo, setDeviceInfo] = useState<DeviceInfo | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  /**
   * Load available models and device info
   */
  const loadData = useCallback(async () => {
    setIsLoading(true);
    try {
      // Load models from SDK
      const allModels = await RunAnywhere.getAvailableModels();
      const categoryFilter = getCategoryForContext(context);

      console.warn('[ModelSelectionSheet] All models count:', allModels.length);
      console.warn('[ModelSelectionSheet] Category filter:', categoryFilter);
      if (allModels.length > 0) {
        console.warn(
          '[ModelSelectionSheet] First model:',
          JSON.stringify(allModels[0], null, 2)
        );
      }

      // Filter models based on context (using category field)
      // Check both enum string value and direct comparison
      let filteredModels = categoryFilter
        ? allModels.filter((m: SDKModelInfo) => {
            const modelCategory = m.category;
            const matches =
              modelCategory === categoryFilter ||
              String(modelCategory).toLowerCase() ===
                String(categoryFilter).toLowerCase();
            return matches;
          })
        : allModels;

      console.warn(
        '[ModelSelectionSheet] Filtered models count:',
        filteredModels.length
      );

      // Fallback: if no models found after filtering for LLM, show models with LlamaCpp framework
      if (
        filteredModels.length === 0 &&
        context === ModelSelectionContext.LLM
      ) {
        console.warn(
          '[ModelSelectionSheet] No category matches, trying framework fallback'
        );
        filteredModels = allModels.filter((m: SDKModelInfo) => {
          const hasLlamaFramework =
            m.preferredFramework === SDKLLMFramework.LlamaCpp ||
            m.compatibleFrameworks?.includes(SDKLLMFramework.LlamaCpp);
          return hasLlamaFramework;
        });
        console.warn(
          '[ModelSelectionSheet] Framework fallback models:',
          filteredModels.length
        );
      }

      // Ultimate fallback: just show all models for LLM context if nothing else works
      if (
        filteredModels.length === 0 &&
        context === ModelSelectionContext.LLM &&
        allModels.length > 0
      ) {
        console.warn(
          '[ModelSelectionSheet] Using all models as final fallback'
        );
        filteredModels = allModels;
      }

      setAvailableModels(filteredModels);

      // Load real device info from native module
      try {
        const deviceInfoModule = requireDeviceInfoModule();
        const [
          modelName,
          chipName,
          totalMemory,
          availableMemory,
          hasNeuralEngine,
          osVersion,
          hasGPU,
          cpuCores,
        ] = await Promise.all([
          deviceInfoModule.getDeviceModel(),
          deviceInfoModule.getChipName(),
          deviceInfoModule.getTotalRAM(),
          deviceInfoModule.getAvailableRAM(),
          deviceInfoModule.hasNPU(),
          deviceInfoModule.getOSVersion(),
          deviceInfoModule.hasGPU(),
          deviceInfoModule.getCPUCores(),
        ]);

        setDeviceInfo({
          modelName,
          chipName: chipName || 'Unknown',
          totalMemory,
          availableMemory,
          hasNeuralEngine,
          osVersion,
          hasGPU,
          cpuCores,
        });
      } catch (error) {
        console.warn(
          '[ModelSelectionSheet] Failed to load device info:',
          error
        );
        // Fallback to basic info
        setDeviceInfo({
          modelName: 'Unknown Device',
          chipName: 'Unknown',
          totalMemory: 0,
          availableMemory: 0,
          hasNeuralEngine: false,
          osVersion: 'Unknown',
        });
      }
    } catch (error) {
      console.error('[ModelSelectionSheet] Error loading data:', error);
    } finally {
      setIsLoading(false);
    }
  }, [context]);

  // Load data when visible or on mount
  // This ensures models are loaded even if the sheet renders before becoming visible
  useEffect(() => {
    loadData();
  }, [loadData]);

  // Reload data when visibility changes to ensure fresh data
  useEffect(() => {
    if (visible) {
      loadData();
    }
  }, [visible, loadData]);

  /**
   * Get frameworks with their model counts
   */
  const getFrameworks = useCallback((): FrameworkDisplayInfo[] => {
    const frameworkCounts = new Map<LLMFramework, number>();

    console.warn(
      '[ModelSelectionSheet] getFrameworks called, availableModels count:',
      availableModels.length
    );

    availableModels.forEach((model: SDKModelInfo, index: number) => {
      // Determine framework from model - use preferredFramework or first compatibleFramework
      const frameworkValue =
        model.preferredFramework || model.compatibleFrameworks?.[0];

      if (index < 3) {
        console.warn(
          `[ModelSelectionSheet] Model ${index}: preferredFramework=${model.preferredFramework}, compatibleFrameworks=${JSON.stringify(model.compatibleFrameworks)}`
        );
      }

      // Map string to enum if needed
      let framework: LLMFramework;
      if (
        typeof frameworkValue === 'string' &&
        frameworkValue in LLMFramework
      ) {
        framework = LLMFramework[frameworkValue as keyof typeof LLMFramework];
      } else if (Object.values(LLMFramework).includes(frameworkValue)) {
        framework = frameworkValue as LLMFramework;
      } else {
        framework = LLMFramework.LlamaCpp; // Default
      }

      const count = frameworkCounts.get(framework) || 0;
      frameworkCounts.set(framework, count + 1);
    });

    // Add System TTS for TTS context
    if (context === ModelSelectionContext.TTS) {
      frameworkCounts.set(LLMFramework.SystemTTS, 1);
    }

    console.warn(
      '[ModelSelectionSheet] Framework counts:',
      Array.from(frameworkCounts.entries())
    );

    return Array.from(frameworkCounts.entries())
      .map(([framework, count]) => getFrameworkInfo(framework, count))
      .sort((a, b) => b.modelCount - a.modelCount);
  }, [availableModels, context]);

  /**
   * Get models for a specific framework
   */
  const getModelsForFramework = useCallback(
    (framework: LLMFramework): SDKModelInfo[] => {
      return availableModels.filter((model: SDKModelInfo) => {
        // Check preferredFramework first, then compatibleFrameworks
        const modelFramework =
          (model.preferredFramework as LLMFramework) ||
          (model.compatibleFrameworks?.[0] as LLMFramework) ||
          LLMFramework.LlamaCpp;

        // Also check if this framework is in compatibleFrameworks
        const isCompatible = model.compatibleFrameworks?.includes(framework);

        return modelFramework === framework || isCompatible;
      });
    },
    [availableModels]
  );

  /**
   * Toggle framework expansion
   */
  const toggleFramework = (framework: LLMFramework) => {
    setExpandedFramework(expandedFramework === framework ? null : framework);
  };

  /**
   * Handle model selection
   */
  const handleSelectModel = async (model: SDKModelInfo) => {
    if (!model.isDownloaded && !model.localPath) {
      // Model needs to be downloaded first
      return;
    }

    // Don't show loading overlay - parent will close modal and show loading state
    // Just call the callback and let parent handle the rest
    try {
      await onModelSelected(model);
      // Parent is responsible for closing the modal
    } catch (error) {
      console.error('[ModelSelectionSheet] Error selecting model:', error);
    }
  };

  /**
   * Handle model download with real-time progress
   * Supports multiple concurrent downloads
   */
  const handleDownloadModel = async (model: SDKModelInfo) => {
    // Add this model to downloading set
    setDownloadingModels((prev) => ({ ...prev, [model.id]: 0 }));

    try {
      // Use real download API with progress callback
      await RunAnywhere.downloadModel(model.id, (progress) => {
        // Update progress for this specific model
        setDownloadingModels((prev) => ({
          ...prev,
          [model.id]: progress.progress,
        }));
        console.warn(
          `[Download] ${model.id}: ${Math.round(progress.progress * 100)}% (${formatBytes(progress.bytesDownloaded)} / ${formatBytes(progress.totalBytes)})`
        );
      });

      // Refresh models after download
      await loadData();
    } catch (error) {
      console.error('[ModelSelectionSheet] Error downloading model:', error);
    } finally {
      // Remove this model from downloading set
      setDownloadingModels((prev) => {
        const updated = { ...prev };
        delete updated[model.id];
        return updated;
      });
    }
  };

  /**
   * Handle System TTS selection
   */
  const handleSelectSystemTTS = async () => {
    try {
      // Create a pseudo model for System TTS
      const systemTTSModel = {
        id: 'system-tts',
        name: 'System TTS',
        category: ModelCategory.SpeechSynthesis,
        preferredFramework: LLMFramework.SystemTTS,
        compatibleFrameworks: [LLMFramework.SystemTTS],
        isDownloaded: true,
        isAvailable: true,
        downloadSize: 0,
        memoryRequired: 0,
        format: 'system',
      } as unknown as SDKModelInfo;

      // Parent is responsible for closing the modal
      await onModelSelected(systemTTSModel);
    } catch (error) {
      console.error('[ModelSelectionSheet] Error selecting System TTS:', error);
    }
  };

  /**
   * Render device status section
   */
  const renderDeviceStatus = () => (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>Device Status</Text>
      {deviceInfo ? (
        <View style={styles.card}>
          <View style={styles.infoRow}>
            <View style={styles.infoLabel}>
              <Icon
                name="phone-portrait-outline"
                size={18}
                color={Colors.textSecondary}
              />
              <Text style={styles.infoLabelText}>Model</Text>
            </View>
            <Text style={styles.infoValue}>{deviceInfo.modelName}</Text>
          </View>

          <View style={styles.infoRow}>
            <View style={styles.infoLabel}>
              <Icon
                name="hardware-chip-outline"
                size={18}
                color={Colors.textSecondary}
              />
              <Text style={styles.infoLabelText}>Chip</Text>
            </View>
            <Text style={styles.infoValue}>{deviceInfo.chipName}</Text>
          </View>

          <View style={styles.infoRow}>
            <View style={styles.infoLabel}>
              <Icon
                name="server-outline"
                size={18}
                color={Colors.textSecondary}
              />
              <Text style={styles.infoLabelText}>Memory</Text>
            </View>
            <Text style={styles.infoValue}>
              {formatBytes(deviceInfo.totalMemory)}
            </Text>
          </View>

          {deviceInfo.cpuCores != null && deviceInfo.cpuCores > 0 && (
            <View style={styles.infoRow}>
              <View style={styles.infoLabel}>
                <Icon
                  name="speedometer-outline"
                  size={18}
                  color={Colors.textSecondary}
                />
                <Text style={styles.infoLabelText}>CPU Cores</Text>
              </View>
              <Text style={styles.infoValue}>{deviceInfo.cpuCores}</Text>
            </View>
          )}

          <View style={styles.infoRow}>
            <View style={styles.infoLabel}>
              <Icon
                name="cube-outline"
                size={18}
                color={Colors.textSecondary}
              />
              <Text style={styles.infoLabelText}>GPU</Text>
            </View>
            <Icon
              name={deviceInfo.hasGPU ? 'checkmark-circle' : 'close-circle'}
              size={20}
              color={deviceInfo.hasGPU ? Colors.statusGreen : Colors.statusRed}
            />
          </View>

          <View style={styles.infoRow}>
            <View style={styles.infoLabel}>
              <Icon
                name="flash-outline"
                size={18}
                color={Colors.textSecondary}
              />
              <Text style={styles.infoLabelText}>NPU/Neural Engine</Text>
            </View>
            <Icon
              name={
                deviceInfo.hasNeuralEngine ? 'checkmark-circle' : 'close-circle'
              }
              size={20}
              color={
                deviceInfo.hasNeuralEngine
                  ? Colors.statusGreen
                  : Colors.statusRed
              }
            />
          </View>
        </View>
      ) : (
        <View style={styles.card}>
          <ActivityIndicator size="small" color={Colors.primaryBlue} />
          <Text style={styles.loadingText}>Loading device info...</Text>
        </View>
      )}
    </View>
  );

  /**
   * Render framework row
   */
  const renderFrameworkRow = (info: FrameworkDisplayInfo) => {
    const isExpanded = expandedFramework === info.framework;

    return (
      <View key={info.framework}>
        <TouchableOpacity
          style={styles.frameworkRow}
          onPress={() => toggleFramework(info.framework)}
        >
          <View
            style={[
              styles.frameworkIcon,
              { backgroundColor: info.color + '20' },
            ]}
          >
            <Icon name={info.iconName} size={20} color={info.color} />
          </View>

          <View style={styles.frameworkInfo}>
            <Text style={styles.frameworkName}>{info.displayName}</Text>
            <Text style={styles.frameworkCount}>
              {info.modelCount} {info.modelCount === 1 ? 'model' : 'models'}
            </Text>
          </View>

          <Icon
            name={isExpanded ? 'chevron-up' : 'chevron-down'}
            size={20}
            color={Colors.textSecondary}
          />
        </TouchableOpacity>

        {isExpanded && renderExpandedModels(info.framework)}
      </View>
    );
  };

  /**
   * Render expanded models for a framework
   */
  const renderExpandedModels = (framework: LLMFramework) => {
    if (framework === LLMFramework.SystemTTS) {
      return renderSystemTTSRow();
    }

    const models = getModelsForFramework(framework);

    if (models.length === 0) {
      return (
        <View style={styles.emptyModels}>
          <Text style={styles.emptyText}>
            No models available for this framework
          </Text>
        </View>
      );
    }

    return (
      <View style={styles.modelsList}>
        {models.map((model) => renderModelRow(model))}
      </View>
    );
  };

  /**
   * Render System TTS row
   */
  const renderSystemTTSRow = () => (
    <View style={styles.modelsList}>
      <View style={styles.modelRow}>
        <View style={styles.modelInfo}>
          <Text style={styles.modelName}>Default System Voice</Text>
          <View style={styles.modelMeta}>
            <View style={styles.badge}>
              <Text style={styles.badgeText}>Built-in</Text>
            </View>
            <Text style={styles.modelMetaText}>AVSpeechSynthesizer</Text>
          </View>
          <View style={styles.statusRow}>
            <Icon
              name="checkmark-circle"
              size={14}
              color={Colors.statusGreen}
            />
            <Text style={[styles.statusText, { color: Colors.statusGreen }]}>
              Always available
            </Text>
          </View>
        </View>

        <TouchableOpacity
          style={styles.selectButton}
          onPress={handleSelectSystemTTS}
          disabled={isLoadingModel}
        >
          <Text style={styles.selectButtonText}>Select</Text>
        </TouchableOpacity>
      </View>
    </View>
  );

  /**
   * Render model row
   */
  const renderModelRow = (model: SDKModelInfo) => {
    const isDownloading = model.id in downloadingModels;
    const downloadProgress = downloadingModels[model.id] ?? 0;
    const isSelected = selectedModelId === model.id;
    const canSelect = model.isDownloaded || model.localPath;

    return (
      <View
        key={model.id}
        style={[
          styles.modelRow,
          isLoadingModel && !isSelected && styles.dimmed,
        ]}
      >
        <View style={styles.modelInfo}>
          <Text
            style={[styles.modelName, isSelected && styles.modelNameSelected]}
          >
            {model.name}
          </Text>

          <View style={styles.modelMeta}>
            {model.downloadSize != null && model.downloadSize > 0 && (
              <View style={styles.sizeTag}>
                <Icon
                  name="server-outline"
                  size={12}
                  color={Colors.textSecondary}
                />
                <Text style={styles.sizeText}>
                  {formatBytes(model.downloadSize)}
                </Text>
              </View>
            )}

            <View style={styles.badge}>
              <Text style={styles.badgeText}>
                {(model.format || 'GGUF').toUpperCase()}
              </Text>
            </View>
          </View>

          {/* Download/Status indicator */}
          <View style={styles.statusRow}>
            {isDownloading ? (
              <View style={styles.downloadProgressContainer}>
                <View style={styles.downloadProgressRow}>
                  <ActivityIndicator size="small" color={Colors.primaryBlue} />
                  <Text style={styles.statusText}>
                    Downloading... {Math.round(downloadProgress * 100)}%
                  </Text>
                </View>
                {/* Progress bar */}
                <View style={styles.progressBarBackground}>
                  <View
                    style={[
                      styles.progressBarFill,
                      { width: `${Math.round(downloadProgress * 100)}%` },
                    ]}
                  />
                </View>
              </View>
            ) : canSelect ? (
              <>
                <Icon
                  name="checkmark-circle"
                  size={14}
                  color={Colors.statusGreen}
                />
                <Text
                  style={[styles.statusText, { color: Colors.statusGreen }]}
                >
                  Downloaded
                </Text>
              </>
            ) : (
              <>
                <Icon
                  name="cloud-download-outline"
                  size={14}
                  color={Colors.statusBlue}
                />
                <Text style={[styles.statusText, { color: Colors.statusBlue }]}>
                  Available for download
                </Text>
              </>
            )}
          </View>
        </View>

        {/* Action button */}
        <View style={styles.actionButtons}>
          {isDownloading ? (
            <View style={styles.downloadingIndicator}>
              <ActivityIndicator size="small" color={Colors.primaryBlue} />
            </View>
          ) : canSelect ? (
            <TouchableOpacity
              style={[
                styles.selectButton,
                (isLoadingModel || isSelected) && styles.buttonDisabled,
              ]}
              onPress={() => handleSelectModel(model)}
              disabled={isLoadingModel || isSelected}
            >
              <Text style={styles.selectButtonText}>Select</Text>
            </TouchableOpacity>
          ) : (
            <TouchableOpacity
              style={styles.downloadButton}
              onPress={() => handleDownloadModel(model)}
              disabled={isLoadingModel}
            >
              <Text style={styles.downloadButtonText}>Download</Text>
            </TouchableOpacity>
          )}
        </View>
      </View>
    );
  };

  /**
   * Render loading overlay
   */
  const renderLoadingOverlay = () => {
    if (!isLoadingModel) return null;

    return (
      <View style={styles.loadingOverlay}>
        <View style={styles.loadingCard}>
          <ActivityIndicator size="large" color={Colors.primaryBlue} />
          <Text style={styles.loadingTitle}>Loading Model</Text>
          <Text style={styles.loadingMessage}>{loadingProgress}</Text>
        </View>
      </View>
    );
  };

  const frameworks = getFrameworks();

  return (
    <Modal
      visible={visible}
      animationType="slide"
      onRequestClose={onClose}
      onDismiss={() => {
        // Ensure state is cleaned up when modal is dismissed
        setIsLoadingModel(false);
        setSelectedModelId(null);
        // Don't clear downloads - they continue in background
      }}
    >
      <SafeAreaView style={styles.container}>
        {/* Header */}
        <View style={styles.header}>
          <TouchableOpacity
            style={styles.cancelButton}
            onPress={onClose}
            disabled={isLoadingModel}
          >
            <Text
              style={[styles.cancelText, isLoadingModel && styles.textDisabled]}
            >
              Cancel
            </Text>
          </TouchableOpacity>

          <Text style={styles.title}>{getContextTitle(context)}</Text>

          <View style={styles.headerSpacer} />
        </View>

        {/* Content */}
        <ScrollView style={styles.content} showsVerticalScrollIndicator={false}>
          {isLoading ? (
            <View style={styles.loadingContainer}>
              <ActivityIndicator size="large" color={Colors.primaryBlue} />
              <Text style={styles.loadingText}>Loading models...</Text>
            </View>
          ) : (
            <>
              {renderDeviceStatus()}

              {/* Frameworks Section */}
              <View style={styles.section}>
                <Text style={styles.sectionTitle}>Available Frameworks</Text>
                <View style={styles.card}>
                  {frameworks.length > 0 ? (
                    frameworks.map(renderFrameworkRow)
                  ) : (
                    <View style={styles.emptyModels}>
                      <Text style={styles.emptyText}>
                        No frameworks available
                      </Text>
                    </View>
                  )}
                </View>
              </View>
            </>
          )}
        </ScrollView>

        {/* Loading Overlay */}
        {renderLoadingOverlay()}
      </SafeAreaView>
    </Modal>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.backgroundSecondary,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding12,
    backgroundColor: Colors.backgroundPrimary,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  cancelButton: {
    minWidth: 60,
  },
  cancelText: {
    ...Typography.body,
    color: Colors.primaryBlue,
  },
  textDisabled: {
    opacity: 0.5,
  },
  title: {
    ...Typography.headline,
    color: Colors.textPrimary,
  },
  headerSpacer: {
    minWidth: 60,
  },
  content: {
    flex: 1,
  },
  loadingContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: Padding.padding60,
  },
  loadingText: {
    ...Typography.subheadline,
    color: Colors.textSecondary,
    marginTop: Spacing.medium,
  },
  section: {
    marginBottom: Spacing.large,
  },
  sectionTitle: {
    ...Typography.footnote,
    color: Colors.textSecondary,
    textTransform: 'uppercase',
    marginHorizontal: Padding.padding16,
    marginBottom: Spacing.small,
    marginTop: Spacing.large,
  },
  card: {
    backgroundColor: Colors.backgroundPrimary,
    marginHorizontal: Padding.padding16,
    borderRadius: BorderRadius.medium,
    overflow: 'hidden',
  },
  infoRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: Padding.padding12,
    paddingHorizontal: Padding.padding16,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: Colors.borderLight,
  },
  infoLabel: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.smallMedium,
  },
  infoLabelText: {
    ...Typography.body,
    color: Colors.textPrimary,
  },
  infoValue: {
    ...Typography.body,
    color: Colors.textSecondary,
  },
  frameworkRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: Padding.padding12,
    paddingHorizontal: Padding.padding16,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: Colors.borderLight,
  },
  frameworkIcon: {
    width: 36,
    height: 36,
    borderRadius: BorderRadius.regular,
    alignItems: 'center',
    justifyContent: 'center',
  },
  frameworkInfo: {
    flex: 1,
    marginLeft: Spacing.mediumLarge,
  },
  frameworkName: {
    ...Typography.body,
    color: Colors.textPrimary,
  },
  frameworkCount: {
    ...Typography.caption,
    color: Colors.textSecondary,
  },
  modelsList: {
    backgroundColor: Colors.backgroundSecondary,
    paddingHorizontal: Padding.padding16,
  },
  modelRow: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.backgroundPrimary,
    marginVertical: Spacing.xSmall,
    paddingVertical: Padding.padding12,
    paddingHorizontal: Padding.padding12,
    borderRadius: BorderRadius.regular,
  },
  dimmed: {
    opacity: 0.6,
  },
  modelInfo: {
    flex: 1,
  },
  modelName: {
    ...Typography.subheadline,
    color: Colors.textPrimary,
  },
  modelNameSelected: {
    fontWeight: FontWeight.semibold,
  },
  modelMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.small,
    marginTop: Spacing.xSmall,
  },
  sizeTag: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.xxSmall,
  },
  sizeText: {
    ...Typography.caption2,
    color: Colors.textSecondary,
  },
  badge: {
    backgroundColor: Colors.badgeGray,
    paddingHorizontal: Spacing.small,
    paddingVertical: Spacing.xxSmall,
    borderRadius: BorderRadius.small,
  },
  badgeText: {
    ...Typography.caption2,
    color: Colors.textSecondary,
  },
  modelMetaText: {
    ...Typography.caption2,
    color: Colors.textSecondary,
  },
  statusRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.xSmall,
    marginTop: Spacing.xSmall,
  },
  statusText: {
    ...Typography.caption2,
    color: Colors.textSecondary,
  },
  downloadProgressContainer: {
    flex: 1,
  },
  downloadProgressRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.xSmall,
  },
  progressBarBackground: {
    height: 4,
    backgroundColor: Colors.backgroundGray5,
    borderRadius: 2,
    marginTop: 6,
    overflow: 'hidden',
  },
  progressBarFill: {
    height: '100%',
    backgroundColor: Colors.primaryBlue,
    borderRadius: 2,
  },
  actionButtons: {
    marginLeft: Spacing.medium,
  },
  selectButton: {
    backgroundColor: Colors.primaryBlue,
    paddingHorizontal: Padding.padding12,
    paddingVertical: Padding.padding6,
    borderRadius: BorderRadius.regular,
  },
  selectButtonText: {
    ...Typography.caption,
    color: Colors.textWhite,
    fontWeight: FontWeight.semibold,
  },
  downloadButton: {
    backgroundColor: Colors.primaryBlue,
    paddingHorizontal: Padding.padding12,
    paddingVertical: Padding.padding6,
    borderRadius: BorderRadius.regular,
  },
  downloadButtonText: {
    ...Typography.caption,
    color: Colors.textWhite,
    fontWeight: FontWeight.semibold,
  },
  buttonDisabled: {
    opacity: 0.5,
  },
  downloadingIndicator: {
    padding: Padding.padding8,
  },
  emptyModels: {
    padding: Padding.padding16,
    alignItems: 'center',
  },
  emptyText: {
    ...Typography.subheadline,
    color: Colors.textSecondary,
  },
  loadingOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: Colors.overlayMedium,
    alignItems: 'center',
    justifyContent: 'center',
  },
  loadingCard: {
    backgroundColor: Colors.backgroundPrimary,
    paddingHorizontal: Padding.padding40,
    paddingVertical: Padding.padding30,
    borderRadius: BorderRadius.large,
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.15,
    shadowRadius: 12,
    elevation: 8,
  },
  loadingTitle: {
    ...Typography.headline,
    color: Colors.textPrimary,
    marginTop: Spacing.large,
  },
  loadingMessage: {
    ...Typography.subheadline,
    color: Colors.textSecondary,
    marginTop: Spacing.small,
    textAlign: 'center',
  },
});

export default ModelSelectionSheet;
