/**
 * VisionHubScreen - Vision tab hub
 *
 * Lists Vision features: Vision Chat (VLM). Image generation is Swift sample app only.
 *
 * Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Vision/VisionHubView.swift
 */

import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  SafeAreaView,
  TouchableOpacity,
} from 'react-native';
import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding, BorderRadius } from '../theme/spacing';
import type { VisionStackParamList } from '../types';

type NavigationProp = NativeStackNavigationProp<
  VisionStackParamList,
  'VisionHub'
>;

const VisionHubScreen: React.FC = () => {
  const navigation = useNavigation<NavigationProp>();

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>Vision</Text>
        <Text style={styles.subtitle}>
          Vision-language (VLM)
        </Text>
      </View>
      <View style={styles.list}>
        <TouchableOpacity
          style={styles.row}
          onPress={() => navigation.navigate('VLM')}
          activeOpacity={0.7}
        >
          <View style={styles.iconWrap}>
            <Icon
              name="camera-outline"
              size={24}
              color={Colors.primaryBlue}
            />
          </View>
          <View style={styles.rowContent}>
            <Text style={styles.rowTitle}>Vision Chat (VLM)</Text>
            <Text style={styles.rowSubtitle}>
              Describe images with a vision-language model
            </Text>
          </View>
          <Icon name="chevron-forward" size={20} color={Colors.textSecondary} />
        </TouchableOpacity>
      </View>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.backgroundPrimary,
  },
  header: {
    paddingHorizontal: Padding.padding16,
    paddingTop: Spacing.large,
    paddingBottom: Spacing.medium,
  },
  title: {
    ...Typography.title1,
    color: Colors.textPrimary,
  },
  subtitle: {
    ...Typography.footnote,
    color: Colors.textSecondary,
    marginTop: Spacing.xSmall,
  },
  list: {
    paddingHorizontal: Padding.padding16,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.backgroundSecondary,
    borderRadius: BorderRadius.large,
    padding: Spacing.mediumLarge,
    marginBottom: Spacing.smallMedium,
  },
  iconWrap: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: Colors.badgeBlue,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: Spacing.mediumLarge,
  },
  rowContent: {
    flex: 1,
  },
  rowTitle: {
    ...Typography.headline,
    color: Colors.textPrimary,
  },
  rowSubtitle: {
    ...Typography.caption1,
    color: Colors.textSecondary,
    marginTop: 2,
  },
});

export default VisionHubScreen;
