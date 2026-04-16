import React, { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Platform,
  StatusBar,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { NavigationContainer } from '@react-navigation/native';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { AlertCircle, Cpu, RefreshCw } from 'lucide-react-native';
import RootNavigator from './src/navigation/RootNavigator';
import { ThemeProvider, useTheme } from './src/theme';
import { Typography } from './src/theme/typography';
import { BorderRadius, ButtonHeight, Padding, Spacing } from './src/theme/spacing';

import {
  RunAnywhere,
  SDKEnvironment,
  ModelCategory,
  LLMFramework,
  ModelArtifactType,
  initializeNitroModulesGlobally,
  getChip,
  getNPUDownloadUrl,
} from '@runanywhere/core';

type LlamaCPPModule = { register: () => void } | null;
type GenieModule = { register: () => void; isAvailable?: boolean } | null;

let LlamaCPP: LlamaCPPModule = null;
try {
  LlamaCPP = require('@runanywhere/llamacpp').LlamaCPP;
} catch (e) {
  console.warn('[App] LlamaCPP backend not available');
}

let Genie: GenieModule = null;
try {
  Genie = require('@runanywhere/genie').Genie;
} catch (e) {
  console.warn('[App] Genie NPU backend not available');
}

import { ONNX } from '@runanywhere/onnx';
import {
  getStoredApiKey,
  getStoredBaseURL,
  hasCustomConfiguration,
} from './src/screens/SettingsScreen';

type InitState = 'loading' | 'ready' | 'error';

const LoadingView: React.FC = () => {
  const { colors } = useTheme();
  return (
    <View style={[styles.centerContainer, { backgroundColor: colors.background }]}>
      <View style={styles.centerContent}>
        <View
          style={[styles.iconCircle, { backgroundColor: colors.primarySoft }]}
        >
          <Cpu size={48} color={colors.primary} />
        </View>
        <Text style={[styles.title, { color: colors.text }]}>RunAnywhere AI</Text>
        <Text style={[styles.subtitle, { color: colors.textSecondary }]}>
          Initializing SDK…
        </Text>
        <ActivityIndicator
          size="large"
          color={colors.primary}
          style={styles.spinner}
        />
      </View>
    </View>
  );
};

const ErrorView: React.FC<{ error: string; onRetry: () => void }> = ({
  error,
  onRetry,
}) => {
  const { colors } = useTheme();
  return (
    <View style={[styles.centerContainer, { backgroundColor: colors.background }]}>
      <View style={[styles.centerContent, styles.errorContent]}>
        <View style={[styles.iconCircle, { backgroundColor: colors.primarySoft }]}>
          <AlertCircle size={48} color={colors.error} />
        </View>
        <Text style={[styles.errorTitle, { color: colors.text }]}>
          Initialization Failed
        </Text>
        <Text style={[styles.errorMessage, { color: colors.textSecondary }]}>
          {error}
        </Text>
        <TouchableOpacity
          style={[styles.retryButton, { backgroundColor: colors.primary }]}
          onPress={onRetry}
          activeOpacity={0.85}
        >
          <RefreshCw size={20} color={colors.onPrimary} />
          <Text style={[styles.retryButtonText, { color: colors.onPrimary }]}>
            Retry
          </Text>
        </TouchableOpacity>
      </View>
    </View>
  );
};

async function registerModulesAndModels(): Promise<void> {
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

    await Promise.all([
      RunAnywhere.registerModel({
        id: 'smolvlm-500m-instruct-q8_0',
        name: 'SmolVLM 500M Instruct',
        url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-vlm-models-v1/smolvlm-500m-instruct-q8_0.tar.gz',
        framework: LLMFramework.LlamaCpp,
        modality: ModelCategory.Multimodal,
        artifactType: ModelArtifactType.TarGzArchive,
        memoryRequirement: 600_000_000,
      }),
      RunAnywhere.registerMultiFileModel({
        id: 'qwen2-vl-2b-instruct-q4_k_m',
        name: 'Qwen2-VL 2B Instruct',
        files: [
          {
            url: 'https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf',
            filename: 'Qwen2-VL-2B-Instruct-Q4_K_M.gguf',
          },
          {
            url: 'https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf',
            filename: 'mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf',
          },
        ],
        framework: LLMFramework.LlamaCpp,
        modality: ModelCategory.Multimodal,
        memoryRequirement: 1_800_000_000,
      }),
      RunAnywhere.registerMultiFileModel({
        id: 'lfm2-vl-450m-q8_0',
        name: 'LFM2-VL 450M',
        files: [
          {
            url: 'https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/LFM2-VL-450M-Q8_0.gguf',
            filename: 'LFM2-VL-450M-Q8_0.gguf',
          },
          {
            url: 'https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/mmproj-LFM2-VL-450M-Q8_0.gguf',
            filename: 'mmproj-LFM2-VL-450M-Q8_0.gguf',
          },
        ],
        framework: LLMFramework.LlamaCpp,
        modality: ModelCategory.Multimodal,
        memoryRequirement: 600_000_000,
      }),
    ]);
  }

  if (Platform.OS === 'android' && Genie && Genie.isAvailable) {
    Genie.register();
    const chip = await getChip();
    if (chip) {
      const genieModels: Array<{
        slug: string;
        name: string;
        mem: number;
        chips: string[];
        quant?: string;
      }> = [
        { slug: 'qwen3-4b', name: 'Qwen3 4B', mem: 2_800_000_000, chips: ['8elite-gen5'] },
        { slug: 'llama3.2-1b-instruct', name: 'Llama 3.2 1B Instruct', mem: 1_200_000_000, chips: ['8elite', '8elite-gen5'] },
        { slug: 'sea-lion3.5-8b-instruct', name: 'SEA-LION v3.5 8B Instruct', mem: 4_800_000_000, chips: ['8elite', '8elite-gen5'] },
        { slug: 'qwen2.5-7b-instruct', name: 'Qwen 2.5 7B Instruct', mem: 4_200_000_000, chips: ['8elite'], quant: 'w8a16' },
      ];
      const registrations = genieModels
        .filter((m) => m.chips.includes(chip.identifier))
        .map((m) =>
          RunAnywhere.registerModel({
            id: `${m.slug}-npu-${chip.identifier}`,
            name: `${m.name} (NPU - ${chip.displayName})`,
            url: getNPUDownloadUrl(chip, m.slug, m.quant),
            framework: LLMFramework.Genie,
            memoryRequirement: m.mem,
          })
        );
      await Promise.all(registrations);
    }
  }

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
    RunAnywhere.registerMultiFileModel({
      id: 'all-minilm-l6-v2',
      name: 'All MiniLM L6 v2 (Embedding)',
      files: [
        {
          url: 'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx',
          filename: 'model.onnx',
        },
        {
          url: 'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/vocab.txt',
          filename: 'vocab.txt',
        },
      ],
      framework: LLMFramework.ONNX,
      modality: ModelCategory.Embedding,
      memoryRequirement: 25_500_000,
    }),
  ]);
}

const ThemedStatusBar: React.FC = () => {
  const { scheme, colors } = useTheme();
  return (
    <StatusBar
      translucent
      backgroundColor="transparent"
      barStyle={scheme === 'dark' ? 'light-content' : 'dark-content'}
      animated
    />
  );
};

const AppInner: React.FC = () => {
  const [initState, setInitState] = useState<InitState>('loading');
  const [error, setError] = useState<string | null>(null);

  const initializeSDK = useCallback(async () => {
    setInitState('loading');
    setError(null);
    try {
      await initializeNitroModulesGlobally();

      const customApiKey = await getStoredApiKey();
      const customBaseURL = await getStoredBaseURL();
      const hasCustomConfig = await hasCustomConfiguration();

      if (hasCustomConfig && customApiKey && customBaseURL) {
        await RunAnywhere.initialize({
          apiKey: customApiKey,
          baseURL: customBaseURL,
          environment: SDKEnvironment.Production,
        });
      } else {
        await RunAnywhere.initialize({
          apiKey: '',
          baseURL: 'https://api.runanywhere.ai',
          environment: SDKEnvironment.Development,
        });
      }

      await registerModulesAndModels();
      setInitState('ready');
    } catch (err) {
      console.error('[App] SDK initialization failed:', err);
      const message = err instanceof Error ? err.message : 'Unknown error';
      setError(message);
      setInitState('error');
    }
  }, []);

  useEffect(() => {
    const id = setTimeout(() => initializeSDK(), 100);
    return () => clearTimeout(id);
  }, [initializeSDK]);

  if (initState === 'loading') return (<><ThemedStatusBar /><LoadingView /></>);
  if (initState === 'error')
    return (
      <>
        <ThemedStatusBar />
        <ErrorView error={error ?? 'Failed to initialize SDK'} onRetry={initializeSDK} />
      </>
    );
  return (
    <>
      <ThemedStatusBar />
      <NavigationContainer>
        <RootNavigator />
      </NavigationContainer>
    </>
  );
};

const App: React.FC = () => (
  <SafeAreaProvider>
    <ThemeProvider>
      <AppInner />
    </ThemeProvider>
  </SafeAreaProvider>
);

const styles = StyleSheet.create({
  centerContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  centerContent: {
    alignItems: 'center',
  },
  errorContent: {
    maxWidth: 320,
    paddingHorizontal: Padding.padding24,
  },
  iconCircle: {
    width: 80,
    height: 80,
    borderRadius: 40,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: Spacing.xLarge,
  },
  title: {
    ...Typography.title,
    marginBottom: Spacing.small,
  },
  subtitle: {
    ...Typography.body,
    marginBottom: Spacing.xLarge,
  },
  spinner: {
    marginTop: Spacing.large,
  },
  errorTitle: {
    ...Typography.title2,
    marginBottom: Spacing.medium,
  },
  errorMessage: {
    ...Typography.body,
    textAlign: 'center',
    marginBottom: Spacing.xLarge,
  },
  retryButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: Spacing.smallMedium,
    paddingHorizontal: Padding.padding24,
    height: ButtonHeight.regular,
    borderRadius: BorderRadius.large,
  },
  retryButtonText: {
    ...Typography.headline,
  },
});

export default App;
