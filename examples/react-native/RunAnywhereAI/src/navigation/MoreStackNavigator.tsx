import React from 'react';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { useTheme } from '../theme';
import type { MoreStackParamList } from '../types';
import MoreScreen from '../screens/MoreScreen';
import STTScreen from '../screens/STTScreen';
import TTSScreen from '../screens/TTSScreen';
import VoiceAssistantScreen from '../screens/VoiceAssistantScreen';
import RAGScreen from '../screens/RAGScreen';
import ModelsScreen from '../screens/ModelsScreen';

const Stack = createNativeStackNavigator<MoreStackParamList>();

const MoreStackNavigator: React.FC = () => {
  const { colors } = useTheme();
  return (
    <Stack.Navigator
      screenOptions={{
        headerStyle: { backgroundColor: colors.background },
        headerTintColor: colors.text,
        headerTitleStyle: { color: colors.text },
        contentStyle: { backgroundColor: colors.background },
      }}
    >
      <Stack.Screen
        name="MoreHome"
        component={MoreScreen}
        options={{ title: 'More', headerShown: false }}
      />
      <Stack.Screen
        name="STT"
        component={STTScreen}
        options={{ title: 'Speech to Text' }}
      />
      <Stack.Screen
        name="TTS"
        component={TTSScreen}
        options={{ title: 'Text to Speech' }}
      />
      <Stack.Screen
        name="Voice"
        component={VoiceAssistantScreen}
        options={{ title: 'Voice Assistant' }}
      />
      <Stack.Screen
        name="RAG"
        component={RAGScreen}
        options={{ title: 'Document Q&A' }}
      />
      <Stack.Screen
        name="Models"
        component={ModelsScreen}
        options={{ title: 'Models' }}
      />
    </Stack.Navigator>
  );
};

export default MoreStackNavigator;
