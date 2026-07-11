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
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding, BorderRadius } from '../theme/spacing';
import {
  DEFAULT_INFERENCE_FRAMEWORK,
  getFrameworkColor,
  getFrameworkDisplayName,
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
            color={isRefreshing ? Colors.textTertiary : Colors.primaryBlue}
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
            <Icon name="trash-outline" size={18} color={Colors.primaryOrange} />
            <Text style={styles.actionButtonText}>Clear Cache</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={styles.actionButton}
            onPress={cleanTempFiles}
          >
            <Icon
              name="file-tray-outline"
              size={18}
              color={Colors.primaryBlue}
            />
            <Text style={styles.actionButtonText}>Clean Temp</Text>
          </TouchableOpacity>
        </View>

        <Text style={styles.sectionTitle}>Downloaded Models</Text>
        <View style={styles.section}>
          {downloadedModels.length === 0 ? (
            <Text style={styles.emptyText}>No downloaded models.</Text>
          ) : (
            downloadedModels.map((model) => {
              const framework = getPrimaryFramework(model, DEFAULT_INFERENCE_FRAMEWORK);
              const frameworkColor = getFrameworkColor(framework);
              return (
                <View key={model.id} style={styles.modelRow}>
                  <View style={styles.modelText}>
                    <Text style={styles.modelName}>{model.name || model.id}</Text>
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
                        <Text style={[styles.backendText, { color: frameworkColor }]}>
                          {getFrameworkDisplayName(framework)}
                        </Text>
                      </View>
                    </View>
                  </View>
                  <TouchableOpacity
                    style={styles.deleteButton}
                    onPress={() => deleteModel(model)}
                  >
                    <Icon
                      name="trash-outline"
                      size={18}
                      color={Colors.primaryRed}
                    />
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
}) => (
  <View style={styles.storageRow}>
    <Text style={styles.storageLabel}>{label}</Text>
    <Text style={styles.storageValue}>{value}</Text>
  </View>
);

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
    ...Typography.title2,
    color: Colors.textPrimary,
  },
  content: {
    flex: 1,
  },
  contentInner: {
    padding: Padding.padding16,
    gap: Spacing.large,
  },
  sectionTitle: {
    ...Typography.headline,
    color: Colors.textPrimary,
  },
  section: {
    borderRadius: BorderRadius.regular,
    backgroundColor: Colors.backgroundSecondary,
    overflow: 'hidden',
  },
  storageRow: {
    minHeight: 48,
    paddingHorizontal: Padding.padding16,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  storageLabel: {
    ...Typography.body,
    color: Colors.textSecondary,
  },
  storageValue: {
    ...Typography.body,
    color: Colors.textPrimary,
    fontWeight: '600',
  },
  actionRow: {
    flexDirection: 'row',
    gap: Spacing.medium,
  },
  actionButton: {
    flex: 1,
    minHeight: 44,
    borderRadius: BorderRadius.regular,
    backgroundColor: Colors.backgroundSecondary,
    alignItems: 'center',
    justifyContent: 'center',
    flexDirection: 'row',
    gap: Spacing.small,
  },
  actionButtonText: {
    ...Typography.subheadline,
    color: Colors.textPrimary,
  },
  emptyText: {
    ...Typography.body,
    color: Colors.textSecondary,
    padding: Padding.padding16,
  },
  modelRow: {
    minHeight: 64,
    paddingHorizontal: Padding.padding16,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  modelText: {
    flex: 1,
  },
  modelMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.small,
    marginTop: 4,
  },
  modelName: {
    ...Typography.subheadline,
    color: Colors.textPrimary,
    fontWeight: '600',
  },
  modelSize: {
    ...Typography.footnote,
    color: Colors.textSecondary,
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
    ...Typography.caption2,
    fontWeight: '700',
  },
  deleteButton: {
    padding: Padding.padding10,
  },
});

export default StorageScreen;
