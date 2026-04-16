import { useContext } from 'react';
import { ThemeContext } from './ThemeProvider';
import { lightColors } from './colors';
import type { ThemeColors } from './colors';
import type { ResolvedScheme, ThemeMode } from './ThemeProvider';

type UseThemeResult = {
  colors: ThemeColors;
  scheme: ResolvedScheme;
  mode: ThemeMode;
  setMode: (mode: ThemeMode) => void;
};

export function useTheme(): UseThemeResult {
  const ctx = useContext(ThemeContext);
  if (!ctx) {
    return {
      colors: lightColors,
      scheme: 'light',
      mode: 'system',
      setMode: () => {},
    };
  }
  return ctx;
}
