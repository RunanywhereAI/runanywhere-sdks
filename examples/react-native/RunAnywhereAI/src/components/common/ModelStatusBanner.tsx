/**
 * ModelStatusBanner Component
 *
 * Shows the current model status with options to select or change model.
 *
 * Reference: iOS ModelStatusBanner equivalent
 */

import React from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import {
  typography,
  useTheme,
  useThemedStyles,
  type ColorScheme,
} from '../../theme/system';
import type { InferenceFramework } from '@runanywhere/proto-ts/model_types';
import { RunAnywhere } from '@runanywhere/core';
import { getFrameworkColor, getFrameworkIcon } from '../../utils/modelDisplay';

interface ModelStatusBannerProps {
  /** Model name if loaded */
  modelName?: string;
  /** Framework being used */
  framework?: InferenceFramework;
  /** Whether model is loading */
  isLoading?: boolean;
  /** Loading progress (0-1) */
  loadProgress?: number;
  /** Callback when select/change button pressed */
  onSelectModel: () => void;
  /** Placeholder text when no model */
  placeholder?: string;
}

export const ModelStatusBanner: React.FC<ModelStatusBannerProps> = ({
  modelName,
  framework,
  isLoading = false,
  loadProgress,
  onSelectModel,
  placeholder = 'Select a model to get started',
}) => {
  const { colors } = useTheme();
  const styles = useThemedStyles(createStyles);

  // Loading state
  if (isLoading) {
    return (
      <View style={styles.container}>
        <View style={styles.loadingContent}>
          <ActivityIndicator size="small" color={colors.primary} />
          <Text style={styles.loadingText}>
            Loading model...
            {loadProgress !== undefined &&
              ` ${Math.round(loadProgress * 100)}%`}
          </Text>
        </View>
        {loadProgress !== undefined && (
          <View style={styles.progressBar}>
            <View
              style={[styles.progressFill, { width: `${loadProgress * 100}%` }]}
            />
          </View>
        )}
      </View>
    );
  }

  // No model state
  if (!modelName || !framework) {
    return (
      <TouchableOpacity
        style={[styles.container, styles.emptyContainer]}
        onPress={onSelectModel}
        activeOpacity={0.7}
      >
        <View style={styles.emptyContent}>
          <Icon name="add-circle-outline" size={20} color={colors.primary} />
          <Text style={styles.emptyText}>{placeholder}</Text>
        </View>
        <View style={styles.selectButton}>
          <Text style={styles.selectButtonText}>Select Model</Text>
          <Icon name="chevron-forward" size={16} color={colors.primary} />
        </View>
      </TouchableOpacity>
    );
  }

  // Model loaded state
  const frameworkColor = getFrameworkColor(framework);
  const frameworkIcon = getFrameworkIcon(framework);
  const frameworkName = RunAnywhere.formatFramework(framework);

  return (
    <View style={styles.container}>
      <View style={styles.loadedContent}>
        {/* Framework Badge */}
        <View
          style={[
            styles.frameworkBadge,
            { backgroundColor: `${frameworkColor}20` },
          ]}
        >
          <Icon name={frameworkIcon} size={14} color={frameworkColor} />
          <Text style={[styles.frameworkText, { color: frameworkColor }]}>
            {frameworkName}
          </Text>
        </View>

        {/* Model Name */}
        <Text style={styles.modelName} numberOfLines={1}>
          {modelName}
        </Text>
      </View>

      {/* Change Button */}
      <TouchableOpacity
        style={styles.changeButton}
        onPress={onSelectModel}
        activeOpacity={0.7}
      >
        <Text style={styles.changeButtonText}>Change</Text>
      </TouchableOpacity>
    </View>
  );
};

const createStyles = (colors: ColorScheme) =>
  StyleSheet.create({
    container: {
      backgroundColor: colors.surfaceContainer,
      borderRadius: 10,
      padding: 12,
      marginHorizontal: 16,
      marginVertical: 6,
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
    },
    emptyContainer: {
      borderWidth: 1,
      borderColor: colors.outlineVariant,
      borderStyle: 'dashed',
    },
    emptyContent: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 8,
    },
    emptyText: {
      ...typography.bodyMedium,
      color: colors.onSurfaceVariant,
    },
    selectButton: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 4,
    },
    selectButtonText: {
      ...typography.bodyMedium,
      color: colors.primary,
      fontWeight: '600',
    },
    loadingContent: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 8,
      flex: 1,
    },
    loadingText: {
      ...typography.bodyMedium,
      color: colors.onSurfaceVariant,
    },
    progressBar: {
      position: 'absolute',
      bottom: 0,
      left: 0,
      right: 0,
      height: 3,
      backgroundColor: colors.surfaceContainerHighest,
      borderBottomLeftRadius: 10,
      borderBottomRightRadius: 10,
      overflow: 'hidden',
    },
    progressFill: {
      height: '100%',
      backgroundColor: colors.primary,
    },
    loadedContent: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 8,
      flex: 1,
    },
    frameworkBadge: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 4,
      paddingHorizontal: 8,
      paddingVertical: 4,
      borderRadius: 4,
    },
    frameworkText: {
      ...typography.bodySmall,
      fontWeight: '600',
    },
    modelName: {
      ...typography.bodyMedium,
      color: colors.onSurface,
      flex: 1,
    },
    changeButton: {
      paddingHorizontal: 10,
      paddingVertical: 6,
    },
    changeButtonText: {
      ...typography.bodyMedium,
      color: colors.primary,
      fontWeight: '600',
    },
  });

export default ModelStatusBanner;
