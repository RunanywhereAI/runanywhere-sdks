import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  RefreshControl,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { FlashList } from '@shopify/flash-list';
import {
  RunAnywhere,
  LLMFramework,
  type ModelInfo as SDKModelInfo,
} from '@runanywhere/core';
import { useTheme } from '../theme';
import { Typography } from '../theme/typography';
import { BorderRadius, Padding, Spacing } from '../theme/spacing';
import type { ThemeColors } from '../theme/colors';
import { AppIcon } from '../components/common/AppIcon';

type FrameworkStyle = { label: string; color: (c: ThemeColors) => string };

const frameworkStyles: Partial<Record<string, FrameworkStyle>> = {
  [LLMFramework.LlamaCpp]: {
    label: 'llama.cpp',
    color: (c) => c.frameworkLlamaCpp,
  },
  [LLMFramework.ONNX]: { label: 'ONNX', color: (c) => c.frameworkONNX },
  [LLMFramework.Genie]: { label: 'Genie', color: (c) => c.primary },
  [LLMFramework.WhisperKit]: {
    label: 'WhisperKit',
    color: (c) => c.frameworkWhisperKit,
  },
  [LLMFramework.PiperTTS]: {
    label: 'Piper',
    color: (c) => c.frameworkPiperTTS,
  },
};

function formatBytes(bytes: number): string {
  if (!bytes || bytes <= 0) return '—';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${(bytes / Math.pow(k, i)).toFixed(1)} ${sizes[i]}`;
}

type RowState = 'idle' | 'downloading' | 'ready' | 'deleting';

type ModelRowProps = {
  model: SDKModelInfo;
  downloadedIds: Set<string>;
  progress: number | undefined;
  rowState: RowState;
  onDownload: (m: SDKModelInfo) => void;
  onDelete: (m: SDKModelInfo) => void;
};

const ModelRow: React.FC<ModelRowProps> = React.memo(
  ({ model, downloadedIds, progress, rowState, onDownload, onDelete }) => {
    const { colors } = useTheme();
    const isDownloaded = downloadedIds.has(model.id);
    const frameworkKey = String(
      model.preferredFramework ?? model.compatibleFrameworks?.[0] ?? ''
    );
    const fwStyle = frameworkStyles[frameworkKey];
    const fwColor = fwStyle?.color(colors) ?? colors.primary;
    const fwLabel = fwStyle?.label ?? frameworkKey;

    return (
      <View
        style={[
          styles.row,
          {
            backgroundColor: colors.surface,
            borderColor: colors.border,
          },
        ]}
      >
        <View style={styles.rowHeader}>
          <Text
            style={[Typography.headline, { color: colors.text, flex: 1 }]}
            numberOfLines={1}
          >
            {model.name}
          </Text>
          <View
            style={[
              styles.badge,
              { backgroundColor: colors.primarySoft, borderColor: fwColor },
            ]}
          >
            <Text style={[styles.badgeText, { color: fwColor }]}>{fwLabel}</Text>
          </View>
        </View>

        <Text
          style={[Typography.caption, { color: colors.textSecondary }]}
          numberOfLines={1}
        >
          {formatBytes(model.downloadSize ?? model.memoryRequired ?? 0)}
          {model.category ? ` · ${String(model.category)}` : ''}
        </Text>

        {rowState === 'downloading' ? (
          <View style={styles.progressWrap}>
            <View
              style={[
                styles.progressTrack,
                { backgroundColor: colors.surfaceAlt },
              ]}
            >
              <View
                style={[
                  styles.progressFill,
                  {
                    backgroundColor: colors.primary,
                    width: `${Math.round((progress ?? 0) * 100)}%`,
                  },
                ]}
              />
            </View>
            <Text style={[Typography.caption2, { color: colors.textSecondary }]}>
              {Math.round((progress ?? 0) * 100)}%
            </Text>
          </View>
        ) : (
          <View style={styles.actionRow}>
            {isDownloaded ? (
              <TouchableOpacity
                onPress={() => onDelete(model)}
                disabled={rowState === 'deleting'}
                style={[
                  styles.secondaryButton,
                  { borderColor: colors.border },
                ]}
              >
                {rowState === 'deleting' ? (
                  <ActivityIndicator size="small" color={colors.text} />
                ) : (
                  <>
                    <AppIcon
                      name="trash-outline"
                      size={16}
                      color={colors.error}
                    />
                    <Text
                      style={[Typography.footnote, { color: colors.error }]}
                    >
                      Delete
                    </Text>
                  </>
                )}
              </TouchableOpacity>
            ) : (
              <TouchableOpacity
                onPress={() => onDownload(model)}
                style={[
                  styles.primaryButton,
                  { backgroundColor: colors.primary },
                ]}
              >
                <AppIcon
                  name="cloud-download-outline"
                  size={16}
                  color={colors.onPrimary}
                />
                <Text
                  style={[Typography.footnote, { color: colors.onPrimary }]}
                >
                  Download
                </Text>
              </TouchableOpacity>
            )}
          </View>
        )}
      </View>
    );
  }
);

ModelRow.displayName = 'ModelRow';

const ModelsScreen: React.FC = () => {
  const { colors } = useTheme();
  const [models, setModels] = useState<SDKModelInfo[]>([]);
  const [downloadedIds, setDownloadedIds] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [progresses, setProgresses] = useState<Record<string, number>>({});
  const [deleting, setDeleting] = useState<Set<string>>(new Set());

  const loadModels = useCallback(async () => {
    try {
      const [all, downloaded] = await Promise.all([
        RunAnywhere.getAvailableModels(),
        RunAnywhere.getDownloadedModels(),
      ]);
      setModels(all);
      setDownloadedIds(new Set(downloaded.map((m) => m.id)));
    } catch (err) {
      console.error('[ModelsScreen] load failed', err);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    loadModels();
  }, [loadModels]);

  const onRefresh = useCallback(() => {
    setRefreshing(true);
    loadModels();
  }, [loadModels]);

  const handleDownload = useCallback(
    async (model: SDKModelInfo) => {
      setProgresses((p) => ({ ...p, [model.id]: 0 }));
      try {
        await RunAnywhere.downloadModel(model.id, (progress) => {
          setProgresses((p) => ({ ...p, [model.id]: progress.progress ?? 0 }));
        });
        await loadModels();
      } catch (err) {
        console.error('[ModelsScreen] download failed', err);
        Alert.alert('Download failed', (err as Error).message);
      } finally {
        setProgresses((p) => {
          const next = { ...p };
          delete next[model.id];
          return next;
        });
      }
    },
    [loadModels]
  );

  const handleDelete = useCallback(
    (model: SDKModelInfo) => {
      Alert.alert(
        'Delete model?',
        `Remove ${model.name} from device?`,
        [
          { text: 'Cancel', style: 'cancel' },
          {
            text: 'Delete',
            style: 'destructive',
            onPress: async () => {
              setDeleting((s) => new Set(s).add(model.id));
              try {
                await RunAnywhere.deleteModel(model.id);
                await loadModels();
              } catch (err) {
                Alert.alert('Delete failed', (err as Error).message);
              } finally {
                setDeleting((s) => {
                  const next = new Set(s);
                  next.delete(model.id);
                  return next;
                });
              }
            },
          },
        ],
        { cancelable: true }
      );
    },
    [loadModels]
  );

  const renderItem = useCallback(
    ({ item }: { item: SDKModelInfo }) => {
      const progress = progresses[item.id];
      const isDeleting = deleting.has(item.id);
      const rowState: RowState =
        progress !== undefined
          ? 'downloading'
          : isDeleting
          ? 'deleting'
          : downloadedIds.has(item.id)
          ? 'ready'
          : 'idle';
      return (
        <ModelRow
          model={item}
          downloadedIds={downloadedIds}
          progress={progress}
          rowState={rowState}
          onDownload={handleDownload}
          onDelete={handleDelete}
        />
      );
    },
    [progresses, deleting, downloadedIds, handleDownload, handleDelete]
  );

  const data = useMemo(() => models, [models]);

  if (loading) {
    return (
      <View
        style={[styles.centered, { backgroundColor: colors.background }]}
      >
        <ActivityIndicator color={colors.primary} />
      </View>
    );
  }

  return (
    <SafeAreaView
      edges={['bottom']}
      style={[styles.container, { backgroundColor: colors.background }]}
    >
      <FlashList
        data={data}
        keyExtractor={(item) => item.id}
        renderItem={renderItem}
        contentContainerStyle={styles.listContent}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={onRefresh}
            tintColor={colors.primary}
          />
        }
        ListEmptyComponent={
          <View style={styles.empty}>
            <Text style={[Typography.body, { color: colors.textSecondary }]}>
              No models registered.
            </Text>
          </View>
        }
      />
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  centered: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  listContent: {
    padding: Padding.padding16,
    paddingBottom: Spacing.xxxLarge,
  },
  row: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: BorderRadius.large,
    padding: Padding.padding16,
    marginBottom: Spacing.mediumLarge,
    gap: Spacing.small,
  },
  rowHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.small,
  },
  badge: {
    paddingHorizontal: Spacing.small,
    paddingVertical: 3,
    borderRadius: BorderRadius.small,
    borderWidth: StyleSheet.hairlineWidth,
  },
  badgeText: {
    fontSize: 11,
    fontWeight: '600',
  },
  progressWrap: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.small,
    marginTop: Spacing.xSmall,
  },
  progressTrack: {
    flex: 1,
    height: 6,
    borderRadius: 3,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    borderRadius: 3,
  },
  actionRow: {
    flexDirection: 'row',
    gap: Spacing.small,
    marginTop: Spacing.xSmall,
  },
  primaryButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: Padding.padding14,
    paddingVertical: Spacing.small,
    borderRadius: BorderRadius.medium,
  },
  secondaryButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: Padding.padding14,
    paddingVertical: Spacing.small,
    borderRadius: BorderRadius.medium,
    borderWidth: StyleSheet.hairlineWidth,
  },
  empty: {
    alignItems: 'center',
    padding: Padding.padding24,
  },
});

export default ModelsScreen;
