import React, { useState, useCallback, useEffect, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Alert,
  TextInput,
  Modal,
  Switch,
  ActivityIndicator,
  type DimensionValue,
} from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { ROUTES } from '../navigation/routes';
import type { RootStackParamList } from '../navigation/navigation.types';
import type { StorageInfo } from '../types/settings';
import {
  RoutingPolicy,
  ROUTING_POLICY_OPTIONS,
  RoutingPolicyDisplayNames,
  SETTINGS_CONSTRAINTS,
  GENERATION_SETTINGS_KEYS,
  APP_STORAGE_KEYS,
} from '../types/settings';
import {
  getFrameworkDisplayName,
  getModelDownloadSizeBytes,
  getPrimaryFramework,
} from '../utils/modelDisplay';
import { registerDemoTools as registerSharedDemoTools } from '../utils/chatSampleTools';
import { Icon, useTheme } from '../theme/system';

import { RunAnywhere } from '@runanywhere/core';
import {
  ModelCategory,
  type ModelInfo,
} from '@runanywhere/proto-ts/model_types';
import type { DownloadProgress } from '@runanywhere/proto-ts/download_service';
import {
  isModelLoadedForCategory,
  unloadModelsForCategory,
} from '../utils/runAnywhereLifecycle';

const downloadModelStreamHelper = RunAnywhere.downloadModelStream;
const listModels = async (): Promise<ModelInfo[]> =>
  (await RunAnywhere.listModels()).models?.models ?? [];
const listDownloadedModels = async (): Promise<ModelInfo[]> =>
  (await RunAnywhere.downloadedModels()).models?.models ?? [];

const STORAGE_KEYS = APP_STORAGE_KEYS;

function hasUsableBackendConfig(options: {
  apiKey?: string | null;
  baseURL?: string | null;
}): boolean {
  const apiKey = options.apiKey?.trim() ?? '';
  const baseURL = options.baseURL?.trim() ?? '';
  if (!apiKey || apiKey.length < 8 || !baseURL) return false;
  return baseURL.startsWith('http://') || baseURL.startsWith('https://');
}

export const getStoredApiKey = async (): Promise<string | null> => {
  try {
    return await AsyncStorage.getItem(STORAGE_KEYS.API_KEY);
  } catch {
    return null;
  }
};

export const getStoredBaseURL = async (): Promise<string | null> => {
  try {
    const value = await AsyncStorage.getItem(STORAGE_KEYS.BASE_URL);
    if (!value) return null;
    const trimmed = value.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return `https://${trimmed}`;
  } catch {
    return null;
  }
};

export const getStoredHfToken = async (): Promise<string | null> => {
  try {
    return await AsyncStorage.getItem(STORAGE_KEYS.HF_TOKEN);
  } catch {
    return null;
  }
};

export const hasCustomConfiguration = async (): Promise<boolean> => {
  const apiKey = await getStoredApiKey();
  const baseURL = await getStoredBaseURL();
  return hasUsableBackendConfig({ apiKey, baseURL });
};

const DEFAULT_STORAGE_INFO: StorageInfo = {
  totalStorage: 256 * 1024 * 1024 * 1024,
  appStorage: 0,
  modelsStorage: 0,
  cacheSize: 0,
  freeSpace: 100 * 1024 * 1024 * 1024,
};

const formatBytes = (bytes: number): string => {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(2))} ${sizes[i]}`;
};

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

interface SectionProps {
  title: string;
  children: React.ReactNode;
}

const Section: React.FC<SectionProps> = ({ title, children }) => {
  const { colors, typography, dimens } = useTheme();
  return (
    <View style={{ gap: dimens.spacing.sm }}>
      <Text
        style={[
          typography.titleSmall,
          { color: colors.onSurfaceVariant, paddingHorizontal: dimens.screenPadding },
        ]}
      >
        {title}
      </Text>
      <View
        style={[
          styles.sectionCard,
          {
            backgroundColor: colors.surfaceContainerHigh,
            borderRadius: dimens.radius.lg,
            marginHorizontal: dimens.screenPadding,
            padding: dimens.spacing.lg,
            gap: dimens.spacing.md,
          },
        ]}
      >
        {children}
      </View>
    </View>
  );
};

interface SliderRowProps {
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  formatValue: (v: number) => string;
  onChange: (v: number) => void;
}

const SliderRow: React.FC<SliderRowProps> = ({
  label,
  value,
  min,
  max,
  step,
  formatValue,
  onChange,
}) => {
  const { colors, typography, dimens } = useTheme();
  const fillPct = `${Math.round(
    ((value - min) / (max - min)) * 100
  )}%` as DimensionValue;
  return (
    <View style={{ gap: 4 }}>
      <View style={styles.row}>
        <Text style={[typography.bodyLarge, { color: colors.onSurface }]}>{label}</Text>
        <Text style={[typography.metric, { color: colors.onSurfaceVariant }]}>
          {formatValue(value)}
        </Text>
      </View>
      <View style={styles.sliderRow}>
        <TouchableOpacity
          hitSlop={8}
          onPress={() => onChange(Math.max(min, Math.round((value - step) * 100) / 100))}
          style={[styles.sliderBtn, { backgroundColor: colors.surfaceContainerHighest }]}
        >
          <Text style={[typography.labelLarge, { color: colors.primary }]}>−</Text>
        </TouchableOpacity>
        <View style={[styles.sliderTrack, { backgroundColor: colors.surfaceContainerHighest }]}>
          <View style={[styles.sliderFill, { width: fillPct, backgroundColor: colors.primary }]} />
        </View>
        <TouchableOpacity
          hitSlop={8}
          onPress={() => onChange(Math.min(max, Math.round((value + step) * 100) / 100))}
          style={[styles.sliderBtn, { backgroundColor: colors.surfaceContainerHighest }]}
        >
          <Text style={[typography.labelLarge, { color: colors.primary }]}>+</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
};

interface ToggleRowProps {
  label: string;
  description: string;
  value: boolean;
  onChange: (v: boolean) => void;
}

const ToggleRow: React.FC<ToggleRowProps> = ({ label, description, value, onChange }) => {
  const { colors, typography } = useTheme();
  return (
    <View style={[styles.row, { alignItems: 'center' }]}>
      <View style={{ flex: 1, gap: 2 }}>
        <Text style={[typography.bodyLarge, { color: colors.onSurface }]}>{label}</Text>
        <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}>{description}</Text>
      </View>
      <Switch
        value={value}
        onValueChange={onChange}
        trackColor={{ false: colors.surfaceContainerHighest, true: colors.primary }}
        thumbColor={colors.onPrimary}
      />
    </View>
  );
};

interface InfoRowProps {
  label: string;
  value: string;
}

const InfoRow: React.FC<InfoRowProps> = ({ label, value }) => {
  const { colors, typography } = useTheme();
  return (
    <View style={styles.row}>
      <Text style={[typography.bodyLarge, { color: colors.onSurface }]}>{label}</Text>
      <Text style={[typography.metric, { color: colors.onSurfaceVariant }]}>{value}</Text>
    </View>
  );
};

interface DownloadedModelRowProps {
  model: ModelInfo;
  busy: boolean;
  onDelete: () => void;
}

const DownloadedModelRow: React.FC<DownloadedModelRowProps> = ({ model, busy, onDelete }) => {
  const { colors, typography, dimens } = useTheme();
  const sizeBytes = getModelDownloadSizeBytes(model);
  return (
    <View
      style={[
        styles.modelCard,
        {
          backgroundColor: colors.surface,
          borderRadius: dimens.radius.md,
        },
      ]}
    >
      <View style={[styles.modelCardInner, { paddingHorizontal: dimens.spacing.md, paddingVertical: dimens.spacing.sm }]}>
        <View style={{ flex: 1 }}>
          <Text
            style={[typography.bodyMedium, { color: colors.onSurface }]}
            numberOfLines={1}
          >
            {model.name}
          </Text>
          <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}>
            {formatBytes(sizeBytes)}
          </Text>
        </View>
        {busy ? (
          <ActivityIndicator
            size="small"
            color={colors.primary}
            style={{ marginHorizontal: dimens.spacing.md }}
          />
        ) : (
          <TouchableOpacity onPress={onDelete} hitSlop={8} style={{ padding: dimens.spacing.sm }}>
            <Icon name="trash" size={dimens.icon.sm} color={colors.error} />
          </TouchableOpacity>
        )}
      </View>
    </View>
  );
};

interface CatalogModelRowProps {
  model: ModelInfo;
  isDownloaded: boolean;
  isDownloading: boolean;
  downloadProgress: number;
  onAction: () => void;
}

const CatalogModelRow: React.FC<CatalogModelRowProps> = ({
  model,
  isDownloaded,
  isDownloading,
  downloadProgress,
  onAction,
}) => {
  const { colors, typography, dimens } = useTheme();
  const frameworkName = getFrameworkDisplayName(getPrimaryFramework(model));
  const sizeBytes = getModelDownloadSizeBytes(model);

  return (
    <View style={[styles.row, { alignItems: 'center', gap: dimens.spacing.sm }]}>
      <View style={{ flex: 1, gap: 2 }}>
        <Text style={[typography.bodyMedium, { color: colors.onSurface, fontWeight: '600' }]} numberOfLines={1}>
          {model.name}
        </Text>
        {!!model.metadata?.description && (
          <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant }]} numberOfLines={2}>
            {model.metadata.description}
          </Text>
        )}
        <View style={{ flexDirection: 'row', gap: dimens.spacing.sm, marginTop: 2 }}>
          <Text style={[typography.labelSmall, { color: colors.onSurfaceVariant }]}>
            {formatBytes(sizeBytes)}
          </Text>
          {!!frameworkName && (
            <Text style={[typography.labelSmall, { color: colors.onSurfaceVariant }]}>
              {frameworkName}
            </Text>
          )}
        </View>
        {isDownloading && (
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: dimens.spacing.sm, marginTop: 4 }}>
            <View style={[styles.sliderTrack, { flex: 1, backgroundColor: colors.surfaceContainerHighest }]}>
              <View
                style={[
                  styles.sliderFill,
                  {
                    width: `${(downloadProgress * 100).toFixed(
                      0
                    )}%` as DimensionValue,
                    backgroundColor: colors.primary,
                  },
                ]}
              />
            </View>
            <Text style={[typography.labelSmall, { color: colors.primary, minWidth: 36 }]}>
              {(downloadProgress * 100).toFixed(0)}%
            </Text>
          </View>
        )}
      </View>
      <TouchableOpacity onPress={onAction} hitSlop={8}>
        {isDownloaded ? (
          <Icon name="check" size={dimens.icon.md} color={colors.success} />
        ) : isDownloading ? (
          <Icon name="close" size={dimens.icon.md} color={colors.error} />
        ) : (
          <Icon name="download" size={dimens.icon.md} color={colors.primary} />
        )}
      </TouchableOpacity>
    </View>
  );
};

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------

export const SettingsScreen: React.FC = () => {
  const insets = useSafeAreaInsets();
  const navigation = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const { colors, typography, dimens } = useTheme();

  const [_routingPolicy, setRoutingPolicy] = useState<RoutingPolicy>(
    RoutingPolicy.ROUTING_POLICY_UNSPECIFIED
  );
  const [temperature, setTemperature] = useState(0.7);
  const [maxTokens, setMaxTokens] = useState(1000);
  const [systemPrompt, setSystemPrompt] = useState('');
  const [thinkingModeEnabled, setThinkingModeEnabled] = useState(false);
  const [apiKeyConfigured, setApiKeyConfigured] = useState(false);

  const [apiKey, setApiKey] = useState('');
  const [baseURL, setBaseURL] = useState('');
  const [hfToken, setHfTokenInput] = useState('');
  const [isBaseURLConfigured, setIsBaseURLConfigured] = useState(false);
  const [showApiConfigModal, setShowApiConfigModal] = useState(false);
  const [showPassword, setShowPassword] = useState(false);

  const [storageInfo, setStorageInfo] = useState<StorageInfo>(DEFAULT_STORAGE_INFO);
  const [_isRefreshing, setIsRefreshing] = useState(false);
  const [sdkVersion, setSdkVersion] = useState('0.1.0');

  const [availableModels, setAvailableModels] = useState<ModelInfo[]>([]);
  const [downloadingModels, setDownloadingModels] = useState<Record<string, number>>({});
  const [downloadedModels, setDownloadedModels] = useState<ModelInfo[]>([]);
  const downloadIteratorsRef = useRef<Record<string, AsyncIterator<DownloadProgress>>>({});

  const [toolCallingEnabled, setToolCallingEnabled] = useState(false);
  const [registeredTools, setRegisteredTools] = useState<
    Array<{ name: string; description: string; parameters: Array<{ name: string }> }>
  >([]);

  const _capabilityNames: Record<number, string> = {
    0: 'STT (Speech-to-Text)',
    1: 'TTS (Text-to-Speech)',
    2: 'Text Generation',
    3: 'Embeddings',
    4: 'VAD (Voice Activity)',
    5: 'Diarization',
  };

  useEffect(() => {
    loadData();
    loadApiConfiguration();
    loadHfToken();
    loadGenerationSettings();
    loadToolCallingSettings();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    return () => {
      for (const iter of Object.values(downloadIteratorsRef.current)) {
        iter.return?.().catch(() => {});
      }
      downloadIteratorsRef.current = {};
    };
  }, []);

  const loadApiConfiguration = async () => {
    try {
      const storedApiKey = await AsyncStorage.getItem(STORAGE_KEYS.API_KEY);
      const storedBaseURL = await AsyncStorage.getItem(STORAGE_KEYS.BASE_URL);
      setApiKey(storedApiKey || '');
      setBaseURL(storedBaseURL || '');
      setApiKeyConfigured(!!storedApiKey && storedApiKey !== '');
      setIsBaseURLConfigured(!!storedBaseURL && storedBaseURL !== '');
    } catch (error) {
      console.error('[Settings] Failed to load API configuration:', error);
    }
  };

  const loadHfToken = async () => {
    try {
      const storedHfToken = await AsyncStorage.getItem(STORAGE_KEYS.HF_TOKEN);
      setHfTokenInput(storedHfToken || '');
    } catch (error) {
      console.error('[Settings] Failed to load HuggingFace token:', error);
    }
  };

  const saveHfToken = useCallback(async (value: string) => {
    const trimmed = value.trim();
    try {
      await AsyncStorage.setItem(STORAGE_KEYS.HF_TOKEN, trimmed);
      await RunAnywhere.setHfToken(trimmed);
    } catch (error) {
      console.error('[Settings] Failed to save HuggingFace token:', error);
    }
  }, []);

  const handleHfTokenChange = useCallback(
    (value: string) => {
      setHfTokenInput(value);
    },
    []
  );

  const handleHfTokenCommit = useCallback(
    () => {
      // eslint-disable-next-line no-void
      void saveHfToken(hfToken);
    },
    [hfToken, saveHfToken]
  );

  const loadGenerationSettings = async () => {
    try {
      const tempStr = await AsyncStorage.getItem(GENERATION_SETTINGS_KEYS.TEMPERATURE);
      const maxStr = await AsyncStorage.getItem(GENERATION_SETTINGS_KEYS.MAX_TOKENS);
      const sysStr = await AsyncStorage.getItem(GENERATION_SETTINGS_KEYS.SYSTEM_PROMPT);
      const thinkingStr = await AsyncStorage.getItem(GENERATION_SETTINGS_KEYS.THINKING_MODE_ENABLED);
      const loadedTemperature = tempStr !== null ? parseFloat(tempStr) : 0.7;
      setTemperature(loadedTemperature);
      if (maxStr) setMaxTokens(parseInt(maxStr, 10));
      if (sysStr) setSystemPrompt(sysStr);
      setThinkingModeEnabled(thinkingStr === 'true');
      // eslint-disable-next-line no-console
      console.log('[Settings] Loaded generation settings:', {
        temperature: loadedTemperature,
        maxTokens,
        systemPrompt: systemPrompt ? 'set' : 'empty',
        thinkingModeEnabled: thinkingStr === 'true',
      });
    } catch (error) {
      console.error('[Settings] Failed to load generation settings:', error);
    }
  };

  const saveGenerationSettings = async () => {
    try {
      await AsyncStorage.setItem(GENERATION_SETTINGS_KEYS.TEMPERATURE, temperature.toString());
      await AsyncStorage.setItem(GENERATION_SETTINGS_KEYS.MAX_TOKENS, maxTokens.toString());
      await AsyncStorage.setItem(GENERATION_SETTINGS_KEYS.SYSTEM_PROMPT, systemPrompt);
      await AsyncStorage.setItem(
        GENERATION_SETTINGS_KEYS.THINKING_MODE_ENABLED,
        thinkingModeEnabled ? 'true' : 'false'
      );
      // eslint-disable-next-line no-console
      console.log('[Settings] Saved generation settings:', {
        temperature,
        maxTokens,
        systemPrompt: systemPrompt ? `set(${systemPrompt.length} chars)` : 'empty',
        thinkingModeEnabled,
      });
      Alert.alert('Saved', 'Generation settings have been saved successfully.');
    } catch (error) {
      console.error('[Settings] Failed to save generation settings:', error);
      Alert.alert('Error', `Failed to save settings: ${error}`);
    }
  };

  const loadToolCallingSettings = async () => {
    try {
      const enabled = await AsyncStorage.getItem(STORAGE_KEYS.TOOL_CALLING_ENABLED);
      setToolCallingEnabled(enabled === 'true');
      // eslint-disable-next-line no-void
      void refreshRegisteredTools();
    } catch (error) {
      console.error('[Settings] Failed to load tool calling settings:', error);
    }
  };

  const refreshRegisteredTools = async () => {
    const tools = await RunAnywhere.getRegisteredTools();
    setRegisteredTools(
      tools.map((t) => ({
        name: t.name,
        description: t.description,
        parameters: t.parameters || [],
      }))
    );
  };

  const handleToggleToolCalling = async (enabled: boolean) => {
    setToolCallingEnabled(enabled);
    try {
      await AsyncStorage.setItem(STORAGE_KEYS.TOOL_CALLING_ENABLED, enabled ? 'true' : 'false');
      if (enabled) {
        await registerSharedDemoTools();
      } else {
        await RunAnywhere.clearTools();
      }
      await refreshRegisteredTools();
    } catch (error) {
      console.error('[Settings] Failed to save tool calling setting:', error);
    }
  };

  const clearAllTools = () => {
    Alert.alert('Clear All Tools', 'Are you sure you want to remove all registered tools?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Clear',
        style: 'destructive',
        onPress: () => {
          // eslint-disable-next-line no-void
          void (async () => {
            await RunAnywhere.clearTools();
            await refreshRegisteredTools();
          })();
        },
      },
    ]);
  };

  const normalizeBaseURL = (url: string): string => {
    const trimmed = url.trim();
    if (!trimmed) return trimmed;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) return trimmed;
    return `https://${trimmed}`;
  };

  const saveApiConfiguration = async () => {
    try {
      const normalizedURL = normalizeBaseURL(baseURL);
      await AsyncStorage.setItem(STORAGE_KEYS.API_KEY, apiKey);
      await AsyncStorage.setItem(STORAGE_KEYS.BASE_URL, normalizedURL);
      setBaseURL(normalizedURL);
      setApiKeyConfigured(!!apiKey);
      setIsBaseURLConfigured(!!normalizedURL);
      setShowApiConfigModal(false);
      Alert.alert(
        'Restart Required',
        'API configuration has been updated. Please restart the app for changes to take effect.',
        [{ text: 'OK' }]
      );
    } catch (error) {
      Alert.alert('Error', `Failed to save API configuration: ${error}`);
    }
  };

  const clearApiConfiguration = async () => {
    try {
      await AsyncStorage.multiRemove([
        STORAGE_KEYS.API_KEY,
        STORAGE_KEYS.BASE_URL,
        STORAGE_KEYS.DEVICE_REGISTERED,
      ]);
      setApiKey('');
      setBaseURL('');
      setApiKeyConfigured(false);
      setIsBaseURLConfigured(false);
      Alert.alert(
        'Restart Required',
        'API configuration has been cleared. Please restart the app for changes to take effect.',
        [{ text: 'OK' }]
      );
    } catch (error) {
      Alert.alert('Error', `Failed to clear API configuration: ${error}`);
    }
  };

  const loadData = async () => {
    setIsRefreshing(true);
    try {
      const version = RunAnywhere.version;
      setSdkVersion(version);
      const isInit = await RunAnywhere.isInitialized;
      // eslint-disable-next-line no-console
      console.log('[Settings] SDK isInitialized:', isInit);
      const backendInfo = {
        environment: RunAnywhere.environment,
        servicesReady: RunAnywhere.areServicesReady,
      };
      // eslint-disable-next-line no-console
      console.log('[Settings] Backend info:', backendInfo);
      const sttLoaded = await isModelLoadedForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION);
      const ttsLoaded = await isModelLoadedForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS);
      const textLoaded = await isModelLoadedForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE);
      const vadLoaded = await isModelLoadedForCategory(ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION);
      console.warn('[Settings] Models loaded - STT:', sttLoaded, 'TTS:', ttsLoaded, 'Text:', textLoaded, 'VAD:', vadLoaded);
      try {
        const available = await listModels();
        console.warn('[Settings] Available models:', available);
        setAvailableModels(available);
      } catch (err) {
        console.warn('[Settings] Failed to get available models:', err);
      }
      try {
        const downloaded = await listDownloadedModels();
        console.warn('[Settings] Downloaded models:', downloaded);
        setDownloadedModels(downloaded);
      } catch (err) {
        console.warn('[Settings] Failed to get downloaded models:', err);
      }
      try {
        const storage = await RunAnywhere.getStorageInfo();
        console.warn('[Settings] Storage info:', storage);
        if (storage) {
          setStorageInfo({
            totalStorage: storage.device?.totalBytes ?? 0,
            appStorage: storage.app?.totalBytes ?? 0,
            modelsStorage: storage.totalModelsBytes,
            cacheSize: storage.app?.cacheBytes ?? 0,
            freeSpace: storage.device?.freeBytes ?? 0,
          });
        }
      } catch (err) {
        console.warn('[Settings] Failed to get storage info:', err);
      }
    } catch (error) {
      console.error('Failed to load data:', error);
    } finally {
      setIsRefreshing(false);
    }
  };

  const _handleRoutingPolicyChange = useCallback(() => {
    Alert.alert(
      'Routing Policy',
      'Choose how requests are routed',
      ROUTING_POLICY_OPTIONS.map((policy) => ({
        text: RoutingPolicyDisplayNames[policy],
        onPress: () => { setRoutingPolicy(policy); },
      }))
    );
  }, []);

  const handleConfigureApiKey = useCallback(() => {
    setShowApiConfigModal(true);
  }, []);

  const handleCancelApiConfig = useCallback(() => {
    loadApiConfiguration();
    setShowApiConfigModal(false);
  }, []);

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
            try {
              await RunAnywhere.clearCache();
              await RunAnywhere.cleanTempFiles();
              Alert.alert('Success', 'Cache cleared successfully');
              loadData();
            } catch (err) {
              console.error('[Settings] Failed to clear cache:', err);
              Alert.alert('Error', `Failed to clear cache: ${err}`);
            }
          },
        },
      ]
    );
  }, []);

  const handleDownloadModel = useCallback(
    async (model: ModelInfo) => {
      if (downloadingModels[model.id] !== undefined) {
        try {
          await downloadIteratorsRef.current[model.id]?.return?.();
          delete downloadIteratorsRef.current[model.id];
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
      setDownloadingModels((prev) => ({ ...prev, [model.id]: 0 }));
      try {
        const dlIter = downloadModelStreamHelper(model)[Symbol.asyncIterator]();
        downloadIteratorsRef.current[model.id] = dlIter;
        let dlResult = await dlIter.next();
        while (!dlResult.done) {
          const progress = dlResult.value;
          console.warn(`[Settings] Download progress for ${model.id}: ${((progress.stageProgress ?? 0) * 100).toFixed(1)}%`);
          setDownloadingModels((prev) => ({ ...prev, [model.id]: progress.stageProgress ?? 0 }));
          dlResult = await dlIter.next();
        }
        setDownloadingModels((prev) => {
          const updated = { ...prev };
          delete updated[model.id];
          return updated;
        });
        delete downloadIteratorsRef.current[model.id];
        Alert.alert('Success', `${model.name} downloaded successfully!`);
        loadData();
      } catch (err) {
        setDownloadingModels((prev) => {
          const updated = { ...prev };
          delete updated[model.id];
          return updated;
        });
        delete downloadIteratorsRef.current[model.id];
        Alert.alert('Download Failed', `Failed to download ${model.name}: ${err}`);
      }
    },
    [downloadingModels]
  );

  const handleDeleteDownloadedModel = useCallback(
    async (model: ModelInfo) => {
      const downloadedModel = downloadedModels.find((m) => m.id === model.id);
      const freedSize = getModelDownloadSizeBytes(downloadedModel ?? model);
      Alert.alert(
        'Delete Model',
        `Are you sure you want to delete ${model.name}? This will free up ${formatBytes(freedSize)}.`,
        [
          { text: 'Cancel', style: 'cancel' },
          {
            text: 'Delete',
            style: 'destructive',
            onPress: async () => {
              try {
                const result = await RunAnywhere.deleteModel(model.id);
                if (!result.success) throw new Error(result.errorMessage || 'Storage delete failed');
                Alert.alert('Deleted', `${model.name} has been deleted.`);
                loadData();
              } catch (err) {
                Alert.alert('Error', `Failed to delete: ${err}`);
              }
            },
          },
        ]
      );
    },
    [downloadedModels]
  );

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
              await unloadModelsForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE);
              await unloadModelsForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION);
              await unloadModelsForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS);
              await RunAnywhere.reset();
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

  // Storage summary text — matches Android "Models X · Y free"
  const storageSummary = `Models ${formatBytes(storageInfo.modelsStorage)}  ·  ${formatBytes(storageInfo.freeSpace)} free`;

  return (
    <View style={[styles.root, { backgroundColor: colors.background }]}>
      {/* Header */}
      <View style={[styles.header, { paddingTop: insets.top + dimens.spacing.sm }]}>
        <Text style={[typography.titleLarge, { color: colors.onSurface, fontWeight: '700' }]}>
          Settings
        </Text>
      </View>

      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={[
          styles.scrollContent,
          { paddingBottom: insets.bottom + dimens.spacing.xl },
        ]}
        showsVerticalScrollIndicator={false}
      >
        {/* Generation */}
        <Section title="Generation">
          <SliderRow
            label="Temperature"
            value={temperature}
            min={SETTINGS_CONSTRAINTS.temperature.min}
            max={SETTINGS_CONSTRAINTS.temperature.max}
            step={SETTINGS_CONSTRAINTS.temperature.step}
            formatValue={(v) => v.toFixed(1)}
            onChange={setTemperature}
          />
          <SliderRow
            label="Max tokens"
            value={maxTokens}
            min={SETTINGS_CONSTRAINTS.maxTokens.min}
            max={SETTINGS_CONSTRAINTS.maxTokens.max}
            step={SETTINGS_CONSTRAINTS.maxTokens.step}
            formatValue={(v) => v.toLocaleString()}
            onChange={(v) => setMaxTokens(Math.round(v))}
          />
          <View style={{ gap: dimens.spacing.xs }}>
            <Text style={[typography.bodyLarge, { color: colors.onSurface }]}>System prompt</Text>
            <TextInput
              style={[
                styles.textArea,
                {
                  backgroundColor: colors.surfaceContainerHighest,
                  borderColor: colors.outline,
                  color: colors.onSurface,
                  borderRadius: dimens.radius.sm,
                },
                typography.bodyMedium,
              ]}
              value={systemPrompt}
              onChangeText={setSystemPrompt}
              placeholder="Optional — sets the assistant's behavior"
              placeholderTextColor={colors.onSurfaceVariant}
              multiline
              numberOfLines={3}
              textAlignVertical="top"
            />
          </View>
          <ToggleRow
            label="Streaming"
            description="Show the reply token-by-token"
            value={thinkingModeEnabled}
            onChange={setThinkingModeEnabled}
          />
          <TouchableOpacity
            style={[styles.saveBtn, { backgroundColor: colors.primary, borderRadius: dimens.radius.sm }]}
            onPress={saveGenerationSettings}
          >
            <Icon name="check" size={dimens.icon.sm} color={colors.onPrimary} />
            <Text style={[typography.labelLarge, { color: colors.onPrimary }]}>Save Settings</Text>
          </TouchableOpacity>
        </Section>

        {/* Storage */}
        <Section title="Storage">
          <Text style={[typography.metric, { color: colors.onSurfaceVariant }]}>
            {storageSummary}
          </Text>
          {downloadedModels.length === 0 ? (
            <Text style={[typography.bodyMedium, { color: colors.onSurfaceVariant }]}>
              No downloaded models
            </Text>
          ) : (
            downloadedModels.map((model) => (
              <DownloadedModelRow
                key={model.id}
                model={model}
                busy={downloadingModels[model.id] !== undefined}
                onDelete={() => handleDeleteDownloadedModel(model)}
              />
            ))
          )}
          <View style={{ flexDirection: 'row', gap: dimens.spacing.sm }}>
            <TouchableOpacity onPress={handleClearCache}>
              <Text style={[typography.labelLarge, { color: colors.primary }]}>Clear cache</Text>
            </TouchableOpacity>
            <TouchableOpacity onPress={handleClearAllData}>
              <Text style={[typography.labelLarge, { color: colors.error }]}>Clear all data</Text>
            </TouchableOpacity>
          </View>
        </Section>

        {/* Downloads (matches Android SettingsScreen "Downloads") */}
        <Section title="Downloads">
          <View style={{ gap: dimens.spacing.xs }}>
            <Text style={[typography.bodyLarge, { color: colors.onSurface }]}>
              HuggingFace token
            </Text>
            <TextInput
              style={[
                styles.inputField,
                typography.bodyMedium,
                {
                  color: colors.onSurface,
                  backgroundColor: colors.surfaceContainerHighest,
                  borderColor: colors.outline,
                  borderRadius: dimens.radius.sm,
                },
              ]}
              value={hfToken}
              onChangeText={handleHfTokenChange}
              onBlur={handleHfTokenCommit}
              onSubmitEditing={handleHfTokenCommit}
              placeholder="hf_…"
              placeholderTextColor={colors.onSurfaceVariant}
              autoCapitalize="none"
              autoCorrect={false}
              returnKeyType="done"
              secureTextEntry
              textContentType="password"
            />
            <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}>
              Used to download private Hugging Face model repos
            </Text>
          </View>
        </Section>

        {/* API Configuration */}
        <Section title="API Configuration">
          <View style={styles.row}>
            <Text style={[typography.bodyLarge, { color: colors.onSurface }]}>API Key</Text>
            <Text
              style={[
                typography.metric,
                { color: apiKeyConfigured ? colors.success : colors.error },
              ]}
            >
              {apiKeyConfigured ? 'Configured' : 'Not Set'}
            </Text>
          </View>
          <View style={[styles.divider, { backgroundColor: colors.outlineVariant }]} />
          <View style={styles.row}>
            <Text style={[typography.bodyLarge, { color: colors.onSurface }]}>Base URL</Text>
            <Text
              style={[
                typography.metric,
                { color: isBaseURLConfigured ? colors.success : colors.error },
              ]}
            >
              {isBaseURLConfigured ? 'Configured' : 'Not Set'}
            </Text>
          </View>
          <View style={[styles.divider, { backgroundColor: colors.outlineVariant }]} />
          <View style={{ flexDirection: 'row', gap: dimens.spacing.sm }}>
            <TouchableOpacity
              style={[
                styles.outlineBtn,
                { borderColor: colors.primary, borderRadius: dimens.radius.sm },
              ]}
              onPress={handleConfigureApiKey}
            >
              <Text style={[typography.labelLarge, { color: colors.primary }]}>Configure</Text>
            </TouchableOpacity>
            {apiKeyConfigured && isBaseURLConfigured && (
              <TouchableOpacity
                style={[
                  styles.outlineBtn,
                  { borderColor: colors.error, borderRadius: dimens.radius.sm },
                ]}
                onPress={clearApiConfiguration}
              >
                <Text style={[typography.labelLarge, { color: colors.error }]}>Clear</Text>
              </TouchableOpacity>
            )}
          </View>
          <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}>
            Configure custom API key and base URL for testing. Requires app restart.
          </Text>
        </Section>

        {/* Tool Settings */}
        <Section title="Tool Settings">
          <ToggleRow
            label="Enable Tool Calling"
            description="Allow LLMs to call tools (APIs, functions)"
            value={toolCallingEnabled}
            onChange={handleToggleToolCalling}
          />
          {toolCallingEnabled && (
            <>
              <View style={[styles.divider, { backgroundColor: colors.outlineVariant }]} />
              <View style={styles.row}>
                <Text style={[typography.bodyLarge, { color: colors.onSurface }]}>
                  Registered Tools
                </Text>
                <Text
                  style={[
                    typography.metric,
                    { color: registeredTools.length > 0 ? colors.success : colors.onSurfaceVariant },
                  ]}
                >
                  {registeredTools.length} {registeredTools.length === 1 ? 'tool' : 'tools'}
                </Text>
              </View>
              {registeredTools.length > 0 && (
                <>
                  <View style={[styles.divider, { backgroundColor: colors.outlineVariant }]} />
                  {registeredTools.map((tool) => (
                    <View
                      key={tool.name}
                      style={[
                        styles.toolCard,
                        {
                          backgroundColor: colors.surfaceContainerHighest,
                          borderRadius: dimens.radius.sm,
                          padding: dimens.spacing.md,
                          gap: dimens.spacing.xs,
                        },
                      ]}
                    >
                      <View style={{ flexDirection: 'row', alignItems: 'center', gap: dimens.spacing.sm }}>
                        <Icon name="sliders" size={dimens.icon.sm} color={colors.primary} />
                        <Text style={[typography.bodyMedium, { color: colors.onSurface, fontWeight: '600' }]}>
                          {tool.name}
                        </Text>
                      </View>
                      <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant }]} numberOfLines={2}>
                        {tool.description}
                      </Text>
                      {tool.parameters.length > 0 && (
                        <View style={styles.chipRow}>
                          {tool.parameters.map((p) => (
                            <View
                              key={p.name}
                              style={[
                                styles.chip,
                                { backgroundColor: colors.secondaryContainer, borderRadius: dimens.radius.full },
                              ]}
                            >
                              <Text
                                style={[typography.labelSmall, { color: colors.onSecondaryContainer }]}
                              >
                                {p.name}
                              </Text>
                            </View>
                          ))}
                        </View>
                      )}
                    </View>
                  ))}
                  <View style={[styles.divider, { backgroundColor: colors.outlineVariant }]} />
                  <TouchableOpacity style={styles.centerRow} onPress={clearAllTools}>
                    <Icon name="trash" size={dimens.icon.sm} color={colors.error} />
                    <Text style={[typography.labelLarge, { color: colors.error }]}>
                      Clear All Tools
                    </Text>
                  </TouchableOpacity>
                </>
              )}
            </>
          )}
          <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}>
            Tools allow the LLM to call external APIs and functions to get real-time data.
          </Text>
        </Section>

        {/* Performance */}
        <Section title="Performance">
          <TouchableOpacity
            style={[styles.row, { alignItems: 'center' }]}
            onPress={() => navigation.navigate(ROUTES.Benchmarks)}
            activeOpacity={0.7}
          >
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: dimens.spacing.sm, flex: 1 }}>
              <Icon name="benchmarks" size={dimens.icon.sm} color={colors.onSurface} />
              <Text style={[typography.bodyLarge, { color: colors.onSurface }]}>Benchmarks</Text>
            </View>
            <Icon name="chevronRight" size={dimens.icon.sm} color={colors.onSurfaceVariant} />
          </TouchableOpacity>
        </Section>

        {/* Model Catalog */}
        <Section title="Model Catalog">
          {availableModels.length === 0 ? (
            <Text style={[typography.bodyMedium, { color: colors.onSurfaceVariant }]}>
              Loading models…
            </Text>
          ) : (
            availableModels.map((model, i) => (
              <React.Fragment key={model.id}>
                {i > 0 && (
                  <View style={[styles.divider, { backgroundColor: colors.outlineVariant }]} />
                )}
                <CatalogModelRow
                  model={model}
                  isDownloaded={downloadedModels.some((m) => m.id === model.id)}
                  isDownloading={downloadingModels[model.id] !== undefined}
                  downloadProgress={downloadingModels[model.id] ?? 0}
                  onAction={() =>
                    downloadedModels.some((m) => m.id === model.id)
                      ? handleDeleteDownloadedModel(model)
                      : handleDownloadModel(model)
                  }
                />
              </React.Fragment>
            ))
          )}
        </Section>

        {/* About */}
        <Section title="About">
          <InfoRow label="SDK version" value={`v${sdkVersion}`} />
          <View style={[styles.divider, { backgroundColor: colors.outlineVariant }]} />
          <TouchableOpacity
            onPress={() => {
              /* open docs URL */
            }}
          >
            <Text style={[typography.bodyLarge, { color: colors.primary }]}>Documentation</Text>
          </TouchableOpacity>
        </Section>
      </ScrollView>

      {/* API Configuration Modal */}
      <Modal
        visible={showApiConfigModal}
        animationType="slide"
        transparent
        onRequestClose={handleCancelApiConfig}
      >
        <View style={styles.modalOverlay}>
          <View
            style={[
              styles.modalContent,
              {
                backgroundColor: colors.surfaceContainerHigh,
                borderRadius: dimens.radius.lg,
              },
            ]}
          >
            <Text
              style={[
                typography.titleMedium,
                { color: colors.onSurface, textAlign: 'center', marginBottom: dimens.spacing.lg },
              ]}
            >
              API Configuration
            </Text>

            <View style={{ gap: dimens.spacing.xs, marginBottom: dimens.spacing.lg }}>
              <Text style={[typography.labelLarge, { color: colors.onSurfaceVariant }]}>API Key</Text>
              <View
                style={[
                  styles.inputRow,
                  {
                    backgroundColor: colors.surfaceContainerHighest,
                    borderColor: colors.outline,
                    borderRadius: dimens.radius.sm,
                  },
                ]}
              >
                <TextInput
                  style={[styles.inputFlex, typography.bodyMedium, { color: colors.onSurface }]}
                  value={apiKey}
                  onChangeText={setApiKey}
                  placeholder="Enter your API key"
                  placeholderTextColor={colors.onSurfaceVariant}
                  secureTextEntry={!showPassword}
                  autoCapitalize="none"
                  autoCorrect={false}
                />
                <TouchableOpacity
                  style={{ padding: dimens.spacing.md }}
                  onPress={() => setShowPassword(!showPassword)}
                >
                  <Icon
                    name={showPassword ? 'close' : 'info'}
                    size={dimens.icon.sm}
                    color={colors.onSurfaceVariant}
                  />
                </TouchableOpacity>
              </View>
              <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}>
                Your API key for authenticating with the backend
              </Text>
            </View>

            <View style={{ gap: dimens.spacing.xs, marginBottom: dimens.spacing.lg }}>
              <Text style={[typography.labelLarge, { color: colors.onSurfaceVariant }]}>Base URL</Text>
              <TextInput
                style={[
                  styles.inputField,
                  typography.bodyMedium,
                  {
                    color: colors.onSurface,
                    backgroundColor: colors.surfaceContainerHighest,
                    borderColor: colors.outline,
                    borderRadius: dimens.radius.sm,
                  },
                ]}
                value={baseURL}
                onChangeText={setBaseURL}
                placeholder="https://api.example.com"
                placeholderTextColor={colors.onSurfaceVariant}
                autoCapitalize="none"
                autoCorrect={false}
                keyboardType="url"
              />
              <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}>
                The backend API URL (https:// added automatically if missing)
              </Text>
            </View>

            <View
              style={[
                styles.warningBox,
                {
                  backgroundColor: colors.errorContainer,
                  borderRadius: dimens.radius.sm,
                  padding: dimens.spacing.md,
                  marginBottom: dimens.spacing.lg,
                },
              ]}
            >
              <Icon name="info" size={dimens.icon.sm} color={colors.onErrorContainer} />
              <Text style={[typography.bodySmall, { color: colors.onErrorContainer, flex: 1 }]}>
                After saving, you must restart the app for changes to take effect.
              </Text>
            </View>

            <View style={[styles.modalBtns, { gap: dimens.spacing.sm }]}>
              <TouchableOpacity
                style={[
                  styles.modalBtn,
                  { borderRadius: dimens.radius.sm, backgroundColor: colors.surfaceContainerHighest },
                ]}
                onPress={handleCancelApiConfig}
              >
                <Text style={[typography.labelLarge, { color: colors.onSurface }]}>Cancel</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[
                  styles.modalBtn,
                  {
                    borderRadius: dimens.radius.sm,
                    backgroundColor: !apiKey || !baseURL ? colors.surfaceContainerHighest : colors.primary,
                    flex: 1,
                  },
                ]}
                onPress={saveApiConfiguration}
                disabled={!apiKey || !baseURL}
              >
                <Text
                  style={[
                    typography.labelLarge,
                    { color: !apiKey || !baseURL ? colors.onSurfaceVariant : colors.onPrimary },
                  ]}
                >
                  Save
                </Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>
    </View>
  );
};

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
  header: {
    paddingHorizontal: 16,
    paddingBottom: 8,
  },
  scrollContent: {
    gap: 16,
    paddingTop: 8,
  },
  sectionCard: {
    overflow: 'hidden',
  },
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  divider: {
    height: StyleSheet.hairlineWidth,
  },
  sliderRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  sliderBtn: {
    width: 32,
    height: 32,
    borderRadius: 16,
    justifyContent: 'center',
    alignItems: 'center',
  },
  sliderTrack: {
    flex: 1,
    height: 6,
    borderRadius: 3,
    overflow: 'hidden',
  },
  sliderFill: {
    height: '100%',
    borderRadius: 3,
  },
  textArea: {
    borderWidth: 1,
    padding: 12,
    minHeight: 72,
  },
  saveBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    paddingVertical: 12,
    paddingHorizontal: 16,
  },
  outlineBtn: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderWidth: 1,
  },
  centerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
  },
  modelCard: {
    overflow: 'hidden',
  },
  modelCardInner: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  toolCard: {},
  chipRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
  },
  chip: {
    paddingHorizontal: 8,
    paddingVertical: 2,
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.5)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: 24,
  },
  modalContent: {
    width: '100%',
    maxWidth: 400,
    padding: 24,
  },
  inputRow: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1,
  },
  inputFlex: {
    flex: 1,
    padding: 12,
  },
  inputField: {
    borderWidth: 1,
    padding: 12,
  },
  warningBox: {
    flexDirection: 'row',
    gap: 8,
    alignItems: 'flex-start',
  },
  modalBtns: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
  },
  modalBtn: {
    paddingHorizontal: 16,
    paddingVertical: 10,
    alignItems: 'center',
    minWidth: 80,
  },
});

export default SettingsScreen;
