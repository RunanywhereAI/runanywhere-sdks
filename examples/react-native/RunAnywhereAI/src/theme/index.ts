/**
 * Theme System - Unified export
 *
 * Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/Design/
 */

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
  colors: require('./colors').Colors,
  darkColors: require('./colors').DarkColors,
  typography: require('./typography').Typography,
  spacing: require('./spacing').Spacing,
  padding: require('./spacing').Padding,
  iconSize: require('./spacing').IconSize,
  buttonHeight: require('./spacing').ButtonHeight,
  borderRadius: require('./spacing').BorderRadius,
  shadowRadius: require('./spacing').ShadowRadius,
  animationDuration: require('./spacing').AnimationDuration,
  layout: require('./spacing').Layout,
};
