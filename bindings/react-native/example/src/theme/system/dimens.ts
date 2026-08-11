/**
 * Spacing / size / radius scale — ported from the Android example (ui/theme/Dimens.kt).
 * Read via `useTheme().dimens` so layout never hard-codes magic numbers.
 */
export const dimens = {
  screenPadding: 16,
  spacing: { xs: 4, sm: 8, md: 12, lg: 16, xl: 24 },
  icon: { sm: 18, md: 22, lg: 28 },
  radius: { sm: 8, md: 12, lg: 20, full: 999 },
  inputBarMinHeight: 48,
  contentMaxWidth: 760,
  navDrawerWidth: 260,
} as const;

export type Dimens = typeof dimens;
