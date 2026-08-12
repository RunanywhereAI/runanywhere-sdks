/**
 * ModelRequiredOverlay — empty state shown when a modality has no model loaded.
 *
 * Themed on the design system: a soft icon medallion, title + description, and a
 * filled primary "Select a model" button that opens the model picker. Touches in
 * empty regions pass through (box-none) so the chat header beneath stays tappable.
 */
import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Icon, useTheme, type IconName } from '../../theme/system';

export type RequiredModelKind = 'llm' | 'stt' | 'tts' | 'vad' | 'vlm';

interface ModelRequiredOverlayProps {
  modality: RequiredModelKind;
  title?: string;
  description?: string;
  onSelectModel: () => void;
}

const MODALITY_ICON: Record<RequiredModelKind, IconName> = {
  llm: 'chat',
  stt: 'transcribe',
  tts: 'speak',
  vad: 'vad',
  vlm: 'vision',
};

const DEFAULT_TITLE: Record<RequiredModelKind, string> = {
  llm: 'No language model selected',
  stt: 'No speech model selected',
  tts: 'No voice model selected',
  vad: 'No VAD model selected',
  vlm: 'No vision model selected',
};

const DEFAULT_DESCRIPTION: Record<RequiredModelKind, string> = {
  llm: 'Select a language model to start chatting with AI on your device.',
  stt: 'Select a speech recognition model to transcribe audio.',
  tts: 'Select a text-to-speech model to generate audio.',
  vad: 'Select a voice activity model to detect speech in microphone audio.',
  vlm: 'Select a vision model to analyze images.',
};

export const ModelRequiredOverlay: React.FC<ModelRequiredOverlayProps> = ({
  modality,
  title,
  description,
  onSelectModel,
}) => {
  const { colors, typography } = useTheme();
  const displayTitle = title ?? DEFAULT_TITLE[modality];
  const displayDescription = description ?? DEFAULT_DESCRIPTION[modality];

  return (
    <View
      style={[styles.container, { backgroundColor: colors.background }]}
      pointerEvents="box-none"
    >
      <View style={styles.content} pointerEvents="auto">
        <View
          style={[styles.medallion, { backgroundColor: colors.surfaceVariant }]}
        >
          <Icon
            name={MODALITY_ICON[modality]}
            size={36}
            color={colors.onSurfaceVariant}
          />
        </View>

        <Text
          style={[typography.titleLarge, styles.title, { color: colors.onSurface }]}
        >
          {displayTitle}
        </Text>

        <Text
          style={[
            typography.bodyMedium,
            styles.description,
            { color: colors.onSurfaceVariant },
          ]}
        >
          {displayDescription}
        </Text>

        <TouchableOpacity
          style={[styles.button, { backgroundColor: colors.primary }]}
          onPress={onSelectModel}
          activeOpacity={0.85}
          accessibilityLabel="Select a model"
          accessibilityRole="button"
        >
          <Icon name="plus" size={20} color={colors.onPrimary} />
          <Text
            style={[typography.titleSmall, styles.buttonText, { color: colors.onPrimary }]}
          >
            Select a model
          </Text>
        </TouchableOpacity>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 40,
  },
  content: {
    alignItems: 'center',
    maxWidth: 320,
  },
  medallion: {
    width: 88,
    height: 88,
    borderRadius: 44,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 24,
  },
  title: {
    textAlign: 'center',
    fontWeight: '700',
    marginBottom: 10,
  },
  description: {
    textAlign: 'center',
    lineHeight: 22,
    marginBottom: 28,
  },
  button: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    paddingHorizontal: 24,
    height: 52,
    borderRadius: 16,
    minWidth: 200,
  },
  buttonText: {
    fontWeight: '700',
  },
});

export default ModelRequiredOverlay;
