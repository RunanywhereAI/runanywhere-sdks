/**
 * Primary mic control for STT / VAD / Voice.
 *
 * Sized to `Control.primaryCircle` (60). States are presentation-only — the
 * view owns the capture session and must call `dispose`/stop when leaving the
 * screen so the microphone closes.
 */
import { icon } from './icons';

export type MicButtonState = 'idle' | 'listening' | 'recording' | 'busy' | 'disabled';

export interface MicButtonOptions {
  readonly state?: MicButtonState;
  readonly label?: string;
  readonly onClick?: () => void;
}

export interface MicButton {
  readonly element: HTMLButtonElement;
  setState(state: MicButtonState): void;
  dispose(): void;
}

export function createMicButton(options: MicButtonOptions = {}): MicButton {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'ra-mic';
  button.innerHTML = icon('mic', { size: 28 });

  const apply = (state: MicButtonState): void => {
    button.dataset.state = state;
    button.disabled = state === 'disabled' || state === 'busy';
    const label =
      options.label ??
      (state === 'listening' || state === 'recording'
        ? 'Stop listening'
        : state === 'busy'
          ? 'Working'
          : 'Start listening');
    button.setAttribute('aria-label', label);
    button.title = label;
  };

  apply(options.state ?? 'idle');

  const onClick = (): void => {
    if (button.disabled) return;
    options.onClick?.();
  };
  button.addEventListener('click', onClick);

  return {
    element: button,
    setState(state: MicButtonState): void {
      apply(state);
    },
    dispose(): void {
      button.removeEventListener('click', onClick);
      button.remove();
    },
  };
}
