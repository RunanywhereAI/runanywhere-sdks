/**
 * Voice activity — one live `vad.openStream` session.
 *
 * Prefer the stream API (not polling `detect`). One session at a time; leaving
 * the route finishes and closes the stream and the microphone.
 */
import type { AudioFormatSpec, VadEvent, VadStream } from '@runanywhere/electron';

import { emptyState } from '../components/empty-state-mark';
import {
  float32FrameBytes,
  MIC_SAMPLE_RATE_HZ,
  MicCapture,
  toMicRate,
} from '../services/mic-capture';
import { errorMessage } from '../services/modality-models';
import type { ViewFactory, ViewInstance } from '../shell/app';
import { badge, button, el, section, statusLine } from './dom';

const STREAM_FORMAT = {
  encoding: 'PCM_F32_LE',
  sampleRate: MIC_SAMPLE_RATE_HZ,
  channels: 1,
} as const satisfies AudioFormatSpec;

const ActivityLabel = {
  Started: 'Speech Started',
  Ended: 'Speech Ended',
} as const;
type ActivityLabel = (typeof ActivityLabel)[keyof typeof ActivityLabel];

interface ActivityEntry {
  readonly label: ActivityLabel;
  readonly at: Date;
}

/** Module-level guard — only one VAD stream may be open in the app. */
let vadSessionOwner: symbol | null = null;

export const createVadView: ViewFactory = ({ root }): ViewInstance => {
  const owner = Symbol('vad-view');
  const mic = new MicCapture();
  let stream: VadStream | null = null;
  let listening = false;
  let speech = false;
  let probability = 0;
  let sessionOriginMs: number | null = null;
  let errorText: string | null = null;
  let log: ActivityEntry[] = [];
  let disposed = false;

  const wrap = el('div', 'ra-view-scroll ra-stack ra-measure-content');
  const actions = el('div', 'ra-row');
  const statusEl = statusLine('');
  const pillHost = el('div', 'ra-row');
  const metrics = el('dl', 'ra-voice-metrics');
  const logHost = el('div', 'ra-voice-log');

  wrap.append(
    section('Detect when someone is speaking', (() => {
      const body = el('div', 'ra-stack');
      body.append(
        el(
          'p',
          'ra-type-secondary',
          'Listens to the microphone and marks where speech starts and stops. Audio never leaves this device. Built-in energy VAD needs no model download.',
        ),
        actions,
        statusEl,
      );
      return body;
    })()),
    section('Live status', (() => {
      const body = el('div', 'ra-stack');
      body.append(pillHost, metrics);
      return body;
    })()),
    section('Activity log', logHost),
  );
  root.append(wrap);

  function paintPill(): void {
    pillHost.replaceChildren(
      badge(
        speech ? 'Speech detected' : listening ? 'Listening — silence' : 'Not listening',
        speech ? 'success' : 'neutral',
      ),
    );
  }

  function formatPosition(timestampMs: number | undefined): string {
    if (timestampMs === undefined) return '—';
    sessionOriginMs ??= timestampMs;
    const elapsedMs = Math.max(0, timestampMs - sessionOriginMs);
    const deciseconds = Math.round(elapsedMs / 100);
    const minutes = Math.floor(deciseconds / 600);
    const seconds = (deciseconds % 600) / 10;
    return `${minutes}:${seconds.toFixed(1).padStart(4, '0')}`;
  }

  function paintMetrics(): void {
    metrics.replaceChildren();
    const conf = el('div', 'ra-voice-metric');
    conf.append(el('dt', '', 'Confidence'), el('dd', 'ra-selectable', speech || listening ? probability.toFixed(3) : '—'));
    const pos = el('div', 'ra-voice-metric');
    pos.append(el('dt', '', 'Position'), el('dd', 'ra-selectable', '—'));
    metrics.append(conf, pos);
  }

  function updateMetrics(timestampMs?: number): void {
    const conf = metrics.querySelector('dd');
    if (conf instanceof HTMLElement) conf.textContent = probability.toFixed(3);
    const pos = metrics.querySelectorAll('dd')[1];
    if (pos instanceof HTMLElement) pos.textContent = formatPosition(timestampMs);
  }

  function paintLog(): void {
    logHost.replaceChildren();
    if (log.length === 0) {
      logHost.append(
        emptyState({
          glyph: 'waveform',
          title: 'No activity yet',
          message: 'Speech starts and stops will be listed here.',
          diameter: 88,
        }),
      );
      return;
    }
    const list = el('ul', 'ra-voice-log-list');
    for (const entry of log) {
      const item = el('li', 'ra-voice-log-item');
      item.append(
        el('div', 'ra-type-card-title', entry.label),
        el('div', 'ra-type-caption', entry.at.toLocaleTimeString()),
      );
      list.append(item);
    }
    logHost.append(list);
  }

  function paintActions(): void {
    actions.replaceChildren(
      button(
        listening ? 'ra-btn-secondary' : 'ra-btn-primary',
        listening ? 'Stop listening' : 'Start listening',
        () => {
          if (listening) {
            void stopListening();
          } else {
            void startListening();
          }
        },
      ),
      button('ra-btn-secondary', 'Clear log', () => {
        log = [];
        paintLog();
      }, { disabled: log.length === 0 }),
    );
  }

  function addLog(label: ActivityLabel): void {
    log = [{ label, at: new Date() }, ...log].slice(0, 50);
    paintLog();
    paintActions();
  }

  function handleEvent(event: VadEvent): void {
    switch (event.type) {
      case 'speechStarted':
        speech = true;
        addLog(ActivityLabel.Started);
        paintPill();
        return;
      case 'speechEnded':
        speech = false;
        addLog(ActivityLabel.Ended);
        paintPill();
        return;
      case 'activity':
        speech = event.isSpeech;
        probability = event.probability;
        paintPill();
        updateMetrics(event.timestampMs);
        return;
      case 'failed':
        errorText = event.error.message;
        statusEl.textContent = errorText;
        statusEl.dataset.tone = 'danger';
        void stopListening();
        return;
      case 'completed':
        return;
      default: {
        const _exhaustive: never = event;
        void _exhaustive;
      }
    }
  }

  async function consume(active: VadStream): Promise<void> {
    try {
      for await (const event of active.events) {
        if (disposed || stream !== active) return;
        handleEvent(event);
      }
    } catch (error) {
      if (!disposed) {
        errorText = errorMessage(error);
        statusEl.textContent = `VAD stream failed: ${errorText}`;
        statusEl.dataset.tone = 'danger';
        await stopListening();
      }
    }
  }

  async function startListening(): Promise<void> {
    if (listening) return;
    if (vadSessionOwner !== null && vadSessionOwner !== owner) {
      statusEl.textContent = 'Another voice-activity session is already open.';
      statusEl.dataset.tone = 'danger';
      return;
    }

    errorText = null;
    speech = false;
    probability = 0;
    sessionOriginMs = null;
    statusEl.textContent = '';
    statusEl.dataset.tone = 'neutral';

    try {
      stream = await window.runanywhere.vad.openStream(STREAM_FORMAT);
      vadSessionOwner = owner;
      void consume(stream);
      await mic.start((frame, rate) => {
        if (stream === null) return;
        const mono = toMicRate(frame, rate);
        stream.pushFrame({ samples: float32FrameBytes(mono), sampleCount: mono.length });
      });
      listening = true;
      paintPill();
      paintActions();
      paintMetrics();
    } catch (error) {
      await stopListening();
      statusEl.textContent = `Failed to start: ${errorMessage(error)}`;
      statusEl.dataset.tone = 'danger';
      paintActions();
    }
  }

  async function stopListening(): Promise<void> {
    listening = false;
    speech = false;
    mic.stop();
    const active = stream;
    stream = null;
    if (vadSessionOwner === owner) vadSessionOwner = null;
    if (active !== null) {
      try {
        active.finish();
        await active.close();
      } catch {
        /* best-effort */
      }
    }
    if (!disposed) {
      paintPill();
      paintActions();
      paintMetrics();
    }
  }

  paintPill();
  paintMetrics();
  paintLog();
  paintActions();

  return {
    dispose(): void {
      disposed = true;
      void stopListening();
    },
  };
};
