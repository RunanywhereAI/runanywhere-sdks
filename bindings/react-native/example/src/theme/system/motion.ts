/**
 * Motion system — ported 1:1 from the Android example (ui/theme/AppMotion.kt).
 * iOS-inspired durations, easing curves, and springs, mapped onto React Native's
 * Animated primitives (Easing.bezier for tweens, {stiffness,damping,mass} for
 * springs). Consume via `motion.*` so timings stay consistent everywhere — UI
 * components and the navigation transitions both read from here.
 *
 * Spring damping is derived from Compose's damping-ratio so the feel matches:
 *   damping = ratio * 2 * sqrt(stiffness * mass)
 */
import { Easing, type EasingFunction } from 'react-native';

/** Durations in milliseconds. */
export const duration = {
  short: 200,
  medium: 300,
  long: 450,
  extraLong: 550,
} as const;

/** Cubic-bezier easing curves (AppMotion easing constants). */
export const easing: Record<
  'easeInOut' | 'easeOut' | 'easeIn' | 'snappy',
  EasingFunction
> = {
  easeInOut: Easing.bezier(0.25, 0.1, 0.25, 1.0),
  easeOut: Easing.bezier(0.0, 0.0, 0.2, 1.0),
  easeIn: Easing.bezier(0.4, 0.0, 1.0, 1.0),
  snappy: Easing.bezier(0.2, 0.0, 0.0, 1.0),
};

/** Spring presets for Animated.spring (Compose ratio/stiffness → RN physics). */
export interface SpringConfig {
  stiffness: number;
  damping: number;
  mass: number;
}

export const spring: Record<
  'default' | 'snappy' | 'gentle' | 'bouncy',
  SpringConfig
> = {
  // NoBouncy (ratio 1.0) + StiffnessMediumLow (400)
  default: { stiffness: 400, damping: 40, mass: 1 },
  // ratio 0.85 + StiffnessMedium (1500)
  snappy: { stiffness: 1500, damping: 66, mass: 1 },
  // NoBouncy (ratio 1.0) + StiffnessLow (200)
  gentle: { stiffness: 200, damping: 28, mass: 1 },
  // LowBouncy (ratio 0.75) + StiffnessMedium (1500)
  bouncy: { stiffness: 1500, damping: 58, mass: 1 },
};

/** Ready-made Animated.timing configs (duration + curve), mirroring tween* helpers. */
export const timing = {
  short: { duration: duration.short, easing: easing.easeOut },
  medium: { duration: duration.medium, easing: easing.easeInOut },
  long: { duration: duration.long, easing: easing.easeInOut },
  exit: { duration: duration.short, easing: easing.easeIn },
} as const;

export const motion = { duration, easing, spring, timing } as const;

export default motion;
