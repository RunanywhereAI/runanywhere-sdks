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
 * - Context-based filtering (LLM, STT, TTS, Voice, VLM, RAG Embedding, RAG LLM)
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
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../../theme/colors';
import { Typography, FontWeight } from '../../theme/typography';
import { Spacing, Padding, BorderRadius } from '../../theme/spacing';
import {
  DEFAULT_INFERENCE_FRAMEWORK,
  getFrameworkColor,
  getFrameworkDisplayName,
  getFrameworkIcon,
  getModelDownloadSizeBytes,
  getModelFormatLabel,
  getModelFrameworks,
  getPrimaryFramework,
  isModelCompatibleWithFramework,
} from '../../utils/modelDisplay';

// Import SDK types and values
// Import RunAnywhere SDK (Multi-Package Architecture)
import { RunAnywhere } from '@runanywhere/core';
import {
  InferenceFramework,
  ModelCategory,
  type ModelInfo as SDKModelInfo,
} from '@runanywhere/proto-ts/model_types';

// Canonical SDK methods (Swift parity).
const downloadModelStreamHelper = RunAnywhere.downloadModelStream;
const listModels = async (): Promise<SDKModelInfo[]> =>
  (await RunAnywhere.listModels()).models?.models ?? [];

/**
 * Context for filtering frameworks and models based on the current experience/modality
 */
export enum ModelSelectionContext {
  LLM = 'llm', // Chat experience - show LLM frameworks
  STT = 'stt', // Speech-to-Text - show STT frameworks
  TTS = 'tts', // Text-to-Speech - show TTS frameworks
  Voice = 'voice', // Voice Assistant - show all voice-related
  VAD = 'vad', // Voice Activity Detection
  VLM = 'vlm', // Vision - show VLM frameworks
  RagEmbedding = 'ragEmbedding', // RAG embedding - ONNX embedding models only
  RagLLM = 'ragLLM', // RAG generation - LlamaCpp language models only
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
    case ModelSelectionContext.VAD:
      return 'Select VAD Model';
    case ModelSelectionContext.VLM:
      return 'Select Vision Model';
    case ModelSelectionContext.RagEmbedding:
      return 'Select Embedding Model';
    case ModelSelectionContext.RagLLM:
      return 'Select LLM Model';
  }
};

/**
 * Get category for SDK filtering (uses SDK's `ModelCategory` proto enum).
 * Returns the proto-canonical numeric `ModelCategory` value or `null` to mean
 * "show all".
 */
const getCategoryForContext = (
  context: ModelSelectionContext
): ModelCategory | null => {
  switch (context) {
    case ModelSelectionContext.LLM:
      return ModelCategory.MODEL_CATEGORY_LANGUAGE;
    case ModelSelectionContext.STT:
      return ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION;
    case ModelSelectionContext.TTS:
      return ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS;
    case ModelSelectionContext.Voice:
      return null; // Show all
    case ModelSelectionContext.VAD:
      return ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION;
    case ModelSelectionContext.VLM:
      return ModelCategory.MODEL_CATEGORY_MULTIMODAL;
    case ModelSelectionContext.RagEmbedding:
      return ModelCategory.MODEL_CATEGORY_EMBEDDING;
    case ModelSelectionContext.RagLLM:
      return ModelCategory.MODEL_CATEGORY_LANGUAGE;
  }
};

/**
 * Get allowed frameworks for context.
 * Returns null if all frameworks are acceptable.
 */
const getAllowedFrameworksForContext = (
  context: ModelSelectionContext
): Set<InferenceFramework> | null => {
  switch (context) {
    case ModelSelectionContext.RagEmbedding:
      return new Set([InferenceFramework.INFERENCE_FRAMEWORK_ONNX]);
    case ModelSelectionContext.RagLLM:
      return new Set([InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP]);
    default:
      return null;
  }
};

/**
 * Whether this context is a RAG context (no model pre-loading needed)
 */
const isRAGContext = (context: ModelSelectionContext): boolean =>
  context === ModelSelectionContext.RagEmbedding ||
  context === ModelSelectionContext.RagLLM;

/**
 * Framework info for display
 */
interface FrameworkDisplayInfo {
  framework: InferenceFramework;
  displayName: string;
  iconName: string;
  color: string;
  modelCount: number;
}

/**
 * Get framework display info
 */
const getFrameworkInfo = (
  framework: InferenceFramework,
  modelCount: number
): FrameworkDisplayInfo => {
  return {
    framework,
    displayName: getFrameworkDisplayName(framework),
    iconName: getFrameworkIcon(framework),
    color: getFrameworkColor(framework),
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
    useState<InferenceFramework | null>(null);
  const [isLoadingModel, setIsLoadingModel] = useState(false);
  const [loadingProgress, _setLoadingProgress] = useState('');
  const [selectedModelId, setSelectedModelId] = useState<string | null>(null);
  // Track multiple downloads: modelId -> progress (0-1)
  const [downloadingModels, setDownloadingModels] = useState<
    Record<string, number>
  >({});
  const [isLoading, setIsLoading] = useState(true);

  /**
   * Load available models
   */
  const loadData = useCallback(async () => {
    setIsLoading(true);
    try {
      // Single canonical SDK query — category + (optional) framework
      // filter applied registry-side. The previous triple-fallback
      // (category → framework → all-models) papered over the registry
      // catalog when chosen IDs didn't match the strict combination;
      // empty results are now surfaced via the empty-state UI so the
      // user sees that no model is registered for the selected mode.
      const allModels = await listModels();
      const categoryFilter = getCategoryForContext(context);
      const allowedFrameworks = getAllowedFrameworksForContext(context);

      const filteredModels = categoryFilter
        ? allModels.filter((m: SDKModelInfo) => {
            const modelCategory = m.category;
            const categoryMatch =
              modelCategory === categoryFilter ||
              String(modelCategory).toLowerCase() ===
                String(categoryFilter).toLowerCase();
            if (!categoryMatch) return false;

            // Framework restriction (e.g., ONNX-only for embedding,
            // LlamaCpp-only for RAG LLM).
            if (allowedFrameworks) {
              const frameworks = getModelFrameworks(m);
              if (!frameworks.some((fw) => allowedFrameworks.has(fw))) {
                return false;
              }
            }
            return true;
          })
        : allModels;

      setAvailableModels(filteredModels);
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

  // B-RN-Sheet-Routing: clear stale lists when context changes so we don't
  // briefly render the previous tab's models while loadData is in flight.
  useEffect(() => {
    setAvailableModels([]);
    setExpandedFramework(null);
    setSelectedModelId(null);
  }, [context]);

  /**
   * Get frameworks with their model counts
   */
  const getFrameworks = useCallback((): FrameworkDisplayInfo[] => {
    const frameworkCounts = new Map<InferenceFramework, number>();

    availableModels.forEach((model: SDKModelInfo, _index: number) => {
      const framework = getPrimaryFramework(model, DEFAULT_INFERENCE_FRAMEWORK);

      const count = frameworkCounts.get(framework) || 0;
      frameworkCounts.set(framework, count + 1);
    });

    return Array.from(frameworkCounts.entries())
      .map(([framework, count]) => getFrameworkInfo(framework, count))
      .sort((a, b) => b.modelCount - a.modelCount);
  }, [availableModels]);

  /**
   * Get models for a specific framework
   */
  const getModelsForFramework = useCallback(
    (framework: InferenceFramework): SDKModelInfo[] => {
      return availableModels.filter((model: SDKModelInfo) => {
        return isModelCompatibleWithFramework(model, framework);
      });
    },
    [availableModels]
  );

  /**
   * Toggle framework expansion
   */
  const toggleFramework = (framework: InferenceFramework) => {
    setExpandedFramework(expandedFramework === framework ? null : framework);
  };

  /**
   * Handle model selection
   */
  const handleSelectModel = async (model: SDKModelInfo) => {
    console.warn('[ModelSelectionSheet] Select tapped:', model.id);
    if (!model.isDownloaded && !model.localPath) {
      return;
    }

    try {
      if (isRAGContext(context)) {
        // RAG models are referenced by file path at pipeline creation time,
        // not pre-loaded into memory. Just pass the selection back and close.
        await onModelSelected(model);
        onClose();
      } else {
        await onModelSelected(model);
      }
    } catch (error) {
      console.error('[ModelSelectionSheet] Error selecting model:', error);
    }
  };

  useEffect(() => {
    const testGlobal = globalThis as typeof globalThis & {
      __testModels?: SDKModelInfo[];
      __testOnModelSelected?: (model: SDKModelInfo) => Promise<void>;
    };
    testGlobal.__testModels = availableModels;
    testGlobal.__testOnModelSelected = onModelSelected;
  }, [availableModels, onModelSelected]);

  /**
   * Handle model download with real-time progress
   * Supports multiple concurrent downloads
   */
  const handleDownloadModel = async (model: SDKModelInfo) => {
    // B-RN-3-002: log entry so a missing call is visible in metro/logcat
    console.warn('[ModelSelectionSheet] Download tapped:', model.id);
    // Add this model to downloading set
    setDownloadingModels((prev) => ({ ...prev, [model.id]: 0 }));

    try {
      // Manual async iteration — Hermes doesn't recognise NitroModules async iterables with for-await
      const dlIter = downloadModelStreamHelper(model)[Symbol.asyncIterator]();
      let dlResult = await dlIter.next();
      while (!dlResult.done) {
        const progress = dlResult.value;
        setDownloadingModels((prev) => ({
          ...prev,
          [model.id]: progress.stageProgress ?? 0,
        }));
        console.warn(
          `[Download] ${model.id}: ${Math.round((progress.stageProgress ?? 0) * 100)}% (${formatBytes(progress.bytesDownloaded)} / ${formatBytes(progress.totalBytes)})`
        );
        dlResult = await dlIter.next();
      }

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
  const renderExpandedModels = (framework: InferenceFramework) => {
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
   * Render model row
   */
  const renderModelRow = (model: SDKModelInfo) => {
    const isDownloading = model.id in downloadingModels;
    const downloadProgress = downloadingModels[model.id] ?? 0;
    const isSelected = selectedModelId === model.id;
    const canSelect = model.isDownloaded || model.localPath;
    const modelInfoContent = (
      <>
        <Text
          style={[styles.modelName, isSelected && styles.modelNameSelected]}
        >
          {model.name}
        </Text>

        <View style={styles.modelMeta}>
          {getModelDownloadSizeBytes(model) > 0 && (
            <View style={styles.sizeTag}>
              <Icon
                name="server-outline"
                size={12}
                color={Colors.textSecondary}
              />
              <Text style={styles.sizeText}>
                {formatBytes(getModelDownloadSizeBytes(model))}
              </Text>
            </View>
          )}

          <View style={styles.badge}>
            <Text style={styles.badgeText}>
              {getModelFormatLabel(model.format)}
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
              <Text style={[styles.statusText, { color: Colors.statusGreen }]}>
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
      </>
    );

    return (
      <View
        key={model.id}
        style={[
          styles.modelRow,
          isLoadingModel && !isSelected && styles.dimmed,
        ]}
      >
        {canSelect ? (
          <TouchableOpacity
            style={styles.modelInfo}
            onPress={() => handleSelectModel(model)}
            disabled={isLoadingModel || isSelected}
            accessible={false}
          >
            {modelInfoContent}
          </TouchableOpacity>
        ) : (
          <View style={styles.modelInfo}>{modelInfoContent}</View>
        )}

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
              accessible={true}
              accessibilityLabel={`Select ${model.name}`}
              accessibilityRole="button"
            >
              <Text style={styles.selectButtonText}>Select</Text>
            </TouchableOpacity>
          ) : (
            // B-RN-3-002: Removed `disabled={isLoadingModel}` — concurrent
            // downloads are supported (each model has its own progress entry
            // in `downloadingModels`), so a load-in-progress on a different
            // model must not block downloads. Per-model `isDownloading` is
            // managed via `downloadingModels[model.id]`.
            <TouchableOpacity
              style={styles.downloadButton}
              onPress={() => handleDownloadModel(model)}
              disabled={downloadingModels[model.id] !== undefined}
              accessible={true}
              accessibilityLabel={`Download ${model.name}`}
              accessibilityRole="button"
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
        <ScrollView
          style={styles.content}
          contentContainerStyle={styles.contentContainer}
          showsVerticalScrollIndicator={false}
        >
          {isLoading ? (
            <View style={styles.loadingContainer}>
              <ActivityIndicator size="large" color={Colors.primaryBlue} />
              <Text style={styles.loadingText}>Loading models...</Text>
            </View>
          ) : (
            <>
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
  // B-RN-3-004: ensure the last model row's CTA button clears the
  // bottom tab bar so users on shorter devices don't have to overscroll
  // to reveal it.
  contentContainer: {
    paddingBottom: 80,
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
    ...StyleSheet.absoluteFill,
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
