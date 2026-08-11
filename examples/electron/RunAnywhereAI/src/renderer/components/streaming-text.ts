/**
 * Streaming assistant text.
 *
 * Accumulates `textDelta` / plain appends into one buffer and refreshes only
 * this node — never the whole transcript. Markdown is re-rendered for the tail
 * on demand (throttled while streaming, flush on settle) so a token arrival
 * cannot force a full chat re-parse.
 */
import { renderMarkdown, wireMarkdown } from './markdown';
import { prefersReducedMotion } from '../design/motion';

export interface StreamingTextOptions {
  /** Re-render markdown at most this often while streaming. Default 80 ms. */
  readonly throttleMs?: number;
  readonly error?: boolean;
}

export class StreamingText {
  readonly element: HTMLElement;

  private readonly content: HTMLElement;
  private readonly cursor: HTMLElement;
  private buffer = '';
  private streaming = false;
  private error = false;
  private throttleMs: number;
  private timer = 0;
  private dirty = false;

  constructor(options: StreamingTextOptions = {}) {
    this.throttleMs = options.throttleMs ?? 80;
    this.error = options.error === true;

    this.element = document.createElement('div');
    this.element.className = 'ra-msg-bubble ra-selectable ra-md';
    if (this.error) this.element.dataset.error = 'true';

    this.content = document.createElement('div');
    this.content.className = 'ra-stream-content';

    this.cursor = document.createElement('span');
    this.cursor.className = 'ra-stream-cursor';
    this.cursor.setAttribute('aria-label', 'Generating');
    this.cursor.hidden = true;
    if (prefersReducedMotion()) this.cursor.style.animation = 'none';

    this.element.append(this.content, this.cursor);
  }

  get text(): string {
    return this.buffer;
  }

  setError(error: boolean): void {
    this.error = error;
    this.element.dataset.error = error ? 'true' : 'false';
  }

  setStreaming(streaming: boolean): void {
    this.streaming = streaming;
    this.cursor.hidden = !streaming;
    if (!streaming) this.flush();
  }

  setContent(text: string): void {
    this.buffer = text;
    this.schedule();
  }

  append(delta: string): void {
    if (delta === '') return;
    this.buffer += delta;
    this.schedule();
  }

  /** Force a markdown render now (call on stream settle). */
  flush(): void {
    if (this.timer !== 0) {
      window.clearTimeout(this.timer);
      this.timer = 0;
    }
    this.dirty = false;
    this.render();
  }

  private schedule(): void {
    this.dirty = true;
    if (!this.streaming) {
      this.flush();
      return;
    }
    if (this.timer !== 0) return;
    this.timer = window.setTimeout(() => {
      this.timer = 0;
      if (this.dirty) this.render();
    }, this.throttleMs);
  }

  private render(): void {
    this.dirty = false;
    this.content.innerHTML = this.buffer === '' ? '' : renderMarkdown(this.buffer);
    wireMarkdown(this.content);
  }
}

/** Brand streaming caret for callers that manage their own body HTML. */
export function streamingCursor(): HTMLElement {
  const dot = document.createElement('span');
  dot.className = 'ra-stream-cursor';
  dot.setAttribute('aria-label', 'Generating');
  if (prefersReducedMotion()) dot.style.animation = 'none';
  return dot;
}
