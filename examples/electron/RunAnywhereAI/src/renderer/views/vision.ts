/**
 * Vision — describe an image with the on-device VLM.
 *
 * Thin SDK call: `vlm.generateStream(image.file(path), prompt, options)`.
 * Live camera is deferred (parity plan Slice E). File pick matches the legacy
 * Electron workbench and Swift's photo-library path.
 */
import type { ViewFactory, ViewInstance } from '../shell/app';
import { showError } from '../components/toast';
import { escapeHtml } from '../services/format';
import { logger } from '../services/logger';
import { modelLabel } from '../services/modality-models';
import { generationOptions, loadAppSettings, selectedModel } from '../services/settings';
const log = logger('vision');
const DEFAULT_PROMPT = 'Describe this image in one sentence.';

export const createVisionView: ViewFactory = ({ root, refreshChrome }): ViewInstance => {
  let imagePath: string | null = null;
  let imageLabel = 'No image selected';
  let busy = false;
  let stream: AsyncIterableIterator<unknown> | null = null;
  let caption = '';

  const scroll = document.createElement('div');
  scroll.className = 'ra-view-scroll';
  scroll.innerHTML = `
    <div class="ra-stack">
      <p class="ra-hint">Describe an image with the vision-language model. Nothing leaves this device.</p>
      <div class="ra-card ra-stack">
        <div class="ra-row ra-filepick">
          <button type="button" class="ra-btn-secondary" data-action="pick">Choose image</button>
          <span class="ra-filepick-name" data-role="fname">${escapeHtml(imageLabel)}</span>
        </div>
        <label class="ra-field">
          <span class="ra-label">Prompt</span>
          <textarea class="ra-textarea" data-role="prompt" rows="2">${escapeHtml(DEFAULT_PROMPT)}</textarea>
        </label>
        <div class="ra-row">
          <button type="button" class="ra-btn-primary" data-action="run" disabled>Caption</button>
          <button type="button" class="ra-btn-quiet" data-action="stop" hidden>Stop</button>
        </div>
      </div>
      <div>
        <div class="ra-label">Caption</div>
        <div class="ra-out" data-role="out" data-empty="Choose an image, then Caption it — the description appears here."></div>
      </div>
    </div>
  `;
  root.append(scroll);

  const fname = scroll.querySelector<HTMLElement>('[data-role="fname"]');
  const promptEl = scroll.querySelector<HTMLTextAreaElement>('[data-role="prompt"]');
  const out = scroll.querySelector<HTMLElement>('[data-role="out"]');
  const runBtn = scroll.querySelector<HTMLButtonElement>('[data-action="run"]');
  const stopBtn = scroll.querySelector<HTMLButtonElement>('[data-action="stop"]');
  const pickBtn = scroll.querySelector<HTMLButtonElement>('[data-action="pick"]');

  const setBusy = (next: boolean): void => {
    busy = next;
    if (runBtn !== null) runBtn.disabled = next || imagePath === null;
    if (stopBtn !== null) stopBtn.hidden = !next;
    if (pickBtn !== null) pickBtn.disabled = next;
    refreshChrome();
  };

  const setOut = (text: string): void => {
    if (out === null) return;
    out.textContent = text;
    out.toggleAttribute('data-has-content', text.length > 0);
  };

  const pick = async (): Promise<void> => {
    const paths = await window.appStore.pickFiles({
      title: 'Choose an image',
      filters: [{ name: 'Images', extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'] }],
    });
    const path = paths.at(0);
    if (path === undefined) return;
    imagePath = path;
    imageLabel = path.split(/[/\\]/).pop() ?? path;
    if (fname !== null) fname.textContent = imageLabel;
    if (runBtn !== null) runBtn.disabled = busy;
  };

  const stop = async (): Promise<void> => {
    const active = stream;
    stream = null;
    await active?.return?.(undefined);
  };

  const run = async (): Promise<void> => {
    if (imagePath === null || busy) return;
    await loadAppSettings();
    setBusy(true);
    caption = '';
    setOut('');
    const prompt = promptEl?.value.trim() || DEFAULT_PROMPT;
    const path = imagePath;
    try {
      const iterable = window.runanywhere.vlm.generateStream(
        window.runanywhere.image.file(path),
        prompt,
        generationOptions({ model: selectedModel('vlm') }),
      );
      stream = iterable;
      for await (const event of iterable) {
        if (stream !== iterable) break;
        switch (event.type) {
          case 'textDelta':
            caption += event.text;
            setOut(caption);
            break;
          case 'completed':
            caption = event.result.text;
            setOut(caption.trim());
            break;
          case 'failed':
            throw new Error(event.error.message);
          case 'cancelled':
            setOut((event.partial?.text ?? caption).trim() || 'Cancelled.');
            break;
          case 'started':
          case 'outputItemAdded':
          case 'reasoningDelta':
          case 'toolCallAdded':
          case 'toolArgumentsDelta':
          case 'toolArgumentsDone':
          case 'usage':
            break;
        }
      }
    } catch (error) {
      log.error('vision failed', error);
      showError(error, 'Vision caption failed');
    } finally {
      if (stream !== null) stream = null;
      setBusy(false);
    }
  };

  scroll.addEventListener('click', (event) => {
    const target = (event.target as HTMLElement | null)?.closest<HTMLElement>('[data-action]');
    if (target === null || target === undefined) return;
    const action = target.dataset.action;
    if (action === 'pick') void pick();
    else if (action === 'run') void run();
    else if (action === 'stop') void stop();
  });

  void loadAppSettings();

  return {
    dispose() {
      void stop();
    },
    model() {
      return { name: modelLabel(selectedModel('vlm')), meta: 'Vision' };
    },
    capabilities() {
      return {
        canStopGeneration: busy,
        canShowChatDetails: false,
        canPasteAttachment: false,
      };
    },
  };
};
