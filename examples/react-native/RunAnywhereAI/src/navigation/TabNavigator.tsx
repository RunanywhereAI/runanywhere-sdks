/**
 * TabNavigator - Bottom Tab Navigation
 *
 * Reference: iOS ContentView.swift with 5 tabs:
 * - Chat
 * - Vision
 * - Voice
 * - More
 * - Settings
 */

import React from 'react';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import type {
  MoreStackParamList,
  RootTabParamList,
  VisionStackParamList,
} from '../types';

import ChatScreen from '../screens/ChatScreen';
import STTScreen from '../screens/STTScreen';
import TTSScreen from '../screens/TTSScreen';
import VoiceAssistantScreen from '../screens/VoiceAssistantScreen';
import RAGScreen from '../screens/RAGScreen';
import SolutionsScreen from '../screens/SolutionsScreen';
import MoreScreen from '../screens/MoreScreen';
import StorageScreen from '../screens/StorageScreen';
import VADScreen from '../screens/VADScreen';
import VisionHubScreen from '../screens/VisionHubScreen';
import VLMScreen from '../screens/VLMScreen';
import SettingsScreen from '../screens/SettingsScreen';

const Tab = createBottomTabNavigator<RootTabParamList>();
const VisionStack = createNativeStackNavigator<VisionStackParamList>();
const MoreStack = createNativeStackNavigator<MoreStackParamList>();

const tabIcons: Record<
  keyof RootTabParamList,
  { focused: string; unfocused: string }
> = {
  Chat: { focused: 'chatbubble', unfocused: 'chatbubble-outline' },
  Vision: { focused: 'eye', unfocused: 'eye-outline' },
  Voice: { focused: 'mic', unfocused: 'mic-outline' },
  More: {
    focused: 'ellipsis-horizontal',
    unfocused: 'ellipsis-horizontal-outline',
  },
  Settings: { focused: 'settings', unfocused: 'settings-outline' },
};

const tabLabels: Record<keyof RootTabParamList, string> = {
  Chat: 'Chat',
  Vision: 'Vision',
  Voice: 'Voice',
  More: 'More',
  Settings: 'Settings',
};

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
      <Tab.Screen
        name="Chat"
        component={ChatScreen}
        options={{ tabBarLabel: tabLabels.Chat }}
      />
      <Tab.Screen
        name="Vision"
        component={VisionStackScreen}
        options={{ tabBarLabel: tabLabels.Vision }}
      />
      <Tab.Screen
        name="Voice"
        component={VoiceAssistantScreen}
        options={{ tabBarLabel: tabLabels.Voice }}
      />
      <Tab.Screen
        name="More"
        component={MoreStackScreen}
        options={{ tabBarLabel: tabLabels.More }}
      />
      <Tab.Screen
        name="Settings"
        component={SettingsScreen}
        options={{ tabBarLabel: tabLabels.Settings }}
      />
    </Tab.Navigator>
  );
};

const VisionStackScreen: React.FC = () => {
  return (
    <VisionStack.Navigator
      screenOptions={{ headerShown: true }}
      initialRouteName="VisionHub"
    >
      <VisionStack.Screen
        name="VisionHub"
        component={VisionHubScreen}
        options={{ title: 'Vision' }}
      />
      <VisionStack.Screen
        name="VLM"
        component={VLMScreen}
        options={{ title: 'Vision Chat (VLM)' }}
      />
    </VisionStack.Navigator>
  );
};

const MoreStackScreen: React.FC = () => {
  return (
    <MoreStack.Navigator
      screenOptions={{ headerShown: true }}
      initialRouteName="MoreHome"
    >
      <MoreStack.Screen
        name="MoreHome"
        component={MoreScreen}
        options={{ headerShown: false }}
      />
      <MoreStack.Screen
        name="STT"
        component={STTScreen}
        options={{ title: 'Transcribe' }}
      />
      <MoreStack.Screen
        name="TTS"
        component={TTSScreen}
        options={{ title: 'Speak' }}
      />
      <MoreStack.Screen
        name="RAG"
        component={RAGScreen}
        options={{ title: 'RAG' }}
      />
      <MoreStack.Screen
        name="VAD"
        component={VADScreen}
        options={{ title: 'Voice Activity' }}
      />
      <MoreStack.Screen
        name="Storage"
        component={StorageScreen}
        options={{ title: 'Storage' }}
      />
      <MoreStack.Screen
        name="Solutions"
        component={SolutionsScreen}
        options={{ title: 'Solutions' }}
      />
    </MoreStack.Navigator>
  );
};

export default TabNavigator;
