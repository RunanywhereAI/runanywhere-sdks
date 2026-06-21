/**
 * Type scale — ported from the Android example (ui/theme/Type.kt). Figtree for
 * UI, Maple Mono for code/metrics (both bundled in assets/fonts). Read via
 * `useTheme().typography`, e.g. `style={typography.titleLarge}`.
 *
 * Font files must be linked (react-native.config.js `assets` → `npx react-native-asset`)
 * and the app rebuilt for these families to render; until then text falls back
 * to the system font at the same sizes.
 */
import type { TextStyle } from 'react-native';

export const fontFamily = { sans: 'Figtree', mono: 'MapleMono' } as const;

const sans = fontFamily.sans;
const mono = fontFamily.mono;

export const typography = {
  displayLarge: { fontFamily: sans, fontWeight: '700', fontSize: 57, lineHeight: 64, letterSpacing: -0.25 },
  displayMedium: { fontFamily: sans, fontWeight: '700', fontSize: 45, lineHeight: 52, letterSpacing: 0 },
  displaySmall: { fontFamily: sans, fontWeight: '600', fontSize: 36, lineHeight: 44, letterSpacing: 0 },
  headlineLarge: { fontFamily: sans, fontWeight: '600', fontSize: 32, lineHeight: 40, letterSpacing: 0 },
  headlineMedium: { fontFamily: sans, fontWeight: '600', fontSize: 28, lineHeight: 36, letterSpacing: 0 },
  headlineSmall: { fontFamily: sans, fontWeight: '600', fontSize: 24, lineHeight: 32, letterSpacing: 0 },
  titleLarge: { fontFamily: sans, fontWeight: '600', fontSize: 22, lineHeight: 28, letterSpacing: 0 },
  titleMedium: { fontFamily: sans, fontWeight: '600', fontSize: 16, lineHeight: 24, letterSpacing: 0.15 },
  titleSmall: { fontFamily: sans, fontWeight: '500', fontSize: 14, lineHeight: 20, letterSpacing: 0.1 },
  bodyLarge: { fontFamily: sans, fontWeight: '400', fontSize: 16, lineHeight: 24, letterSpacing: 0.5 },
  bodyMedium: { fontFamily: sans, fontWeight: '400', fontSize: 14, lineHeight: 20, letterSpacing: 0.25 },
  bodySmall: { fontFamily: sans, fontWeight: '400', fontSize: 12, lineHeight: 16, letterSpacing: 0.4 },
  labelLarge: { fontFamily: sans, fontWeight: '500', fontSize: 14, lineHeight: 20, letterSpacing: 0.1 },
  labelMedium: { fontFamily: sans, fontWeight: '500', fontSize: 12, lineHeight: 16, letterSpacing: 0.5 },
  labelSmall: { fontFamily: sans, fontWeight: '500', fontSize: 11, lineHeight: 16, letterSpacing: 0.5 },
  // Mono — code / model output / metrics.
  code: { fontFamily: mono, fontWeight: '400', fontSize: 14, lineHeight: 22, letterSpacing: 0 },
  codeSmall: { fontFamily: mono, fontWeight: '400', fontSize: 12, lineHeight: 18, letterSpacing: 0 },
  metric: { fontFamily: mono, fontWeight: '500', fontSize: 13, lineHeight: 16, letterSpacing: 0 },
} as const satisfies Record<string, TextStyle>;

export type Typography = typeof typography;
