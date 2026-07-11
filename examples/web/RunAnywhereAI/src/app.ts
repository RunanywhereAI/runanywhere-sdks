/**
 * RunAnywhere AI - Web Consumer Shell
 *
 * Chat is the primary product surface. SDK showcase features stay available
 * behind a drawer, composer actions, and the Advanced hub so the example keeps
 * its power without presenting a twelve-panel developer console on first launch.
 */

import { ModelCategory } from '@runanywhere/web';
import { initChatTab } from './views/chat';
import { initVisionTab } from './views/vision';
import { initVoiceTab } from './views/voice';
import { initTranscribeTab } from './views/transcribe';
import { initSpeakTab } from './views/speak';
import { initVadTab } from './views/vad';
import { initDocumentsTab } from './views/documents';
import { initStorageTab } from './views/storage';
import { initSolutionsTab } from './views/solutions';
import { initBenchmarksTab } from './views/benchmarks';
import { initSettingsTab } from './views/settings';
import {
  buildToolbarModelButton,
  openSheet,
  type OpenSheetOptions,
} from './components/model-selection';
import { appLogger } from './services/app-logger';

// ---------------------------------------------------------------------------
// Tab Lifecycle
// ---------------------------------------------------------------------------

/**
 * Lifecycle callbacks for panels that hold resources (camera, mic, generation).
 * Called by the app shell when the user switches between surfaces so each view
 * can release expensive resources and avoid background work.
 */
export interface TabLifecycle {
  onActivate?: () => void;
  onDeactivate?: () => void;
}

// ---------------------------------------------------------------------------
// Shell Definitions
// ---------------------------------------------------------------------------

type TabId =
  | 'chat'
  | 'advanced'
  | 'storage'
  | 'settings'
  | 'voice'
  | 'vision'
  | 'documents'
  | 'transcribe'
  | 'speak'
  | 'vad'
  | 'solutions'
  | 'benchmarks';

interface TabDef {
  id: TabId;
  label: string;
  initializer: (el: HTMLElement) => TabLifecycle | undefined;
}

interface NavItem {
  type: 'tab' | 'action';
  id: string;
  label: string;
  description: string;
  icon: string;
  tabId?: TabId;
  action?: () => void;
}

interface NavSection {
  title: string;
  items: NavItem[];
}

const CHAT_SHEET_OPTIONS: OpenSheetOptions = {
  title: 'Choose Chat Model',
  filterCategories: [ModelCategory.MODEL_CATEGORY_LANGUAGE],
};

const TABS: TabDef[] = [
  { id: 'chat', label: 'Assistant', initializer: initChatTab },
  { id: 'advanced', label: 'Advanced', initializer: initAdvancedHub },
  { id: 'storage', label: 'Downloads', initializer: initStorageTab },
  { id: 'settings', label: 'Settings', initializer: (el) => { initSettingsTab(el); return undefined; } },
  { id: 'voice', label: 'Talk Mode', initializer: initVoiceTab },
  { id: 'vision', label: 'Image & Live', initializer: initVisionTab },
  { id: 'documents', label: 'Documents', initializer: initDocumentsTab },
  { id: 'transcribe', label: 'Transcribe', initializer: initTranscribeTab },
  { id: 'speak', label: 'Read Aloud', initializer: initSpeakTab },
  { id: 'vad', label: 'Voice Activity', initializer: initVadTab },
  { id: 'solutions', label: 'Solutions', initializer: initSolutionsTab },
  { id: 'benchmarks', label: 'Benchmarks', initializer: initBenchmarksTab },
];

const TAB_INDEX = new Map<TabId, number>(TABS.map((tab, index) => [tab.id, index]));

let activeTab = 0;
let drawerOpen = false;

/** Per-panel lifecycle callbacks keyed by panel id. */
const tabLifecycles: Record<string, TabLifecycle | undefined> = {};

function icon(paths: string): string {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${paths}</svg>`;
}

const ICONS = {
  sparkles: '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8L12 3z"/><path d="M5 3l.8 2.2L8 6l-2.2.8L5 9l-.8-2.2L2 6l2.2-.8L5 3z"/><path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8L19 15z"/>',
  menu: '<line x1="4" y1="7" x2="20" y2="7"/><line x1="4" y1="12" x2="20" y2="12"/><line x1="4" y1="17" x2="20" y2="17"/>',
  newChat: '<path d="M12 5v14"/><path d="M5 12h14"/>',
  model: '<path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><path d="M3.3 7 12 12l8.7-5"/><path d="M12 22V12"/>',
  storage: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/>',
  settings: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .34 1.88l.04.04a2 2 0 1 1-2.83 2.83l-.04-.04A1.7 1.7 0 0 0 15 19.4a1.7 1.7 0 0 0-1 1.55V21a2 2 0 1 1-4 0v-.05A1.7 1.7 0 0 0 9 19.4a1.7 1.7 0 0 0-1.88.34l-.04.04a2 2 0 1 1-2.83-2.83l.04-.04A1.7 1.7 0 0 0 4.6 15a1.7 1.7 0 0 0-1.55-1H3a2 2 0 1 1 0-4h.05A1.7 1.7 0 0 0 4.6 9a1.7 1.7 0 0 0-.34-1.88l-.04-.04a2 2 0 1 1 2.83-2.83l.04.04A1.7 1.7 0 0 0 9 4.6a1.7 1.7 0 0 0 1-1.55V3a2 2 0 1 1 4 0v.05A1.7 1.7 0 0 0 15 4.6a1.7 1.7 0 0 0 1.88-.34l.04-.04a2 2 0 1 1 2.83 2.83l-.04.04A1.7 1.7 0 0 0 19.4 9a1.7 1.7 0 0 0 1.55 1H21a2 2 0 1 1 0 4h-.05A1.7 1.7 0 0 0 19.4 15z"/>',
  mic: '<path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><path d="M12 19v3"/><path d="M8 22h8"/>',
  image: '<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="8.5" cy="10.5" r="1.5"/><path d="M21 15l-4.5-4.5L9 18"/>',
  file: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><path d="M8 13h8"/><path d="M8 17h5"/>',
  waveform: '<path d="M2 12h3l2-7 4 14 3-10 2 3h6"/>',
  speaker: '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M16 9.5a4 4 0 0 1 0 5"/><path d="M19 6a8 8 0 0 1 0 12"/>',
  advanced: '<path d="M4 21v-7"/><path d="M4 10V3"/><path d="M12 21v-9"/><path d="M12 8V3"/><path d="M20 21v-5"/><path d="M20 12V3"/><path d="M2 14h4"/><path d="M10 8h4"/><path d="M18 16h4"/>',
  stack: '<polygon points="12 2 2 7 12 12 22 7 12 2"/><polyline points="2 17 12 22 22 17"/><polyline points="2 12 12 17 22 12"/>',
  gauge: '<path d="M12 14l4-4"/><path d="M4.93 19.07A10 10 0 1 1 19.07 19.07"/><path d="M12 20a2 2 0 1 0 0-4 2 2 0 0 0 0 4z"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/>',
  moon: '<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/>',
} as const;

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------

const THEME_STORAGE_KEY = 'runanywhere-theme';
const THEME_COLORS = { dark: '#191817', light: '#FCFBFA' } as const;

type ThemeName = 'dark' | 'light';

function effectiveTheme(): ThemeName {
  const explicit = document.documentElement.dataset.theme;
  if (explicit === 'light' || explicit === 'dark') return explicit;
  return window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
}

function applyTheme(theme: ThemeName): void {
  document.documentElement.dataset.theme = theme;
  try {
    localStorage.setItem(THEME_STORAGE_KEY, theme);
  } catch { /* storage may not be available */ }
  document
    .querySelector('meta[name="theme-color"]')
    ?.setAttribute('content', THEME_COLORS[theme]);
  refreshThemeButton();
}

function refreshThemeButton(): void {
  const button = document.getElementById('consumer-theme-btn');
  if (!button) return;
  const theme = effectiveTheme();
  button.innerHTML = icon(theme === 'dark' ? ICONS.sun : ICONS.moon);
  const label = theme === 'dark' ? 'Switch to light theme' : 'Switch to dark theme';
  button.setAttribute('aria-label', label);
  button.title = label;
}

function navSections(): NavSection[] {
  return [
    {
      title: '',
      items: [
        navTab('assistant', 'Assistant', 'Private chat with local models', ICONS.sparkles, 'chat'),
        {
          type: 'action',
          id: 'models',
          label: 'Choose model',
          description: 'Download or switch chat models',
          icon: ICONS.model,
          action: () => openSheet(CHAT_SHEET_OPTIONS),
        },
        navTab('downloads', 'Manage downloads', 'Models, cache, and local files', ICONS.storage, 'storage'),
      ],
    },
    {
      title: 'Manage',
      items: [
        navTab('settings', 'Settings', 'Generation, thinking, and API config', ICONS.settings, 'settings'),
        navTab('advanced', 'Advanced', 'SDK demos and diagnostics', ICONS.advanced, 'advanced'),
      ],
    },
  ];
}

function navTab(
  id: string,
  label: string,
  description: string,
  itemIcon: string,
  tabId: TabId,
): NavItem {
  return { type: 'tab', id, label, description, icon: itemIcon, tabId };
}

// ---------------------------------------------------------------------------
// Build App Shell
// ---------------------------------------------------------------------------

export function buildAppShell(): void {
  const app = document.getElementById('app')!;
  app.innerHTML = '';

  const shell = document.createElement('div');
  shell.className = 'consumer-shell';

  const topbar = document.createElement('header');
  topbar.className = 'consumer-topbar';
  topbar.innerHTML = `
    <div class="consumer-topbar__side consumer-topbar__side--left">
      <button type="button" class="shell-icon-btn shell-menu-btn" id="consumer-menu-btn" aria-label="Open menu">
        ${icon(ICONS.menu)}
      </button>
      <div class="consumer-brand" aria-label="RunAnywhere">
        <img class="consumer-brand__mark" src="/runanywhere-logo.svg" alt="" />
        <span class="consumer-brand__name">RunAnywhere</span>
      </div>
    </div>
    <div class="consumer-model-slot" id="consumer-model-slot"></div>
    <div class="consumer-topbar__side consumer-topbar__side--right">
      <button type="button" class="shell-icon-btn" id="consumer-new-chat-btn" aria-label="New chat" title="New chat">
        ${icon(ICONS.newChat)}
      </button>
      <button type="button" class="shell-icon-btn" id="consumer-theme-btn" aria-label="Switch theme" title="Switch theme"></button>
      <button type="button" class="shell-icon-btn" id="consumer-settings-btn" aria-label="Settings" title="Settings">
        ${icon(ICONS.settings)}
      </button>
    </div>
  `;

  const layout = document.createElement('div');
  layout.className = 'consumer-layout';

  const drawer = document.createElement('aside');
  drawer.id = 'consumer-drawer';
  drawer.className = 'consumer-drawer';
  drawer.innerHTML = `
    <div class="consumer-drawer__header">
      <div>
        <div class="consumer-drawer__eyebrow">Local assistant</div>
        <div class="consumer-drawer__title">RunAnywhere</div>
      </div>
      <button type="button" class="shell-icon-btn consumer-drawer__close" id="consumer-close-drawer-btn" aria-label="Close menu">
        ${icon('<path d="M18 6 6 18"/><path d="M6 6l12 12"/>')}
      </button>
    </div>
    <button type="button" class="consumer-new-chat" id="consumer-drawer-new-chat-btn">
      ${icon(ICONS.newChat)}
      <span>New chat</span>
    </button>
    <div class="consumer-recents">
      <div class="consumer-section-title">Recent</div>
      <button type="button" class="consumer-recent-row" id="consumer-current-chat-btn">
        <span class="consumer-recent-row__title" id="consumer-current-chat-title">Current chat</span>
        <span class="consumer-recent-row__meta" id="consumer-current-chat-meta">Stored locally</span>
      </button>
    </div>
    <nav class="tab-bar consumer-nav" id="consumer-nav" aria-label="Main navigation"></nav>
  `;

  const drawerScrim = document.createElement('button');
  drawerScrim.id = 'consumer-drawer-scrim';
  drawerScrim.className = 'consumer-drawer-scrim';
  drawerScrim.type = 'button';
  drawerScrim.setAttribute('aria-label', 'Close menu');

  const main = document.createElement('main');
  main.className = 'consumer-main';
  const tabContent = document.createElement('div');
  tabContent.className = 'tab-content';
  for (const tab of TABS) {
    const panel = document.createElement('section');
    panel.className = 'tab-panel';
    panel.id = `tab-${tab.id}`;
    panel.dataset.tab = tab.id;
    panel.setAttribute('aria-label', tab.label);
    tabContent.appendChild(panel);
  }
  main.appendChild(tabContent);

  layout.appendChild(drawer);
  layout.appendChild(drawerScrim);
  layout.appendChild(main);

  shell.appendChild(topbar);
  shell.appendChild(layout);
  app.appendChild(shell);

  document
    .getElementById('consumer-model-slot')!
    .appendChild(buildToolbarModelButton(CHAT_SHEET_OPTIONS));

  renderNav();
  wireShellActions();
  initializePanels();
  switchTabById('chat');
  refreshCurrentChatSummary();
}

function renderNav(): void {
  const nav = document.getElementById('consumer-nav');
  if (!nav) return;

  nav.innerHTML = navSections().map((section) => `
    <div class="consumer-nav-section">
      ${section.title ? `<div class="consumer-section-title">${section.title}</div>` : ''}
      ${section.items.map((item) => `
        <button
          type="button"
          class="tab-item consumer-nav-item"
          data-nav-id="${item.id}"
          ${item.type === 'tab' ? `data-tab="${item.tabId}"` : `data-action="${item.id}"`}
        >
          <span class="consumer-nav-item__icon">${icon(item.icon)}</span>
          <span class="consumer-nav-item__text">
            <span class="consumer-nav-item__label">${item.label}</span>
            <span class="consumer-nav-item__description">${item.description}</span>
          </span>
        </button>
      `).join('')}
    </div>
  `).join('');

  const sections = navSections();
  for (const section of sections) {
    for (const item of section.items) {
      const el = nav.querySelector<HTMLButtonElement>(`[data-nav-id="${item.id}"]`);
      if (!el) continue;
      el.addEventListener('click', () => {
        if (item.type === 'tab' && item.tabId) {
          switchTabById(item.tabId);
        } else {
          item.action?.();
        }
        closeDrawer();
      });
    }
  }
}

function wireShellActions(): void {
  refreshThemeButton();
  document.getElementById('consumer-theme-btn')?.addEventListener('click', () => {
    applyTheme(effectiveTheme() === 'dark' ? 'light' : 'dark');
  });
  window.matchMedia('(prefers-color-scheme: light)').addEventListener('change', refreshThemeButton);
  document.getElementById('consumer-menu-btn')?.addEventListener('click', openDrawer);
  document.getElementById('consumer-close-drawer-btn')?.addEventListener('click', closeDrawer);
  document.getElementById('consumer-drawer-scrim')?.addEventListener('click', closeDrawer);
  document.getElementById('consumer-settings-btn')?.addEventListener('click', () => switchTabById('settings'));
  document.getElementById('consumer-new-chat-btn')?.addEventListener('click', startNewChat);
  document.getElementById('consumer-drawer-new-chat-btn')?.addEventListener('click', () => {
    startNewChat();
    closeDrawer();
  });
  document.getElementById('consumer-current-chat-btn')?.addEventListener('click', () => {
    switchTabById('chat');
    closeDrawer();
  });

  window.addEventListener('runanywhere:navigate', (event) => {
    const tabId = (event as CustomEvent<{ tab: TabId }>).detail?.tab;
    if (tabId) switchTabById(tabId);
  });
  window.addEventListener('runanywhere:conversation-updated', refreshCurrentChatSummary);
  window.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && drawerOpen) closeDrawer();
  });
}

function initializePanels(): void {
  for (const tab of TABS) {
    tabLifecycles[tab.id] = tab.initializer(document.getElementById(`tab-${tab.id}`)!);
  }
}

function openDrawer(): void {
  drawerOpen = true;
  document.body.classList.add('consumer-drawer-open');
  setMobileDrawerAria(false);
}

function closeDrawer(): void {
  drawerOpen = false;
  document.body.classList.remove('consumer-drawer-open');
  setMobileDrawerAria(true);
}

function setMobileDrawerAria(hidden: boolean): void {
  const drawer = document.getElementById('consumer-drawer');
  if (!drawer) return;
  if (window.matchMedia('(max-width: 920px)').matches) {
    drawer.setAttribute('aria-hidden', String(hidden));
  } else {
    drawer.removeAttribute('aria-hidden');
  }
}

function startNewChat(): void {
  window.dispatchEvent(new CustomEvent('runanywhere:new-chat'));
  switchTabById('chat');
  refreshCurrentChatSummary();
}

function switchTabById(tabId: TabId): void {
  const index = TAB_INDEX.get(tabId);
  if (index === undefined) return;
  switchTab(index);
}

function switchTab(index: number): void {
  const previousTab = activeTab;
  activeTab = index;

  if (previousTab !== index) {
    const previousId = TABS[previousTab].id;
    try {
      tabLifecycles[previousId]?.onDeactivate?.();
    } catch (err) {
      appLogger.warning(`[App] Panel ${previousId} onDeactivate error:`, err);
    }
  }

  document.querySelectorAll('.tab-panel').forEach((panel, i) => {
    panel.classList.toggle('active', i === index);
  });

  const activeId = TABS[index].id;
  document.querySelectorAll<HTMLElement>('.tab-item[data-tab]').forEach((item) => {
    item.classList.toggle('active', item.dataset.tab === activeId);
  });

  if (previousTab !== index) {
    try {
      tabLifecycles[activeId]?.onActivate?.();
    } catch (err) {
      appLogger.warning(`[App] Panel ${activeId} onActivate error:`, err);
    }
  }
}

function refreshCurrentChatSummary(): void {
  const titleEl = document.getElementById('consumer-current-chat-title');
  const metaEl = document.getElementById('consumer-current-chat-meta');
  if (!titleEl || !metaEl) return;

  try {
    const saved = localStorage.getItem('runanywhere-chat-conversation');
    if (!saved) {
      titleEl.textContent = 'No saved chats yet';
      metaEl.textContent = 'Start a private local conversation';
      return;
    }
    const parsed: unknown = JSON.parse(saved);
    const record = typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)
      ? parsed as Readonly<Record<string, unknown>>
      : null;
    const rawMessages = record && Array.isArray(record.messages) ? record.messages : [];
    const firstUser = rawMessages.find((message): boolean => {
      if (typeof message !== 'object' || message === null || Array.isArray(message)) return false;
      const candidate = message as Readonly<Record<string, unknown>>;
      return candidate.role === 'user'
        && typeof candidate.content === 'string'
        && candidate.content.trim().length > 0;
    }) as Readonly<Record<string, unknown>> | undefined;
    const firstContent = typeof firstUser?.content === 'string' ? firstUser.content.trim() : '';
    const updatedAt = typeof record?.updatedAt === 'number' && Number.isFinite(record.updatedAt)
      ? record.updatedAt
      : null;
    titleEl.textContent = firstContent.slice(0, 56) || 'Current chat';
    metaEl.textContent = updatedAt !== null
      ? `Saved ${new Date(updatedAt).toLocaleDateString()}`
      : 'Stored locally';
  } catch {
    titleEl.textContent = 'Current chat';
    metaEl.textContent = 'Stored locally';
  }
}

function initAdvancedHub(el: HTMLElement): TabLifecycle {
  const hubItems: Array<{
    tab: TabId;
    icon: string;
    title: string;
    subtitle: string;
  }> = [
    { tab: 'voice', icon: ICONS.mic, title: 'Talk Mode', subtitle: 'Full STT + LLM + TTS voice assistant' },
    { tab: 'documents', icon: ICONS.file, title: 'Documents & RAG', subtitle: 'Index local documents and ask grounded questions' },
    { tab: 'transcribe', icon: ICONS.waveform, title: 'Transcribe', subtitle: 'Speech-to-text utility' },
    { tab: 'speak', icon: ICONS.speaker, title: 'Read Aloud', subtitle: 'Text-to-speech utility' },
    { tab: 'vad', icon: ICONS.waveform, title: 'Voice Activity', subtitle: 'Speech and silence diagnostics' },
    { tab: 'storage', icon: ICONS.storage, title: 'Storage', subtitle: 'Models, cache, and browser files' },
    { tab: 'benchmarks', icon: ICONS.gauge, title: 'Benchmarks', subtitle: 'Measure local model performance' },
    { tab: 'solutions', icon: ICONS.stack, title: 'Solutions', subtitle: 'Run scripted SDK workflows' },
  ];

  el.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Advanced</div>
      <div class="toolbar-actions"></div>
    </div>
    <div class="scroll-area advanced-hub">
      <section class="advanced-hub__intro">
        <h2>SDK utilities</h2>
        <p>Document, image, and live camera flows can start from the assistant composer. These lower-level tools stay here for diagnostics and deeper control.</p>
      </section>
      <section class="advanced-hub__section">
        <div class="consumer-section-title">Assistant Modes</div>
        ${hubItems.slice(0, 2).map((item) => advancedRow(item)).join('')}
      </section>
      <section class="advanced-hub__section">
        <div class="consumer-section-title">Voice Utilities</div>
        ${hubItems.slice(2, 5).map((item) => advancedRow(item)).join('')}
      </section>
      <section class="advanced-hub__section">
        <div class="consumer-section-title">Management</div>
        ${hubItems.slice(5).map((item) => advancedRow(item)).join('')}
      </section>
    </div>
  `;

  el.querySelectorAll<HTMLButtonElement>('[data-advanced-target]').forEach((button) => {
    button.addEventListener('click', () => {
      const tab = button.dataset.advancedTarget as TabId | undefined;
      if (tab) switchTabById(tab);
    });
  });
  return {};
}

function advancedRow(item: { tab: TabId; icon: string; title: string; subtitle: string }): string {
  return `
    <button type="button" class="advanced-row" data-advanced-target="${item.tab}">
      <span class="advanced-row__icon">${icon(item.icon)}</span>
      <span><strong>${item.title}</strong><small>${item.subtitle}</small></span>
    </button>
  `;
}

// Export for external probes.
export function getActiveTab(): number {
  return activeTab;
}
