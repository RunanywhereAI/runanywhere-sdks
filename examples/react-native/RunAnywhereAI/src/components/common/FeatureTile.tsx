import React, { memo } from 'react';
import { StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { useTheme } from '../../theme';
import { Typography } from '../../theme/typography';
import { BorderRadius, Padding, Spacing } from '../../theme/spacing';
import { AppIcon } from './AppIcon';
import type { AppIconName } from './AppIcon';

type FeatureTileProps = {
  icon: AppIconName;
  title: string;
  subtitle?: string;
  onPress: () => void;
  accent?: string;
  disabled?: boolean;
  badge?: string;
};

const FeatureTileInner: React.FC<FeatureTileProps> = ({
  icon,
  title,
  subtitle,
  onPress,
  accent,
  disabled,
  badge,
}) => {
  const { colors } = useTheme();
  const tint = accent ?? colors.primary;
  return (
    <TouchableOpacity
      onPress={onPress}
      disabled={disabled}
      activeOpacity={0.7}
      style={[
        styles.container,
        {
          backgroundColor: colors.surface,
          borderColor: colors.border,
          opacity: disabled ? 0.5 : 1,
        },
      ]}
    >
      <View
        style={[
          styles.iconWrap,
          { backgroundColor: colors.primarySoft },
        ]}
      >
        <AppIcon name={icon} size={22} color={tint} />
      </View>
      <View style={styles.textWrap}>
        <Text style={[Typography.headline, { color: colors.text }]} numberOfLines={1}>
          {title}
        </Text>
        {subtitle ? (
          <Text
            style={[Typography.caption, { color: colors.textSecondary }]}
            numberOfLines={2}
          >
            {subtitle}
          </Text>
        ) : null}
      </View>
      {badge ? (
        <View style={[styles.badge, { backgroundColor: colors.surfaceAlt }]}>
          <Text style={[Typography.caption2, { color: colors.textSecondary }]}>
            {badge}
          </Text>
        </View>
      ) : (
        <AppIcon name="chevron-forward" size={18} color={colors.textTertiary} />
      )}
    </TouchableOpacity>
  );
};

export const FeatureTile = memo(FeatureTileInner);

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: BorderRadius.large,
    borderWidth: StyleSheet.hairlineWidth,
    paddingVertical: Spacing.mediumLarge,
    paddingHorizontal: Padding.padding16,
    gap: Spacing.mediumLarge,
    marginHorizontal: Padding.padding16,
    marginVertical: Spacing.xSmall,
  },
  iconWrap: {
    width: 40,
    height: 40,
    borderRadius: BorderRadius.medium,
    justifyContent: 'center',
    alignItems: 'center',
  },
  textWrap: {
    flex: 1,
    gap: 2,
  },
  badge: {
    paddingHorizontal: Spacing.small,
    paddingVertical: Spacing.xxSmall,
    borderRadius: BorderRadius.small,
  },
});

export default FeatureTile;
