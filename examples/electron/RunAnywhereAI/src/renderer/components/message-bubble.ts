/**
 * Message bubble chrome.
 *
 * User turns: brand gradient capsule (radius 16). Assistant turns: prose at
 * full reading measure — no fill. Thinking disclosure and streaming cursor are
 * optional slots the chat view fills.
 */
import { icon } from './icons';
import { escapeHtml } from '../services/format';

export type MessageRole = 'user' | 'assistant';

export interface MessageBubbleOptions {
  readonly role: MessageRole;
  readonly bodyHtml: string;
  readonly who?: string;
  readonly thinkingHtml?: string;
  readonly thinkingOpen?: boolean;
  readonly streaming?: boolean;
  readonly error?: boolean;
  readonly latest?: boolean;
  readonly metrics?: string;
  readonly onCopy?: () => void;
  readonly onRegenerate?: () => void;
}

export function messageBubble(options: MessageBubbleOptions): HTMLElement {
  const root = document.createElement('article');
  root.className = 'ra-msg';
  root.dataset.role = options.role;
  if (options.error === true) root.dataset.error = 'true';
  if (options.latest === true) root.dataset.latest = 'true';

  const who = document.createElement('div');
  who.className = 'ra-msg-who';
  who.textContent = options.who ?? (options.role === 'assistant' ? 'RunAnywhere' : 'You');
  root.append(who);

  if (options.role === 'assistant' && options.thinkingHtml !== undefined && options.thinkingHtml !== '') {
    const details = document.createElement('details');
    details.className = 'ra-thinking';
    if (options.thinkingOpen === true || (options.streaming === true && options.bodyHtml === '')) {
      details.open = true;
    }
    const summary = document.createElement('summary');
    summary.innerHTML = `${icon('brain', { size: 14 })}<span>Reasoning</span>`;
    const body = document.createElement('div');
    body.className = 'ra-thinking-body ra-selectable';
    body.innerHTML = options.thinkingHtml;
    details.append(summary, body);
    root.append(details);
  }

  const bubble = document.createElement('div');
  bubble.className = 'ra-msg-bubble ra-selectable';
  bubble.innerHTML = options.bodyHtml;
  if (options.streaming === true) {
    bubble.insertAdjacentHTML(
      'beforeend',
      '<span class="ra-stream-cursor" aria-label="Generating"></span>',
    );
  }
  root.append(bubble);

  if (options.role === 'assistant' && options.streaming !== true) {
    const meta = document.createElement('div');
    meta.className = 'ra-msg-meta';

    if (options.metrics !== undefined && options.metrics !== '') {
      const metrics = document.createElement('span');
      metrics.textContent = options.metrics;
      meta.append(metrics);
    }

    const actions = document.createElement('div');
    actions.className = 'ra-msg-actions';

    if (options.onCopy !== undefined) {
      const copy = document.createElement('button');
      copy.type = 'button';
      copy.className = 'ra-btn-quiet';
      copy.innerHTML = `${icon('doc.on.doc', { size: 14 })}<span>Copy</span>`;
      copy.addEventListener('click', () => options.onCopy?.());
      actions.append(copy);
    }

    if (options.onRegenerate !== undefined) {
      const regen = document.createElement('button');
      regen.type = 'button';
      regen.className = 'ra-btn-quiet';
      regen.innerHTML = `${icon('arrow.clockwise', { size: 14 })}<span>Retry</span>`;
      regen.addEventListener('click', () => options.onRegenerate?.());
      actions.append(regen);
    }

    if (actions.childElementCount > 0) meta.append(actions);
    if (meta.childElementCount > 0) root.append(meta);
  }

  return root;
}

/** Plain-text user bubble — user turns never run through markdown. */
export function userBubbleHtml(text: string): string {
  return escapeHtml(text).replace(/\n/g, '<br>');
}
