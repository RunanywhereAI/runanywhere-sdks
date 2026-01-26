/**
 * DoorDash Theme - Clone of DoorDash's design system
 * 
 * Color palette, typography, and spacing matching DoorDash's mobile app
 */

export const DoorDashColors = {
  // Primary Brand Colors
  primary: '#FF3008', // DoorDash Red
  primaryDark: '#C8200A',
  primaryLight: '#FF6B4D',
  
  // Secondary Colors
  secondary: '#191919', // Almost black
  secondaryLight: '#494949',
  
  // Background Colors
  background: '#FFFFFF',
  backgroundSecondary: '#F5F5F5',
  backgroundTertiary: '#EBEBEB',
  backgroundDark: '#191919',
  
  // Text Colors
  textPrimary: '#191919',
  textSecondary: '#767676',
  textTertiary: '#ABABAB',
  textWhite: '#FFFFFF',
  textLink: '#0066FF',
  
  // Status Colors
  success: '#00AA4F',
  successLight: '#E6F7ED',
  warning: '#FF9500',
  warningLight: '#FFF4E5',
  error: '#FF3B30',
  errorLight: '#FFEBEA',
  
  // UI Colors
  border: '#E8E8E8',
  borderDark: '#CCCCCC',
  divider: '#F0F0F0',
  cardShadow: 'rgba(0, 0, 0, 0.08)',
  overlay: 'rgba(0, 0, 0, 0.5)',
  
  // Rating Colors
  ratingGold: '#FF8C00',
  ratingGreen: '#00AA4F',
  
  // Promo Colors
  promoGreen: '#00AA4F',
  promoPurple: '#7B61FF',
  promoBlue: '#0066FF',
  
  // DashPass Colors
  dashPassPurple: '#7B61FF',
  dashPassBackground: '#F5F0FF',
} as const;

export const DoorDashTypography = {
  // Headers
  headerLarge: {
    fontSize: 28,
    fontWeight: '700' as const,
    lineHeight: 34,
    letterSpacing: -0.5,
  },
  headerMedium: {
    fontSize: 22,
    fontWeight: '700' as const,
    lineHeight: 28,
    letterSpacing: -0.3,
  },
  headerSmall: {
    fontSize: 18,
    fontWeight: '600' as const,
    lineHeight: 24,
    letterSpacing: -0.2,
  },
  
  // Body Text
  bodyLarge: {
    fontSize: 16,
    fontWeight: '400' as const,
    lineHeight: 22,
    letterSpacing: 0,
  },
  bodyMedium: {
    fontSize: 14,
    fontWeight: '400' as const,
    lineHeight: 20,
    letterSpacing: 0,
  },
  bodySmall: {
    fontSize: 12,
    fontWeight: '400' as const,
    lineHeight: 16,
    letterSpacing: 0,
  },
  
  // Special Text
  price: {
    fontSize: 16,
    fontWeight: '600' as const,
    lineHeight: 22,
  },
  priceStrike: {
    fontSize: 14,
    fontWeight: '400' as const,
    lineHeight: 20,
    textDecorationLine: 'line-through' as const,
  },
  badge: {
    fontSize: 11,
    fontWeight: '600' as const,
    lineHeight: 14,
    letterSpacing: 0.3,
    textTransform: 'uppercase' as const,
  },
  button: {
    fontSize: 16,
    fontWeight: '600' as const,
    lineHeight: 22,
  },
  caption: {
    fontSize: 11,
    fontWeight: '400' as const,
    lineHeight: 14,
  },
} as const;

export const DoorDashSpacing = {
  // Base spacing
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 20,
  xxl: 24,
  xxxl: 32,
  
  // Specific spacing
  cardPadding: 16,
  sectionPadding: 20,
  screenPadding: 16,
  itemGap: 12,
  
  // Border radius
  radiusSmall: 4,
  radiusMedium: 8,
  radiusLarge: 12,
  radiusXLarge: 16,
  radiusFull: 9999,
} as const;

export const DoorDashShadows = {
  card: {
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.08,
    shadowRadius: 8,
    elevation: 3,
  },
  cardHover: {
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.12,
    shadowRadius: 12,
    elevation: 5,
  },
  button: {
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.15,
    shadowRadius: 4,
    elevation: 2,
  },
  floating: {
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.2,
    shadowRadius: 12,
    elevation: 8,
  },
} as const;
