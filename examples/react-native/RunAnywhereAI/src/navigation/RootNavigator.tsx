import React from 'react';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { useTheme } from '../theme';
import type { RootStackParamList } from '../types';
import TabNavigator from './TabNavigator';
import ConversationListScreen from '../screens/ConversationListScreen';
import ChatAnalyticsScreen from '../screens/ChatAnalyticsScreen';

const Stack = createNativeStackNavigator<RootStackParamList>();

const RootNavigator: React.FC = () => {
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
        name="MainTabs"
        component={TabNavigator}
        options={{ headerShown: false }}
      />
      <Stack.Screen
        name="ConversationList"
        component={ConversationListScreen}
        options={{ presentation: 'modal', title: 'Conversations' }}
      />
      <Stack.Screen
        name="ChatAnalytics"
        component={ChatAnalyticsScreen}
        options={{ presentation: 'modal', title: 'Analytics' }}
      />
    </Stack.Navigator>
  );
};

export default RootNavigator;
