import React, { useCallback } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useTheme } from '../theme';
import { Spacing } from '../theme/spacing';
import { ScreenHeader } from '../components/common/ScreenHeader';
import { SectionHeader } from '../components/common/SectionHeader';
import { FeatureTile } from '../components/common/FeatureTile';
import type { MoreStackParamList } from '../types';

type MoreNavigationProp = NativeStackNavigationProp<MoreStackParamList, 'MoreHome'>;

type TileSpec = {
  route: keyof Omit<MoreStackParamList, 'MoreHome'>;
  icon: Parameters<typeof FeatureTile>[0]['icon'];
  title: string;
  subtitle: string;
};

type Section = {
  label: string;
  tiles: TileSpec[];
};

const sections: Section[] = [
  {
    label: 'Voice & Audio',
    tiles: [
      {
        route: 'STT',
        icon: 'mic-outline',
        title: 'Speech to Text',
        subtitle: 'Transcribe audio locally with Whisper',
      },
      {
        route: 'TTS',
        icon: 'volume-high',
        title: 'Text to Speech',
        subtitle: 'Synthesize neural voices with Piper',
      },
      {
        route: 'Voice',
        icon: 'pulse',
        title: 'Voice Assistant',
        subtitle: 'STT → LLM → TTS pipeline on-device',
      },
    ],
  },
  {
    label: 'Knowledge',
    tiles: [
      {
        route: 'RAG',
        icon: 'document-text-outline',
        title: 'Document Q&A',
        subtitle: 'Ask questions about your documents',
      },
    ],
  },
  {
    label: 'Models',
    tiles: [
      {
        route: 'Models',
        icon: 'cube-outline',
        title: 'Models',
        subtitle: 'Download, load, and manage AI models',
      },
    ],
  },
];

const MoreScreen: React.FC = () => {
  const { colors } = useTheme();
  const navigation = useNavigation<MoreNavigationProp>();

  const handleTilePress = useCallback(
    (route: TileSpec['route']) => () => navigation.navigate(route),
    [navigation]
  );

  return (
    <SafeAreaView
      style={[styles.container, { backgroundColor: colors.background }]}
      edges={['top']}
    >
      <ScreenHeader title="More" />
      <ScrollView
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {sections.map((section) => (
          <View key={section.label}>
            <SectionHeader label={section.label} />
            {section.tiles.map((tile) => (
              <FeatureTile
                key={tile.route}
                icon={tile.icon}
                title={tile.title}
                subtitle={tile.subtitle}
                onPress={handleTilePress(tile.route)}
              />
            ))}
          </View>
        ))}
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  scrollContent: {
    paddingBottom: Spacing.xxxLarge,
  },
});

export default MoreScreen;
