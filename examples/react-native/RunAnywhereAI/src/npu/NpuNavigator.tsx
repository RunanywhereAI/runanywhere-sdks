/**
 * Self-contained NPU (QHexRT) section — a nested native stack reached from the
 * app's More → NPU entry. Home is the section root; each modality is pushed.
 * No NavigationContainer here (the app's RootNavigator already provides one).
 */
import React from 'react';
import { createNativeStackNavigator } from '@react-navigation/native-stack';

import { NpuStackParamList } from './navTypes';
import HomeScreen from './screens/HomeScreen';
import LlmScreen from './screens/LlmScreen';
import VlmScreen from './screens/VlmScreen';
import SttScreen from './screens/SttScreen';
import TtsScreen from './screens/TtsScreen';

const Stack = createNativeStackNavigator<NpuStackParamList>();

export const NpuNavigator: React.FC = () => (
  <Stack.Navigator screenOptions={{ headerShown: false }}>
    <Stack.Screen name="Home" component={HomeScreen} />
    <Stack.Screen name="Llm" component={LlmScreen} />
    <Stack.Screen name="Vlm" component={VlmScreen} />
    <Stack.Screen name="Stt" component={SttScreen} />
    <Stack.Screen name="Tts" component={TtsScreen} />
  </Stack.Navigator>
);

export default NpuNavigator;
