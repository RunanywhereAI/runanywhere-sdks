/**
 * RootNavigator — the single source of truth for the whole navigation graph.
 * One flat native-stack: the tab bar plus every feature screen as a direct
 * sibling route (reachable in one navigate() call). Global fade transition.
 *
 * Header handling is transitional: screens that already render their own header
 * (Transcribe/Speak/RAG/VAD/Storage/Vision/Settings) keep the stack header hidden
 * — single clean header, and system back (Android button / iOS swipe) pops the
 * stack. The three screens with no own header (VLM/Solutions/Benchmarks) use the
 * stack header for title + back. A unified header lands in each screen's rebuild.
 * Modal routes (ModelSelection/Lora/ConversationList/ChatAnalytics) are declared
 * in the param list and get registered when ChatScreen is rebuilt.
 */
import React from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import type { RootStackParamList } from './navigation.types';
import { ROUTES } from './routes';
import { screenFade } from './transitions';
import { BottomTabs } from './BottomTabs';
import VisionHubScreen from '../screens/VisionHubScreen';
import VLMScreen from '../screens/VLMScreen';
import STTScreen from '../screens/STTScreen';
import TTSScreen from '../screens/TTSScreen';
import VADScreen from '../screens/VADScreen';
import RAGScreen from '../screens/RAGScreen';
import StorageScreen from '../screens/StorageScreen';
import SolutionsScreen from '../screens/SolutionsScreen';
import BenchmarkScreen from '../screens/BenchmarkScreen';
import SettingsScreen from '../screens/SettingsScreen';

const Stack = createNativeStackNavigator<RootStackParamList>();

export const RootNavigator: React.FC = () => (
  <NavigationContainer>
    <Stack.Navigator
      initialRouteName={ROUTES.Tabs}
      screenOptions={{ ...screenFade, headerShown: false }}
    >
      <Stack.Screen name={ROUTES.Tabs} component={BottomTabs} />

      {/* Own-header screens: stack header hidden, system back pops the stack. */}
      <Stack.Screen name={ROUTES.Vision} component={VisionHubScreen} />
      <Stack.Screen name={ROUTES.Transcribe} component={STTScreen} />
      <Stack.Screen name={ROUTES.Speak} component={TTSScreen} />
      <Stack.Screen name={ROUTES.Vad} component={VADScreen} />
      <Stack.Screen name={ROUTES.Rag} component={RAGScreen} />
      <Stack.Screen name={ROUTES.Storage} component={StorageScreen} />
      <Stack.Screen name={ROUTES.Settings} component={SettingsScreen} />

      {/* No own header: stack header provides title + back. */}
      <Stack.Screen
        name={ROUTES.Vlm}
        component={VLMScreen}
        options={{ headerShown: true, title: 'Vision Chat' }}
      />
      <Stack.Screen
        name={ROUTES.Solutions}
        component={SolutionsScreen}
        options={{ headerShown: true, title: 'Solutions' }}
      />
      <Stack.Screen
        name={ROUTES.Benchmarks}
        component={BenchmarkScreen}
        options={{ headerShown: true, title: 'Benchmarks' }}
      />
    </Stack.Navigator>
  </NavigationContainer>
);

export default RootNavigator;
