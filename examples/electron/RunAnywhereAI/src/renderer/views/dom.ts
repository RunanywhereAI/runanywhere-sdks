/**
 * Tiny DOM builders shared by voice screens — keep markup out of string templates
 * so textContent stays the default escape path for model-authored strings.
 */

export function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  className?: string,
  text?: string,
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  if (className !== undefined) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

export function button(
  className: string,
  label: string,
  onClick: () => void,
  options: { disabled?: boolean; ariaLabel?: string } = {},
): HTMLButtonElement {
  const node = el('button', className, label);
  if (options.disabled === true) node.disabled = true;
  if (options.ariaLabel !== undefined) node.setAttribute('aria-label', options.ariaLabel);
  node.addEventListener('click', () => onClick());
  return node;
}

export function section(title: string, body: HTMLElement): HTMLElement {
  const wrap = el('section', 'ra-card ra-voice-section');
  const heading = el('h3', 'ra-type-card-title', title);
  wrap.append(heading, body);
  return wrap;
}

export function statusLine(text: string, tone: 'neutral' | 'danger' | 'success' = 'neutral'): HTMLElement {
  const node = el('p', 'ra-type-secondary ra-voice-status ra-selectable', text);
  node.dataset.tone = tone;
  node.setAttribute('role', 'status');
  return node;
}

export function badge(text: string, tone: 'neutral' | 'success' | 'warning' | 'danger' = 'neutral'): HTMLElement {
  const node = el('span', 'ra-badge', text);
  if (tone !== 'neutral') node.dataset.tone = tone;
  return node;
}
