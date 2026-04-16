import React from 'react';
import { StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { AppIcon } from './AppIcon';
import type { AppIconName } from './AppIcon';
import { useTheme } from '../../theme';
import { Typography } from '../../theme/typography';
import {
  BorderRadius,
  ButtonHeight,
  IconSize,
  Padding,
  Spacing,
} from '../../theme/spacing';
import { ModelModality } from '../../types/model';

interface ModelRequiredOverlayProps {
  modality: ModelModality;
  title?: string;
  description?: string;
  onSelectModel: () => void;
}

const modalityIcon: Record<ModelModality, AppIconName> = {
  [ModelModality.LLM]: 'chatbubble-ellipses-outline',
  [ModelModality.STT]: 'mic-outline',
  [ModelModality.TTS]: 'volume-high-outline',
  [ModelModality.VLM]: 'eye-outline',
};

const modalityTitle: Record<ModelModality, string> = {
  [ModelModality.LLM]: 'No Language Model Selected',
  [ModelModality.STT]: 'No Speech Model Selected',
  [ModelModality.TTS]: 'No Voice Model Selected',
  [ModelModality.VLM]: 'No Vision Model Selected',
};

const modalityDescription: Record<ModelModality, string> = {
  [ModelModality.LLM]:
    'Select a language model to start chatting with AI on your device.',
  [ModelModality.STT]: 'Select a speech recognition model to transcribe audio.',
  [ModelModality.TTS]: 'Select a text-to-speech model to generate audio.',
  [ModelModality.VLM]: 'Select a vision model to analyze images.',
};

export const ModelRequiredOverlay: React.FC<ModelRequiredOverlayProps> = ({
  modality,
  title,
  description,
  onSelectModel,
}) => {
  const { colors } = useTheme();
  const iconName = modalityIcon[modality] ?? 'cube-outline';
  const displayTitle = title ?? modalityTitle[modality] ?? 'No Model Selected';
  const displayDescription =
    description ?? modalityDescription[modality] ?? 'Select a model to get started.';

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <View style={styles.content}>
        <View
          style={[styles.iconCircle, { backgroundColor: colors.primarySoft }]}
        >
          <AppIcon name={iconName} size={IconSize.xLarge} color={colors.primary} />
        </View>
        <Text
          style={[styles.title, Typography.title3, { color: colors.text }]}
        >
          {displayTitle}
        </Text>
        <Text
          style={[
            styles.description,
            Typography.body,
            { color: colors.textSecondary },
          ]}
        >
          {displayDescription}
        </Text>
        <TouchableOpacity
          style={[styles.button, { backgroundColor: colors.primary }]}
          onPress={onSelectModel}
          activeOpacity={0.85}
        >
          <AppIcon name="add-circle" size={20} color={colors.onPrimary} />
          <Text
            style={[
              Typography.headline,
              styles.buttonText,
              { color: colors.onPrimary },
            ]}
          >
            Select a Model
          </Text>
        </TouchableOpacity>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: 'center',
    alignItems: 'center',
    padding: Padding.padding40,
  },
  content: {
    alignItems: 'center',
    maxWidth: 320,
  },
  iconCircle: {
    width: 88,
    height: 88,
    borderRadius: 44,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: Spacing.xLarge,
  },
  title: {
    textAlign: 'center',
    marginBottom: Spacing.medium,
  },
  description: {
    textAlign: 'center',
    marginBottom: Spacing.xxLarge,
    lineHeight: 22,
  },
  button: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: Spacing.smallMedium,
    paddingHorizontal: Padding.padding24,
    height: ButtonHeight.regular,
    borderRadius: BorderRadius.large,
    minWidth: 200,
  },
  buttonText: {},
});

export default ModelRequiredOverlay;
