/**
 * TabNavigator - Bottom Tab Navigation
 *
 * Reference: iOS ContentView.swift with 5 tabs:
 * - Chat (LLM)
 * - STT (Speech-to-Text)
 * - TTS (Text-to-Speech)
 * - Voice (Voice Assistant - STT + LLM + TTS)
 * - Settings
 */

import React from 'react';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import type { RootTabParamList } from '../types';

// Screens
import ChatScreen from '../screens/ChatScreen';
import STTScreen from '../screens/STTScreen';
import TTSScreen from '../screens/TTSScreen';
import VoiceAssistantScreen from '../screens/VoiceAssistantScreen';
import SettingsScreen from '../screens/SettingsScreen';

const Tab = createBottomTabNavigator<RootTabParamList>();

/**
 * Tab icon mapping - matching Swift sample app (ContentView.swift)
 */
const tabIcons: Record<
  keyof RootTabParamList,
  { focused: string; unfocused: string }
> = {
  Chat: { focused: 'chatbubble', unfocused: 'chatbubble-outline' },
  STT: { focused: 'pulse', unfocused: 'pulse-outline' }, // waveform equivalent
  TTS: { focused: 'volume-high', unfocused: 'volume-high-outline' }, // speaker.wave.2
  Voice: { focused: 'mic', unfocused: 'mic-outline' }, // mic for voice assistant
  Settings: { focused: 'settings', unfocused: 'settings-outline' },
};

/**
 * Tab display names - matching iOS Swift sample app (ContentView.swift)
 * iOS uses: Chat, Transcribe, Speak, Voice, Settings
 */
const tabLabels: Record<keyof RootTabParamList, string> = {
  Chat: 'Chat',
  STT: 'Transcribe',
  TTS: 'Speak',
  Voice: 'Voice',
  Settings: 'Settings',
};

/**
 * Stable tab bar icon component to avoid react/no-unstable-nested-components
 */
const renderTabBarIcon = (
  routeName: keyof RootTabParamList,
  focused: boolean,
  color: string,
  size: number
) => {
  const iconName = focused
    ? tabIcons[routeName].focused
    : tabIcons[routeName].unfocused;
  return <Icon name={iconName} size={size} color={color} />;
};

export const TabNavigator: React.FC = () => {
  return (
    <Tab.Navigator
      screenOptions={({ route }) => ({
        tabBarIcon: ({ focused, color, size }) =>
          renderTabBarIcon(route.name, focused, color, size),
        tabBarActiveTintColor: Colors.primaryBlue,
        tabBarInactiveTintColor: Colors.textSecondary,
        tabBarStyle: {
          backgroundColor: Colors.backgroundPrimary,
          borderTopColor: Colors.borderLight,
        },
        tabBarLabelStyle: {
          ...Typography.caption2,
        },
        headerShown: false,
      })}
    >
      {/* Tab 0: Chat (LLM) */}
      <Tab.Screen
        name="Chat"
        component={ChatScreen}
        options={{ tabBarLabel: tabLabels.Chat }}
      />
      {/* Tab 1: Speech-to-Text */}
      <Tab.Screen
        name="STT"
        component={STTScreen}
        options={{ tabBarLabel: tabLabels.STT }}
      />
      {/* Tab 2: Text-to-Speech */}
      <Tab.Screen
        name="TTS"
        component={TTSScreen}
        options={{ tabBarLabel: tabLabels.TTS }}
      />
      {/* Tab 3: Voice Assistant (STT + LLM + TTS) */}
      <Tab.Screen
        name="Voice"
        component={VoiceAssistantScreen}
        options={{ tabBarLabel: tabLabels.Voice }}
      />
      {/* Tab 4: Settings */}
      <Tab.Screen
        name="Settings"
        component={SettingsScreen}
        options={{ tabBarLabel: tabLabels.Settings }}
      />
    </Tab.Navigator>
  );
};

export default TabNavigator;
