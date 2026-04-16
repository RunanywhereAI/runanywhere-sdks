import React from 'react';
import { StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import type { ReactNode } from 'react';
import { useTheme } from '../../theme';
import { Typography } from '../../theme/typography';
import { Padding, Spacing } from '../../theme/spacing';
import { AppIcon } from './AppIcon';
import type { AppIconName } from './AppIcon';

type HeaderAction = {
  icon: AppIconName;
  onPress: () => void;
  accessibilityLabel?: string;
  tint?: string;
};

type ScreenHeaderProps = {
  title: string;
  subtitle?: string;
  leftAction?: HeaderAction;
  rightActions?: HeaderAction[];
  trailing?: ReactNode;
};

export const ScreenHeader: React.FC<ScreenHeaderProps> = ({
  title,
  subtitle,
  leftAction,
  rightActions,
  trailing,
}) => {
  const { colors } = useTheme();
  return (
    <View style={[styles.container, { borderBottomColor: colors.border }]}>
      <View style={styles.row}>
        {leftAction ? (
          <TouchableOpacity
            style={styles.actionButton}
            onPress={leftAction.onPress}
            accessibilityLabel={leftAction.accessibilityLabel}
            hitSlop={8}
          >
            <AppIcon
              name={leftAction.icon}
              size={22}
              color={leftAction.tint ?? colors.text}
            />
          </TouchableOpacity>
        ) : (
          <View style={styles.actionButton} />
        )}

        <View style={styles.titleWrap}>
          <Text style={[Typography.title3, { color: colors.text }]} numberOfLines={1}>
            {title}
          </Text>
          {subtitle ? (
            <Text
              style={[Typography.caption, { color: colors.textSecondary }]}
              numberOfLines={1}
            >
              {subtitle}
            </Text>
          ) : null}
        </View>

        <View style={styles.rightGroup}>
          {trailing}
          {rightActions?.map((action, index) => (
            <TouchableOpacity
              key={`${action.icon}-${index}`}
              style={styles.actionButton}
              onPress={action.onPress}
              accessibilityLabel={action.accessibilityLabel}
              hitSlop={8}
            >
              <AppIcon
                name={action.icon}
                size={22}
                color={action.tint ?? colors.text}
              />
            </TouchableOpacity>
          ))}
        </View>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: Padding.padding8,
    paddingVertical: Spacing.smallMedium,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  actionButton: {
    width: 40,
    height: 40,
    justifyContent: 'center',
    alignItems: 'center',
  },
  titleWrap: {
    flex: 1,
    alignItems: 'flex-start',
    paddingHorizontal: Spacing.small,
  },
  rightGroup: {
    flexDirection: 'row',
    alignItems: 'center',
  },
});

export default ScreenHeader;
