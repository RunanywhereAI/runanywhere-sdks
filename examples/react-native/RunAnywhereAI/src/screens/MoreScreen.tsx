import React from 'react';
import { StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import Icon from 'react-native-vector-icons/Ionicons';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding, BorderRadius } from '../theme/spacing';
import type { MoreStackParamList } from '../types';

type Props = NativeStackScreenProps<MoreStackParamList, 'MoreHome'>;

type MoreItem = {
  route: Exclude<keyof MoreStackParamList, 'MoreHome'>;
  title: string;
  subtitle: string;
  icon: string;
};

const ITEMS: MoreItem[] = [
  {
    route: 'STT',
    title: 'Transcribe',
    subtitle: 'Speech-to-text',
    icon: 'pulse-outline',
  },
  {
    route: 'TTS',
    title: 'Speak',
    subtitle: 'Text-to-speech',
    icon: 'volume-high-outline',
  },
  {
    route: 'RAG',
    title: 'RAG',
    subtitle: 'Document question answering',
    icon: 'search-outline',
  },
  {
    route: 'VAD',
    title: 'Voice Activity',
    subtitle: 'Speech detection stream',
    icon: 'mic-circle-outline',
  },
  {
    route: 'Storage',
    title: 'Storage',
    subtitle: 'Cache and model storage',
    icon: 'folder-outline',
  },
  {
    route: 'Solutions',
    title: 'Solutions',
    subtitle: 'YAML pipeline demos',
    icon: 'layers-outline',
  },
];

export const MoreScreen: React.FC<Props> = ({ navigation }) => (
  <SafeAreaView style={styles.container}>
    <View style={styles.header}>
      <Text style={styles.title}>More</Text>
    </View>
    <View style={styles.list}>
      {ITEMS.map((item) => (
        <TouchableOpacity
          key={item.route}
          style={styles.row}
          onPress={() => navigation.navigate(item.route)}
        >
          <View style={styles.iconContainer}>
            <Icon name={item.icon} size={22} color={Colors.primaryBlue} />
          </View>
          <View style={styles.rowText}>
            <Text style={styles.rowTitle}>{item.title}</Text>
            <Text style={styles.rowSubtitle}>{item.subtitle}</Text>
          </View>
          <Icon name="chevron-forward" size={20} color={Colors.textTertiary} />
        </TouchableOpacity>
      ))}
    </View>
  </SafeAreaView>
);

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.backgroundPrimary,
  },
  header: {
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding12,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  title: {
    ...Typography.title2,
    color: Colors.textPrimary,
  },
  list: {
    padding: Padding.padding16,
    gap: Spacing.smallMedium,
  },
  row: {
    minHeight: 72,
    flexDirection: 'row',
    alignItems: 'center',
    padding: Padding.padding16,
    borderRadius: BorderRadius.regular,
    backgroundColor: Colors.backgroundSecondary,
    gap: Spacing.medium,
  },
  iconContainer: {
    width: 40,
    height: 40,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.badgeBlue,
  },
  rowText: {
    flex: 1,
  },
  rowTitle: {
    ...Typography.headline,
    color: Colors.textPrimary,
  },
  rowSubtitle: {
    ...Typography.footnote,
    color: Colors.textSecondary,
    marginTop: 2,
  },
});

export default MoreScreen;
