/**
 * useThemedStyles — build a StyleSheet from the active color scheme.
 *
 * Factories are declared at module level, so results are cached per
 * (factory, scheme): exactly one StyleSheet per factory for light and one for
 * dark, shared across all component instances.
 *
 *   const styles = useThemedStyles(createStyles);
 *   ...
 *   const createStyles = (colors: ColorScheme) => StyleSheet.create({ ... });
 */
import { useTheme } from './ThemeProvider';
import type { ColorScheme } from './colors';

type StyleFactory<T> = (colors: ColorScheme) => T;

const cache = new WeakMap<
  StyleFactory<unknown>,
  WeakMap<ColorScheme, unknown>
>();

export function useThemedStyles<T extends object>(factory: StyleFactory<T>): T {
  const { colors } = useTheme();
  let byScheme = cache.get(factory as StyleFactory<unknown>);
  if (!byScheme) {
    byScheme = new WeakMap();
    cache.set(factory as StyleFactory<unknown>, byScheme);
  }
  let styles = byScheme.get(colors) as T | undefined;
  if (!styles) {
    styles = factory(colors);
    byScheme.set(colors, styles);
  }
  return styles;
}
