/**
 * LoRASheet - LoRA adapter management sheet for the Chat screen.
 *
 * RN equivalent of iOS `LoRAManagementSheetView` (ChatLoRASheets.swift):
 * lists catalog adapters compatible with the loaded model (download/apply
 * with a scale slider) and currently-loaded adapters (remove / clear all).
 * All calls go through the canonical `RunAnywhere.lora.*` namespace,
 * mirroring iOS LLMViewModel's LoRA call sequences.
 *
 * MVP scope: the iOS file-picker import flow (`importAndLoadLoraAdapter` /
 * `markImportCompleted`) is intentionally omitted — the seeded catalog
 * adapter covers the demo.
 */

import React, { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import Slider from '@react-native-community/slider';
import Icon from 'react-native-vector-icons/Ionicons';
import { SafeAreaView } from 'react-native-safe-area-context';
import { RunAnywhere } from '@runanywhere/core';
import {
  LoRAAdapterConfig,
  LoRAApplyRequest,
  LoRARemoveRequest,
  LoraAdapterCatalogQuery,
  type LoRAAdapterInfo,
  type LoRAState,
  type LoraAdapterCatalogEntry,
} from '@runanywhere/proto-ts/lora_options';
import { Colors } from '../../theme/colors';
import { Typography } from '../../theme/typography';
import { Spacing, Padding, BorderRadius } from '../../theme/spacing';

interface LoRASheetProps {
  modelId: string | null;
  onClose: () => void;
  /** Lets the parent (ChatScreen badge) track the loaded-adapter count. */
  onAdaptersChanged?: (adapters: LoRAAdapterInfo[]) => void;
}

function formatBytes(bytes: number): string {
  if (bytes >= 1_000_000) return `${(bytes / 1_000_000).toFixed(1)} MB`;
  if (bytes >= 1_000) return `${(bytes / 1_000).toFixed(1)} KB`;
  return `${bytes} B`;
}

function lastPathComponent(path: string): string {
  const idx = path.lastIndexOf('/');
  return idx >= 0 ? path.slice(idx + 1) : path;
}

export const LoRASheet: React.FC<LoRASheetProps> = ({
  modelId,
  onClose,
  onAdaptersChanged,
}) => {
  const [availableAdapters, setAvailableAdapters] = useState<
    LoraAdapterCatalogEntry[]
  >([]);
  const [loadedAdapters, setLoadedAdapters] = useState<LoRAAdapterInfo[]>([]);
  const [scales, setScales] = useState<Record<string, number>>({});
  const [isLoadingLoRA, setIsLoadingLoRA] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const updateLoaded = useCallback(
    (adapters: LoRAAdapterInfo[]) => {
      setLoadedAdapters(adapters);
      onAdaptersChanged?.(adapters);
    },
    [onAdaptersChanged]
  );

  /** Mirrors iOS LLMViewModel.handleLoraState. */
  const handleLoraState = useCallback(
    (state: LoRAState) => {
      if (state.errorMessage) {
        setError(state.errorMessage);
        return;
      }
      updateLoaded(state.loadedAdapters);
    },
    [updateLoaded]
  );

  /** Mirrors iOS refreshAvailableAdapters + refreshLoraAdapters. */
  const refresh = useCallback(async () => {
    setError(null);
    try {
      if (modelId) {
        const result = await RunAnywhere.lora.queryCatalog(
          LoraAdapterCatalogQuery.fromPartial({ modelId })
        );
        if (!result.success) {
          throw new Error(result.errorMessage || 'LoRA catalog query failed');
        }
        setAvailableAdapters(result.entries);
      } else {
        setAvailableAdapters([]);
      }
      handleLoraState(await RunAnywhere.lora.list());
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }, [modelId, handleLoraState]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  /** Mirrors iOS downloadAndLoadAdapter -> loadLoraAdapter. */
  const handleDownloadAndApply = useCallback(
    async (entry: LoraAdapterCatalogEntry) => {
      setIsLoadingLoRA(true);
      setError(null);
      try {
        const scale = scales[entry.id] ?? entry.defaultScale;
        const localPath =
          entry.isDownloaded && entry.localPath
            ? entry.localPath
            : await RunAnywhere.lora.download(entry);
        const result = await RunAnywhere.lora.apply(
          LoRAApplyRequest.fromPartial({
            adapters: [
              LoRAAdapterConfig.fromPartial({
                adapterPath: localPath,
                adapterId: entry.id,
                scale,
              }),
            ],
          })
        );
        if (!result.success) {
          throw new Error(result.errorMessage || 'LoRA apply failed');
        }
        updateLoaded(result.adapters);
        await refresh();
      } catch (err) {
        setError(err instanceof Error ? err.message : String(err));
      } finally {
        setIsLoadingLoRA(false);
      }
    },
    [scales, updateLoaded, refresh]
  );

  /** Mirrors iOS removeLoraAdapter(path:). */
  const handleRemove = useCallback(
    async (path: string) => {
      try {
        handleLoraState(
          await RunAnywhere.lora.remove(
            LoRARemoveRequest.fromPartial({ adapterPaths: [path] })
          )
        );
      } catch (err) {
        setError(err instanceof Error ? err.message : String(err));
      }
    },
    [handleLoraState]
  );

  /** Mirrors iOS clearLoraAdapters. */
  const handleClearAll = useCallback(async () => {
    try {
      handleLoraState(
        await RunAnywhere.lora.remove(
          LoRARemoveRequest.fromPartial({ clearAll: true })
        )
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }, [handleLoraState]);

  const isApplied = useCallback(
    (entry: LoraAdapterCatalogEntry) =>
      loadedAdapters.some(
        (adapter) =>
          adapter.adapterId === entry.id ||
          (entry.localPath != null && adapter.adapterPath === entry.localPath)
      ),
    [loadedAdapters]
  );

  return (
    <SafeAreaView style={styles.container} edges={['top', 'bottom']}>
      <View style={styles.header}>
        <Text style={styles.title}>LoRA Adapters</Text>
        <TouchableOpacity onPress={onClose} style={styles.doneButton}>
          <Text style={styles.doneText}>Done</Text>
        </TouchableOpacity>
      </View>

      <ScrollView contentContainerStyle={styles.content}>
        {error && (
          <View style={styles.errorBox}>
            <Icon name="alert-circle" size={16} color={Colors.primaryRed} />
            <Text style={styles.errorText}>{error}</Text>
          </View>
        )}

        {availableAdapters.length > 0 && (
          <View style={styles.section}>
            <Text style={styles.sectionHeader}>AVAILABLE FOR THIS MODEL</Text>
            {availableAdapters.map((entry) => {
              const applied = isApplied(entry);
              const downloaded = Boolean(entry.isDownloaded && entry.localPath);
              const scale = scales[entry.id] ?? entry.defaultScale;
              return (
                <View key={entry.id} style={styles.card}>
                  <View style={styles.cardHeader}>
                    <View style={styles.cardInfo}>
                      <Text style={styles.adapterName}>{entry.name}</Text>
                      <Text style={styles.adapterDescription}>
                        {entry.description}
                      </Text>
                      <Text style={styles.adapterSize}>
                        {formatBytes(entry.sizeBytes)}
                      </Text>
                    </View>
                    {applied ? (
                      <View style={styles.badgeApplied}>
                        <Icon
                          name="checkmark-circle"
                          size={14}
                          color={Colors.primaryGreen}
                        />
                        <Text style={styles.badgeAppliedText}>Applied</Text>
                      </View>
                    ) : downloaded ? (
                      <View style={styles.badgeDownloaded}>
                        <Icon
                          name="checkmark-circle-outline"
                          size={14}
                          color={Colors.primaryBlue}
                        />
                        <Text style={styles.badgeDownloadedText}>
                          Downloaded
                        </Text>
                      </View>
                    ) : null}
                  </View>

                  {!applied && (
                    <View style={styles.applyRow}>
                      <View style={styles.sliderColumn}>
                        <Text style={styles.scaleLabel}>
                          Scale: {scale.toFixed(1)}
                        </Text>
                        <Slider
                          minimumValue={0}
                          maximumValue={2}
                          step={0.1}
                          value={scale}
                          minimumTrackTintColor={Colors.primaryPurple}
                          onValueChange={(value: number) =>
                            setScales((prev) => ({
                              ...prev,
                              [entry.id]: value,
                            }))
                          }
                        />
                      </View>
                      <TouchableOpacity
                        style={[
                          styles.applyButton,
                          isLoadingLoRA && styles.applyButtonDisabled,
                        ]}
                        disabled={isLoadingLoRA}
                        onPress={() => handleDownloadAndApply(entry)}
                      >
                        {isLoadingLoRA ? (
                          <ActivityIndicator
                            size="small"
                            color={Colors.textWhite}
                          />
                        ) : (
                          <Text style={styles.applyButtonText}>
                            {downloaded ? 'Apply' : 'Download'}
                          </Text>
                        )}
                      </TouchableOpacity>
                    </View>
                  )}
                </View>
              );
            })}
            <Text style={styles.sectionFooter}>
              Downloaded adapters are stored locally.
            </Text>
          </View>
        )}

        {loadedAdapters.length > 0 && (
          <View style={styles.section}>
            <Text style={styles.sectionHeader}>LOADED ADAPTERS</Text>
            {loadedAdapters.map((adapter) => (
              <View key={adapter.adapterPath} style={styles.card}>
                <View style={styles.cardHeader}>
                  <View style={styles.cardInfo}>
                    <Text style={styles.adapterName} numberOfLines={1}>
                      {lastPathComponent(adapter.adapterPath)}
                    </Text>
                    <View style={styles.loadedMetaRow}>
                      <Text style={styles.adapterSize}>
                        Scale: {adapter.scale.toFixed(1)}
                      </Text>
                      {adapter.applied && (
                        <Text style={styles.badgeAppliedText}>Applied</Text>
                      )}
                    </View>
                  </View>
                  <TouchableOpacity
                    onPress={() => handleRemove(adapter.adapterPath)}
                  >
                    <Icon
                      name="close-circle"
                      size={22}
                      color={Colors.textTertiary}
                    />
                  </TouchableOpacity>
                </View>
              </View>
            ))}
            <TouchableOpacity
              style={styles.clearAllRow}
              onPress={handleClearAll}
            >
              <Icon name="trash-outline" size={16} color={Colors.primaryRed} />
              <Text style={styles.clearAllText}>Clear All Adapters</Text>
            </TouchableOpacity>
          </View>
        )}

        {availableAdapters.length === 0 && loadedAdapters.length === 0 && (
          <View style={styles.emptyState}>
            <Icon name="sparkles" size={32} color={Colors.primaryPurple} />
            <Text style={styles.emptyText}>
              No LoRA adapters available for this model.
            </Text>
          </View>
        )}
      </ScrollView>
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
    ...Typography.title3,
    color: Colors.textPrimary,
  },
  doneButton: {
    padding: Spacing.small,
  },
  doneText: {
    ...Typography.headline,
    color: Colors.primaryBlue,
  },
  content: {
    padding: Padding.padding16,
  },
  errorBox: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.small,
    backgroundColor: Colors.badgeRed,
    borderRadius: BorderRadius.medium,
    padding: Padding.padding12,
    marginBottom: Spacing.medium,
  },
  errorText: {
    ...Typography.caption,
    color: Colors.primaryRed,
    flex: 1,
  },
  section: {
    marginBottom: Spacing.xLarge,
  },
  sectionHeader: {
    ...Typography.caption,
    color: Colors.textSecondary,
    marginBottom: Spacing.small,
  },
  sectionFooter: {
    ...Typography.caption2,
    color: Colors.textTertiary,
    marginTop: Spacing.small,
  },
  card: {
    backgroundColor: Colors.backgroundSecondary,
    borderRadius: BorderRadius.medium,
    padding: Padding.padding12,
    marginBottom: Spacing.small,
  },
  cardHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
  },
  cardInfo: {
    flex: 1,
    marginRight: Spacing.small,
  },
  adapterName: {
    ...Typography.subheadline,
    color: Colors.textPrimary,
  },
  adapterDescription: {
    ...Typography.caption,
    color: Colors.textSecondary,
    marginTop: 2,
  },
  adapterSize: {
    ...Typography.caption2,
    color: Colors.textTertiary,
    marginTop: 2,
  },
  loadedMetaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.small,
    marginTop: 2,
  },
  badgeApplied: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  badgeAppliedText: {
    ...Typography.caption2,
    color: Colors.primaryGreen,
  },
  badgeDownloaded: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  badgeDownloadedText: {
    ...Typography.caption2,
    color: Colors.primaryBlue,
  },
  applyRow: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: Spacing.medium,
    marginTop: Spacing.small,
  },
  sliderColumn: {
    flex: 1,
  },
  scaleLabel: {
    ...Typography.caption2,
    color: Colors.textSecondary,
  },
  applyButton: {
    backgroundColor: Colors.primaryPurple,
    borderRadius: BorderRadius.medium,
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding8,
    minWidth: 92,
    alignItems: 'center',
  },
  applyButtonDisabled: {
    opacity: 0.6,
  },
  applyButtonText: {
    ...Typography.caption,
    color: Colors.textWhite,
    fontWeight: '600',
  },
  clearAllRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: Spacing.small,
    paddingVertical: Padding.padding12,
  },
  clearAllText: {
    ...Typography.subheadline,
    color: Colors.primaryRed,
  },
  emptyState: {
    alignItems: 'center',
    gap: Spacing.medium,
    paddingVertical: Padding.padding40,
  },
  emptyText: {
    ...Typography.body,
    color: Colors.textSecondary,
    textAlign: 'center',
  },
});
