/**
 * TypingIndicator Component
 *
 * Animated dots to show AI is thinking/generating.
 *
 * Reference: iOS TypingIndicatorView.swift
 */

import React, { useEffect, useRef } from 'react';
import { View, Text, StyleSheet, Animated } from 'react-native';
import { Colors } from '../../theme/colors';
import { Typography } from '../../theme/typography';
import { Spacing, BorderRadius, Padding } from '../../theme/spacing';

interface TypingIndicatorProps {
  /** Label text */
  label?: string;
}

export const TypingIndicator: React.FC<TypingIndicatorProps> = ({
  label = 'AI is thinking...',
}) => {
  // Animation values for each dot
  const dot1 = useRef(new Animated.Value(0)).current;
  const dot2 = useRef(new Animated.Value(0)).current;
  const dot3 = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    const createDotAnimation = (dot: Animated.Value, delay: number) => {
      return Animated.loop(
        Animated.sequence([
          Animated.delay(delay),
          Animated.timing(dot, {
            toValue: 1,
            duration: 300,
            useNativeDriver: true,
          }),
          Animated.timing(dot, {
            toValue: 0,
            duration: 300,
            useNativeDriver: true,
          }),
          Animated.delay(600 - delay),
        ])
      );
    };

    const animation = Animated.parallel([
      createDotAnimation(dot1, 0),
      createDotAnimation(dot2, 150),
      createDotAnimation(dot3, 300),
    ]);

    animation.start();

    return () => {
      animation.stop();
    };
  }, [dot1, dot2, dot3]);

  const createDotStyle = (animatedValue: Animated.Value) => ({
    transform: [
      {
        scale: animatedValue.interpolate({
          inputRange: [0, 1],
          outputRange: [1, 1.3],
        }),
      },
    ],
    opacity: animatedValue.interpolate({
      inputRange: [0, 1],
      outputRange: [0.4, 1],
    }),
  });

  return (
    <View style={styles.container}>
      <View style={styles.bubble}>
        <View style={styles.dotsContainer}>
          <Animated.View style={[styles.dot, createDotStyle(dot1)]} />
          <Animated.View style={[styles.dot, createDotStyle(dot2)]} />
          <Animated.View style={[styles.dot, createDotStyle(dot3)]} />
        </View>
        <Text style={styles.label}>{label}</Text>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    alignItems: 'flex-start',
    paddingHorizontal: Padding.padding16,
    marginVertical: Spacing.xSmall,
  },
  bubble: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.smallMedium,
    backgroundColor: Colors.backgroundGray5,
    borderRadius: BorderRadius.xLarge,
    borderBottomLeftRadius: BorderRadius.small,
    paddingHorizontal: Padding.padding14,
    paddingVertical: Padding.padding10,
  },
  dotsContainer: {
    flexDirection: 'row',
    gap: Spacing.xSmall,
  },
  dot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: Colors.textSecondary,
  },
  label: {
    ...Typography.footnote,
    color: Colors.textSecondary,
  },
});

export default TypingIndicator;
