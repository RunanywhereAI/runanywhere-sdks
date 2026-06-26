/**
 * IntroScreen — shown while the SDK initializes. Minimal by design: the app name
 * and an indeterminate horizontal progress bar. Fully themed (light/dark) and
 * animated via the motion system.
 */
import React, { useEffect, useRef, useState } from 'react';
import { Animated, StyleSheet, Text, View } from 'react-native';
import { useTheme } from '../../theme/system';

const TRACK_HEIGHT = 4;
const BAR_FRACTION = 0.4;

export const IntroScreen: React.FC = () => {
  const { colors, typography, dimens, motion } = useTheme();
  const [trackWidth, setTrackWidth] = useState(0);
  const progress = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    const loop = Animated.loop(
      Animated.timing(progress, {
        toValue: 1,
        duration: motion.duration.extraLong,
        easing: motion.easing.easeInOut,
        useNativeDriver: true,
      })
    );
    loop.start();
    return () => loop.stop();
  }, [progress, motion.duration.extraLong, motion.easing.easeInOut]);

  const barWidth = trackWidth * BAR_FRACTION;
  const translateX = progress.interpolate({
    inputRange: [0, 1],
    outputRange: [-barWidth, trackWidth],
  });

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <Text
        style={[
          typography.headlineMedium,
          { color: colors.onBackground, marginBottom: dimens.spacing.xl },
        ]}
      >
        RunAnywhere AI
      </Text>

      <View
        onLayout={(e) => setTrackWidth(e.nativeEvent.layout.width)}
        style={[
          styles.track,
          {
            backgroundColor: colors.surfaceVariant,
            borderRadius: dimens.radius.full,
          },
        ]}
      >
        {trackWidth > 0 && (
          <Animated.View
            style={[
              styles.bar,
              {
                width: barWidth,
                backgroundColor: colors.primary,
                borderRadius: dimens.radius.full,
                transform: [{ translateX }],
              },
            ]}
          />
        )}
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 32,
  },
  track: {
    width: '60%',
    maxWidth: 280,
    height: TRACK_HEIGHT,
    overflow: 'hidden',
  },
  bar: {
    height: TRACK_HEIGHT,
  },
});

export default IntroScreen;
