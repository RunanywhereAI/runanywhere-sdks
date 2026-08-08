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
import { initSegmentationTab } from './views/segmentation';
import { initDiarizationTab } from './views/diarization';
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
import { icon, type IconName } from './components/icons';
import { appLogger } from './services/app-logger';
import { ConversationsStore, type StoredConversation } from './services/conversations-store';

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
  | 'segmentation'
  | 'documents'
  | 'transcribe'
  | 'speak'
  | 'vad'
  | 'diarization'
  | 'solutions'
  | 'benchmarks';

interface TabDef {
  id: TabId;
  label: string;
  initializer: (el: HTMLElement) => TabLifecycle | undefined;
  /**
   * The surface this one was opened *from*, for panels reached by drilling in
   * rather than from the sidebar.
   *
   * Without this the shell had no idea these panels were nested, and it showed:
   * opening one cleared every nav highlight — so the sidebar pointed at nothing
   * and the only "where am I" signal was the panel's own title — and no view
   * offered a way back. On mobile, where the sidebar is a drawer, drilling into
   * one of these was a dead end.
   */
  parent?: TabId;
}

interface NavItem {
  type: 'tab' | 'action';
  id: string;
  label: string;
  description: string;
  icon: IconName;
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
  // Top-level surfaces: these have their own sidebar entry, so no parent.
  { id: 'chat', label: 'Assistant', initializer: initChatTab },
  // Talk is a destination, not a diagnostic. It used to sit inside the Advanced hub
  // with `parent: 'advanced'`, while Android gave it the drawer's second row — so a
  // reader who learned it on the phone could not find it in the browser. Same name in
  // both apps now ("Talk"), at the same level of the navigation.
  { id: 'voice', label: 'Talk', initializer: initVoiceTab },
  { id: 'advanced', label: 'Advanced', initializer: initAdvancedHub },
  { id: 'storage', label: 'Downloads', initializer: initStorageTab },
  { id: 'settings', label: 'Settings', initializer: (el) => { initSettingsTab(el); return undefined; } },
  // Drilled-into surfaces. `parent` is the surface a user most likely came from,
  // and is only the fallback: switchTab records the actual origin, because some of
  // these have two entrances (Image & Live is both an Advanced-adjacent surface and
  // the composer's Live camera action) and a hardcoded parent would send half of
  // those visitors somewhere they had never been.
  { id: 'vision', label: 'Image & Live', initializer: initVisionTab, parent: 'chat' },
  { id: 'segmentation', label: 'Segmentation', initializer: initSegmentationTab, parent: 'advanced' },
  { id: 'documents', label: 'Documents', initializer: initDocumentsTab, parent: 'advanced' },
  { id: 'transcribe', label: 'Transcribe', initializer: initTranscribeTab, parent: 'advanced' },
  { id: 'speak', label: 'Read Aloud', initializer: initSpeakTab, parent: 'advanced' },
  { id: 'vad', label: 'Voice Activity', initializer: initVadTab, parent: 'advanced' },
  { id: 'diarization', label: 'Diarization', initializer: initDiarizationTab, parent: 'advanced' },
  { id: 'solutions', label: 'Solutions', initializer: initSolutionsTab, parent: 'advanced' },
  { id: 'benchmarks', label: 'Benchmarks', initializer: initBenchmarksTab, parent: 'advanced' },
];

const TAB_INDEX = new Map<TabId, number>(TABS.map((tab, index) => [tab.id, index]));

// ---------------------------------------------------------------------------
// Routing
// ---------------------------------------------------------------------------

/**
 * Every surface has a URL, and the URL is a fragment: `#/vision`.
 *
 * WHY THIS EXISTS AT ALL. The active surface used to be a module-scope integer.
 * So there was no way to link to a tab, the browser's Back button did nothing on
 * a screen full of drilled-into panels, and a refresh — including the one the
 * cross-origin-isolation service worker performs on Safari — always dumped the
 * user back on the assistant, whatever they had been doing.
 *
 * WHY A FRAGMENT RATHER THAN THE HISTORY API. This example is a static bundle:
 * Vite in development, a prebuilt static output on Vercel in production, and a
 * plain directory of files for anyone who copies it. A path-based route only
 * survives a refresh or a pasted link when the host rewrites every unknown path
 * to `index.html` — a server-side contract this app would then depend on in
 * three separate configs, and one that silently does not exist on a bare file
 * server. A fragment is never sent to the server, so it works everywhere the
 * bundle does, including `file://`. No router library: the whole mechanism is
 * the four functions below.
 */
const DEFAULT_TAB: TabId = 'chat';

/** The surface the current URL names; the default for an absent or bogus one. */
function routeFromLocation(): TabId {
  const slug = window.location.hash.replace(/^#\/?/, '').trim();
  return TAB_INDEX.has(slug as TabId) ? (slug as TabId) : DEFAULT_TAB;
}

function hashForTab(tabId: TabId): string {
  return `#/${tabId}`;
}

/** What this app writes into `history.state`, to recognise its own entries. */
interface RouteHistoryState {
  runanywhereDepth: number;
}

/**
 * How many entries this app has pushed onto the session history.
 *
 * Re-read from `history.state` on every traversal so it stays correct through
 * back *and* forward, rather than drifting the way a plain counter would. The
 * toolbar's Back button reads it to tell "there is an entry of ours behind this
 * one" from "this is where the user entered the site" — on a deep link straight
 * into a nested surface, `history.back()` would leave the app entirely.
 */
let historyDepth = 0;

function readHistoryDepth(state: unknown): number {
  const depth = (state as RouteHistoryState | null)?.runanywhereDepth;
  return typeof depth === 'number' && depth >= 0 ? depth : 0;
}

/**
 * Go to a surface and record it in the browser's history.
 *
 * `replace` is for the initial route only: restoring the tab a URL already names
 * must not leave a phantom entry behind the user's first Back press.
 */
function navigateToTab(tabId: TabId, options: { replace?: boolean } = {}): void {
  if (!TAB_INDEX.has(tabId)) return;
  const hash = hashForTab(tabId);
  if (options.replace || window.location.hash === hash) {
    // Already the current URL: re-selecting the surface you are on — tapping its
    // nav row again, or "New chat" from the assistant — must not stack a
    // duplicate entry that Back then has to walk through.
    window.history.replaceState({ runanywhereDepth: historyDepth }, '', hash);
  } else {
    historyDepth += 1;
    window.history.pushState({ runanywhereDepth: historyDepth }, '', hash);
  }
  applyRoute();
}

/** Show whatever surface the URL currently names. The one way a tab changes. */
function applyRoute(): void {
  const index = TAB_INDEX.get(routeFromLocation());
  if (index !== undefined) switchTab(index);
}

/** Surfaces with their own sidebar entry — the only ones that can be highlighted. */
const NAV_TAB_IDS = new Set<TabId>(TABS.filter((tab) => tab.parent === undefined).map((tab) => tab.id));

/**
 * Where each nested surface was actually opened from.
 *
 * Overrides TabDef.parent so Back retraces the user's own step: Image & Live reached
 * from the composer returns to the assistant, and the same surface reached from
 * the Advanced hub returns there.
 */
const tabOrigin = new Map<TabId, TabId>();

/**
 * Watches the current nested panel so a view re-render cannot drop the shell's
 * Back button. Exactly one is live at a time — see syncBackButton.
 */
let backButtonObserver: MutationObserver | null = null;

let activeTab = 0;
let drawerOpen = false;

/** Per-panel lifecycle callbacks keyed by panel id. */
const tabLifecycles: Record<string, TabLifecycle | undefined> = {};

/**
 * The shell's glyph names, aliased from the shared registry.
 *
 * The paths themselves used to live here as a 20-entry map, with a private
 * `icon()` helper at 1.7px alongside a byte-identical one in `views/chat.ts` at
 * the same weight — two copies of the same function, and one of four stroke
 * weights in the app. Both now come from `components/icons.ts` at the §7 weight.
 *
 * Kept as an alias rather than rewriting 21 call sites to string literals: the
 * names read as a table of contents for the nav, and `IconName` still makes a
 * typo a compile error.
 */
const ICONS = {
  sparkles: 'sparkles',
  menu: 'menu',
  newChat: 'plus',
  model: 'model',
  /** Bytes ARRIVING, not bytes at rest — the Download action on a model row. The
   * Downloads *destination* uses `storage`; a tray glyph on a bytes-at-rest screen
   * mislabels it as an in-flight-transfer screen. */
  downloads: 'download',
  storage: 'storage',
  settings: 'settings',
  mic: 'mic',
  image: 'image',
  file: 'file',
  waveform: 'waveform',
  speaker: 'speaker',
  advanced: 'advanced',
  stack: 'stack',
  gauge: 'gauge',
  sun: 'sun',
  moon: 'moon',
  back: 'back',
} as const satisfies Record<string, IconName>;

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------

const THEME_STORAGE_KEY = 'runanywhere-theme';
const THEME_COLORS = { dark: '#191817', light: '#FCFBFA' } as const;

type ThemeName = 'dark' | 'light';

/**
 * The user's explicit choice, or null when they have never toggled and are
 * therefore still following the OS.
 *
 * This has to be tracked separately from `data-theme`, because the pre-paint
 * script in index.html always resolves the attribute to a concrete value —
 * `design-system.css` has no `prefers-color-scheme` fallback, by design, so an
 * unset attribute would mean dark rather than "ask the OS". Reading the
 * attribute back therefore cannot distinguish "chose light" from "OS is light",
 * which is the difference that decides whether an OS change should be followed.
 */
let storedThemeChoice: ThemeName | null = readStoredThemeChoice();

function readStoredThemeChoice(): ThemeName | null {
  try {
    const value = localStorage.getItem(THEME_STORAGE_KEY);
    return value === 'light' || value === 'dark' ? value : null;
  } catch {
    return null; // storage may be blocked; treat as "follow the OS"
  }
}

function systemTheme(): ThemeName {
  return window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
}

function effectiveTheme(): ThemeName {
  return storedThemeChoice ?? systemTheme();
}

/** Paints the current effective theme. Does not change the stored choice. */
function renderTheme(): void {
  const theme = effectiveTheme();
  document.documentElement.dataset.theme = theme;
  document.documentElement.style.colorScheme = theme;
  document
    .querySelector('meta[name="theme-color"]')
    ?.setAttribute('content', THEME_COLORS[theme]);
  refreshThemeButton();
}

function applyTheme(theme: ThemeName): void {
  storedThemeChoice = theme;
  try {
    localStorage.setItem(THEME_STORAGE_KEY, theme);
  } catch { /* storage may not be available */ }
  renderTheme();
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
        navTab('talk', 'Talk', 'Hands-free voice assistant', ICONS.mic, 'voice'),
        {
          type: 'action',
          id: 'models',
          label: 'Choose model',
          description: 'Download or switch chat models',
          icon: ICONS.model,
          action: () => openSheet(CHAT_SHEET_OPTIONS),
        },
        // "Downloads", not "Manage downloads", and the `storage` glyph, not the
        // download tray: this row, the Advanced-hub row, the tab registry and the
        // panel's own toolbar all name ONE destination, and they used to name it four
        // different ways with two different glyphs.
        navTab('downloads', 'Downloads', 'Models on this device, and space used', ICONS.storage, 'storage'),
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
  itemIcon: IconName,
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
        ${icon('close')}
      </button>
    </div>
    <button type="button" class="consumer-new-chat" id="consumer-drawer-new-chat-btn">
      ${icon(ICONS.newChat)}
      <span>New chat</span>
    </button>
    <div class="consumer-recents">
      <div class="consumer-section-title">Recent</div>
      <div class="consumer-recent-list" id="consumer-conversation-list"></div>
    </div>
    <nav class="tab-bar consumer-nav" id="consumer-nav" aria-label="Main navigation"></nav>
    <div class="consumer-drawer__footer" id="consumer-runtime-slot"></div>
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
  // Restore the surface the URL names — a deep link, a refresh, or the reload
  // the cross-origin-isolation service worker performs on its first install.
  // `replace`, so the restored tab is the entry the user is already on.
  historyDepth = readHistoryDepth(window.history.state);
  navigateToTab(routeFromLocation(), { replace: true });
  void refreshConversationList();
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
          navigateToTab(item.tabId);
        } else {
          item.action?.();
        }
        closeDrawer();
      });
    }
  }
}

function wireShellActions(): void {
  renderTheme();
  document.getElementById('consumer-theme-btn')?.addEventListener('click', () => {
    applyTheme(effectiveTheme() === 'dark' ? 'light' : 'dark');
  });
  // Only repaints while the user is still following the OS; once they toggle,
  // `storedThemeChoice` wins and `renderTheme()` is a no-op.
  window.matchMedia('(prefers-color-scheme: light)').addEventListener('change', renderTheme);
  document.getElementById('consumer-menu-btn')?.addEventListener('click', openDrawer);
  document.getElementById('consumer-close-drawer-btn')?.addEventListener('click', closeDrawer);
  document.getElementById('consumer-drawer-scrim')?.addEventListener('click', closeDrawer);
  document.getElementById('consumer-settings-btn')?.addEventListener('click', () => navigateToTab('settings'));
  document.getElementById('consumer-new-chat-btn')?.addEventListener('click', startNewChat);
  document.getElementById('consumer-drawer-new-chat-btn')?.addEventListener('click', () => {
    startNewChat();
    closeDrawer();
  });

  // Back and forward. `pushState` fires nothing, so this only ever runs for a
  // real traversal — our own navigations call `applyRoute()` themselves.
  window.addEventListener('popstate', (event) => {
    historyDepth = readHistoryDepth(event.state);
    applyRoute();
  });
  // A fragment typed or edited in the address bar fires `hashchange` but not
  // `popstate`, so the two listeners together are what make the URL the single
  // source of truth. Guarded because a traversal fires this one as well, right
  // after the `popstate` that already applied the route.
  window.addEventListener('hashchange', () => {
    if (routeFromLocation() !== TABS[activeTab].id) applyRoute();
  });

  window.addEventListener('runanywhere:navigate', (event) => {
    const tabId = (event as CustomEvent<{ tab: TabId }>).detail?.tab;
    if (tabId) navigateToTab(tabId);
  });
  ConversationsStore.onChange(() => {
    void refreshConversationList();
  });
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
  navigateToTab('chat');
}

/**
 * Which sidebar entry should read as current for a given surface.
 *
 * Nested surfaces have no entry of their own, so they light their nearest
 * ancestor that does. Walks the chain rather than reading `parent` once, so a
 * surface nested two levels deep still resolves to a real nav entry.
 */
function navHighlightFor(tabId: TabId): TabId {
  const seen = new Set<TabId>();
  let current = tabId;
  while (!NAV_TAB_IDS.has(current)) {
    if (seen.has(current)) break;      // cycle guard: a mis-declared parent must not hang the shell
    seen.add(current);
    const parent = TABS[TAB_INDEX.get(current)!].parent;
    if (parent === undefined) break;
    current = parent;
  }
  return current;
}

/** Where Back goes: the surface actually navigated from, else the declared parent. */
function backTargetFor(tab: TabDef): TabId | undefined {
  if (tab.parent === undefined) return undefined;
  return tabOrigin.get(tab.id) ?? tab.parent;
}

/**
 * Keep a Back button in the current nested surface's toolbar.
 *
 * Owned by the shell rather than by each of the ten nested views: it is shell
 * navigation, the views do not own it, and ten copies is ten chances for the
 * label, icon and placement to drift.
 *
 * The views do own their toolbars, though, and rebuild them via innerHTML on
 * model-state changes and user actions as well as on activation — which threw a
 * one-shot injection away. So the shell re-asserts the button whenever the panel
 * subtree changes, and stops watching as soon as the user leaves.
 */
function syncBackButton(tab: TabDef): void {
  backButtonObserver?.disconnect();
  backButtonObserver = null;

  const panel = document.getElementById(`tab-${tab.id}`);
  if (!panel) return;

  const target = backTargetFor(tab);
  if (target === undefined) {
    panel.querySelector('.toolbar-back')?.remove();
    return;
  }

  const label = `Back to ${TABS[TAB_INDEX.get(target)!].label}`;
  ensureBackButton(panel, target, label);

  backButtonObserver = new MutationObserver(() => {
    // Re-inject only when it is actually gone. The insertion itself mutates the
    // subtree and re-enters this callback, so this check is what terminates it.
    if (!panel.querySelector('.toolbar-back')) ensureBackButton(panel, target, label);
  });
  backButtonObserver.observe(panel, { childList: true, subtree: true });
}

/** Insert or relabel the Back button in a panel's toolbar. */
function ensureBackButton(panel: HTMLElement, target: TabId, label: string): void {
  const toolbar = panel.firstElementChild;
  if (!toolbar?.classList.contains('toolbar')) return;

  const existing = toolbar.querySelector<HTMLButtonElement>('.toolbar-back');
  if (existing) {
    // Reuse the node so re-entering cannot stack duplicates, and relabel it in
    // case this visit arrived from a different origin.
    existing.setAttribute('aria-label', label);
    existing.title = label;
    existing.dataset.backTarget = target;
    return;
  }

  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'shell-icon-btn toolbar-back';
  button.setAttribute('aria-label', label);
  button.title = label;
  button.dataset.backTarget = target;
  button.innerHTML = icon(ICONS.back);
  button.addEventListener('click', () => {
    // Prefer the browser's own history. It records where the user actually came
    // from — better than any parent we could declare — and it keeps this button
    // and the browser's Back in agreement: pushing a *new* entry here would mean
    // the browser's Back immediately undid the toolbar's Back.
    if (historyDepth > 0) {
      window.history.back();
      return;
    }
    // Nothing of ours behind this entry (a deep link straight into a nested
    // surface), so `history.back()` would leave the site. Fall back to the
    // declared parent, read at click time: this node gets relabelled in place,
    // so a captured value could send a reused button to a stale surface.
    const dest = button.dataset.backTarget;
    if (dest) navigateToTab(dest as TabId);
  });
  toolbar.insertBefore(button, toolbar.firstChild);
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

  const activeTabDef = TABS[index];
  const activeId = activeTabDef.id;

  // Remember where a drilled-into surface was opened from, so Back returns the
  // user to the surface they actually came from rather than a guess. Only set on
  // a real change, so re-selecting the current tab cannot make it its own origin.
  if (previousTab !== index && activeTabDef.parent !== undefined) {
    tabOrigin.set(activeId, TABS[previousTab].id);
  }

  // A nested surface keeps its parent's nav entry lit. Highlighting nothing left
  // the sidebar pointing at no current location at all.
  const highlightId = navHighlightFor(activeId);
  document.querySelectorAll<HTMLElement>('.tab-item[data-tab]').forEach((item) => {
    const isCurrent = item.dataset.tab === highlightId;
    item.classList.toggle('active', isCurrent);
    // The highlight was purely visual — a screen reader had no way to tell which
    // surface was open. aria-current is the right primitive here (these are
    // navigation buttons, not an ARIA tablist).
    if (isCurrent) {
      item.setAttribute('aria-current', activeId === highlightId ? 'page' : 'true');
    } else {
      item.removeAttribute('aria-current');
    }
  });

  if (previousTab !== index) {
    try {
      tabLifecycles[activeId]?.onActivate?.();
    } catch (err) {
      appLogger.warning(`[App] Panel ${activeId} onActivate error:`, err);
    }
  }

  // After onActivate, never before: several views rebuild their whole subtree
  // there (Segmentation, Diarization and Benchmarks all re-render on activate),
  // which silently discarded a button injected earlier in this same function.
  syncBackButton(activeTabDef);
}

async function refreshConversationList(): Promise<void> {
  const list = document.getElementById('consumer-conversation-list');
  if (!list) return;
  let conversations: StoredConversation[];
  let current: StoredConversation | null;
  try {
    [conversations, current] = await Promise.all([
      ConversationsStore.getConversations(),
      ConversationsStore.getCurrent(),
    ]);
  } catch (error) {
    list.replaceChildren();
    const unavailable = document.createElement('p');
    unavailable.className = 'consumer-recents__empty';
    unavailable.textContent = 'Saved chats unavailable';
    list.appendChild(unavailable);
    appLogger.warning('[App] Could not load saved chats:', error);
    return;
  }
  list.replaceChildren();
  const currentId = current?.id ?? null;
  if (conversations.length === 0) {
    const empty = document.createElement('p');
    empty.className = 'consumer-recents__empty';
    empty.textContent = 'No saved chats yet';
    list.appendChild(empty);
    return;
  }

  for (const conversation of conversations) {
    list.appendChild(buildConversationRow(conversation, conversation.id === currentId));
  }
}

function buildConversationRow(
  conversation: StoredConversation,
  isCurrent: boolean,
): HTMLElement {
  const entry = document.createElement('div');
  entry.className = `consumer-recent-entry${isCurrent ? ' active' : ''}`;

  const openButton = document.createElement('button');
  openButton.type = 'button';
  openButton.className = 'consumer-recent-row';
  openButton.setAttribute('aria-label', `Open saved chat: ${conversation.title}`);

  const title = document.createElement('span');
  title.className = 'consumer-recent-row__title';
  title.textContent = conversation.title;
  const meta = document.createElement('span');
  meta.className = 'consumer-recent-row__meta';
  const messageLabel = conversation.messages.length === 1 ? 'message' : 'messages';
  meta.textContent = `${conversation.messages.length} ${messageLabel} · ${formatSavedDate(conversation.updatedAt)}`;
  openButton.append(title, meta);
  openButton.addEventListener('click', () => {
    window.dispatchEvent(new CustomEvent('runanywhere:load-chat', {
      detail: { conversationId: conversation.id },
    }));
    navigateToTab('chat');
    closeDrawer();
  });

  const deleteButton = document.createElement('button');
  deleteButton.type = 'button';
  deleteButton.className = 'consumer-recent-delete';
  deleteButton.setAttribute('aria-label', `Delete saved chat: ${conversation.title}`);
  deleteButton.textContent = '\u00d7';
  deleteButton.addEventListener('click', () => {
    void ConversationsStore.getCurrent().then((current) => {
      window.dispatchEvent(new CustomEvent('runanywhere:delete-chat', {
        detail: { conversationId: conversation.id },
      }));
      if (current?.id === conversation.id) navigateToTab('chat');
    }).catch((error) => {
      appLogger.warning('[App] Could not delete saved chat:', error);
    });
  });

  entry.append(openButton, deleteButton);
  return entry;
}

function formatSavedDate(timestamp: number): string {
  const saved = new Date(timestamp);
  const today = new Date();
  if (saved.toDateString() === today.toDateString()) {
    return saved.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  }
  return saved.toLocaleDateString();
}

function initAdvancedHub(el: HTMLElement): TabLifecycle {
  // One glyph per row, all distinct (DESIGN_GUIDELINE.md §7). Three pairs used to
  // collide here — waveform for both Transcribe and Voice Activity, mic for both
  // Talk and Diarization, image for both Segmentation and (elsewhere) photo
  // attachments — so adjacent rows in the same list were visually identical and
  // the icon column carried no information at all.
  //
  // Every subtitle says what the reader gets, not which model does it. They used to
  // read like release notes — "Semantic image segmentation (SegFormer)", "Full STT +
  // LLM + TTS voice assistant" — and a parenthesised codename or a stack acronym is
  // the one thing a reader deciding whether to tap cannot use. The model names live
  // on the screens themselves, where a curious reader has already opted in. iOS
  // `ConsumerAdvancedHubView` and Android `MoreScreen` carry the same rewrite.
  const hubItems: Array<{
    tab: TabId;
    icon: IconName;
    title: string;
    subtitle: string;
  }> = [
    // Talk is deliberately absent: it is a primary nav row and the composer's mic
    // button, so a third entrance filed under "Advanced" — where a reader looks for
    // diagnostics — only said it was harder to reach than it is.
    { tab: 'segmentation', icon: 'segments', title: 'Segmentation', subtitle: 'Split a photo into labelled regions' },
    { tab: 'documents', icon: 'file', title: 'Documents', subtitle: 'Ask questions about your own files' },
    { tab: 'transcribe', icon: 'waveform', title: 'Transcribe', subtitle: 'Turn a recording into text' },
    { tab: 'speak', icon: 'speaker', title: 'Read Aloud', subtitle: 'Hear any text spoken on this device' },
    { tab: 'vad', icon: 'pulse', title: 'Voice Activity', subtitle: 'See when speech starts and stops' },
    { tab: 'diarization', icon: 'speakers', title: 'Diarization', subtitle: 'See who spoke when in a recording' },
    { tab: 'storage', icon: 'storage', title: 'Downloads', subtitle: 'Models on this device, and space used' },
    { tab: 'benchmarks', icon: 'gauge', title: 'Benchmarks', subtitle: 'Measure local model performance' },
    { tab: 'solutions', icon: 'stack', title: 'Solutions', subtitle: 'Run saved multi-step workflows' },
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
        ${hubItems.slice(0, 3).map((item) => advancedRow(item)).join('')}
      </section>
      <section class="advanced-hub__section">
        <div class="consumer-section-title">Voice Utilities</div>
        ${hubItems.slice(3, 7).map((item) => advancedRow(item)).join('')}
      </section>
      <section class="advanced-hub__section">
        <div class="consumer-section-title">Management</div>
        ${hubItems.slice(7).map((item) => advancedRow(item)).join('')}
      </section>
    </div>
  `;

  el.querySelectorAll<HTMLButtonElement>('[data-advanced-target]').forEach((button) => {
    button.addEventListener('click', () => {
      const tab = button.dataset.advancedTarget as TabId | undefined;
      if (tab) navigateToTab(tab);
    });
  });
  return {};
}

function advancedRow(item: { tab: TabId; icon: IconName; title: string; subtitle: string }): string {
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

/**
 * The surface currently on screen, by id.
 *
 * `main.ts`'s readiness probe needs this: now that a URL can name any tab, the
 * probe can no longer assume the assistant is the panel that must be showing.
 */
export function getActiveTabId(): string {
  return TABS[activeTab].id;
}

/** True when the assistant is the routed surface — the only one with model UI. */
export function isChatRouteActive(): boolean {
  return TABS[activeTab].id === DEFAULT_TAB;
}
