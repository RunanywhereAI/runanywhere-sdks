/**
 * Chat composer chrome.
 *
 * Layout-only: attach / tools / send affordances and a growing textarea. The
 * view owns send / stop / attach behaviour. Radius is `--ra-radius-xl` (16) —
 * the macOS value, not the iOS 28.
 */
import { icon } from './icons';

export interface ComposerCallbacks {
  readonly onSend: (text: string) => void;
  readonly onStop?: () => void;
  readonly onAttach?: () => void;
  readonly onVoice?: () => void;
}

export interface ComposerOptions {
  readonly placeholder?: string;
  readonly generating?: boolean;
}

export class Composer {
  readonly element: HTMLElement;
  readonly input: HTMLTextAreaElement;

  private readonly sendButton: HTMLButtonElement;
  private readonly pills: HTMLElement;
  private generating = false;

  constructor(
    private readonly callbacks: ComposerCallbacks,
    options: ComposerOptions = {},
  ) {
    this.element = document.createElement('div');
    this.element.className = 'ra-composer-shell';

    this.pills = document.createElement('div');
    this.pills.className = 'ra-composer-pills';
    this.pills.hidden = true;

    const row = document.createElement('div');
    row.className = 'ra-composer';

    if (callbacks.onAttach !== undefined) {
      const attach = document.createElement('button');
      attach.type = 'button';
      attach.className = 'ra-icon-button';
      attach.title = 'Attach';
      attach.setAttribute('aria-label', 'Attach a file');
      attach.innerHTML = icon('plus', { size: 18 });
      attach.addEventListener('click', () => this.callbacks.onAttach?.());
      row.append(attach);
    }

    this.input = document.createElement('textarea');
    this.input.className = 'ra-composer-input';
    this.input.rows = 1;
    this.input.placeholder = options.placeholder ?? 'Ask anything';
    this.input.setAttribute('aria-label', 'Message');
    this.input.addEventListener('input', () => this.autosize());
    this.input.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' && !event.shiftKey) {
        event.preventDefault();
        this.submit();
      }
    });
    row.append(this.input);

    if (callbacks.onVoice !== undefined) {
      const voice = document.createElement('button');
      voice.type = 'button';
      voice.className = 'ra-icon-button';
      voice.title = 'Voice';
      voice.setAttribute('aria-label', 'Open voice');
      voice.innerHTML = icon('waveform', { size: 18 });
      voice.addEventListener('click', () => this.callbacks.onVoice?.());
      row.append(voice);
    }

    this.sendButton = document.createElement('button');
    this.sendButton.type = 'button';
    this.sendButton.className = 'ra-composer-send';
    this.sendButton.addEventListener('click', () => this.submit());
    row.append(this.sendButton);

    this.element.append(this.pills, row);
    this.setGenerating(options.generating === true);
    this.autosize();
  }

  setGenerating(generating: boolean): void {
    this.generating = generating;
    if (generating) {
      this.sendButton.innerHTML = icon('stop.fill', { size: 14 });
      this.sendButton.setAttribute('aria-label', 'Stop generating');
      this.sendButton.title = 'Stop';
      this.sendButton.disabled = this.callbacks.onStop === undefined;
    } else {
      this.sendButton.innerHTML = icon('arrow.up', { size: 18 });
      this.sendButton.setAttribute('aria-label', 'Send');
      this.sendButton.title = 'Send';
      this.sendButton.disabled = false;
    }
  }

  setDropping(dropping: boolean): void {
    const row = this.element.querySelector('.ra-composer');
    if (row instanceof HTMLElement) row.dataset.dropping = dropping ? 'true' : 'false';
  }

  /** Status pills above the input (tools on, attachment name, …). */
  setPills(pills: readonly HTMLElement[]): void {
    this.pills.replaceChildren(...pills);
    this.pills.hidden = pills.length === 0;
  }

  focus(): void {
    this.input.focus();
  }

  clear(): void {
    this.input.value = '';
    this.autosize();
  }

  private submit(): void {
    if (this.generating) {
      this.callbacks.onStop?.();
      return;
    }
    const text = this.input.value.trim();
    if (text === '') return;
    this.callbacks.onSend(text);
  }

  private autosize(): void {
    this.input.style.height = 'auto';
    this.input.style.height = `${Math.min(this.input.scrollHeight, 160)}px`;
  }
}
