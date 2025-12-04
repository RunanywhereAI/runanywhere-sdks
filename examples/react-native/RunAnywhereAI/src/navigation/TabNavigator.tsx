/**
 * TabNavigator - Bottom Tab Navigation
 *
 * Reference: iOS ContentView with 6 tabs (Chat, STT, TTS, Quiz, Voice, Settings)
 */

import React from 'react';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { RootTabParamList } from '../types';

// Screens
import ChatScreen from '../screens/ChatScreen';
import STTScreen from '../screens/STTScreen';
import TTSScreen from '../screens/TTSScreen';
import QuizScreen from '../screens/QuizScreen';
import VoiceAssistantScreen from '../screens/VoiceAssistantScreen';
import SettingsScreen from '../screens/SettingsScreen';

const Tab = createBottomTabNavigator<RootTabParamList>();

/**
 * Tab icon mapping
 */
const tabIcons: Record<keyof RootTabParamList, { focused: string; unfocused: string }> = {
  Chat: { focused: 'chatbubble', unfocused: 'chatbubble-outline' },
  STT: { focused: 'mic', unfocused: 'mic-outline' },
  TTS: { focused: 'volume-high', unfocused: 'volume-high-outline' },
  Quiz: { focused: 'school', unfocused: 'school-outline' },
  VoiceAssistant: { focused: 'person-circle', unfocused: 'person-circle-outline' },
  Settings: { focused: 'settings', unfocused: 'settings-outline' },
};

/**
 * Tab display names
 */
const tabLabels: Record<keyof RootTabParamList, string> = {
  Chat: 'Chat',
  STT: 'Speech',
  TTS: 'Voice',
  Quiz: 'Quiz',
  VoiceAssistant: 'Assistant',
  Settings: 'Settings',
};

export const TabNavigator: React.FC = () => {
  return (
    <Tab.Navigator
      screenOptions={({ route }) => ({
        tabBarIcon: ({ focused, color, size }) => {
          const iconName = focused
            ? tabIcons[route.name].focused
            : tabIcons[route.name].unfocused;
          return <Icon name={iconName} size={size} color={color} />;
        },
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
      <Tab.Screen
        name="Chat"
        component={ChatScreen}
        options={{ tabBarLabel: tabLabels.Chat }}
      />
      <Tab.Screen
        name="STT"
        component={STTScreen}
        options={{ tabBarLabel: tabLabels.STT }}
      />
      <Tab.Screen
        name="TTS"
        component={TTSScreen}
        options={{ tabBarLabel: tabLabels.TTS }}
      />
      <Tab.Screen
        name="Quiz"
        component={QuizScreen}
        options={{ tabBarLabel: tabLabels.Quiz }}
      />
      <Tab.Screen
        name="VoiceAssistant"
        component={VoiceAssistantScreen}
        options={{ tabBarLabel: tabLabels.VoiceAssistant }}
      />
      <Tab.Screen
        name="Settings"
        component={SettingsScreen}
        options={{ tabBarLabel: tabLabels.Settings }}
      />
    </Tab.Navigator>
  );
};

export default TabNavigator;
