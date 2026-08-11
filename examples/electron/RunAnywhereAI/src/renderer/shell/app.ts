/**
 * The app shell: sidebar + unified toolbar + a detail column, with hash routing.
 *
 * Mirrors `ConsumerMacShell` (ContentView.swift:27-126). Two behaviours from that
 * file are load-bearing:
 *
 *  * **Never leave the sidebar with nothing highlighted.** A split view whose
 *    first column has no selection reads as "not loaded yet".
 *  * **Sidebar visibility survives a relaunch** (`@SceneStorage`), because a
 *    window that reopens with the columns the user left is the difference
 *    between a document app and a demo.
 */
import type { ConversationRecord } from '@shared/conversation';
import { MenuCommand } from '@shared/ipc-contract';

import { Sidebar } from '../components/sidebar';
import { showError } from '../components/toast';
import { Toolbar } from './toolbar';
import { hashForRoute, ROUTE_META, Route, routeFromHash, scopeOf } from './routes';

const SIDEBAR_KEY = 'ra.sidebar.visibility';

/** What a view needs from the shell, and what it hands back. */
export interface ViewContext {
  /** Mount point. A view owns everything inside it and nothing outside. */
  readonly root: HTMLElement;
  /** Re-render the toolbar, e.g. after loading a model or renaming a chat. */
  readonly refreshChrome: () => void;
  readonly navigate: (route: Route) => void;
  /** Push conversation chrome back to the sidebar (Chat owns the store). */
  readonly setConversations: (
    list: readonly ConversationRecord[],
    currentId: string | null,
  ) => void;
  /** Snapshot of the sidebar's conversation list. */
  readonly conversations: () => {
    readonly list: readonly ConversationRecord[];
    readonly currentId: string | null;
  };
}

/** A view is a mount function returning its teardown. */
export type ViewFactory = (context: ViewContext) => ViewInstance;

export interface ViewInstance {
  /** Release listeners, close the microphone, cancel in-flight work. */
  dispose?(): void;
  /** Title override for the toolbar (the chat shows its conversation's title). */
  title?(): string | undefined;
  /** Subtitle override. */
  subtitle?(): string | undefined;
  /** The centred model chip, when the screen uses a model. */
  model?(): { name: string; meta: string } | undefined;
  /** Menu capabilities this view publishes (greys out unavailable items). */
  capabilities?(): {
    canStopGeneration: boolean;
    canShowChatDetails: boolean;
    canPasteAttachment: boolean;
  };
  /** Handle a menu command the shell cannot resolve itself. */
  onMenuCommand?(command: MenuCommand): void;
}

export interface ShellOptions {
  readonly mount: HTMLElement;
  readonly views: Readonly<Record<Route, ViewFactory>>;
  readonly privacyNote: string;
}

export class Shell {
  private readonly sidebar: Sidebar;
  private readonly toolbar: Toolbar;
  private readonly detail: HTMLElement;
  private readonly viewHost: HTMLElement;

  private route: Route = Route.Chat;
  private current: ViewInstance | null = null;
  private conversations: readonly ConversationRecord[] = [];
  private currentConversationId: string | null = null;

  constructor(private readonly options: ShellOptions) {
    this.sidebar = new Sidebar({
      onNavigate: (route) => this.navigate(route),
      onSelectConversation: (id) => {
        this.currentConversationId = id;
        this.navigate(Route.Chat);
        this.emit('conversation:select', id);
      },
      onNewConversation: () => this.emit('conversation:new', null),
      onDeleteConversation: (id) => this.emit('conversation:delete', id),
      onRenameConversation: (id, title) => this.emit('conversation:rename', { id, title }),
    });

    this.toolbar = new Toolbar({
      onToggleSidebar: () => this.toggleSidebar(),
      onOpenSettings: () => {
        void window.appStore.openSettings();
      },
      onOpenModelPicker: () => this.emit('models:pick', null),
      onShowChatDetails: () => this.emit('chat:details', null),
    });

    this.viewHost = document.createElement('div');
    this.viewHost.className = 'ra-view';

    this.detail = document.createElement('main');
    this.detail.className = 'ra-detail';
    this.detail.append(this.toolbar.element, this.viewHost);

    options.mount.append(this.sidebar.element, this.detail);

    // Restore the column the user left.
    if (localStorage.getItem(SIDEBAR_KEY) === 'hidden') {
      options.mount.dataset.sidebar = 'hidden';
    }

    window.addEventListener('hashchange', () => this.navigate(routeFromHash(location.hash), false));
    window.appStore.onMenuCommand((command) => this.handleMenuCommand(command));
  }

  /** Renderer-internal events. Views subscribe rather than reaching into the shell. */
  private emit(name: string, detail: unknown): void {
    window.dispatchEvent(new CustomEvent(`runanywhere:${name}`, { detail }));
  }

  start(): void {
    this.navigate(routeFromHash(location.hash));
  }

  setConversations(list: readonly ConversationRecord[], currentId: string | null): void {
    this.conversations = list;
    this.currentConversationId = currentId;
    this.renderChrome();
  }

  navigate(route: Route, updateHash = true): void {
    if (updateHash && location.hash !== hashForRoute(route)) {
      location.hash = hashForRoute(route);
      return; // the hashchange listener re-enters with the new route
    }

    if (this.current !== null && this.route === route) {
      this.renderChrome();
      return;
    }

    // Leaving a view must release its resources — the Voice and Diarization
    // screens hold the microphone open.
    this.current?.dispose?.();
    this.current = null;
    this.viewHost.replaceChildren();

    this.route = route;

    const factory = this.options.views[route];
    const root = document.createElement('div');
    root.className = 'ra-view-body';
    root.dataset.view = route;
    this.viewHost.append(root);

    try {
      this.current = factory({
        root,
        refreshChrome: () => this.renderChrome(),
        navigate: (next) => this.navigate(next),
        setConversations: (list, currentId) => this.setConversations(list, currentId),
        conversations: () => ({
          list: this.conversations,
          currentId: this.currentConversationId,
        }),
      });
    } catch (error) {
      showError(error, `The ${ROUTE_META[route].title} screen failed to load`);
    }

    this.renderChrome();
  }

  private renderChrome(): void {
    this.sidebar.render({
      route: this.route,
      conversations: this.conversations,
      currentConversationId: this.currentConversationId,
      privacyNote: this.options.privacyNote,
    });

    const capabilities = this.current?.capabilities?.() ?? {
      canStopGeneration: false,
      canShowChatDetails: false,
      canPasteAttachment: false,
    };

    this.toolbar.render({
      route: this.route,
      title: this.current?.title?.(),
      subtitle: this.current?.subtitle?.(),
      model: this.current?.model?.(),
      canShowChatDetails: capabilities.canShowChatDetails,
    });

    window.appStore.setMenuCapabilities(capabilities);
  }

  private toggleSidebar(): void {
    const hidden = this.options.mount.dataset.sidebar === 'hidden';
    this.options.mount.dataset.sidebar = hidden ? 'visible' : 'hidden';
    localStorage.setItem(SIDEBAR_KEY, hidden ? 'visible' : 'hidden');
  }

  private handleMenuCommand(command: MenuCommand): void {
    switch (command) {
      case MenuCommand.ShowChat:
        this.navigate(Route.Chat);
        return;
      case MenuCommand.ShowModels:
        this.navigate(Route.Models);
        return;
      case MenuCommand.ShowAdvanced:
        this.navigate(Route.Advanced);
        return;
      case MenuCommand.ToggleSidebar:
        this.toggleSidebar();
        return;
      case MenuCommand.NewConversation:
        this.navigate(Route.Chat);
        this.emit('conversation:new', null);
        return;
      case MenuCommand.OpenSettings:
        void window.appStore.openSettings();
        return;
      // The rest belong to whichever view is focused.
      case MenuCommand.ShowChatDetails:
      case MenuCommand.FocusComposer:
      case MenuCommand.OpenModelPicker:
      case MenuCommand.StopGeneration:
      case MenuCommand.PasteAttachment:
      case MenuCommand.ImportDocument:
        this.current?.onMenuCommand?.(command);
        return;
      default: {
        // Exhaustive: a new MenuCommand is a compile error until it is handled.
        const unhandled: never = command;
        void unhandled;
      }
    }
  }

  /** Which screen is showing — used by the scope-aware sidebar. */
  get scope(): ReturnType<typeof scopeOf> {
    return scopeOf(this.route);
  }
}
