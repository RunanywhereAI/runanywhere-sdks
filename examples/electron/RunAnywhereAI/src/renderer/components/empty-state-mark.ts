/**
 * The composed brand mark used on empty states.
 *
 * Transcribed from `Core/DesignSystem/EmptyStateMark.swift`: a 3-layer figure,
 * back to front — **bloom → aperture → glyph**.
 *
 * **Motion: none, deliberately.** It previously breathed on the ambient period and
 * rotated a trimmed arc; both were cut, because *"an empty state is not working on
 * anything … a still, well-drawn mark reads as designed; a pulsing one reads as a
 * spinner that never resolves."* Do not add an animation here.
 *
 * The figure is decorative: the caller's title and message already say what it is,
 * so it is `aria-hidden`.
 */
import { icon, type IconName } from './icons';

export interface EmptyStateMarkOptions {
  /** Figure diameter. 132 is the hero size; 88 fits inside a card. */
  readonly diameter?: number;
  /** Accent this surface is themed with. Defaults to the brand orange. */
  readonly tint?: string;
}

export function emptyStateMark(glyph: IconName, options: EmptyStateMarkOptions = {}): HTMLElement {
  const { diameter = 132, tint = 'var(--ra-brand)' } = options;

  // The aperture sits inside a D × 0.06 inset, so its box is D × 0.88.
  const inset = diameter * 0.06;
  const box = diameter - inset * 2;
  const center = diameter / 2;
  // Ring 1 uses SwiftUI's .strokeBorder (drawn entirely inside the bounds), so
  // its path radius is inset by half the stroke width. Ring 2 uses .stroke,
  // which is centred on the path.
  const structureRadius = (box - 2) / 2;
  const arcRadius = box / 2;
  const arcCircumference = 2 * Math.PI * arcRadius;
  // trim(from: 0, to: 0.22) — 22% of the circumference, 79.2°.
  const arcLength = arcCircumference * 0.22;
  // The glyph is 34% of the figure so the ring reads as an aperture around it
  // rather than a tight collar.
  const glyphSize = diameter * 0.34;

  const wrap = document.createElement('div');
  wrap.className = 'ra-mark';
  wrap.setAttribute('aria-hidden', 'true');
  wrap.style.setProperty('--ra-mark-d', `${diameter}px`);
  wrap.style.setProperty('--ra-mark-tint', tint);

  const bloom = document.createElement('div');
  bloom.className = 'ra-mark-bloom';

  // SVG is the right tool for a trimmed arc. `.trim` begins at 3 o'clock, and an
  // arc hanging off the right side looks like an accident rather than a crown —
  // hence the -90° rotation that moves it to 12 o'clock, sweeping clockwise.
  const aperture = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  aperture.setAttribute('class', 'ra-mark-aperture');
  aperture.setAttribute('viewBox', `0 0 ${diameter} ${diameter}`);
  aperture.setAttribute('aria-hidden', 'true');
  aperture.innerHTML =
    `<circle cx="${center}" cy="${center}" r="${structureRadius.toFixed(2)}" fill="none" ` +
    `stroke="${tint}" stroke-opacity="0.20" stroke-width="2"/>` +
    `<circle cx="${center}" cy="${center}" r="${arcRadius.toFixed(2)}" fill="none" ` +
    `stroke="${tint}" stroke-opacity="0.85" stroke-width="2" stroke-linecap="round" ` +
    `stroke-dasharray="${arcLength.toFixed(2)} ${(arcCircumference - arcLength).toFixed(2)}" ` +
    `transform="rotate(-90 ${center} ${center})"/>`;

  const mark = document.createElement('div');
  mark.className = 'ra-mark-glyph';
  mark.innerHTML = icon(glyph, { size: Math.round(glyphSize) });

  wrap.append(bloom, aperture, mark);
  return wrap;
}

/** The full empty state: mark, title, message, and optional actions. */
export interface EmptyStateOptions {
  readonly glyph: IconName;
  readonly title: string;
  readonly message?: string;
  /** 88 fits inside a card; omit for the 132 hero size. */
  readonly diameter?: number;
  readonly actions?: readonly HTMLElement[];
}

export function emptyState(options: EmptyStateOptions): HTMLElement {
  const { glyph, title, message, diameter, actions = [] } = options;

  const wrap = document.createElement('div');
  wrap.className = 'ra-empty';
  wrap.append(emptyStateMark(glyph, diameter === undefined ? {} : { diameter }));

  const heading = document.createElement('h2');
  heading.className = 'ra-empty-title';
  heading.textContent = title;
  wrap.append(heading);

  if (message !== undefined) {
    const text = document.createElement('p');
    text.className = 'ra-empty-subtitle';
    text.textContent = message;
    wrap.append(text);
  }

  if (actions.length > 0) {
    const row = document.createElement('div');
    row.className = 'ra-row';
    row.append(...actions);
    wrap.append(row);
  }

  return wrap;
}
