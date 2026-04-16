import React from 'react';
import {
  ActivityIndicator,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { AppIcon } from './AppIcon';
import type { AppIconName } from './AppIcon';
import { useTheme } from '../../theme';
import { Typography } from '../../theme/typography';
import { BorderRadius, Padding, Spacing } from '../../theme/spacing';
import type { ThemeColors } from '../../theme/colors';
import { LLMFramework, FrameworkDisplayNames } from '../../types/model';

interface ModelStatusBannerProps {
  modelName?: string;
  framework?: LLMFramework;
  isLoading?: boolean;
  loadProgress?: number;
  onSelectModel: () => void;
  placeholder?: string;
}

const frameworkIconMap: Partial<Record<LLMFramework, AppIconName>> = {
  [LLMFramework.LlamaCpp]: 'cube-outline',
  [LLMFramework.WhisperKit]: 'mic-outline',
  [LLMFramework.PiperTTS]: 'volume-high-outline',
  [LLMFramework.FoundationModels]: 'sparkles-outline',
  [LLMFramework.CoreML]: 'hardware-chip-outline',
  [LLMFramework.ONNX]: 'cube-outline',
};

const frameworkColor = (framework: LLMFramework, c: ThemeColors): string => {
  switch (framework) {
    case LLMFramework.LlamaCpp:
      return c.frameworkLlamaCpp;
    case LLMFramework.WhisperKit:
      return c.frameworkWhisperKit;
    case LLMFramework.PiperTTS:
      return c.frameworkPiperTTS;
    case LLMFramework.FoundationModels:
      return c.frameworkFoundationModels;
    case LLMFramework.CoreML:
      return c.frameworkCoreML;
    case LLMFramework.ONNX:
      return c.frameworkONNX;
    default:
      return c.primary;
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
  const { colors } = useTheme();

  if (isLoading) {
    return (
      <View
        style={[
          styles.container,
          { backgroundColor: colors.surface, borderColor: colors.border },
        ]}
      >
        <View style={styles.loadingContent}>
          <ActivityIndicator size="small" color={colors.primary} />
          <Text
            style={[Typography.subheadline, { color: colors.textSecondary }]}
          >
            Loading model…
            {loadProgress !== undefined
              ? ` ${Math.round(loadProgress * 100)}%`
              : ''}
          </Text>
        </View>
        {loadProgress !== undefined ? (
          <View
            style={[
              styles.progressBar,
              { backgroundColor: colors.surfaceAlt },
            ]}
          >
            <View
              style={[
                styles.progressFill,
                {
                  backgroundColor: colors.primary,
                  width: `${loadProgress * 100}%`,
                },
              ]}
            />
          </View>
        ) : null}
      </View>
    );
  }

  if (!modelName || !framework) {
    return (
      <TouchableOpacity
        activeOpacity={0.7}
        onPress={onSelectModel}
        style={[
          styles.container,
          styles.emptyContainer,
          {
            borderColor: colors.border,
            backgroundColor: colors.surface,
          },
        ]}
      >
        <View style={styles.emptyContent}>
          <AppIcon name="add-circle-outline" size={20} color={colors.primary} />
          <Text style={[Typography.subheadline, { color: colors.textSecondary }]}>
            {placeholder}
          </Text>
        </View>
        <View style={styles.selectButton}>
          <Text
            style={[Typography.subheadline, styles.boldText, { color: colors.primary }]}
          >
            Select Model
          </Text>
          <AppIcon name="chevron-forward" size={16} color={colors.primary} />
        </View>
      </TouchableOpacity>
    );
  }

  const fwColor = frameworkColor(framework, colors);
  const fwIcon: AppIconName = frameworkIconMap[framework] ?? 'cube-outline';
  const fwName = FrameworkDisplayNames[framework] || framework;

  return (
    <View
      style={[
        styles.container,
        { backgroundColor: colors.surface, borderColor: colors.border },
      ]}
    >
      <View style={styles.loadedContent}>
        <View style={[styles.frameworkBadge, { backgroundColor: `${fwColor}20` }]}>
          <AppIcon name={fwIcon} size={14} color={fwColor} />
          <Text style={[Typography.caption, styles.boldText, { color: fwColor }]}>
            {fwName}
          </Text>
        </View>
        <Text
          style={[Typography.subheadline, { color: colors.text, flex: 1 }]}
          numberOfLines={1}
        >
          {modelName}
        </Text>
      </View>
      <TouchableOpacity
        style={styles.changeButton}
        onPress={onSelectModel}
        activeOpacity={0.7}
      >
        <Text
          style={[Typography.subheadline, styles.boldText, { color: colors.primary }]}
        >
          Change
        </Text>
      </TouchableOpacity>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    borderRadius: BorderRadius.medium,
    borderWidth: StyleSheet.hairlineWidth,
    padding: Padding.padding12,
    marginHorizontal: Padding.padding16,
    marginVertical: Spacing.small,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: Spacing.smallMedium,
  },
  emptyContainer: {
    borderStyle: 'dashed',
  },
  emptyContent: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.smallMedium,
    flex: 1,
  },
  selectButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.xSmall,
  },
  loadingContent: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.smallMedium,
    flex: 1,
  },
  progressBar: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    height: 3,
    borderBottomLeftRadius: BorderRadius.medium,
    borderBottomRightRadius: BorderRadius.medium,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
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
  changeButton: {
    paddingHorizontal: Spacing.medium,
    paddingVertical: Spacing.small,
  },
  boldText: {
    fontWeight: '600',
  },
});

export default ModelStatusBanner;
