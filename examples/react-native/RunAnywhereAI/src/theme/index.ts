/**
 * Theme System - Unified export
 *
 * Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/Design/
 */

import { Colors, DarkColors } from './colors';
import { Typography } from './typography';
import {
  Spacing,
  Padding,
  IconSize,
  ButtonHeight,
  BorderRadius,
  ShadowRadius,
  AnimationDuration,
  Layout,
} from './spacing';

export { Colors, DarkColors } from './colors';
export type { ColorKey } from './colors';

export { Typography, FontWeight, fontSize } from './typography';
export type { TypographyKey } from './typography';

export {
  Spacing,
  Padding,
  IconSize,
  ButtonHeight,
  BorderRadius,
  ShadowRadius,
  AnimationDuration,
  Layout,
} from './spacing';
export type { SpacingKey, IconSizeKey } from './spacing';

/**
 * Combined theme object for convenience
 */
export const Theme = {
  colors: Colors,
  darkColors: DarkColors,
  typography: Typography,
  spacing: Spacing,
  padding: Padding,
  iconSize: IconSize,
  buttonHeight: ButtonHeight,
  borderRadius: BorderRadius,
  shadowRadius: ShadowRadius,
  animationDuration: AnimationDuration,
  layout: Layout,
};
