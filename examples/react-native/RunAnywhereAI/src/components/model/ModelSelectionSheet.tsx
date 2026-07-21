/**
 * ModelSelectionSheet — model picker presented in the app bottom sheet.
 *
 * Design: a device-storage summary card, then models split into "On device"
 * (ready to use) and "Available" (downloadable) sections of rich rows — no
 * framework dropdown/accordion. Context-based filtering (LLM, STT, TTS, Voice,
 * VLM, RAG Embedding, RAG LLM) selects which models are shown.
 */
import React, {
  useCallback,
  useEffect,
  useMemo,
  useState,
  useSyncExternalStore,
} from 'react';
import {
  ActivityIndicator,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { BottomSheet, BottomSheetScrollView } from '../ui/BottomSheet';
import { Icon, useTheme } from '../../theme/system';
import {
  DEFAULT_INFERENCE_FRAMEWORK,
  getFrameworkColor,
  getFrameworkSystemIcon,
  getModelDownloadSizeBytes,
  getModelFormatLabel,
  getModelFrameworks,
  getPrimaryFramework,
} from '../../utils/modelDisplay';
import { RunAnywhere } from '@runanywhere/core';
import {
  InferenceFramework,
  ModelCategory,
  type ModelInfo as SDKModelInfo,
} from '@runanywhere/proto-ts/model_types';
import {
  getNpuCatalogSnapshot,
  subscribeNpuCatalog,
} from '../../services/NpuModelCatalog';
import { RAG_EMBEDDING_FRAMEWORKS } from '../../services/EmbeddingCatalogPolicy';
import { listVisibleCatalogModels } from '../../services/ModelRegistryQueries';

const downloadModelStreamHelper = RunAnywhere.downloadModelStream;

type StorageSnapshot = Awaited<ReturnType<typeof RunAnywhere.getStorageInfo>>;

// Opens tall (long model lists); drag up to near-full.
const SNAP_POINTS = ['60%', '92%'];

/**
 * Context for filtering models based on the current experience/modality.
 */
export enum ModelSelectionContext {
  LLM = 'llm',
  STT = 'stt',
  TTS = 'tts',
  Voice = 'voice',
  VAD = 'vad',
  VLM = 'vlm',
  RagEmbedding = 'ragEmbedding',
  RagLLM = 'ragLLM',
}

const getContextTitle = (context: ModelSelectionContext): string => {
  switch (context) {
    case ModelSelectionContext.LLM:
      return 'Select a model';
    case ModelSelectionContext.STT:
      return 'Select a speech model';
    case ModelSelectionContext.TTS:
      return 'Select a voice';
    case ModelSelectionContext.Voice:
      return 'Select a model';
    case ModelSelectionContext.VAD:
      return 'Select a VAD model';
    case ModelSelectionContext.VLM:
      return 'Select a vision model';
    case ModelSelectionContext.RagEmbedding:
      return 'Select an embedding model';
    case ModelSelectionContext.RagLLM:
      return 'Select a model';
  }
};

/** SDK category filter (proto `ModelCategory`); null = show all. */
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
      return null;
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

/** Framework restriction for a context; null = any framework. */
const getAllowedFrameworksForContext = (
  context: ModelSelectionContext
): ReadonlySet<InferenceFramework> | null => {
  switch (context) {
    case ModelSelectionContext.RagEmbedding:
      return RAG_EMBEDDING_FRAMEWORKS;
    case ModelSelectionContext.RagLLM:
      return new Set([
        InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      ]);
    default:
      return null;
  }
};

const isRAGContext = (context: ModelSelectionContext): boolean =>
  context === ModelSelectionContext.RagEmbedding ||
  context === ModelSelectionContext.RagLLM;

const isOnDevice = (model: SDKModelInfo): boolean =>
  Boolean(model.isDownloaded || model.localPath);

const formatBytes = (bytes: number): string => {
  if (!bytes || bytes <= 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`;
};

const modelSubtitle = (model: SDKModelInfo): string => {
  const size = getModelDownloadSizeBytes(model);
  const framework = RunAnywhere.formatFramework(
    getPrimaryFramework(model, DEFAULT_INFERENCE_FRAMEWORK)
  );
  return [
    size > 0 ? formatBytes(size) : null,
    getModelFormatLabel(model.format),
    framework,
  ]
    .filter(Boolean)
    .join('  ·  ');
};

interface ModelSelectionSheetProps {
  visible: boolean;
  context: ModelSelectionContext;
  /** Id of the model currently loaded/in use, so its row shows "In use". */
  activeModelId?: string | null;
  onClose: () => void;
  onModelSelected: (model: SDKModelInfo) => Promise<void>;
}

export const ModelSelectionSheet: React.FC<ModelSelectionSheetProps> = ({
  visible,
  context,
  activeModelId,
  onClose,
  onModelSelected,
}) => {
  const { colors, typography } = useTheme();
  const [models, setModels] = useState<SDKModelInfo[]>([]);
  const [storage, setStorage] = useState<StorageSnapshot | null>(null);
  const [downloading, setDownloading] = useState<Record<string, number>>({});
  const [isLoading, setIsLoading] = useState(true);
  const [loadingId, setLoadingId] = useState<string | null>(null);
  const [activeId, setActiveId] = useState<string | null>(null);
  // Model ids that have at least one compatible LoRA adapter in the catalog,
  // so their rows can show a "LoRA" tag. listCatalog is a catalog op (no loaded
  // model required), so it's safe to call here.
  const [loraModelIds, setLoraModelIds] = useState<Set<string>>(new Set());
  const npuCatalogSnapshot = useSyncExternalStore(
    subscribeNpuCatalog,
    getNpuCatalogSnapshot,
    getNpuCatalogSnapshot
  );

  const loadData = useCallback(async () => {
    setIsLoading(true);
    try {
      const [allModels, storageInfo, loraCatalog] = await Promise.all([
        listVisibleCatalogModels(npuCatalogSnapshot.registeredModelIds),
        RunAnywhere.getStorageInfo().catch(() => null),
        RunAnywhere.lora.listCatalog().catch(() => null),
      ]);
      setStorage(storageInfo);

      if (loraCatalog?.success) {
        const ids = new Set<string>();
        for (const entry of loraCatalog.entries) {
          entry.compatibleModels.forEach((id) => ids.add(id));
        }
        setLoraModelIds(ids);
      }

      const categoryFilter = getCategoryForContext(context);
      const allowedFrameworks = getAllowedFrameworksForContext(context);
      const filtered = categoryFilter
        ? allModels.filter((m) => {
            const categoryMatch =
              m.category === categoryFilter ||
              String(m.category).toLowerCase() ===
                String(categoryFilter).toLowerCase();
            if (!categoryMatch) return false;
            if (allowedFrameworks) {
              return getModelFrameworks(m).some((fw) =>
                allowedFrameworks.has(fw)
              );
            }
            return true;
          })
        : allModels;
      setModels(filtered);
    } catch (error) {
      console.error('[ModelSelectionSheet] load failed:', error);
    } finally {
      setIsLoading(false);
    }
  }, [context, npuCatalogSnapshot.registeredModelIds]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  useEffect(() => {
    if (visible) loadData();
  }, [visible, loadData]);

  useEffect(() => {
    setModels([]);
  }, [context]);

  // E2E hooks.
  useEffect(() => {
    const g = globalThis as typeof globalThis & {
      __testModels?: SDKModelInfo[];
      __testOnModelSelected?: (model: SDKModelInfo) => Promise<void>;
    };
    g.__testModels = models;
    g.__testOnModelSelected = onModelSelected;
  }, [models, onModelSelected]);

  const handleSheetClose = useCallback(() => {
    onClose();
  }, [onClose]);

  const handleSelect = useCallback(
    async (model: SDKModelInfo) => {
      if (!isOnDevice(model)) return;
      setLoadingId(model.id);
      try {
        await onModelSelected(model);
        setActiveId(model.id);
        if (isRAGContext(context)) onClose();
      } catch (error) {
        console.error('[ModelSelectionSheet] select failed:', error);
      } finally {
        setLoadingId(null);
      }
    },
    [context, onClose, onModelSelected]
  );

  const handleDownload = useCallback(
    async (model: SDKModelInfo) => {
      setDownloading((prev) => ({ ...prev, [model.id]: 0 }));
      try {
        const iter = downloadModelStreamHelper(model)[Symbol.asyncIterator]();
        let step = await iter.next();
        while (!step.done) {
          const p = step.value.stageProgress ?? 0;
          setDownloading((prev) => ({ ...prev, [model.id]: p }));
          step = await iter.next();
        }
        await loadData();
      } catch (error) {
        console.error('[ModelSelectionSheet] download failed:', error);
      } finally {
        setDownloading((prev) => {
          const next = { ...prev };
          delete next[model.id];
          return next;
        });
      }
    },
    [loadData]
  );

  const onDeviceModels = useMemo(() => models.filter(isOnDevice), [models]);
  const availableModels = useMemo(
    () => models.filter((m) => !isOnDevice(m)),
    [models]
  );

  const renderRow = (model: SDKModelInfo, ready: boolean) => {
    const progress = downloading[model.id];
    const isDownloading = progress !== undefined;
    const framework = getPrimaryFramework(model, DEFAULT_INFERENCE_FRAMEWORK);
    const frameworkColor = getFrameworkColor(framework);
    return (
      <TouchableOpacity
        key={model.id}
        style={styles.row}
        activeOpacity={0.7}
        disabled={isDownloading || loadingId === model.id}
        onPress={() =>
          ready ? handleSelect(model) : !isDownloading && handleDownload(model)
        }
      >
        <View style={[styles.tile, { backgroundColor: `${frameworkColor}18` }]}>
          <Icon
            name={getFrameworkSystemIcon(framework)}
            size={20}
            color={frameworkColor}
          />
        </View>
        <View style={styles.rowText}>
          <View style={styles.nameRow}>
            <Text
              style={[
                typography.titleMedium,
                styles.bold,
                styles.nameText,
                { color: colors.onSurface },
              ]}
              numberOfLines={1}
            >
              {model.name}
            </Text>
            {loraModelIds.has(model.id) && (
              <View
                style={[
                  styles.loraTag,
                  { backgroundColor: colors.tertiaryContainer },
                ]}
              >
                <Icon
                  name="sparkles"
                  size={11}
                  color={colors.onTertiaryContainer}
                />
                <Text
                  style={[
                    typography.labelSmall,
                    styles.bold,
                    { color: colors.onTertiaryContainer },
                  ]}
                >
                  LoRA
                </Text>
              </View>
            )}
          </View>
          <Text
            style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}
            numberOfLines={1}
          >
            {isDownloading
              ? `Downloading…  ${Math.round((progress ?? 0) * 100)}%`
              : modelSubtitle(model)}
          </Text>
          {isDownloading && (
            <View
              style={[styles.track, { backgroundColor: colors.surfaceVariant }]}
            >
              <View
                style={[
                  styles.trackFill,
                  {
                    backgroundColor: colors.primary,
                    width: `${Math.round((progress ?? 0) * 100)}%`,
                  },
                ]}
              />
            </View>
          )}
        </View>
        {ready ? (
          loadingId === model.id ? (
            <ActivityIndicator size="small" color={colors.primary} />
          ) : activeId === model.id || activeModelId === model.id ? (
            <View style={styles.inUse}>
              <Icon name="check" size={16} color={colors.primary} />
              <Text
                style={[
                  typography.labelLarge,
                  styles.bold,
                  { color: colors.primary },
                ]}
              >
                In use
              </Text>
            </View>
          ) : (
            <View style={[styles.usePill, { backgroundColor: colors.primary }]}>
              <Text
                style={[
                  typography.labelLarge,
                  styles.bold,
                  { color: colors.onPrimary },
                ]}
              >
                Use
              </Text>
            </View>
          )
        ) : (
          !isDownloading && (
            <Icon name="download" size={22} color={colors.primary} />
          )
        )}
      </TouchableOpacity>
    );
  };

  const renderSection = (title: string, list: SDKModelInfo[], ready: boolean) =>
    list.length > 0 && (
      <View style={styles.section}>
        <Text
          style={[
            styles.sectionLabel,
            typography.labelMedium,
            styles.bold,
            { color: colors.onSurfaceVariant },
          ]}
        >
          {title}
        </Text>
        <View
          style={[styles.card, { backgroundColor: colors.surfaceContainerHigh }]}
        >
          {list.map((m) => renderRow(m, ready))}
        </View>
      </View>
    );

  return (
    <BottomSheet
      visible={visible}
      onClose={handleSheetClose}
      snapPoints={SNAP_POINTS}
    >
      <View style={styles.header}>
        <Text
          style={[typography.titleLarge, styles.bold, { color: colors.onSurface }]}
        >
          {getContextTitle(context)}
        </Text>
      </View>

      <BottomSheetScrollView contentContainerStyle={styles.content}>
        {isLoading ? (
          <View style={styles.loading}>
            <ActivityIndicator color={colors.primary} />
            <Text
              style={[typography.bodyMedium, { color: colors.onSurfaceVariant }]}
            >
              Loading models…
            </Text>
          </View>
        ) : (
          <>
            <View
              style={[
                styles.storageCard,
                { backgroundColor: colors.primaryContainer },
              ]}
            >
              <View style={styles.storageTop}>
                <View
                  style={[styles.storageIcon, { backgroundColor: colors.surface }]}
                >
                  <Icon name="storageDevice" size={18} color={colors.primary} />
                </View>
                <Text
                  style={[
                    typography.labelMedium,
                    styles.bold,
                    styles.storageLabel,
                    { color: colors.onPrimaryContainer },
                  ]}
                >
                  Device storage
                </Text>
              </View>

              <View style={styles.storageStatRow}>
                <Text
                  style={[
                    typography.displaySmall,
                    styles.bold,
                    { color: colors.onPrimaryContainer },
                  ]}
                >
                  {formatBytes(storage?.device?.freeBytes ?? 0)}
                </Text>
                <Text
                  style={[
                    typography.titleMedium,
                    styles.italic,
                    { color: colors.onPrimaryContainer },
                  ]}
                >
                  free
                </Text>
                <View style={styles.flexSpacer} />
                <Text
                  style={[
                    typography.bodyMedium,
                    { color: colors.onPrimaryContainer },
                  ]}
                >
                  of {formatBytes(storage?.device?.totalBytes ?? 0)}
                </Text>
              </View>

              <View
                style={[styles.usageTrack, { backgroundColor: colors.surface }]}
              >
                <View
                  style={[
                    styles.usageFill,
                    {
                      backgroundColor: colors.primary,
                      width: `${Math.min(100, Math.max(0, storage?.device?.usedPercent ?? 0))}%`,
                    },
                  ]}
                />
              </View>

              <Text
                style={[
                  typography.bodySmall,
                  styles.italic,
                  { color: colors.onPrimaryContainer },
                ]}
              >
                {formatBytes(storage?.totalModelsBytes ?? 0)} in models  ·  {onDeviceModels.length} on device
              </Text>
            </View>

            {renderSection('On device', onDeviceModels, true)}
            {renderSection('Available', availableModels, false)}

            {models.length === 0 && (
              <Text
                style={[
                  typography.bodyMedium,
                  styles.empty,
                  { color: colors.onSurfaceVariant },
                ]}
              >
                No models available for this mode.
              </Text>
            )}
          </>
        )}
      </BottomSheetScrollView>
    </BottomSheet>
  );
};

const styles = StyleSheet.create({
  header: {
    paddingHorizontal: 20,
    paddingTop: 4,
    paddingBottom: 12,
  },
  content: {
    paddingHorizontal: 16,
    paddingBottom: 24,
    gap: 16,
  },
  loading: {
    paddingVertical: 48,
    alignItems: 'center',
    gap: 12,
  },
  storageCard: {
    borderRadius: 22,
    padding: 18,
    gap: 12,
  },
  storageTop: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  storageIcon: {
    width: 32,
    height: 32,
    borderRadius: 10,
    alignItems: 'center',
    justifyContent: 'center',
  },
  storageLabel: {
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  storageStatRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
    gap: 6,
  },
  flexSpacer: {
    flex: 1,
  },
  usageTrack: {
    height: 8,
    borderRadius: 999,
    overflow: 'hidden',
  },
  usageFill: {
    height: 8,
    borderRadius: 999,
  },
  usePill: {
    paddingHorizontal: 16,
    paddingVertical: 7,
    borderRadius: 999,
  },
  inUse: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  bold: {
    fontWeight: '700',
  },
  italic: {
    fontStyle: 'italic',
  },
  section: {
    gap: 8,
  },
  sectionLabel: {
    textTransform: 'uppercase',
    paddingHorizontal: 4,
  },
  card: {
    borderRadius: 16,
    overflow: 'hidden',
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 12,
    paddingVertical: 12,
  },
  tile: {
    width: 40,
    height: 40,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  rowText: {
    flex: 1,
    gap: 2,
  },
  nameRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  nameText: {
    flexShrink: 1,
  },
  loraTag: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
    paddingHorizontal: 7,
    paddingVertical: 2,
    borderRadius: 999,
  },
  track: {
    height: 3,
    borderRadius: 999,
    marginTop: 6,
    overflow: 'hidden',
  },
  trackFill: {
    height: 3,
    borderRadius: 999,
  },
  empty: {
    textAlign: 'center',
    paddingVertical: 32,
  },
});

export default ModelSelectionSheet;
