/**
 * Typography System - Matching iOS AppTypography.swift
 *
 * Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/Design/AppTypography.swift
 */

import type { TextStyle } from 'react-native';
import { Platform } from 'react-native';

const fontFamily = Platform.select({
  ios: 'System',
  android: 'Roboto',
  default: 'System',
});

/**
 * Font weights mapped to numeric values
 */
export const FontWeight = {
  regular: '400' as const,
  medium: '500' as const,
  semibold: '600' as const,
  bold: '700' as const,
};

/**
 * Typography styles matching iOS system fonts
 */
export const Typography = {
  // Large Title - used for primary headings
  largeTitle: {
    fontSize: 34,
    fontWeight: FontWeight.bold,
    lineHeight: 41,
    letterSpacing: 0.37,
    fontFamily,
  } satisfies TextStyle,

  // Title - main titles
  title: {
    fontSize: 28,
    fontWeight: FontWeight.bold,
    lineHeight: 34,
    letterSpacing: 0.36,
    fontFamily,
  } satisfies TextStyle,

  // Title 2 - secondary titles
  title2: {
    fontSize: 22,
    fontWeight: FontWeight.bold,
    lineHeight: 28,
    letterSpacing: 0.35,
    fontFamily,
  } satisfies TextStyle,

  // Title 3 - tertiary titles
  title3: {
    fontSize: 20,
    fontWeight: FontWeight.semibold,
    lineHeight: 25,
    letterSpacing: 0.38,
    fontFamily,
  } satisfies TextStyle,

  // Headline - section headers
  headline: {
    fontSize: 17,
    fontWeight: FontWeight.semibold,
    lineHeight: 22,
    letterSpacing: -0.41,
    fontFamily,
  } satisfies TextStyle,

  // Body - main text content
  body: {
    fontSize: 17,
    fontWeight: FontWeight.regular,
    lineHeight: 22,
    letterSpacing: -0.41,
    fontFamily,
  } satisfies TextStyle,

  // Callout - emphasized text
  callout: {
    fontSize: 16,
    fontWeight: FontWeight.regular,
    lineHeight: 21,
    letterSpacing: -0.32,
    fontFamily,
  } satisfies TextStyle,

  // Subheadline - secondary text
  subheadline: {
    fontSize: 15,
    fontWeight: FontWeight.regular,
    lineHeight: 20,
    letterSpacing: -0.24,
    fontFamily,
  } satisfies TextStyle,

  // Footnote - small text
  footnote: {
    fontSize: 13,
    fontWeight: FontWeight.regular,
    lineHeight: 18,
    letterSpacing: -0.08,
    fontFamily,
  } satisfies TextStyle,

  // Caption - smallest readable text
  caption: {
    fontSize: 12,
    fontWeight: FontWeight.regular,
    lineHeight: 16,
    letterSpacing: 0,
    fontFamily,
  } satisfies TextStyle,

  // Caption 2 - very small text
  caption2: {
    fontSize: 11,
    fontWeight: FontWeight.regular,
    lineHeight: 13,
    letterSpacing: 0.06,
    fontFamily,
  } satisfies TextStyle,

  // Monospaced caption - for code/metrics
  monospacedCaption: {
    fontSize: 12,
    fontWeight: FontWeight.bold,
    lineHeight: 16,
    letterSpacing: 0,
    fontFamily: Platform.select({
      ios: 'Menlo',
      android: 'monospace',
      default: 'monospace',
    }),
  } satisfies TextStyle,
} as const;

/**
 * Create a text style with a specific size
 */
export function fontSize(
  size: number,
  weight: keyof typeof FontWeight = 'regular'
): TextStyle {
  return {
    fontSize: size,
    fontWeight: FontWeight[weight],
    fontFamily,
  };
}

export type TypographyKey = keyof typeof Typography;
