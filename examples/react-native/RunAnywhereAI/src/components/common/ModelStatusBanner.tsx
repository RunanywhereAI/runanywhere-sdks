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
import { Colors } from '../../theme/colors';
import { Typography } from '../../theme/typography';
import { Spacing, BorderRadius, Padding } from '../../theme/spacing';
import { LLMFramework, FrameworkDisplayNames } from '../../types/model';

interface ModelStatusBannerProps {
  /** Model name if loaded */
  modelName?: string;
  /** Framework being used */
  framework?: LLMFramework;
  /** Whether model is loading */
  isLoading?: boolean;
  /** Loading progress (0-1) */
  loadProgress?: number;
  /** Callback when select/change button pressed */
  onSelectModel: () => void;
  /** Placeholder text when no model */
  placeholder?: string;
}

/**
 * Get framework-specific icon name
 */
const getFrameworkIcon = (framework: LLMFramework): string => {
  switch (framework) {
    case LLMFramework.LlamaCpp:
      return 'cube-outline';
    case LLMFramework.WhisperKit:
      return 'mic-outline';
    case LLMFramework.PiperTTS:
      return 'volume-high-outline';
    case LLMFramework.FoundationModels:
      return 'sparkles-outline';
    case LLMFramework.CoreML:
      return 'hardware-chip-outline';
    case LLMFramework.ONNX:
      return 'git-network-outline';
    default:
      return 'cube-outline';
  }
};

/**
 * Get framework-specific color
 */
const getFrameworkColor = (framework: LLMFramework): string => {
  switch (framework) {
    case LLMFramework.LlamaCpp:
      return Colors.frameworkLlamaCpp;
    case LLMFramework.WhisperKit:
      return Colors.frameworkWhisperKit;
    case LLMFramework.PiperTTS:
      return Colors.frameworkPiperTTS;
    case LLMFramework.FoundationModels:
      return Colors.frameworkFoundationModels;
    case LLMFramework.CoreML:
      return Colors.frameworkCoreML;
    case LLMFramework.ONNX:
      return Colors.frameworkONNX;
    default:
      return Colors.primaryBlue;
  }
};

export const ModelStatusBanner: React.FC<ModelStatusBannerProps> = ({
  modelName,
  framework,
  isLoading = false,
  loadProgress,
  onSelectModel,
  placeholder = 'Select a model to get started',
}) => {
  // Loading state
  if (isLoading) {
    return (
      <View style={styles.container}>
        <View style={styles.loadingContent}>
          <ActivityIndicator size="small" color={Colors.primaryBlue} />
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
          <Icon
            name="add-circle-outline"
            size={20}
            color={Colors.primaryBlue}
          />
          <Text style={styles.emptyText}>{placeholder}</Text>
        </View>
        <View style={styles.selectButton}>
          <Text style={styles.selectButtonText}>Select Model</Text>
          <Icon name="chevron-forward" size={16} color={Colors.primaryBlue} />
        </View>
      </TouchableOpacity>
    );
  }

  // Model loaded state
  const frameworkColor = getFrameworkColor(framework);
  const frameworkIcon = getFrameworkIcon(framework);
  const frameworkName = FrameworkDisplayNames[framework] || framework;

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

const styles = StyleSheet.create({
  container: {
    backgroundColor: Colors.backgroundSecondary,
    borderRadius: BorderRadius.medium,
    padding: Padding.padding12,
    marginHorizontal: Padding.padding16,
    marginVertical: Spacing.small,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  emptyContainer: {
    borderWidth: 1,
    borderColor: Colors.borderLight,
    borderStyle: 'dashed',
  },
  emptyContent: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.smallMedium,
  },
  emptyText: {
    ...Typography.subheadline,
    color: Colors.textSecondary,
  },
  selectButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.xSmall,
  },
  selectButtonText: {
    ...Typography.subheadline,
    color: Colors.primaryBlue,
    fontWeight: '600',
  },
  loadingContent: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.smallMedium,
    flex: 1,
  },
  loadingText: {
    ...Typography.subheadline,
    color: Colors.textSecondary,
  },
  progressBar: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    height: 3,
    backgroundColor: Colors.backgroundGray5,
    borderBottomLeftRadius: BorderRadius.medium,
    borderBottomRightRadius: BorderRadius.medium,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    backgroundColor: Colors.primaryBlue,
  },
  loadedContent: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.smallMedium,
    flex: 1,
  },
  frameworkBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.xSmall,
    paddingHorizontal: Spacing.smallMedium,
    paddingVertical: Spacing.xSmall,
    borderRadius: BorderRadius.small,
  },
  frameworkText: {
    ...Typography.caption,
    fontWeight: '600',
  },
  modelName: {
    ...Typography.subheadline,
    color: Colors.textPrimary,
    flex: 1,
  },
  changeButton: {
    paddingHorizontal: Spacing.medium,
    paddingVertical: Spacing.small,
  },
  changeButtonText: {
    ...Typography.subheadline,
    color: Colors.primaryBlue,
    fontWeight: '600',
  },
});

export default ModelStatusBanner;
