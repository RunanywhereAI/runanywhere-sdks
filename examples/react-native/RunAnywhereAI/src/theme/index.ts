import { Colors, DarkColors, lightColors, darkColors } from './colors';
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

export { Colors, DarkColors, lightColors, darkColors } from './colors';
export type { ColorKey, ThemeColors } from './colors';

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

export { ThemeProvider, ThemeContext } from './ThemeProvider';
export type { ThemeMode, ResolvedScheme } from './ThemeProvider';
export { useTheme } from './useTheme';

export const Theme = {
  colors: Colors,
  darkColors: DarkColors,
  light: lightColors,
  dark: darkColors,
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
