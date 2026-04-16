import React, { useMemo } from 'react';
import { StyleSheet } from 'react-native';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import {
  Eye,
  LayoutGrid,
  MessageCircle,
  Settings as SettingsIcon,
} from 'lucide-react-native';
import type { LucideIcon } from 'lucide-react-native';
import { useTheme } from '../theme';
import { Typography } from '../theme/typography';
import type { RootTabParamList } from '../types';

import ChatScreen from '../screens/ChatScreen';
import VLMScreen from '../screens/VLMScreen';
import MoreStackNavigator from './MoreStackNavigator';
import SettingsScreen from '../screens/SettingsScreen';

const Tab = createBottomTabNavigator<RootTabParamList>();

type TabIconPair = { inactive: LucideIcon; active: LucideIcon };

const tabIcons: Record<keyof RootTabParamList, TabIconPair> = {
  Chat: { inactive: MessageCircle, active: MessageCircle },
  Vision: { inactive: Eye, active: Eye },
  More: { inactive: LayoutGrid, active: LayoutGrid },
  Settings: { inactive: SettingsIcon, active: SettingsIcon },
};

type TabIconProps = {
  routeName: keyof RootTabParamList;
  focused: boolean;
  color: string;
  size: number;
};

const TabIcon: React.FC<TabIconProps> = ({ routeName, focused, color, size }) => {
  const { active, inactive } = tabIcons[routeName];
  const Component = focused ? active : inactive;
  return <Component size={size} color={color} strokeWidth={focused ? 2.4 : 1.8} />;
};

const TabNavigator: React.FC = () => {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();

  const tabBarStyle = useMemo(
    () => ({
      backgroundColor: colors.background,
      borderTopColor: colors.border,
      borderTopWidth: StyleSheet.hairlineWidth,
      height: 58 + insets.bottom,
      paddingBottom: Math.max(insets.bottom, 6),
      paddingTop: 8,
    }),
    [colors.background, colors.border, insets.bottom]
  );

  return (
    <Tab.Navigator
      screenOptions={({ route }) => ({
        headerShown: false,
        tabBarActiveTintColor: colors.primary,
        tabBarInactiveTintColor: colors.textSecondary,
        tabBarStyle,
        tabBarLabelStyle: styles.tabBarLabel,
        tabBarIcon: ({ focused, color, size }) => (
          <TabIcon
            routeName={route.name}
            focused={focused}
            color={color}
            size={size}
          />
        ),
      })}
    >
      <Tab.Screen name="Chat" component={ChatScreen} />
      <Tab.Screen name="Vision" component={VLMScreen} />
      <Tab.Screen name="More" component={MoreStackNavigator} />
      <Tab.Screen name="Settings" component={SettingsScreen} />
    </Tab.Navigator>
  );
};

const styles = StyleSheet.create({
  tabBarLabel: {
    ...Typography.caption2,
    marginTop: 2,
  },
});

export default TabNavigator;
