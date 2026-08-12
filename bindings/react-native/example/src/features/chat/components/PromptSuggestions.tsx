/**
 * PromptSuggestions — a horizontal row of example-prompt pills shown above the
 * chat composer while the conversation is empty. The set shown depends on mode,
 * mirroring the Android app: LoRA active → uncensored prompts, tools enabled →
 * tool-calling prompts, otherwise casual prompts. Tapping a pill sends it.
 */
import React from 'react';
import { ScrollView, StyleSheet, Text, TouchableOpacity } from 'react-native';
import { Icon, useTheme, type IconName } from '../../../theme/system';

interface Suggestion {
  label: string;
  prompt: string;
  icon?: IconName;
}

const CASUAL: Suggestion[] = [
  { label: 'Explain LLMs', prompt: 'Explain how large language models work, in simple terms.' },
  { label: 'Write a poem', prompt: 'Write a short poem about the ocean at night.' },
  { label: 'Summarize a story', prompt: 'Summarize Romeo and Juliet in three sentences.' },
  { label: 'Name ideas', prompt: 'Give me five creative names for a coffee shop.' },
];

const TOOL: Suggestion[] = [
  { label: 'Weather in Tokyo', prompt: "What's the weather in Tokyo right now?", icon: 'cloud' },
  { label: 'Current time', prompt: 'What time is it right now?', icon: 'clock' },
  { label: 'Battery level', prompt: "What's my battery level?", icon: 'battery' },
  { label: 'Quick math', prompt: 'What is 15% of 240?', icon: 'calculator' },
];

const UNCENSORED: Suggestion[] = [
  { label: 'Brutally honest', prompt: 'Give me brutally honest feedback on a weak startup idea.', icon: 'bolt' },
  { label: 'Dark joke', prompt: 'Tell me a dark joke.', icon: 'bolt' },
  { label: 'Hot take', prompt: 'Give me a controversial tech opinion and defend it hard.', icon: 'bolt' },
  { label: 'Roast me', prompt: 'Roast my code in one savage paragraph, no holding back.', icon: 'bolt' },
];

interface PromptSuggestionsProps {
  toolsEnabled: boolean;
  loraActive: boolean;
  onSelect: (prompt: string) => void;
}

export const PromptSuggestions: React.FC<PromptSuggestionsProps> = ({
  toolsEnabled,
  loraActive,
  onSelect,
}) => {
  const { colors, typography } = useTheme();
  const items = loraActive ? UNCENSORED : toolsEnabled ? TOOL : CASUAL;

  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      keyboardShouldPersistTaps="handled"
      style={styles.scroll}
      contentContainerStyle={styles.row}
    >
      {items.map((s) => (
        <TouchableOpacity
          key={s.label}
          activeOpacity={0.7}
          onPress={() => onSelect(s.prompt)}
          style={[styles.pill, { backgroundColor: colors.surfaceContainerHigh }]}
        >
          {s.icon && <Icon name={s.icon} size={15} color={colors.primary} />}
          <Text
            style={[typography.labelLarge, styles.label, { color: colors.onSurface }]}
            numberOfLines={1}
          >
            {s.label}
          </Text>
        </TouchableOpacity>
      ))}
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  // A horizontal ScrollView stretches to fill a flex column unless capped;
  // flexGrow:0 keeps it at its content height so it sits snug above the input.
  scroll: {
    flexGrow: 0,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 16,
    paddingTop: 2,
    paddingBottom: 6,
  },
  pill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 999,
  },
  label: {
    fontWeight: '600',
  },
});

export default PromptSuggestions;
