/**
 * RunAnywhere AI Example App
 *
 * React Native demonstration app for the RunAnywhere on-device AI SDK.
 *
 * Architecture Pattern:
 * - Two-phase SDK initialization (matching iOS pattern)
 * - All model registration uses the canonical SDK methods
 *   (`RunAnywhere.registerModel(...)` / `RunAnywhere.registerMultiFileModel(...)`)
 *   which mirror the Swift SDK.
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
  Platform,
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

import { RunAnywhere, SDKEnvironment } from '@runanywhere/core';
import {
  ModelCategory,
  InferenceFramework,
  ModelArtifactType,
} from '@runanywhere/proto-ts/model_types';
import { NPUChip } from '@runanywhere/proto-ts/storage_types';

// Canonical SDK methods (Swift parity).
const { registerModel, registerMultiFileModel } = RunAnywhere;

/**
 * Minimal structural type for optional backend modules.
 * Each backend exposes a `register()` entry point and an optional `isAvailable`
 * flag. Typed here to avoid `any` while keeping the dynamic-require pattern.
 */
type OptionalBackend = {
  register: () => void | Promise<void | boolean>;
  isAvailable?: boolean;
};

function hasUsableBackendConfig(options: {
  apiKey?: string | null;
  baseURL?: string | null;
}): boolean {
  const apiKey = options.apiKey?.trim() ?? '';
  const baseURL = options.baseURL?.trim() ?? '';
  if (!apiKey || apiKey.length < 8 || !baseURL) return false;
  return baseURL.startsWith('http://') || baseURL.startsWith('https://');
}

// Make LlamaCPP optional for ONNX-only builds
let LlamaCPP: OptionalBackend | null = null;
try {
  LlamaCPP = require('@runanywhere/llamacpp').LlamaCPP as OptionalBackend;
} catch {
  logDiagnostic(
    '[App] LlamaCPP backend not available - some features disabled'
  );
}

// Make Genie optional (Android/Snapdragon only)
let Genie: OptionalBackend | null = null;
try {
  Genie = require('@runanywhere/genie').Genie as OptionalBackend;
} catch {
  logDiagnostic('[App] Genie NPU backend not available');
}

let ONNX: OptionalBackend | null = null;
try {
  ONNX = require('@runanywhere/onnx').ONNX as OptionalBackend;
} catch {
  logDiagnostic('[App] ONNX backend not available - speech features disabled');
}
import {
  getStoredApiKey,
  getStoredBaseURL,
  hasCustomConfiguration,
} from './src/screens/SettingsScreen';
import { logDiagnostic } from './src/utils/diagnostics';

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
 * All model registration uses the canonical SDK methods
 * (`RunAnywhere.registerModel(...)` / `RunAnywhere.registerMultiFileModel(...)`).
 * Module-specific addModel() methods are NOT used.
 */
async function registerModulesAndModels(): Promise<void> {
  // =========================================================================
  // LlamaCPP backend + LLM models
  // =========================================================================
  // LlamaCPP.register() returns Promise<boolean>; only register Llama/VLM
  // models when the native backend was actually installed so the demo never
  // routes inference to a backend that failed to register.
  const llamaRegistered = LlamaCPP ? await LlamaCPP.register() : false;
  if (!llamaRegistered && LlamaCPP) {
    logDiagnostic(
      '[App] LlamaCPP.register() returned false - skipping LLM/VLM model registration'
    );
  }

  if (llamaRegistered) {
    await Promise.all([
      registerModel({
        id: 'smollm2-360m-q8_0',
        name: 'SmolLM2 360M Q8_0',
        url: 'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 500_000_000,
      }),
      registerModel({
        id: 'llama-2-7b-chat-q4_k_m',
        name: 'Llama 2 7B Chat Q4_K_M',
        url: 'https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 4_000_000_000,
      }),
      registerModel({
        id: 'mistral-7b-instruct-q4_k_m',
        name: 'Mistral 7B Instruct Q4_K_M',
        url: 'https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 4_000_000_000,
      }),
      registerModel({
        id: 'qwen2.5-0.5b-instruct-q6_k',
        name: 'Qwen 2.5 0.5B Instruct Q6_K',
        url: 'https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 600_000_000,
      }),
      registerModel({
        id: 'qwen2.5-1.5b-instruct-q4_k_m',
        name: 'Qwen 2.5 1.5B Instruct Q4_K_M',
        url: 'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 2_500_000_000,
      }),
      registerModel({
        id: 'qwen3-0.6b-q4_k_m',
        name: 'Qwen3 0.6B Q4_K_M',
        url: 'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 477_000_000,
        supportsThinking: true,
      }),
      registerModel({
        id: 'qwen3-1.7b-q4_k_m',
        name: 'Qwen3 1.7B Q4_K_M',
        url: 'https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 1_200_000_000,
        supportsThinking: true,
      }),
      registerModel({
        id: 'qwen3-4b-q4_k_m',
        name: 'Qwen3 4B Q4_K_M',
        url: 'https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 2_800_000_000,
        supportsThinking: true,
      }),
      registerModel({
        id: 'llama-3.2-3b-instruct-q4_k_m',
        name: 'Llama 3.2 3B Instruct Q4_K_M (Tool Calling)',
        url: 'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 2_000_000_000,
      }),
      registerModel({
        id: 'lfm2-350m-q4_k_m',
        name: 'LiquidAI LFM2 350M Q4_K_M',
        url: 'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 250_000_000,
      }),
      registerModel({
        id: 'lfm2-350m-q8_0',
        name: 'LiquidAI LFM2 350M Q8_0',
        url: 'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 400_000_000,
      }),
      registerModel({
        id: 'lfm2.5-1.2b-instruct-q4_k_m',
        name: 'LiquidAI LFM2.5 1.2B Instruct Q4_K_M',
        url: 'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 900_000_000,
      }),
      registerModel({
        id: 'lfm2-1.2b-tool-q4_k_m',
        name: 'LiquidAI LFM2 1.2B Tool Q4_K_M',
        url: 'https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 800_000_000,
      }),
      registerModel({
        id: 'lfm2-1.2b-tool-q8_0',
        name: 'LiquidAI LFM2 1.2B Tool Q8_0',
        url: 'https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q8_0.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 1_400_000_000,
      }),
    ]);
  } else if (!LlamaCPP) {
    logDiagnostic('[App] Skipping LlamaCPP models - backend not available');
  }

  // =========================================================================
  // VLM (Vision Language) models
  // =========================================================================
  if (llamaRegistered) {
    await Promise.all([
      // SmolVLM 500M - Ultra-lightweight VLM for mobile (~500MB total)
      registerModel({
        id: 'smolvlm-500m-instruct-q8_0',
        name: 'SmolVLM 500M Instruct',
        url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-vlm-models-v1/smolvlm-500m-instruct-q8_0.tar.gz',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
        memoryRequirement: 600_000_000,
      }),
      // Qwen2-VL 2B - Small but capable VLM (~1.6GB total)
      // Uses multi-file download: main model (986MB) + mmproj (710MB)
      registerMultiFileModel({
        id: 'qwen2-vl-2b-instruct-q4_k_m',
        name: 'Qwen2-VL 2B Instruct',
        files: [
          {
            url: 'https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf',
            filename: 'Qwen2-VL-2B-Instruct-Q4_K_M.gguf',
            isRequired: true,
          },
          {
            url: 'https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf',
            filename: 'mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf',
            isRequired: true,
          },
        ],
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        memoryRequirement: 1_800_000_000,
      }),
      // LFM2-VL 450M - LiquidAI's compact VLM, ideal for mobile (~600MB total)
      registerMultiFileModel({
        id: 'lfm2-vl-450m-q8_0',
        name: 'LFM2-VL 450M',
        files: [
          {
            url: 'https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/LFM2-VL-450M-Q8_0.gguf',
            filename: 'LFM2-VL-450M-Q8_0.gguf',
            isRequired: true,
          },
          {
            url: 'https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/mmproj-LFM2-VL-450M-Q8_0.gguf',
            filename: 'mmproj-LFM2-VL-450M-Q8_0.gguf',
            isRequired: true,
          },
        ],
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        memoryRequirement: 600_000_000,
      }),
    ]);
  }

  // =========================================================================
  // Genie NPU backend + Snapdragon-only model catalog (Android only)
  //
  // Drive per-chip model selection from the canonical hardware namespace:
  // `RunAnywhere.hardware.getNPUChip()` returns the structured `NPUChip`
  // vendor enum (Qualcomm Hexagon, Apple Neural Engine, etc.) and
  // `RunAnywhere.hardware.getChip()` returns the raw SoC string for
  // intra-vendor model variant selection (e.g. 8 Elite vs 8 Elite Gen 5).
  // =========================================================================
  if (Platform.OS === 'android' && Genie && Genie.isAvailable) {
    await Genie.register();
    const npuChip = await RunAnywhere.hardware.getNPUChip();
    if (npuChip === NPUChip.NPU_CHIP_QUALCOMM_HEXAGON) {
      const rawChip = (await RunAnywhere.hardware.getChip()).toLowerCase();
      const isGen5 =
        rawChip.includes('gen 5') || rawChip.includes('8 elite gen 5');
      const isElite =
        rawChip.includes('8 elite') || rawChip.includes('snapdragon 8 elite');
      const chipSlug = isGen5 ? '8elite-gen5' : isElite ? '8elite' : null;
      if (chipSlug) {
        const baseUrl = `https://github.com/RunanywhereAI/runanywhere-genie-models/releases/download/v1`;
        const genieModels = [
          {
            slug: 'qwen3-4b',
            name: 'Qwen3 4B',
            memoryRequirement: 2_800_000_000,
            chips: ['8elite-gen5'],
          },
          {
            slug: 'llama3.2-1b-instruct',
            name: 'Llama 3.2 1B Instruct',
            memoryRequirement: 1_200_000_000,
            chips: ['8elite', '8elite-gen5'],
          },
          {
            slug: 'sea-lion3.5-8b-instruct',
            name: 'SEA-LION v3.5 8B Instruct',
            memoryRequirement: 4_800_000_000,
            chips: ['8elite', '8elite-gen5'],
          },
        ];
        await Promise.all(
          genieModels
            .filter((m) => m.chips.includes(chipSlug))
            .map((m) =>
              registerModel({
                id: `${m.slug}-npu-${chipSlug}`,
                name: `${m.name} (NPU - ${chipSlug})`,
                url: `${baseUrl}/${m.slug}-${chipSlug}.bin`,
                framework: InferenceFramework.INFERENCE_FRAMEWORK_GENIE,
                modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
                memoryRequirement: m.memoryRequirement,
              })
            )
        );
        logDiagnostic(
          `[App] Genie NPU models registered for ${chipSlug} (${rawChip})`
        );
      } else {
        logDiagnostic(
          `[App] Genie available but Snapdragon variant '${rawChip}' has no model catalog`
        );
      }
    } else {
      logDiagnostic(
        '[App] Genie backend registered but device is not Snapdragon Hexagon'
      );
    }
  }

  // =========================================================================
  // ONNX backend + STT/TTS models
  // =========================================================================
  // Mirror the LlamaCPP gating: ONNX.register() returns Promise<boolean>;
  // skip STT/TTS/VAD/embedding model registration when the native backend
  // failed to install so the demo never routes inference to a backend that
  // failed to register.
  const onnxRegistered = ONNX ? await ONNX.register() : false;
  if (!ONNX) {
    logDiagnostic('[App] Skipping ONNX models - backend not available');
    return;
  }
  if (!onnxRegistered) {
    logDiagnostic(
      '[App] ONNX.register() returned false - skipping STT/TTS/VAD/embedding model registration'
    );
    return;
  }

  await Promise.all([
    // Sherpa-ONNX speech models — served by the Sherpa engine plugin
    registerModel({
      id: 'sherpa-onnx-whisper-tiny.en',
      name: 'Sherpa Whisper Tiny (ONNX)',
      url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
      artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
      memoryRequirement: 75_000_000,
    }),
    registerModel({
      id: 'vits-piper-en_US-lessac-medium',
      name: 'Piper TTS (US English - Medium)',
      url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
      artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
      memoryRequirement: 65_000_000,
    }),
    registerModel({
      id: 'vits-piper-en_GB-alba-medium',
      name: 'Piper TTS (British English)',
      url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
      artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
      memoryRequirement: 65_000_000,
    }),
    // Silero VAD — one-per-modality minimum for voice-agent parity with
    // iOS. Small .onnx file served directly from the upstream repo.
    registerModel({
      id: 'silero-vad',
      name: 'Silero VAD',
      url: 'https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
      modality: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
      memoryRequirement: 5_000_000,
    }),
    // Embedding model for RAG (multi-file: model.onnx + vocab.txt co-located)
    // Identical to iOS: RunAnywhere.registerMultiFileModel(id:name:files:framework:modality:memoryRequirement:)
    registerMultiFileModel({
      id: 'all-minilm-l6-v2',
      name: 'All MiniLM L6 v2 (Embedding)',
      files: [
        {
          url: 'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx',
          filename: 'model.onnx',
          isRequired: true,
        },
        {
          url: 'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/vocab.txt',
          filename: 'vocab.txt',
          isRequired: true,
        },
      ],
      framework: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
      modality: ModelCategory.MODEL_CATEGORY_EMBEDDING,
      memoryRequirement: 25_500_000,
    }),
  ]);

  // eslint-disable-next-line no-console -- demo app bootstrap diagnostic
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

      /* eslint-disable no-console -- demo app bootstrap diagnostics */
      const customApiKey = await getStoredApiKey();
      const customBaseURL = await getStoredBaseURL();
      const hasCustomConfig = await hasCustomConfiguration();

      if (
        hasCustomConfig &&
        customApiKey &&
        customBaseURL &&
        hasUsableBackendConfig({ apiKey: customApiKey, baseURL: customBaseURL })
      ) {
        console.log('[App] Found custom API configuration');
        await RunAnywhere.initialize({
          apiKey: customApiKey,
          baseURL: customBaseURL,
          environment: SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
        });
        console.log(
          '[App] SDK initialized with custom configuration (production)'
        );
      } else {
        await RunAnywhere.initialize({
          apiKey: '',
          baseURL: 'https://api.runanywhere.ai',
          environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
        });
        console.log('[App] SDK initialized in DEVELOPMENT mode');
      }

      await registerModulesAndModels();

      const initTime = Date.now() - startTime;
      const isInit = await RunAnywhere.isInitialized;
      const version = RunAnywhere.version;
      const sdkState = {
        environment: RunAnywhere.environment,
        servicesReady: RunAnywhere.areServicesReady,
      };

      console.log(
        `[App] SDK initialized: v${version}, ${isInit ? 'Active' : 'Inactive'}, ${initTime}ms, state: ${JSON.stringify(sdkState)}`
      );
      /* eslint-enable no-console */

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
