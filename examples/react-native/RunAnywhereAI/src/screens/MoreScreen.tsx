import React from 'react';
import { ScrollView, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Icon, useTheme } from '../theme/system';
import type { IconName } from '../theme/system/icons';
import { ROUTES } from '../navigation/routes';
import type { RootStackParamList } from '../navigation/navigation.types';
import HexagonNpuCard from '../components/HexagonNpuCard';

type MoreEntry = {
  label: string;
  description: string;
  icon: IconName;
  route: keyof RootStackParamList | null;
};

const ENTRIES: MoreEntry[] = [
  {
    label: 'Settings',
    description: 'Generation and storage',
    icon: 'settings',
    route: ROUTES.Settings,
  },
  {
    label: 'Tool Calling',
    description: 'Let the LLM use registered tools',
    icon: 'sliders',
    route: null,
  },
  {
    label: 'Text to Speech',
    description: 'Read text aloud',
    icon: 'speak',
    route: ROUTES.Speak,
  },
  {
    label: 'Speech to Text',
    description: 'Transcribe audio on-device',
    icon: 'transcribe',
    route: ROUTES.Transcribe,
  },
  {
    label: 'Voice Detection',
    description: 'Detect speech activity in real-time',
    icon: 'vad',
    route: ROUTES.Vad,
  },
  {
    label: 'Vision',
    description: 'Describe images with a VLM',
    icon: 'vision',
    route: ROUTES.Vlm,
  },
  {
    label: 'Documents',
    description: 'Chat with your files (RAG)',
    icon: 'rag',
    route: ROUTES.Rag,
  },
  {
    label: 'Solutions',
    description: 'Run prepackaged pipelines from YAML',
    icon: 'solutions',
    route: ROUTES.Solutions,
  },
  {
    label: 'Cloud Providers',
    description: 'Register cloud STT backends',
    icon: 'cloud',
    route: null,
  },
  {
    label: 'Benchmarks',
    description: 'Measure model performance',
    icon: 'benchmarks',
    route: ROUTES.Benchmarks,
  },
];

export const MoreScreen: React.FC = () => {
  const navigation =
    useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const { colors, typography } = useTheme();
  const insets = useSafeAreaInsets();

  return (
    <ScrollView
      style={[styles.root, { backgroundColor: colors.background }]}
      contentContainerStyle={[
        styles.content,
        { paddingTop: insets.top + 16, paddingBottom: insets.bottom + 24 },
      ]}
      showsVerticalScrollIndicator={false}
    >
      <HexagonNpuCard />
      {ENTRIES.map((entry) => {
        const enabled = entry.route !== null;
        const labelColor = enabled
          ? colors.onSurface
          : colors.onSurfaceVariant;
        const descColor = colors.onSurfaceVariant;

        return (
          <TouchableOpacity
            key={entry.label}
            style={[styles.card, { backgroundColor: colors.surfaceContainerHigh }]}
            activeOpacity={enabled ? 0.7 : 1}
            disabled={!enabled}
            onPress={() => {
              if (enabled && entry.route) {
                navigation.navigate(entry.route as keyof RootStackParamList);
              }
            }}
          >
            <Icon
              name={entry.icon}
              size={24}
              color={enabled ? colors.primary : colors.onSurfaceVariant}
            />
            <View style={styles.textBlock}>
              <Text
                style={[typography.bodyLarge, { color: labelColor }]}
                numberOfLines={1}
              >
                {entry.label}
              </Text>
              <Text
                style={[typography.bodySmall, { color: descColor, opacity: enabled ? 1 : 0.6 }]}
                numberOfLines={1}
              >
                {entry.description}
              </Text>
            </View>
            {enabled ? (
              <Icon name="chevronRight" size={20} color={colors.onSurfaceVariant} />
            ) : (
              <Text style={[typography.labelSmall, { color: colors.onSurfaceVariant, opacity: 0.6 }]}>
                Soon
              </Text>
            )}
          </TouchableOpacity>
        );
      })}
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
  content: {
    paddingHorizontal: 16,
    gap: 8,
  },
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    borderRadius: 16,
    paddingHorizontal: 18,
    paddingVertical: 16,
  },
  textBlock: {
    flex: 1,
    gap: 2,
  },
});

export default MoreScreen;
