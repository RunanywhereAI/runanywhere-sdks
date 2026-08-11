/**
 * Audio activity figure.
 *
 * Transcribed from `Core/DesignSystem/AudioActivityBars.swift`. Two honest modes:
 *
 *  - `.level` — bar heights come from a real 0…1 meter.
 *  - `.indeterminate` — silhouette holds still; a highlight sweeps on the
 *    canonical 1.2s shimmer period (suppressed under Reduce Motion).
 *
 * Envelope math is identical to Swift: taper from centre, floor on silence,
 * opacity tied to the same envelope so the figure has a recognisable rest shape.
 */
import { onReducedMotionChange, prefersReducedMotion } from '../design/motion';

export type AudioBarsMode =
  | { readonly kind: 'level'; readonly level: number }
  | { readonly kind: 'indeterminate' };

export interface AudioActivityBarsOptions {
  readonly barCount?: number;
  readonly height?: number;
  readonly tint?: string;
  readonly mode?: AudioBarsMode;
}

const BAR_WIDTH = 5;
const SWEEP_PERIOD_MS = 1200;
const STROKE_EMPHASIS = 2;

function envelope(index: number, barCount: number): number {
  if (barCount <= 1) return 1;
  const mid = (barCount - 1) / 2;
  const distance = Math.abs(index - mid) / mid;
  return 1 - 0.55 * distance * distance;
}

function levelHeight(index: number, barCount: number, height: number, level: number): number {
  const clamped = Math.max(0, Math.min(1, level));
  const amplitude = 0.18 + 0.82 * clamped;
  return Math.max(STROKE_EMPHASIS, height * amplitude * envelope(index, barCount));
}

function restHeight(index: number, barCount: number, height: number): number {
  return Math.max(STROKE_EMPHASIS, height * 0.62 * envelope(index, barCount));
}

function baseOpacity(index: number, barCount: number): number {
  return 0.45 + 0.55 * envelope(index, barCount);
}

function highlight(index: number, barCount: number, sweep: number): number {
  if (barCount <= 1) return 1;
  const position = index / (barCount - 1);
  let distance = Math.abs(position - sweep);
  if (distance > 0.5) distance = 1 - distance;
  const falloff = Math.max(0, 1 - distance / 0.35);
  return 0.45 + 0.55 * falloff;
}

export class AudioActivityBars {
  readonly element: HTMLElement;

  private readonly bars: HTMLElement[] = [];
  private readonly barCount: number;
  private readonly height: number;
  private mode: AudioBarsMode;
  private raf = 0;
  private unsubReduce: (() => void) | null = null;

  constructor(options: AudioActivityBarsOptions = {}) {
    this.barCount = options.barCount ?? 7;
    this.height = options.height ?? 40;
    this.mode = options.mode ?? { kind: 'indeterminate' };

    this.element = document.createElement('div');
    this.element.className = 'ra-audio-bars';
    this.element.style.setProperty('--ra-audio-bars-height', `${this.height}px`);
    if (options.tint !== undefined) this.element.style.setProperty('--ra-audio-tint', options.tint);
    this.element.setAttribute('role', 'img');
    this.element.setAttribute('aria-label', this.mode.kind === 'level' ? 'Input level' : 'Audio activity');

    for (let i = 0; i < this.barCount; i += 1) {
      const bar = document.createElement('div');
      bar.className = 'ra-audio-bar';
      bar.style.width = `${BAR_WIDTH}px`;
      this.bars.push(bar);
      this.element.append(bar);
    }

    this.paint();
    this.unsubReduce = onReducedMotionChange(() => this.paint());
  }

  setMode(mode: AudioBarsMode): void {
    this.mode = mode;
    this.element.setAttribute('aria-label', mode.kind === 'level' ? 'Input level' : 'Audio activity');
    if (mode.kind === 'level') {
      this.element.setAttribute('aria-valuenow', String(Math.round(Math.max(0, Math.min(1, mode.level)) * 100)));
      this.element.setAttribute('aria-valuemin', '0');
      this.element.setAttribute('aria-valuemax', '100');
    } else {
      this.element.removeAttribute('aria-valuenow');
      this.element.removeAttribute('aria-valuemin');
      this.element.removeAttribute('aria-valuemax');
    }
    this.paint();
  }

  setLevel(level: number): void {
    this.setMode({ kind: 'level', level });
  }

  dispose(): void {
    this.stopSweep();
    this.unsubReduce?.();
    this.unsubReduce = null;
    this.element.remove();
  }

  private paint(): void {
    this.stopSweep();

    if (this.mode.kind === 'level') {
      for (let i = 0; i < this.barCount; i += 1) {
        const bar = this.bars[i];
        bar.style.height = `${levelHeight(i, this.barCount, this.height, this.mode.level)}px`;
        bar.style.opacity = String(baseOpacity(i, this.barCount));
      }
      return;
    }

    for (let i = 0; i < this.barCount; i += 1) {
      const bar = this.bars[i];
      bar.style.height = `${restHeight(i, this.barCount, this.height)}px`;
      bar.style.opacity = String(baseOpacity(i, this.barCount));
    }

    if (prefersReducedMotion()) return;
    this.startSweep();
  }

  private startSweep(): void {
    const tick = (now: number): void => {
      const sweep = (now % SWEEP_PERIOD_MS) / SWEEP_PERIOD_MS;
      for (let i = 0; i < this.barCount; i += 1) {
        this.bars[i].style.opacity = String(baseOpacity(i, this.barCount) * highlight(i, this.barCount, sweep));
      }
      this.raf = requestAnimationFrame(tick);
    };
    this.raf = requestAnimationFrame(tick);
  }

  private stopSweep(): void {
    if (this.raf !== 0) {
      cancelAnimationFrame(this.raf);
      this.raf = 0;
    }
  }
}

export function audioActivityBars(options?: AudioActivityBarsOptions): AudioActivityBars {
  return new AudioActivityBars(options);
}
