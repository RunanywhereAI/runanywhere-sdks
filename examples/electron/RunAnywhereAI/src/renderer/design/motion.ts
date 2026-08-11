/**
 * The motion vocabulary, transcribed from `Core/DesignSystem/Motion.swift`.
 *
 * Motion.swift says every animation MUST route through `motionAware(_:value:)` so
 * the accessibility path cannot be forgotten. This module is that single seam: ask
 * for a named tier, get a transition string that already honours Reduce Motion.
 *
 * Durations and eases live in `tokens.css`; this file reads them so there is
 * exactly one definition of each value.
 */

/** Discrete transitions: a state change the user did not drag. */
export type MotionTier = 'micro' | 'standard' | 'emphasis' | 'hero';

/**
 * Direct-manipulation transitions. SwiftUI expresses these as
 * `spring(response:dampingFraction:)`; CSS has no spring, so each is a measured
 * settle time paired with the spring ease.
 */
export type SpringTier = 'snappy' | 'standard' | 'gentle' | 'bouncy';

/** Repeating ambient motion. `breathe` alternates; the others do not. */
export type AmbientTier = 'breathe' | 'shimmer' | 'spin';

const TIER_VAR: Readonly<Record<MotionTier, string>> = {
  micro: '--ra-duration-micro',
  standard: '--ra-duration-standard',
  emphasis: '--ra-duration-emphasis',
  hero: '--ra-duration-hero',
};

const SPRING_VAR: Readonly<Record<SpringTier, string>> = {
  snappy: '--ra-spring-snappy',
  standard: '--ra-spring-standard',
  gentle: '--ra-spring-gentle',
  bouncy: '--ra-spring-bouncy',
};

const AMBIENT_VAR: Readonly<Record<AmbientTier, string>> = {
  breathe: '--ra-ambient-breathe',
  shimmer: '--ra-ambient-shimmer',
  spin: '--ra-ambient-spin',
};

const reduceMotionQuery = (): MediaQueryList | null =>
  typeof window === 'undefined' ? null : window.matchMedia('(prefers-reduced-motion: reduce)');

/** True when the user has asked for reduced motion. */
export function prefersReducedMotion(): boolean {
  return reduceMotionQuery()?.matches ?? false;
}

/** Call `onChange` whenever the Reduce Motion preference flips. Returns an unsubscribe. */
export function onReducedMotionChange(onChange: (reduced: boolean) => void): () => void {
  const query = reduceMotionQuery();
  if (query === null) return () => undefined;
  const handler = (event: MediaQueryListEvent): void => onChange(event.matches);
  query.addEventListener('change', handler);
  return () => query.removeEventListener('change', handler);
}

/**
 * A `transition` value for one or more properties at a discrete tier.
 *
 * Under Reduce Motion this collapses to the 150 ms crossfade Motion.swift
 * specifies — the change must be *perceived*, not blinked past, which is why it
 * is not zero.
 */
export function transition(tier: MotionTier, properties: readonly string[] = ['all']): string {
  if (prefersReducedMotion()) {
    return properties.map((p) => `${p} var(--ra-reduced-fallback) var(--ra-ease-in-out)`).join(', ');
  }
  return properties.map((p) => `${p} var(${TIER_VAR[tier]}) var(--ra-ease-out)`).join(', ');
}

/** A `transition` value for a direct-manipulation spring. */
export function springTransition(tier: SpringTier, properties: readonly string[] = ['all']): string {
  if (prefersReducedMotion()) {
    return properties.map((p) => `${p} var(--ra-reduced-fallback) var(--ra-ease-in-out)`).join(', ');
  }
  return properties.map((p) => `${p} var(${SPRING_VAR[tier]}) var(--ra-ease-spring)`).join(', ');
}

/**
 * An `animation` value for repeating ambient motion, or `'none'` under Reduce
 * Motion — `resolveAmbient` in Motion.swift returns nil there, suppressing the
 * animation entirely rather than merely shortening it.
 */
export function ambient(name: string, tier: AmbientTier): string {
  if (prefersReducedMotion()) return 'none';
  const alternate = tier === 'breathe' ? ' alternate' : '';
  return `${name} var(${AMBIENT_VAR[tier]}) var(--ra-ease-in-out) infinite${alternate}`;
}

/**
 * Run `mutate`, then let the browser animate to the new state. Under Reduce
 * Motion the mutation still happens; only its animation is suppressed by the
 * stylesheet's media query, so callers need no branch of their own.
 */
export function withMotion(element: HTMLElement, tier: MotionTier, mutate: () => void): void {
  element.style.transition = transition(tier);
  mutate();
}
