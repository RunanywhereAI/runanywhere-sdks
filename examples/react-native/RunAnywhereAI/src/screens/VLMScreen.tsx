/**
 * VLMScreen - Vision Chat (VLM) placeholder
 *
 * VLM (Vision-Language Model) is not yet exposed in the React Native SDK.
 * This screen shows a coming-soon message and will be wired to processImage
 * when the core adds VLM APIs.
 *
 * Reference: iOS Features/Vision/VLMCameraView.swift, VLMViewModel.swift
 */

import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  SafeAreaView,
  ScrollView,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding } from '../theme/spacing';

const VLMScreen: React.FC = () => {
  return (
    <SafeAreaView style={styles.container}>
      <ScrollView
        contentContainerStyle={styles.scroll}
        showsVerticalScrollIndicator={false}
      >
        <View style={styles.iconWrap}>
          <Icon
            name="camera-outline"
            size={48}
            color={Colors.primaryBlue}
          />
        </View>
        <Text style={styles.title}>Vision Chat (VLM)</Text>
        <Text style={styles.message}>
          Vision-language models (describe images, visual QA) are coming to the
          React Native SDK. On iOS and Android, the native SDKs already support
          VLM; the RN bridge will expose processImage and model loading in a
          future release.
        </Text>
        <Text style={styles.hint}>
          When available, you’ll be able to pick an image (camera or gallery)
          and get a text description or answer questions about it.
        </Text>
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.backgroundPrimary,
  },
  scroll: {
    padding: Padding.padding24,
    alignItems: 'center',
  },
  iconWrap: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: Colors.badgeBlue,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: Spacing.large,
  },
  title: {
    ...Typography.title2,
    color: Colors.textPrimary,
    marginBottom: Spacing.medium,
    textAlign: 'center',
  },
  message: {
    ...Typography.body,
    color: Colors.textSecondary,
    textAlign: 'center',
    marginBottom: Spacing.mediumLarge,
  },
  hint: {
    ...Typography.footnote,
    color: Colors.textTertiary,
    textAlign: 'center',
  },
});

export default VLMScreen;
