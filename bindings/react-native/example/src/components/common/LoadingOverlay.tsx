/**
 * LoadingOverlay Component
 *
 * Full-screen loading overlay with optional progress.
 *
 * Reference: iOS loading states
 */

import React from 'react';
import { View, Text, StyleSheet, ActivityIndicator, Modal } from 'react-native';
import {
  typography,
  useTheme,
  useThemedStyles,
  type ColorScheme,
} from '../../theme/system';

interface LoadingOverlayProps {
  /** Whether to show the overlay */
  visible: boolean;
  /** Loading message */
  message?: string;
  /** Progress (0-1), shows progress bar if provided */
  progress?: number;
  /** Whether to use modal (blocks interaction) */
  modal?: boolean;
}

export const LoadingOverlay: React.FC<LoadingOverlayProps> = ({
  visible,
  message = 'Loading...',
  progress,
  modal = true,
}) => {
  const { colors } = useTheme();
  const styles = useThemedStyles(createStyles);

  if (!visible) {
    return null;
  }

  const content = (
    <View style={styles.container}>
      <View style={styles.card}>
        <ActivityIndicator size="large" color={colors.primary} />

        {message && <Text style={styles.message}>{message}</Text>}

        {progress !== undefined && (
          <View style={styles.progressContainer}>
            <View style={styles.progressBar}>
              <View
                style={[styles.progressFill, { width: `${progress * 100}%` }]}
              />
            </View>
            <Text style={styles.progressText}>
              {Math.round(progress * 100)}%
            </Text>
          </View>
        )}
      </View>
    </View>
  );

  if (modal) {
    return (
      <Modal transparent visible={visible} animationType="fade">
        {content}
      </Modal>
    );
  }

  return content;
};

const createStyles = (colors: ColorScheme) =>
  StyleSheet.create({
    container: {
      ...StyleSheet.absoluteFill,
      backgroundColor: 'rgba(0, 0, 0, 0.3)',
      justifyContent: 'center',
      alignItems: 'center',
    },
    card: {
      backgroundColor: colors.surface,
      borderRadius: 16,
      padding: 30,
      alignItems: 'center',
      minWidth: 200,
      shadowColor: '#000',
      shadowOffset: { width: 0, height: 4 },
      shadowOpacity: 0.15,
      shadowRadius: 12,
      elevation: 8,
    },
    message: {
      ...typography.bodyLarge,
      color: colors.onSurface,
      marginTop: 16,
      textAlign: 'center',
    },
    progressContainer: {
      width: '100%',
      marginTop: 16,
      alignItems: 'center',
    },
    progressBar: {
      width: '100%',
      height: 6,
      backgroundColor: colors.surfaceContainerHighest,
      borderRadius: 3,
      overflow: 'hidden',
    },
    progressFill: {
      height: '100%',
      backgroundColor: colors.primary,
      borderRadius: 3,
    },
    progressText: {
      ...typography.bodySmall,
      color: colors.onSurfaceVariant,
      marginTop: 6,
    },
  });

export default LoadingOverlay;
