/**
 * Color System - Matching iOS AppColors.swift
 *
 * Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/Design/AppColors.swift
 */

export const Colors = {
  // Primary Colors
  primaryAccent: '#007AFF',
  primaryBlue: '#007AFF',
  primaryGreen: '#34C759',
  primaryRed: '#FF3B30',
  primaryOrange: '#FF9500',
  primaryPurple: '#AF52DE',

  // Text Colors
  textPrimary: '#000000',
  textSecondary: '#8E8E93',
  textTertiary: '#C7C7CC',
  textWhite: '#FFFFFF',

  // Background Colors - Light Mode
  backgroundPrimary: '#FFFFFF',
  backgroundSecondary: '#F2F2F7',
  backgroundTertiary: '#FFFFFF',
  backgroundGrouped: '#F2F2F7',
  backgroundGray5: '#E5E5EA',
  backgroundGray6: '#F2F2F7',

  // Component Badges
  badgeBlue: 'rgba(0, 122, 255, 0.12)',
  badgeGreen: 'rgba(52, 199, 89, 0.12)',
  badgePurple: 'rgba(175, 82, 222, 0.12)',
  badgeOrange: 'rgba(255, 149, 0, 0.12)',
  badgeRed: 'rgba(255, 59, 48, 0.12)',
  badgeGray: 'rgba(142, 142, 147, 0.12)',

  // Status Colors
  statusGreen: '#34C759',
  statusOrange: '#FF9500',
  statusRed: '#FF3B30',
  statusGray: '#8E8E93',
  statusBlue: '#007AFF',

  // Shadows & Overlays
  shadowLight: 'rgba(0, 0, 0, 0.04)',
  shadowMedium: 'rgba(0, 0, 0, 0.08)',
  shadowDark: 'rgba(0, 0, 0, 0.15)',
  overlayLight: 'rgba(0, 0, 0, 0.3)',
  overlayMedium: 'rgba(0, 0, 0, 0.5)',

  // Borders
  borderLight: 'rgba(60, 60, 67, 0.12)',
  borderMedium: 'rgba(60, 60, 67, 0.29)',

  // Message Bubbles
  userBubbleGradientStart: '#007AFF',
  userBubbleGradientEnd: '#5856D6',
  assistantBubbleBg: '#E5E5EA',

  // Framework-specific colors (from iOS)
  frameworkLlamaCpp: '#FF6B35',
  frameworkWhisperKit: '#00C853',
  frameworkONNX: '#1E88E5',
  frameworkCoreML: '#FF9500',
  frameworkFoundationModels: '#AF52DE',
  frameworkTFLite: '#FFC107',
  frameworkPiperTTS: '#E91E63',
  frameworkSystemTTS: '#8E8E93',
} as const;

/**
 * Dark mode color overrides
 */
export const DarkColors: Record<string, string> = {
  // Primary Colors (adjusted for dark mode)
  primaryAccent: '#0A84FF',
  primaryBlue: '#0A84FF',
  primaryGreen: '#30D158',
  primaryRed: '#FF453A',
  primaryOrange: '#FF9F0A',
  primaryPurple: '#BF5AF2',

  // Text Colors
  textPrimary: '#FFFFFF',
  textSecondary: '#8E8E93',
  textTertiary: '#48484A',

  // Background Colors - Dark Mode
  backgroundPrimary: '#000000',
  backgroundSecondary: '#1C1C1E',
  backgroundTertiary: '#2C2C2E',
  backgroundGrouped: '#1C1C1E',
  backgroundGray5: '#3A3A3C',
  backgroundGray6: '#2C2C2E',

  // Message Bubbles
  userBubbleGradientStart: '#0A84FF',
  userBubbleGradientEnd: '#5E5CE6',
  assistantBubbleBg: '#3A3A3C',

  // Borders
  borderLight: 'rgba(84, 84, 88, 0.65)',
  borderMedium: 'rgba(84, 84, 88, 0.90)',
};

export type ColorKey = keyof typeof Colors;
