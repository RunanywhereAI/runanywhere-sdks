/**
 * RunAnywhere AI Example App
 *
 * React Native demonstration app for the RunAnywhere on-device AI SDK.
 *
 * Architecture Pattern:
 * - Two-phase SDK initialization (matching iOS pattern)
 * - Module registration with models (LlamaCPP, ONNX, FluidAudio)
 * - Tab-based navigation with 5 tabs (Chat, STT, TTS, Voice, Settings)
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

// Import RunAnywhere SDK (Multi-Package Architecture)
import { RunAnywhere, SDKEnvironment, ModelCategory } from '@runanywhere/core';
import { LlamaCPP } from '@runanywhere/llamacpp';
import { ONNX, ModelArtifactType } from '@runanywhere/onnx';
import { getStoredApiKey, getStoredBaseURL, hasCustomConfiguration } from './src/screens/SettingsScreen';

/**
 * App initialization state
 */
type InitState = 'loading' | 'ready' | 'error';

/**
 * Initialization Loading View
 */
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

/**
 * Initialization Error View
 */
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
 * Main App Component
 */
const App: React.FC = () => {
  const [initState, setInitState] = useState<InitState>('loading');
  const [error, setError] = useState<string | null>(null);

  /**
   * Register modules and their models
   * Matches iOS registerModulesAndModels() in RunAnywhereAIApp.swift
   *
   * Note: Model registration is async, so we need to wait for all registrations
   * to complete before the UI queries models.
   */
  const registerModulesAndModels = async () => {
    // LlamaCPP module with LLM models
    // Using explicit IDs ensures models are recognized after download across app restarts
    LlamaCPP.register();
    await LlamaCPP.addModel({
      id: 'smollm2-360m-q8_0',
      name: 'SmolLM2 360M Q8_0',
      url: 'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
      memoryRequirement: 500_000_000,
    });
    await LlamaCPP.addModel({
      id: 'llama-2-7b-chat-q4_k_m',
      name: 'Llama 2 7B Chat Q4_K_M',
      url: 'https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf',
      memoryRequirement: 4_000_000_000,
    });
    await LlamaCPP.addModel({
      id: 'mistral-7b-instruct-q4_k_m',
      name: 'Mistral 7B Instruct Q4_K_M',
      url: 'https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf',
      memoryRequirement: 4_000_000_000,
    });
    await LlamaCPP.addModel({
      id: 'qwen2.5-0.5b-instruct-q6_k',
      name: 'Qwen 2.5 0.5B Instruct Q6_K',
      url: 'https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf',
      memoryRequirement: 600_000_000,
    });
    await LlamaCPP.addModel({
      id: 'lfm2-350m-q4_k_m',
      name: 'LiquidAI LFM2 350M Q4_K_M',
      url: 'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf',
      memoryRequirement: 250_000_000,
    });
    await LlamaCPP.addModel({
      id: 'lfm2-350m-q8_0',
      name: 'LiquidAI LFM2 350M Q8_0',
      url: 'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf',
      memoryRequirement: 400_000_000,
    });

    // ONNX module with STT and TTS models
    // Using tar.gz format hosted on RunanywhereAI/sherpa-onnx for fast native extraction
    // Using explicit IDs ensures models are recognized after download across app restarts
    ONNX.register();
    // STT Models (Sherpa-ONNX Whisper)
    await ONNX.addModel({
      id: 'sherpa-onnx-whisper-tiny.en',
      name: 'Sherpa Whisper Tiny (ONNX)',
      url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz',
      modality: ModelCategory.SpeechRecognition,
      artifactType: ModelArtifactType.TarGzArchive,
      memoryRequirement: 75_000_000,
    });
    // NOTE: whisper-small.en not included to match iOS/Android examples
    // All ONNX models use tar.gz from RunanywhereAI/sherpa-onnx fork for fast native extraction
    // If you need whisper-small, convert to tar.gz and upload to the fork
    // TTS Models (Piper VITS)
    await ONNX.addModel({
      id: 'vits-piper-en_US-lessac-medium',
      name: 'Piper TTS (US English - Medium)',
      url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz',
      modality: ModelCategory.SpeechSynthesis,
      artifactType: ModelArtifactType.TarGzArchive,
      memoryRequirement: 65_000_000,
    });
    await ONNX.addModel({
      id: 'vits-piper-en_GB-alba-medium',
      name: 'Piper TTS (British English)',
      url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz',
      modality: ModelCategory.SpeechSynthesis,
      artifactType: ModelArtifactType.TarGzArchive,
      memoryRequirement: 65_000_000,
    });

    console.warn('[App] All models registered');
  };

  /**
   * Initialize the SDK
   * Matches iOS initializeSDK() in RunAnywhereAIApp.swift
   */
  const initializeSDK = useCallback(async () => {
    setInitState('loading');
    setError(null);

    try {
      const startTime = Date.now();

      // Check for custom API configuration (stored via Settings screen)
      const customApiKey = await getStoredApiKey();
      const customBaseURL = await getStoredBaseURL();
      const hasCustomConfig = await hasCustomConfiguration();

      if (hasCustomConfig && customApiKey && customBaseURL) {
        console.log('🔧 Found custom API configuration');
        console.log(`   Base URL: ${customBaseURL}`);

        // Custom configuration mode - use stored API key and base URL
        await RunAnywhere.initialize({
          apiKey: customApiKey,
          baseURL: customBaseURL,
          environment: SDKEnvironment.Production,
        });
        console.log('✅ SDK initialized with CUSTOM configuration (production)');
      } else {
        // DEVELOPMENT mode (default) - uses Supabase directly
        // Credentials come from runanywhere-commons/development_config.cpp (git-ignored)
        // This is the safest option for committing to git
        await RunAnywhere.initialize({
          apiKey: '', // Empty in development mode - uses C++ dev config
          baseURL: 'https://api.runanywhere.ai',
          environment: SDKEnvironment.Development,
        });
        console.log('✅ SDK initialized in DEVELOPMENT mode (Supabase via C++ config)');
      }

      // Register modules and models (await to ensure models are ready before UI)
      await registerModulesAndModels();

      const initTime = Date.now() - startTime;

      // Get SDK info for debugging
      const isInit = await RunAnywhere.isInitialized();
      const version = await RunAnywhere.getVersion();
      const backendInfo = await RunAnywhere.getBackendInfo();

      // Log initialization summary
      // eslint-disable-next-line no-console
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
    initializeSDK();
  }, [initializeSDK]);

  // Render based on state
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
  // Loading View
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

  // Error View
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
