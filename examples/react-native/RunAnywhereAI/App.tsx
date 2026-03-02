/**
 * RunAnywhere AI Example App
 *
 * React Native demonstration app for the RunAnywhere on-device AI SDK.
 *
 * Architecture Pattern:
 * - Two-phase SDK initialization (matching iOS pattern)
 * - All model registration via RunAnywhere.registerModel() / RunAnywhere.registerMultiFileModel()
 * - Tab-based navigation with 5 tabs (Chat, Transcribe, Speak, Voice, Settings)
 * - Tool calling settings are in Settings tab (matching iOS)
 *
 * Reference: iOS examples/ios/RunAnywhereAI/RunAnywhereAI/App/RunAnywhereAIApp.swift
 */

import React, { useCallback, useEffect, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ActivityIndicator,
  TouchableOpacity,
} from 'react-native';
import { NavigationContainer } from '@react-navigation/native';
import Icon from 'react-native-vector-icons/Ionicons';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import TabNavigator from './src/navigation/TabNavigator';
import { Colors } from './src/theme/colors';
import { Typography } from './src/theme/typography';
import {
  Spacing,
  Padding,
  BorderRadius,
  IconSize,
  ButtonHeight,
} from './src/theme/spacing';

import {
  RunAnywhere,
  SDKEnvironment,
  ModelCategory,
  LLMFramework,
  ModelArtifactType,
  initializeNitroModulesGlobally,
} from '@runanywhere/core';

// Make LlamaCPP optional for ONNX-only builds
let LlamaCPP: any = null;
try {
  LlamaCPP = require('@runanywhere/llamacpp').LlamaCPP;
} catch (e) {
  console.warn('[App] LlamaCPP backend not available - some features disabled');
}
import { ONNX } from '@runanywhere/onnx';
import { getStoredApiKey, getStoredBaseURL, hasCustomConfiguration } from './src/screens/SettingsScreen';

type InitState = 'loading' | 'ready' | 'error';

const InitializationLoadingView: React.FC = () => (
  <View style={styles.loadingContainer}>
    <View style={styles.loadingContent}>
      <View style={styles.iconContainer}>
        <Icon
          name="hardware-chip-outline"
          size={48}
          color={Colors.primaryBlue}
        />
      </View>
      <Text style={styles.loadingTitle}>RunAnywhere AI</Text>
      <Text style={styles.loadingSubtitle}>Initializing SDK...</Text>
      <ActivityIndicator
        size="large"
        color={Colors.primaryBlue}
        style={styles.spinner}
      />
    </View>
  </View>
);

const InitializationErrorView: React.FC<{
  error: string;
  onRetry: () => void;
}> = ({ error, onRetry }) => (
  <View style={styles.errorContainer}>
    <View style={styles.errorContent}>
      <View style={styles.errorIconContainer}>
        <Icon name="alert-circle-outline" size={48} color={Colors.primaryRed} />
      </View>
      <Text style={styles.errorTitle}>Initialization Failed</Text>
      <Text style={styles.errorMessage}>{error}</Text>
      <TouchableOpacity style={styles.retryButton} onPress={onRetry}>
        <Icon name="refresh" size={20} color={Colors.textWhite} />
        <Text style={styles.retryButtonText}>Retry</Text>
      </TouchableOpacity>
    </View>
  </View>
);

/**
 * Register modules and their models.
 * Matches iOS registerModulesAndModels() in RunAnywhereAIApp.swift
 *
 * All model registration uses RunAnywhere.registerModel() / RunAnywhere.registerMultiFileModel()
 * — identical to the iOS pattern. Module-specific addModel() methods are NOT used.
 */
async function registerModulesAndModels(): Promise<void> {
  // =========================================================================
  // LlamaCPP backend + LLM models
  // =========================================================================
  if (LlamaCPP) {
    LlamaCPP.register();

    await Promise.all([
      RunAnywhere.registerModel({
        id: 'smollm2-360m-q8_0',
        name: 'SmolLM2 360M Q8_0',
        url: 'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
        framework: LLMFramework.LlamaCpp,
        memoryRequirement: 500_000_000,
      }),
      RunAnywhere.registerModel({
        id: 'llama-2-7b-chat-q4_k_m',
        name: 'Llama 2 7B Chat Q4_K_M',
        url: 'https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf',
        framework: LLMFramework.LlamaCpp,
        memoryRequirement: 4_000_000_000,
      }),
      RunAnywhere.registerModel({
        id: 'mistral-7b-instruct-q4_k_m',
        name: 'Mistral 7B Instruct Q4_K_M',
        url: 'https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf',
        framework: LLMFramework.LlamaCpp,
        memoryRequirement: 4_000_000_000,
      }),
      RunAnywhere.registerModel({
        id: 'qwen2.5-0.5b-instruct-q6_k',
        name: 'Qwen 2.5 0.5B Instruct Q6_K',
        url: 'https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf',
        framework: LLMFramework.LlamaCpp,
        memoryRequirement: 600_000_000,
      }),
      RunAnywhere.registerModel({
        id: 'llama-3.2-3b-instruct-q4_k_m',
        name: 'Llama 3.2 3B Instruct Q4_K_M (Tool Calling)',
        url: 'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
        framework: LLMFramework.LlamaCpp,
        memoryRequirement: 2_000_000_000,
      }),
      RunAnywhere.registerModel({
        id: 'lfm2-350m-q4_k_m',
        name: 'LiquidAI LFM2 350M Q4_K_M',
        url: 'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf',
        framework: LLMFramework.LlamaCpp,
        memoryRequirement: 250_000_000,
      }),
      RunAnywhere.registerModel({
        id: 'lfm2-350m-q8_0',
        name: 'LiquidAI LFM2 350M Q8_0',
        url: 'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf',
        framework: LLMFramework.LlamaCpp,
        memoryRequirement: 400_000_000,
      }),
      RunAnywhere.registerModel({
        id: 'lfm2.5-1.2b-instruct-q4_k_m',
        name: 'LiquidAI LFM2.5 1.2B Instruct Q4_K_M',
        url: 'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
        framework: LLMFramework.LlamaCpp,
        memoryRequirement: 900_000_000,
      }),
      RunAnywhere.registerModel({
        id: 'lfm2-1.2b-tool-q4_k_m',
        name: 'LiquidAI LFM2 1.2B Tool Q4_K_M',
        url: 'https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q4_K_M.gguf',
        framework: LLMFramework.LlamaCpp,
        memoryRequirement: 800_000_000,
      }),
      RunAnywhere.registerModel({
        id: 'lfm2-1.2b-tool-q8_0',
        name: 'LiquidAI LFM2 1.2B Tool Q8_0',
        url: 'https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q8_0.gguf',
        framework: LLMFramework.LlamaCpp,
        memoryRequirement: 1_400_000_000,
      }),
    ]);
  } else {
    console.warn('[App] Skipping LlamaCPP models - backend not available');
  }

  // =========================================================================
  // VLM (Vision Language) models
  // =========================================================================
  if (LlamaCPP) {
    await Promise.all([
      // SmolVLM 500M - Ultra-lightweight VLM for mobile (~500MB total)
      RunAnywhere.registerModel({
        id: 'smolvlm-500m-instruct-q8_0',
        name: 'SmolVLM 500M Instruct',
        url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-vlm-models-v1/smolvlm-500m-instruct-q8_0.tar.gz',
        framework: LLMFramework.LlamaCpp,
        modality: ModelCategory.Multimodal,
        artifactType: ModelArtifactType.TarGzArchive,
        memoryRequirement: 600_000_000,
      }),
      // Qwen2-VL 2B - Small but capable VLM (~1.6GB total)
      // Uses multi-file download: main model (986MB) + mmproj (710MB)
      RunAnywhere.registerMultiFileModel({
        id: 'qwen2-vl-2b-instruct-q4_k_m',
        name: 'Qwen2-VL 2B Instruct',
        files: [
          { url: 'https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf', filename: 'Qwen2-VL-2B-Instruct-Q4_K_M.gguf' },
          { url: 'https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf', filename: 'mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf' },
        ],
        framework: LLMFramework.LlamaCpp,
        modality: ModelCategory.Multimodal,
        memoryRequirement: 1_800_000_000,
      }),
      // LFM2-VL 450M - LiquidAI's compact VLM, ideal for mobile (~600MB total)
      RunAnywhere.registerMultiFileModel({
        id: 'lfm2-vl-450m-q8_0',
        name: 'LFM2-VL 450M',
        files: [
          { url: 'https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/LFM2-VL-450M-Q8_0.gguf', filename: 'LFM2-VL-450M-Q8_0.gguf' },
          { url: 'https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/mmproj-LFM2-VL-450M-Q8_0.gguf', filename: 'mmproj-LFM2-VL-450M-Q8_0.gguf' },
        ],
        framework: LLMFramework.LlamaCpp,
        modality: ModelCategory.Multimodal,
        memoryRequirement: 600_000_000,
      }),
    ]);
  }

  // =========================================================================
  // ONNX backend + STT/TTS models
  // =========================================================================
  await ONNX.register();

  await Promise.all([
    RunAnywhere.registerModel({
      id: 'sherpa-onnx-whisper-tiny.en',
      name: 'Sherpa Whisper Tiny (ONNX)',
      url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz',
      framework: LLMFramework.ONNX,
      modality: ModelCategory.SpeechRecognition,
      artifactType: ModelArtifactType.TarGzArchive,
      memoryRequirement: 75_000_000,
    }),
    RunAnywhere.registerModel({
      id: 'vits-piper-en_US-lessac-medium',
      name: 'Piper TTS (US English - Medium)',
      url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz',
      framework: LLMFramework.ONNX,
      modality: ModelCategory.SpeechSynthesis,
      artifactType: ModelArtifactType.TarGzArchive,
      memoryRequirement: 65_000_000,
    }),
    RunAnywhere.registerModel({
      id: 'vits-piper-en_GB-alba-medium',
      name: 'Piper TTS (British English)',
      url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz',
      framework: LLMFramework.ONNX,
      modality: ModelCategory.SpeechSynthesis,
      artifactType: ModelArtifactType.TarGzArchive,
      memoryRequirement: 65_000_000,
    }),
    // Embedding model for RAG (multi-file: model.onnx + vocab.txt co-located)
    // Identical to iOS: RunAnywhere.registerMultiFileModel(id:name:files:framework:modality:memoryRequirement:)
    RunAnywhere.registerMultiFileModel({
      id: 'all-minilm-l6-v2',
      name: 'All MiniLM L6 v2 (Embedding)',
      files: [
        { url: 'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx', filename: 'model.onnx' },
        { url: 'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/vocab.txt', filename: 'vocab.txt' },
      ],
      framework: LLMFramework.ONNX,
      modality: ModelCategory.Embedding,
      memoryRequirement: 25_500_000,
    }),
  ]);

  console.log('[App] All models registered');
}

const App: React.FC = () => {
  const [initState, setInitState] = useState<InitState>('loading');
  const [error, setError] = useState<string | null>(null);

  /**
   * Initialize the SDK
   * Matches iOS initializeSDK() in RunAnywhereAIApp.swift
   */
  const initializeSDK = useCallback(async () => {
    setInitState('loading');
    setError(null);

    try {
      const startTime = Date.now();

      console.log('[App] Initializing global NitroModules...');
      await initializeNitroModulesGlobally();
      console.log('[App] Global NitroModules initialized successfully');

      const customApiKey = await getStoredApiKey();
      const customBaseURL = await getStoredBaseURL();
      const hasCustomConfig = await hasCustomConfiguration();

      if (hasCustomConfig && customApiKey && customBaseURL) {
        console.log('[App] Found custom API configuration');
        await RunAnywhere.initialize({
          apiKey: customApiKey,
          baseURL: customBaseURL,
          environment: SDKEnvironment.Production,
        });
        console.log('[App] SDK initialized with custom configuration (production)');
      } else {
        await RunAnywhere.initialize({
          apiKey: '',
          baseURL: 'https://api.runanywhere.ai',
          environment: SDKEnvironment.Development,
        });
        console.log('[App] SDK initialized in DEVELOPMENT mode');
      }

      await registerModulesAndModels();

      const initTime = Date.now() - startTime;
      const isInit = await RunAnywhere.isInitialized();
      const version = await RunAnywhere.getVersion();
      const backendInfo = await RunAnywhere.getBackendInfo();

      console.log(
        `[App] SDK initialized: v${version}, ${isInit ? 'Active' : 'Inactive'}, ${initTime}ms, env: ${JSON.stringify(backendInfo)}`
      );

      setInitState('ready');
    } catch (err) {
      console.error('[App] SDK initialization failed:', err);
      const errorMessage =
        err instanceof Error ? err.message : 'Unknown error occurred';
      setError(errorMessage);
      setInitState('error');
    }
  }, []);

  useEffect(() => {
    const timeoutId = setTimeout(() => {
      initializeSDK();
    }, 100);
    return () => clearTimeout(timeoutId);
  }, [initializeSDK]);

  if (initState === 'loading') {
    return (
      <SafeAreaProvider>
        <InitializationLoadingView />
      </SafeAreaProvider>
    );
  }

  if (initState === 'error') {
    return (
      <SafeAreaProvider>
        <InitializationErrorView
          error={error || 'Failed to initialize SDK'}
          onRetry={initializeSDK}
        />
      </SafeAreaProvider>
    );
  }

  return (
    <SafeAreaProvider>
      <NavigationContainer>
        <TabNavigator />
      </NavigationContainer>
    </SafeAreaProvider>
  );
};

const styles = StyleSheet.create({
  loadingContainer: {
    flex: 1,
    backgroundColor: Colors.backgroundPrimary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  loadingContent: {
    alignItems: 'center',
  },
  iconContainer: {
    width: IconSize.huge,
    height: IconSize.huge,
    borderRadius: IconSize.huge / 2,
    backgroundColor: Colors.badgeBlue,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: Spacing.xLarge,
  },
  loadingTitle: {
    ...Typography.title,
    color: Colors.textPrimary,
    marginBottom: Spacing.small,
  },
  loadingSubtitle: {
    ...Typography.body,
    color: Colors.textSecondary,
    marginBottom: Spacing.xLarge,
  },
  spinner: {
    marginTop: Spacing.large,
  },
  errorContainer: {
    flex: 1,
    backgroundColor: Colors.backgroundPrimary,
    justifyContent: 'center',
    alignItems: 'center',
    padding: Padding.padding24,
  },
  errorContent: {
    alignItems: 'center',
    maxWidth: 300,
  },
  errorIconContainer: {
    width: IconSize.huge,
    height: IconSize.huge,
    borderRadius: IconSize.huge / 2,
    backgroundColor: Colors.badgeRed,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: Spacing.xLarge,
  },
  errorTitle: {
    ...Typography.title2,
    color: Colors.textPrimary,
    marginBottom: Spacing.medium,
  },
  errorMessage: {
    ...Typography.body,
    color: Colors.textSecondary,
    textAlign: 'center',
    marginBottom: Spacing.xLarge,
  },
  retryButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: Spacing.smallMedium,
    backgroundColor: Colors.primaryBlue,
    paddingHorizontal: Padding.padding24,
    height: ButtonHeight.regular,
    borderRadius: BorderRadius.large,
  },
  retryButtonText: {
    ...Typography.headline,
    color: Colors.textWhite,
  },
});

export default App;
