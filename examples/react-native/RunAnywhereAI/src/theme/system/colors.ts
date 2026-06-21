/**
 * Color tokens — ported 1:1 from the Android example app
 * (ui/theme/Color.kt + the Material3 light/dark schemes in Theme.kt).
 *
 * `palette` holds the raw tonal ramps; `lightScheme`/`darkScheme` map them onto
 * Material3 semantic roles. UI code never reads `palette` directly — it reads
 * roles via `useTheme().colors`, so light/dark stays a single switch.
 */

// Raw tonal palette (Color.kt)
const palette = {
  // Primary — Orange
  primary20: '#4E1C00',
  primary30: '#732B00',
  primary60: '#E65500',
  primary70: '#FF6D1F',
  primary80: '#FFB693',
  primary90: '#FFDBCA',

  // Secondary — Warm Neutral
  secondary10: '#1F1A17',
  secondary20: '#352F2B',
  secondary30: '#4C4541',
  secondary40: '#655D58',
  secondary80: '#D0C5BF',
  secondary90: '#EDE0DA',

  // Tertiary — Warm Gold
  tertiary10: '#231B00',
  tertiary20: '#3B3000',
  tertiary30: '#554600',
  tertiary40: '#705D00',
  tertiary80: '#E5C52A',
  tertiary90: '#F4E07A',

  // Error
  error10: '#410002',
  error20: '#690005',
  error30: '#93000A',
  error40: '#BA1A1A',
  error80: '#FFB4AB',
  error90: '#FFDAD6',

  // Neutral — Surfaces
  neutral4: '#0F0F0F',
  neutral6: '#141414',
  neutral10: '#1C1B1B',
  neutral12: '#201F1F',
  neutral17: '#2B2A2A',
  neutral20: '#313030',
  neutral22: '#363534',
  neutral90: '#E6E1E0',
  neutral92: '#ECE6E4',
  neutral94: '#F2ECEA',
  neutral95: '#F5F0EE',
  neutral96: '#F8F2F0',
  neutral98: '#FEF8F6',
  neutral99: '#FFFBFF',
  neutral100: '#FFFFFF',

  // Neutral Variant — Outlines & surface tints
  neutralVariant30: '#4E4542',
  neutralVariant50: '#807672',
  neutralVariant60: '#9B908B',
  neutralVariant80: '#D1C5C0',
  neutralVariant90: '#EDE0DB',

  // Success
  green: '#10B981', // Emerald-500
} as const;

/** Material3 semantic color roles. Identical key set for light & dark. */
export interface ColorScheme {
  primary: string;
  onPrimary: string;
  primaryContainer: string;
  onPrimaryContainer: string;
  secondary: string;
  onSecondary: string;
  secondaryContainer: string;
  onSecondaryContainer: string;
  tertiary: string;
  onTertiary: string;
  tertiaryContainer: string;
  onTertiaryContainer: string;
  error: string;
  onError: string;
  errorContainer: string;
  onErrorContainer: string;
  background: string;
  onBackground: string;
  surface: string;
  onSurface: string;
  surfaceVariant: string;
  onSurfaceVariant: string;
  surfaceContainerLowest: string;
  surfaceContainerLow: string;
  surfaceContainer: string;
  surfaceContainerHigh: string;
  surfaceContainerHighest: string;
  surfaceTint: string;
  outline: string;
  outlineVariant: string;
  inverseSurface: string;
  inverseOnSurface: string;
  inversePrimary: string;
  scrim: string;
  /** Non-Material role kept from the Android palette for success states. */
  success: string;
}

export const lightScheme: ColorScheme = {
  primary: palette.primary60,
  onPrimary: palette.neutral99,
  primaryContainer: palette.primary90,
  onPrimaryContainer: palette.primary20,
  secondary: palette.secondary40,
  onSecondary: palette.neutral99,
  secondaryContainer: palette.secondary90,
  onSecondaryContainer: palette.secondary10,
  tertiary: palette.tertiary40,
  onTertiary: palette.neutral99,
  tertiaryContainer: palette.tertiary90,
  onTertiaryContainer: palette.tertiary10,
  error: palette.error40,
  onError: palette.neutral99,
  errorContainer: palette.error90,
  onErrorContainer: palette.error10,
  background: palette.neutral98,
  onBackground: palette.neutral10,
  surface: palette.neutral98,
  onSurface: palette.neutral10,
  surfaceVariant: palette.neutralVariant90,
  onSurfaceVariant: palette.neutralVariant30,
  surfaceContainerLowest: palette.neutral100,
  surfaceContainerLow: palette.neutral96,
  surfaceContainer: palette.neutral94,
  surfaceContainerHigh: palette.neutral92,
  surfaceContainerHighest: palette.neutral90,
  surfaceTint: palette.primary60,
  outline: palette.neutralVariant50,
  outlineVariant: palette.neutralVariant80,
  inverseSurface: palette.neutral20,
  inverseOnSurface: palette.neutral95,
  inversePrimary: palette.primary80,
  scrim: palette.neutral10,
  success: palette.green,
};

export const darkScheme: ColorScheme = {
  primary: palette.primary70,
  onPrimary: palette.primary20,
  primaryContainer: palette.primary30,
  onPrimaryContainer: palette.primary90,
  secondary: palette.secondary80,
  onSecondary: palette.secondary20,
  secondaryContainer: palette.secondary30,
  onSecondaryContainer: palette.secondary90,
  tertiary: palette.tertiary80,
  onTertiary: palette.tertiary20,
  tertiaryContainer: palette.tertiary30,
  onTertiaryContainer: palette.tertiary90,
  error: palette.error80,
  onError: palette.error20,
  errorContainer: palette.error30,
  onErrorContainer: palette.error90,
  background: palette.neutral6,
  onBackground: palette.neutral90,
  surface: palette.neutral6,
  onSurface: palette.neutral90,
  surfaceVariant: palette.neutralVariant30,
  onSurfaceVariant: palette.neutralVariant80,
  surfaceContainerLowest: palette.neutral4,
  surfaceContainerLow: palette.neutral10,
  surfaceContainer: palette.neutral12,
  surfaceContainerHigh: palette.neutral17,
  surfaceContainerHighest: palette.neutral22,
  surfaceTint: palette.primary70,
  outline: palette.neutralVariant60,
  outlineVariant: palette.neutralVariant30,
  inverseSurface: palette.neutral90,
  inverseOnSurface: palette.neutral20,
  inversePrimary: palette.primary60,
  scrim: palette.neutral10,
  success: palette.green,
};
