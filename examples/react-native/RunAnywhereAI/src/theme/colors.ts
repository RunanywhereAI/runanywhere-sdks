const palette = {
  orange: {
    50: '#FFF3EA',
    100: '#FFE0C8',
    300: '#FF8A3D',
    500: '#E8620A',
    700: '#BF4E00',
    900: '#7A3200',
  },
  neutral: {
    0: '#FFFFFF',
    50: '#FAFAFA',
    100: '#F3F3F3',
    200: '#E6E6E6',
    300: '#D1D1D1',
    400: '#A8A8A8',
    500: '#8A8A8A',
    600: '#5E5E5E',
    700: '#3A3A3C',
    800: '#2C2C2E',
    900: '#1C1C1E',
    950: '#111113',
    1000: '#000000',
  },
  semantic: {
    success: '#2E9E4F',
    successDark: '#30D158',
    warning: '#F57C00',
    warningDark: '#FF9F0A',
    error: '#D14343',
    errorDark: '#FF453A',
    info: '#1E62D0',
    infoDark: '#5EA1FF',
  },
  framework: {
    llamaCpp: '#E8620A',
    whisperKit: '#2E9E4F',
    onnx: '#1E62D0',
    coreML: '#F57C00',
    foundationModels: '#8B5CF6',
    tflite: '#F5B400',
    piperTTS: '#D14343',
    systemTTS: '#8A8A8A',
  },
} as const;

export type ThemeColors = {
  primary: string;
  primarySoft: string;
  onPrimary: string;

  background: string;
  surface: string;
  surfaceAlt: string;
  surfaceRaised: string;

  text: string;
  textSecondary: string;
  textTertiary: string;
  textInverse: string;

  border: string;
  borderStrong: string;

  success: string;
  warning: string;
  error: string;
  info: string;

  userBubble: string;
  onUserBubble: string;
  assistantBubble: string;
  onAssistantBubble: string;

  overlay: string;
  overlayStrong: string;
  shadow: string;
  scheme: 'light' | 'dark';

  primaryAccent: string;
  primaryBlue: string;
  primaryGreen: string;
  primaryRed: string;
  primaryOrange: string;
  primaryPurple: string;

  textPrimary: string;
  textWhite: string;

  backgroundPrimary: string;
  backgroundSecondary: string;
  backgroundTertiary: string;
  backgroundGrouped: string;
  backgroundGray5: string;
  backgroundGray6: string;

  badgeBlue: string;
  badgeGreen: string;
  badgePurple: string;
  badgeOrange: string;
  badgeRed: string;
  badgeGray: string;

  statusGreen: string;
  statusOrange: string;
  statusRed: string;
  statusGray: string;
  statusBlue: string;

  shadowLight: string;
  shadowMedium: string;
  shadowDark: string;
  overlayLight: string;
  overlayMedium: string;

  borderLight: string;
  borderMedium: string;

  userBubbleGradientStart: string;
  userBubbleGradientEnd: string;
  assistantBubbleBg: string;

  frameworkLlamaCpp: string;
  frameworkWhisperKit: string;
  frameworkONNX: string;
  frameworkCoreML: string;
  frameworkFoundationModels: string;
  frameworkTFLite: string;
  frameworkPiperTTS: string;
  frameworkSystemTTS: string;
};

export const lightColors: ThemeColors = {
  primary: palette.orange[500],
  primarySoft: palette.orange[50],
  onPrimary: palette.neutral[0],

  background: palette.neutral[0],
  surface: palette.neutral[50],
  surfaceAlt: palette.neutral[100],
  surfaceRaised: palette.neutral[0],

  text: palette.neutral[1000],
  textSecondary: palette.neutral[600],
  textTertiary: palette.neutral[400],
  textInverse: palette.neutral[0],

  border: palette.neutral[200],
  borderStrong: palette.neutral[300],

  success: palette.semantic.success,
  warning: palette.semantic.warning,
  error: palette.semantic.error,
  info: palette.semantic.info,

  userBubble: palette.orange[500],
  onUserBubble: palette.neutral[0],
  assistantBubble: palette.neutral[100],
  onAssistantBubble: palette.neutral[1000],

  overlay: 'rgba(0, 0, 0, 0.3)',
  overlayStrong: 'rgba(0, 0, 0, 0.5)',
  shadow: 'rgba(0, 0, 0, 0.08)',
  scheme: 'light',

  primaryAccent: palette.orange[500],
  primaryBlue: palette.orange[500],
  primaryGreen: palette.semantic.success,
  primaryRed: palette.semantic.error,
  primaryOrange: palette.orange[500],
  primaryPurple: palette.orange[500],

  textPrimary: palette.neutral[1000],
  textWhite: palette.neutral[0],

  backgroundPrimary: palette.neutral[0],
  backgroundSecondary: palette.neutral[50],
  backgroundTertiary: palette.neutral[0],
  backgroundGrouped: palette.neutral[50],
  backgroundGray5: palette.neutral[200],
  backgroundGray6: palette.neutral[100],

  badgeBlue: 'rgba(232, 98, 10, 0.12)',
  badgeGreen: 'rgba(46, 158, 79, 0.12)',
  badgePurple: 'rgba(26, 26, 26, 0.06)',
  badgeOrange: 'rgba(245, 124, 0, 0.14)',
  badgeRed: 'rgba(209, 67, 67, 0.12)',
  badgeGray: 'rgba(138, 138, 138, 0.14)',

  statusGreen: palette.semantic.success,
  statusOrange: palette.orange[500],
  statusRed: palette.semantic.error,
  statusGray: palette.neutral[500],
  statusBlue: palette.semantic.info,

  shadowLight: 'rgba(0, 0, 0, 0.04)',
  shadowMedium: 'rgba(0, 0, 0, 0.08)',
  shadowDark: 'rgba(0, 0, 0, 0.15)',
  overlayLight: 'rgba(0, 0, 0, 0.3)',
  overlayMedium: 'rgba(0, 0, 0, 0.5)',

  borderLight: palette.neutral[200],
  borderMedium: palette.neutral[300],

  userBubbleGradientStart: palette.orange[500],
  userBubbleGradientEnd: palette.orange[700],
  assistantBubbleBg: palette.neutral[100],

  frameworkLlamaCpp: palette.framework.llamaCpp,
  frameworkWhisperKit: palette.framework.whisperKit,
  frameworkONNX: palette.framework.onnx,
  frameworkCoreML: palette.framework.coreML,
  frameworkFoundationModels: palette.framework.foundationModels,
  frameworkTFLite: palette.framework.tflite,
  frameworkPiperTTS: palette.framework.piperTTS,
  frameworkSystemTTS: palette.framework.systemTTS,
};

export const darkColors: ThemeColors = {
  primary: palette.orange[500],
  primarySoft: 'rgba(232, 98, 10, 0.16)',
  onPrimary: palette.neutral[0],

  background: palette.neutral[1000],
  surface: palette.neutral[900],
  surfaceAlt: palette.neutral[800],
  surfaceRaised: palette.neutral[800],

  text: palette.neutral[0],
  textSecondary: palette.neutral[300],
  textTertiary: palette.neutral[500],
  textInverse: palette.neutral[1000],

  border: palette.neutral[800],
  borderStrong: palette.neutral[700],

  success: palette.semantic.successDark,
  warning: palette.semantic.warningDark,
  error: palette.semantic.errorDark,
  info: palette.semantic.infoDark,

  userBubble: palette.orange[500],
  onUserBubble: palette.neutral[0],
  assistantBubble: palette.neutral[800],
  onAssistantBubble: palette.neutral[0],

  overlay: 'rgba(0, 0, 0, 0.5)',
  overlayStrong: 'rgba(0, 0, 0, 0.7)',
  shadow: 'rgba(0, 0, 0, 0.4)',
  scheme: 'dark',

  primaryAccent: palette.orange[500],
  primaryBlue: palette.orange[500],
  primaryGreen: palette.semantic.successDark,
  primaryRed: palette.semantic.errorDark,
  primaryOrange: palette.orange[500],
  primaryPurple: palette.orange[500],

  textPrimary: palette.neutral[0],
  textWhite: palette.neutral[0],

  backgroundPrimary: palette.neutral[1000],
  backgroundSecondary: palette.neutral[900],
  backgroundTertiary: palette.neutral[800],
  backgroundGrouped: palette.neutral[900],
  backgroundGray5: palette.neutral[700],
  backgroundGray6: palette.neutral[800],

  badgeBlue: 'rgba(232, 98, 10, 0.22)',
  badgeGreen: 'rgba(48, 209, 88, 0.22)',
  badgePurple: 'rgba(255, 255, 255, 0.10)',
  badgeOrange: 'rgba(255, 159, 10, 0.22)',
  badgeRed: 'rgba(255, 69, 58, 0.22)',
  badgeGray: 'rgba(168, 168, 168, 0.18)',

  statusGreen: palette.semantic.successDark,
  statusOrange: palette.orange[500],
  statusRed: palette.semantic.errorDark,
  statusGray: palette.neutral[400],
  statusBlue: palette.semantic.infoDark,

  shadowLight: 'rgba(0, 0, 0, 0.25)',
  shadowMedium: 'rgba(0, 0, 0, 0.40)',
  shadowDark: 'rgba(0, 0, 0, 0.55)',
  overlayLight: 'rgba(0, 0, 0, 0.4)',
  overlayMedium: 'rgba(0, 0, 0, 0.6)',

  borderLight: palette.neutral[800],
  borderMedium: palette.neutral[700],

  userBubbleGradientStart: palette.orange[500],
  userBubbleGradientEnd: palette.orange[700],
  assistantBubbleBg: palette.neutral[800],

  frameworkLlamaCpp: palette.framework.llamaCpp,
  frameworkWhisperKit: palette.semantic.successDark,
  frameworkONNX: palette.semantic.infoDark,
  frameworkCoreML: palette.semantic.warningDark,
  frameworkFoundationModels: palette.framework.foundationModels,
  frameworkTFLite: palette.framework.tflite,
  frameworkPiperTTS: palette.semantic.errorDark,
  frameworkSystemTTS: palette.neutral[400],
};

export const Colors = lightColors;
export const DarkColors = darkColors;

export type ColorKey = keyof ThemeColors;
