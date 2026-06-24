/**
 * RunAnywhere NPU - theme
 *
 * Orange RunAnywhere palette (matches the Kotlin/Flutter RunAnywhereAiNPU apps):
 * primary #FF6D1F / #E65500, warm neutrals, light + dark schemes.
 */
import { useColorScheme } from 'react-native';

export interface AppColors {
  primary: string;
  primaryDark: string;
  onPrimary: string;
  background: string;
  surface: string;
  surfaceVariant: string;
  onSurface: string;
  onSurfaceVariant: string;
  outline: string;
  success: string;
  warning: string;
  error: string;
  dark: boolean;
}

const LIGHT: AppColors = {
  primary: '#FF6D1F',
  primaryDark: '#E65500',
  onPrimary: '#FFFFFF',
  background: '#FAF7F4',
  surface: '#FFFFFF',
  surfaceVariant: '#F2ECE6',
  onSurface: '#1C1B1A',
  onSurfaceVariant: '#6B6660',
  outline: '#E5DFD8',
  success: '#2E7D32',
  warning: '#B26A00',
  error: '#C62828',
  dark: false,
};

const DARK: AppColors = {
  primary: '#FF8A4C',
  primaryDark: '#FF6D1F',
  onPrimary: '#231200',
  background: '#121110',
  surface: '#1E1C1A',
  surfaceVariant: '#26231F',
  onSurface: '#ECE7E1',
  onSurfaceVariant: '#A8A29A',
  outline: '#34302B',
  success: '#7FD18B',
  warning: '#E0A458',
  error: '#F2877F',
  dark: true,
};

export function useAppColors(): AppColors {
  return useColorScheme() === 'dark' ? DARK : LIGHT;
}

export const Radius = { sm: 8, md: 12, lg: 16, xl: 22 };
export const Space = { xs: 4, sm: 8, md: 12, lg: 16, xl: 24, xxl: 32 };
/** Centered content max width on tablets / split-screen / landscape. */
export const CONTENT_MAX_WIDTH = 640;

/** Monospace family for metric values (matches Maple Mono usage in siblings). */
export const MONO = { fontFamily: undefined as string | undefined };
