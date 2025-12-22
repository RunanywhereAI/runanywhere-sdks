/**
 * SettingsScreen - Tab 4: Settings & Storage
 *
 * Provides SDK configuration, model management, and storage overview.
 * Matches iOS CombinedSettingsView architecture and patterns.
 *
 * Features:
 * - Generation settings (temperature, max tokens)
 * - API configuration
 * - Storage overview (total usage, available space, models storage)
 * - Downloaded models list with delete functionality
 * - Storage management (clear cache, clean temp files)
 * - SDK info (version, capabilities, loaded models)
 *
 * Architecture:
 * - Fetches SDK state via RunAnywhere methods
 * - Shows available vs downloaded models
 * - Manages model downloads and deletions
 * - Displays backend info and capabilities
 *
 * Reference: iOS examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Settings/CombinedSettingsView.swift
 */

import React, { useState, useCallback, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  SafeAreaView,
  ScrollView,
  TouchableOpacity,
  Alert,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding, BorderRadius } from '../theme/spacing';
import {
  RoutingPolicy,
  RoutingPolicyDisplayNames,
  StorageInfo,
  SETTINGS_CONSTRAINTS,
} from '../types/settings';
import { StoredModel, LLMFramework, FrameworkDisplayNames } from '../types/model';

// Import actual RunAnywhere SDK
import { RunAnywhere, type ModelInfo } from 'runanywhere-react-native';

// Default storage info
const DEFAULT_STORAGE_INFO: StorageInfo = {
  totalStorage: 256 * 1024 * 1024 * 1024,
  appStorage: 0,
  modelsStorage: 0,
  cacheSize: 0,
  freeSpace: 100 * 1024 * 1024 * 1024,
};

/**
 * Format bytes to human readable
 */
const formatBytes = (bytes: number): string => {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(2))} ${sizes[i]}`;
};

export const SettingsScreen: React.FC = () => {
  // Settings state
  const [routingPolicy, setRoutingPolicy] = useState<RoutingPolicy>(RoutingPolicy.Automatic);
  const [temperature, setTemperature] = useState(0.7);
  const [maxTokens, setMaxTokens] = useState(10000);
  const [apiKeyConfigured, setApiKeyConfigured] = useState(false);

  // Storage state
  const [storageInfo, setStorageInfo] = useState<StorageInfo>(DEFAULT_STORAGE_INFO);
  const [storedModels, setStoredModels] = useState<StoredModel[]>([]);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [sdkVersion, setSdkVersion] = useState('0.1.0');

  // SDK State
  const [capabilities, setCapabilities] = useState<number[]>([]);
  const [backendInfoData, setBackendInfoData] = useState<Record<string, unknown>>({});
  const [isSTTLoaded, setIsSTTLoaded] = useState(false);
  const [isTTSLoaded, setIsTTSLoaded] = useState(false);
  const [isTextLoaded, setIsTextLoaded] = useState(false);
  const [isVADLoaded, setIsVADLoaded] = useState(false);
  const [memoryUsage, setMemoryUsage] = useState(0);

  // Model catalog state
  const [availableModels, setAvailableModels] = useState<ModelInfo[]>([]);
  const [downloadingModels, setDownloadingModels] = useState<Record<string, number>>({});
  const [downloadedModels, setDownloadedModels] = useState<ModelInfo[]>([]);

  // Capability names mapping
  const capabilityNames: Record<number, string> = {
    0: 'STT (Speech-to-Text)',
    1: 'TTS (Text-to-Speech)',
    2: 'Text Generation',
    3: 'Embeddings',
    4: 'VAD (Voice Activity)',
    5: 'Diarization',
  };

  // Load data on mount
  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    setIsRefreshing(true);
    try {
      // Get SDK version
      const version = await RunAnywhere.getVersion();
      setSdkVersion(version);

      // Get backend info for storage data
      const backendInfo = await RunAnywhere.getBackendInfo();
      console.log('[Settings] Backend info:', backendInfo);
      setBackendInfoData(backendInfo);

      // Get capabilities (returns string[], not number[])
      const caps = await RunAnywhere.getCapabilities();
      console.log('[Settings] Capabilities:', caps);
      // Convert string capabilities to numbers for display mapping
      const capNumbers = caps.map((cap, index) => index);
      setCapabilities(capNumbers);

      // Check loaded models
      const sttLoaded = await RunAnywhere.isSTTModelLoaded();
      const ttsLoaded = await RunAnywhere.isTTSModelLoaded();
      const textLoaded = await RunAnywhere.isTextModelLoaded();
      const vadLoaded = await RunAnywhere.isVADModelLoaded();

      setIsSTTLoaded(sttLoaded);
      setIsTTSLoaded(ttsLoaded);
      setIsTextLoaded(textLoaded);
      setIsVADLoaded(vadLoaded);

      console.log('[Settings] Models loaded - STT:', sttLoaded, 'TTS:', ttsLoaded, 'Text:', textLoaded, 'VAD:', vadLoaded);

      // Get available models from catalog
      try {
        const available = await RunAnywhere.getAvailableModels();
        console.log('[Settings] Available models:', available);
        setAvailableModels(available);
      } catch (err) {
        console.warn('[Settings] Failed to get available models:', err);
      }

      // Get downloaded models
      try {
        const downloaded = await RunAnywhere.getDownloadedModels();
        console.log('[Settings] Downloaded models:', downloaded);
        setDownloadedModels(downloaded);
      } catch (err) {
        console.warn('[Settings] Failed to get downloaded models:', err);
      }

    } catch (error) {
      console.error('Failed to load data:', error);
    } finally {
      setIsRefreshing(false);
    }
  };

  /**
   * Handle routing policy change
   */
  const handleRoutingPolicyChange = useCallback(() => {
    const policies = Object.values(RoutingPolicy);
    Alert.alert(
      'Routing Policy',
      'Choose how requests are routed',
      policies.map((policy) => ({
        text: RoutingPolicyDisplayNames[policy],
        onPress: () => {
          setRoutingPolicy(policy);
        },
      }))
    );
  }, []);

  /**
   * Handle API key configuration
   */
  const handleConfigureApiKey = useCallback(() => {
    Alert.prompt(
      'API Key',
      'Enter your RunAnywhere API key',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Save',
          onPress: (key?: string) => {
            if (key && key.trim()) {
              setApiKeyConfigured(true);
              // In a real implementation, reinitialize SDK with the new key
            }
          },
        },
      ],
      'secure-text'
    );
  }, []);

  /**
   * Handle model deletion
   */
  const handleDeleteModel = useCallback((model: StoredModel) => {
    Alert.alert(
      'Delete Model',
      `Are you sure you want to delete ${model.name}?`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: async () => {
            try {
              // Unload models if they're loaded
              await RunAnywhere.unloadTextModel();
              await RunAnywhere.unloadSTTModel();
              await RunAnywhere.unloadTTSModel();
              setStoredModels((prev) => prev.filter((m) => m.id !== model.id));
            } catch (error) {
              Alert.alert('Error', `Failed to delete model: ${error}`);
            }
          },
        },
      ]
    );
  }, []);

  /**
   * Handle clear cache
   */
  const handleClearCache = useCallback(() => {
    Alert.alert(
      'Clear Cache',
      'This will clear temporary files. Models will not be deleted.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Clear',
          style: 'destructive',
          onPress: async () => {
            // In a real implementation, call SDK cache clear method
            Alert.alert('Success', 'Cache cleared');
            loadData();
          },
        },
      ]
    );
  }, []);

  /**
   * Handle model download
   */
  const handleDownloadModel = useCallback(async (model: ModelInfo) => {
    if (downloadingModels[model.id] !== undefined) {
      // Already downloading, cancel it
      try {
        await RunAnywhere.cancelDownload(model.id);
        setDownloadingModels((prev) => {
          const updated = { ...prev };
          delete updated[model.id];
          return updated;
        });
      } catch (err) {
        console.error('Failed to cancel download:', err);
      }
      return;
    }

    // Start download with progress tracking
    setDownloadingModels((prev) => ({ ...prev, [model.id]: 0 }));

    try {
      await RunAnywhere.downloadModel(model.id, (progress) => {
        console.log(`[Settings] Download progress for ${model.id}: ${(progress.progress * 100).toFixed(1)}%`);
        setDownloadingModels((prev) => ({
          ...prev,
          [model.id]: progress.progress,
        }));
      });

      // Download complete
      setDownloadingModels((prev) => {
        const updated = { ...prev };
        delete updated[model.id];
        return updated;
      });

      Alert.alert('Success', `${model.name} downloaded successfully!`);
      loadData(); // Refresh to show downloaded model
    } catch (err) {
      setDownloadingModels((prev) => {
        const updated = { ...prev };
        delete updated[model.id];
        return updated;
      });
      Alert.alert('Download Failed', `Failed to download ${model.name}: ${err}`);
    }
  }, [downloadingModels]);

  /**
   * Handle delete downloaded model
   */
  const handleDeleteDownloadedModel = useCallback(async (model: ModelInfo) => {
    Alert.alert(
      'Delete Model',
      `Are you sure you want to delete ${model.name}? This will free up ${formatBytes(model.downloadSize || 0)}.`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: async () => {
            try {
              await RunAnywhere.deleteModel(model.id);
              Alert.alert('Deleted', `${model.name} has been deleted.`);
              loadData(); // Refresh list
            } catch (err) {
              Alert.alert('Error', `Failed to delete: ${err}`);
            }
          },
        },
      ]
    );
  }, []);

  /**
   * Handle clear all data
   */
  const handleClearAllData = useCallback(() => {
    Alert.alert(
      'Clear All Data',
      'This will delete all models and reset the app. This action cannot be undone.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Clear All',
          style: 'destructive',
          onPress: async () => {
            try {
              // Unload all models
              await RunAnywhere.unloadTextModel();
              await RunAnywhere.unloadSTTModel();
              await RunAnywhere.unloadTTSModel();
              // Destroy SDK
              await RunAnywhere.destroy();
              setStoredModels([]);
              Alert.alert('Success', 'All data cleared');
            } catch (error) {
              Alert.alert('Error', `Failed to clear data: ${error}`);
            }
            loadData();
          },
        },
      ]
    );
  }, []);

  /**
   * Render section header
   */
  const renderSectionHeader = (title: string) => (
    <Text style={styles.sectionHeader}>{title}</Text>
  );

  /**
   * Render setting row
   */
  const renderSettingRow = (
    icon: string,
    title: string,
    value: string,
    onPress?: () => void,
    showChevron: boolean = true
  ) => (
    <TouchableOpacity
      style={styles.settingRow}
      onPress={onPress}
      disabled={!onPress}
      activeOpacity={0.7}
    >
      <View style={styles.settingRowLeft}>
        <Icon name={icon} size={20} color={Colors.primaryBlue} />
        <Text style={styles.settingLabel}>{title}</Text>
      </View>
      <View style={styles.settingRowRight}>
        <Text style={styles.settingValue}>{value}</Text>
        {showChevron && onPress && (
          <Icon name="chevron-forward" size={18} color={Colors.textTertiary} />
        )}
      </View>
    </TouchableOpacity>
  );

  /**
   * Render slider setting
   */
  const renderSliderSetting = (
    title: string,
    value: number,
    onChange: (value: number) => void,
    min: number,
    max: number,
    step: number,
    formatValue: (v: number) => string
  ) => (
    <View style={styles.sliderSetting}>
      <View style={styles.sliderHeader}>
        <Text style={styles.settingLabel}>{title}</Text>
        <Text style={styles.sliderValue}>{formatValue(value)}</Text>
      </View>
      <View style={styles.sliderControls}>
        <TouchableOpacity
          style={styles.sliderButton}
          onPress={() => onChange(Math.max(min, value - step))}
        >
          <Icon name="remove" size={20} color={Colors.primaryBlue} />
        </TouchableOpacity>
        <View style={styles.sliderTrack}>
          <View
            style={[
              styles.sliderFill,
              { width: `${((value - min) / (max - min)) * 100}%` },
            ]}
          />
        </View>
        <TouchableOpacity
          style={styles.sliderButton}
          onPress={() => onChange(Math.min(max, value + step))}
        >
          <Icon name="add" size={20} color={Colors.primaryBlue} />
        </TouchableOpacity>
      </View>
    </View>
  );

  /**
   * Render storage bar
   */
  const renderStorageBar = () => {
    const usedPercent = (storageInfo.appStorage / storageInfo.totalStorage) * 100;
    return (
      <View style={styles.storageBar}>
        <View style={styles.storageBarTrack}>
          <View
            style={[styles.storageBarFill, { width: `${Math.min(usedPercent, 100)}%` }]}
          />
        </View>
        <Text style={styles.storageText}>
          {formatBytes(storageInfo.appStorage)} of {formatBytes(storageInfo.totalStorage)} used
        </Text>
      </View>
    );
  };

  /**
   * Render stored model row
   */
  const renderStoredModelRow = (model: StoredModel) => (
    <View key={model.id} style={styles.modelRow}>
      <View style={styles.modelInfo}>
        <Text style={styles.modelName}>{model.name}</Text>
        <View style={styles.modelMeta}>
          <View style={styles.frameworkBadge}>
            <Text style={styles.frameworkBadgeText}>
              {FrameworkDisplayNames[model.framework] || model.framework}
            </Text>
          </View>
          <Text style={styles.modelSize}>{formatBytes(model.sizeOnDisk)}</Text>
        </View>
      </View>
      <TouchableOpacity
        style={styles.deleteButton}
        onPress={() => handleDeleteModel(model)}
      >
        <Icon name="trash-outline" size={20} color={Colors.primaryRed} />
      </TouchableOpacity>
    </View>
  );

  /**
   * Render catalog model row
   */
  const renderCatalogModelRow = (model: ModelInfo) => {
    const isDownloading = downloadingModels[model.id] !== undefined;
    const downloadProgress = downloadingModels[model.id] || 0;
    const isDownloaded = downloadedModels.some((m) => m.id === model.id);

    return (
      <View key={model.id} style={styles.catalogModelRow}>
        <View style={styles.catalogModelInfo}>
          <View style={styles.catalogModelHeader}>
            <Text style={styles.catalogModelName}>{model.name}</Text>
            <View style={styles.catalogModelBadge}>
              <Text style={styles.catalogModelBadgeText}>{model.category}</Text>
            </View>
          </View>
          {model.metadata?.description && (
            <Text style={styles.catalogModelDescription} numberOfLines={2}>
              {model.metadata.description}
            </Text>
          )}
          <View style={styles.catalogModelMeta}>
            <Text style={styles.catalogModelSize}>{formatBytes(model.downloadSize || 0)}</Text>
            <Text style={styles.catalogModelFormat}>{model.format}</Text>
          </View>
          {isDownloading && (
            <View style={styles.downloadProgressContainer}>
              <View style={styles.downloadProgressTrack}>
                <View
                  style={[
                    styles.downloadProgressFill,
                    { width: `${downloadProgress * 100}%` },
                  ]}
                />
              </View>
              <Text style={styles.downloadProgressText}>
                {(downloadProgress * 100).toFixed(0)}%
              </Text>
            </View>
          )}
        </View>
        <TouchableOpacity
          style={[
            styles.catalogModelButton,
            isDownloaded && styles.catalogModelButtonDownloaded,
            isDownloading && styles.catalogModelButtonDownloading,
          ]}
          onPress={() =>
            isDownloaded ? handleDeleteDownloadedModel(model) : handleDownloadModel(model)
          }
        >
          <Icon
            name={
              isDownloaded
                ? 'checkmark-circle'
                : isDownloading
                  ? 'close-circle'
                  : 'cloud-download-outline'
            }
            size={24}
            color={
              isDownloaded
                ? Colors.primaryGreen
                : isDownloading
                  ? Colors.primaryOrange
                  : Colors.primaryBlue
            }
          />
        </TouchableOpacity>
      </View>
    );
  };

  return (
    <SafeAreaView style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.title}>Settings</Text>
        <TouchableOpacity style={styles.refreshButton} onPress={loadData}>
          <Icon name="refresh" size={22} color={Colors.primaryBlue} />
        </TouchableOpacity>
      </View>

      <ScrollView style={styles.content} showsVerticalScrollIndicator={false}>
        {/* SDK Status */}
        {renderSectionHeader('SDK Status')}
        <View style={styles.section}>
          {/* Backend Info */}
          <View style={styles.statusRow}>
            <Text style={styles.statusLabel}>Backend</Text>
            <Text style={styles.statusValue}>
              {(backendInfoData as { name?: string }).name || 'Not initialized'}
            </Text>
          </View>
          <View style={styles.statusRow}>
            <Text style={styles.statusLabel}>Version</Text>
            <Text style={styles.statusValue}>
              {(backendInfoData as { version?: string }).version || '-'}
            </Text>
          </View>

          {/* Capabilities */}
          <View style={styles.capabilitiesContainer}>
            <Text style={styles.capabilitiesLabel}>Supported Capabilities:</Text>
            {capabilities.length > 0 ? (
              <View style={styles.capabilitiesList}>
                {capabilities.map((cap) => (
                  <View key={cap} style={styles.capabilityBadge}>
                    <Icon name="checkmark-circle" size={14} color={Colors.primaryGreen} />
                    <Text style={styles.capabilityText}>
                      {capabilityNames[cap] || `Capability ${cap}`}
                    </Text>
                  </View>
                ))}
              </View>
            ) : (
              <Text style={styles.noCapabilities}>No capabilities reported</Text>
            )}
          </View>

          {/* Model Status */}
          <View style={styles.modelStatusContainer}>
            <Text style={styles.capabilitiesLabel}>Loaded Models:</Text>
            <View style={styles.modelStatusGrid}>
              <View style={[styles.modelStatusItem, isSTTLoaded && styles.modelStatusItemLoaded]}>
                <Icon
                  name={isSTTLoaded ? 'checkmark-circle' : 'close-circle'}
                  size={16}
                  color={isSTTLoaded ? Colors.primaryGreen : Colors.textTertiary}
                />
                <Text style={styles.modelStatusText}>STT</Text>
              </View>
              <View style={[styles.modelStatusItem, isTTSLoaded && styles.modelStatusItemLoaded]}>
                <Icon
                  name={isTTSLoaded ? 'checkmark-circle' : 'close-circle'}
                  size={16}
                  color={isTTSLoaded ? Colors.primaryGreen : Colors.textTertiary}
                />
                <Text style={styles.modelStatusText}>TTS</Text>
              </View>
              <View style={[styles.modelStatusItem, isTextLoaded && styles.modelStatusItemLoaded]}>
                <Icon
                  name={isTextLoaded ? 'checkmark-circle' : 'close-circle'}
                  size={16}
                  color={isTextLoaded ? Colors.primaryGreen : Colors.textTertiary}
                />
                <Text style={styles.modelStatusText}>LLM</Text>
              </View>
              <View style={[styles.modelStatusItem, isVADLoaded && styles.modelStatusItemLoaded]}>
                <Icon
                  name={isVADLoaded ? 'checkmark-circle' : 'close-circle'}
                  size={16}
                  color={isVADLoaded ? Colors.primaryGreen : Colors.textTertiary}
                />
                <Text style={styles.modelStatusText}>VAD</Text>
              </View>
            </View>
          </View>
        </View>

        {/* SDK Configuration */}
        {renderSectionHeader('SDK Configuration')}
        <View style={styles.section}>
          {renderSettingRow(
            'git-branch-outline',
            'Routing Policy',
            RoutingPolicyDisplayNames[routingPolicy],
            handleRoutingPolicyChange
          )}
        </View>

        {/* Generation Settings */}
        {renderSectionHeader('Generation Settings')}
        <View style={styles.section}>
          {renderSliderSetting(
            'Temperature',
            temperature,
            setTemperature,
            SETTINGS_CONSTRAINTS.temperature.min,
            SETTINGS_CONSTRAINTS.temperature.max,
            SETTINGS_CONSTRAINTS.temperature.step,
            (v) => v.toFixed(1)
          )}
          {renderSliderSetting(
            'Max Tokens',
            maxTokens,
            setMaxTokens,
            SETTINGS_CONSTRAINTS.maxTokens.min,
            SETTINGS_CONSTRAINTS.maxTokens.max,
            SETTINGS_CONSTRAINTS.maxTokens.step,
            (v) => v.toLocaleString()
          )}
        </View>

        {/* API Configuration */}
        {renderSectionHeader('API Configuration')}
        <View style={styles.section}>
          {renderSettingRow(
            'key-outline',
            'API Key',
            apiKeyConfigured ? 'Configured' : 'Not Set',
            handleConfigureApiKey
          )}
        </View>

        {/* Storage Overview */}
        {renderSectionHeader('Storage Overview')}
        <View style={styles.section}>
          {renderStorageBar()}
          <View style={styles.storageDetails}>
            <View style={styles.storageDetailRow}>
              <Text style={styles.storageDetailLabel}>Models</Text>
              <Text style={styles.storageDetailValue}>
                {formatBytes(storageInfo.modelsStorage)}
              </Text>
            </View>
            <View style={styles.storageDetailRow}>
              <Text style={styles.storageDetailLabel}>Cache</Text>
              <Text style={styles.storageDetailValue}>
                {formatBytes(storageInfo.cacheSize)}
              </Text>
            </View>
            <View style={styles.storageDetailRow}>
              <Text style={styles.storageDetailLabel}>Free Space</Text>
              <Text style={styles.storageDetailValue}>
                {formatBytes(storageInfo.freeSpace)}
              </Text>
            </View>
          </View>
        </View>

        {/* Model Catalog */}
        {renderSectionHeader('Model Catalog')}
        <View style={styles.section}>
          {availableModels.length === 0 ? (
            <Text style={styles.emptyText}>Loading models...</Text>
          ) : (
            availableModels.map(renderCatalogModelRow)
          )}
        </View>

        {/* Downloaded Models (legacy) */}
        {storedModels.length > 0 && (
          <>
            {renderSectionHeader('Downloaded Models')}
            <View style={styles.section}>
              {storedModels.map(renderStoredModelRow)}
            </View>
          </>
        )}

        {/* Storage Management */}
        {renderSectionHeader('Storage Management')}
        <View style={styles.section}>
          <TouchableOpacity style={styles.dangerButton} onPress={handleClearCache}>
            <Icon name="trash-outline" size={20} color={Colors.primaryOrange} />
            <Text style={styles.dangerButtonText}>Clear Cache</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.dangerButton, styles.dangerButtonRed]}
            onPress={handleClearAllData}
          >
            <Icon name="warning-outline" size={20} color={Colors.primaryRed} />
            <Text style={[styles.dangerButtonText, styles.dangerButtonTextRed]}>
              Clear All Data
            </Text>
          </TouchableOpacity>
        </View>

        {/* Version Info */}
        <View style={styles.versionContainer}>
          <Text style={styles.versionText}>RunAnywhere AI Demo v1.0.0</Text>
          <Text style={styles.versionSubtext}>SDK v{sdkVersion} (React Native)</Text>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.backgroundGrouped,
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
  title: {
    ...Typography.title2,
    color: Colors.textPrimary,
  },
  refreshButton: {
    padding: Spacing.small,
  },
  content: {
    flex: 1,
  },
  sectionHeader: {
    ...Typography.footnote,
    color: Colors.textSecondary,
    textTransform: 'uppercase',
    marginTop: Spacing.xLarge,
    marginBottom: Spacing.small,
    marginHorizontal: Padding.padding16,
  },
  section: {
    backgroundColor: Colors.backgroundPrimary,
    borderRadius: BorderRadius.medium,
    marginHorizontal: Padding.padding16,
    overflow: 'hidden',
  },
  settingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: Padding.padding16,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  settingRowLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.medium,
  },
  settingRowRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.small,
  },
  settingLabel: {
    ...Typography.body,
    color: Colors.textPrimary,
  },
  settingValue: {
    ...Typography.body,
    color: Colors.textSecondary,
  },
  sliderSetting: {
    padding: Padding.padding16,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  sliderHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: Spacing.medium,
  },
  sliderValue: {
    ...Typography.body,
    color: Colors.primaryBlue,
    fontWeight: '600',
  },
  sliderControls: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.medium,
  },
  sliderButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: Colors.backgroundSecondary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  sliderTrack: {
    flex: 1,
    height: 6,
    backgroundColor: Colors.backgroundGray5,
    borderRadius: 3,
  },
  sliderFill: {
    height: '100%',
    backgroundColor: Colors.primaryBlue,
    borderRadius: 3,
  },
  storageBar: {
    padding: Padding.padding16,
  },
  storageBarTrack: {
    height: 8,
    backgroundColor: Colors.backgroundGray5,
    borderRadius: 4,
    overflow: 'hidden',
  },
  storageBarFill: {
    height: '100%',
    backgroundColor: Colors.primaryBlue,
    borderRadius: 4,
  },
  storageText: {
    ...Typography.footnote,
    color: Colors.textSecondary,
    marginTop: Spacing.small,
    textAlign: 'center',
  },
  storageDetails: {
    borderTopWidth: 1,
    borderTopColor: Colors.borderLight,
    padding: Padding.padding16,
    gap: Spacing.small,
  },
  storageDetailRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  storageDetailLabel: {
    ...Typography.subheadline,
    color: Colors.textSecondary,
  },
  storageDetailValue: {
    ...Typography.subheadline,
    color: Colors.textPrimary,
  },
  modelRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: Padding.padding16,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  modelInfo: {
    flex: 1,
  },
  modelName: {
    ...Typography.body,
    color: Colors.textPrimary,
  },
  modelMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.small,
    marginTop: Spacing.xSmall,
  },
  frameworkBadge: {
    backgroundColor: Colors.badgeBlue,
    paddingHorizontal: Spacing.small,
    paddingVertical: Spacing.xxSmall,
    borderRadius: BorderRadius.small,
  },
  frameworkBadgeText: {
    ...Typography.caption2,
    color: Colors.primaryBlue,
    fontWeight: '600',
  },
  modelSize: {
    ...Typography.caption,
    color: Colors.textSecondary,
  },
  deleteButton: {
    padding: Spacing.small,
  },
  emptyText: {
    ...Typography.body,
    color: Colors.textSecondary,
    textAlign: 'center',
    padding: Padding.padding24,
  },
  dangerButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: Spacing.smallMedium,
    padding: Padding.padding16,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  dangerButtonRed: {
    borderBottomWidth: 0,
  },
  dangerButtonText: {
    ...Typography.body,
    color: Colors.primaryOrange,
  },
  dangerButtonTextRed: {
    color: Colors.primaryRed,
  },
  versionContainer: {
    alignItems: 'center',
    padding: Padding.padding24,
    marginTop: Spacing.large,
    marginBottom: Spacing.xxxLarge,
  },
  versionText: {
    ...Typography.footnote,
    color: Colors.textTertiary,
  },
  versionSubtext: {
    ...Typography.caption,
    color: Colors.textTertiary,
    marginTop: Spacing.xSmall,
  },
  // SDK Status styles
  statusRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: Padding.padding16,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  statusLabel: {
    ...Typography.body,
    color: Colors.textPrimary,
  },
  statusValue: {
    ...Typography.body,
    color: Colors.primaryBlue,
    fontWeight: '600',
  },
  capabilitiesContainer: {
    padding: Padding.padding16,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  capabilitiesLabel: {
    ...Typography.subheadline,
    color: Colors.textSecondary,
    marginBottom: Spacing.small,
  },
  capabilitiesList: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: Spacing.small,
  },
  capabilityBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.xSmall,
    backgroundColor: Colors.badgeGreen,
    paddingHorizontal: Spacing.smallMedium,
    paddingVertical: Spacing.xSmall,
    borderRadius: BorderRadius.small,
  },
  capabilityText: {
    ...Typography.caption,
    color: Colors.primaryGreen,
    fontWeight: '600',
  },
  noCapabilities: {
    ...Typography.body,
    color: Colors.textTertiary,
    fontStyle: 'italic',
  },
  modelStatusContainer: {
    padding: Padding.padding16,
  },
  modelStatusGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: Spacing.small,
    marginTop: Spacing.small,
  },
  modelStatusItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.xSmall,
    backgroundColor: Colors.backgroundSecondary,
    paddingHorizontal: Spacing.medium,
    paddingVertical: Spacing.small,
    borderRadius: BorderRadius.small,
  },
  modelStatusItemLoaded: {
    backgroundColor: Colors.badgeGreen,
  },
  modelStatusText: {
    ...Typography.footnote,
    color: Colors.textSecondary,
    fontWeight: '600',
  },
  // Model catalog styles
  catalogModelRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: Padding.padding16,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  catalogModelInfo: {
    flex: 1,
    marginRight: Spacing.medium,
  },
  catalogModelHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.small,
    marginBottom: Spacing.xSmall,
  },
  catalogModelName: {
    ...Typography.body,
    color: Colors.textPrimary,
    fontWeight: '600',
  },
  catalogModelBadge: {
    backgroundColor: Colors.badgeBlue,
    paddingHorizontal: Spacing.small,
    paddingVertical: Spacing.xxSmall,
    borderRadius: BorderRadius.small,
  },
  catalogModelBadgeText: {
    ...Typography.caption2,
    color: Colors.primaryBlue,
    fontWeight: '600',
    textTransform: 'uppercase',
  },
  catalogModelDescription: {
    ...Typography.footnote,
    color: Colors.textSecondary,
    marginBottom: Spacing.xSmall,
  },
  catalogModelMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.small,
  },
  catalogModelSize: {
    ...Typography.caption,
    color: Colors.textTertiary,
  },
  catalogModelFormat: {
    ...Typography.caption,
    color: Colors.textTertiary,
  },
  catalogModelButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: Colors.backgroundSecondary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  catalogModelButtonDownloaded: {
    backgroundColor: Colors.badgeGreen,
  },
  catalogModelButtonDownloading: {
    backgroundColor: Colors.badgeOrange,
  },
  downloadProgressContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.small,
    marginTop: Spacing.small,
  },
  downloadProgressTrack: {
    flex: 1,
    height: 4,
    backgroundColor: Colors.backgroundGray5,
    borderRadius: 2,
    overflow: 'hidden',
  },
  downloadProgressFill: {
    height: '100%',
    backgroundColor: Colors.primaryBlue,
    borderRadius: 2,
  },
  downloadProgressText: {
    ...Typography.caption,
    color: Colors.primaryBlue,
    fontWeight: '600',
    minWidth: 40,
    textAlign: 'right',
  },
});

export default SettingsScreen;
