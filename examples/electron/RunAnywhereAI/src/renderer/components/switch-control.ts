/**
 * Switch control — a real `<button role="switch">`.
 *
 * `aria-checked` is the state of record; the CSS mirrors it. No business logic:
 * callers own the setting and pass the next value through `onChange`.
 */

export interface SwitchOptions {
  readonly checked?: boolean;
  readonly disabled?: boolean;
  readonly label?: string;
  readonly onChange?: (checked: boolean) => void;
}

export interface SwitchControl {
  readonly element: HTMLButtonElement;
  get checked(): boolean;
  setChecked(checked: boolean): void;
  setDisabled(disabled: boolean): void;
}

export function createSwitch(options: SwitchOptions = {}): SwitchControl {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'ra-switch';
  button.setAttribute('role', 'switch');
  button.setAttribute('aria-checked', options.checked === true ? 'true' : 'false');
  if (options.label !== undefined) button.setAttribute('aria-label', options.label);
  button.disabled = options.disabled === true;

  button.addEventListener('click', () => {
    if (button.disabled) return;
    const next = button.getAttribute('aria-checked') !== 'true';
    button.setAttribute('aria-checked', next ? 'true' : 'false');
    options.onChange?.(next);
  });

  return {
    element: button,
    get checked(): boolean {
      return button.getAttribute('aria-checked') === 'true';
    },
    setChecked(checked: boolean): void {
      button.setAttribute('aria-checked', checked ? 'true' : 'false');
    },
    setDisabled(disabled: boolean): void {
      button.disabled = disabled;
    },
  };
}
