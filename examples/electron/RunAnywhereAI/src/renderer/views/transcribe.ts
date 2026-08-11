/**
 * Transcribe — batch / live STT.
 *
 * Batch: record then `stt.transcribe`. Live: `stt.openStream` with pushed mic
 * frames (prefer over deprecated `transcribeStream`). Leaving the route closes
 * the microphone.
 */
import type { AudioFormatSpec, SttStream, TranscriptionEvent } from '@runanywhere/electron';

import { emptyState } from '../components/empty-state-mark';
import {
  float32FrameBytes,
  MIC_SAMPLE_RATE_HZ,
  MicCapture,
  toMicRate,
} from '../services/mic-capture';
import { ensureModelLoaded, errorMessage, modelLabel, selectedModelId } from '../services/modality-models';
import type { ViewFactory, ViewInstance } from '../shell/app';
import { button, el, section, statusLine } from './dom';

const SttMode = {
  Batch: 'batch',
  Live: 'live',
} as const;
type SttMode = (typeof SttMode)[keyof typeof SttMode];

const MODE_COPY: Readonly<Record<SttMode, { label: string; detail: string }>> = {
  [SttMode.Batch]: {
    label: 'Batch',
    detail: 'Records everything first, then transcribes it in one pass.',
  },
  [SttMode.Live]: {
    label: 'Live',
    detail: 'Shows a running guess as you speak. The transcript settles when you stop.',
  },
};

const STREAM_FORMAT = {
  encoding: 'PCM_F32_LE',
  sampleRate: MIC_SAMPLE_RATE_HZ,
  channels: 1,
} as const satisfies AudioFormatSpec;

export const createTranscribeView: ViewFactory = ({ root }): ViewInstance => {
  let mode: SttMode = SttMode.Batch;
  const mic = new MicCapture();
  let stream: SttStream | null = null;
  let capturing = false;
  let processing = false;
  let transcript = '';
  let partial = false;
  let modelId = '';
  let disposed = false;

  const wrap = el('div', 'ra-view-scroll ra-stack ra-measure-content');
  const modeRow = el('div', 'ra-row ra-segmented');
  const detail = el('p', 'ra-type-secondary', MODE_COPY[mode].detail);
  const modelMeta = el('p', 'ra-type-caption', '');
  const actions = el('div', 'ra-row');
  const statusEl = statusLine('');
  const outputHost = el('div', 'ra-voice-output');

  wrap.append(
    section('How to listen', (() => {
      const body = el('div', 'ra-stack');
      body.append(modeRow, detail, modelMeta);
      return body;
    })()),
    section('Record', (() => {
      const body = el('div', 'ra-stack');
      body.append(actions, statusEl, outputHost);
      return body;
    })()),
  );
  root.append(wrap);

  function setStatus(text: string, tone: 'neutral' | 'danger' | 'success' = 'neutral'): void {
    statusEl.textContent = text;
    statusEl.dataset.tone = tone;
  }

  function paintOutput(): void {
    outputHost.replaceChildren();
    if (transcript.length === 0) {
      outputHost.append(
        emptyState({
          glyph: 'waveform',
          title: 'Transcript',
          message: 'Your transcript will appear here.',
          diameter: 88,
        }),
      );
      return;
    }
    const pre = el('pre', 'ra-voice-pre ra-selectable', transcript);
    if (partial) pre.dataset.partial = 'true';
    outputHost.append(pre);
  }

  function paintActions(): void {
    actions.replaceChildren();
    const busy = capturing || processing;
    actions.append(
      button(
        capturing ? 'ra-btn-secondary' : 'ra-btn-primary',
        capturing ? 'Stop and transcribe' : 'Start recording',
        () => void toggleMic(),
        { disabled: processing },
      ),
      button('ra-btn-secondary', 'Clear', () => {
        transcript = '';
        partial = false;
        setStatus('');
        paintOutput();
      }, { disabled: busy || transcript.length === 0 }),
    );
  }

  function paintMode(): void {
    modeRow.replaceChildren();
    for (const next of [SttMode.Batch, SttMode.Live] as const) {
      const btn = button(
        'ra-chip',
        MODE_COPY[next].label,
        () => {
          if (capturing || processing || mode === next) return;
          mode = next;
          transcript = '';
          partial = false;
          setStatus('');
          detail.textContent = MODE_COPY[next].detail;
          paintMode();
          paintOutput();
        },
        { disabled: capturing || processing },
      );
      if (mode === next) btn.dataset.active = 'true';
      modeRow.append(btn);
    }
  }

  async function refreshModelMeta(): Promise<void> {
    try {
      modelId = await selectedModelId('stt');
      modelMeta.textContent = `Model · ${modelLabel(modelId)}`;
    } catch (error) {
      modelMeta.textContent = errorMessage(error);
    }
  }

  async function closeStream(cancel: boolean): Promise<void> {
    const active = stream;
    stream = null;
    if (active === null) return;
    try {
      if (!cancel) active.finish();
      await active.close();
    } catch {
      /* best-effort */
    }
  }

  async function runBatch(samples: Float32Array, sampleRate: number): Promise<void> {
    processing = true;
    paintActions();
    setStatus(`Transcribing ${(samples.length / sampleRate).toFixed(2)}s…`);
    try {
      await ensureModelLoaded('stt');
      const mono = toMicRate(samples, sampleRate);
      const output = await window.runanywhere.stt.transcribe(
        window.runanywhere.audio.float32(mono, MIC_SAMPLE_RATE_HZ),
      );
      transcript = output.text.trim();
      partial = false;
      setStatus(transcript.length > 0 ? 'Done.' : 'No speech detected in that recording.', 'success');
      paintOutput();
    } catch (error) {
      setStatus(`Transcribe failed: ${errorMessage(error)}`, 'danger');
    } finally {
      processing = false;
      paintActions();
    }
  }

  async function consumeLive(active: SttStream): Promise<void> {
    try {
      for await (const event of active.events) {
        if (disposed || stream !== active) return;
        applyTranscriptionEvent(event);
      }
      if (!disposed) {
        setStatus(transcript.length > 0 ? 'Done.' : 'No speech detected.', 'success');
      }
    } catch (error) {
      if (!disposed) setStatus(`Transcribe failed: ${errorMessage(error)}`, 'danger');
    } finally {
      processing = false;
      if (!disposed) paintActions();
    }
  }

  function applyTranscriptionEvent(event: TranscriptionEvent): void {
    switch (event.type) {
      case 'partial': {
        const text = (event.alternatives[0] ?? '').trim();
        if (text.length > 0) {
          transcript = text;
          partial = true;
          paintOutput();
        }
        return;
      }
      case 'transcriptFinal':
        transcript = event.transcription.text.trim();
        partial = false;
        paintOutput();
        return;
      case 'failed':
        setStatus(event.error.message, 'danger');
        return;
      case 'started':
      case 'speechStarted':
      case 'speechEnded':
      case 'completed':
      case 'cancelled':
        return;
      default: {
        const _exhaustive: never = event;
        void _exhaustive;
      }
    }
  }

  async function startMic(): Promise<void> {
    try {
      await ensureModelLoaded('stt');
      transcript = '';
      partial = false;
      paintOutput();

      if (mode === SttMode.Live) {
        stream = await window.runanywhere.stt.openStream(STREAM_FORMAT);
        processing = true;
        void consumeLive(stream);
        await mic.start((frame, rate) => {
          if (stream === null) return;
          const mono = toMicRate(frame, rate);
          stream.pushFrame({ samples: float32FrameBytes(mono), sampleCount: mono.length });
        });
        setStatus('Listening — the first guess appears shortly.');
      } else {
        await mic.start();
        setStatus('Recording — press stop when you have finished speaking.');
      }
      capturing = true;
      paintActions();
      paintMode();
    } catch (error) {
      await closeStream(true);
      mic.stop();
      capturing = false;
      processing = false;
      setStatus(`Microphone error: ${errorMessage(error)}`, 'danger');
      paintActions();
    }
  }

  async function toggleMic(): Promise<void> {
    if (capturing) {
      if (mode === SttMode.Live) {
        const active = stream;
        mic.stop();
        capturing = false;
        if (active !== null) {
          setStatus('Settling the transcript…');
          active.finish();
          await active.close().catch(() => undefined);
          stream = null;
        }
        processing = false;
        paintActions();
        paintMode();
        return;
      }
      const result = mic.stop();
      capturing = false;
      paintActions();
      paintMode();
      if (result === null || result.samples.length === 0) {
        setStatus('No audio captured.');
        return;
      }
      await runBatch(result.samples, result.sampleRate);
      return;
    }
    await startMic();
  }

  void refreshModelMeta();
  paintMode();
  paintActions();
  paintOutput();

  return {
    dispose(): void {
      disposed = true;
      mic.stop();
      void closeStream(true);
    },
    model(): { name: string; meta: string } | undefined {
      if (modelId.length === 0) return undefined;
      return { name: modelLabel(modelId), meta: 'Speech-to-text' };
    },
  };
};
