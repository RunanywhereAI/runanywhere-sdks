/**
 * Segmented control — `radiogroup` of mutually exclusive options.
 *
 * Arrow keys move selection; Space/Enter activate the focused option. Matches
 * the Web `.segmented` contract so STT Batch/Live and similar choices read as
 * one control rather than two competing buttons.
 */

export interface SegmentedOption<T extends string = string> {
  readonly value: T;
  readonly label: string;
  readonly disabled?: boolean;
}

export interface SegmentedOptions<T extends string = string> {
  readonly name: string;
  readonly options: readonly SegmentedOption<T>[];
  readonly value: T;
  readonly onChange?: (value: T) => void;
}

export interface SegmentedControl<T extends string = string> {
  readonly element: HTMLElement;
  get value(): T;
  setValue(value: T): void;
}

export function createSegmented<T extends string>(options: SegmentedOptions<T>): SegmentedControl<T> {
  const group = document.createElement('div');
  group.className = 'ra-segmented';
  group.setAttribute('role', 'radiogroup');
  group.setAttribute('aria-label', options.name);

  let current = options.value;
  const buttons: HTMLButtonElement[] = [];

  const paint = (): void => {
    for (const button of buttons) {
      const selected = button.dataset.value === current;
      button.setAttribute('aria-checked', selected ? 'true' : 'false');
      button.tabIndex = selected ? 0 : -1;
    }
  };

  const select = (value: T): void => {
    if (value === current) return;
    current = value;
    paint();
    options.onChange?.(value);
  };

  for (const option of options.options) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'ra-segmented-option';
    button.setAttribute('role', 'radio');
    button.dataset.value = option.value;
    button.textContent = option.label;
    button.disabled = option.disabled === true;
    button.addEventListener('click', () => {
      if (button.disabled) return;
      select(option.value);
    });
    button.addEventListener('keydown', (event) => {
      if (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft' && event.key !== 'ArrowDown' && event.key !== 'ArrowUp') {
        return;
      }
      event.preventDefault();
      const enabled = buttons.filter((b) => !b.disabled);
      const index = enabled.indexOf(button);
      if (index < 0 || enabled.length === 0) return;
      const delta = event.key === 'ArrowRight' || event.key === 'ArrowDown' ? 1 : -1;
      const next = enabled[(index + delta + enabled.length) % enabled.length];
      const value = next.dataset.value;
      if (value === undefined) return;
      select(value as T);
      next.focus();
    });
    buttons.push(button);
    group.append(button);
  }

  paint();

  return {
    element: group,
    get value(): T {
      return current;
    },
    setValue(value: T): void {
      current = value;
      paint();
    },
  };
}
