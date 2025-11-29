/**
 * RunAnywhere AI Example App
 *
 * React Native demonstration app for the RunAnywhere on-device AI SDK.
 *
 * Reference: iOS RunAnywhereAIApp.swift
 */

import React, { useEffect, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ActivityIndicator,
  TouchableOpacity,
} from 'react-native';
import { NavigationContainer } from '@react-navigation/native';
import Icon from 'react-native-vector-icons/Ionicons';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import TabNavigator from './src/navigation/TabNavigator';
import { Colors } from './src/theme/colors';
import { Typography } from './src/theme/typography';
import { Spacing, Padding, BorderRadius, IconSize, ButtonHeight } from './src/theme/spacing';
import MockSDK from './src/services/MockSDK';

/**
 * App initialization state
 */
type InitState = 'loading' | 'ready' | 'error';

/**
 * Initialization Loading View
 */
const InitializationLoadingView: React.FC = () => (
  <View style={styles.loadingContainer}>
    <View style={styles.loadingContent}>
      <View style={styles.iconContainer}>
        <Icon name="hardware-chip-outline" size={48} color={Colors.primaryBlue} />
      </View>
      <Text style={styles.loadingTitle}>RunAnywhere AI</Text>
      <Text style={styles.loadingSubtitle}>Initializing SDK...</Text>
      <ActivityIndicator
        size="large"
        color={Colors.primaryBlue}
        style={styles.spinner}
      />
    </View>
  </View>
);

/**
 * Initialization Error View
 */
const InitializationErrorView: React.FC<{ error: string; onRetry: () => void }> = ({
  error,
  onRetry,
}) => (
  <View style={styles.errorContainer}>
    <View style={styles.errorContent}>
      <View style={styles.errorIconContainer}>
        <Icon name="alert-circle-outline" size={48} color={Colors.primaryRed} />
      </View>
      <Text style={styles.errorTitle}>Initialization Failed</Text>
      <Text style={styles.errorMessage}>{error}</Text>
      <TouchableOpacity style={styles.retryButton} onPress={onRetry}>
        <Icon name="refresh" size={20} color={Colors.textWhite} />
        <Text style={styles.retryButtonText}>Retry</Text>
      </TouchableOpacity>
    </View>
  </View>
);

/**
 * Main App Component
 */
const App: React.FC = () => {
  const [initState, setInitState] = useState<InitState>('loading');
  const [error, setError] = useState<string | null>(null);

  /**
   * Initialize the SDK
   * TODO: Replace with actual RunAnywhere SDK initialization
   */
  const initializeSDK = async () => {
    setInitState('loading');
    setError(null);

    try {
      // TODO: Replace with actual SDK initialization
      // await RunAnywhere.initialize({
      //   apiKey: 'your-api-key',
      //   baseURL: 'https://api.runanywhere.com',
      //   environment: SDKEnvironment.Production,
      // });

      await MockSDK.initialize('mock-api-key');
      setInitState('ready');
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : 'Unknown error occurred';
      setError(errorMessage);
      setInitState('error');
    }
  };

  useEffect(() => {
    initializeSDK();
  }, []);

  // Render based on state
  if (initState === 'loading') {
    return (
      <SafeAreaProvider>
        <InitializationLoadingView />
      </SafeAreaProvider>
    );
  }

  if (initState === 'error') {
    return (
      <SafeAreaProvider>
        <InitializationErrorView
          error={error || 'Failed to initialize SDK'}
          onRetry={initializeSDK}
        />
      </SafeAreaProvider>
    );
  }

  return (
    <SafeAreaProvider>
      <NavigationContainer>
        <TabNavigator />
      </NavigationContainer>
    </SafeAreaProvider>
  );
};

const styles = StyleSheet.create({
  // Loading View
  loadingContainer: {
    flex: 1,
    backgroundColor: Colors.backgroundPrimary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  loadingContent: {
    alignItems: 'center',
  },
  iconContainer: {
    width: IconSize.huge,
    height: IconSize.huge,
    borderRadius: IconSize.huge / 2,
    backgroundColor: Colors.badgeBlue,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: Spacing.xLarge,
  },
  loadingTitle: {
    ...Typography.title,
    color: Colors.textPrimary,
    marginBottom: Spacing.small,
  },
  loadingSubtitle: {
    ...Typography.body,
    color: Colors.textSecondary,
    marginBottom: Spacing.xLarge,
  },
  spinner: {
    marginTop: Spacing.large,
  },

  // Error View
  errorContainer: {
    flex: 1,
    backgroundColor: Colors.backgroundPrimary,
    justifyContent: 'center',
    alignItems: 'center',
    padding: Padding.padding24,
  },
  errorContent: {
    alignItems: 'center',
    maxWidth: 300,
  },
  errorIconContainer: {
    width: IconSize.huge,
    height: IconSize.huge,
    borderRadius: IconSize.huge / 2,
    backgroundColor: Colors.badgeRed,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: Spacing.xLarge,
  },
  errorTitle: {
    ...Typography.title2,
    color: Colors.textPrimary,
    marginBottom: Spacing.medium,
  },
  errorMessage: {
    ...Typography.body,
    color: Colors.textSecondary,
    textAlign: 'center',
    marginBottom: Spacing.xLarge,
  },
  retryButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: Spacing.smallMedium,
    backgroundColor: Colors.primaryBlue,
    paddingHorizontal: Padding.padding24,
    height: ButtonHeight.regular,
    borderRadius: BorderRadius.large,
  },
  retryButtonText: {
    ...Typography.headline,
    color: Colors.textWhite,
  },
});

export default App;
