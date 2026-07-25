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
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import Slider from '@react-native-community/slider';
import Icon from 'react-native-vector-icons/Ionicons';
import { BottomSheet, BottomSheetScrollView } from '../ui/BottomSheet';
import { RunAnywhere } from '@runanywhere/core';
import {
  LoRARemoveRequest,
  LoraAdapterCatalogQuery,
  type LoRAAdapterInfo,
  type LoRAState,
  type LoraAdapterCatalogEntry,
} from '@runanywhere/proto-ts/lora_options';
import {
  typography,
  useTheme,
  useThemedStyles,
  type ColorScheme,
} from '../../theme/system';

interface LoRASheetProps {
  visible: boolean;
  modelId: string | null;
  onClose: () => void;
  /** Lets the parent (ChatScreen badge) track the loaded-adapter count. */
  onAdaptersChanged?: (adapters: LoRAAdapterInfo[]) => void;
}

const LORA_SNAP_POINTS = ['75%'];

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
  visible,
  modelId,
  onClose,
  onAdaptersChanged,
}) => {
  const { colors } = useTheme();
  const styles = useThemedStyles(createStyles);
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
    // LoRA `list()` is a loaded-service operation: it requires an LLM model to
    // be loaded. Calling it with no model fails with "LoRA service is not
    // loaded" and emits a spurious lora.failed/-230 telemetry event. Guard both
    // catalog + list on modelId so we never touch the service before a load.
    if (!modelId) {
      setAvailableAdapters([]);
      updateLoaded([]);
      return;
    }
    try {
      const result = await RunAnywhere.lora.queryCatalog(
        LoraAdapterCatalogQuery.fromPartial({ modelId })
      );
      if (!result.success) {
        throw new Error(result.errorMessage || 'LoRA catalog query failed');
      }
      setAvailableAdapters(result.entries);
      handleLoraState(await RunAnywhere.lora.list());
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }, [modelId, handleLoraState, updateLoaded]);

  // Only refresh once the user actually opens the sheet — the sheet is mounted
  // (hidden) on the chat screen at startup, so an unconditional mount-refresh
  // would hit the LoRA service before any model is loaded.
  useEffect(() => {
    if (visible) refresh();
  }, [visible, refresh]);

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
        const result = await RunAnywhere.lora.applyCatalogAdapter(entry, {
          localPath,
          scale,
        });
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
    <BottomSheet
      visible={visible}
      onClose={onClose}
      snapPoints={LORA_SNAP_POINTS}
    >
      <View style={styles.sheetHeader}>
        <Text style={styles.title}>LoRA Adapters</Text>
      </View>

      <BottomSheetScrollView contentContainerStyle={styles.content}>
        {error && (
          <View style={styles.errorBox}>
            <Icon
              name="alert-circle"
              size={16}
              color={colors.onErrorContainer}
            />
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
                          color={colors.success}
                        />
                        <Text style={styles.badgeAppliedText}>Applied</Text>
                      </View>
                    ) : downloaded ? (
                      <View style={styles.badgeDownloaded}>
                        <Icon
                          name="checkmark-circle-outline"
                          size={14}
                          color={colors.primary}
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
                          minimumTrackTintColor={colors.primary}
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
                            color={colors.onPrimary}
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
                      color={colors.outline}
                    />
                  </TouchableOpacity>
                </View>
              </View>
            ))}
            <TouchableOpacity
              style={styles.clearAllRow}
              onPress={handleClearAll}
            >
              <Icon name="trash-outline" size={16} color={colors.error} />
              <Text style={styles.clearAllText}>Clear All Adapters</Text>
            </TouchableOpacity>
          </View>
        )}

        {availableAdapters.length === 0 && loadedAdapters.length === 0 && (
          <View style={styles.emptyState}>
            <Icon name="sparkles" size={32} color={colors.primary} />
            <Text style={styles.emptyText}>
              No LoRA adapters available for this model.
            </Text>
          </View>
        )}
      </BottomSheetScrollView>
    </BottomSheet>
  );
};

const createStyles = (colors: ColorScheme) =>
  StyleSheet.create({
    sheetHeader: {
      paddingHorizontal: 16,
      paddingTop: 6,
      paddingBottom: 10,
      alignItems: 'center',
    },
    title: {
      ...typography.titleLarge,
      color: colors.onSurface,
    },
    content: {
      padding: 16,
    },
    errorBox: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 6,
      backgroundColor: colors.errorContainer,
      borderRadius: 10,
      padding: 12,
      marginBottom: 10,
    },
    errorText: {
      ...typography.bodySmall,
      color: colors.onErrorContainer,
      flex: 1,
    },
    section: {
      marginBottom: 20,
    },
    sectionHeader: {
      ...typography.labelMedium,
      color: colors.onSurfaceVariant,
      marginBottom: 6,
    },
    sectionFooter: {
      ...typography.labelSmall,
      color: colors.outline,
      marginTop: 6,
    },
    card: {
      backgroundColor: colors.surfaceContainer,
      borderRadius: 10,
      padding: 12,
      marginBottom: 6,
    },
    cardHeader: {
      flexDirection: 'row',
      alignItems: 'flex-start',
      justifyContent: 'space-between',
    },
    cardInfo: {
      flex: 1,
      marginRight: 6,
    },
    adapterName: {
      ...typography.bodyMedium,
      color: colors.onSurface,
    },
    adapterDescription: {
      ...typography.bodySmall,
      color: colors.onSurfaceVariant,
      marginTop: 2,
    },
    adapterSize: {
      ...typography.labelSmall,
      color: colors.outline,
      marginTop: 2,
    },
    loadedMetaRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 6,
      marginTop: 2,
    },
    badgeApplied: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 4,
    },
    badgeAppliedText: {
      ...typography.labelSmall,
      color: colors.success,
    },
    badgeDownloaded: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 4,
    },
    badgeDownloadedText: {
      ...typography.labelSmall,
      color: colors.primary,
    },
    applyRow: {
      flexDirection: 'row',
      alignItems: 'flex-end',
      gap: 10,
      marginTop: 6,
    },
    sliderColumn: {
      flex: 1,
    },
    scaleLabel: {
      ...typography.labelSmall,
      color: colors.onSurfaceVariant,
    },
    applyButton: {
      backgroundColor: colors.primary,
      borderRadius: 10,
      paddingHorizontal: 16,
      paddingVertical: 8,
      minWidth: 92,
      alignItems: 'center',
    },
    applyButtonDisabled: {
      opacity: 0.6,
    },
    applyButtonText: {
      ...typography.labelMedium,
      color: colors.onPrimary,
    },
    clearAllRow: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 6,
      paddingVertical: 12,
    },
    clearAllText: {
      ...typography.bodyMedium,
      color: colors.error,
    },
    emptyState: {
      alignItems: 'center',
      gap: 10,
      paddingVertical: 40,
    },
    emptyText: {
      ...typography.bodyLarge,
      color: colors.onSurfaceVariant,
      textAlign: 'center',
    },
  });
