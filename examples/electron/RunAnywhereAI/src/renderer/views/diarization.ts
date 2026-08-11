/**
 * Diarization — who spoke when.
 *
 * Desktop-capable even though macOS Swift gates this behind UIKit: Electron
 * ships ONNX Sortformer. Record or pick a file, then `diarization.diarize`.
 * Do not pin a framework in the app. Leaving the route closes the mic.
 */
import type { DiarizationResult } from '@runanywhere/electron';

import { emptyState } from '../components/empty-state-mark';
import { MIC_SAMPLE_RATE_HZ, MicCapture, toMicRate } from '../services/mic-capture';
import { ensureModelLoaded, errorMessage, modelLabel, selectedModelId } from '../services/modality-models';
import { formatSeconds } from '../services/format';
import type { ViewFactory, ViewInstance } from '../shell/app';
import { button, el, section, statusLine } from './dom';

interface LoadedAudio {
  readonly samples: Float32Array;
  readonly label: string;
}

export const createDiarizationView: ViewFactory = ({ root }): ViewInstance => {
  const mic = new MicCapture();
  let recording = false;
  let busy = false;
  let audio: LoadedAudio | null = null;
  let result: DiarizationResult | null = null;
  let modelId = '';
  let disposed = false;

  const wrap = el('div', 'ra-view-scroll ra-stack ra-measure-content');
  const modelMeta = el('p', 'ra-type-caption', '');
  const actions = el('div', 'ra-row');
  const fileHint = el('p', 'ra-type-secondary', '');
  const statusEl = statusLine('');
  const resultHost = el('div', 'ra-voice-output');

  wrap.append(
    section('Audio', (() => {
      const body = el('div', 'ra-stack');
      body.append(
        el(
          'p',
          'ra-type-secondary',
          'Record a multi-speaker clip, or pick a WAV/audio file. Labelling runs entirely on this device.',
        ),
        modelMeta,
        actions,
        fileHint,
        statusEl,
      );
      return body;
    })()),
    section('Speakers', resultHost),
  );
  root.append(wrap);

  function setStatus(text: string, tone: 'neutral' | 'danger' | 'success' = 'neutral'): void {
    statusEl.textContent = text;
    statusEl.dataset.tone = tone;
  }

  function paintActions(): void {
    actions.replaceChildren(
      button(
        recording ? 'ra-btn-secondary' : 'ra-btn-primary',
        recording ? 'Stop' : 'Record',
        () => void toggleRecord(),
        { disabled: busy },
      ),
      button('ra-btn-secondary', 'Choose file…', () => void pickFile(), {
        disabled: busy || recording,
      }),
      button('ra-btn-primary', busy ? 'Diarizing…' : 'Run diarization', () => void runDiarize(), {
        disabled: busy || recording || audio === null,
      }),
    );
  }

  function paintResult(): void {
    resultHost.replaceChildren();
    if (result === null) {
      resultHost.append(
        emptyState({
          glyph: 'person.2.wave.2',
          title: 'No segments yet',
          message: 'Record or load audio, then run diarization.',
          diameter: 88,
        }),
      );
      return;
    }
    if (result.segments.length === 0) {
      resultHost.append(
        el(
          'p',
          'ra-type-secondary',
          `No speech segments detected (${result.speakerCount} speaker${result.speakerCount === 1 ? '' : 's'}).`,
        ),
      );
      return;
    }

    const summary = el(
      'p',
      'ra-type-caption',
      `${result.speakerCount} speaker${result.speakerCount === 1 ? '' : 's'} · ${result.segments.length} segments`,
    );
    const list = el('ul', 'ra-voice-log-list');
    const speakers = [...new Set(result.segments.map((segment) => segment.speakerId))];
    const sorted = [...result.segments].sort((a, b) => a.startMs - b.startMs);
    for (const segment of sorted) {
      const index = speakers.indexOf(segment.speakerId) + 1;
      const item = el('li', 'ra-voice-log-item');
      item.append(
        el('div', 'ra-type-card-title', `Speaker ${index}`),
        el(
          'div',
          'ra-type-caption ra-selectable',
          `${formatSeconds(segment.startMs)} – ${formatSeconds(segment.endMs)}`,
        ),
      );
      list.append(item);
    }
    resultHost.append(summary, list);
  }

  async function refreshModelMeta(): Promise<void> {
    try {
      modelId = await selectedModelId('diarization');
      modelMeta.textContent = `Model · ${modelLabel(modelId)}`;
    } catch (error) {
      modelMeta.textContent = errorMessage(error);
    }
  }

  async function toggleRecord(): Promise<void> {
    if (recording) {
      const captured = mic.stop();
      recording = false;
      paintActions();
      if (captured === null || captured.samples.length === 0) {
        setStatus('No audio captured.');
        return;
      }
      const mono = toMicRate(captured.samples, captured.sampleRate);
      audio = { samples: mono, label: 'microphone' };
      result = null;
      fileHint.textContent = `Recorded ${(mono.length / MIC_SAMPLE_RATE_HZ).toFixed(2)}s from the microphone.`;
      setStatus('Ready to diarize.');
      paintResult();
      paintActions();
      return;
    }

    try {
      await mic.start();
      recording = true;
      audio = null;
      result = null;
      fileHint.textContent = '';
      setStatus('Recording… tap Stop when done.');
      paintResult();
      paintActions();
    } catch (error) {
      setStatus(`Could not open the microphone: ${errorMessage(error)}`, 'danger');
    }
  }

  async function pickFile(): Promise<void> {
    try {
      const paths = await window.appStore.pickFiles({
        title: 'Choose audio',
        filters: [{ name: 'Audio', extensions: ['wav', 'mp3', 'm4a', 'ogg', 'flac'] }],
      });
      if (paths.length === 0) return;
      const path = paths.at(0);
      if (path === undefined) return;
      setStatus('Loading audio…');
      busy = true;
      paintActions();
      // Path-based input — commons / SDK decode WAV (and path) without app-side decode.
      const diarized = await (async () => {
        await ensureModelLoaded('diarization');
        return window.runanywhere.diarization.diarize(window.runanywhere.audio.file(path));
      })();
      // Keep a path marker so the UI shows what ran; samples stay in the SDK path.
      audio = { samples: new Float32Array(0), label: path };
      result = diarized;
      const basename = path.split(/[/\\]/).at(-1);
      fileHint.textContent = `Loaded from ${basename ?? path}.`;
      setStatus(
        `Done — ${diarized.speakerCount} speakers, ${diarized.segments.length} segments.`,
        'success',
      );
      paintResult();
    } catch (error) {
      // File pick that is not WAV may fail on path decode; fall back to asking
      // the user to record, which always yields float32 we control.
      setStatus(
        `Could not diarize that file (${errorMessage(error)}). Try a WAV, or record from the mic.`,
        'danger',
      );
    } finally {
      busy = false;
      if (!disposed) paintActions();
    }
  }

  async function runDiarize(): Promise<void> {
    if (audio === null) {
      setStatus('Record or load audio first.');
      return;
    }
    if (audio.samples.length === 0) {
      setStatus('This clip was already diarized from a file. Record again or pick another file.');
      return;
    }

    busy = true;
    result = null;
    setStatus('Diarizing…');
    paintActions();
    paintResult();

    try {
      await ensureModelLoaded('diarization');
      const started = performance.now();
      result = await window.runanywhere.diarization.diarize(
        window.runanywhere.audio.float32(audio.samples, MIC_SAMPLE_RATE_HZ),
      );
      setStatus(
        `Done — ${result.speakerCount} speakers, ${result.segments.length} segments in ${Math.round(performance.now() - started)}ms.`,
        'success',
      );
      paintResult();
    } catch (error) {
      setStatus(`Diarization failed: ${errorMessage(error)}`, 'danger');
    } finally {
      busy = false;
      if (!disposed) paintActions();
    }
  }

  void refreshModelMeta();
  paintActions();
  paintResult();

  return {
    dispose(): void {
      disposed = true;
      if (recording) mic.stop();
      recording = false;
    },
    model(): { name: string; meta: string } | undefined {
      if (modelId.length === 0) return undefined;
      return { name: modelLabel(modelId), meta: 'Diarization' };
    },
  };
};
