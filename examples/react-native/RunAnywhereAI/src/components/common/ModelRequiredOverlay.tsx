/**
 * ModelRequiredOverlay Component
 *
 * Full-screen overlay shown when a model is required but not selected.
 *
 * Reference: iOS ModelRequiredOverlay
 */

import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../../theme/colors';
import { Typography } from '../../theme/typography';
import {
  Spacing,
  BorderRadius,
  Padding,
  IconSize,
  ButtonHeight,
} from '../../theme/spacing';
import { ModelModality } from '../../types/model';

interface ModelRequiredOverlayProps {
  /** Modality context for icon and text */
  modality: ModelModality;
  /** Title text */
  title?: string;
  /** Description text */
  description?: string;
  /** Callback when select model button pressed */
  onSelectModel: () => void;
}

/**
 * Get icon name based on modality
 */
const getModalityIcon = (modality: ModelModality): string => {
  switch (modality) {
    case ModelModality.LLM:
      return 'chatbubble-ellipses-outline';
    case ModelModality.STT:
      return 'mic-outline';
    case ModelModality.TTS:
      return 'volume-high-outline';
    case ModelModality.VLM:
      return 'eye-outline';
    default:
      return 'cube-outline';
  }
};

/**
 * Get default title based on modality
 */
const getDefaultTitle = (modality: ModelModality): string => {
  switch (modality) {
    case ModelModality.LLM:
      return 'No Language Model Selected';
    case ModelModality.STT:
      return 'No Speech Model Selected';
    case ModelModality.TTS:
      return 'No Voice Model Selected';
    case ModelModality.VLM:
      return 'No Vision Model Selected';
    default:
      return 'No Model Selected';
  }
};

/**
 * Get default description based on modality
 */
const getDefaultDescription = (modality: ModelModality): string => {
  switch (modality) {
    case ModelModality.LLM:
      return 'Select a language model to start chatting with AI on your device.';
    case ModelModality.STT:
      return 'Select a speech recognition model to transcribe audio.';
    case ModelModality.TTS:
      return 'Select a text-to-speech model to generate audio.';
    case ModelModality.VLM:
      return 'Select a vision model to analyze images.';
    default:
      return 'Select a model to get started.';
  }
};

export const ModelRequiredOverlay: React.FC<ModelRequiredOverlayProps> = ({
  modality,
  title,
  description,
  onSelectModel,
}) => {
  const iconName = getModalityIcon(modality);
  const displayTitle = title || getDefaultTitle(modality);
  const displayDescription = description || getDefaultDescription(modality);

  return (
    <View style={styles.container}>
      <View style={styles.content}>
        {/* Icon */}
        <View style={styles.iconContainer}>
          <Icon
            name={iconName}
            size={IconSize.xLarge}
            color={Colors.textSecondary}
          />
        </View>

        {/* Title */}
        <Text style={styles.title}>{displayTitle}</Text>

        {/* Description */}
        <Text style={styles.description}>{displayDescription}</Text>

        {/* Select Model Button */}
        <TouchableOpacity
          style={styles.button}
          onPress={onSelectModel}
          activeOpacity={0.8}
        >
          <Icon name="add-circle" size={20} color={Colors.textWhite} />
          <Text style={styles.buttonText}>Select a Model</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: Colors.backgroundPrimary,
    justifyContent: 'center',
    alignItems: 'center',
    padding: Padding.padding40,
  },
  content: {
    alignItems: 'center',
    maxWidth: 300,
  },
  iconContainer: {
    width: IconSize.huge,
    height: IconSize.huge,
    borderRadius: IconSize.huge / 2,
    backgroundColor: Colors.backgroundSecondary,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: Spacing.xLarge,
  },
  title: {
    ...Typography.title3,
    color: Colors.textPrimary,
    textAlign: 'center',
    marginBottom: Spacing.medium,
  },
  description: {
    ...Typography.body,
    color: Colors.textSecondary,
    textAlign: 'center',
    marginBottom: Spacing.xxLarge,
    lineHeight: 24,
  },
  button: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: Spacing.smallMedium,
    backgroundColor: Colors.primaryBlue,
    paddingHorizontal: Padding.padding24,
    height: ButtonHeight.regular,
    borderRadius: BorderRadius.large,
    minWidth: 200,
  },
  buttonText: {
    ...Typography.headline,
    color: Colors.textWhite,
  },
});

export default ModelRequiredOverlay;
