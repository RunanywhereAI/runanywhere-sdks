/**
 * RunAnywhere NPU - React Native demo
 *
 * Mirrors the Kotlin/Flutter RunAnywhereAiNPU apps: a QHexRT (Qualcomm Hexagon
 * NPU) only demo. On launch it initializes the core SDK, registers the QHexRT
 * backend, and runs a pre-flight NPU capability probe so unsupported devices
 * (non-v79/v81 Hexagon) are warned up front.
 */
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { View, Text, StyleSheet, ActivityIndicator, StatusBar, useColorScheme } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { NavigationContainer, DefaultTheme, DarkTheme } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';

import { RunAnywhere, SDKEnvironment } from '@runanywhere/core';
import { QHexRT, NpuInfo, UNKNOWN_NPU_INFO } from '@runanywhere/qhexrt';

import { AppStateContext, InitState } from './src/AppState';
import { useAppColors } from './src/theme';
import { PrimaryButton } from './src/widgets';
import HomeScreen from './src/screens/HomeScreen';
import LlmScreen from './src/screens/LlmScreen';
import VlmScreen from './src/screens/VlmScreen';
import SttScreen from './src/screens/SttScreen';
import TtsScreen from './src/screens/TtsScreen';
import ModelsScreen from './src/screens/ModelsScreen';

// Default development backend (mirrors the sibling RN example app).
const DEFAULT_BASE_URL = 'https://runanywhere-backend-development.up.railway.app';
const DEFAULT_API_KEY = 'runa_prod_f_sf4FrG4LhuUia4vupidcuIx5fD0t-usz2eNqKBeQw';

export type RootStackParamList = {
  Home: undefined;
  Llm: undefined;
  Vlm: undefined;
  Stt: undefined;
  Tts: undefined;
  Models: undefined;
};

const Stack = createNativeStackNavigator<RootStackParamList>();

const LoadingView: React.FC = () => {
  const c = useAppColors();
  return (
    <View style={[styles.center, { backgroundColor: c.background }]}>
      <ActivityIndicator size="large" color={c.primary} />
      <Text style={[styles.loadingText, { color: c.onSurfaceVariant }]}>Initializing NPU runtime…</Text>
    </View>
  );
};

const ErrorView: React.FC<{ error: string; onRetry: () => void }> = ({ error, onRetry }) => {
  const c = useAppColors();
  return (
    <View style={[styles.center, { backgroundColor: c.background, padding: 24 }]}>
      <Text style={[styles.errTitle, { color: c.error }]}>Initialization failed</Text>
      <Text style={[styles.errMsg, { color: c.onSurfaceVariant }]}>{error}</Text>
      <View style={{ height: 24 }} />
      <PrimaryButton label="Retry" onPress={onRetry} />
    </View>
  );
};

const App: React.FC = () => {
  const scheme = useColorScheme();
  const [initState, setInitState] = useState<InitState>('loading');
  const [error, setError] = useState<string | null>(null);
  const [npu, setNpu] = useState<NpuInfo>(UNKNOWN_NPU_INFO);
  const [qhexrtRegistered, setQhexrtRegistered] = useState(false);
  const [sdkVersion, setSdkVersion] = useState('');

  const initialize = useCallback(async () => {
    setInitState('loading');
    setError(null);
    try {
      // Pre-flight NPU probe first (no QNN load) so the home screen can warn
      // unsupported devices even if registration later fails.
      const probed = await QHexRT.probeNpu();
      setNpu(probed);

      await RunAnywhere.initialize({
        apiKey: DEFAULT_API_KEY,
        baseURL: DEFAULT_BASE_URL,
        environment: SDKEnvironment.SDK_ENVIRONMENT_STAGING,
      });

      const registered = await QHexRT.register();
      setQhexrtRegistered(registered);

      try {
        await RunAnywhere.refreshModelRegistry();
      } catch {
        // Non-fatal: model registry refresh needs network; the app still runs.
      }

      setSdkVersion(RunAnywhere.version);
      setInitState('ready');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error');
      setInitState('error');
    }
  }, []);

  useEffect(() => {
    const id = setTimeout(initialize, 100);
    return () => clearTimeout(id);
  }, [initialize]);

  const stateValue = useMemo(
    () => ({ initState, error, npu, qhexrtRegistered, sdkVersion }),
    [initState, error, npu, qhexrtRegistered, sdkVersion]
  );

  let content: React.ReactNode;
  if (initState === 'loading') {
    content = <LoadingView />;
  } else if (initState === 'error') {
    content = <ErrorView error={error ?? 'Failed to initialize'} onRetry={initialize} />;
  } else {
    content = (
      <NavigationContainer theme={scheme === 'dark' ? DarkTheme : DefaultTheme}>
        <Stack.Navigator screenOptions={{ headerShown: false }}>
          <Stack.Screen name="Home" component={HomeScreen} />
          <Stack.Screen name="Llm" component={LlmScreen} />
          <Stack.Screen name="Vlm" component={VlmScreen} />
          <Stack.Screen name="Stt" component={SttScreen} />
          <Stack.Screen name="Tts" component={TtsScreen} />
          <Stack.Screen name="Models" component={ModelsScreen} />
        </Stack.Navigator>
      </NavigationContainer>
    );
  }

  return (
    <GestureHandlerRootView style={styles.root}>
      <SafeAreaProvider>
        <StatusBar
          barStyle={scheme === 'dark' ? 'light-content' : 'dark-content'}
          backgroundColor="transparent"
          translucent
        />
        <AppStateContext.Provider value={stateValue}>{content}</AppStateContext.Provider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
};

const styles = StyleSheet.create({
  root: { flex: 1 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  loadingText: { marginTop: 16, fontSize: 15 },
  errTitle: { fontSize: 20, fontWeight: '700', marginBottom: 8 },
  errMsg: { fontSize: 14, textAlign: 'center' },
});

export default App;
