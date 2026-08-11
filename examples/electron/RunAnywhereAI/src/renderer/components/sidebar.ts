/**
 * The sidebar.
 *
 * Mirrors `App/MacSidebar.swift`. Two behaviours from that file are load-bearing
 * and easy to lose:
 *
 *  * **The list is scoped to the open destination.** A sidebar offering "Search
 *    chats" and twelve conversation rows while the detail column shows Models is
 *    describing a screen the user is not looking at. So the Chats section and its
 *    search field appear under Chat and nowhere else, while the three
 *    destinations are always present — otherwise there would be no way back.
 *  * **Search text is cleared when leaving Chat scope** (MacSidebar.swift:92-94).
 */
import type { ConversationRecord } from '@shared/conversation';
import { historyBucket, type HistoryBucket } from '@shared/conversation';

import { icon } from './icons';
import { SIDEBAR_ROUTES, scopeOf, type Route, type Scope } from '../shell/routes';

export interface SidebarCallbacks {
  readonly onNavigate: (route: Route) => void;
  readonly onSelectConversation: (id: string) => void;
  readonly onNewConversation: () => void;
  readonly onDeleteConversation: (id: string) => void;
  readonly onRenameConversation: (id: string, title: string) => void;
}

export interface SidebarState {
  readonly route: Route;
  readonly conversations: readonly ConversationRecord[];
  readonly currentConversationId: string | null;
  readonly privacyNote: string;
}

/** Relative date, as the macOS row's second line shows it. */
function relativeDate(unixMs: number, now: number): string {
  const seconds = Math.max(0, Math.round((now - unixMs) / 1000));
  if (seconds < 60) return 'Just now';
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.round(hours / 24);
  if (days < 7) return `${days}d ago`;
  return new Date(unixMs).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

export class Sidebar {
  readonly element: HTMLElement;

  private searchText = '';
  private scope: Scope = 'chat';
  private state: SidebarState | null = null;

  private readonly searchWrap: HTMLElement;
  private readonly searchInput: HTMLInputElement;
  private readonly nav: HTMLElement;
  private readonly chats: HTMLElement;

  constructor(private readonly callbacks: SidebarCallbacks) {
    this.element = document.createElement('aside');
    this.element.className = 'ra-sidebar';

    // The traffic lights float over this strip; the New Chat button sits at its
    // trailing edge, matching the sidebar toolbar item in MacSidebar.swift:82-89.
    const titlebar = document.createElement('div');
    titlebar.className = 'ra-sidebar-titlebar';
    const newChat = document.createElement('button');
    newChat.className = 'ra-icon-button';
    newChat.type = 'button';
    newChat.title = 'New Chat (⌘N)';
    newChat.setAttribute('aria-label', 'New Chat');
    newChat.innerHTML = icon('square.and.pencil', { size: 18 });
    newChat.addEventListener('click', () => this.callbacks.onNewConversation());
    titlebar.append(newChat);

    this.searchWrap = document.createElement('div');
    this.searchWrap.className = 'ra-sidebar-search';
    this.searchInput = document.createElement('input');
    this.searchInput.type = 'search';
    this.searchInput.placeholder = 'Search chats';
    this.searchInput.className = 'ra-search-input';
    this.searchInput.setAttribute('aria-label', 'Search chats');
    this.searchInput.addEventListener('input', () => {
      this.searchText = this.searchInput.value;
      this.renderChats();
    });
    this.searchWrap.innerHTML = icon('magnifyingglass', { size: 14, className: 'ra-search-icon' });
    this.searchWrap.append(this.searchInput);

    this.nav = document.createElement('nav');
    this.nav.className = 'ra-sidebar-nav';
    this.nav.setAttribute('aria-label', 'Destinations');

    this.chats = document.createElement('div');
    this.chats.className = 'ra-sidebar-chats ra-scroll';

    const footer = document.createElement('div');
    footer.className = 'ra-sidebar-footer';
    footer.innerHTML = `${icon('lock', { size: 13 })}<span class="ra-type-caption"></span>`;

    this.element.append(titlebar, this.searchWrap, this.nav, this.chats, footer);
    this.footer = footer;
  }

  private readonly footer: HTMLElement;

  render(state: SidebarState): void {
    const previousScope = this.scope;
    this.state = state;
    this.scope = scopeOf(state.route);

    // Leaving Chat scope clears the query, so returning does not land on a
    // filtered list the user does not remember typing.
    if (previousScope === 'chat' && this.scope !== 'chat') {
      this.searchText = '';
      this.searchInput.value = '';
    }

    this.renderNav();
    this.renderChats();

    const note = this.footer.querySelector('span');
    if (note !== null) note.textContent = state.privacyNote;
  }

  private renderNav(): void {
    const current = this.state;
    if (current === null) return;
    this.nav.replaceChildren();

    for (const meta of SIDEBAR_ROUTES) {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'ra-nav-row';
      button.dataset.route = meta.route;
      const active = scopeOf(current.route) === scopeOf(meta.route);
      button.setAttribute('aria-current', active ? 'page' : 'false');
      button.innerHTML = `${icon(meta.icon, { size: 17 })}<span>${meta.title}</span>`;
      button.addEventListener('click', () => this.callbacks.onNavigate(meta.route));
      this.nav.append(button);
    }
  }

  private renderChats(): void {
    const current = this.state;
    if (current === null) return;

    // The Chats section and the search field exist only in Chat scope.
    const inChat = this.scope === 'chat';
    this.searchWrap.hidden = !inChat;
    this.chats.hidden = !inChat;
    if (!inChat) {
      this.chats.replaceChildren();
      return;
    }

    const query = this.searchText.trim().toLowerCase();
    const matches =
      query === ''
        ? current.conversations
        : current.conversations.filter(
            (conversation) =>
              conversation.title.toLowerCase().includes(query) ||
              conversation.messages.some((message) => message.content.toLowerCase().includes(query)),
          );

    this.chats.replaceChildren();

    const header = document.createElement('div');
    header.className = 'ra-type-overline ra-sidebar-section';
    header.textContent = 'Chats';
    this.chats.append(header);

    if (matches.length === 0) {
      const empty = document.createElement('p');
      empty.className = 'ra-type-meta ra-sidebar-empty';
      empty.textContent = query === '' ? 'No conversations yet' : 'No matches';
      this.chats.append(empty);
      return;
    }

    // Grouped by recency, like the macOS history list.
    const now = Date.now();
    let lastBucket: HistoryBucket | null = null;
    for (const conversation of matches) {
      const bucket = historyBucket(conversation.updatedAtUnixMs, now);
      if (bucket !== lastBucket) {
        lastBucket = bucket;
        const groupLabel = document.createElement('div');
        groupLabel.className = 'ra-type-caption ra-sidebar-group';
        groupLabel.textContent = bucket;
        this.chats.append(groupLabel);
      }
      this.chats.append(this.conversationRow(conversation, now, conversation.id === current.currentConversationId));
    }
  }

  /** Two lines: what the chat is, and when it last moved. */
  private conversationRow(conversation: ConversationRecord, now: number, active: boolean): HTMLElement {
    const row = document.createElement('div');
    row.className = 'ra-conv-row';
    row.dataset.conversationId = conversation.id;
    if (active) row.setAttribute('aria-current', 'true');

    const open = document.createElement('button');
    open.type = 'button';
    open.className = 'ra-conv-open';
    open.innerHTML =
      `<span class="ra-conv-title">${escapeHtml(conversation.title)}</span>` +
      `<span class="ra-type-caption">${relativeDate(conversation.updatedAtUnixMs, now)}</span>`;
    open.addEventListener('click', () => this.callbacks.onSelectConversation(conversation.id));

    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'ra-conv-delete';
    remove.title = 'Delete conversation';
    remove.setAttribute('aria-label', `Delete ${conversation.title}`);
    remove.innerHTML = icon('trash', { size: 14 });
    remove.addEventListener('click', (event) => {
      event.stopPropagation();
      this.callbacks.onDeleteConversation(conversation.id);
    });

    // Double-click to rename, matching the macOS row's inline edit.
    open.addEventListener('dblclick', () => {
      const title = window.prompt('Rename conversation', conversation.title);
      if (title !== null && title.trim() !== '') {
        this.callbacks.onRenameConversation(conversation.id, title.trim());
      }
    });

    row.append(open, remove);
    return row;
  }
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (char) => {
    switch (char) {
      case '&':
        return '&amp;';
      case '<':
        return '&lt;';
      case '>':
        return '&gt;';
      case '"':
        return '&quot;';
      default:
        return '&#39;';
    }
  });
}
