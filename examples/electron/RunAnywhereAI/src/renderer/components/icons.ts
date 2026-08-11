/**
 * The icon set.
 *
 * Every glyph is 24×24, `stroke-width: 1.5`, round caps and joins, `currentColor`,
 * and no fill — guideline §7. The names mirror the SF Symbols the macOS app uses,
 * so a screen's icon can be traced back to its Swift counterpart.
 */

/** SF Symbol name -> the path data that reproduces it at 24×24. */
const PATHS: Readonly<Record<string, string>> = {
  // bubble.left.and.bubble.right — sidebar: Chat
  'bubble.left.and.bubble.right':
    'M8.5 13.5H5.2A2.2 2.2 0 0 1 3 11.3V5.7A2.2 2.2 0 0 1 5.2 3.5h7.6A2.2 2.2 0 0 1 15 5.7v1.1 M9 20.5l2.6-2.2h4.2A2.2 2.2 0 0 0 18 16.1v-4.4a2.2 2.2 0 0 0-2.2-2.2H9.7a2.2 2.2 0 0 0-2.2 2.2v4.4A2.2 2.2 0 0 0 9.7 18.3H9z',
  // square.stack.3d.up — sidebar: Models
  'square.stack.3d.up': 'M12 2.75 20.5 7 12 11.25 3.5 7z M3.5 12 12 16.25 20.5 12 M3.5 17 12 21.25 20.5 17',
  // slider.horizontal.3 — sidebar: Advanced
  'slider.horizontal.3':
    'M3.75 7.5h16.5 M3.75 12h16.5 M3.75 16.5h16.5 M9 7.5a1.5 1.5 0 1 0 3 0 1.5 1.5 0 1 0-3 0 M14 12a1.5 1.5 0 1 0 3 0 1.5 1.5 0 1 0-3 0 M7 16.5a1.5 1.5 0 1 0 3 0 1.5 1.5 0 1 0-3 0',
  // square.and.pencil — new conversation
  'square.and.pencil':
    'M15.5 4.5H6a2 2 0 0 0-2 2V18a2 2 0 0 0 2 2h11.5a2 2 0 0 0 2-2V9 M18.4 3.1a1.8 1.8 0 0 1 2.5 2.5L13 13.5l-3.4.9.9-3.4z',
  // magnifyingglass — search
  magnifyingglass: 'M10.75 4.5a6.25 6.25 0 1 0 0 12.5 6.25 6.25 0 0 0 0-12.5z M15.5 15.5 20 20',
  // gearshape — settings
  gearshape:
    'M12 15.25a3.25 3.25 0 1 0 0-6.5 3.25 3.25 0 0 0 0 6.5z M19.4 15a1.7 1.7 0 0 0 .34 1.87l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.7 1.7 0 0 0-1.87-.34 1.7 1.7 0 0 0-1.03 1.56V21a2 2 0 0 1-4 0v-.09a1.7 1.7 0 0 0-1.11-1.56 1.7 1.7 0 0 0-1.87.34l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.7 1.7 0 0 0 .34-1.87 1.7 1.7 0 0 0-1.56-1.03H3a2 2 0 0 1 0-4h.09a1.7 1.7 0 0 0 1.56-1.11 1.7 1.7 0 0 0-.34-1.87l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.7 1.7 0 0 0 1.87.34H9a1.7 1.7 0 0 0 1.03-1.56V3a2 2 0 0 1 4 0v.09a1.7 1.7 0 0 0 1.03 1.56 1.7 1.7 0 0 0 1.87-.34l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.7 1.7 0 0 0-.34 1.87V9a1.7 1.7 0 0 0 1.56 1.03H21a2 2 0 0 1 0 4h-.09A1.7 1.7 0 0 0 19.4 15z',
  // arrow.up — send
  'arrow.up': 'M12 19.5V5 M5.5 11.5 12 5l6.5 6.5',
  // stop.fill — stop generating (the one filled glyph; it reads as a hard stop)
  'stop.fill': 'M7 7h10v10H7z',
  // plus — attach
  plus: 'M12 5v14 M5 12h14',
  // paperclip — attachment
  paperclip:
    'M20.4 11.5l-8.2 8.2a5 5 0 0 1-7.1-7.1l8.5-8.5a3.4 3.4 0 0 1 4.8 4.8l-8.5 8.5a1.7 1.7 0 0 1-2.4-2.4l7.8-7.8',
  // waveform — voice
  waveform: 'M4 10v4 M8 7v10 M12 4.5v15 M16 7v10 M20 10v4',
  // mic — record
  mic: 'M12 3.75a3 3 0 0 0-3 3v4.5a3 3 0 0 0 6 0v-4.5a3 3 0 0 0-3-3z M5.5 11.5a6.5 6.5 0 0 0 13 0 M12 18v2.5 M8.5 20.5h7',
  // photo — vision
  photo:
    'M4 5.75h16a1 1 0 0 1 1 1v10.5a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V6.75a1 1 0 0 1 1-1z M8 11a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3z M21 15.5 16 11l-9 7.25',
  // doc.text — knowledge / documents
  'doc.text': 'M14 3.5H7a2 2 0 0 0-2 2V19a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8.5z M14 3.5V8.5h5 M8.5 13h7 M8.5 16.5h7',
  // speaker.wave.2 — speak / TTS
  'speaker.wave.2': 'M11 5.5 6.5 9.5H3.5v5h3L11 18.5z M15 9a4 4 0 0 1 0 6 M17.8 6.5a7.5 7.5 0 0 1 0 11',
  // person.2.wave.2 — diarization
  'person.2.wave.2':
    'M9 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M3.5 19.5a5.5 5.5 0 0 1 11 0 M16 6.5a3.7 3.7 0 0 1 0 5 M19 4.5a6.5 6.5 0 0 1 0 9',
  // square.dashed — segmentation
  'square.dashed': 'M4 8V6a2 2 0 0 1 2-2h2 M16 4h2a2 2 0 0 1 2 2v2 M20 16v2a2 2 0 0 1-2 2h-2 M8 20H6a2 2 0 0 1-2-2v-2',
  // chart.bar — benchmarks
  'chart.bar': 'M4 20V11 M9.5 20V4.5 M15 20v-6.5 M20.5 20V8',
  // internaldrive — storage
  internaldrive:
    'M4 6.75h16a1 1 0 0 1 1 1v8.5a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-8.5a1 1 0 0 1 1-1z M6.5 14h5 M17 14a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5z',
  // curlybraces — structured output
  curlybraces:
    'M9 4.5C7 4.5 7 8 7 9.5S5.5 12 5.5 12 7 12.5 7 14.5 7 19.5 9 19.5 M15 4.5c2 0 2 3.5 2 5s1.5 2.5 1.5 2.5S17 12.5 17 14.5s0 5-2 5',
  // wrench.and.screwdriver — tools
  'wrench.and.screwdriver':
    'M14.5 9.5 20 4 M17.5 3.5 20.5 6.5 M4 15l5-5 M10.5 4.8a3.7 3.7 0 0 0-5 5l9.7 9.7a2 2 0 0 0 2.8-2.8z',
  // sparkles — assistant / empty state
  sparkles:
    'M12 3.5l1.6 4.4L18 9.5l-4.4 1.6L12 15.5l-1.6-4.4L6 9.5l4.4-1.6z M18.5 15l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z',
  // sidebar.left — toggle sidebar
  'sidebar.left': 'M4 5.5h16a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-11a1 1 0 0 1 1-1z M9.5 5.5v13',
  // info.circle — chat details
  'info.circle': 'M12 3.75a8.25 8.25 0 1 0 0 16.5 8.25 8.25 0 0 0 0-16.5z M12 11v5.5 M12 7.75h.01',
  // xmark — close / dismiss
  xmark: 'M6 6l12 12 M18 6 6 18',
  // chevron.down — disclosure
  'chevron.down': 'M6 9.5 12 15.5l6-6',
  // chevron.right — disclosure, collapsed
  'chevron.right': 'M9.5 6 15.5 12l-6 6',
  // checkmark — done / active
  checkmark: 'M5 12.5 9.5 17 19 7.5',
  // arrow.down.circle — download
  'arrow.down.circle': 'M12 3.75a8.25 8.25 0 1 0 0 16.5 8.25 8.25 0 0 0 0-16.5z M12 7.5v8 M8.5 12 12 15.5 15.5 12',
  // arrow.clockwise — retry / regenerate
  'arrow.clockwise': 'M20 12a8 8 0 1 1-2.4-5.7 M20 4v4.5h-4.5',
  // trash — delete
  trash: 'M4.5 7h15 M9.5 7V4.75h5V7 M6.5 7l.8 12.2a1.5 1.5 0 0 0 1.5 1.4h6.4a1.5 1.5 0 0 0 1.5-1.4L17.5 7',
  // doc.on.doc — copy
  'doc.on.doc':
    'M9 8.5h9a1.5 1.5 0 0 1 1.5 1.5v9a1.5 1.5 0 0 1-1.5 1.5H9A1.5 1.5 0 0 1 7.5 19v-9A1.5 1.5 0 0 1 9 8.5z M16 5.5V4.5a1.5 1.5 0 0 0-1.5-1.5H6A1.5 1.5 0 0 0 4.5 4.5v10',
  // lock — privacy footer
  lock: 'M6.5 10.5h11a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1v-8a1 1 0 0 1 1-1z M8.5 10.5V7.5a3.5 3.5 0 0 1 7 0v3',
  // brain — thinking / reasoning
  brain:
    'M12 5a3 3 0 0 0-3 3 2.5 2.5 0 0 0-1.5 4.6A2.5 2.5 0 0 0 9 17.5a3 3 0 0 0 3 1.5 3 3 0 0 0 3-1.5 2.5 2.5 0 0 0 1.5-4.9A2.5 2.5 0 0 0 15 8a3 3 0 0 0-3-3z M12 5v14',
  // globe — web / tools on
  globe: 'M12 3.75a8.25 8.25 0 1 0 0 16.5 8.25 8.25 0 0 0 0-16.5z M3.9 9.5h16.2 M3.9 14.5h16.2 M12 3.75c2.2 2.4 3.3 5.2 3.3 8.25S14.2 17.85 12 20.25c-2.2-2.4-3.3-5.2-3.3-8.25S9.8 6.15 12 3.75z',
} as const;

export type IconName = keyof typeof PATHS;

export interface IconOptions {
  /** Optical size in px. Guideline sizes: 16, 20, 24, 28. */
  readonly size?: number;
  /** Extra classes on the <svg>. */
  readonly className?: string;
  /** Accessible label; omitted icons are marked aria-hidden. */
  readonly label?: string;
}

/**
 * An icon as an SVG string.
 *
 * Returns a string rather than an element so it can be embedded in the template
 * literals the views build, matching the Web app's `icon()` convention.
 */
export function icon(name: IconName, options: IconOptions = {}): string {
  const { size = 24, className = '', label } = options;
  const path = PATHS[name];
  const a11y = label === undefined ? 'aria-hidden="true"' : `role="img" aria-label="${label}"`;
  return (
    `<svg class="ra-icon ${className}" width="${size}" height="${size}" viewBox="0 0 24 24" ` +
    `fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" ` +
    `stroke-linejoin="round" ${a11y}>` +
    path
      .split(' M')
      .map((segment, index) => `<path d="${index === 0 ? segment : `M${segment}`}"/>`)
      .join('') +
    '</svg>'
  );
}

/** True when a name has a glyph — useful for data-driven icon fields. */
export function hasIcon(name: string): name is IconName {
  return Object.prototype.hasOwnProperty.call(PATHS, name);
}
