/**
 * Theme provider + useTheme hook — the single accessor screens use for design
 * tokens. Resolves the active color scheme from the OS (light/dark) and bundles
 * colors + dimens + motion into one object. Wrap the app once near the root;
 * read anywhere via `const { colors, dimens, motion } = useTheme()`.
 */
import React, { createContext, useContext, useMemo } from 'react';
import { useColorScheme } from 'react-native';
import { lightScheme, darkScheme, type ColorScheme } from './colors';
import { dimens, type Dimens } from './dimens';
import { motion } from './motion';
import { typography, type Typography } from './typography';

export interface Theme {
  colors: ColorScheme;
  dimens: Dimens;
  motion: typeof motion;
  typography: Typography;
  dark: boolean;
}

const ThemeContext = createContext<Theme>({
  colors: lightScheme,
  dimens,
  motion,
  typography,
  dark: false,
});

export const ThemeProvider: React.FC<{ children: React.ReactNode }> = ({
  children,
}) => {
  const dark = useColorScheme() === 'dark';
  const theme = useMemo<Theme>(
    () => ({
      colors: dark ? darkScheme : lightScheme,
      dimens,
      motion,
      typography,
      dark,
    }),
    [dark]
  );
  return (
    <ThemeContext.Provider value={theme}>{children}</ThemeContext.Provider>
  );
};

export const useTheme = (): Theme => useContext(ThemeContext);
