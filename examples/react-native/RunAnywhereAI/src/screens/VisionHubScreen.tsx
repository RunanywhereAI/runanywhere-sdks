import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ScrollView } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { Icon, useTheme } from '../theme/system';
import { ROUTES } from '../navigation/routes';
import type { RootStackParamList } from '../navigation/navigation.types';

type NavigationProp = NativeStackNavigationProp<RootStackParamList>;

const VisionHubScreen: React.FC = () => {
  const { colors, typography, dimens } = useTheme();
  const insets = useSafeAreaInsets();
  const navigation = useNavigation<NavigationProp>();

  return (
    <ScrollView
      style={[styles.root, { backgroundColor: colors.background }]}
      contentContainerStyle={[
        styles.content,
        {
          paddingTop: insets.top + dimens.spacing.lg,
          paddingBottom: insets.bottom + dimens.spacing.xl,
          paddingHorizontal: dimens.screenPadding,
        },
      ]}
      showsVerticalScrollIndicator={false}
    >
      <Text style={[typography.headlineMedium, { color: colors.onBackground, marginBottom: dimens.spacing.xs }]}>
        Vision
      </Text>
      <Text style={[typography.bodyMedium, { color: colors.onSurfaceVariant, marginBottom: dimens.spacing.xl }]}>
        Vision-language models that understand images
      </Text>

      {/* Vision Chat (VLM) */}
      <TouchableOpacity
        style={[styles.card, { backgroundColor: colors.surfaceContainerHigh }]}
        onPress={() => navigation.navigate(ROUTES.Vlm)}
        activeOpacity={0.7}
      >
        <View style={[styles.iconTile, { backgroundColor: colors.primaryContainer }]}>
          <Icon name="vision" size={dimens.icon.md} color={colors.primary} />
        </View>
        <View style={styles.cardText}>
          <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}>
            Vision model
          </Text>
          <Text style={[typography.bodyLarge, { color: colors.onSurface }]}>
            Vision Chat (VLM)
          </Text>
          <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant, marginTop: 2 }]}>
            Describe images with a vision-language model
          </Text>
        </View>
        <Icon name="chevronRight" size={dimens.icon.sm} color={colors.onSurfaceVariant} />
      </TouchableOpacity>

      {/* Image Generation — coming soon */}
      <View
        style={[
          styles.card,
          styles.cardDisabled,
          { backgroundColor: colors.surfaceContainerHigh },
        ]}
      >
        <View style={[styles.iconTile, { backgroundColor: colors.surfaceVariant }]}>
          <Icon name="sparkles" size={dimens.icon.md} color={colors.onSurfaceVariant} />
        </View>
        <View style={styles.cardText}>
          <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}>
            Diffusion model
          </Text>
          <Text style={[typography.bodyLarge, { color: colors.onSurface }]}>
            Image Generation
          </Text>
          <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant, marginTop: 2 }]}>
            Generate images from text descriptions
          </Text>
        </View>
        <View style={[styles.badge, { backgroundColor: colors.surfaceVariant }]}>
          <Text style={[typography.labelSmall, { color: colors.onSurfaceVariant }]}>
            Coming Soon
          </Text>
        </View>
      </View>
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
  content: {
    flexGrow: 1,
    gap: 12,
  },
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: 20,
    padding: 16,
    gap: 12,
  },
  cardDisabled: {
    opacity: 0.55,
  },
  iconTile: {
    width: 44,
    height: 44,
    borderRadius: 12,
    justifyContent: 'center',
    alignItems: 'center',
  },
  cardText: {
    flex: 1,
  },
  badge: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 999,
  },
});

export default VisionHubScreen;
