/**
 * RunAnywhere AI Example App
 *
 * React Native demonstration app for the RunAnywhere on-device AI SDK.
 *
 * Architecture Pattern:
 * - Two-phase SDK initialization (matching iOS pattern)
 * - Model catalog seeding lives in src/services/ModelCatalogBootstrap.ts,
 *   mirroring iOS ModelCatalogBootstrap.swift.
 * - Tab-based navigation with 5 tabs (Chat, Vision, Voice, More, Settings)
 * - Tool calling settings are in Settings tab (matching iOS)
 *
 * Reference: iOS examples/ios/RunAnywhereAI/RunAnywhereAI/App/RunAnywhereAIApp.swift
 */

import React, { useCallback, useEffect, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  StatusBar,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import RootNavigator from './src/navigation/RootNavigator';
import IntroScreen from './src/features/intro/IntroScreen';
import { ThemeProvider, useTheme } from './src/theme/system';
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
  registerAll,
  type BackendRegistrationState,
} from './src/services/ModelCatalogBootstrap';
import {
  normalizeAPIConfiguration,
  setAPIConfigurationApplyHandler,
  type APIConfiguration,
} from './src/services/APIConfiguration';

/**
 * Minimal structural type for optional backend modules.
 * Each backend exposes a `register()` entry point and an optional `isAvailable`
 * flag. Typed here to avoid `any` while keeping the dynamic-require pattern.
 */
type OptionalBackend = {
  register: () => void | Promise<void | boolean>;
  isAvailable?: boolean;
};

// Make LlamaCPP optional for ONNX-only builds
let LlamaCPP: OptionalBackend | null = null;
try {
  LlamaCPP = require('@runanywhere/llamacpp').LlamaCPP as OptionalBackend;
} catch {
  logDiagnostic(
    '[App] LlamaCPP backend not available - some features disabled'
  );
}

let ONNX: OptionalBackend | null = null;
try {
  ONNX = require('@runanywhere/onnx').ONNX as OptionalBackend;
} catch {
  logDiagnostic('[App] ONNX backend not available - speech features disabled');
}

// QHexRT (Qualcomm Hexagon NPU) — Android arm64 only. On other platforms the
// native hybrid is absent, so the app falls back.
let QHexRT: OptionalBackend | null = null;
try {
  const qhexrtModule = require('@runanywhere/qhexrt');
  QHexRT = qhexrtModule.QHexRT as OptionalBackend;
} catch {
  logDiagnostic(
    '[App] QHexRT backend not available - NPU disabled on this platform'
  );
}
import { logDiagnostic } from './src/utils/diagnostics';
import { RUNANYWHERE_BASE_URL, RUNANYWHERE_API_KEY } from '@env';

// Default backend config, injected at build time from the gitignored .env via
// react-native-dotenv (mirrors the Flutter example's --dart-define and the
// Android example's local.properties -> BuildConfig.RUNANYWHERE_*). Used when
// no custom configuration has been saved in Settings.
const DEFAULT_BASE_URL = RUNANYWHERE_BASE_URL ?? '';
const DEFAULT_API_KEY = RUNANYWHERE_API_KEY ?? '';

function buildTimeAPIConfiguration(): APIConfiguration | null {
  try {
    return normalizeAPIConfiguration(DEFAULT_API_KEY, DEFAULT_BASE_URL, {
      allowInsecureLoopback: __DEV__,
    });
  } catch {
    return null;
  }
}

type InitState = 'loading' | 'ready' | 'error';

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
 * Register backend engine plugins. Stays in App.tsx (platform/backends
 * wiring, like iOS RunAnywhereAIApp.swift); the curated model catalog
 * lives in src/services/ModelCatalogBootstrap.ts.
 */
async function registerBackends(): Promise<BackendRegistrationState> {
  const llamaResult = LlamaCPP ? await LlamaCPP.register() : false;
  const llamaRegistered = llamaResult !== false;
  if (!llamaRegistered && LlamaCPP) {
    logDiagnostic(
      '[App] LlamaCPP.register() returned false - skipping LLM/VLM model registration'
    );
  }

  const onnxResult = ONNX ? await ONNX.register() : false;
  const onnxRegistered = onnxResult !== false;
  if (!ONNX) {
    logDiagnostic('[App] Skipping ONNX models - backend not available');
  } else if (!onnxRegistered) {
    logDiagnostic(
      '[App] ONNX.register() returned false - skipping STT/TTS/VAD/embedding model registration'
    );
  }

  // QHexRT registers all NPU modalities (LLM/VLM/STT/TTS) in one call. The SDK
  // resolves logical HNPU URLs to the current Hexagon arch during registration.
  let qhexrtRegistered = false;
  if (QHexRT) {
    try {
      qhexrtRegistered = (await QHexRT.register()) !== false;
      if (qhexrtRegistered) {
        logDiagnostic('[App] QHexRT (NPU) backend registered');
      } else {
        logDiagnostic(
          '[App] QHexRT.register() returned false - NPU unavailable on this device'
        );
      }
    } catch (error) {
      logDiagnostic(`[App] QHexRT backend not available: ${String(error)}`);
    }
  }

  return { llamaRegistered, onnxRegistered, qhexrtRegistered };
}

const App: React.FC = () => {
  const [initState, setInitState] = useState<InitState>('loading');
  const [error, setError] = useState<string | null>(null);

  /**
   * Initialize the SDK
   * Matches iOS initializeSDK() in RunAnywhereAIApp.swift
   */
  const initializeSDK = useCallback(
    async (configurationOverride?: APIConfiguration | null) => {
      const isReconfiguration = configurationOverride !== undefined;
      if (!isReconfiguration) {
        setInitState('loading');
        setError(null);
      }

      try {
        const startTime = Date.now();
        if (isReconfiguration) {
          await RunAnywhere.reset();
        }

        /* eslint-disable no-console -- demo app bootstrap diagnostics */
        const backendState = await registerBackends();
        const configuration =
          configurationOverride ?? buildTimeAPIConfiguration();

        if (configuration) {
          console.log('[App] Found backend configuration');
          // Staging (not Production) so the custom base URL is honored AND
          // local logging stays on — Production sets enableLocalLogging:false,
          // hiding all SDK/telemetry logs. Development would ignore baseURL.
          await RunAnywhere.initialize({
            apiKey: configuration.apiKey,
            baseURL: configuration.baseURL,
            environment: SDKEnvironment.SDK_ENVIRONMENT_STAGING,
          });
          console.log(
            '[App] SDK initialized with backend configuration (staging)'
          );
        } else {
          await RunAnywhere.initialize({
            apiKey: '',
            baseURL: 'https://api.runanywhere.ai',
            environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
          });
          console.log('[App] SDK initialized in DEVELOPMENT mode');
        }

        await registerAll(backendState);
        await RunAnywhere.refreshModelRegistry();

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

        if (!isReconfiguration) {
          setInitState('ready');
        }
      } catch (err) {
        console.error('[App] SDK initialization failed:', err);
        if (isReconfiguration) {
          throw err;
        }
        const errorMessage =
          err instanceof Error ? err.message : 'Unknown error occurred';
        setError(errorMessage);
        setInitState('error');
      }
    },
    []
  );

  useEffect(
    () =>
      setAPIConfigurationApplyHandler((configuration) =>
        initializeSDK(configuration)
      ),
    [initializeSDK]
  );

  useEffect(() => {
    const timeoutId = setTimeout(() => {
      initializeSDK();
    }, 100);
    return () => clearTimeout(timeoutId);
  }, [initializeSDK]);

  let content: React.ReactNode;
  if (initState === 'loading') {
    content = <IntroScreen />;
  } else if (initState === 'error') {
    content = (
      <InitializationErrorView
        error={error || 'Failed to initialize SDK'}
        onRetry={initializeSDK}
      />
    );
  } else {
    content = <RootNavigator />;
  }

  return (
    <GestureHandlerRootView style={styles.root}>
      <SafeAreaProvider>
        <ThemeProvider>
          <ThemedStatusBar />
          {content}
        </ThemeProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
};

/**
 * Edge-to-edge status bar driven by the theme. System bars are transparent and
 * content draws behind them; only barStyle (icon color) is honored on Android
 * 15+, so it follows light/dark to keep the clock/battery/nav glyphs visible.
 */
const ThemedStatusBar: React.FC = () => {
  const { dark } = useTheme();
  return (
    <StatusBar
      barStyle={dark ? 'light-content' : 'dark-content'}
      backgroundColor="transparent"
      translucent
    />
  );
};

const styles = StyleSheet.create({
  root: {
    flex: 1,
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
