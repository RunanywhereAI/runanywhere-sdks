/**
 * The app's icon set — one glyph per meaning, drawn once.
 *
 * WHY THIS EXISTS. Icons were being re-typed as raw `<svg>` literals at 27 sites
 * across 13 files, in four different stroke weights: 2, 1.8, 1.7 and 1.5. Two
 * near-identical `icon()` / `svgIcon()` helpers existed in parallel (`app.ts` and
 * `views/chat.ts`), so the two halves of the same screen drew at different
 * weights — a difference that is invisible next to itself and obvious side by
 * side. The document glyph appeared four times, the microphone three, the brand
 * sparkle three, each an independent transcription that could drift on its own.
 *
 * DESIGN_GUIDELINE.md §7 fixes the language: a 24x24 grid, 1.5px strokes with
 * round caps and joins, no fill, and `currentColor` so an icon is coloured by the
 * text it sits beside rather than by a hardcoded hex. Everything below conforms,
 * and `icon()` is the only way to emit one.
 *
 * ONE GLYPH, ONE MEANING — app-wide and cross-app (iOS and Android carry the
 * same mapping through SF Symbols and Material Symbols Rounded). A microphone is
 * always capture, never "audio in general"; a waveform is always audio content,
 * never "activity". Reusing a glyph for a second meaning to avoid drawing a new
 * one is the cheapest way to make an interface unreadable.
 */

/** The optical sizes from §7. A glyph is drawn for its slot, not scaled into it. */
export type IconSize = 16 | 20 | 24 | 28 | 32 | 40;

export interface IconOptions {
  size?: IconSize;
  /** Extra class on the `<svg>`, for positioning or an animation hook. */
  className?: string;
  /**
   * A name for assistive tech.
   *
   * Omit it — the default — whenever adjacent text already names the thing, which
   * is the common case. An icon inside a labelled button is decorative, and
   * announcing "document, Documents" is worse than announcing "Documents".
   * Supply it only for an icon that is the *entire* content of a control.
   */
  label?: string;
}

/**
 * Render a glyph.
 *
 * Takes a name from `ICON_PATHS` rather than raw path data, so a typo is a
 * compile error instead of an empty box, and so no call site can pick its own
 * stroke weight.
 */
export function icon(name: IconName, options: IconOptions = {}): string {
  const { size = 24, className, label } = options;
  const a11y = label
    ? `role="img" aria-label="${escapeAttribute(label)}"`
    : 'aria-hidden="true"';
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="${size}" height="${size}"`
    + ` fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"`
    + ` stroke-linejoin="round"${className ? ` class="${className}"` : ''} ${a11y}>`
    + `${ICON_PATHS[name]}</svg>`;
}

/**
 * Attribute-escape a label.
 *
 * Local rather than imported from `services/escape-html`, because that helper
 * escapes for text content; an attribute value additionally cannot carry a raw
 * quote. Labels are authored strings today, but an icon label will eventually be
 * built from a model or file name, and this is the sink that has to hold then.
 */
function escapeAttribute(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

/**
 * The glyphs, grouped by what they mean.
 *
 * Every path is drawn on the 24x24 box with a 2px optical margin, so a set of
 * icons at the same size share an apparent weight and centre. Adding one means
 * checking it against this list first — if the meaning is already here, use the
 * existing glyph.
 */
export const ICON_PATHS = {
  // ---- Brand and navigation -----------------------------------------------
  /** The product's own mark-in-miniature. Assistant, "ask AI", brand moments. */
  sparkles: '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8L12 3z"/>'
    + '<path d="M5 3l.8 2.2L8 6l-2.2.8L5 9l-.8-2.2L2 6l2.2-.8L5 3z"/>'
    + '<path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8L19 15z"/>',
  menu: '<line x1="4" y1="7" x2="20" y2="7"/><line x1="4" y1="12" x2="20" y2="12"/>'
    + '<line x1="4" y1="17" x2="20" y2="17"/>',
  back: '<path d="M15 18l-6-6 6-6"/>',
  close: '<path d="M18 6 6 18"/><path d="M6 6l12 12"/>',
  chevronDown: '<polyline points="6 9 12 15 18 9"/>',
  chevronRight: '<polyline points="9 6 15 12 9 18"/>',
  plus: '<path d="M12 5v14"/><path d="M5 12h14"/>',

  /** A single star: "recommended", "picked for you". Not the brand sparkle. */
  star: '<path d="M12 3l2 5.6L20 10l-6 1.4L12 17l-2-5.6L4 10l6-1.4L12 3z"/>',

  // ---- Modalities ---------------------------------------------------------
  /**
   * A model artifact — a weights bundle. Model pickers, the toolbar button,
   * engine rows.
   *
   * Deliberately a solid-ish box and NOT a globe. A globe was previously the
   * toolbar model button's glyph while the nav's model row used this box, so the
   * same concept had two shapes; worse, the globe simultaneously meant "web and
   * tools" in the composer, so one shape had two meanings. `globe` below is now
   * exclusively the network.
   */
  model: '<path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8'
    + 'a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/>'
    + '<path d="M3.3 7 12 12l8.7-5"/><path d="M12 22V12"/>',
  /** The network, and only the network. Web search, tool calling, cloud. */
  globe: '<circle cx="12" cy="12" r="9"/><path d="M12 3c2.5 3 2.5 15 0 18"/>'
    + '<path d="M12 3c-2.5 3-2.5 15 0 18"/><path d="M3 12h18"/>',
  /** Silicon. Device capability, hardware tier, accelerator. */
  chip: '<rect x="4" y="4" width="16" height="16" rx="3"/><rect x="9" y="9" width="6" height="6" rx="1"/>'
    + '<path d="M9 2v2"/><path d="M15 2v2"/><path d="M9 20v2"/><path d="M15 20v2"/>'
    + '<path d="M2 9h2"/><path d="M2 15h2"/><path d="M20 9h2"/><path d="M20 15h2"/>',
  /** Runs entirely here. Privacy assurances, on-device badges. */
  lock: '<rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>',
  /** A callable tool, in the tool-calling sense. */
  tool: '<path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.8-3.8a6 6 0 0 1-7.9 7.9'
    + 'l-6.9 6.9a2.1 2.1 0 0 1-3-3l6.9-6.9a6 6 0 0 1 7.9-7.9l-3.8 3.8z"/>',
  /** Capture. Recording, dictation, listening — never "audio" in general. */
  mic: '<path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3z"/>'
    + '<path d="M19 10v2a7 7 0 0 1-14 0v-2"/><path d="M12 19v3"/><path d="M8 22h8"/>',
  /** Audio *content*: a transcript, a clip, a signal. Never "listening". */
  waveform: '<path d="M2 12h3l2-7 4 14 3-10 2 3h6"/>',
  /** Playback and synthesis. Read aloud, voices. */
  speaker: '<path d="M11 5 6 9H2v6h4l5 4V5z"/><path d="M16 9.5a4 4 0 0 1 0 5"/>'
    + '<path d="M19 6a8 8 0 0 1 0 12"/>',
  /**
   * Speech-vs-silence detection over time. Voice Activity only.
   *
   * Distinct from `waveform`, which was serving both Transcribe and Voice
   * Activity in the Advanced hub — two adjacent rows, same picture. A trace with
   * a flat baseline and one burst is what VAD actually shows.
   */
  pulse: '<path d="M2 12h4l2-5 3 10 2.5-7 1.5 2h7"/><path d="M2 18h20"/>',
  /**
   * Two people. Diarization — who spoke when.
   *
   * `mic` was doing this job as well as Talk Mode's; diarization is about
   * *speakers*, not about capture, and the distinction is the whole feature.
   */
  speakers: '<path d="M15 20v-1.5a3.5 3.5 0 0 0-3.5-3.5h-4A3.5 3.5 0 0 0 4 18.5V20"/>'
    + '<circle cx="9.5" cy="8" r="3.5"/>'
    + '<path d="M20 20v-1.5a3.5 3.5 0 0 0-2.6-3.4"/><path d="M15.5 5.1a3.5 3.5 0 0 1 0 5.8"/>',
  /** An image split into regions. Segmentation only. */
  segments: '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 10h7"/>'
    + '<path d="M10 3v18"/><path d="M10 15h11"/>',
  /** A picture as input. Vision, attachments, image understanding. */
  image: '<rect x="3" y="5" width="18" height="14" rx="2"/>'
    + '<circle cx="8.5" cy="10.5" r="1.5"/><path d="M21 15l-4.5-4.5L9 18"/>',
  /**
   * A picture as *output*. Diffusion / image-generation models only.
   *
   * A frame with a sparkle in it, deliberately not `image` (a frame with a
   * photographed scene in it): the two categories sit in the same model list,
   * and reusing one glyph for both would say a generator and a vision model are
   * the same kind of thing.
   */
  imageSparkle: '<rect x="3" y="4" width="18" height="16" rx="2"/>'
    + '<path d="M12 8.2l1.2 3.1 3.1 1.2-3.1 1.2L12 16.8l-1.2-3.1L7.7 12.5l3.1-1.2L12 8.2z"/>',
  camera: '<path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/>'
    + '<circle cx="12" cy="13" r="4"/>',
  /** A corpus document. Files indexed for retrieval, attachments. */
  file: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>'
    + '<polyline points="14 2 14 8 20 8"/><path d="M8 13h8"/><path d="M8 17h5"/>',
  /** Conversation. Chat, replies, answers. */
  message: '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>',
  /**
   * Looking through a live feed. Live camera and the Vision destination only.
   *
   * `device` (a phone frame) used to carry this, which named the *hardware* rather
   * than the act — and named it differently from Android (`RACIcons.Outline.Eye`,
   * documented as "looking through a live feed") and iOS (`eye`, which is what
   * `RAModelCategory.consumerCapabilityIcon` returns for vision). One concept,
   * one shape, in all three apps.
   */
  eye: '<path d="M21 12c-2.4 4-5.4 6-9 6s-6.6-2-9-6c2.4-4 5.4-6 9-6s6.6 2 9 6z"/>'
    + '<circle cx="12" cy="12" r="2.5"/>',
  /**
   * Reasoning. The thinking-mode toggle and the "Reasoning" state it produces.
   *
   * Reserved for reasoning and nothing else — Android freed the same glyph from its
   * voice screen, where a brain had meant *speech recognition* while iOS drew a brain
   * for the language model, so one shape meant two opposite ends of one pipeline.
   */
  brain: '<path d="M9.5 3.5A3.5 3.5 0 0 0 6 7v.5A3.5 3.5 0 0 0 4 10.7a3.4 3.4 0 0 0 1.5 2.8'
    + 'A3.4 3.4 0 0 0 5 15.9 3.4 3.4 0 0 0 8.4 19.3c.4 0 .8 0 1.1-.2"/>'
    + '<path d="M14.5 3.5A3.5 3.5 0 0 1 18 7v.5a3.5 3.5 0 0 1 2 3.2 3.4 3.4 0 0 1-1.5 2.8'
    + 'A3.4 3.4 0 0 1 19 15.9a3.4 3.4 0 0 1-3.4 3.4c-.4 0-.8 0-1.1-.2"/>'
    + '<path d="M12 4v16"/>',

  // ---- Suggestions (chat starters) ----------------------------------------
  /** Compose, draft, write. */
  pencil: '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>',
  /**
   * Condense — long text in, short text out. The Summarize starter only.
   *
   * Deliberately not `checklist` (which the Plan starter uses) and not `file` (a
   * corpus document): the lines getting shorter is the whole idea, and the four
   * starters have to be four distinguishable shapes to be worth drawing at all.
   */
  condense: '<path d="M4 5h16"/><path d="M4 10h16"/><path d="M4 15h10"/><path d="M4 20h5"/>',
  /** Compare, weigh options, expand out. */
  compare: '<path d="M16 3h5v5"/><path d="M8 3H3v5"/><path d="M21 3l-7 7"/><path d="M3 3l7 7"/>'
    + '<path d="M16 21h5v-5"/><path d="M8 21H3v-5"/><path d="M21 21l-7-7"/><path d="M3 21l7-7"/>',
  /** A list of things to do. */
  checklist: '<path d="M3 17l2 2 4-4"/><path d="M3 7l2 2 4-4"/><path d="M13 6h8"/>'
    + '<path d="M13 12h8"/><path d="M13 18h8"/>',
  /** Leaves this app. External links only. */
  externalLink: '<path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>'
    + '<polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/>',

  // ---- Actions -----------------------------------------------------------
  send: '<path d="M22 2 11 13"/><path d="M22 2 15 22l-4-9-9-4 20-7z"/>',
  stop: '<rect x="6" y="6" width="12" height="12" rx="2"/>',
  copy: '<rect x="9" y="9" width="13" height="13" rx="2"/>'
    + '<path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>',
  trash: '<path d="M3 6h18"/><path d="M8 6V4a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v2"/>'
    + '<path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/>',
  download: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>'
    + '<polyline points="8 11 12 15 16 11"/><line x1="12" y1="3" x2="12" y2="15"/>',
  upload: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>'
    + '<polyline points="8 8 12 4 16 8"/><line x1="12" y1="4" x2="12" y2="16"/>',
  retry: '<path d="M21 12a9 9 0 1 1-3.5-7.1"/><polyline points="21 3 21 9 15 9"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-4.3-4.3"/>',

  // ---- Status ------------------------------------------------------------
  check: '<polyline points="20 6 10 17 5 12"/>',
  /** Something failed but is recoverable, and the user can act on it. */
  warning: '<path d="M10.3 3.6 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.6a2 2 0 0 0-3.4 0z"/>'
    + '<line x1="12" y1="9" x2="12" y2="14"/><line x1="12" y1="17" x2="12.01" y2="17"/>',
  info: '<circle cx="12" cy="12" r="9"/><line x1="12" y1="11" x2="12" y2="16"/>'
    + '<line x1="12" y1="8" x2="12.01" y2="8"/>',

  // ---- Surfaces ----------------------------------------------------------
  /**
   * Physical bytes at rest. Disk usage, the Storage screen, cached artifacts.
   *
   * A disk stack, not a download tray. The tray glyph (`download`) previously
   * served both "Manage downloads" and "Storage" in the nav, so two adjacent
   * rows carried the same picture — the one thing §7 forbids.
   */
  storage: '<ellipse cx="12" cy="6" rx="8" ry="3"/><path d="M4 6v12c0 1.7 3.6 3 8 3s8-1.3 8-3V6"/>'
    + '<path d="M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"/>',
  settings: '<circle cx="12" cy="12" r="3"/>'
    + '<path d="M19.4 15a1.7 1.7 0 0 0 .34 1.88l.04.04a2 2 0 1 1-2.83 2.83l-.04-.04A1.7 1.7 0 0 0 15 19.4'
    + 'a1.7 1.7 0 0 0-1 1.55V21a2 2 0 1 1-4 0v-.05A1.7 1.7 0 0 0 9 19.4a1.7 1.7 0 0 0-1.88.34l-.04.04'
    + 'a2 2 0 1 1-2.83-2.83l.04-.04A1.7 1.7 0 0 0 4.6 15a1.7 1.7 0 0 0-1.55-1H3a2 2 0 1 1 0-4h.05'
    + 'A1.7 1.7 0 0 0 4.6 9a1.7 1.7 0 0 0-.34-1.88l-.04-.04a2 2 0 1 1 2.83-2.83l.04.04A1.7 1.7 0 0 0 9 4.6'
    + 'a1.7 1.7 0 0 0 1-1.55V3a2 2 0 1 1 4 0v.05A1.7 1.7 0 0 0 15 4.6a1.7 1.7 0 0 0 1.88-.34l.04-.04'
    + 'a2 2 0 1 1 2.83 2.83l-.04.04A1.7 1.7 0 0 0 19.4 9a1.7 1.7 0 0 0 1.55 1H21a2 2 0 1 1 0 4h-.05'
    + 'a1.7 1.7 0 0 0-1.55 1z"/>',
  /** More/other — a set of capabilities beyond the main ones. */
  advanced: '<path d="M4 21v-7"/><path d="M4 10V3"/><path d="M12 21v-9"/><path d="M12 8V3"/>'
    + '<path d="M20 21v-5"/><path d="M20 12V3"/><path d="M2 14h4"/><path d="M10 8h4"/><path d="M18 16h4"/>',
  /** A stack of things — a catalog, a library, layered artifacts. */
  stack: '<polygon points="12 2 2 7 12 12 22 7 12 2"/><polyline points="2 17 12 22 22 17"/>'
    + '<polyline points="2 12 12 17 22 12"/>',
  /** Measurement. Benchmarks, throughput, performance. */
  gauge: '<path d="M4.93 19.07A10 10 0 1 1 19.07 19.07"/><path d="M12 14l4-4"/>'
    + '<circle cx="12" cy="18" r="2"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/>'
    + '<path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/>'
    + '<path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/>',
  moon: '<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/>',
} as const;

export type IconName = keyof typeof ICON_PATHS;
