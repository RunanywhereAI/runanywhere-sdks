/**
 * Speak (Read aloud) — `tts.speak` owns synthesis and playback.
 *
 * Stop interrupts the active {@link SpeechHandle}. Leaving the route stops
 * playout so audio does not continue off-screen.
 */
import type { SpeechHandle } from '@runanywhere/electron';

import { ensureModelLoaded, errorMessage, modelLabel, selectedModelId } from '../services/modality-models';
import type { ViewFactory, ViewInstance } from '../shell/app';
import { button, el, section, statusLine } from './dom';

const DEFAULT_TEXT =
  'Hello — this synthesis was generated entirely on-device. Nothing left this machine.';

export const createSpeakView: ViewFactory = ({ root }): ViewInstance => {
  let speaking = false;
  let active: SpeechHandle | null = null;
  let speechRate = 1;
  let modelId = '';
  let disposed = false;

  const wrap = el('div', 'ra-view-scroll ra-stack ra-measure-content');
  const modelMeta = el('p', 'ra-type-caption', '');
  const textarea = el('textarea', 'ra-textarea');
  textarea.rows = 4;
  textarea.setAttribute('aria-label', 'Text to read aloud');
  textarea.value = DEFAULT_TEXT;

  const rateRow = el('div', 'ra-row ra-voice-rate');
  const rateLabel = el('label', 'ra-type-secondary', 'Speed');
  rateLabel.htmlFor = 'speak-rate';
  const rateInput = el('input', 'ra-slider');
  rateInput.id = 'speak-rate';
  rateInput.type = 'range';
  rateInput.min = '0.5';
  rateInput.max = '2';
  rateInput.step = '0.1';
  rateInput.value = String(speechRate);
  const rateValue = el('span', 'ra-type-caption', `${speechRate.toFixed(1)}×`);
  rateRow.append(rateLabel, rateInput, rateValue);

  const actions = el('div', 'ra-row');
  const statusEl = statusLine('');

  const body = el('div', 'ra-stack');
  body.append(
    el('p', 'ra-type-secondary', 'Type anything and hear it spoken on this device.'),
    modelMeta,
    textarea,
    rateRow,
    actions,
    statusEl,
  );
  wrap.append(section('Turn text into speech', body));
  root.append(wrap);

  function setStatus(text: string, tone: 'neutral' | 'danger' | 'success' = 'neutral'): void {
    statusEl.textContent = text;
    statusEl.dataset.tone = tone;
  }

  function paintActions(): void {
    actions.replaceChildren(
      button('ra-btn-primary', speaking ? 'Speaking…' : 'Read aloud', () => void runSpeak(), {
        disabled: speaking,
      }),
      button('ra-btn-secondary', 'Stop', () => {
        void active?.interrupt();
      }, { disabled: !speaking }),
    );
    textarea.disabled = speaking;
    rateInput.disabled = speaking;
  }

  async function refreshModelMeta(): Promise<void> {
    try {
      modelId = await selectedModelId('tts');
      modelMeta.textContent = `Voice · ${modelLabel(modelId)}`;
      setStatus('Choose a TTS model under Models if this one is not downloaded yet.');
    } catch (error) {
      modelMeta.textContent = errorMessage(error);
    }
  }

  rateInput.addEventListener('input', () => {
    speechRate = Number(rateInput.value);
    rateValue.textContent = `${speechRate.toFixed(1)}×`;
  });

  async function runSpeak(): Promise<void> {
    const text = textarea.value.trim();
    if (text.length === 0) return;

    speaking = true;
    setStatus('');
    paintActions();

    try {
      await ensureModelLoaded('tts');
      const handle = await window.runanywhere.tts.speak(text, { speed: speechRate });
      if (disposed) {
        await handle.interrupt();
        return;
      }
      active = handle;
      paintActions();
      await handle.waitForPlayout();
      if (handle.error !== undefined) setStatus(handle.error.message, 'danger');
      else setStatus(handle.interrupted ? 'Stopped.' : 'Finished reading.', 'success');
    } catch (error) {
      setStatus(errorMessage(error), 'danger');
    } finally {
      active = null;
      speaking = false;
      if (!disposed) paintActions();
    }
  }

  void refreshModelMeta();
  paintActions();

  return {
    dispose(): void {
      disposed = true;
      void active?.interrupt();
    },
    model(): { name: string; meta: string } | undefined {
      if (modelId.length === 0) return undefined;
      return { name: modelLabel(modelId), meta: 'Text-to-speech' };
    },
  };
};
