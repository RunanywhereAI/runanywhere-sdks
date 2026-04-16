import React from 'react';
import {
  ActivityIndicator,
  Modal,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useTheme } from '../../theme';
import { Typography } from '../../theme/typography';
import { BorderRadius, Padding, Spacing } from '../../theme/spacing';

interface LoadingOverlayProps {
  visible: boolean;
  message?: string;
  progress?: number;
  modal?: boolean;
}

export const LoadingOverlay: React.FC<LoadingOverlayProps> = ({
  visible,
  message = 'Loading…',
  progress,
  modal = true,
}) => {
  const { colors } = useTheme();
  if (!visible) return null;

  const content = (
    <View style={[styles.container, { backgroundColor: colors.overlay }]}>
      <View
        style={[
          styles.card,
          { backgroundColor: colors.surfaceRaised, shadowColor: colors.shadow },
        ]}
      >
        <ActivityIndicator size="large" color={colors.primary} />
        {message ? (
          <Text style={[Typography.body, styles.message, { color: colors.text }]}>
            {message}
          </Text>
        ) : null}
        {progress !== undefined ? (
          <View style={styles.progressContainer}>
            <View
              style={[styles.progressBar, { backgroundColor: colors.surfaceAlt }]}
            >
              <View
                style={[
                  styles.progressFill,
                  {
                    backgroundColor: colors.primary,
                    width: `${progress * 100}%`,
                  },
                ]}
              />
            </View>
            <Text
              style={[
                Typography.caption,
                styles.progressText,
                { color: colors.textSecondary },
              ]}
            >
              {Math.round(progress * 100)}%
            </Text>
          </View>
        ) : null}
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
    justifyContent: 'center',
    alignItems: 'center',
  },
  card: {
    borderRadius: BorderRadius.xLarge,
    padding: Padding.padding30,
    alignItems: 'center',
    minWidth: 200,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.15,
    shadowRadius: 12,
    elevation: 8,
  },
  message: {
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
    borderRadius: 3,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    borderRadius: 3,
  },
  progressText: {
    marginTop: Spacing.small,
  },
});

export default LoadingOverlay;
