/**
 * SettingsScreen - Tab 4: Settings & Storage
 *
 * Reference: iOS Features/Settings/CombinedSettingsView.swift
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
  Switch,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding, BorderRadius, IconSize } from '../theme/spacing';
import {
  RoutingPolicy,
  RoutingPolicyDisplayNames,
  StorageInfo,
  SETTINGS_CONSTRAINTS,
} from '../types/settings';
import { StoredModel, LLMFramework, FrameworkDisplayNames } from '../types/model';
import MockSDK, { MOCK_STORAGE_INFO } from '../services/MockSDK';

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
  const [storageInfo, setStorageInfo] = useState<StorageInfo>(MOCK_STORAGE_INFO);
  const [storedModels, setStoredModels] = useState<StoredModel[]>([]);
  const [isRefreshing, setIsRefreshing] = useState(false);

  // Load data on mount
  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    setIsRefreshing(true);
    try {
      const storage = await MockSDK.getStorageInfo();
      const models = await MockSDK.getStoredModels();
      setStorageInfo(storage);
      setStoredModels(models);
    } catch (error) {
      console.error('Failed to load storage data:', error);
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
          // TODO: Save to SDK settings
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
          onPress: (key) => {
            if (key && key.trim()) {
              setApiKeyConfigured(true);
              // TODO: Save API key securely
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
              await MockSDK.deleteModel(model.id);
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
            await MockSDK.clearCache();
            loadData();
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
            await MockSDK.clearAllData();
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

        {/* Downloaded Models */}
        {renderSectionHeader('Downloaded Models')}
        <View style={styles.section}>
          {storedModels.length === 0 ? (
            <Text style={styles.emptyText}>No models downloaded</Text>
          ) : (
            storedModels.map(renderStoredModelRow)
          )}
        </View>

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
          <Text style={styles.versionSubtext}>SDK v0.1.0 (React Native)</Text>
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
});

export default SettingsScreen;
