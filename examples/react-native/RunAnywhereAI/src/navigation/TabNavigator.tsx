/**
 * TabNavigator - Bottom Tab Navigation
 *
 * Reference: iOS ContentView.swift with 7 tabs:
 * - Food (AI Food Ordering Demo - DoorDash Clone) ⭐ FEATURED
 * - Chat (LLM)
 * - STT (Speech-to-Text)
 * - TTS (Text-to-Speech)
 * - Voice (Voice Assistant - STT + LLM + TTS)
 * - Tools (Tool Calling Demo)
 * - Settings
 */

import React from 'react';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import type { RootTabParamList } from '../types';

// Screens
import FoodOrderScreen from '../screens/FoodOrderScreen';
import ChatScreen from '../screens/ChatScreen';
import STTScreen from '../screens/STTScreen';
import TTSScreen from '../screens/TTSScreen';
import VoiceAssistantScreen from '../screens/VoiceAssistantScreen';
import ToolsScreen from '../screens/ToolsScreen';
import SettingsScreen from '../screens/SettingsScreen';

const Tab = createBottomTabNavigator<RootTabParamList>();

/**
 * Tab icon mapping - matching Swift sample app (ContentView.swift)
 */
const tabIcons: Record<
  keyof RootTabParamList,
  { focused: string; unfocused: string }
> = {
  Food: { focused: 'fast-food', unfocused: 'fast-food-outline' }, // DoorDash clone demo
  Chat: { focused: 'chatbubble', unfocused: 'chatbubble-outline' },
  STT: { focused: 'pulse', unfocused: 'pulse-outline' }, // waveform equivalent
  TTS: { focused: 'volume-high', unfocused: 'volume-high-outline' }, // speaker.wave.2
  Voice: { focused: 'mic', unfocused: 'mic-outline' }, // mic for voice assistant
  Tools: { focused: 'construct', unfocused: 'construct-outline' }, // tool calling demo
  Settings: { focused: 'settings', unfocused: 'settings-outline' },
};

/**
 * Tab display names - matching iOS Swift sample app (ContentView.swift)
 * iOS uses: Food, Chat, Transcribe, Speak, Voice, Tools, Settings
 */
const tabLabels: Record<keyof RootTabParamList, string> = {
  Food: 'Food',
  Chat: 'Chat',
  STT: 'Transcribe',
  TTS: 'Speak',
  Voice: 'Voice',
  Tools: 'Tools',
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
      {/* Tab 0: Food (AI Food Ordering Demo - DoorDash Clone) */}
      <Tab.Screen
        name="Food"
        component={FoodOrderScreen}
        options={{ tabBarLabel: tabLabels.Food }}
      />
      {/* Tab 1: Chat (LLM) */}
      <Tab.Screen
        name="Chat"
        component={ChatScreen}
        options={{ tabBarLabel: tabLabels.Chat }}
      />
      {/* Tab 2: Speech-to-Text */}
      <Tab.Screen
        name="STT"
        component={STTScreen}
        options={{ tabBarLabel: tabLabels.STT }}
      />
      {/* Tab 3: Text-to-Speech */}
      <Tab.Screen
        name="TTS"
        component={TTSScreen}
        options={{ tabBarLabel: tabLabels.TTS }}
      />
      {/* Tab 4: Voice Assistant (STT + LLM + TTS) */}
      <Tab.Screen
        name="Voice"
        component={VoiceAssistantScreen}
        options={{ tabBarLabel: tabLabels.Voice }}
      />
      {/* Tab 5: Tools (Tool Calling Demo) */}
      <Tab.Screen
        name="Tools"
        component={ToolsScreen}
        options={{ tabBarLabel: tabLabels.Tools }}
      />
      {/* Tab 6: Settings */}
      <Tab.Screen
        name="Settings"
        component={SettingsScreen}
        options={{ tabBarLabel: tabLabels.Settings }}
      />
    </Tab.Navigator>
  );
};

export default TabNavigator;
