import React from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { useTheme } from '../../theme';
import { Padding, Spacing } from '../../theme/spacing';

type SectionHeaderProps = {
  label: string;
};

export const SectionHeader: React.FC<SectionHeaderProps> = ({ label }) => {
  const { colors } = useTheme();
  return (
    <View style={styles.container}>
      <Text style={[styles.label, { color: colors.textSecondary }]}>
        {label.toUpperCase()}
      </Text>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    paddingHorizontal: Padding.padding16,
    paddingTop: Spacing.xLarge,
    paddingBottom: Spacing.smallMedium,
  },
  label: {
    fontSize: 12,
    fontWeight: '600',
    letterSpacing: 0.6,
  },
});

export default SectionHeader;
