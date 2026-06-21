/**
 * Bottom tab bar — the only navigator container in the graph. Three sections:
 * Chat, Voice, More (More is the hub to every other screen). Tab changes fade.
 */
import React from 'react';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { Typography } from '../theme/typography';
import { Icon, type IconName, useTheme } from '../theme/system';
import type { TabParamList } from './navigation.types';
import { ROUTES } from './routes';
import ChatScreen from '../screens/ChatScreen';
import VoiceAssistantScreen from '../screens/VoiceAssistantScreen';
import MoreScreen from '../screens/MoreScreen';

const Tab = createBottomTabNavigator<TabParamList>();

const TAB_ICONS: Record<keyof TabParamList, IconName> = {
  Chat: 'chat',
  Voice: 'voice',
  More: 'more',
};

export const BottomTabs: React.FC = () => {
  const { colors } = useTheme();
  return (
    <Tab.Navigator
      screenOptions={({ route }) => ({
        headerShown: false,
        animation: 'fade',
        tabBarActiveTintColor: colors.primary,
        tabBarInactiveTintColor: colors.onSurfaceVariant,
        tabBarStyle: {
          backgroundColor: colors.surface,
          borderTopColor: colors.outlineVariant,
        },
        tabBarLabelStyle: { ...Typography.caption2 },
        tabBarIcon: ({ color, size }) => (
          <Icon name={TAB_ICONS[route.name]} size={size} color={color} />
        ),
      })}
    >
    <Tab.Screen
      name={ROUTES.Chat}
      component={ChatScreen}
      options={{ tabBarLabel: 'Chat' }}
    />
    <Tab.Screen
      name={ROUTES.Voice}
      component={VoiceAssistantScreen}
      options={{ tabBarLabel: 'Voice' }}
    />
    <Tab.Screen
      name={ROUTES.More}
      component={MoreScreen}
      options={{ tabBarLabel: 'More' }}
    />
    </Tab.Navigator>
  );
};

export default BottomTabs;
