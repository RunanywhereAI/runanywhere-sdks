/**
 * The unified toolbar.
 *
 * `.windowToolbarStyle(.unified)` on macOS merges the toolbar into the title bar
 * row: title and subtitle stacked on the left, the model chip centred, controls
 * right-aligned. The three-column grid is what keeps the chip at the same x on
 * every screen.
 */
import { icon } from '../components/icons';
import { ROUTE_META, type Route } from './routes';

export interface ToolbarCallbacks {
  readonly onToggleSidebar: () => void;
  readonly onOpenSettings: () => void;
  readonly onOpenModelPicker: () => void;
  readonly onShowChatDetails: () => void;
}

export interface ToolbarState {
  readonly route: Route;
  /** Overrides the route's title — the chat shows its conversation's title. */
  readonly title?: string;
  readonly subtitle?: string;
  /** The centred model chip. Hidden when a screen uses no model. */
  readonly model?: {
    readonly name: string;
    readonly meta: string;
  };
  readonly canShowChatDetails: boolean;
}

export class Toolbar {
  readonly element: HTMLElement;

  private readonly titles: HTMLElement;
  private readonly titleLine: HTMLElement;
  private readonly subtitleLine: HTMLElement;
  private readonly center: HTMLElement;
  private readonly detailsButton: HTMLButtonElement;

  constructor(private readonly callbacks: ToolbarCallbacks) {
    this.element = document.createElement('header');
    this.element.className = 'ra-toolbar';

    const leading = document.createElement('div');
    leading.className = 'ra-row';

    const sidebarToggle = document.createElement('button');
    sidebarToggle.type = 'button';
    sidebarToggle.className = 'ra-icon-button';
    sidebarToggle.title = 'Show/Hide Sidebar (⌃⌘S)';
    sidebarToggle.setAttribute('aria-label', 'Show or hide the sidebar');
    sidebarToggle.innerHTML = icon('sidebar.left', { size: 17 });
    sidebarToggle.addEventListener('click', () => this.callbacks.onToggleSidebar());

    this.titles = document.createElement('div');
    this.titles.className = 'ra-toolbar-titles';
    this.titleLine = document.createElement('div');
    this.titleLine.className = 'ra-toolbar-title';
    this.subtitleLine = document.createElement('div');
    this.subtitleLine.className = 'ra-toolbar-subtitle';
    this.titles.append(this.titleLine, this.subtitleLine);

    leading.append(sidebarToggle, this.titles);

    this.center = document.createElement('div');
    this.center.className = 'ra-toolbar-center';

    const trailing = document.createElement('div');
    trailing.className = 'ra-toolbar-trailing';

    this.detailsButton = document.createElement('button');
    this.detailsButton.type = 'button';
    this.detailsButton.className = 'ra-icon-button';
    this.detailsButton.title = 'Chat Details (⌘I)';
    this.detailsButton.setAttribute('aria-label', 'Chat details');
    this.detailsButton.innerHTML = icon('info.circle', { size: 17 });
    this.detailsButton.addEventListener('click', () => this.callbacks.onShowChatDetails());

    const settings = document.createElement('button');
    settings.type = 'button';
    settings.className = 'ra-icon-button';
    settings.title = 'Settings (⌘,)';
    settings.setAttribute('aria-label', 'Settings');
    settings.innerHTML = icon('gearshape', { size: 17 });
    settings.addEventListener('click', () => this.callbacks.onOpenSettings());

    trailing.append(this.detailsButton, settings);

    this.element.append(leading, this.center, trailing);
  }

  render(state: ToolbarState): void {
    const meta = ROUTE_META[state.route];
    this.titleLine.textContent = state.title ?? meta.title;
    this.subtitleLine.textContent = state.subtitle ?? meta.subtitle;

    this.detailsButton.disabled = !state.canShowChatDetails;
    this.detailsButton.hidden = state.route !== 'chat';

    this.center.replaceChildren();
    if (state.model !== undefined) {
      const chip = document.createElement('button');
      chip.type = 'button';
      chip.className = 'ra-model-chip';
      chip.title = 'Load Model… (⇧⌘L)';
      chip.innerHTML =
        icon('square.stack.3d.up', { size: 15 }) +
        `<span class="ra-model-chip-text">` +
        `<span class="ra-model-chip-name"></span>` +
        `<span class="ra-model-chip-meta"></span>` +
        `</span>` +
        icon('chevron.down', { size: 12 });
      const name = chip.querySelector('.ra-model-chip-name');
      const metaLine = chip.querySelector('.ra-model-chip-meta');
      if (name !== null) name.textContent = state.model.name;
      if (metaLine !== null) metaLine.textContent = state.model.meta;
      chip.addEventListener('click', () => this.callbacks.onOpenModelPicker());
      this.center.append(chip);
    }
  }
}
