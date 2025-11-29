/**
 * Spacing System - Matching iOS AppSpacing.swift
 *
 * Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/Design/AppSpacing.swift
 */

/**
 * Semantic spacing values
 */
export const Spacing = {
  // Extra small values
  xxSmall: 2,
  xSmall: 4,
  small: 6,
  smallMedium: 8,

  // Medium values
  medium: 10,
  mediumLarge: 12,
  regular: 14,

  // Large values
  large: 16,
  xLarge: 20,
  xxLarge: 30,
  xxxLarge: 40,

  // Extra large values
  huge: 48,
  massive: 60,
} as const;

/**
 * Padding presets
 */
export const Padding = {
  padding4: 4,
  padding6: 6,
  padding8: 8,
  padding10: 10,
  padding12: 12,
  padding14: 14,
  padding16: 16,
  padding20: 20,
  padding24: 24,
  padding30: 30,
  padding40: 40,
  padding48: 48,
  padding60: 60,
  padding80: 80,
  padding100: 100,
} as const;

/**
 * Icon sizes
 */
export const IconSize = {
  small: 8,
  regular: 18,
  medium: 28,
  large: 48,
  xLarge: 60,
  xxLarge: 72,
  huge: 80,
} as const;

/**
 * Button heights
 */
export const ButtonHeight = {
  small: 28,
  regular: 44,
  large: 72,
} as const;

/**
 * Corner radius values
 */
export const BorderRadius = {
  small: 4,
  regular: 8,
  medium: 10,
  large: 12,
  xLarge: 16,
  pill: 20,
  circle: 9999,
} as const;

/**
 * Shadow radius values
 */
export const ShadowRadius = {
  small: 2,
  regular: 4,
  medium: 6,
  large: 8,
  xLarge: 10,
} as const;

/**
 * Animation durations (in milliseconds)
 */
export const AnimationDuration = {
  fast: 250,
  regular: 300,
  slow: 500,
  verySlow: 600,
  loop: 1000,
  loopSlow: 2000,
} as const;

/**
 * Layout constants
 */
export const Layout = {
  // Message bubble max width (75% of screen)
  messageBubbleMaxWidth: 0.75,

  // Modal dimensions
  modalMinWidth: 320,
  modalIdealWidth: 400,
  modalMaxWidth: 500,

  // Sheet dimensions
  sheetMinHeight: 400,
  sheetIdealHeight: 600,
  sheetMaxHeight: 800,

  // Input heights
  inputMinHeight: 44,
  textAreaMinHeight: 120,
} as const;

export type SpacingKey = keyof typeof Spacing;
export type IconSizeKey = keyof typeof IconSize;
