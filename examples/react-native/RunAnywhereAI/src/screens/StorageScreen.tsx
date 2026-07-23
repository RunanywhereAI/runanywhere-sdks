import React, { useCallback, useEffect, useState } from 'react';
import {
  Alert,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { SafeAreaView } from 'react-native-safe-area-context';
import { RunAnywhere } from '@runanywhere/core';
import type { StorageInfo } from '@runanywhere/proto-ts/storage_types';
import type { ModelInfo } from '@runanywhere/proto-ts/model_types';
import {
  typography,
  useTheme,
  useThemedStyles,
  type ColorScheme,
} from '../theme/system';
import {
  DEFAULT_INFERENCE_FRAMEWORK,
  getFrameworkColor,
  getFrameworkIcon,
  getModelDownloadSizeBytes,
  getPrimaryFramework,
} from '../utils/modelDisplay';
import { listDownloadedCatalogModels } from '../services/ModelRegistryQueries';

function formatBytes(bytes: number): string {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const index = Math.min(
    units.length - 1,
    Math.floor(Math.log(bytes) / Math.log(1024))
  );
  return `${(bytes / Math.pow(1024, index)).toFixed(index === 0 ? 0 : 1)} ${
    units[index]
  }`;
}

export const StorageScreen: React.FC = () => {
  const { colors } = useTheme();
  const styles = useThemedStyles(createStyles);
  const [storageInfo, setStorageInfo] = useState<StorageInfo | null>(null);
  const [downloadedModels, setDownloadedModels] = useState<ModelInfo[]>([]);
  const [isRefreshing, setIsRefreshing] = useState(false);

  const refresh = useCallback(async () => {
    setIsRefreshing(true);
    try {
      const [storage, models] = await Promise.all([
        RunAnywhere.getStorageInfo(),
        listDownloadedCatalogModels(),
      ]);
      setStorageInfo(storage);
      setDownloadedModels(models);
    } finally {
      setIsRefreshing(false);
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const clearCache = async () => {
    await RunAnywhere.clearCache();
    await refresh();
  };

  const cleanTempFiles = async () => {
    await RunAnywhere.cleanTempFiles();
    await refresh();
  };

  const deleteModel = (model: ModelInfo) => {
    Alert.alert('Delete Model', `Delete ${model.name || model.id}?`, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: () => {
          void (async () => {
            await RunAnywhere.deleteModel(model.id);
            await refresh();
          })();
        },
      },
    ]);
  };

  const app = storageInfo?.app;
  const device = storageInfo?.device;

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>Storage</Text>
        <TouchableOpacity onPress={refresh} disabled={isRefreshing}>
          <Icon
            name="refresh"
            size={22}
            color={isRefreshing ? colors.outline : colors.primary}
          />
        </TouchableOpacity>
      </View>

      <ScrollView
        style={styles.content}
        contentContainerStyle={styles.contentInner}
      >
        <View style={styles.section}>
          <StorageRow label="App" value={formatBytes(app?.totalBytes ?? 0)} />
          <StorageRow
            label="Documents"
            value={formatBytes(app?.documentsBytes ?? 0)}
          />
          <StorageRow label="Cache" value={formatBytes(app?.cacheBytes ?? 0)} />
          <StorageRow
            label="Models"
            value={formatBytes(storageInfo?.totalModelsBytes ?? 0)}
          />
          <StorageRow
            label="Free"
            value={formatBytes(device?.freeBytes ?? 0)}
          />
        </View>

        <View style={styles.actionRow}>
          <TouchableOpacity style={styles.actionButton} onPress={clearCache}>
            <Icon name="trash-outline" size={18} color={colors.tertiary} />
            <Text style={styles.actionButtonText}>Clear Cache</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={styles.actionButton}
            onPress={cleanTempFiles}
          >
            <Icon name="file-tray-outline" size={18} color={colors.primary} />
            <Text style={styles.actionButtonText}>Clean Temp</Text>
          </TouchableOpacity>
        </View>

        <Text style={styles.sectionTitle}>Downloaded Models</Text>
        <View style={styles.section}>
          {downloadedModels.length === 0 ? (
            <Text style={styles.emptyText}>No downloaded models.</Text>
          ) : (
            downloadedModels.map((model) => {
              const framework = getPrimaryFramework(
                model,
                DEFAULT_INFERENCE_FRAMEWORK
              );
              const frameworkColor = getFrameworkColor(framework);
              return (
                <View key={model.id} style={styles.modelRow}>
                  <View style={styles.modelText}>
                    <Text style={styles.modelName}>
                      {model.name || model.id}
                    </Text>
                    <View style={styles.modelMeta}>
                      <Text style={styles.modelSize}>
                        {formatBytes(getModelDownloadSizeBytes(model))}
                      </Text>
                      <View
                        style={[
                          styles.backendBadge,
                          { backgroundColor: `${frameworkColor}18` },
                        ]}
                      >
                        <Icon
                          name={getFrameworkIcon(framework)}
                          size={12}
                          color={frameworkColor}
                        />
                        <Text
                          style={[
                            styles.backendText,
                            { color: frameworkColor },
                          ]}
                        >
                          {RunAnywhere.formatFramework(framework)}
                        </Text>
                      </View>
                    </View>
                  </View>
                  <TouchableOpacity
                    style={styles.deleteButton}
                    onPress={() => deleteModel(model)}
                  >
                    <Icon name="trash-outline" size={18} color={colors.error} />
                  </TouchableOpacity>
                </View>
              );
            })
          )}
        </View>
      </ScrollView>
    </SafeAreaView>
  );
};

const StorageRow: React.FC<{ label: string; value: string }> = ({
  label,
  value,
}) => {
  const styles = useThemedStyles(createStyles);
  return (
    <View style={styles.storageRow}>
      <Text style={styles.storageLabel}>{label}</Text>
      <Text style={styles.storageValue}>{value}</Text>
    </View>
  );
};

const createStyles = (colors: ColorScheme) =>
  StyleSheet.create({
    container: {
      flex: 1,
      backgroundColor: colors.background,
    },
    header: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      paddingHorizontal: 16,
      paddingVertical: 12,
      borderBottomWidth: 1,
      borderBottomColor: colors.outlineVariant,
    },
    title: {
      ...typography.titleLarge,
      color: colors.onSurface,
    },
    content: {
      flex: 1,
    },
    contentInner: {
      padding: 16,
      gap: 16,
    },
    sectionTitle: {
      ...typography.titleMedium,
      color: colors.onSurface,
    },
    section: {
      borderRadius: 8,
      backgroundColor: colors.surfaceContainer,
      overflow: 'hidden',
    },
    storageRow: {
      minHeight: 48,
      paddingHorizontal: 16,
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      borderBottomWidth: 1,
      borderBottomColor: colors.outlineVariant,
    },
    storageLabel: {
      ...typography.bodyLarge,
      color: colors.onSurfaceVariant,
    },
    storageValue: {
      ...typography.bodyLarge,
      color: colors.onSurface,
      fontWeight: '600',
    },
    actionRow: {
      flexDirection: 'row',
      gap: 10,
    },
    actionButton: {
      flex: 1,
      minHeight: 44,
      borderRadius: 8,
      backgroundColor: colors.surfaceContainer,
      alignItems: 'center',
      justifyContent: 'center',
      flexDirection: 'row',
      gap: 6,
    },
    actionButtonText: {
      ...typography.bodyMedium,
      color: colors.onSurface,
    },
    emptyText: {
      ...typography.bodyLarge,
      color: colors.onSurfaceVariant,
      padding: 16,
    },
    modelRow: {
      minHeight: 64,
      paddingHorizontal: 16,
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      borderBottomWidth: 1,
      borderBottomColor: colors.outlineVariant,
    },
    modelText: {
      flex: 1,
    },
    modelMeta: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 6,
      marginTop: 4,
    },
    modelName: {
      ...typography.bodyMedium,
      color: colors.onSurface,
      fontWeight: '600',
    },
    modelSize: {
      ...typography.bodySmall,
      color: colors.onSurfaceVariant,
    },
    backendBadge: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 4,
      borderRadius: 999,
      paddingHorizontal: 8,
      paddingVertical: 3,
    },
    backendText: {
      ...typography.labelSmall,
      fontWeight: '700',
    },
    deleteButton: {
      padding: 10,
    },
  });

export default StorageScreen;
