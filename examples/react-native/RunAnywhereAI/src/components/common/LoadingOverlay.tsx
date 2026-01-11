/**
 * LoadingOverlay Component
 *
 * Full-screen loading overlay with optional progress.
 *
 * Reference: iOS loading states
 */

import React from 'react';
import { View, Text, StyleSheet, ActivityIndicator, Modal } from 'react-native';
import { Colors } from '../../theme/colors';
import { Typography } from '../../theme/typography';
import { Spacing, BorderRadius, Padding } from '../../theme/spacing';

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
  if (!visible) {
    return null;
  }

  const content = (
    <View style={styles.container}>
      <View style={styles.card}>
        <ActivityIndicator size="large" color={Colors.primaryBlue} />

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

const styles = StyleSheet.create({
  container: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: Colors.overlayLight,
    justifyContent: 'center',
    alignItems: 'center',
  },
  card: {
    backgroundColor: Colors.backgroundPrimary,
    borderRadius: BorderRadius.xLarge,
    padding: Padding.padding30,
    alignItems: 'center',
    minWidth: 200,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.15,
    shadowRadius: 12,
    elevation: 8,
  },
  message: {
    ...Typography.body,
    color: Colors.textPrimary,
    marginTop: Spacing.large,
    textAlign: 'center',
  },
  progressContainer: {
    width: '100%',
    marginTop: Spacing.large,
    alignItems: 'center',
  },
  progressBar: {
    width: '100%',
    height: 6,
    backgroundColor: Colors.backgroundGray5,
    borderRadius: 3,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    backgroundColor: Colors.primaryBlue,
    borderRadius: 3,
  },
  progressText: {
    ...Typography.caption,
    color: Colors.textSecondary,
    marginTop: Spacing.small,
  },
});

export default LoadingOverlay;
